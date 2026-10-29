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

        it("has Forever's level range for a classic dungeon (not the classic-era one)", function()
            local d = Dungeons.Get("deadmines")
            assertEqual(d.name, "The Deadmines")
            assertEqual(d.minLevel, 18)
            assertEqual(d.maxLevel, 23)
        end)

        it("includes all nine new Forever dungeons with their published ranges", function()
            local expected = {
                ["hall-of-thanes"] = { 13, 18 }, ["ruins-of-lordaeron"] = { 15, 20 },
                ["excavation-site-wetlands"] = { 24, 29 }, ["city-of-dalaran"] = { 28, 33 },
                ["drowned-city"] = { 35, 40 }, ["krol-dok-stronghold"] = { 40, 45 },
                ["alcaz-prison"] = { 48, 53 }, ["blackmaw-hold"] = { 55, 60 },
                ["shapers-terrace"] = { 58, 60 },
            }
            for key, range in pairs(expected) do
                local d = Dungeons.Get(key)
                assert(d, "missing " .. key)
                assertEqual({ d.minLevel, d.maxLevel }, range)
            end
        end)

        it("lists multi-wing dungeons per wing", function()
            for _, key in ipairs({
                "scarlet-monastery-graveyard", "scarlet-monastery-library",
                "scarlet-monastery-armory", "scarlet-monastery-cathedral",
                "maraudon-foulspore-cavern", "maraudon-wicked-grotto", "maraudon-earth-song-falls",
            }) do
                assert(Dungeons.Get(key), "missing wing " .. key)
            end
        end)
    end)

    describe("Dungeons.Get", function()
        it("returns nil for an unknown dungeon", function()
            assertEqual(Dungeons.Get("nope"), nil)
        end)
    end)
end
