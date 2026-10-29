local addonName, ns = ...

local UI = {}
ns.UI = UI

local RADIUS = 70
local CHARTS = {
    { key = "roles",       title = "Roles (from notes)" },
    { key = "professions", title = "Professions (from notes)" },
    { key = "classes",     title = "Classes" },
    { key = "levels",      title = "Levels" },
}

local window

local function addTab(parent, x, width, onClick)
    local tab = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    tab:SetSize(width, 22)
    tab:SetPoint("TOPLEFT", x, -30)
    tab:SetScript("OnClick", onClick)
    return tab
end

-- Only one pane is shown at a time; hiding a pane also hides its pie lines,
-- which would otherwise draw over other frames. The active tab is disabled.
local TAB_NAMES = { "census", "finder", "logs" }

local function selectTab(f, name)
    f.activeTab = name
    for _, tabName in ipairs(TAB_NAMES) do
        local active = tabName == name
        f.panes[tabName]:SetShown(active)
        if active then
            f.tabs[tabName]:Disable()
        else
            f.tabs[tabName]:Enable()
        end
    end
end

local function addPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetPoint("TOPLEFT", 0, -58)
    pane:SetPoint("BOTTOMRIGHT", 0, 0)
    return pane
end

local function build()
    local f = CreateFrame("Frame", addonName .. "Window", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(880, 470)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())

    f.TitleText:SetText("Guild Census")

    f.tabs, f.panes = {}, {}
    local function addNamedTab(name, text, x, width)
        local tab = addTab(f, x, width, function() selectTab(f, name) end)
        tab:SetText(text)
        f.tabs[name] = tab
        return tab
    end
    f.censusTab = addNamedTab("census", "Census", 14, 100)
    f.finderTab = addNamedTab("finder", "Finder", 118, 100)
    f.logsTab = addNamedTab("logs", "Logs", 222, 120)

    f.censusPane = addPane(f)
    f.summary = f.censusPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.summary:SetPoint("TOPLEFT", 14, -4)

    f.charts = {}
    for i, def in ipairs(CHARTS) do
        local chart = ns.PieChart.Create(f.censusPane, def.title, RADIUS)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        chart:SetPoint("TOPLEFT", 16 + col * 430, -30 - row * 188)
        f.charts[def.key] = chart
    end

    f.finderPane = ns.Finder.Create(addPane(f))
    f.logsPane = ns.Logs.Create(addPane(f))
    f.panes.census, f.panes.finder, f.panes.logs = f.censusPane, f.finderPane, f.logsPane

    selectTab(f, "census")
    return f
end

function UI.Refresh()
    if not window or not window:IsShown() then return end

    local members = {}
    if not ns.demoMode and not IsInGuild() then
        window.summary:SetText("You are not in a guild.")
        UI.lastCensus = ns.Census.Build({}, ns.settings)
        for _, chart in pairs(window.charts) do chart:SetData({}) end
    else
        members = ns.Roster.Read()
        local census = ns.Census.Build(members, ns.settings)
        UI.lastCensus = census
        window.summary:SetText(string.format("%d guild members%s", census.total,
            ns.demoMode and " (demo data)" or ""))
        for key, chart in pairs(window.charts) do
            chart:SetData(census[key])
        end
    end

    window.finderPane:Update(members, ns.settings)
    window.logsTab:SetText(string.format("Logs (%d)", #UI.lastCensus.conflicts))
    window.logsPane:Update(UI.lastCensus)
end

function UI.Show()
    window = window or build()
    window:Show()
    ns.Roster.Request()
    UI.Refresh()
end

function UI.SelectTab(name)
    UI.Show()
    selectTab(window, name)
end

function UI.Toggle()
    if window and window:IsShown() then
        window:Hide()
    else
        UI.Show()
    end
end
