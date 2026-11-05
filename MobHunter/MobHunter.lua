local addonName, ns = ...

-- /mobhunt <name>: alerts (sound, text, a marker over the mob's nameplate, a MobHunter icon on the
-- minimap) when a mob with that name comes into range. Targeting it is left to the player:
-- TargetUnit is protected, so the addon only offers a button and a keybind that run
-- "/target <name>" when pressed.

local SCAN_SECONDS = 1
local PROBE_STEP = 6 -- minimap units between probe points
local ALERT_SOUND = 8959 -- raid warning; used only if SOUNDKIT doesn't name it

local hunted -- normalized name being hunted, or nil
local tracker = ns.Hunt.NewTracker()
local ticker
local markers = {} -- nameplate unit token -> marker frame
local icons = {} -- minimap icon frames
local pendingMacro = false
local seenToken, seenName -- nameplate token and full name of a mob that matched; "/target" needs the full name

local frame = CreateFrame("Frame", addonName .. "EventFrame")
local handlers = {}

local function say(message)
    print("|cff66ccffMobHunter:|r " .. message)
end

-- The "Target" button is a secure button: its macro text can only be changed out of combat,
-- so a change made in combat waits for PLAYER_REGEN_ENABLED. The keybind works either way.
local button
local function showButton()
    return not (MobHunterDB and MobHunterDB.showButton == false)
end

local function applyMacro()
    if not button then return end
    if InCombatLockdown() then
        pendingMacro = true
        return
    end
    pendingMacro = false
    button:SetAttribute("type", "macro")
    local name = seenName or hunted
    button:SetAttribute("macrotext", name and ("/target " .. name) or "")
    button:SetText(name and ("Target " .. name) or "MobHunter")
    if seenToken and showButton() then button:Show() else button:Hide() end -- only while a match is in range
end

local function createButton()
    button = CreateFrame("Button", "MobHunterTargetButton", UIParent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    button:SetSize(200, 28)
    button:SetPoint("TOP", UIParent, "TOP", 0, -140)
    button:RegisterForClicks("AnyUp", "AnyDown") -- the ActionButtonUseKeyDown setting picks which one fires
    button:SetMovable(true)
    button:RegisterForDrag("RightButton")
    button:SetScript("OnDragStart", button.StartMoving)
    button:SetScript("OnDragStop", button.StopMovingOrSizing)
    button:Hide()
end

local function markerFor(token)
    local marker = markers[token]
    if not marker then
        marker = CreateFrame("Frame", nil, UIParent)
        marker:SetSize(160, 20)
        marker.text = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        marker.text:SetPoint("CENTER")
        markers[token] = marker
    end
    return marker
end

local function showMarker(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit.token)
    if not plate then return end
    local marker = markerFor(unit.token)
    marker.text:SetText("|cffff3333>> " .. tostring(unit.name) .. " <<|r")
    marker:ClearAllPoints()
    marker:SetPoint("BOTTOM", plate, "TOP", 0, 8)
    marker:Show()
end

local function hideMarkers()
    for _, marker in pairs(markers) do marker:Hide() end
end

-- MobHunter's icon on the minimap, one per hunted mob found among the tracking dots. The
-- client draws the dots itself and gives addons no way to hide them, so the icon is a child
-- frame above the minimap, larger than a dot, covering it.
local ICON_PATH = "Interface\\AddOns\\MobHunter\\icon"
local ICON_SIZE, MAX_ICONS = 20, 8
local function iconFor(i)
    local icon = icons[i]
    if not icon then
        icon = CreateFrame("Frame", nil, Minimap)
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetFrameStrata("HIGH")
        icon.texture = icon:CreateTexture(nil, "OVERLAY")
        icon.texture:SetAllPoints()
        icon.texture:SetTexture(ICON_PATH)
        icons[i] = icon
    end
    return icon
end

-- centres: list of { dx, dy } offsets from the minimap's middle, as Probe.Find returns them.
local function showIcons(centres)
    if not (Minimap and CreateFrame) then return end
    local radius = Minimap:GetWidth() / 2
    for i = 1, math.min(#centres, MAX_ICONS) do
        local icon = iconFor(i)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", Minimap, "BOTTOMLEFT", radius + centres[i][1], radius + centres[i][2])
        icon:Show()
    end
    for i = math.min(#centres, MAX_ICONS) + 1, #icons do icons[i]:Hide() end
end

local function hideIcons()
    for _, icon in ipairs(icons) do icon:Hide() end
end

local function alert(name)
    local sound = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or ALERT_SOUND
    pcall(PlaySound, sound)
    say("found |cffffff00" .. tostring(name) .. "|r. Press the Target button or your MobHunter keybind to target it.")
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage("MobHunter: " .. tostring(name), 1, 0.2, 0.2)
    end
end

-- What the client says is in range: the visible nameplates.
local function readUnits()
    local units = {}
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return units end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local token = plate.unitToken
        if token then
            units[#units + 1] = {
                token = token,
                name = UnitName(token),
                guid = UnitGUID(token),
                isDead = UnitIsDead(token),
                isPlayer = UnitIsPlayer(token),
            }
        end
    end
    return units
end

local function scan()
    if not hunted then return end

    -- 1) mobs in range (nameplates)
    for _, unit in ipairs(ns.Hunt.Scan(tracker, hunted, readUnits())) do
        alert(unit.name)
        showMarker(unit)
        seenToken, seenName = unit.token, unit.name
        applyMacro()
    end

    -- 2) mobs among the minimap's tracking dots, when something is being tracked (they get our icon)
    if ns.Probe.Available(Minimap) and ns.Probe.IsTracking() then
        local centres = ns.Probe.Find(Minimap, hunted, PROBE_STEP) or {}
        if #centres > 0 then
            if not tracker.onMinimap then alert(hunted) end
            tracker.onMinimap = true
            showIcons(centres)
        else
            tracker.onMinimap = nil
            hideIcons()
        end
    end
end

local function stop()
    hunted, seenToken, seenName = nil, nil, nil
    tracker = ns.Hunt.NewTracker()
    if ticker then ticker:Cancel(); ticker = nil end
    hideMarkers()
    hideIcons()
    applyMacro()
end

local function start(name)
    stop()
    hunted = name
    if not button then createButton() end
    applyMacro()
    if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(SCAN_SECONDS, scan) end
    say("hunting |cffffff00" .. name .. "|r. Type /mobhunt stop to cancel.")
    local ok, shown = pcall(GetCVar, "nameplateShowEnemies")
    if ok and shown == "0" then
        say("enemy nameplates are off, so mobs in range can't be seen. Turn them on (Options > Interface > Names, or the V key).")
    end
    scan()
end

function handlers.ADDON_LOADED(loadedName)
    if loadedName ~= addonName then return end
    MobHunterDB = MobHunterDB or {}
    if MobHunterDB.showButton == nil then MobHunterDB.showButton = true end
    createButton()
    frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.NAME_PLATE_UNIT_ADDED()
    scan()
end

function handlers.NAME_PLATE_UNIT_REMOVED(token)
    if markers[token] then markers[token]:Hide() end
    if token == seenToken then
        seenToken, seenName = nil, nil
        applyMacro()
    end
end

function handlers.PLAYER_REGEN_ENABLED()
    if pendingMacro then applyMacro() end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then handler(...) end
end)

for event in pairs(handlers) do
    frame:RegisterEvent(event)
end

_G["BINDING_HEADER_MOBHUNTER"] = "MobHunter"
_G["BINDING_NAME_CLICK MobHunterTargetButton:LeftButton"] = "Target the hunted mob"

SLASH_MOBHUNT1 = "/mobhunt"
SLASH_MOBHUNT2 = "/mobhunter"
SlashCmdList["MOBHUNT"] = function(msg)
    local command = ns.Hunt.ParseCommand(msg)
    if command.action == "hunt" then
        start(command.name)
    elseif command.action == "stop" then
        stop()
        say("stopped.")
    elseif command.action == "button" then
        MobHunterDB = MobHunterDB or {}
        if command.on ~= nil then
            MobHunterDB.showButton = command.on
            applyMacro()
        end
        say("the Target button is " .. (showButton() and "on" or "off") .. ". /mobhunt button on|off to change it.")
    elseif command.action == "target" then
        -- Targeting is protected: it only runs from a click or keypress on a secure button, never
        -- from a slash command. A macro can click the button (shown or not) instead.
        say("addons can't target from a slash command. Put |cffffff00/click MobHunterTargetButton|r in a macro (or bind a key under Keybindings > AddOns > MobHunter).")
    elseif command.action == "status" then
        say(hunted and ("hunting |cffffff00" .. hunted .. "|r.") or "not hunting anything. Type /mobhunt <mob name>.")
    else
        say("/mobhunt <mob name> to start, /mobhunt stop to cancel, /mobhunt button on|off, /mobhunt target.")
    end
end

ns.MobHunter = { Start = start, Stop = stop, Scan = scan }
