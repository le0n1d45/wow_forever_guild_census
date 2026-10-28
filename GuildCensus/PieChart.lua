local _, ns = ...

local PieChart = {}
ns.PieChart = PieChart

local SEGMENTS = 360
local MAX_LEGEND = 14

local PALETTE = {
    { 0.20, 0.60, 0.86 }, { 0.90, 0.30, 0.24 }, { 0.18, 0.80, 0.44 },
    { 0.95, 0.77, 0.06 }, { 0.61, 0.35, 0.71 }, { 0.90, 0.49, 0.13 },
    { 0.10, 0.74, 0.61 }, { 0.91, 0.12, 0.39 }, { 0.50, 0.55, 0.55 },
    { 0.55, 0.76, 0.29 }, { 0.40, 0.23, 0.72 }, { 0.80, 0.60, 0.40 },
}

local function sliceColor(slice, index)
    if slice.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[slice.classFile] then
        local c = RAID_CLASS_COLORS[slice.classFile]
        return c.r, c.g, c.b
    end
    local c = PALETTE[(index - 1) % #PALETTE + 1]
    return c[1], c[2], c[3]
end

-- WoW has no native pie widget, so the disc is drawn as SEGMENTS thin lines
-- radiating from the centre. This needs no texture assets.
local function setWedge(line, canvas, degree, radius)
    local angle = math.rad(degree)
    line:SetStartPoint("CENTER", canvas, 0, 0)
    line:SetEndPoint("CENTER", canvas, radius * math.sin(angle), radius * math.cos(angle))
end

function PieChart.Create(parent, title, radius)
    local chart = CreateFrame("Frame", nil, parent)
    chart:SetSize(radius * 2 + 190, radius * 2 + 24)

    chart.title = chart:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chart.title:SetPoint("TOPLEFT", 0, 0)
    chart.title:SetText(title)

    local canvas = CreateFrame("Frame", nil, chart)
    canvas:SetSize(radius * 2, radius * 2)
    canvas:SetPoint("TOPLEFT", 0, -22)

    local thickness = math.max(2, 2 * math.pi * radius / SEGMENTS * 1.6)
    local lines = {}
    for i = 1, SEGMENTS do
        local line = canvas:CreateLine(nil, "ARTWORK")
        line:SetThickness(thickness)
        setWedge(line, canvas, (i - 0.5) * 360 / SEGMENTS, radius)
        line:Hide()
        lines[i] = line
    end

    chart.empty = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    chart.empty:SetPoint("CENTER")
    chart.empty:SetText("No data")

    local legend = {}
    for i = 1, MAX_LEGEND do
        local text = chart:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", canvas, "TOPRIGHT", 10, -(i - 1) * 14)
        text:SetJustifyH("LEFT")
        text:Hide()
        legend[i] = text
    end

    chart.lines, chart.legend = lines, legend

    -- slices: list of { label, count, classFile? }
    function chart:SetData(slices)
        local total = 0
        for _, slice in ipairs(slices) do total = total + slice.count end

        self.empty:SetShown(total == 0)
        for _, text in ipairs(legend) do text:Hide() end
        for _, line in ipairs(lines) do line:Hide() end
        if total == 0 then return end

        local boundary, index = 0, 1
        local colors = {}
        for i, slice in ipairs(slices) do
            local r, g, b = sliceColor(slice, i)
            colors[i] = { r, g, b }
        end

        for i = 1, SEGMENTS do
            local midpoint = (i - 0.5) / SEGMENTS
            while index < #slices and midpoint > boundary + slices[index].count / total do
                boundary = boundary + slices[index].count / total
                index = index + 1
            end
            local c = colors[index]
            lines[i]:SetColorTexture(c[1], c[2], c[3], 1)
            lines[i]:Show()
        end

        for i, slice in ipairs(slices) do
            local text = legend[i]
            if not text then break end
            local c = colors[i]
            text:SetText(string.format("|cff%02x%02x%02x■|r %s: %d (%d%%)",
                c[1] * 255, c[2] * 255, c[3] * 255,
                slice.label, slice.count, math.floor(slice.count / total * 100 + 0.5)))
            text:Show()
        end
    end

    return chart
end
