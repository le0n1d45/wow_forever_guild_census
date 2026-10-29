local addonName, ns = ...

local Options = {}
ns.Options = Options

local category

local function addLabel(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function addEditBox(parent, x, y, width, onChange)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22)
    box:SetPoint("TOPLEFT", x, y)
    box:SetAutoFocus(false)
    box:SetMaxLetters(500)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then onChange(self:GetText()) end
    end)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    return box
end

-- Rows of "Label: [textbox]" bound to settings[group][def.key].
local function addRuleRows(panel, group, defs, columns, startY, boxWidth)
    local rowHeight, columnWidth = 28, 270
    for i, def in ipairs(defs) do
        local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
        local x, y = 16 + col * columnWidth, startY - row * rowHeight
        addLabel(panel, def.label .. ":", x, y - 4)
        panel.controls[group][def.key] = addEditBox(panel, x + 100, y, boxWidth, function(text)
            ns.settings[group][def.key] = text
            ns.UI.Refresh()
        end)
    end
    return startY - math.ceil(#defs / columns) * rowHeight
end

local function build()
    local panel = CreateFrame("Frame", addonName .. "OptionsPanel")
    panel.name = "Guild Census"
    panel.controls = { identity = {}, roles = {}, professions = {} }

    addLabel(panel, "Guild Census", 16, -16, "GameFontNormalLarge")

    local function addCheckbox(setting, text, y)
        local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", 12, y)
        box:SetScript("OnClick", function(self)
            ns.settings[setting] = self:GetChecked() and true or false
            ns.UI.Refresh()
        end)
        panel.controls[setting] = box
        addLabel(panel, text, 44, y - 6)
    end
    addCheckbox("includeAlts", "Include alts", -44)
    addCheckbox("onlyMains", "Include ONLY mains declared within guild notes", -72)

    local y = -110
    addLabel(panel, "Alt/Main Detection (comma-separated list)", 16, y, "GameFontNormal")
    y = addRuleRows(panel, "identity", ns.Config.IDENTITY, 1, y - 24, 400)

    y = y - 16
    addLabel(panel, "Role Detection (comma-separated list)", 16, y, "GameFontNormal")
    y = addRuleRows(panel, "roles", ns.Config.ROLES, 1, y - 24, 400)

    y = y - 16
    addLabel(panel, "Profession Detection (comma-separated list)", 16, y, "GameFontNormal")
    y = addRuleRows(panel, "professions", ns.Config.PROFESSIONS, 2, y - 24, 150)

    local function populate()
        local s = ns.settings
        panel.controls.includeAlts:SetChecked(s.includeAlts)
        panel.controls.onlyMains:SetChecked(s.onlyMains)
        for group, defs in pairs({
            identity = ns.Config.IDENTITY,
            roles = ns.Config.ROLES,
            professions = ns.Config.PROFESSIONS,
        }) do
            for _, def in ipairs(defs) do
                local box = panel.controls[group][def.key]
                box:SetText(s[group][def.key])
                box:SetCursorPosition(0)
            end
        end
    end

    local function reset()
        ns.Config.Reset(ns.settings)
        populate()
        ns.UI.Refresh()
    end

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(160, 24)
    resetButton:SetPoint("TOPLEFT", 16, y - 16)
    resetButton:SetText("Reset to defaults")
    resetButton:SetScript("OnClick", reset)
    panel.controls.reset = resetButton

    panel.OnDefault = reset
    panel:SetScript("OnShow", populate)
    populate()
    return panel
end

-- Call once ns.settings is initialised (after ADDON_LOADED).
function Options.Register()
    local panel = build()
    Options.panel = panel

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function Options.Open()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Known quirk: the first call only opens the frame on some clients.
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
        InterfaceOptionsFrame_OpenToCategory(Options.panel)
    end
end
