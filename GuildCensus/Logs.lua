local addonName, ns = ...

local Logs = {}
ns.Logs = Logs

local window

-- "|" starts an escape sequence in WoW strings, so notes must double it.
local function escape(text)
    return (string.gsub(text, "|", "||"))
end

function Logs.FormatEntry(conflict)
    return string.format("|cffffd100%s|r (%s %s): %s\n    Note: \"%s\"",
        escape(conflict.name),
        conflict.level and ("L" .. conflict.level) or "L?",
        conflict.className or "?",
        conflict.message,
        escape(conflict.note))
end

function Logs.FormatAll(conflicts)
    if #conflicts == 0 then return "No conflicts detected." end
    local entries = {}
    for i, conflict in ipairs(conflicts) do
        entries[i] = Logs.FormatEntry(conflict)
    end
    return table.concat(entries, "\n\n")
end

local function build()
    local f = CreateFrame("Frame", addonName .. "LogsWindow", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(620, 420)
    f:SetPoint("CENTER", 60, -30)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())

    f.TitleText:SetText("Census Logs")

    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.summary:SetPoint("TOPLEFT", 14, -34)

    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 14, -56)
    f.scroll:SetPoint("BOTTOMRIGHT", -34, 14)

    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(556, 1)
    f.scroll:SetScrollChild(f.content)

    f.text = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT")
    f.text:SetWidth(556)
    f.text:SetJustifyH("LEFT")
    return f
end

function Logs.Refresh()
    if not window or not window:IsShown() then return end

    local census = ns.UI.lastCensus
    local conflicts = census and census.conflicts or {}
    window.summary:SetText(string.format("%d conflict%s among %d guild members",
        #conflicts, #conflicts == 1 and "" or "s", census and census.memberCount or 0))
    window.text:SetText(Logs.FormatAll(conflicts))
    window.content:SetHeight(window.text:GetStringHeight() + 8)
end

function Logs.Toggle()
    window = window or build()
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        Logs.Refresh()
    end
end
