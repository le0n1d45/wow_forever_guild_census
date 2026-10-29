local addonName, ns = ...

local Finder = {}
ns.Finder = Finder

local ROW_HEIGHT = 16
local MAX_ROWS = 300 -- rows are pooled frames; cap them so a huge guild stays cheap

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

local function addLevelBox(parent, x, onChange)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(36, 20)
    box:SetPoint("TOPLEFT", x, -3)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    box:SetScript("OnTextChanged", function() onChange() end)
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

-- Creates the role selector: a real dropdown with fixed choices. Blizzard's
-- dropdown templates differ between clients, so try the modern one, then the
-- legacy one, and finally fall back to a button that cycles through the choices.
-- Returns the kind ("modern" | "legacy" | "cycle") and the widget.
local function createRoleSelector(pane, choices, selectRole)
    addLabel(pane, "Role:", 14, -6)

    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, pane, "WowStyle1DropdownTemplate")
    if ok and dropdown and dropdown.SetupMenu then
        dropdown:SetWidth(120)
        dropdown:SetPoint("TOPLEFT", 52, -2)
        dropdown:SetupMenu(function(_, root)
            for i, choice in ipairs(choices) do
                root:CreateRadio(choice.label,
                    function() return pane.roleIndex == i end,
                    function() selectRole(i) end)
            end
        end)
        return "modern", dropdown
    end

    local okLegacy, legacy = pcall(CreateFrame, "Frame", addonName .. "RoleDropdown", pane, "UIDropDownMenuTemplate")
    if okLegacy and legacy and UIDropDownMenu_Initialize then
        legacy:SetPoint("TOPLEFT", 36, 2)
        UIDropDownMenu_SetWidth(legacy, 90)
        UIDropDownMenu_SetText(legacy, choices[1].label)
        UIDropDownMenu_Initialize(legacy, function()
            for i, choice in ipairs(choices) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = choice.label
                info.checked = pane.roleIndex == i
                info.func = function()
                    selectRole(i)
                    UIDropDownMenu_SetText(legacy, choice.label)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        return "legacy", legacy
    end

    local button = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    button:SetSize(90, 22)
    button:SetPoint("TOPLEFT", 52, -2)
    button:SetText(choices[1].label)
    button:SetScript("OnClick", function()
        local index = pane.roleIndex % #choices + 1
        button:SetText(choices[index].label)
        selectRole(index)
    end)
    return "cycle", button
end

-- Fills `pane` (a Frame the caller has already sized and anchored) with the
-- finder: role/level controls above a scrolling list of matching members.
-- Call pane:Update(members, settings) whenever the roster or settings change.
function Finder.Create(pane)
    -- Role choices: "Any" first, then each configured role.
    local choices = { { label = "Any" } }
    for _, def in ipairs(ns.Config.ROLES) do
        choices[#choices + 1] = { key = def.key, label = def.label }
    end
    pane.roleIndex = 1
    pane.members, pane.settings = {}, nil

    pane.roleControl, pane.roleWidget = createRoleSelector(pane, choices, function(index)
        pane.roleIndex = index
        pane:Search()
    end)

    addLabel(pane, "Level:", 190, -6)
    pane.minBox = addLevelBox(pane, 232, function() pane:Search() end)
    addLabel(pane, "to", 276, -6)
    pane.maxBox = addLevelBox(pane, 296, function() pane:Search() end)

    pane.summary = addLabel(pane, "", 346, -6)

    for _, column in ipairs(COLUMNS) do
        addLabel(pane, column.title, 14 + column.x, -34, "GameFontNormal")
    end

    pane.scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    pane.scroll:SetPoint("TOPLEFT", 14, -52)
    pane.scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    pane.content = CreateFrame("Frame", nil, pane.scroll)
    pane.content:SetSize(796, 1)
    pane.scroll:SetScrollChild(pane.content)
    pane.rows = {}

    -- Empty boxes mean "no bound"; tonumber("") is nil.
    function pane:Criteria()
        return {
            role = choices[self.roleIndex].key,
            minLevel = tonumber(self.minBox:GetText()),
            maxLevel = tonumber(self.maxBox:GetText()),
        }
    end

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

    function pane:Update(members, settings)
        self.members, self.settings = members or {}, settings
        self:Search()
    end

    return pane
end
