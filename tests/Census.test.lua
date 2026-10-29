return function(ns)
    local Census = ns.Census
    local Config = ns.Config

    local function label(slices, name)
        for _, s in ipairs(slices) do
            if s.label == name then return s.count end
        end
        return 0
    end

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
                { label = "Tank", count = 2 },
                { label = "DPS", count = 1 },
                { label = "Healer", count = 1 },
            })
        end)

        it("counts professions only for players who list them", function()
            assertEqual(census.professions, {
                { label = "Blacksmith", count = 1 },
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

    describe("Census.Build pure-DPS classes", function()
        it("counts warlock, hunter, mage and rogue as DPS with empty notes", function()
            local census = Census.Build({
                { level = 60, classFile = "WARLOCK", className = "Warlock", note = "" },
                { level = 60, classFile = "HUNTER", className = "Hunter", note = nil },
                { level = 60, classFile = "MAGE", className = "Mage", note = "" },
                { level = 60, classFile = "ROGUE", className = "Rogue", note = "" },
            })
            assertEqual(census.roles, { { label = "DPS", count = 4 } })
        end)

        it("does not double count when the note also says dps", function()
            local census = Census.Build({
                { level = 60, classFile = "MAGE", className = "Mage", note = "dps" },
            })
            assertEqual(census.roles, { { label = "DPS", count = 1 } })
        end)

        it("leaves hybrid classes to their notes", function()
            local census = Census.Build({
                { level = 60, classFile = "DRUID", className = "Druid", note = "" },
                { level = 60, classFile = "PALADIN", className = "Paladin", note = "" },
            })
            assertEqual(census.roles, {})
        end)
    end)

    describe("Census.Build alt and main filters", function()
        local members = {
            { level = 60, classFile = "WARRIOR", className = "Warrior", note = "Main tank" },
            { level = 60, classFile = "PRIEST", className = "Priest", note = "alt of Bob, healer" },
            { level = 60, classFile = "DRUID", className = "Druid", note = "resto" },
            { level = 60, classFile = "MAGE", className = "Mage", note = "ALT" },
        }

        it("includes everyone by default", function()
            assertEqual(Census.Build(members).total, 4)
        end)

        it("excludes alts when includeAlts is off", function()
            local s = Config.Defaults()
            s.includeAlts = false
            local census = Census.Build(members, s)
            assertEqual(census.total, 2)
            assertEqual(label(census.roles, "Healer"), 1)
            assertEqual(label(census.roles, "DPS"), 0)
        end)

        it("only mains keeps just notes that declare a main", function()
            local s = Config.Defaults()
            s.onlyMains = true
            local census = Census.Build(members, s)
            assertEqual(census.total, 1)
            assertEqual(census.classes, { { label = "Warrior", classFile = "WARRIOR", count = 1 } })
        end)

        it("only mains also honours the alts checkbox", function()
            local s = Config.Defaults()
            s.onlyMains, s.includeAlts = true, false
            local both = { { level = 60, classFile = "DRUID", className = "Druid", note = "main, alt of Bob" } }
            assertEqual(Census.Build(both, s).total, 0)
            s.includeAlts = true
            assertEqual(Census.Build(both, s).total, 1)
        end)

        it("uses custom alt and main keywords", function()
            local s = Config.Defaults()
            s.includeAlts = false
            s.identity.alt = "twink, second"
            local custom = {
                { level = 10, classFile = "MAGE", className = "Mage", note = "twink" },
                { level = 60, classFile = "MAGE", className = "Mage", note = "alt of Bob" },
            }
            assertEqual(Census.Build(custom, s).total, 1)
        end)
    end)

    describe("Census.Build conflicts", function()
        local function conflictsFor(member, settings)
            member.name = member.name or "Bob"
            member.level = member.level or 60
            return Census.Build({ member }, settings).conflicts
        end

        it("flags a note detected as both main and alt, naming the keywords", function()
            local c = conflictsFor({ classFile = "DRUID", className = "Druid", note = "Main, alt of Bob" })
            assertEqual(#c, 1)
            assertEqual(c[1].kind, "main-and-alt")
            assertEqual(c[1].message, "Detected as both a main ('main') and an alt ('alt')")
            assertEqual(c[1].name, "Bob")
            assertEqual(c[1].note, "Main, alt of Bob")
        end)

        it("flags more than two professions and lists what matched", function()
            local c = conflictsFor({ classFile = "DRUID", className = "Druid", note = "mining skinning herb" })
            assertEqual(#c, 1)
            assertEqual(c[1].kind, "too-many-professions")
            assertEqual(c[1].message,
                "3 professions detected (max 2): Skinning ('skinning'), Mining ('mining'), Herbalism ('herb')")
        end)

        it("allows exactly two professions", function()
            assertEqual(conflictsFor({ classFile = "DRUID", className = "Druid", note = "mining herb" }), {})
        end)

        it("does NOT flag a hybrid holding all three roles", function()
            assertEqual(conflictsFor({ classFile = "DRUID", className = "Druid", note = "tank heal dps" }), {})
            assertEqual(conflictsFor({ classFile = "PALADIN", className = "Paladin", note = "tank heal dps" }), {})
        end)

        it("flags a class that cannot fill a detected role", function()
            local c = conflictsFor({ classFile = "MAGE", className = "Mage", note = "healer" })
            assertEqual(#c, 1)
            assertEqual(c[1].kind, "role-class-mismatch")
            assertEqual(c[1].message, "Mage cannot fill the Healer role, but the note matched 'heal'")
            assertEqual(#conflictsFor({ classFile = "WARRIOR", className = "Warrior", note = "healer" }), 1)
            assertEqual(#conflictsFor({ classFile = "PRIEST", className = "Priest", note = "tank" }), 1)
        end)

        it("does not flag roles a class can fill", function()
            assertEqual(conflictsFor({ classFile = "MAGE", className = "Mage", note = "dps" }), {})
            assertEqual(conflictsFor({ classFile = "WARRIOR", className = "Warrior", note = "tank / dps" }), {})
            assertEqual(conflictsFor({ classFile = "PRIEST", className = "Priest", note = "healer" }), {})
        end)

        it("reports nothing for plain notes", function()
            assertEqual(conflictsFor({ classFile = "MAGE", className = "Mage", note = "" }), {})
            assertEqual(conflictsFor({ classFile = "MAGE", className = "Mage", note = nil }), {})
        end)

        it("reports conflicts even for members hidden by the alt/main filters", function()
            local s = Config.Defaults()
            s.includeAlts, s.onlyMains = false, true
            local census = Census.Build({
                { name = "Bob", level = 60, classFile = "DRUID", className = "Druid", note = "main, alt" },
            }, s)
            assertEqual(census.total, 0)
            assertEqual(#census.conflicts, 1)
        end)

        it("reports every conflict for a member and sorts by name", function()
            local census = Census.Build({
                { name = "zed", level = 60, classFile = "MAGE", className = "Mage", note = "heal main alt" },
                { name = "Amy", level = 60, classFile = "DRUID", className = "Druid", note = "main alt" },
            })
            assertEqual(census.memberCount, 2)
            assertEqual(#census.conflicts, 3)
            assertEqual(census.conflicts[1].name, "Amy")
            assertEqual(census.conflicts[2].kind, "main-and-alt")
            assertEqual(census.conflicts[3].kind, "role-class-mismatch")
        end)
    end)

    describe("Census.Build custom detection", function()
        it("uses keyword lists from settings", function()
            local s = Config.Defaults()
            s.roles.tank = "wall"
            s.professions.mining = "pickaxe"
            local census = Census.Build({
                { level = 60, classFile = "WARRIOR", className = "Warrior", note = "wall, pickaxe, tank" },
            }, s)
            assertEqual(census.roles, { { label = "Tank", count = 1 } })
            assertEqual(census.professions, { { label = "Mining", count = 1 } })
        end)
    end)
end
