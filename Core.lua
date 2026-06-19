local ADDON = ...
local DB

-- Midnight protects certain values (tooltip text, cooldown numbers) from addon code.
-- issecretvalue() safely checks this without crashing, unlike a direct comparison.
local issecretvalue = issecretvalue or function() return false end
local function IsSecret(v)
    return issecretvalue(v)
end

local SPELL_HERB = 1223014 -- Overload Infused Herb
local SPELL_MINE = 1225392 -- Overload Infused Deposit

-- Mounting/dismounting briefly reports a tiny fake cooldown on unrelated spells.
-- Real Overload cooldowns run ~12 hours, so anything under a minute is noise — ignore it.
local MIN_REAL_COOLDOWN = 60 -- seconds

local ICON_SIZE  = 64
local FONT_BODY  = "Fonts\\FRIZQT__.TTF"
local FONT_TITLE = "Fonts\\MORPHEUS.TTF"

local frames = {}
local reminderFrame
local herbKnown, mineKnown
local lastTooltipName = nil
local tooltipElapsed  = 0

-- =========================
-- DB
-- =========================
local function EnsureDB()
    FOHM_DB        = FOHM_DB or {}
    FOHM_DB.frames = FOHM_DB.frames or {}
    FOHM_DB.opts   = FOHM_DB.opts or { locked = false, reminder = true }
    DB = FOHM_DB
end

local function SavePoint(frame, key)
    local p, _, rp, x, y = frame:GetPoint(1)
    DB.frames[key] = DB.frames[key] or {}
    local t = DB.frames[key]
    t.p, t.rp, t.x, t.y = p, rp, x, y
end

local function RestorePoint(frame, key, defaultX, defaultY)
    local t = DB.frames[key]
    frame:ClearAllPoints()
    if t and t.p and t.rp and t.x and t.y then
        frame:SetPoint(t.p, UIParent, t.rp, t.x, t.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
    end
end

-- =========================
-- Spell helpers
-- =========================
local function KnowsSpell(spellID)
    if C_Spell and C_Spell.IsSpellKnown then
        local ok, known = pcall(C_Spell.IsSpellKnown, spellID)
        if ok then return known and true or false end
    end
    local ok, known = pcall(IsSpellKnown, spellID)
    return ok and known and true or false
end

local function RefreshKnown()
    local hk = KnowsSpell(SPELL_HERB)
    local mk = KnowsSpell(SPELL_MINE)
    if herbKnown == nil then herbKnown = hk elseif hk then herbKnown = true end
    if mineKnown == nil then mineKnown = mk elseif mk then mineKnown = true end
end

local function GetSpellIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info and info.iconID then return info.iconID end
    end
    local ok, tex = pcall(GetSpellTexture, spellID)
    return ok and tex or 134400
end

local function GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name and name ~= "" then return name end
    end
    local ok, name = pcall(GetSpellInfo, spellID)
    if ok and name and name ~= "" then return name end
    return nil
end

-- Reads the real cooldown using the same safe pattern as TeleportMenu:
-- check IsSecret() before touching the value, never compare a secret directly.
local function GetCooldownInfo(spellID)
    local ok, cooldown = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(cooldown) ~= "table" then
        return 0, 0
    end
    local start    = cooldown.startTime
    local duration = cooldown.duration
    if IsSecret(start) or IsSecret(duration) then
        -- Can't read it; assume ready rather than crash. Cooldown swipe just won't show.
        return 0, 0
    end
    return start or 0, duration or 0
end

local function IsReady(spellID)
    local start, duration = GetCooldownInfo(spellID)
    if duration <= 0 or start <= 0 then return true end
    return duration < MIN_REAL_COOLDOWN
end

local function ApplyLockState()
    if InCombatLockdown() then return end
    local locked = DB and DB.opts and DB.opts.locked
    if frames.herb then frames.herb:EnableMouse(not locked) end
    if frames.mine then frames.mine:EnableMouse(not locked) end
    if reminderFrame and reminderFrame.handle then
        reminderFrame.handle:EnableMouse(not locked)
        reminderFrame.handle:SetShown(not locked)
    end
end

-- =========================
-- Trackers
-- =========================
local function CreateTrackerFrame(key, spellID, defaultX, defaultY, smallLabel)
    -- Confirmed working pattern from TeleportMenu: SecureActionButtonTemplate with
    -- type=spell and the numeric spell ID set directly as the attribute value.
    local f = CreateFrame("Button", "FOHM_Tracker_" .. key, UIParent, "SecureActionButtonTemplate,BackdropTemplate")
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetAttribute("type",  "spell")
    f:SetAttribute("spell", spellID)
    f:RegisterForClicks("AnyDown", "AnyUp")
    f:RegisterForDrag("RightButton")

    -- Icon
    f.icon = f:CreateTexture(nil, "BACKGROUND")
    f.icon:SetAllPoints()
    f.icon:SetTexture(GetSpellIcon(spellID))

    -- Cooldown swipe, same template Blizzard action bars use
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    f.cooldown:SetDrawEdge(true)

    -- Glow border
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.border:SetBlendMode("ADD")
    f.border:SetAlpha(0.9)
    f.border:SetSize(ICON_SIZE * 1.7, ICON_SIZE * 1.7)
    f.border:SetPoint("CENTER")

    -- "Ready" label above
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(FONT_TITLE, 16, "OUTLINE")
    f.text:SetPoint("BOTTOM", f, "TOP", 0, 4)
    f.text:SetText("Ready")
    f.text:SetTextColor(0.2, 1, 0.2)

    -- Small label below
    f.small = f:CreateFontString(nil, "OVERLAY")
    f.small:SetFont(FONT_BODY, 11, "OUTLINE")
    f.small:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.small:SetText(smallLabel or "")
    f.small:SetTextColor(0.85, 0.85, 0.85)

    f.spellID = spellID
    f.key     = key

    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePoint(self, key)
    end)

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local name = GetSpellName(self.spellID) or ("SpellID " .. self.spellID)
        GameTooltip:AddLine(name)
        GameTooltip:AddLine("Click to cast", 0.2, 1, 0.2)
        GameTooltip:AddLine("Right-click drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    f:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)

    f:SetAlpha(0)
    f:EnableMouse(false)
    RestorePoint(f, key, defaultX, defaultY)
    return f
end

local function UpdateTrackerVisuals(f, spellID, known)
    if not known then
        f:SetAlpha(0)
        if not InCombatLockdown() then f:EnableMouse(false) end
        return
    end

    -- Never call Hide()/Show() on a secure frame — it breaks the click handler.
    -- Alpha + EnableMouse simulates visibility without touching secure state.
    f:SetAlpha(1)
    if not InCombatLockdown() then f:EnableMouse(true) end

    local start, duration = GetCooldownInfo(spellID)
    -- Ignore tiny transient cooldown blips (e.g. mounting briefly reports ~1-2s
    -- on unrelated spells). Real Overload cooldowns run minutes, not seconds.
    local ready = duration <= 0 or start <= 0 or duration < MIN_REAL_COOLDOWN

    if ready then
        f.cooldown:Clear()
        f.icon:SetDesaturated(false)
        f.border:SetAlpha(0.9)
        f.text:Show()
    else
        f.cooldown:SetCooldown(start, duration)
        f.icon:SetDesaturated(true)
        f.border:SetAlpha(0)
        f.text:Hide()
    end
end

local function UpdateTrackers()
    if frames.herb then UpdateTrackerVisuals(frames.herb, SPELL_HERB, herbKnown) end
    if frames.mine then UpdateTrackerVisuals(frames.mine, SPELL_MINE, mineKnown) end
end

-- =========================
-- Reminder overlay
-- =========================
local affixMap = {
    Lightfused       = "Lightfused: Collect orbs on the ground.",
    Voidbound        = "Voidbound: Portal spawns.",
    Wild             = "Wild: Elite mob. Kill for +15% Perception (5m).",
    Primal           = "Primal: Do not move while channeling.",
    Lichtdurchflutet = "Lightfused: Collect orbs on the ground.",
    Leerengebunden   = "Voidbound: Portal spawns.",
    Wildheit         = "Wild: Elite mob. Kill for +15% Perception (5m).",
    Urzeitlich       = "Primal: Do not move while channeling.",
}

local herbNames = {
    ["Tranquility Bloom"] = true, ["Argentleaf"] = true,
    ["Mana Lily"]         = true, ["Sanguithorn"] = true,
    ["Blüte der Ruhe"]    = true, ["Silberblatt"] = true,
    ["Manalilie"]         = true, ["Blutdorn"]    = true,
}

local oreNames = {
    ["Refulgent Copper"]   = true, ["Brilliant Silver"] = true, ["Umbral Tin"] = true,
    ["Strahlendes Kupfer"] = true, ["Brillantsilber"]   = true, ["Umbralzinn"] = true,
}

local function ParseNodeName(name)
    if not name then return end
    local foundAffix, reminderText
    for affix, text in pairs(affixMap) do
        if string.find(name, affix, 1, true) then
            foundAffix, reminderText = affix, text; break
        end
    end
    if not foundAffix then return end
    local isHerb, isOre
    for herb in pairs(herbNames) do
        if string.find(name, herb, 1, true) then isHerb = true; break end
    end
    if not isHerb then
        for ore in pairs(oreNames) do
            if string.find(name, ore, 1, true) then isOre = true; break end
        end
    end
    if not isHerb and not isOre then return end
    if isHerb and (not herbKnown or not IsReady(SPELL_HERB)) then return end
    if isOre  and (not mineKnown or not IsReady(SPELL_MINE)) then return end
    return foundAffix, reminderText, isHerb and "Herb" or "Ore"
end

local function CreateReminderOverlay()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(340, 70)
    f:SetClampedToScreen(true)
    f:EnableMouse(false)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.65)

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(FONT_TITLE, 14, "OUTLINE")
    f.title:SetPoint("TOPLEFT", 26, -8)
    f.title:SetTextColor(1, 0.82, 0)

    f.body = f:CreateFontString(nil, "OVERLAY")
    f.body:SetFont(FONT_BODY, 12, "OUTLINE")
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.body:SetPoint("RIGHT", -10, 0)
    f.body:SetJustifyH("LEFT")
    f.body:SetTextColor(0.95, 0.95, 0.95)

    local handle = CreateFrame("Button", nil, f, "BackdropTemplate")
    handle:SetSize(14, 14)
    handle:SetPoint("TOPLEFT", 6, -6)
    handle:SetClampedToScreen(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("RightButton")

    handle.bg = handle:CreateTexture(nil, "BACKGROUND")
    handle.bg:SetAllPoints()
    handle.bg:SetColorTexture(1, 1, 1, 0.35)

    handle:SetScript("OnDragStart", function()
        f:SetMovable(true); f:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing(); f:SetMovable(false)
        SavePoint(f, "reminder")
    end)

    f.handle = handle
    f:Hide()
    RestorePoint(f, "reminder", 0, 120)
    return f
end

local function UpdateTooltipReminder()
    if not (DB and DB.opts and DB.opts.reminder) then
        if reminderFrame and reminderFrame:IsShown() then reminderFrame:Hide() end
        return
    end
    if not reminderFrame then return end
    if UnitAffectingCombat("player") then
        if reminderFrame:IsShown() then reminderFrame:Hide() end
        lastTooltipName = nil
        return
    end
    if not GameTooltip:IsShown() then
        if reminderFrame:IsShown() then reminderFrame:Hide() end
        lastTooltipName = nil
        return
    end
    local owner = GameTooltip:GetOwner()
    if owner and reminderFrame.handle and owner == reminderFrame.handle then return end

    local left1 = _G.GameTooltipTextLeft1
    if not left1 then return end
    local okName, name = pcall(left1.GetText, left1)
    if not okName or not name or name == "" then return end

    -- name may be a "secret" protected string in Midnight (world object tooltips).
    -- Direct comparison (name == lastTooltipName) would throw a taint error, so skip
    -- the dedup optimization entirely when the value is secret and just re-parse.
    if not IsSecret(name) then
        if name == lastTooltipName then return end
        lastTooltipName = name
    end

    local ok, affix, text, kind = pcall(ParseNodeName, name)
    if not ok or not affix then
        if reminderFrame:IsShown() then reminderFrame:Hide() end
        return
    end
    reminderFrame.title:SetText(kind .. " Overload Opportunity")
    reminderFrame.body:SetText(IsSecret(name) and text or (name .. "\n" .. text))
    reminderFrame:Show()
end

local tickerFrame   = CreateFrame("Frame")
local tickerEnabled = false

local function EnableTooltipTicker()
    if tickerEnabled then return end
    tickerEnabled = true
    tickerFrame:SetScript("OnUpdate", function(_, elapsed)
        tooltipElapsed = tooltipElapsed + elapsed
        if tooltipElapsed < 0.12 then return end
        tooltipElapsed = 0
        UpdateTooltipReminder()
    end)
end

-- =========================
-- Events
-- =========================
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")     -- fires when a spell's cooldown actually changes
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")  -- fires the instant a cast completes, for immediate feedback
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        EnsureDB()
        return
    end

    if event == "PLAYER_LOGIN" then
        EnsureDB()
        frames.herb   = CreateTrackerFrame("herb", SPELL_HERB, -40, 0, "Herb")
        frames.mine   = CreateTrackerFrame("mine", SPELL_MINE,  40, 0, "Ore")
        reminderFrame = CreateReminderOverlay()
        if DB.opts.reminder then EnableTooltipTicker() end
        RefreshKnown()
        UpdateTrackers()
        ApplyLockState()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then ApplyLockState() end
    if event == "SPELLS_CHANGED" then RefreshKnown() end

    if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 ~= "player" then
        return -- ignore other units' casts
    end

    UpdateTrackers()
end)

-- =========================
-- Slash commands
-- =========================
SLASH_FOHM1 = "/fohm"
SlashCmdList.FOHM = function(msg)
    msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""
    if msg == "lock" then
        DB.opts.locked = true
        ApplyLockState()
        print("FOHM: locked")
    elseif msg == "unlock" then
        DB.opts.locked = false
        ApplyLockState()
        print("FOHM: unlocked — right-click drag to move")
    elseif msg == "reminder on" then
        DB.opts.reminder = true
        EnableTooltipTicker()
        print("FOHM: reminder ON")
    elseif msg == "reminder off" then
        DB.opts.reminder = false
        if reminderFrame and reminderFrame:IsShown() then reminderFrame:Hide() end
        print("FOHM: reminder OFF")
    elseif msg == "debug" then
        print("=== FOHM DEBUG ===")
        print("herbKnown:", tostring(herbKnown))
        print("mineKnown:", tostring(mineKnown))
        print("Herb IsReady:", tostring(IsReady(SPELL_HERB)))
        print("Mine IsReady:", tostring(IsReady(SPELL_MINE)))
        if frames.herb then
            print("Herb alpha:", frames.herb:GetAlpha(), "mouse:", tostring(frames.herb:IsMouseEnabled()))
        end
        if frames.mine then
            print("Mine alpha:", frames.mine:GetAlpha(), "mouse:", tostring(frames.mine:IsMouseEnabled()))
        end
        print("Herb name:", tostring(GetSpellName(SPELL_HERB)))
        print("Mine name:", tostring(GetSpellName(SPELL_MINE)))
    else
        print("FOHM commands:")
        print("  /fohm lock / unlock")
        print("  /fohm reminder on / off")
        print("  /fohm debug")
    end
end
