local _, ns = ...

local Logs = {}
ns.Logs = Logs

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

-- Fills `pane` (a Frame the caller has already sized and anchored) with the
-- conflicts summary and a scrolling list. Call pane:Update(census) to refresh.
function Logs.Create(pane)
    pane.summary = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pane.summary:SetPoint("TOPLEFT", 14, -4)

    pane.scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    pane.scroll:SetPoint("TOPLEFT", 14, -30)
    pane.scroll:SetPoint("BOTTOMRIGHT", -34, 14)

    pane.content = CreateFrame("Frame", nil, pane.scroll)
    pane.content:SetSize(800, 1)
    pane.scroll:SetScrollChild(pane.content)

    pane.text = pane.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pane.text:SetPoint("TOPLEFT")
    pane.text:SetWidth(796)
    pane.text:SetJustifyH("LEFT")

    function pane:Update(census)
        local conflicts = census and census.conflicts or {}
        self.summary:SetText(string.format("%d conflict%s among %d guild members",
            #conflicts, #conflicts == 1 and "" or "s", census and census.memberCount or 0))
        self.text:SetText(Logs.FormatAll(conflicts))
        self.content:SetHeight(self.text:GetStringHeight() + 8)
    end

    return pane
end
