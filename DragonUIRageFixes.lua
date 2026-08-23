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
        key = "altGoldRightClickMenu",
        label = "Right-click bag gold to manage Alt Gold",
        desc = "Right-clicking the gold in your bags opens a menu to delete a single character's stored gold, or wipe all of it. Left-click coin pickup is unaffected.",
        default = true,
    },
    {
        key = "trackBazaarTokens",
        label = "Track Bazaar Tokens per character",
        desc = "Adds each character's Bazaar Token count to the gold tooltip in your bags. Counts include the bank.",
        default = true,
    },
    {
        key = "nameplateRoleIcons",
        label = "Role icons on nameplates",
        desc = "Shows a small tank / healer / support icon above group members' nameplates. Sits alongside TurboPlates rather than replacing it -- it draws its own icon on the nameplate frame and never touches TurboPlates' own healer mark.",
        default = false,
    },
    {
        key = "detailsAutoReset",
        label = "Auto-clear Details overall on new instance",
        desc = "Wipes Details!'s overall segment each time you enter a new dungeon or raid, so numbers never carry over from the previous run. Waits until you're out of combat before resetting.",
        default = true,
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
-- Fix #3a: track Bazaar Tokens (and any other item) per character
--
-- DragonUI's Alt Gold tooltip only knows about gold. This records each
-- character's Bazaar Token count alongside it and appends it to that same
-- tooltip, so you can see tokens per alt without logging into each one.
--
-- Bazaar Tokens are a normal ITEM (id 975001), not a currency -- confirmed
-- from the in-game tooltip -- so the count comes from GetItemCount rather
-- than the currency API. Bank contents are included, since tokens are
-- commonly parked there.
--
-- Counts live in THIS addon's SavedVariables rather than DragonUI's:
-- writing into another addon's saved table risks it being pruned by that
-- addon's own defaults handling on upgrade.
--------------------------------------------------------------------------

local BAZAAR_TOKEN_ITEM_ID = 975001

local function TokenStore(create)
    if create and type(DragonUIRageFixesDB.characterTokens) ~= "table" then
        DragonUIRageFixesDB.characterTokens = {}
    end
    return DragonUIRageFixesDB.characterTokens
end

local function TokenWatchList()
    local list = DragonUIRageFixesDB.tokenWatch
    if type(list) ~= "table" or #list == 0 then
        return { BAZAAR_TOKEN_ITEM_ID }
    end
    return list
end

-- GetItemInfo returns nil for an item the client hasn't cached yet, so
-- fall back to a stable placeholder instead of dropping the entry.
local function TokenName(itemID)
    local name = GetItemInfo(itemID)
    if name then return name end
    if itemID == BAZAAR_TOKEN_ITEM_ID then return "Bazaar Token" end
    return "Item " .. tostring(itemID)
end

local function CountToken(itemID)
    if type(_G.GetItemCount) ~= "function" then return 0 end
    -- includeBank = true; tokens are often parked in the bank.
    local ok, count = pcall(_G.GetItemCount, itemID, true)
    return (ok and count) or 0
end

local function SaveCurrentTokens()
    local store = TokenStore(true)
    if not store then return end
    local key = (GetRealmName() or "") .. "|" .. (UnitName("player") or "")

    local recorded, any = {}, false
    for _, itemID in ipairs(TokenWatchList()) do
        local count = CountToken(itemID)
        if count > 0 then
            recorded[itemID] = count
            any = true
        end
    end

    -- Written even when empty so spending down to zero clears the old
    -- figure rather than leaving a stale count forever.
    store[key] = any and recorded or nil
end

-- Token cleanup mirrors the Alt Gold resets, so clearing a character
-- removes both its gold and its token record rather than leaving orphans.
local function ClearAllTokens()
    DragonUIRageFixesDB.characterTokens = {}
end

local function ClearTokensFor(keyOrName)
    local store = TokenStore(false)
    if not store or not keyOrName then return end
    for key in pairs(store) do
        if key == keyOrName or (key:lower():match("|(.+)$") == keyOrName:lower()) then
            store[key] = nil
        end
    end
end

local function ListTokens()
    print("|cff33ccffDragonUI Rage Fixes|r: tracked items on this character:")
    for _, itemID in ipairs(TokenWatchList()) do
        print(("  %s (id %d) = %d"):format(TokenName(itemID), itemID, CountToken(itemID)))
    end
    print("  Add another with /duf trackitem <itemID>.")
end

-- Appends the per-character token lines onto DragonUI's Alt Gold tooltip.
--
-- This runs a frame LATER than the money button's OnEnter rather than
-- inline, because DragonUI's own OnEnter calls GameTooltip:SetOwner --
-- which wipes any lines added before it. Deferring a frame means the
-- append lands after DragonUI has finished building the tooltip,
-- regardless of which addon hooked OnEnter first.
local tokenTooltipFrame = CreateFrame("Frame")
tokenTooltipFrame:Hide()

local function AppendTokenLines(owner)
    if not owner then return end

    local store = TokenStore(false)
    if not store then return end

    -- On Bagster the tooltip already exists (DragonUI's Alt Gold list) and
    -- we append to it. On Combuctor nothing owns the tooltip, because
    -- Combuctor never registers with DragonUI's alt-money module -- so
    -- open our own rather than silently doing nothing.
    local standalone = not GameTooltip:IsOwned(owner)
    if standalone then
        if not owner:IsVisible() then return end
        GameTooltip:SetOwner(owner, "ANCHOR_TOPRIGHT")
    end

    local rows = {}
    for key, tokens in pairs(store) do
        local realm, name = key:match("^(.-)|(.+)$")
        local total = 0
        if type(tokens) == "table" then
            for _, count in pairs(tokens) do total = total + (count or 0) end
        end
        if total > 0 then
            rows[#rows + 1] = { name = name or key, realm = realm, total = total }
        end
    end
    if #rows == 0 then
        if standalone then GameTooltip:Hide() end
        return
    end

    table.sort(rows, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)

    local grand = 0
    if not standalone then GameTooltip:AddLine(" ") end
    GameTooltip:AddLine(TokenName(BAZAAR_TOKEN_ITEM_ID) .. "s", 1, 0.82, 0)
    for _, row in ipairs(rows) do
        GameTooltip:AddDoubleLine(row.name, row.total, 1, 1, 1, 1, 1, 1)
        grand = grand + row.total
    end
    if #rows > 1 then
        GameTooltip:AddDoubleLine("Total", grand, 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
end

tokenTooltipFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    AppendTokenLines(self.owner)
end)

local function ScheduleTokenTooltip(owner)
    if DragonUIRageFixesDB.trackBazaarTokens == false then return end
    SaveCurrentTokens()
    tokenTooltipFrame.owner = owner
    tokenTooltipFrame:Show()
end

-- Keep the current character's count fresh as items move around.
local tokenEventFrame = CreateFrame("Frame")
tokenEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tokenEventFrame:RegisterEvent("BAG_UPDATE")
tokenEventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
tokenEventFrame:SetScript("OnEvent", function() SaveCurrentTokens() end)

--------------------------------------------------------------------------
-- Fix #3b: right-click the bag gold to manage Alt Gold entries
--
-- DragonUI already hooks OnEnter/OnLeave of the bag money buttons
-- (ContainerFrame<N>MoneyFrameGold/Silver/CopperButton) to show its Alt
-- Gold tooltip. This adds a right-click menu on those same buttons to
-- delete a single character or wipe the lot, so the data can be managed
-- where it's actually displayed instead of only via slash commands.
--
-- OnClick is hooked (not replaced) and ignores anything but RightButton,
-- so the stock left-click coin-pickup behaviour is untouched.
--------------------------------------------------------------------------

local altGoldMenuFrame

StaticPopupDialogs["DUF_RESET_ALT_GOLD"] = {
    text = "Wipe ALL stored Alt Gold data?\n\nYour current character is re-recorded immediately; other characters refresh the next time you log into them.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() ResetAltGold(false, nil); ClearAllTokens() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function BuildAltGoldMenu()
    local menu = {
        { text = "Alt Gold", isTitle = true, notCheckable = true },
    }

    local store = AltGoldStore()
    local currentKey = CurrentGoldKey()

    -- Sorted so the menu order is stable between openings.
    local keys = {}
    if store then
        for key in pairs(store) do keys[#keys + 1] = key end
        table.sort(keys)
    end

    if #keys == 0 then
        menu[#menu + 1] = { text = "(no data recorded)", notCheckable = true, disabled = true }
    else
        for _, key in ipairs(keys) do
            local entry = store[key]
            local realm, name = key:match("^(.-)|(.+)$")
            name = name or key
            local gold = math.floor(((type(entry) == "table" and entry.copper) or 0) / 10000)
            local label = ("Delete %s (%dg)"):format(name, gold)
            if key == currentKey then
                label = label .. " |cff808080(current)|r"
            end
            menu[#menu + 1] = {
                text = label,
                notCheckable = true,
                func = function()
                    store[key] = nil
                    ClearTokensFor(key)
                    print(("|cff33ccffDragonUI Rage Fixes|r: removed Alt Gold entry for %s."):format(name))
                end,
            }
        end
    end

    menu[#menu + 1] = { text = "", disabled = true, notCheckable = true }
    menu[#menu + 1] = {
        text = "Reset all Alt Gold data",
        notCheckable = true,
        func = function() StaticPopup_Show("DUF_RESET_ALT_GOLD") end,
    }
    menu[#menu + 1] = { text = CANCEL or "Cancel", notCheckable = true }

    return menu
end

local function ShowAltGoldMenu(anchor)
    if type(_G.EasyMenu) ~= "function" then
        -- Shouldn't happen on 3.3.5a, but degrade to the slash commands
        -- rather than erroring on click.
        print("|cff33ccffDragonUI Rage Fixes|r: dropdown menus unavailable -- use /duf resetgold or /duf goldlist.")
        return
    end
    if not altGoldMenuFrame then
        altGoldMenuFrame = CreateFrame("Frame", "DUFAltGoldMenuFrame", UIParent, "UIDropDownMenuTemplate")
    end
    EasyMenu(BuildAltGoldMenu(), altGoldMenuFrame, anchor or "cursor", 0, 0, "MENU", 2)
end

local hookedMoneyButtons = {}

local function HookMoneyButton(button)
    if not button or hookedMoneyButtons[button] then return end
    hookedMoneyButtons[button] = true
    -- Additive: keeps LeftButtonUp so coin pickup still works.
    if button.RegisterForClicks then
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    button:HookScript("OnClick", function(self, mouseButton)
        if mouseButton ~= "RightButton" then return end
        if DragonUIRageFixesDB.altGoldRightClickMenu == false then return end
        ShowAltGoldMenu(self)
    end)
    button:HookScript("OnEnter", function(self)
        ScheduleTokenTooltip(self)
    end)
end

local function HookAllMoneyButtons()
    -- Stock Blizzard bags.
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local base = "ContainerFrame" .. i .. "MoneyFrame"
        HookMoneyButton(_G[base .. "GoldButton"])
        HookMoneyButton(_G[base .. "SilverButton"])
        HookMoneyButton(_G[base .. "CopperButton"])
    end

    -- DragonUI's two bag replacements each build their own money display
    -- and name it "DragonUI_<Addon>Money<N>" (ids start at 1). Both are
    -- swept because either can be the active bag addon -- and note that
    -- only Bagster registers itself with DragonUI's alt-money module, so
    -- on Combuctor this addon is the ONLY thing adding to that tooltip.
    for _, prefix in ipairs({ "DragonUI_CombuctorMoney", "DragonUI_BagsterMoney" }) do
        for i = 1, 12 do
            local f = _G[prefix .. i]
            if f then
                HookMoneyButton(f.btnGold)
                HookMoneyButton(f.btnSilver)
                HookMoneyButton(f.btnCopper)
                HookMoneyButton(f.btnText)
            end
        end
    end
end

local moneyHookFrame = CreateFrame("Frame")
moneyHookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
moneyHookFrame:RegisterEvent("BAG_UPDATE")
moneyHookFrame:SetScript("OnEvent", function()
    -- Money frames are created lazily as bags are opened, so re-sweep
    -- rather than hooking once at load.
    HookAllMoneyButtons()
end)

-- Bagster/Combuctor build their money frames the first time the bag UI is
-- shown, which fires no event this addon can rely on -- so sweep on a slow
-- timer too. Already-hooked buttons are skipped, so this settles to a
-- couple of global lookups per tick.
local moneySweepAccum = 0
moneyHookFrame:SetScript("OnUpdate", function(self, elapsed)
    moneySweepAccum = moneySweepAccum + elapsed
    if moneySweepAccum < 2 then return end
    moneySweepAccum = 0
    HookAllMoneyButtons()
end)

--------------------------------------------------------------------------
-- Fix #4: clear Details!'s overall data when entering a new instance
--
-- Details' "overall" segment accumulates across every fight until manually
-- reset, so yesterday's raid keeps inflating today's dungeon numbers. This
-- wipes it on entering a new instance.
--
-- Uses Details:ResetSegmentOverallData() -- the documented API for the
-- overall segment only. (Details:ResetSegmentData() would also nuke the
-- per-fight segment history, which is usually the part you still want.)
--
-- "New instance" is detected by a signature of instance name + difficulty,
-- so re-running the same dungeon counts as new, while zoning within one
-- instance does not. PLAYER_ENTERING_WORLD fires before Details has
-- necessarily finished initialising, so the reset is deferred briefly --
-- and deferred again if you're in combat, since resetting mid-pull would
-- discard the fight in progress.
--------------------------------------------------------------------------

local lastInstanceSignature = nil

local function CurrentInstanceSignature()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return nil, nil, nil end
    local name, _type, difficultyIndex = GetInstanceInfo()
    return (tostring(name) .. "|" .. tostring(difficultyIndex)), instanceType, name
end

local function ShouldResetForInstanceType(instanceType)
    -- Battlegrounds/arenas are deliberately included: overall carry-over is
    -- just as misleading there. Only "none" (open world) is skipped, and
    -- that can't reach here anyway.
    return instanceType == "party" or instanceType == "raid"
        or instanceType == "pvp" or instanceType == "arena"
end

local function DoDetailsOverallReset(instanceName)
    local Details = _G.Details
    if not Details or type(Details.ResetSegmentOverallData) ~= "function" then
        return false
    end
    local ok = pcall(Details.ResetSegmentOverallData, Details)
    if ok then
        print(("|cff33ccffDragonUI Rage Fixes|r: cleared Details overall data for |cffffd100%s|r."):format(
            tostring(instanceName or "this instance")))
    end
    return ok
end

local detailsFrame = CreateFrame("Frame")
local pendingResetName, pendingResetDelay = nil, nil

local function QueueDetailsReset(instanceName)
    pendingResetName = instanceName
    pendingResetDelay = 2 -- let Details finish loading after a zone-in
end

detailsFrame:SetScript("OnUpdate", function(self, elapsed)
    if not pendingResetDelay then return end
    pendingResetDelay = pendingResetDelay - elapsed
    if pendingResetDelay > 0 then return end
    -- Never reset mid-fight; retry shortly instead.
    if InCombatLockdown() then
        pendingResetDelay = 2
        return
    end
    local name = pendingResetName
    pendingResetDelay, pendingResetName = nil, nil
    DoDetailsOverallReset(name)
end)

local function CheckInstanceChange()
    local signature, instanceType, name = CurrentInstanceSignature()

    if not signature then
        -- Left the instance; next entry counts as new.
        lastInstanceSignature = nil
        return
    end

    if signature == lastInstanceSignature then return end
    lastInstanceSignature = signature

    if DragonUIRageFixesDB.detailsAutoReset == false then return end
    if not ShouldResetForInstanceType(instanceType) then return end

    QueueDetailsReset(name)
end

detailsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
detailsFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
detailsFrame:SetScript("OnEvent", CheckInstanceChange)

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
    print("  /duf tokens -- show tracked item counts (Bazaar Tokens) on this character.")
    print("  /duf moneyframes -- diagnostic: which bag money displays got hooked.")
    print("  /duf trackitem <itemID> -- also track another item per character.")
    print("  /duf resetgold -- wipe all Alt Gold data (current character re-recorded immediately).")
    print("  /duf resetgold keep -- wipe every character EXCEPT the current one.")
    print("  /duf resetgold <name> -- remove one character's entry.")
    print("  /duf tracktokens [on|off] -- toggle Bazaar Token tracking.")
    print("  /duf detailsreset [on|off] -- toggle auto-clearing Details overall on new instances.")
    print("  /duf cleardetails -- clear Details overall data right now.")
    print("  /duf status -- show current fix states.")
end

local function PrintStatus()
    print("|cff33ccffDragonUI Rage Fixes|r: feature states")
    for _, option in ipairs(OPTIONS) do
        local on = DragonUIRageFixesDB[option.key]
        print(("  %s -- %s"):format(option.label,
            on and "|cff55ff55on|r" or "|cffff5555off|r"))
    end
    print(("  role icon: size %s, offset %s,%s, art: %s"):format(
        tostring(DragonUIRageFixesDB.roleIconSize),
        tostring(DragonUIRageFixesDB.roleIconOffsetX),
        tostring(DragonUIRageFixesDB.roleIconOffsetY),
        DragonUIRageFixesDB.useCustomRoleArt and "custom" or "stock LFG"))
end

-- Generic on/off for any registered feature, so new fixes get a slash
-- toggle for free instead of needing their own command each time.
local function ToggleFeature(key, rest)
    if rest == "on" then
        DragonUIRageFixesDB[key] = true
    elseif rest == "off" then
        DragonUIRageFixesDB[key] = false
    else
        DragonUIRageFixesDB[key] = not DragonUIRageFixesDB[key]
    end
    for _, option in ipairs(OPTIONS) do
        if option.key == key then
            print(("|cff33ccffDragonUI Rage Fixes|r: %s -- %s"):format(option.label,
                DragonUIRageFixesDB[key] and "|cff55ff55on|r" or "|cffff5555off|r"))
        end
    end
    RefreshAllRoleIcons()
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
        ToggleFeature("hidePartyAuraTooltip", rest)
    elseif cmd == "roleicons" then
        ToggleFeature("nameplateRoleIcons", rest)
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
    elseif cmd == "tokens" then
        ListTokens()
    elseif cmd == "tracktokens" then
        ToggleFeature("trackBazaarTokens", rest)
    elseif cmd == "detailsreset" then
        ToggleFeature("detailsAutoReset", rest)
    elseif cmd == "cleardetails" then
        if not DoDetailsOverallReset("manual reset") then
            print("|cff33ccffDragonUI Rage Fixes|r: Details isn't loaded (or has no ResetSegmentOverallData).")
        end
    elseif cmd == "moneyframes" then
        -- Diagnostic: which money displays this addon managed to hook.
        local n = 0
        for _ in pairs(hookedMoneyButtons) do n = n + 1 end
        print(("|cff33ccffDragonUI Rage Fixes|r: %d money button(s) hooked."):format(n))
        for _, prefix in ipairs({ "DragonUI_CombuctorMoney", "DragonUI_BagsterMoney" }) do
            for i = 1, 12 do
                if _G[prefix .. i] then print("  found " .. prefix .. i) end
            end
        end
        if n == 0 then
            print("  Open your bags first, then run this again.")
        end
    elseif cmd == "trackitem" then
        local id = tonumber(rest)
        if id then
            local list = DragonUIRageFixesDB.tokenWatch
            if type(list) ~= "table" then
                list = { BAZAAR_TOKEN_ITEM_ID }
                DragonUIRageFixesDB.tokenWatch = list
            end
            local already = false
            for _, existing in ipairs(list) do
                if existing == id then already = true end
            end
            if already then
                print(("|cff33ccffDragonUI Rage Fixes|r: item %d is already tracked."):format(id))
            else
                table.insert(list, id)
                SaveCurrentTokens()
                print(("|cff33ccffDragonUI Rage Fixes|r: now tracking %s (id %d)."):format(TokenName(id), id))
            end
        else
            print("|cff33ccffDragonUI Rage Fixes|r: /duf trackitem <itemID>  (Bazaar Token is 975001)")
        end
    elseif cmd == "resetgold" then
        if rest == "" then
            ResetAltGold(false, nil)
            ClearAllTokens()
        elseif rest == "keep" then
            ResetAltGold(true, nil)
        else
            ResetAltGold(false, rest)
            ClearTokensFor(rest)
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
