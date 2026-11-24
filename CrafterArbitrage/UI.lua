local addonName, ns = ...

-- The window: scan button, how to sell (vendor / auction house), which recipes to consider
-- (known / learnable / all), and the ranked list of crafts that pay.

local UI = {}
ns.UI = UI

local PAGE_SIZE = 12
local ROW_HEIGHT = 24
local FILTERS = { { "known", "Known" }, { "learnable", "Learnable" }, { "all", "All" } }

-- The table's columns, shared by the header and every row so they line up: x is from the table's left edge.
local COLUMNS = {
    { key = "name", title = "Recipe", x = 0, width = 205, justify = "LEFT" },
    { key = "crafts", title = "Crafts", x = 210, width = 50, justify = "RIGHT" },
    { key = "cost", title = "Cost", x = 265, width = 105, justify = "RIGHT" },
    { key = "profit", title = "Profit", x = 375, width = 105, justify = "RIGHT" },
    { key = "source", title = "Learn from", x = 495, width = 175, justify = "LEFT" },
}
-- What the columns say when the list is auctions under the vendor price.
local DEAL_TITLES = { name = "Item", crafts = "Units", cost = "Buy for", profit = "Profit", source = "Buy at / vendor pays" }
local TABLE_LEFT, TABLE_WIDTH = 14, 672
local TABLE_TOP = -184 -- y of the first row; the header sits just above

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

local function showDealTooltip(row, deal)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(deal.name)
    GameTooltip:AddLine(string.format("%d listed under the vendor price, cheapest %s each.", deal.units, ns.Format.Money(deal.cheapest)))
    GameTooltip:AddLine(string.format("Buying them all costs %s; a vendor pays %s each, %s.", ns.Format.Money(deal.cost),
        ns.Format.Money(deal.vendor), ns.Format.Money(deal.revenue)))
    GameTooltip:AddLine(string.format("Profit %s. Check the Auction House: the list is as old as the scan.", ns.Format.Money(deal.profit)))
    GameTooltip:Show()
end

local function showTooltip(row)
    local result = row.result
    if not result or not GameTooltip then return end
    if result.deal then return showDealTooltip(row, result.deal) end
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
    row:SetSize(TABLE_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", TABLE_LEFT, TABLE_TOP - (index - 1) * ROW_HEIGHT)
    row:EnableMouse(true)
    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    for _, column in ipairs(COLUMNS) do
        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", column.x, -5)
        fs:SetWidth(column.width)
        fs:SetJustifyH(column.justify)
        fs:SetWordWrap(false)
        row[column.key] = fs
    end
    return row
end

local function fillRow(row, result)
    row.result = result
    if not result then
        row:Hide()
        return
    end
    if result.deal then
        local d = result.deal
        row.name:SetText(d.name)
        row.crafts:SetText(tostring(d.units))
        row.cost:SetText(ns.Format.Money(d.cost))
        row.profit:SetText(ns.Format.Money(d.profit))
        row.source:SetText(ns.Format.Money(d.cheapest) .. " / " .. ns.Format.Money(d.vendor))
        row:Show()
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
    local deals = s.mode == "deals"
    window.modeButtons.crafts[deals and "Enable" or "Disable"](window.modeButtons.crafts)
    window.modeButtons.deals[deals and "Disable" or "Enable"](window.modeButtons.deals)
    for _, column in ipairs(COLUMNS) do
        window.headers[column.key]:SetText(deals and DEAL_TITLES[column.key] or column.title)
    end
    window.scanText:SetText(ns.Scanner.statusText and ns.Scanner.IsBusy() and ns.Scanner.statusText or scanAgeText())
    local pages = math.max(1, math.ceil(#results / PAGE_SIZE))
    page = math.max(1, math.min(page, pages))
    for i, row in ipairs(window.rows) do
        fillRow(row, results[(page - 1) * PAGE_SIZE + i])
    end
    window.pageText:SetText(string.format("Page %d of %d", page, pages))
    if deals then
        if not ns.Prices.HasScan() then
            window.summary:SetText("Scan the Auction House first: prices come from the scan.")
        elseif #results == 0 then
            window.summary:SetText("No auction is listed under its vendor price.")
        else
            window.summary:SetText(string.format("%d items are listed under the vendor price, best first.", #results))
        end
    elseif job then
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
    if s.mode == "deals" then
        job = nil
        results = {}
        for i, deal in ipairs(ns.Deals.List()) do results[i] = { deal = deal } end
        page = 1
        UI.Refresh()
        return
    end
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
    f:SetSize(TABLE_WIDTH + 2 * TABLE_LEFT + 6, 520)
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
    f.neutralBox = addCheckbox(f, "Neutral Auction House (15% cut)", 10, -84, function(on)
        settings().neutral = on
        UI.Recompute()
    end)
    f.bagsBox = addCheckbox(f, "Use reagents in my bags", 300, -84, function(on)
        settings().useBags = on
        UI.Recompute()
    end)

    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 14, -122)
    label:SetText("Recipes:")
    f.filterButtons = {}
    for i, def in ipairs(FILTERS) do
        local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        button:SetSize(90, 22)
        button:SetPoint("TOPLEFT", 74 + (i - 1) * 94, -118)
        button:SetText(def[2])
        button:SetScript("OnClick", function()
            settings().filter = def[1]
            UI.Recompute()
        end)
        f.filterButtons[def[1]] = button
    end
    f.modeButtons = {}
    for i, def in ipairs({ { "crafts", "Crafts" }, { "deals", "Under vendor price" } }) do
        local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        button:SetSize(i == 1 and 70 or 130, 22)
        button:SetPoint("TOPLEFT", i == 1 and 400 or 474, -118)
        button:SetText(def[2])
        button:SetScript("OnClick", function()
            settings().mode = def[1]
            UI.Recompute()
        end)
        f.modeButtons[def[1]] = button
    end
    f.summary = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.summary:SetPoint("TOPLEFT", 14, -150)

    f.headers = {}
    for _, column in ipairs(COLUMNS) do
        local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", TABLE_LEFT + column.x, TABLE_TOP + 16)
        title:SetWidth(column.width)
        title:SetJustifyH(column.justify)
        title:SetText(column.title)
        f.headers[column.key] = title
    end

    f.rows = {}
    for i = 1, PAGE_SIZE do
        f.rows[i] = addRow(f, i)
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
