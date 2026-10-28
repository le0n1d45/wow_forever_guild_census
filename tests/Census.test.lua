return function(ns)
    local Census = ns.Census

    describe("Census.Build", function()
        local members = {
            { level = 60, classFile = "WARRIOR", className = "Warrior", note = "Tank, Blacksmithing" },
            { level = 58, classFile = "PRIEST", className = "Priest", note = "healer enchanting" },
            { level = 12, classFile = "WARRIOR", className = "Warrior", note = "" },
            { level = 5, classFile = "MAGE", className = "Mage", note = "dps / tank" },
        }
        local census = Census.Build(members)

        it("counts members", function()
            assertEqual(census.total, 4)
        end)

        it("counts roles, allowing multiple roles per player", function()
            assertEqual(census.roles, {
                { label = "tank", count = 2 },
                { label = "dps", count = 1 },
                { label = "healer", count = 1 },
            })
        end)

        it("counts professions only for players who list them", function()
            assertEqual(census.professions, {
                { label = "Blacksmithing", count = 1 },
                { label = "Enchanting", count = 1 },
            })
        end)

        it("counts classes with display names, keeping the class file", function()
            assertEqual(census.classes, {
                { label = "Warrior", classFile = "WARRIOR", count = 2 },
                { label = "Mage", classFile = "MAGE", count = 1 },
                { label = "Priest", classFile = "PRIEST", count = 1 },
            })
        end)

        it("buckets levels in ascending order", function()
            assertEqual(census.levels, {
                { label = "1-10", count = 1 },
                { label = "11-20", count = 1 },
                { label = "51-60", count = 2 },
            })
        end)

        it("handles an empty roster", function()
            local empty = Census.Build({})
            assertEqual(empty.total, 0)
            assertEqual(empty.roles, {})
            assertEqual(empty.levels, {})
        end)
    end)
end
