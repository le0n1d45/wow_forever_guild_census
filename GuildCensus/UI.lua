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

local function build()
    local f = CreateFrame("Frame", addonName .. "Window", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(880, 440)
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

    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.summary:SetPoint("TOPLEFT", 14, -34)

    f.charts = {}
    for i, def in ipairs(CHARTS) do
        local chart = ns.PieChart.Create(f, def.title, RADIUS)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        chart:SetPoint("TOPLEFT", 16 + col * 430, -60 - row * 190)
        f.charts[def.key] = chart
    end
    return f
end

function UI.Refresh()
    if not window or not window:IsShown() then return end

    if not ns.demoMode and not IsInGuild() then
        window.summary:SetText("You are not in a guild.")
        for _, chart in pairs(window.charts) do chart:SetData({}) end
        return
    end

    local census = ns.Census.Build(ns.Roster.Read())
    window.summary:SetText(string.format("%d guild members%s", census.total,
        ns.demoMode and " (demo data)" or ""))
    for key, chart in pairs(window.charts) do
        chart:SetData(census[key])
    end
end

function UI.Show()
    window = window or build()
    window:Show()
    ns.Roster.Request()
    UI.Refresh()
end

function UI.Toggle()
    if window and window:IsShown() then
        window:Hide()
    else
        UI.Show()
    end
end
