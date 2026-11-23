local addonName, ns = ...

-- The window: scan button, how to sell (vendor / auction house), which recipes to consider
-- (known / learnable / all), and the ranked list of crafts that pay.

local UI = {}
ns.UI = UI

local PAGE_SIZE = 12
local ROW_HEIGHT = 24
local FILTERS = { { "known", "Known" }, { "learnable", "Learnable" }, { "all", "All" } }

local window, job, results, page = nil, nil, {}, 1

local function settings() return ns.settings end

local function addCheckbox(parent, text, x, y, onClick)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetPoint("TOPLEFT", x, y)
    box:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", x + 30, y - 6)
    label:SetText(text)
    return box
end

local function showTooltip(row)
    local result = row.result
    if not result or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(result.recipe.name)
    local e = result.eval
    GameTooltip:AddLine(string.format("%d crafts make %d x %s", e.crafts, e.units, ns.Format.ItemName(result.recipe.out[1])))
    for _, reagent in ipairs(result.recipe.r) do
        GameTooltip:AddLine(string.format("  %d x %s", reagent[2] * e.crafts, ns.Format.ItemName(reagent[1])))
    end
    GameTooltip:AddLine(string.format("Cost %s, sells for %s, profit %s", ns.Format.Money(e.cost), ns.Format.Money(e.revenue), ns.Format.Money(e.profit)))
    local why = { margin = "More crafts would not pay: reagents get dearer.", supply = "More crafts: not enough reagents listed.",
                  max = settings().channel == "ah" and "Limited to a share of what is already listed." or "Capped at 200 crafts." }
    if why[e.why] then GameTooltip:AddLine(why[e.why]) end
    for _, line in ipairs(ns.Format.SourceLines(result.recipe, result.status)) do GameTooltip:AddLine(line) end
    GameTooltip:Show()
end

local function addRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(600, ROW_HEIGHT)
    row:EnableMouse(true)
    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local function text(x, width, justify)
        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", x, -4)
        fs:SetWidth(width)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    row.name, row.crafts = text(0, 200), text(205, 40, "RIGHT")
    row.cost, row.profit, row.source = text(250, 90, "RIGHT"), text(345, 90, "RIGHT"), text(445, 155)
    return row
end

local function fillRow(row, result)
    row.result = result
    if not result then
        row:Hide()
        return
    end
    local e = result.eval
    row.name:SetText(result.recipe.name)
    row.crafts:SetText(tostring(e.crafts))
    row.cost:SetText(ns.Format.Money(e.cost))
    row.profit:SetText(ns.Format.Money(e.profit))
    row.source:SetText(ns.Format.Source(result.recipe, result.status))
    row:Show()
end

local function scanAgeText()
    local t = ns.Prices.ScanTime()
    if not t then return "No scan yet: open the Auction House and press Scan." end
    return "Prices from the scan " .. ns.Format.Age(time() - t) .. "."
end

function UI.Refresh()
    if not window then return end
    local s = settings()
    window.sellBox:SetChecked(s.channel == "ah")
    window.neutralBox:SetChecked(s.neutral and true or false)
    window.bagsBox:SetChecked(s.useBags and true or false)
    for _, f in ipairs(FILTERS) do
        local button = window.filterButtons[f[1]]
        if s.filter == f[1] then button:Disable() else button:Enable() end
    end
    window.scanText:SetText(ns.Scanner.statusText and ns.Scanner.IsBusy() and ns.Scanner.statusText or scanAgeText())
    local pages = math.max(1, math.ceil(#results / PAGE_SIZE))
    page = math.max(1, math.min(page, pages))
    for i, row in ipairs(window.rows) do
        fillRow(row, results[(page - 1) * PAGE_SIZE + i])
    end
    window.pageText:SetText(string.format("Page %d of %d", page, pages))
    if job then
        window.summary:SetText(string.format("Working it out: %d%%", math.floor(job.index / math.max(1, job.total) * 100)))
    elseif not ns.Prices.HasScan() then
        window.summary:SetText("Scan the Auction House first: prices come from the scan.")
    elseif #results == 0 then
        window.summary:SetText("Nothing pays with these prices and settings.")
    else
        window.summary:SetText(string.format("%d crafts pay, best first. Hover a row for details.", #results))
    end
end

-- Starts working the list out again (after a scan or a changed setting).
function UI.Recompute()
    if not window then return end
    local s = settings()
    job = ns.Engine.NewJob({
        channel = s.channel, filter = s.filter, neutral = s.neutral, useBags = s.useBags, minProfit = s.minProfit,
    })
    results, page = {}, 1
    UI.Refresh()
end

local function onUpdate()
    if not job then return end
    if job:Step() then
        results, job = job.results, nil
    end
    UI.Refresh()
end

local function build()
    local f = CreateFrame("Frame", addonName .. "Window", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(650, 480)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())
    f.TitleText:SetText("CrafterArbitrage")

    f.scanButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.scanButton:SetSize(80, 22)
    f.scanButton:SetPoint("TOPLEFT", 14, -32)
    f.scanButton:SetText("Scan")
    f.scanButton:SetScript("OnClick", function() ns.Scanner.Start(); UI.Refresh() end)
    f.scanText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.scanText:SetPoint("TOPLEFT", 104, -37)

    f.sellBox = addCheckbox(f, "Sell on the Auction House (otherwise to a vendor)", 10, -58, function(on)
        settings().channel = on and "ah" or "vendor"
        UI.Recompute()
    end)
    f.neutralBox = addCheckbox(f, "Neutral Auction House (15% cut)", 340, -58, function(on)
        settings().neutral = on
        UI.Recompute()
    end)
    f.bagsBox = addCheckbox(f, "Use reagents in my bags", 10, -84, function(on)
        settings().useBags = on
        UI.Recompute()
    end)

    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 14, -118)
    label:SetText("Recipes:")
    f.filterButtons = {}
    for i, def in ipairs(FILTERS) do
        local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        button:SetSize(90, 22)
        button:SetPoint("TOPLEFT", 74 + (i - 1) * 94, -114)
        button:SetText(def[2])
        button:SetScript("OnClick", function()
            settings().filter = def[1]
            UI.Recompute()
        end)
        f.filterButtons[def[1]] = button
    end
    f.summary = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.summary:SetPoint("TOPLEFT", 14, -142)

    local header = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 14, -164 - 0)
    header:SetText("Recipe                                              Crafts        Cost       Profit      Learn from")

    f.rows = {}
    for i = 1, PAGE_SIZE do
        f.rows[i] = addRow(f, i)
        f.rows[i]:SetPoint("TOPLEFT", 14, -178 - (i - 1) * ROW_HEIGHT)
    end

    f.prevButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.prevButton:SetSize(80, 22)
    f.prevButton:SetPoint("BOTTOMLEFT", 14, 12)
    f.prevButton:SetText("Previous")
    f.prevButton:SetScript("OnClick", function() page = page - 1; UI.Refresh() end)
    f.nextButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.nextButton:SetSize(80, 22)
    f.nextButton:SetPoint("BOTTOMLEFT", 100, 12)
    f.nextButton:SetText("Next")
    f.nextButton:SetScript("OnClick", function() page = page + 1; UI.Refresh() end)
    f.pageText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.pageText:SetPoint("BOTTOMLEFT", 190, 17)

    f:SetScript("OnUpdate", onUpdate)
    return f
end

function UI.Show()
    window = window or build()
    window:Show()
    UI.Recompute()
end

function UI.Toggle()
    if window and window:IsShown() then window:Hide() else UI.Show() end
end

-- A scan finished or its status changed.
function ns.OnScanDone() if window and window:IsShown() then UI.Recompute() end end
function ns.OnScanStatus() if window and window:IsShown() then UI.Refresh() end end

function UI.Results() return results end
function UI.Window() return window end

-- Tests put a list in place without running the engine.
function UI.SetResultsForTest(list)
    results, job, page = list, nil, 1
    UI.Refresh()
end
