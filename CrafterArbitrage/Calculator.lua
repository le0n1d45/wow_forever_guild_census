local addonName, ns = ...

-- What a craft earns. Everything is in copper. Buying n crafts' worth of reagents climbs the auction house
-- price ladder (Prices), so the first craft is the cheapest and each next one costs more; Evaluate finds how
-- many crafts still pay.

local Calc = {}
ns.Calc = Calc

Calc.MIN_PROFIT = 5 -- copper a craft must earn at the margin
Calc.MIN_MARGIN = 0.10 -- ...and at least this share of what that craft costs
Calc.AH_CUT = 0.05 -- the auction house keeps 5%; 15% at the neutral auction house
Calc.NEUTRAL_AH_CUT = 0.15
Calc.AH_SHARE = 0.3 -- sell at most this share of the units already listed
Calc.MAX_CRAFTS = 200 -- vendor sales have no demand limit; this only bounds the search
Calc.MAX_AH_CRAFTS = 20
Calc.DEPTH = 2 -- how many levels of intermediate crafts (cloth -> bolt -> bag) a reagent may go through

local function items() return ns.Data and ns.Data.Items or {} end

-- Vendor sell price of an item, from the generated data or, for items it doesn't know, from the game.
function Calc.VendorPrice(itemID)
    local info = items()[itemID]
    if info and info.sell then return info.sell end
    if ns.LiveSellPrice then return ns.LiveSellPrice(itemID) end
    return nil
end

function Calc.VendorBuyPrice(itemID)
    local info = items()[itemID]
    return info and info.vendor and info.buy or nil
end

function Calc.IsBoundOnPickup(itemID)
    local info = items()[itemID]
    return info and info.bop or false
end

-- Producer of each item: the cheapest-to-describe recipe that makes it (intermediates). Built once.
local producers
local function producerOf(itemID)
    if not producers then
        producers = {}
        for _, prof in pairs(ns.Data or {}) do
            for spell, recipe in pairs(prof.recipes or {}) do
                local out = recipe.out[1]
                local list = producers[out]
                if not list then list = {}; producers[out] = list end
                list[#list + 1] = { spell = spell, recipe = recipe }
            end
        end
    end
    return producers[itemID]
end
function Calc.ResetProducers() producers = nil end

-- Cost of n units of an item as a reagent: the cheaper of buying (vendor, or the auction house ladder) and
-- crafting it from its own reagents when `ctx.canCraft(recipe)` allows. Returns the cost or nil.
-- `have` (ctx.have[itemID]) units are already owned and cost nothing.
local unitCost
local function craftCost(recipe, crafts, ctx, depth, seen)
    local total = 0
    for _, reagent in ipairs(recipe.r) do
        local c = unitCost(reagent[1], reagent[2] * crafts, ctx, depth, seen)
        if not c then return nil end
        total = total + c
    end
    return total
end

function unitCost(itemID, units, ctx, depth, seen)
    local have = ctx.have and ctx.have[itemID] or 0
    local owned = math.min(have, units)
    units = units - owned
    if units <= 0 then return 0 end
    local best
    local vendor = Calc.VendorBuyPrice(itemID)
    if vendor then best = vendor * units end
    local ah = ns.Prices.Cost(itemID, units)
    if ah and (not best or ah < best) then best = ah end
    if depth > 0 and ctx.canCraft and not seen[itemID] then
        seen[itemID] = true
        for _, p in ipairs(producerOf(itemID) or {}) do
            if ctx.canCraft(p.recipe, p.spell) then
                local crafts = math.ceil(units / p.recipe.out[2])
                local c = craftCost(p.recipe, crafts, ctx, depth - 1, seen)
                if c and (not best or c < best) then best = c end
            end
        end
        seen[itemID] = nil
    end
    return best
end

-- Cost of n crafts of a recipe, or nil when the reagents can't all be had.
function Calc.CraftCost(recipe, crafts, ctx)
    return craftCost(recipe, crafts, ctx, Calc.DEPTH, {})
end

-- What selling `units` of a crafted item brings, or nil when it can't be sold that way.
-- ctx.channel is "vendor" or "ah".
function Calc.Revenue(itemID, units, ctx)
    if ctx.channel == "ah" then
        if Calc.IsBoundOnPickup(itemID) then return nil end
        local ref = ns.Prices.Reference(itemID)
        if not ref then return nil end
        local cut = ctx.neutral and Calc.NEUTRAL_AH_CUT or Calc.AH_CUT
        return math.floor(units * math.max(1, ref - 1) * (1 - cut)) -- undercut by 1 copper
    end
    local price = Calc.VendorPrice(itemID)
    if not price or price <= 0 then return nil end
    return price * units
end

-- Evaluates a recipe: how many crafts are worth making and what they earn. Returns nil when it can't be done
-- at all (no price, a reagent missing, unsellable), else
-- { crafts, cost, revenue, profit, units, why }  where why is what stopped it: "margin", "supply" or "max".
function Calc.Evaluate(recipe, ctx)
    local itemID, perCraft = recipe.out[1], recipe.out[2]
    local cap = ctx.channel == "ah" and Calc.MAX_AH_CRAFTS or Calc.MAX_CRAFTS
    if ctx.channel == "ah" then
        local supply = ns.Prices.Supply(itemID)
        local room = math.max(1, math.floor(supply * Calc.AH_SHARE / perCraft))
        cap = math.min(cap, room)
    end
    local memo = {}
    local function at(n)
        if n == 0 then return { cost = 0, revenue = 0 } end
        local m = memo[n]
        if not m then
            m = { cost = Calc.CraftCost(recipe, n, ctx), revenue = Calc.Revenue(itemID, n * perCraft, ctx) }
            memo[n] = m
        end
        return m
    end
    -- Does the n-th craft pay on its own? (Cost per craft only rises, so this is monotonic.)
    local function pays(n)
        local cur, prev = at(n), at(n - 1)
        if not cur.cost or not cur.revenue then return false, "supply" end
        if not prev.cost or not prev.revenue then return false, "supply" end
        local marginalCost, marginalRevenue = cur.cost - prev.cost, cur.revenue - prev.revenue
        if marginalRevenue - marginalCost < math.max(Calc.MIN_PROFIT, Calc.MIN_MARGIN * marginalCost) then
            return false, "margin"
        end
        return true
    end
    local ok, why = pays(1)
    if not ok then
        if why == "supply" and not at(1).revenue then return nil end -- cannot be sold this way
        if why == "supply" and not at(1).cost then return nil end -- reagents cannot be bought
        return { crafts = 0, cost = 0, revenue = 0, profit = 0, units = 0, why = why }
    end
    local lo, hi, stop = 1, cap, nil
    if pays(cap) then
        lo, stop = cap, "max"
    else
        while hi - lo > 1 do
            local mid = math.floor((lo + hi) / 2)
            if pays(mid) then lo = mid else hi = mid end
        end
        local _, reason = pays(hi)
        stop = reason
    end
    local m = at(lo)
    return { crafts = lo, cost = m.cost, revenue = m.revenue, profit = m.revenue - m.cost, units = lo * perCraft, why = stop }
end
