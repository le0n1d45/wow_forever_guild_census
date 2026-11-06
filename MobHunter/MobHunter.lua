local addonName, ns = ...

-- /mobhunt <name>: alerts (sound, text, a marker over the mob's nameplate, a MobHunter icon on the
-- minimap) when a mob with that name comes into range. Targeting it is left to the player:
-- TargetUnit is protected, so the addon only offers a button and a keybind that run
-- "/target <name>" when pressed.

local SCAN_SECONDS = 1
local PROBE_STEP = 6 -- minimap units between probe points; a dot answers within about 5, so 6 leaves no gaps
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

-- An ordinary character macro ("MobHunter") that mirrors the button's text, for players who'd
-- rather have a bar button. Macro text isn't protected, so it can be edited out of combat.
local MACRO_NAME, MACRO_ICON = "MobHunter", 134400
local function syncMacro(create)
    if not (GetMacroIndexByName and EditMacro) then return false end
    local index = GetMacroIndexByName(MACRO_NAME)
    if (not index or index == 0) and create and CreateMacro then
        local ok = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, "/mobhunt", true)
        if not ok then return false end
        index = GetMacroIndexByName(MACRO_NAME)
    end
    if not index or index == 0 then return false end
    local name = seenName or hunted
    pcall(EditMacro, index, nil, nil, name and ("/target " .. name) or "/mobhunt")
    return true
end

local function soundOn()
    return not (MobHunterDB and MobHunterDB.playSound == false)
end

local function setPlaySound(on)
    MobHunterDB = MobHunterDB or {}
    MobHunterDB.playSound = on and true or false
end

local applyMacro

local function setShowButton(on)
    MobHunterDB = MobHunterDB or {}
    MobHunterDB.showButton = on and true or false
    applyMacro()
end

function applyMacro()
    if not button then return end
    if InCombatLockdown() then
        pendingMacro = true
        return
    end
    pendingMacro = false
    syncMacro(false)
    button:SetAttribute("type", "macro")
    local name = seenName or hunted
    button:SetAttribute("macrotext", name and ("/target " .. name) or "")
    button:SetText(name and ("Target " .. name) or "MobHunter")
    if seenToken and showButton() then button:Show() else button:Hide() end -- only while a match is in range
end

local huntWindow
local function createButton()
    huntWindow = ns.HuntWindow.Create({
        onStart = function(text) ns.MobHunter.Start(ns.Hunt.Normalize(text)) end,
        onStop = function() ns.MobHunter.Stop() end,
    })
    button = huntWindow.targetButton
    huntWindow.frame:SetShown(ns.HuntWindow.ShouldShow())
end

local function setShowWindow(on)
    MobHunterDB = MobHunterDB or {}
    MobHunterDB.showHuntWindow = on and true or false
    if huntWindow then huntWindow.frame:SetShown(on and true or false) end
end

local function getShowWindow()
    return MobHunterDB ~= nil and MobHunterDB.showHuntWindow == true
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
-- frame above the minimap, a pixel larger than a dot, drawn on top of it.
local ICON_PATH = "Interface\\AddOns\\MobHunter\\icon"
local ICON_SIZE, MAX_ICONS = 11, 24
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

-- A window with the text in a selectable box, so it can be copied with Ctrl+C (chat can't be).
local reportFrame
local function showReport(title, text)
    if not reportFrame then
        reportFrame = CreateFrame("Frame", "MobHunterReportFrame", UIParent, "BasicFrameTemplateWithInset")
        reportFrame:SetSize(520, 360)
        reportFrame:SetPoint("CENTER")
        reportFrame:SetFrameStrata("DIALOG")
        reportFrame:SetMovable(true)
        reportFrame:EnableMouse(true)
        reportFrame:RegisterForDrag("LeftButton")
        reportFrame:SetScript("OnDragStart", reportFrame.StartMoving)
        reportFrame:SetScript("OnDragStop", reportFrame.StopMovingOrSizing)
        if UISpecialFrames then table.insert(UISpecialFrames, "MobHunterReportFrame") end -- Esc closes it
        local scroll = CreateFrame("ScrollFrame", "MobHunterReportScroll", reportFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal or GameFontHighlight)
        box:SetWidth(470)
        box:SetScript("OnEscapePressed", function() reportFrame:Hide() end)
        scroll:SetScrollChild(box)
        reportFrame.box = box
    end
    if type(reportFrame.TitleText) == "table" then reportFrame.TitleText:SetText(title) end
    reportFrame.box:SetText(text)
    reportFrame:Show()
    reportFrame.box:SetFocus()
    reportFrame.box:HighlightText() -- selected: just press Ctrl+C
end

local function alert(name)
    local sound = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or ALERT_SOUND
    if soundOn() then pcall(PlaySound, sound) end
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
                isTarget = UnitIsUnit and UnitIsUnit(token, "target") or false,
            }
        end
    end
    return units
end

-- True when the player's current target is a mob being hunted: already found, so no sound.
local function targetIsHunted()
    if not (UnitExists and UnitExists("target")) then return false end
    if UnitIsPlayer("target") or UnitIsDead("target") then return false end
    return ns.Hunt.Matches(hunted, UnitName("target"))
end

local function scan()
    if not hunted then return end

    -- 1) mobs in range (nameplates)
    for _, unit in ipairs(ns.Hunt.Scan(tracker, hunted, readUnits())) do
        if not unit.isTarget then alert(unit.name) end
        showMarker(unit)
        seenToken, seenName = unit.token, unit.name
        applyMacro()
    end

    -- 2) mobs among the minimap's tracking dots, when something is being tracked (they get our icon)
    if not InCombatLockdown() and ns.Probe.Available(Minimap) and ns.Probe.IsTracking() then
        local centres = ns.Probe.Find(Minimap, hunted, PROBE_STEP) or {}
        if #centres > 0 then
            if not tracker.onMinimap and not targetIsHunted() then alert(hunted) end
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
    if huntWindow then huntWindow.SetHunting(nil) end
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
    huntWindow.SetHunting(name)
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
    if MobHunterDB.playSound == nil then MobHunterDB.playSound = true end
    createButton()
    if ns.Options then ns.Options.Register() end
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

local function showDebug()
    local report = ns.Probe.Diagnose(Minimap, PROBE_STEP, hunted)
    MobHunterDB = MobHunterDB or {}
    MobHunterDB.lastDebug = report -- also lands in the SavedVariables file on /reload or logout
    showReport("MobHunter debug", table.concat(report, "\n"))
    say("debug info is in the window (already selected: press Ctrl+C to copy). It is also saved to MobHunter.lua in your WTF\\Account\\<account>\\SavedVariables folder after /reload.")
end

local function createMacro()
    if InCombatLockdown() then
        say("can't create a macro during combat.")
    elseif syncMacro(true) then
        applyMacro()
        say("macro |cffffff00MobHunter|r is ready. Open /macro and drag it to an action bar. It follows your hunt and targets the mob it matched.")
    else
        say("couldn't create the macro (the macro list may be full).")
    end
end

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
        if command.on ~= nil then setShowButton(command.on) end
        say("the Target button is " .. (showButton() and "on" or "off") .. ". /mobhunt button on|off to change it.")
    elseif command.action == "sound" then
        if command.on ~= nil then setPlaySound(command.on) end
        say("the alert sound is " .. (soundOn() and "on" or "off") .. ". /mobhunt sound on|off to change it.")
    elseif command.action == "window" then
        setShowWindow(not getShowWindow())
        say("the Hunt window is " .. (getShowWindow() and "shown" or "hidden") .. ".")
    elseif command.action == "options" then
        if ns.Options and ns.Options.Open then ns.Options.Open() end
    elseif command.action == "debug" then
        showDebug()
    elseif command.action == "macro" then
        createMacro()
    elseif command.action == "target" then
        -- Targeting is protected: it only runs from a click or keypress on a secure button, never
        -- from a slash command. A macro can click the button (shown or not) instead.
        say("addons can't target from a slash command. Type |cffffff00/mobhunt macro|r to make a MobHunter macro for your action bar (or bind a key under Keybindings > AddOns > MobHunter).")
    elseif command.action == "status" then
        say(hunted and ("hunting |cffffff00" .. hunted .. "|r.") or "not hunting anything. Type /mobhunt <mob name>.")
    else
        say("/mobhunt <mob name> to start, /mobhunt stop to cancel, /mobhunt window to show or hide the Hunt window, /mobhunt options.")
    end
end

ns.MobHunter = { Start = start, Stop = stop, Scan = scan, SetShowButton = setShowButton,
    GetShowButton = showButton, SetPlaySound = setPlaySound, GetPlaySound = soundOn, SetShowWindow = setShowWindow, GetShowWindow = getShowWindow, CreateMacro = createMacro, ShowDebug = showDebug }
