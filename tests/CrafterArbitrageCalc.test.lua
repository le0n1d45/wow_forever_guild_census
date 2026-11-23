-- Prices and Calculator: the auction house price ladder and what a craft earns.
return function()
    local function load()
        local ns = { Data = { Items = {}, Test = { recipes = {} } } }
        loadAddonFile(ns, "Prices.lua", "CrafterArbitrage")
        loadAddonFile(ns, "Calculator.lua", "CrafterArbitrage")
        return ns
    end

    describe("Prices", function()
        it("sorts listings cheapest first and merges equal unit prices", function()
            local ns = load()
            ns.Prices.Build({ { 1, 5, 500 }, { 1, 1, 50 }, { 1, 2, 100 }, { 1, 10, 2000 } }, 99)
            assertEqual(ns.Prices.Ladder(1), { { 50, 3 }, { 100, 5 }, { 200, 10 } })
            assertEqual(ns.Prices.ScanTime(), 99)
        end)

        it("ignores listings with no buyout", function()
            local ns = load()
            ns.Prices.Build({ { 1, 1, 0 }, { 2, 3, 30 } }, 1)
            assertEqual(ns.Prices.Ladder(1), nil)
            assertEqual(ns.Prices.Min(2), 10)
        end)

        it("prices n units by climbing the ladder, and gives nil when too few are listed", function()
            local ns = load()
            ns.Prices.Build({ { 1, 2, 20 }, { 1, 2, 40 } }, 1)
            assertEqual(ns.Prices.Cost(1, 3), 2 * 10 + 20)
            assertEqual(ns.Prices.Cost(1, 4), 60)
            assertEqual(ns.Prices.Cost(1, 5), nil)
            assertEqual(ns.Prices.Supply(1), 4)
        end)

        it("takes the third-cheapest unit as the reference price, so one cheap listing does not set it", function()
            local ns = load()
            ns.Prices.Build({ { 1, 1, 5 }, { 1, 1, 100 }, { 1, 1, 110 }, { 1, 5, 600 } }, 1)
            assertEqual(ns.Prices.Reference(1), 110)
            ns.Prices.Build({ { 2, 1, 70 } }, 1)
            assertEqual(ns.Prices.Reference(2), 70)
            assertEqual(ns.Prices.Reference(3), nil)
        end)

        it("round-trips through the saved form", function()
            local ns = load()
            ns.Prices.Build({ { 1, 2, 20 }, { 1, 2, 40 }, { 9, 1, 7 } }, 5)
            local saved = ns.Prices.Export()
            ns.Prices.Build({}, nil)
            ns.Prices.Import(saved)
            assertEqual(ns.Prices.Ladder(1), { { 10, 2 }, { 20, 2 } })
            assertEqual(ns.Prices.ScanTime(), 5)
            ns.Prices.Import(nil)
            assertEqual(ns.Prices.HasScan(), false)
        end)
    end)

    describe("Calc", function()
        -- Cloth (item 10) makes Bolt (item 11, sells to a vendor for 100): 2 cloth per bolt.
        local function setup(channel)
            local ns = load()
            ns.Data.Items[10] = { sell = 5, buy = 20 }
            ns.Data.Items[11] = { sell = 100, buy = 400 }
            local recipe = { name = "Bolt", out = { 11, 1 }, r = { { 10, 2 } } }
            ns.Data.Test.recipes[1] = recipe
            return ns, recipe, { channel = channel or "vendor", have = {}, canCraft = function() return true end }
        end

        it("makes crafts while the next one still pays, stopping when the ladder climbs too high", function()
            local ns, recipe, ctx = setup()
            -- 4 cloth at 10, then 4 at 30: crafts 1-2 cost 20 each, crafts 3-4 cost 60 each (> 100 sale? no, 60 < 100)
            ns.Prices.Build({ { 10, 4, 40 }, { 10, 4, 120 }, { 10, 4, 600 } }, 1)
            local r = ns.Calc.Evaluate(recipe, ctx)
            -- crafts 1-2: 20 each; 3-4: 60 each; 5-6: 300 each (loses). Stops at 4.
            assertEqual(r.crafts, 4)
            assertEqual(r.cost, 2 * 20 + 2 * 60)
            assertEqual(r.revenue, 400)
            assertEqual(r.profit, 400 - 160)
            assertEqual(r.why, "margin")
        end)

        it("stops when the listings run out", function()
            local ns, recipe, ctx = setup()
            ns.Prices.Build({ { 10, 6, 60 } }, 1) -- 3 crafts' worth, 10 each
            local r = ns.Calc.Evaluate(recipe, ctx)
            assertEqual(r.crafts, 3)
            assertEqual(r.why, "supply")
        end)

        it("makes none when it loses money, and gives nil when a reagent is not for sale", function()
            local ns, recipe, ctx = setup()
            ns.Prices.Build({ { 10, 6, 6000 } }, 1) -- 1000 per cloth
            assertEqual(ns.Calc.Evaluate(recipe, ctx).crafts, 0)
            ns.Prices.Build({}, 1)
            assertEqual(ns.Calc.Evaluate(recipe, ctx), nil)
        end)

        it("buys a vendor-sold reagent from the vendor when that is cheaper, with no supply limit", function()
            local ns, recipe, ctx = setup()
            ns.Data.Items[10] = { sell = 5, buy = 20, vendor = true } -- vendor sells cloth at 20
            ns.Prices.Build({ { 10, 2, 100 } }, 1) -- AH: 50 each, dearer than the vendor
            local r = ns.Calc.Evaluate(recipe, ctx)
            assertEqual(r.crafts, 200) -- 40 per craft against a sale of 100, up to MAX_CRAFTS
            assertEqual(r.cost, 200 * 40)
            assertEqual(r.why, "max")
        end)

        it("does not pay for reagents the player already has", function()
            local ns, recipe, ctx = setup()
            ctx.have[10] = 4
            ns.Prices.Build({ { 10, 6, 6000 } }, 1)
            local r = ns.Calc.Evaluate(recipe, ctx)
            assertEqual(r.crafts, 2) -- two crafts from what is owned; nothing else pays at 1000 each
            assertEqual(r.cost, 0)
        end)

        it("crafts an intermediate when that beats buying it, only if the player can craft it", function()
            local ns = load()
            ns.Data.Items[10] = { sell = 1, buy = 1 }
            ns.Data.Items[11] = { sell = 1, buy = 1 }
            ns.Data.Items[12] = { sell = 1000, buy = 1 }
            local bolt = { out = { 11, 1 }, r = { { 10, 2 } } }
            local bag = { out = { 12, 1 }, r = { { 11, 3 } } }
            ns.Data.Test.recipes[1], ns.Data.Test.recipes[2] = bolt, bag
            ns.Prices.Build({ { 10, 100, 1000 }, { 11, 100, 10000 } }, 1) -- cloth 10, bolt 100
            local ctx = { channel = "vendor", have = {}, canCraft = function(r) return r == bolt end }
            assertEqual(ns.Calc.CraftCost(bag, 1, ctx), 3 * 20) -- three bolts, each two cloth
            ctx.canCraft = function() return false end
            assertEqual(ns.Calc.CraftCost(bag, 1, ctx), 300) -- must buy the bolts
        end)

        it("sells on the auction house at the reference price less the cut, and not bound items", function()
            local ns, recipe, ctx = setup("ah")
            ns.Prices.Build({ { 10, 8, 80 }, { 11, 1, 300 }, { 11, 1, 300 }, { 11, 1, 300 }, { 11, 30, 9000 } }, 1)
            assertEqual(ns.Calc.Revenue(11, 1, ctx), math.floor(299 * 0.95))
            ctx.neutral = true
            assertEqual(ns.Calc.Revenue(11, 1, ctx), math.floor(299 * 0.85))
            ns.Data.Items[11].bop = true
            assertEqual(ns.Calc.Revenue(11, 1, ctx), nil)
        end)

        it("limits auction house crafts to a share of what is already listed", function()
            local ns, recipe, ctx = setup("ah")
            ns.Prices.Build({ { 10, 400, 400 }, { 11, 10, 3000 } }, 1) -- ten bolts listed at 300: sell at most 3
            local r = ns.Calc.Evaluate(recipe, ctx)
            assertEqual(r.crafts, 3)
            assertEqual(r.why, "max")
        end)
    end)
end
