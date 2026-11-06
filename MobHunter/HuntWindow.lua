local _, ns = ...

-- The Hunt window: a box to type the mob's name, Start and Stop, a status line, and the Target
-- button (the secure button MobHunter.lua keeps armed). Whether the window is shown is a
-- setting (MobHunterDB.showHuntWindow); the options page and /mobhunt window both flip it.
local HuntWindow = {}
ns.HuntWindow = HuntWindow

local function db()
    MobHunterDB = MobHunterDB or {}
    return MobHunterDB
end

-- callbacks: onStart(text), onStop(), onSound(on), isSound(). Returns { frame, edit, status, targetButton }.
function HuntWindow.Create(callbacks)
    local frame = CreateFrame("Frame", "MobHunterHuntFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 175)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if type(frame.TitleText) == "table" then frame.TitleText:SetText("MobHunter") end
    -- Closing it (the X) is the same as unticking it in the options.
    frame:SetScript("OnShow", function() db().showHuntWindow = true end)
    frame:SetScript("OnHide", function() db().showHuntWindow = false end)

    local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    edit:SetSize(170, 22)
    edit:SetPoint("TOPLEFT", 20, -36)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(80)
    local function start()
        local text = edit:GetText()
        if text and text ~= "" then callbacks.onStart(text) end
        edit:ClearFocus()
    end
    edit:SetScript("OnEnterPressed", start)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)

    local startButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    startButton:SetSize(50, 22)
    startButton:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    startButton:SetText("Start")
    startButton:SetScript("OnClick", start)
    local stopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stopButton:SetSize(50, 22)
    stopButton:SetPoint("LEFT", startButton, "RIGHT", 2, 0)
    stopButton:SetText("Stop")
    stopButton:SetScript("OnClick", function() callbacks.onStop() end)

    local status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    status:SetPoint("TOPLEFT", 22, -66)
    status:SetText("Not hunting.")

    local sound = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    sound:SetPoint("TOPLEFT", 16, -86)
    sound:SetScript("OnClick", function(self) callbacks.onSound(self:GetChecked() and true or false) end)
    local soundLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    soundLabel:SetPoint("LEFT", sound, "RIGHT", 2, 1)
    soundLabel:SetText("Play a sound when found")

    local targetButton = CreateFrame("Button", "MobHunterTargetButton", frame, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    targetButton:SetSize(260, 28)
    targetButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
    targetButton:RegisterForClicks("AnyUp", "AnyDown") -- the ActionButtonUseKeyDown setting picks which one fires
    targetButton:Hide()

    local window = { frame = frame, edit = edit, status = status, targetButton = targetButton, sound = sound }

    function window.SetSound(on) sound:SetChecked(on and true or false) end
    frame:HookScript("OnShow", function() window.SetSound(callbacks.isSound()) end)

    function window.SetHunting(name)
        status:SetText(name and ("Hunting: |cffffff00" .. name .. "|r") or "Not hunting.")
        if name then edit:SetText(name) end
    end
    return window
end

function HuntWindow.ShouldShow()
    return db().showHuntWindow == true
end
