-- DragonUIRageFixes.lua
-- A grab-bag of small standalone fixes for things about DragonUI (or the
-- underlying Blizzard 3.3.5a UI it skins) that got annoying enough to fix.
-- Deliberately kept as its OWN addon rather than edits inside DragonUI's
-- files: DragonUI is actively updated, and a direct edit to its source
-- gets silently blown away the next time it's updated. This addon instead
-- overrides/hooks global functions from the outside, the same way any
-- other addon layers on top of Blizzard's UI.
--
-- Each fix is self-contained below. See CHANGELOG.md for the running list.

local ADDON_NAME = ...

DragonUIRageFixesDB = DragonUIRageFixesDB or {}

--------------------------------------------------------------------------
-- Option registry
--
-- Every toggleable fix gets one entry here. The options UI (further down)
-- is built entirely from this table, so adding a new fix just means
-- adding an entry here plus its logic -- no separate UI wiring needed.
--------------------------------------------------------------------------

local OPTIONS = {
    {
        key = "hidePartyAuraTooltip",
        label = "Hide party frame hover tooltip",
        desc = "Suppresses the buff/debuff tooltip that pops up when hovering a party frame -- useful when mouseover heal/buff macros keep getting visually stepped on by it mid-combat.",
        default = false,
    },
    {
        key = "nameplateRoleIcons",
        label = "Role icons on nameplates",
        desc = "Shows a small tank / healer / support icon above group members' nameplates. Sits alongside TurboPlates rather than replacing it -- it draws its own icon on the nameplate frame and never touches TurboPlates' own healer mark.",
        default = false,
    },
}

local function EnsureDefaults()
    for _, option in ipairs(OPTIONS) do
        if DragonUIRageFixesDB[option.key] == nil then
            DragonUIRageFixesDB[option.key] = option.default
        end
    end
    -- Not a fix toggle of its own: picks custom Artwork\ files over the
    -- stock LFG role atlas. Off until the custom .tga files are installed,
    -- since a missing texture renders as an empty square.
    if DragonUIRageFixesDB.useCustomRoleArt == nil then
        DragonUIRageFixesDB.useCustomRoleArt = false
    end
    -- Icon size / nudge, tunable in-game via /duf rolesize and
    -- /duf roleoffset rather than being baked in.
    if DragonUIRageFixesDB.roleIconSize == nil then
        DragonUIRageFixesDB.roleIconSize = 13
    end
    if DragonUIRageFixesDB.roleIconOffsetX == nil then
        DragonUIRageFixesDB.roleIconOffsetX = 3
    end
    if DragonUIRageFixesDB.roleIconOffsetY == nil then
        DragonUIRageFixesDB.roleIconOffsetY = 0
    end
end

--------------------------------------------------------------------------
-- Fix #1: party frame buff/debuff tooltip on hover
--
-- Hovering a party frame calls Blizzard's UnitFrame_OnEnter ->
-- UnitFrame_UpdateTooltip -> GameTooltip:SetUnit(unit), which draws a
-- buff/debuff icon row on the tooltip. That's disruptive when using
-- mouseover heal/buff macros mid-combat -- the tooltip pops up over
-- exactly what you're trying to click through.
--
-- This wraps UnitFrame_UpdateTooltip itself (not just UnitFrame_OnEnter)
-- since that's the one call that actually triggers GameTooltip:SetUnit --
-- a hooksecurefunc on UnitFrame_OnEnter can't prevent it, it only runs
-- after. Only PartyMemberFrame1-4 are affected; target/focus/raid frames
-- (and anything else that calls UnitFrame_UpdateTooltip) pass straight
-- through to Blizzard's original, untouched.
--------------------------------------------------------------------------

local Blizzard_UnitFrame_UpdateTooltip = UnitFrame_UpdateTooltip
UnitFrame_UpdateTooltip = function(self)
    if DragonUIRageFixesDB.hidePartyAuraTooltip and self and self.GetName then
        local name = self:GetName()
        if name and name:match("^PartyMemberFrame%d+$") then
            return
        end
    end
    Blizzard_UnitFrame_UpdateTooltip(self)
end

--------------------------------------------------------------------------
-- Fix #2: role icons on nameplates
--
-- Draws a small tank / healer / support icon above group members'
-- nameplates. Deliberately independent of TurboPlates: it attaches its
-- own texture to the nameplate frame returned by C_NamePlate and never
-- touches TurboPlates' private namespace or its healer mark, so the two
-- coexist (TurboPlates' healer icon anchors above the plate; this one
-- anchors to the left of it to avoid overlap).
--
-- ROLE SOURCES, and their honest limits:
--   * Group members -> UnitGroupRolesAssigned(unit), which on this server
--     returns (isTank, isHealer, isDamager) BOOLEANS rather than retail's
--     role string. Exact, instant, no inspect.
--   * Yourself -> your spec name via GetSpecialization(), which is the
--     only way to identify the "support" specs (Fleshweaver, Grovekeeper)
--     since the role API has no support concept at all.
--   * Anyone NOT in your group -> no icon. There is no API on this server
--     that exposes an arbitrary player's spec or role (see AutoMark's
--     header for the full list of dead ends). Detecting those would need
--     combat-log spell heuristics, which is a separate feature.
--------------------------------------------------------------------------

-- Fallback only; the live value comes from DragonUIRageFixesDB.roleIconSize.
local ROLE_ICON_SIZE = 13

-- Custom artwork, if present, else the stock LFG role atlas. Drop
-- role_tank.tga / role_healer.tga / role_support.tga into Artwork\ and
-- flip useCustomRoleArt to use them.
local ART_PATH = "Interface\\AddOns\\DragonUIRageFixes\\Artwork\\"
local CUSTOM_ART = {
    TANK    = ART_PATH .. "role_tank",
    HEALER  = ART_PATH .. "role_healer",
    SUPPORT = ART_PATH .. "role_support",
}

-- Stock fallback: Blizzard's LFG role atlas, so the feature is usable
-- before any custom art is installed.
local LFG_ROLE_TEXTURE = "Interface\\LFGFRAME\\UI-LFG-ICON-ROLES"
local LFG_ROLE_COORDS = {
    TANK    = { 0,     19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64,  20/64 },
    SUPPORT = { 20/64, 39/64, 22/64, 41/64 }, -- dps slot, stands in for support
}

-- Specs that play as full healers but aren't reported as HEALER by the
-- role API. Only resolvable for the local player (see header).
local SUPPORT_SPEC_NAMES = {
    ["Fleshweaver"] = true,
    ["Grovekeeper"] = true,
}

local function GetOwnSpecName()
    if type(_G.GetSpecialization) ~= "function" or type(_G.GetSpecializationInfo) ~= "function" then
        return nil
    end
    local ok, specID = pcall(_G.GetSpecialization)
    if not ok or type(specID) ~= "number" then return nil end
    local ok2, _id, name = pcall(_G.GetSpecializationInfo, specID)
    if not ok2 then return nil end
    return name
end

-- Returns "TANK" | "HEALER" | "SUPPORT" | nil for a unit token.
local function GetRoleForUnit(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end

    if UnitIsUnit(unit, "player") then
        local specName = GetOwnSpecName()
        if specName and SUPPORT_SPEC_NAMES[specName] then return "SUPPORT" end
    end

    -- Only group members are resolvable at all.
    local inGroup = UnitInParty(unit) or UnitInRaid(unit) or UnitIsUnit(unit, "player")
    if not inGroup then return nil end

    if type(_G.UnitGroupRolesAssigned) ~= "function" then return nil end
    local ok, isTank, isHealer = pcall(_G.UnitGroupRolesAssigned, unit)
    if not ok then return nil end

    -- Retail-style string form, kept in case a patch changes the signature.
    if type(isTank) == "string" then
        local r = isTank:upper()
        if r == "TANK" then return "TANK" end
        if r == "HEALER" then return "HEALER" end
        return nil
    end

    if isTank == true then return "TANK" end
    if isHealer == true then return "HEALER" end
    return nil
end

-- TurboPlates renders a nameplate in one of two modes, swapping between
-- them as health changes:
--   * full plate  (plate.myPlate)       -- health bar + name, when damaged
--   * lite plate  (plate.liteContainer) -- name only, at full health
-- Each gets its own texture (the same approach TurboPlates uses for its
-- healer mark) so the icon stays correctly parented and layered in both
-- modes instead of floating against the base nameplate frame.
local function EnsureIconOn(frame, key)
    if frame[key] then return frame[key] end
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetWidth(ROLE_ICON_SIZE)
    icon:SetHeight(ROLE_ICON_SIZE)
    icon:Hide()
    frame[key] = icon
    return icon
end

local function ApplyRoleTexture(icon, role)
    -- Size is applied per update, not at creation, so /duf rolesize takes
    -- effect on already-created icons.
    local size = DragonUIRageFixesDB.roleIconSize or ROLE_ICON_SIZE
    icon:SetWidth(size)
    icon:SetHeight(size)

    if DragonUIRageFixesDB.useCustomRoleArt then
        icon:SetTexture(CUSTOM_ART[role])
        icon:SetTexCoord(0, 1, 0, 1)
    else
        icon:SetTexture(LFG_ROLE_TEXTURE)
        icon:SetTexCoord(unpack(LFG_ROLE_COORDS[role]))
    end
end

local function RoleIconOffsets()
    return DragonUIRageFixesDB.roleIconOffsetX or 3, DragonUIRageFixesDB.roleIconOffsetY or 0
end

local function UpdateRoleIcon(plate, unit)
    if not plate then return end

    local enabled = DragonUIRageFixesDB.nameplateRoleIcons
    local role = enabled and GetRoleForUnit(unit) or nil

    local myPlate = plate.myPlate
    local lite = plate.liteContainer

    -- Full plate: sit just past the right end of the health bar, matching
    -- where the reference screenshot puts it. Anchoring outside the bar
    -- rather than on top of it keeps TurboPlates' own HP text readable.
    if myPlate then
        local icon = EnsureIconOn(myPlate, "duf_roleIcon")
        if role and myPlate:IsShown() then
            ApplyRoleTexture(icon, role)
            icon:ClearAllPoints()
            local anchor = myPlate.hp or myPlate
            local ox, oy = RoleIconOffsets()
            icon:SetPoint("LEFT", anchor, "RIGHT", ox, oy)
            icon:Show()
        else
            icon:Hide()
        end
    end

    -- Lite (name-only) plate: sit to the right of the name text, so the
    -- icon still appears for undamaged targets.
    if lite then
        local icon = EnsureIconOn(lite, "duf_roleIcon")
        if role and lite:IsShown() then
            ApplyRoleTexture(icon, role)
            icon:ClearAllPoints()
            -- TurboPlates stores liteNameText on the container in one code
            -- path and on the nameplate itself in another, so check both.
            local anchor = lite.liteNameText or plate.liteNameText or lite
            local ox, oy = RoleIconOffsets()
            icon:SetPoint("LEFT", anchor, "RIGHT", ox, oy)
            icon:Show()
        else
            icon:Hide()
        end
    end

    -- TurboPlates not present (or a plate it hasn't skinned): fall back to
    -- the base nameplate frame so the feature still does something.
    if not myPlate and not lite then
        local icon = EnsureIconOn(plate, "duf_roleIcon")
        if role then
            ApplyRoleTexture(icon, role)
            icon:ClearAllPoints()
            local ox, oy = RoleIconOffsets()
            icon:SetPoint("LEFT", plate, "RIGHT", ox, oy)
            icon:Show()
        else
            icon:Hide()
        end
    end
end

local function RefreshAllRoleIcons()
    if not _G.C_NamePlate or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then return end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            if plate then UpdateRoleIcon(plate, unit) end
        end
    end
end

local nameplateFrame = CreateFrame("Frame")
nameplateFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
nameplateFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
nameplateFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
nameplateFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
nameplateFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if _G.C_NamePlate and arg1 then
            local plate = C_NamePlate.GetNamePlateForUnit(arg1)
            if plate then UpdateRoleIcon(plate, arg1) end
        end
    else
        RefreshAllRoleIcons()
    end
end)

-- TurboPlates swaps a plate between its lite (name-only) and full
-- (health bar) layouts as health changes, and fires no event when it
-- does -- so the icon has to be re-anchored on a light poll or it ends
-- up attached to whichever layout happened to be active when the plate
-- appeared. Cheap: a handful of table lookups per tick, and it exits
-- immediately when the feature is off.
local refreshAccum = 0
nameplateFrame:SetScript("OnUpdate", function(self, elapsed)
    if not DragonUIRageFixesDB.nameplateRoleIcons then return end
    refreshAccum = refreshAccum + elapsed
    if refreshAccum < 0.25 then return end
    refreshAccum = 0
    RefreshAllRoleIcons()
end)

--------------------------------------------------------------------------
-- Fix #3: reset DragonUI's Alt Gold data
--
-- DragonUI's "Alt Gold" module remembers each character's gold in
-- DragonUIDB.global.characterMoney, keyed "Realm|Name", and has no way to
-- clear it -- so renamed, deleted, or transferred characters linger in the
-- bag tooltip forever with stale amounts.
--
-- The table is wiped IN PLACE rather than reassigned: DragonUI's altmoney
-- module holds a live reference to that same table, so replacing it with a
-- fresh one would leave DragonUI writing into the old, orphaned copy until
-- the next reload. Wiping in place clears both views at once.
--
-- Your current character is re-seeded immediately; alts re-record their
-- gold the next time you log into them.
--------------------------------------------------------------------------

local function AltGoldStore()
    local sv = _G.DragonUIDB
    if type(sv) ~= "table" or type(sv.global) ~= "table" then return nil end
    return sv.global.characterMoney
end

local function CurrentGoldKey()
    return (GetRealmName() or "") .. "|" .. (UnitName("player") or "")
end

local function ListAltGold()
    local store = AltGoldStore()
    if not store then
        print("|cff33ccffDragonUI Rage Fixes|r: no Alt Gold data found (is DragonUI loaded?).")
        return
    end
    local n = 0
    print("|cff33ccffDragonUI Rage Fixes|r: stored Alt Gold entries:")
    for key, entry in pairs(store) do
        n = n + 1
        local copper = (type(entry) == "table" and entry.copper) or 0
        print(("  %s -- %dg (%s)"):format(key, math.floor(copper / 10000),
            (type(entry) == "table" and entry.class) or "?"))
    end
    if n == 0 then print("  (none)") end
end

-- keepCurrent: leave this character's entry alone. onlyKey: remove just
-- that one "Realm|Name" entry.
local function ResetAltGold(keepCurrent, onlyKey)
    local store = AltGoldStore()
    if not store then
        print("|cff33ccffDragonUI Rage Fixes|r: no Alt Gold data found (is DragonUI loaded?).")
        return
    end

    local currentKey = CurrentGoldKey()
    local removed = 0

    for key in pairs(store) do
        local remove
        if onlyKey then
            -- Match on the character name alone too, so the full
            -- "Realm|Name" key isn't required for the common case.
            remove = (key == onlyKey) or (key:lower():match("|(.+)$") == onlyKey:lower())
        else
            remove = not (keepCurrent and key == currentKey)
        end
        if remove then
            store[key] = nil
            removed = removed + 1
        end
    end

    -- Re-seed the current character right away so the tooltip isn't empty.
    if not onlyKey then
        store[currentKey] = {
            copper = GetMoney() or 0,
            class = select(2, UnitClass("player")),
        }
    end

    print(("|cff33ccffDragonUI Rage Fixes|r: cleared %d Alt Gold entr%s.%s"):format(
        removed, removed == 1 and "y" or "ies",
        onlyKey and "" or " Current character re-recorded; alts refresh on next login."))
end

--------------------------------------------------------------------------
-- Options UI
--
-- A single checkbox-per-fix panel, built dynamically from the OPTIONS
-- table above. Opens on plain "/duif", closes with Escape (registered in
-- UISpecialFrames) or its own close button.
--------------------------------------------------------------------------

local optionsFrame

local function CreateCheckbox(parent, option, yOffset)
    local cb = CreateFrame("CheckButton", "DragonUIRageFixesCheck" .. option.key, parent, "UICheckButtonTemplate")
    cb:SetWidth(24)
    cb:SetHeight(24)
    cb:SetPoint("TOPLEFT", 20, yOffset)

    local label = cb:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    label:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    label:SetJustifyH("LEFT")
    label:SetText(option.label)

    cb:SetScript("OnClick", function(self)
        DragonUIRageFixesDB[option.key] = self:GetChecked() and true or false
        -- Some fixes render immediately; re-apply so the change is visible
        -- without waiting for the next nameplate/roster event.
        RefreshAllRoleIcons()
    end)

    cb:SetScript("OnShow", function(self)
        self:SetChecked(DragonUIRageFixesDB[option.key])
    end)

    if option.desc then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(option.label, 1, 1, 1)
            GameTooltip:AddLine(option.desc, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    return cb
end

local function CreateOptionsFrame()
    if optionsFrame then
        return optionsFrame
    end

    local rowHeight = 28
    local f = CreateFrame("Frame", "DragonUIRageFixesOptionsFrame", UIParent)
    f:SetWidth(340)
    f:SetHeight(60 + (#OPTIONS * rowHeight))
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("DragonUI Rage Fixes")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local yOffset = -50
    for _, option in ipairs(OPTIONS) do
        CreateCheckbox(f, option, yOffset)
        yOffset = yOffset - rowHeight
    end

    tinsert(UISpecialFrames, "DragonUIRageFixesOptionsFrame")

    optionsFrame = f
    return f
end

local function ToggleOptionsFrame()
    local f = CreateOptionsFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

local function PrintHelp()
    print("|cff33ccffDragonUI Rage Fixes|r commands:")
    print("  /duf -- open the options panel.")
    print("  /duf partytooltip -- toggle the party-frame buff/debuff hover tooltip.")
    print("  /duf partytooltip on|off -- set it explicitly.")
    print("  /duf roleicons [on|off] -- toggle role icons on nameplates.")
    print("  /duf rolesize <6-40> -- role icon size.")
    print("  /duf roleoffset <x> <y> -- nudge the role icon.")
    print("  /duf roleart [on|off] -- use custom Artwork\\ icons instead of the stock LFG role icons.")
    print("  /duf goldlist -- list DragonUI's stored Alt Gold entries.")
    print("  /duf resetgold -- wipe all Alt Gold data (current character re-recorded immediately).")
    print("  /duf resetgold keep -- wipe every character EXCEPT the current one.")
    print("  /duf resetgold <name> -- remove one character's entry.")
    print("  /duf status -- show current fix states.")
end

local function PrintStatus()
    print(("|cff33ccffDragonUI Rage Fixes|r: party hover tooltip = %s"):format(
        DragonUIRageFixesDB.hidePartyAuraTooltip and "|cffff5555hidden|r" or "|cff55ff55shown|r (default)"))
    print(("  nameplate role icons = %s (art: %s)"):format(
        DragonUIRageFixesDB.nameplateRoleIcons and "|cff55ff55on|r" or "|cffff5555off|r",
        DragonUIRageFixesDB.useCustomRoleArt and "custom" or "stock LFG"))
end

SLASH_DRAGONUIRAGEFIXES1 = "/duf"
SlashCmdList["DRAGONUIRAGEFIXES"] = function(msg)
    msg = (msg or ""):lower()
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")

    if cmd == "" then
        ToggleOptionsFrame()
    elseif cmd == "options" or cmd == "config" or cmd == "ui" then
        ToggleOptionsFrame()
    elseif cmd == "partytooltip" then
        if rest == "on" then
            DragonUIRageFixesDB.hidePartyAuraTooltip = true
        elseif rest == "off" then
            DragonUIRageFixesDB.hidePartyAuraTooltip = false
        else
            DragonUIRageFixesDB.hidePartyAuraTooltip = not DragonUIRageFixesDB.hidePartyAuraTooltip
        end
        PrintStatus()
    elseif cmd == "roleicons" then
        if rest == "on" then
            DragonUIRageFixesDB.nameplateRoleIcons = true
        elseif rest == "off" then
            DragonUIRageFixesDB.nameplateRoleIcons = false
        else
            DragonUIRageFixesDB.nameplateRoleIcons = not DragonUIRageFixesDB.nameplateRoleIcons
        end
        RefreshAllRoleIcons()
        PrintStatus()
    elseif cmd == "rolesize" then
        local n = tonumber(rest)
        if n and n >= 6 and n <= 40 then
            DragonUIRageFixesDB.roleIconSize = n
            RefreshAllRoleIcons()
            print(("|cff33ccffDragonUI Rage Fixes|r: role icon size = %d"):format(n))
        else
            print("|cff33ccffDragonUI Rage Fixes|r: /duf rolesize <6-40> (current: "
                .. tostring(DragonUIRageFixesDB.roleIconSize) .. ")")
        end
    elseif cmd == "roleoffset" then
        local x, y = rest:match("^(-?%d+)%s+(-?%d+)$")
        if x and y then
            DragonUIRageFixesDB.roleIconOffsetX = tonumber(x)
            DragonUIRageFixesDB.roleIconOffsetY = tonumber(y)
            RefreshAllRoleIcons()
            print(("|cff33ccffDragonUI Rage Fixes|r: role icon offset = %s, %s"):format(x, y))
        else
            print(("|cff33ccffDragonUI Rage Fixes|r: /duf roleoffset <x> <y> (current: %s, %s)"):format(
                tostring(DragonUIRageFixesDB.roleIconOffsetX), tostring(DragonUIRageFixesDB.roleIconOffsetY)))
        end
    elseif cmd == "roleart" then
        if rest == "on" then
            DragonUIRageFixesDB.useCustomRoleArt = true
        elseif rest == "off" then
            DragonUIRageFixesDB.useCustomRoleArt = false
        else
            DragonUIRageFixesDB.useCustomRoleArt = not DragonUIRageFixesDB.useCustomRoleArt
        end
        RefreshAllRoleIcons()
        PrintStatus()
    elseif cmd == "goldlist" then
        ListAltGold()
    elseif cmd == "resetgold" then
        if rest == "" then
            ResetAltGold(false, nil)
        elseif rest == "keep" then
            ResetAltGold(true, nil)
        else
            ResetAltGold(false, rest)
        end
    elseif cmd == "status" then
        PrintStatus()
    else
        PrintHelp()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end
    EnsureDefaults()
    self:UnregisterEvent("ADDON_LOADED")
end)
