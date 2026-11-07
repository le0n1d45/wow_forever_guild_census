local _, ns = ...

-- The Hunt window: a box to type a mob's name (more boxes with "Add hunt"; a box also takes a
-- comma-separated list), Start and Stop, a status line, the sound checkbox and the Target
-- button (the secure button MobHunter.lua keeps armed). Whether the window is shown is a
-- setting (MobHunterDB.showHuntWindow); the options page and /mobhunt window both flip it.
local HuntWindow = {}
ns.HuntWindow = HuntWindow

local function db()
    MobHunterDB = MobHunterDB or {}
    return MobHunterDB
end

local MAX_ROWS = 8
local ROW_HEIGHT = 26
local TOP = 36 -- where the first text box sits, below the title
local MAX_SUGGESTIONS = 6 -- quest targets listed at most
local SUGGEST_HEIGHT = 22

-- callbacks: onStart(text) (the boxes' text joined with commas), onStop(), onSound(on),
-- isSound(), onSuggest(name) (a quest target was clicked). Returns { frame, edit (the first box), rows, status, targetButton, sound, ... }.
function HuntWindow.Create(callbacks)
    local frame = CreateFrame("Frame", "MobHunterHuntFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 194)
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

    local window = { frame = frame, rows = {}, count = 1 }
    local startButton, stopButton, addButton, status, sound, soundLabel, targetButton
    local suggestHeader
    window.suggestions, window.suggestButtons = {}, {}

    local function texts()
        local list = {}
        for i = 1, window.count do list[#list + 1] = window.rows[i].edit:GetText() or "" end
        return table.concat(list, ",")
    end

    local function start()
        local text = texts()
        if text:gsub("[%s,]", "") ~= "" then callbacks.onStart(text) end
        for i = 1, window.count do window.rows[i].edit:ClearFocus() end
    end

    -- Everything below the boxes moves down as boxes are added, and the window grows with it.
    local function layout()
        for i, row in ipairs(window.rows) do
            if i <= window.count then
                row.edit:ClearAllPoints()
                row.edit:SetPoint("TOPLEFT", 20, -(TOP + (i - 1) * ROW_HEIGHT))
                row.edit:Show()
                if row.remove then row.remove:Show() end
            else
                row.edit:Hide()
                if row.remove then row.remove:Hide() end
            end
        end
        local below = TOP + window.count * ROW_HEIGHT
        addButton:ClearAllPoints()
        addButton:SetPoint("TOPLEFT", 20, -below)
        addButton:SetShown(window.count < MAX_ROWS)
        status:ClearAllPoints()
        status:SetPoint("TOPLEFT", 22, -(below + 28))
        sound:ClearAllPoints()
        sound:SetPoint("TOPLEFT", 16, -(below + 48))
        -- Quest targets, when there are any, sit between the sound checkbox and the Target button.
        local count = math.min(#window.suggestions, MAX_SUGGESTIONS)
        local listTop = below + 48 + 28
        suggestHeader:ClearAllPoints()
        suggestHeader:SetPoint("TOPLEFT", 22, -listTop)
        suggestHeader:SetShown(count > 0)
        for i, button in ipairs(window.suggestButtons) do
            if i <= count then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", 20, -(listTop + 16 + (i - 1) * SUGGEST_HEIGHT))
                button:Show()
            else
                button:Hide()
            end
        end
        local suggestSpace = count > 0 and (16 + count * SUGGEST_HEIGHT + 8) or 0
        frame:SetHeight(below + 48 + 28 + suggestSpace + 12 + 28 + 16)
    end

    local function newRow(i)
        local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        edit:SetSize(170, 22)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(80)
        edit:SetScript("OnEnterPressed", start)
        edit:SetScript("OnEscapePressed", edit.ClearFocus)
        local row = { edit = edit }
        if i > 1 then
            -- A small button that drops this box (the ones below move up).
            local remove = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            remove:SetSize(22, 22)
            remove:SetPoint("LEFT", edit, "RIGHT", 6, 0)
            remove:SetText("x")
            remove:SetScript("OnClick", function()
                for j = i, window.count - 1 do
                    window.rows[j].edit:SetText(window.rows[j + 1].edit:GetText() or "")
                end
                window.rows[window.count].edit:SetText("")
                window.count = window.count - 1
                layout()
            end)
            row.remove = remove
        end
        window.rows[i] = row
        return row
    end

    local first = newRow(1)
    window.edit = first.edit

    startButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    startButton:SetSize(50, 22)
    startButton:SetPoint("LEFT", first.edit, "RIGHT", 6, 0)
    startButton:SetText("Start")
    startButton:SetScript("OnClick", start)
    stopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stopButton:SetSize(50, 22)
    stopButton:SetPoint("LEFT", startButton, "RIGHT", 2, 0)
    stopButton:SetText("Stop")
    stopButton:SetScript("OnClick", function() callbacks.onStop() end)

    addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addButton:SetSize(110, 22)
    addButton:SetText("Add hunt")
    addButton:SetScript("OnClick", function()
        if window.count >= MAX_ROWS then return end
        window.count = window.count + 1
        local row = window.rows[window.count] or newRow(window.count)
        row.edit:SetText("")
        layout()
        row.edit:SetFocus()
    end)

    status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    status:SetText("Not hunting.")

    sound = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    sound:SetScript("OnClick", function(self) callbacks.onSound(self:GetChecked() and true or false) end)
    soundLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    soundLabel:SetPoint("LEFT", sound, "RIGHT", 2, 1)
    soundLabel:SetText("Play a sound when found")

    suggestHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    suggestHeader:SetText("Quest targets (click to hunt):")
    suggestHeader:Hide()

    targetButton = CreateFrame("Button", "MobHunterTargetButton", frame, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    targetButton:SetSize(260, 28)
    targetButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
    targetButton:RegisterForClicks("AnyUp", "AnyDown") -- the ActionButtonUseKeyDown setting picks which one fires
    targetButton:Hide()

    window.startButton, window.stopButton, window.addButton = startButton, stopButton, addButton
    window.status, window.sound, window.targetButton = status, sound, targetButton
    window.Layout = layout

    function window.SetSound(on) sound:SetChecked(on and true or false) end
    frame:HookScript("OnShow", function() window.SetSound(callbacks.isSound()) end)

    -- names: the list being hunted, or nil when not hunting. The boxes show one name each.
    function window.SetHunting(names)
        if names and #names > 0 then
            status:SetText("Hunting: |cffffff00" .. table.concat(names, ", ") .. "|r")
            window.count = math.min(#names, MAX_ROWS)
            for i = 1, window.count do
                local row = window.rows[i] or newRow(i)
                row.edit:SetText(names[i])
            end
            layout()
        else
            status:SetText("Not hunting.")
        end
    end

    -- list: { { name, quest } } from Quests.Suggest; nil or empty hides the section.
    function window.SetSuggestions(list)
        window.suggestions = list or {}
        for i = 1, math.min(#window.suggestions, MAX_SUGGESTIONS) do
            local button = window.suggestButtons[i]
            if not button then
                button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                button:SetSize(260, 20)
                window.suggestButtons[i] = button
            end
            local entry = window.suggestions[i]
            button.suggestion = entry
            button:SetText(entry.name .. (entry.quest and ("  (" .. entry.quest .. ")") or ""))
            button:SetScript("OnClick", function() callbacks.onSuggest(entry.name) end)
        end
        layout()
    end

    layout()
    return window
end

function HuntWindow.ShouldShow()
    return db().showHuntWindow == true
end
