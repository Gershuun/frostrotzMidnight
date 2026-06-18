local ADDON = ...
local DB

local SPELL_HERB = 1223014 -- Overload Infused Herb
local SPELL_MINE = 1225392 -- Overload Infused Deposit

local ICON_SIZE   = 64
local READY_TEXT  = "Ready"
local FONT_BODY   = "Fonts\\FRIZQT__.TTF"
local FONT_TITLE  = "Fonts\\MORPHEUS.TTF"

local frames = {}
local reminderFrame

local herbKnown, mineKnown

local lastReady = {
    [SPELL_HERB] = false,
    [SPELL_MINE] = false,
}

local lastTooltipName = nil
local tooltipElapsed  = 0

-- =========================
-- DB
-- =========================
local function EnsureDB()
    FOHM_DB        = FOHM_DB or {}
    FOHM_DB.frames = FOHM_DB.frames or {}
    FOHM_DB.opts   = FOHM_DB.opts   or { locked = false, reminder = true }
    DB = FOHM_DB
end

local function SavePoint(frame, key)
    local p, _, rp, x, y = frame:GetPoint(1)
    DB.frames[key]     = DB.frames[key] or {}
    local t            = DB.frames[key]
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
    -- upgrade-only: never downgrade to avoid skyriding/secure weirdness
    if herbKnown == nil then herbKnown = hk else if hk then herbKnown = true end end
    if mineKnown == nil then mineKnown = mk else if mk then mineKnown = true end end
end

local function GetSpellIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info and info.iconID then return info.iconID end
    end
    local ok, tex = pcall(GetSpellTexture, spellID)
    return ok and tex or 134400
end

local function GetCooldownTable(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, cd = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(cd) ~= "table" then return nil end
    return cd
end

local function IsReady(spellID)
    local cd = GetCooldownTable(spellID)
    if not cd then return lastReady[spellID] or false end

    local start    = cd.startTime or 0
    local duration = cd.duration  or 0
    local ready    = (start == 0) or (duration == 0)
    lastReady[spellID] = ready
    return ready
end

local function ApplyLockState()
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
    local f = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetMovable(true)
    f:SetClampedToScreen(true)

    -- Gathering spells can't be cast in combat, so a plain OnClick is fine.
    -- CastSpellByID is allowed from any hardware mouse event without taint.
    f:RegisterForClicks("LeftButtonUp")
    f:RegisterForDrag("RightButton")

    f:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            CastSpellByID(self.spellID)
        end
    end)

    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePoint(self, key)
    end)

    -- Icon
    f.icon = f:CreateTexture(nil, "BACKGROUND")
    f.icon:SetAllPoints()
    f.icon:SetTexture(GetSpellIcon(spellID))

    -- "Ready" label above icon
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(FONT_TITLE, 16, "OUTLINE")
    f.text:SetPoint("BOTTOM", f, "TOP", 0, 4)
    f.text:SetText(READY_TEXT)
    f.text:SetTextColor(0.2, 1, 0.2)

    -- Small type label below icon
    f.small = f:CreateFontString(nil, "OVERLAY")
    f.small:SetFont(FONT_BODY, 11, "OUTLINE")
    f.small:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.small:SetText(smallLabel or "")
    f.small:SetTextColor(0.85, 0.85, 0.85)

    -- Glow border
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.border:SetBlendMode("ADD")
    f.border:SetAlpha(0.9)
    f.border:SetSize(ICON_SIZE * 1.7, ICON_SIZE * 1.7)
    f.border:SetPoint("CENTER")

    f.spellID = spellID
    f.key     = key

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(self.spellID))
                  or ("SpellID " .. self.spellID)
        GameTooltip:AddLine(name)
        GameTooltip:AddLine("Click to cast", 0.2, 1, 0.2)
        GameTooltip:AddLine("Right-click drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    f:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)

    RestorePoint(f, key, defaultX, defaultY)
    return f
end

local function UpdateTrackers()
    local herbF = frames.herb
    local mineF = frames.mine
    if not herbF or not mineF then return end

    herbF:SetShown(herbKnown and IsReady(SPELL_HERB) or false)
    mineF:SetShown(mineKnown and IsReady(SPELL_MINE) or false)
end

-- =========================
-- Reminder overlay
-- =========================
local affixMap = {
    Lightfused       = "Lightfused: Collect orbs on the ground.",
    Voidbound        = "Voidbound: Portal spawns.",
    Wild             = "Wild: Elite mob. Kill for +15% Perception (5m).",
    Primal           = "Primal: Do not move while channeling.",
    -- German
    Lichtdurchflutet = "Lightfused: Collect orbs on the ground.",
    Leerengebunden   = "Voidbound: Portal spawns.",
    Wildheit         = "Wild: Elite mob. Kill for +15% Perception (5m).",
    Urzeitlich       = "Primal: Do not move while channeling.",
}

local herbNames = {
    ["Tranquility Bloom"] = true,
    ["Argentleaf"]        = true,
    ["Mana Lily"]         = true,
    ["Sanguithorn"]       = true,
    -- German
    ["Blüte der Ruhe"]    = true,
    ["Silberblatt"]       = true,
    ["Manalilie"]         = true,
    ["Blutdorn"]          = true,
}

local oreNames = {
    ["Refulgent Copper"]   = true,
    ["Brilliant Silver"]   = true,
    ["Umbral Tin"]         = true,
    -- German
    ["Strahlendes Kupfer"] = true,
    ["Brillantsilber"]     = true,
    ["Umbralzinn"]         = true,
}

local function ParseNodeName(name)
    if not name then return end

    local foundAffix, reminderText
    for affix, text in pairs(affixMap) do
        if string.find(name, affix, 1, true) then
            foundAffix   = affix
            reminderText = text
            break
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
    f:EnableMouse(false)  -- click-through: do not break world tooltips

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

    -- Drag handle (small grip in top-left corner)
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
        f:SetMovable(true)
        f:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        f:SetMovable(false)
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

    -- Don't react while the user is dragging the reminder handle
    local owner = GameTooltip:GetOwner()
    if owner and reminderFrame.handle and owner == reminderFrame.handle then return end

    local left1 = _G.GameTooltipTextLeft1
    if not left1 then return end

    local okName, name = pcall(left1.GetText, left1)
    if not okName or not name or name == "" then return end
    if name == lastTooltipName then return end
    lastTooltipName = name

    local ok, affix, text, kind = pcall(ParseNodeName, name)
    if not ok or not affix then
        if reminderFrame:IsShown() then reminderFrame:Hide() end
        return
    end

    reminderFrame.title:SetText(kind .. " Overload Opportunity")
    reminderFrame.body:SetText(name .. "\n" .. text)
    reminderFrame:Show()
end

-- Tooltip polling ticker (low frequency, only runs after login)
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
ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ev:RegisterEvent("SPELLS_CHANGED")

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

    if event == "SPELLS_CHANGED" then
        RefreshKnown()
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
    else
        print("FOHM commands:")
        print("  /fohm lock           — lock frames in place")
        print("  /fohm unlock         — unlock frames (right-click drag to move)")
        print("  /fohm reminder on    — enable tooltip reminder overlay")
        print("  /fohm reminder off   — disable tooltip reminder overlay")
    end
end
