# FrostrotzOverloadHerbMining

A lightweight World of Warcraft: Midnight addon that tracks **Overload Infused Herb** and **Overload Infused Deposit** cooldown readiness and alerts you when an affixed node you're hovering can be overloaded.

---

## Features

- **Cooldown icons** — Floating icons appear on screen when each Overload spell is off cooldown. They hide automatically when the spell is on cooldown.
- **Clickable icons** — Left-click the icon to cast the spell directly (works like an action button; respects in-combat lockdown).
- **Tooltip reminder** — While hovering an affixed herb or ore node with a ready Overload spell, an overlay shows the affix name and what to do.
- **Draggable frames** — Right-click-drag any icon or the reminder overlay to reposition it. Position is saved across sessions.
- **Lock/unlock** — `/fohm lock` freezes all frames so you can't accidentally move them.
- **English & German** — Herb, ore, and affix names are recognized in both locales.

---

## Installation

1. Download and unzip the folder.
2. Place the `FrostrotzOverloadHerbMining` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Launch the game and enable the addon in the **AddOns** menu on the character select screen.

---

## Slash Commands

| Command | Description |
|---|---|
| `/fohm lock` | Lock all frames in place |
| `/fohm unlock` | Unlock frames (right-click drag to reposition) |
| `/fohm reminder on` | Enable the tooltip node reminder overlay |
| `/fohm reminder off` | Disable the tooltip node reminder overlay |

---

## Supported Affixes

| Affix | What to do |
|---|---|
| Lightfused | Collect orbs on the ground |
| Voidbound | Portal spawns |
| Wild | Elite mob — kill for +15% Perception (5 min) |
| Primal | Do not move while channeling |

---

## Changelog

### v1.1.0
- **Fixed:** Removed missing `Media/Expressway.ttf` font reference that caused `FontString:SetFont()` errors and Lua taint on login. The addon now uses built-in WoW fonts only (`MORPHEUS.TTF` for headers, `FRIZQT__.TTF` for body text) — no external files needed.
- **New:** Spell icons are now clickable buttons that cast the corresponding Overload spell (uses `SecureActionButtonTemplate` — works in and out of combat).
- **Improved:** Tooltip text updated to show "Click to cast" hint.
- **Fixed:** Duplicate `Wild` key in the German affix map (was overwriting the English entry). Renamed to `Wildheit`.
- **Cleanup:** Removed dead `FONT_PATH` constant and `SafeSetFont` helper (no longer needed). Simplified `IsReady`, `UpdateTrackers`, slash command parser, and `OnEvent` handler.

### v1.0.3
- Initial public release.

---

## License

Personal use. No redistribution without permission.
