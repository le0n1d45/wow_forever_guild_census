local addonName, ns = ...

-- Auctions listed for less than a vendor pays for the item: buy them out, sell them to a vendor. The scanner
-- offers every listing to Consider; Finish turns what it kept into the list the window shows, best first.

local Deals = {}
ns.Deals = Deals

local MAX_DEALS = 200
local MIN_PROFIT = 1 -- copper over all the listings of an item

local list = {} -- { { itemID, name, units, cost, revenue, profit, cheapest, vendor }, ... } best first
local byItem, vendorPrices -- while a scan is read

function Deals.Begin()
    byItem, vendorPrices = {}, {}
end

local function vendorPrice(itemID)
    local price = vendorPrices[itemID]
    if price == nil then
        price = ns.Calc.VendorPrice(itemID) or false -- false: not known (yet), remembered so it is asked once
        vendorPrices[itemID] = price
    end
    return price or nil
end

-- One listing: `units` of the item for `buyout` copper (the whole stack).
function Deals.Consider(itemID, units, buyout)
    if not byItem or not itemID or not units or units <= 0 or not buyout or buyout <= 0 then return end
    local vendor = vendorPrice(itemID)
    if not vendor or vendor <= 0 then return end
    local unit = buyout / units
    if unit >= vendor then return end
    local deal = byItem[itemID]
    if not deal then
        deal = { itemID = itemID, units = 0, cost = 0, vendor = vendor, cheapest = unit }
        byItem[itemID] = deal
    end
    deal.units, deal.cost = deal.units + units, deal.cost + buyout
    if unit < deal.cheapest then deal.cheapest = unit end
end

function Deals.Finish()
    list = {}
    for itemID, deal in pairs(byItem or {}) do
        deal.revenue = deal.units * deal.vendor
        deal.profit = deal.revenue - deal.cost
        deal.cheapest = math.ceil(deal.cheapest)
        local live = GetItemInfo and GetItemInfo(itemID)
        deal.name = ns.Data.Items[itemID] and ns.Data.Items[itemID].name or live or ("item " .. itemID)
        if deal.profit >= MIN_PROFIT then list[#list + 1] = deal end
    end
    table.sort(list, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.itemID < b.itemID
    end)
    for i = #list, MAX_DEALS + 1, -1 do list[i] = nil end
    byItem, vendorPrices = nil, nil
end

function Deals.List() return list end

-- The saved form (db.deals): a list of plain tables, so it survives a reload as it is.
function Deals.Export() return list end

function Deals.Import(saved)
    list = {}
    if type(saved) ~= "table" then return end
    for _, deal in ipairs(saved) do
        if type(deal) == "table" and deal.itemID and deal.profit then list[#list + 1] = deal end
    end
end
