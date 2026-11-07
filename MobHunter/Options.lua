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

    local function addCheckbox(key, text, y, hintText, onChange)
        local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        box:SetPoint("TOPLEFT", 12, y)
        box:SetScript("OnClick", function(self) onChange(self:GetChecked() and true or false) end)
        panel.controls[key] = box
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("TOPLEFT", 44, y - 6)
        label:SetText(text)
        if hintText then
            local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            hint:SetPoint("TOPLEFT", 44, y - 28)
            hint:SetText(hintText)
        end
        return box
    end
    local windowBox = addCheckbox("showWindow", "Show the Hunt window", -44,
        "A small window to type a mob's name, Start/Stop, and the Target button.",
        function(on) ns.MobHunter.SetShowWindow(on) end)
    local buttonBox = addCheckbox("showButton", "Show the Target button in the Hunt window", -88,
        "Turned off, the key binding and the action bar macro still work.",
        function(on) ns.MobHunter.SetShowButton(on) end)
    local soundBox = addCheckbox("playSound", "Play a sound when a hunted mob is found", -132, nil,
        function(on) ns.MobHunter.SetPlaySound(on) end)

    local suggestBox = addCheckbox("showSuggestions", "Suggest hunt targets from my quests", -176,
        "Lists mobs from kill and item objectives in the Hunt window. Item drops need the QuestieDB addon, or are learned by looting.",
        function(on) ns.MobHunter.SetShowSuggestions(on) end)
    local autoBox = addCheckbox("autoAdd", "Hunt the suggested quest targets automatically", -220, nil,
        function(on) ns.MobHunter.SetAutoAdd(on) end)

    local function addButton(key, text, x, y, width, onClick)
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(width, 24)
        button:SetPoint("TOPLEFT", x, y)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        panel.controls[key] = button
        return button
    end

    addButton("macro", "Create the MobHunter macro", 16, -264, 220, function() ns.MobHunter.CreateMacro() end)
    addButton("debug", "Minimap debug info", 244, -264, 160, function() ns.MobHunter.ShowDebug() end)

    local function populate()
        windowBox:SetChecked(ns.MobHunter.GetShowWindow())
        buttonBox:SetChecked(ns.MobHunter.GetShowButton())
        soundBox:SetChecked(ns.MobHunter.GetPlaySound())
        suggestBox:SetChecked(ns.MobHunter.GetShowSuggestions())
        autoBox:SetChecked(ns.MobHunter.GetAutoAdd())
    end
    panel.OnDefault = function()
        ns.MobHunter.SetShowWindow(false)
        ns.MobHunter.SetShowButton(true)
        ns.MobHunter.SetPlaySound(true)
        ns.MobHunter.SetShowSuggestions(true)
        ns.MobHunter.SetAutoAdd(false)
        populate()
    end
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
