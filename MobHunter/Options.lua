local addonName, ns = ...

-- The addon's page in the game's options window (Settings on current clients, the old
-- Interface Options where that's all there is). Same registration as Guild Census.
local Options = {}
ns.Options = Options

local category

local function build()
    local panel = CreateFrame("Frame", addonName .. "OptionsPanel")
    panel.name = "MobHunter"
    panel.controls = {}

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("MobHunter")

    local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    box:SetPoint("TOPLEFT", 12, -44)
    box:SetScript("OnClick", function(self)
        ns.MobHunter.SetShowButton(self:GetChecked() and true or false)
    end)
    panel.controls.showButton = box
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 44, -50)
    label:SetText("Show the Target button when a hunted mob is in range")

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 44, -76)
    hint:SetText("Turned off, the key binding and the action bar macro still work.")

    local function addButton(key, text, x, y, width, onClick)
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(width, 24)
        button:SetPoint("TOPLEFT", x, y)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        panel.controls[key] = button
        return button
    end

    -- Hunting without a slash command: type a name, press Start.
    local huntLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    huntLabel:SetPoint("TOPLEFT", 16, -120)
    huntLabel:SetText("Hunt a mob (part of the name is enough)")
    local name = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    name:SetSize(220, 22)
    name:SetPoint("TOPLEFT", 22, -144)
    name:SetAutoFocus(false)
    name:SetMaxLetters(80)
    local function startHunt()
        local text = name:GetText()
        if text and text ~= "" then ns.MobHunter.Start(ns.Hunt.Normalize(text)) end
        name:ClearFocus()
    end
    name:SetScript("OnEnterPressed", startHunt)
    name:SetScript("OnEscapePressed", name.ClearFocus)
    panel.controls.huntName = name
    addButton("start", "Start", 252, -143, 70, startHunt)
    addButton("stop", "Stop", 328, -143, 70, function() ns.MobHunter.Stop() end)

    addButton("macro", "Create the MobHunter macro", 16, -190, 220, function() ns.MobHunter.CreateMacro() end)
    addButton("debug", "Minimap debug info", 244, -190, 160, function() ns.MobHunter.ShowDebug() end)

    local function populate()
        box:SetChecked(ns.MobHunter.GetShowButton())
    end
    panel.OnDefault = function() ns.MobHunter.SetShowButton(true); populate() end
    panel:SetScript("OnShow", populate)
    populate()
    return panel
end

-- Call once MobHunterDB is initialised (after ADDON_LOADED).
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
