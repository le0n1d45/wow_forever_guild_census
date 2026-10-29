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

        it("includes the high-level dungeons with their published ranges", function()
            local expected = {
                ["sunken-temple"] = { 50, 60 }, ["blackrock-depths"] = { 52, 60 },
                ["blackrock-spire-lower"] = { 55, 60 }, ["blackrock-spire-upper"] = { 58, 60 },
                ["dire-maul"] = { 58, 60 }, ["scholomance"] = { 58, 60 }, ["stratholme"] = { 58, 60 },
            }
            for key, range in pairs(expected) do
                local d = Dungeons.Get(key)
                assert(d, "missing " .. key)
                assertEqual({ d.minLevel, d.maxLevel }, range)
            end
        end)

        it("matches every range on the Wowhead chart (34 entries)", function()
            local chart = {
                { "The Hall of Thanes", 13, 18 }, { "Ragefire Chasm", 13, 18 },
                { "Ruins of Lordaeron", 15, 20 }, { "Wailing Caverns", 15, 25 },
                { "The Deadmines", 18, 23 }, { "Shadowfang Keep", 22, 30 }, { "The Stockade", 22, 30 },
                { "Blackfathom Deeps", 24, 32 }, { "Excavation Site: Wetlands", 24, 29 },
                { "City of Dalaran", 28, 33 }, { "Scarlet Monastery: Graveyard", 28, 38 },
                { "Gnomeregan", 29, 38 }, { "Scarlet Monastery: Library", 29, 39 },
                { "Razorfen Kraul", 30, 40 }, { "Scarlet Monastery: Armory", 32, 42 },
                { "Scarlet Monastery: Cathedral", 35, 45 }, { "The Drowned City", 35, 40 },
                { "Krol'dok Stronghold", 40, 45 }, { "Razorfen Downs", 40, 50 },
                { "Uldaman", 42, 52 }, { "Zul'Farrak", 44, 54 },
                { "Maraudon: Foulspore Cavern", 45, 53 }, { "Maraudon: Wicked Grotto", 45, 53 },
                { "Alcaz Prison", 48, 53 }, { "Maraudon: Earth Song Falls", 48, 57 },
                { "Sunken Temple", 50, 60 }, { "Blackrock Depths", 52, 60 },
                { "Blackmaw Hold", 55, 60 }, { "Blackrock Spire: Lower", 55, 60 },
                { "Blackrock Spire: Upper", 58, 60 }, { "Dire Maul", 58, 60 },
                { "Scholomance", 58, 60 }, { "Shaper's Terrace", 58, 60 }, { "Stratholme", 58, 60 },
            }
            assertEqual(#Dungeons.LIST, #chart)
            local byName = {}
            for _, d in ipairs(Dungeons.LIST) do byName[d.name] = d end
            for _, row in ipairs(chart) do
                local d = byName[row[1]]
                assert(d, "missing " .. row[1])
                assertEqual({ d.minLevel, d.maxLevel }, { row[2], row[3] })
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
