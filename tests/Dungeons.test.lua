return function(ns)
    local Dungeons = ns.Dungeons

    describe("Dungeons.LIST", function()
        it("has valid, unique entries", function()
            local seen = {}
            for _, d in ipairs(Dungeons.LIST) do
                assert(type(d.key) == "string" and d.key ~= "", "missing key")
                assert(type(d.name) == "string" and d.name ~= "", "missing name for " .. d.key)
                assert(not seen[d.key], "duplicate key " .. d.key)
                seen[d.key] = true
                assert(d.minLevel >= 1 and d.minLevel <= d.maxLevel, "bad range for " .. d.key)
            end
        end)

        it("is sorted by minimum level, then name (the dropdown shows it in this order)", function()
            for i = 2, #Dungeons.LIST do
                local a, b = Dungeons.LIST[i - 1], Dungeons.LIST[i]
                assert(a.minLevel < b.minLevel or (a.minLevel == b.minLevel and a.name <= b.name),
                    a.name .. " should not come before " .. b.name)
            end
        end)

        it("includes the Deadmines with its level range", function()
            local d = Dungeons.Get("deadmines")
            assertEqual(d.name, "The Deadmines")
            assertEqual(d.minLevel, 10)
            assertEqual(d.maxLevel, 20)
        end)
    end)

    describe("Dungeons.Get", function()
        it("returns nil for an unknown dungeon", function()
            assertEqual(Dungeons.Get("nope"), nil)
        end)
    end)
end
