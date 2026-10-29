local addonName, ns = ...

-- Two finders share the same results list, selectors, "Online only" checkbox and
-- Clear button:
--   Role Finder        role, dungeon / level range, online only
--   Profession Finder  profession, online only (levels and roles don't matter there)
local Finder = {}
ns.Finder = Finder

local ROW_HEIGHT = 16
local MAX_ROWS = 300 -- rows are pooled frames; cap them so a huge guild stays cheap
local LONG_MENU = 12 -- menus longer than this scroll instead of running off screen

local COLUMNS = {
    { key = "name", title = "Name", x = 0, width = 150 },
    { key = "level", title = "Level", x = 160, width = 50 },
    { key = "class", title = "Class", x = 220, width = 100 },
    { key = "roles", title = "Roles", x = 330, width = 120 },
    { key = "professions", title = "Professions", x = 460, width = 330 },
}

local function classColored(text, classFile)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not color then return text end
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5),
        math.floor(color.b * 255 + 0.5), text)
end

local function addLabel(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

-- onChange(self, userInput): userInput is false when the text is set from code.
local function addLevelBox(parent, x, y, onChange)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(36, 20)
    box:SetPoint("TOPLEFT", x, y)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    box:SetScript("OnTextChanged", onChange)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    return box
end

local function addRow(content, index)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(796, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    for _, column in ipairs(COLUMNS) do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", column.x, -2)
        fs:SetWidth(column.width)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row[column.key] = fs
    end
    return row
end

-- Creates a labelled selector with a fixed list of choices, so nothing is free text.
-- Blizzard's dropdown templates differ between clients, so try the modern one, then
-- the legacy one, and finally fall back to a button that cycles through the choices.
-- spec: { name, label, labelX, x, y, width, choices = { { label } }, getIndex(), onSelect(index) }
-- Returns { kind = "modern" | "legacy" | "cycle", widget, Refresh() }; call Refresh()
-- after changing the selection from code so the displayed text follows it.
local function createSelector(pane, spec)
    addLabel(pane, spec.label, spec.labelX, spec.y - 4)
    local choices = spec.choices
    local selector = {}

    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, pane, "WowStyle1DropdownTemplate")
    if ok and dropdown and dropdown.SetupMenu then
        dropdown:SetWidth(spec.width)
        dropdown:SetPoint("TOPLEFT", spec.x, spec.y)
        dropdown:SetupMenu(function(_, root)
            if #choices > LONG_MENU and root.SetScrollMode then root:SetScrollMode(300) end
            for i, choice in ipairs(choices) do
                root:CreateRadio(choice.label,
                    function() return spec.getIndex() == i end,
                    function() spec.onSelect(i) end)
            end
        end)
        selector.kind, selector.widget = "modern", dropdown
        function selector:Refresh() dropdown:GenerateMenu() end
        return selector
    end

    local okLegacy, legacy = pcall(CreateFrame, "Frame", addonName .. spec.name .. "Dropdown", pane,
        "UIDropDownMenuTemplate")
    if okLegacy and legacy and UIDropDownMenu_Initialize then
        legacy:SetPoint("TOPLEFT", spec.x - 16, spec.y + 2)
        UIDropDownMenu_SetWidth(legacy, spec.width - 30)
        UIDropDownMenu_Initialize(legacy, function()
            for i, choice in ipairs(choices) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = choice.label
                info.checked = spec.getIndex() == i
                info.func = function()
                    spec.onSelect(i)
                    selector:Refresh()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        selector.kind, selector.widget = "legacy", legacy
        function selector:Refresh() UIDropDownMenu_SetText(legacy, choices[spec.getIndex()].label) end
        selector:Refresh()
        return selector
    end

    local button = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    button:SetSize(spec.width, 22)
    button:SetPoint("TOPLEFT", spec.x, spec.y)
    button:SetScript("OnClick", function()
        spec.onSelect(spec.getIndex() % #choices + 1)
        selector:Refresh()
    end)
    selector.kind, selector.widget = "cycle", button
    function selector:Refresh() button:SetText(choices[spec.getIndex()].label) end
    selector:Refresh()
    return selector
end

-- `anyLabel` first, then one choice per definition (Config.ROLES / Config.PROFESSIONS).
local function choicesFor(defs, anyLabel)
    local choices = { { label = anyLabel } }
    for _, def in ipairs(defs) do
        choices[#choices + 1] = { key = def.key, label = def.label }
    end
    return choices
end

local function dungeonChoices()
    local choices = { { label = "Custom" } }
    for _, dungeon in ipairs(ns.Dungeons.LIST) do
        choices[#choices + 1] = {
            dungeon = dungeon,
            label = string.format("%s (%d-%d)", dungeon.name, dungeon.minLevel, dungeon.maxLevel),
        }
    end
    return choices
end

-- "Online only" checkbox: limits any search to members who are online.
local function addOnlineBox(pane, x, y)
    pane.onlineOnly = false
    pane.onlineBox = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
    pane.onlineBox:SetPoint("TOPLEFT", x, y + 2)
    pane.onlineBox:SetScript("OnClick", function(self)
        pane.onlineOnly = self:GetChecked() and true or false
        pane:Search()
    end)
    addLabel(pane, "Online only", x + 28, y - 6)
end

-- "Clear" button: puts every control back to its default (pane:Reset, defined by
-- each finder).
local function addClearButton(pane, x, y)
    pane.clearButton = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    pane.clearButton:SetSize(70, 22)
    pane.clearButton:SetPoint("TOPLEFT", x, y)
    pane.clearButton:SetText("Clear")
    pane.clearButton:SetScript("OnClick", function() pane:Reset() end)
end

-- Column headers and the pooled, scrolling results list. The finder must define
-- pane:Criteria() and pane.summary first. Adds pane:Search() and pane:Update().
local function addResults(pane, headerY, scrollY)
    for _, column in ipairs(COLUMNS) do
        addLabel(pane, column.title, 14 + column.x, headerY, "GameFontNormal")
    end

    pane.scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    pane.scroll:SetPoint("TOPLEFT", 14, scrollY)
    pane.scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    pane.content = CreateFrame("Frame", nil, pane.scroll)
    pane.content:SetSize(796, 1)
    pane.scroll:SetScrollChild(pane.content)
    pane.rows = {}

    function pane:Search()
        local results = ns.Census.Find(self.members, self:Criteria(), self.settings)
        local shown = math.min(#results, MAX_ROWS)

        for i = 1, shown do
            local row = self.rows[i] or addRow(self.content, i)
            self.rows[i] = row
            local r = results[i]
            row.name:SetText(classColored(r.name or "?", r.classFile))
            row.level:SetText(tostring(r.level or "?"))
            row.class:SetText(r.className or "?")
            row.roles:SetText(table.concat(r.roles, ", "))
            row.professions:SetText(table.concat(r.professions, ", "))
            row:Show()
        end
        for i = shown + 1, #self.rows do
            self.rows[i]:Hide()
        end
        self.content:SetHeight(math.max(1, shown * ROW_HEIGHT))

        if #results == 0 then
            self.summary:SetText("No players found.")
        elseif #results > shown then
            self.summary:SetText(string.format("Showing the first %d of %d players", shown, #results))
        else
            self.summary:SetText(string.format("%d player%s found", #results, #results == 1 and "" or "s"))
        end
    end

    -- Call whenever the roster or settings change.
    function pane:Update(members, settings)
        self.members, self.settings = members or {}, settings
        self:Search()
    end
end

-- Role Finder: fills `pane` (a Frame the caller has already sized and anchored) with
-- role, dungeon / level range and online-only controls above the results list.
function Finder.CreateRoles(pane)
    local roleChoices = choicesFor(ns.Config.ROLES, "Any")
    local dungeons = dungeonChoices()

    pane.roleIndex, pane.dungeonIndex = 1, 1
    pane.members, pane.settings = {}, nil
    pane.selectors = {}

    -- Row 1: who we are looking for.
    pane.selectors.role = createSelector(pane, {
        name = "Role", label = "Role:", labelX = 14, x = 52, y = -2, width = 110,
        choices = roleChoices,
        getIndex = function() return pane.roleIndex end,
        onSelect = function(index)
            pane.roleIndex = index
            pane:Search()
        end,
    })
    addOnlineBox(pane, 190, -2)
    addClearButton(pane, 320, -2)

    -- Row 2: where (a dungeon preset fills in the level range, which stays editable).
    local function selectDungeon(index)
        pane.dungeonIndex = index
        local dungeon = dungeons[index].dungeon
        if dungeon then
            pane.minBox:SetText(tostring(dungeon.minLevel))
            pane.maxBox:SetText(tostring(dungeon.maxLevel))
        end
        pane:Search()
    end
    pane.selectors.dungeon = createSelector(pane, {
        name = "Dungeon", label = "Dungeon:", labelX = 14, x = 70, y = -34, width = 200,
        choices = dungeons,
        getIndex = function() return pane.dungeonIndex end,
        onSelect = selectDungeon,
    })

    -- Typing a level by hand means the range no longer matches the dungeon.
    local function onLevelEdited(_, userInput)
        if userInput and pane.dungeonIndex ~= 1 then
            pane.dungeonIndex = 1
            pane.selectors.dungeon:Refresh()
        end
        pane:Search()
    end
    addLabel(pane, "Level:", 290, -38)
    pane.minBox = addLevelBox(pane, 332, -35, onLevelEdited)
    addLabel(pane, "to", 376, -38)
    pane.maxBox = addLevelBox(pane, 396, -35, onLevelEdited)

    pane.summary = addLabel(pane, "", 446, -38)

    -- Empty boxes mean "no bound"; tonumber("") is nil.
    function pane:Criteria()
        return {
            role = roleChoices[self.roleIndex].key,
            minLevel = tonumber(self.minBox:GetText()),
            maxLevel = tonumber(self.maxBox:GetText()),
            onlineOnly = self.onlineOnly or nil,
        }
    end

    function pane:Reset()
        self.roleIndex, self.dungeonIndex = 1, 1
        self.minBox:SetText("")
        self.maxBox:SetText("")
        self.onlineOnly = false
        self.onlineBox:SetChecked(false)
        for _, selector in pairs(self.selectors) do selector:Refresh() end
        self:Search()
    end

    addResults(pane, -66, -84)
    return pane
end

-- Profession Finder: fills `pane` with a profession selector and online-only. Level
-- ranges and roles are deliberately absent: when you want a crafter, only the
-- profession matters. "Any profession" lists everyone with at least one profession.
function Finder.CreateProfessions(pane)
    local professionChoices = choicesFor(ns.Config.PROFESSIONS, "Any profession")

    pane.professionIndex = 1
    pane.members, pane.settings = {}, nil
    pane.selectors = {}

    pane.selectors.profession = createSelector(pane, {
        name = "Profession", label = "Profession:", labelX = 14, x = 88, y = -2, width = 150,
        choices = professionChoices,
        getIndex = function() return pane.professionIndex end,
        onSelect = function(index)
            pane.professionIndex = index
            pane:Search()
        end,
    })
    addOnlineBox(pane, 262, -2)
    addClearButton(pane, 392, -2)

    pane.summary = addLabel(pane, "", 480, -6)

    function pane:Criteria()
        local key = professionChoices[self.professionIndex].key
        return {
            profession = key,
            hasProfession = key == nil or nil,
            onlineOnly = self.onlineOnly or nil,
        }
    end

    function pane:Reset()
        self.professionIndex = 1
        self.onlineOnly = false
        self.onlineBox:SetChecked(false)
        for _, selector in pairs(self.selectors) do selector:Refresh() end
        self:Search()
    end

    addResults(pane, -34, -52)
    return pane
end
