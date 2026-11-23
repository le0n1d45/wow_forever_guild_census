local addonName, ns = ...

-- The auction house price index: for each item, the listings sorted cheapest first, as a "ladder" of
-- { unit price, units } steps. Buying n units costs what climbing the ladder costs, so the price of the next
-- craft rises as cheap listings run out (Calculator relies on this).

local Prices = {}
ns.Prices = Prices

local MAX_STEPS = 40 -- per item: the cheapest listings are all a craft will ever buy
local REFERENCE_UNITS = 3 -- the price the third-cheapest unit sells at; one lone cheap listing doesn't set it

local ladders = {} -- itemID -> { { price, units }, ... } cheapest first
local scanTime

-- Replaces the index. `auctions` is a list of { itemID, units, buyout } (buyout is the whole stack's price).
function Prices.Build(auctions, time)
    local byItem = {}
    for _, a in ipairs(auctions) do
        local itemID, units, buyout = a[1], a[2], a[3]
        if itemID and units and units > 0 and buyout and buyout > 0 then
            local list = byItem[itemID]
            if not list then list = {}; byItem[itemID] = list end
            local unit = math.ceil(buyout / units)
            -- same unit price: merge, so the ladder stays short
            local last = list[unit]
            if last then last[2] = last[2] + units else list[unit] = { unit, units } end
        end
    end
    ladders = {}
    for itemID, byPrice in pairs(byItem) do
        local steps = {}
        for _, step in pairs(byPrice) do steps[#steps + 1] = step end
        table.sort(steps, function(a, b) return a[1] < b[1] end)
        for i = #steps, MAX_STEPS + 1, -1 do steps[i] = nil end
        ladders[itemID] = steps
    end
    scanTime = time
end

function Prices.ScanTime() return scanTime end
function Prices.HasScan() return scanTime ~= nil end

-- The saved form (db.scan): { time = t, items = { [itemID] = { price1, units1, price2, units2, ... } } }.
function Prices.Export()
    local items = {}
    for itemID, steps in pairs(ladders) do
        local flat = {}
        for _, step in ipairs(steps) do flat[#flat + 1] = step[1]; flat[#flat + 1] = step[2] end
        items[itemID] = flat
    end
    return { time = scanTime, items = items }
end

function Prices.Import(saved)
    ladders, scanTime = {}, nil
    if type(saved) ~= "table" or type(saved.items) ~= "table" then return end
    for itemID, flat in pairs(saved.items) do
        local steps = {}
        for i = 1, #flat - 1, 2 do steps[#steps + 1] = { flat[i], flat[i + 1] } end
        ladders[itemID] = steps
    end
    scanTime = saved.time
end

function Prices.Ladder(itemID) return ladders[itemID] end

function Prices.Supply(itemID)
    local n = 0
    for _, step in ipairs(ladders[itemID] or {}) do n = n + step[2] end
    return n
end

function Prices.Min(itemID)
    local steps = ladders[itemID]
    return steps and steps[1] and steps[1][1] or nil
end

-- What it costs to buy `units` of an item from the ladder, or nil when fewer are listed. `skip` units are
-- bought first and not counted: Cost(id, skip + n) - Cost(id, skip) is the price of the n after them.
function Prices.Cost(itemID, units)
    local steps = ladders[itemID]
    if not steps then return nil end
    local total, left = 0, units
    for _, step in ipairs(steps) do
        local take = math.min(left, step[2])
        total = total + take * step[1]
        left = left - take
        if left <= 0 then return total end
    end
    return left <= 0 and total or nil
end

-- A sale price to plan with: the price of the REFERENCE_UNITS-th cheapest unit, or the dearest listed one when
-- fewer are for sale.
function Prices.Reference(itemID)
    local steps = ladders[itemID]
    if not steps or #steps == 0 then return nil end
    local seen = 0
    for _, step in ipairs(steps) do
        seen = seen + step[2]
        if seen >= REFERENCE_UNITS then return step[1] end
    end
    return steps[#steps][1]
end
