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
            assertEqual(c[1].message, "Mage cannot fill the Healer role, but the note matched 'healer'")
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

        it("never drops conflicted members from the census (the log is informational)", function()
            local census = Census.Build({
                { name = "A", level = 60, classFile = "DRUID", className = "Druid", note = "mining skinning herb" },
                { name = "B", level = 60, classFile = "MAGE", className = "Mage", note = "healer" },
                { name = "C", level = 20, classFile = "PALADIN", className = "Paladin", note = "main, alt" },
            })
            assertEqual(#census.conflicts, 3)
            assertEqual(census.total, 3)
            -- all three detected professions are still counted
            assertEqual(label(census.professions, "Mining"), 1)
            assertEqual(label(census.professions, "Skinning"), 1)
            assertEqual(label(census.professions, "Herbalism"), 1)
            -- the impossible role is still counted, alongside the class's DPS default
            assertEqual(label(census.roles, "Healer"), 1)
            assertEqual(label(census.roles, "DPS"), 1)
            -- and every member appears in the class and level charts
            assertEqual(label(census.classes, "Druid") + label(census.classes, "Mage")
                + label(census.classes, "Paladin"), 3)
            assertEqual(label(census.levels, "51-60") + label(census.levels, "21-30")
                + label(census.levels, "11-20"), 3)
        end)

        it("produces identical charts whether or not conflicts exist", function()
            local conflicted = { name = "A", level = 60, classFile = "DRUID", className = "Druid", note = "mining skinning herb" }
            local clean = { name = "A", level = 60, classFile = "DRUID", className = "Druid", note = "mining skinning herb" }
            local a = Census.Build({ conflicted })
            assertEqual(#a.conflicts, 1)
            local b = Census.Build({ clean }, Config.Defaults())
            assertEqual(a.professions, b.professions)
            assertEqual(a.roles, b.roles)
            assertEqual(a.total, b.total)
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

    local function member(name, level, classFile, note, online)
        return {
            name = name, level = level, classFile = classFile, note = note,
            className = classFile:sub(1, 1) .. classFile:sub(2):lower(), online = online,
        }
    end

    local function names(results)
        local list = {}
        for _, r in ipairs(results) do list[#list + 1] = r.name end
        return list
    end

    describe("Census.Analyze", function()
        local rules = Census.Rules(Config.Defaults())

        it("reports note-detected roles, professions and the matching keywords", function()
            local a = Census.Analyze(member("Bob", 60, "WARRIOR", "tank, miner"), rules)
            assertEqual(a.roles, { "Tank" })
            assertEqual(a.roleKeys, { tank = true })
            assertEqual(a.roleHits, { { key = "tank", label = "Tank", word = "tank" } })
            assertEqual(a.professionHits, { { key = "mining", label = "Mining", word = "miner" } })
            assertEqual(a.included, true)
        end)

        it("adds DPS for pure-DPS classes without a note", function()
            local a = Census.Analyze(member("Mia", 60, "MAGE", ""), rules)
            assertEqual(a.roles, { "DPS" })
            assertEqual(a.roleKeys, { dps = true })
            assertEqual(a.roleHits, {}) -- note-based hits stay empty (used for conflict checks)
        end)

        it("does not add DPS to hybrids", function()
            assertEqual(Census.Analyze(member("Dru", 60, "DRUID", ""), rules).roles, {})
        end)

        it("reports the professions found as a set", function()
            local a = Census.Analyze(member("Bob", 60, "WARRIOR", "miner, bs"), rules)
            assertEqual(a.professionKeys, { mining = true, blacksmith = true })
        end)

        it("marks members excluded by the alts filter", function()
            local s = Config.Defaults()
            s.includeAlts = false
            local a = Census.Analyze(member("Al", 60, "DRUID", "alt of Bob"), Census.Rules(s))
            assertEqual(a.included, false)
            assertEqual(a.altWord, "alt")
        end)

        it("marks members excluded by only-mains", function()
            local s = Config.Defaults()
            s.onlyMains = true
            local r = Census.Rules(s)
            assertEqual(Census.Analyze(member("A", 60, "DRUID", "main"), r).included, true)
            assertEqual(Census.Analyze(member("B", 60, "DRUID", "resto"), r).included, false)
        end)
    end)

    describe("Census.Find", function()
        local roster = {
            member("Tanky", 15, "WARRIOR", "Tank"),
            member("Bulwark", 20, "PALADIN", "prot / heal"),
            member("Elder", 60, "WARRIOR", "main tank"),
            member("Mender", 18, "PRIEST", "healer"),
            member("Zap", 18, "MAGE", ""),
            member("Stab", 25, "ROGUE", "dps"),
            member("Newbie", 5, "WARRIOR", "tank"),
            member("Tag", 17, "DRUID", "alt of Bob, bear"),
        }

        it("finds players for a role within a level range, highest level first", function()
            assertEqual(names(Census.Find(roster, { role = "tank", minLevel = 10, maxLevel = 25 })),
                { "Bulwark", "Tag", "Tanky" })
        end)

        it("treats level bounds as inclusive", function()
            assertEqual(names(Census.Find(roster, { role = "tank", minLevel = 15, maxLevel = 15 })), { "Tanky" })
            assertEqual(names(Census.Find(roster, { role = "tank", minLevel = 20, maxLevel = 20 })), { "Bulwark" })
        end)

        it("supports open-ended ranges", function()
            assertEqual(names(Census.Find(roster, { role = "tank", minLevel = 50 })), { "Elder" })
            assertEqual(names(Census.Find(roster, { role = "tank", maxLevel = 5 })), { "Newbie" })
        end)

        it("finds healers, including hybrids whose note lists several roles", function()
            assertEqual(names(Census.Find(roster, { role = "healer" })), { "Bulwark", "Mender" })
        end)

        it("finds pure-DPS classes for dps without any note", function()
            assertEqual(names(Census.Find(roster, { role = "dps", minLevel = 18, maxLevel = 25 })),
                { "Stab", "Zap" })
        end)

        it("omitting the role matches every role (and notes with none)", function()
            assertEqual(#Census.Find(roster, { minLevel = 1, maxLevel = 100 }), #roster)
            assertEqual(#Census.Find(roster, {}), #roster)
            assertEqual(#Census.Find(roster), #roster)
        end)

        it("matches nobody when minLevel is above maxLevel", function()
            assertEqual(Census.Find(roster, { role = "tank", minLevel = 30, maxLevel = 10 }), {})
        end)

        it("returns nothing when nobody fits", function()
            assertEqual(Census.Find(roster, { role = "healer", minLevel = 40 }), {})
        end)

        it("excludes members hidden by the alts filter", function()
            local s = Config.Defaults()
            s.includeAlts = false
            assertEqual(names(Census.Find(roster, { role = "tank", minLevel = 10, maxLevel = 25 }, s)),
                { "Bulwark", "Tanky" })
        end)

        it("honours only-mains", function()
            local s = Config.Defaults()
            s.onlyMains = true
            assertEqual(names(Census.Find(roster, { role = "tank" }, s)), { "Elder" })
        end)

        it("uses custom keyword lists from settings", function()
            local s = Config.Defaults()
            s.roles.tank = "wall"
            local custom = { member("Wally", 30, "WARRIOR", "wall"), member("Tanky", 30, "WARRIOR", "tank") }
            assertEqual(names(Census.Find(custom, { role = "tank" }, s)), { "Wally" })
        end)

        it("still returns members with logged conflicts", function()
            local conflicted = { member("Both", 30, "DRUID", "main alt tank") }
            assertEqual(#Census.Build(conflicted).conflicts, 1)
            assertEqual(names(Census.Find(conflicted, { role = "tank" })), { "Both" })
        end)

        it("returns the details the UI needs", function()
            local r = Census.Find({ member("Bob", 33, "PALADIN", "tank, mining", true) }, { role = "tank" })[1]
            assertEqual(r.name, "Bob")
            assertEqual(r.level, 33)
            assertEqual(r.className, "Paladin")
            assertEqual(r.classFile, "PALADIN")
            assertEqual(r.note, "tank, mining")
            assertEqual(r.online, true)
            assertEqual(r.roles, { "Tank" })
            assertEqual(r.professions, { "Mining" })
        end)

        it("breaks level ties by name, case-insensitively", function()
            local tied = { member("zed", 20, "ROGUE", ""), member("Amy", 20, "ROGUE", ""), member("bob", 20, "ROGUE", "") }
            assertEqual(names(Census.Find(tied, { role = "dps" })), { "Amy", "bob", "zed" })
        end)

        it("skips members with no level when a level bound is given", function()
            local nolevel = { { name = "Ghost", classFile = "MAGE", className = "Mage", note = "" } }
            assertEqual(Census.Find(nolevel, { role = "dps", minLevel = 1 }), {})
            assertEqual(#Census.Find(nolevel, { role = "dps" }), 1)
        end)

        it("rejects an unknown role", function()
            local ok, err = pcall(Census.Find, roster, { role = "bard" })
            assertEqual(ok, false)
            assert(tostring(err):find("unknown role: bard", 1, true), tostring(err))
        end)

        local crew = {
            member("Dig", 30, "WARRIOR", "tank, mining", true),
            member("Stitch", 30, "PRIEST", "healer, tailoring", false),
            member("Both", 40, "PALADIN", "prot, miner, tailor", true),
            member("Plain", 20, "MAGE", "", true),
            member("Away", 50, "ROGUE", "mining", false),
            member("Unknown", 25, "DRUID", "mining, resto", nil),
        }

        it("filters by profession", function()
            assertEqual(names(Census.Find(crew, { profession = "mining" })), { "Away", "Both", "Dig", "Unknown" })
            assertEqual(names(Census.Find(crew, { profession = "tailor" })), { "Both", "Stitch" })
            assertEqual(Census.Find(crew, { profession = "alchemy" }), {})
        end)

        it("combines profession with role and level range", function()
            assertEqual(names(Census.Find(crew, { profession = "mining", role = "tank" })), { "Both", "Dig" })
            assertEqual(names(Census.Find(crew, { profession = "mining", minLevel = 35 })), { "Away", "Both" })
            assertEqual(names(Census.Find(crew, { profession = "tailor", role = "healer", maxLevel = 30 })), { "Stitch" })
        end)

        it("uses custom profession keywords from settings", function()
            local s = Config.Defaults()
            s.professions.mining = "pickaxe"
            local custom = { member("Pick", 30, "WARRIOR", "pickaxe"), member("Dig", 30, "WARRIOR", "mining") }
            assertEqual(names(Census.Find(custom, { profession = "mining" }, s)), { "Pick" })
        end)

        it("hasProfession returns everyone with at least one detected profession", function()
            assertEqual(names(Census.Find(crew, { hasProfession = true })),
                { "Away", "Both", "Dig", "Stitch", "Unknown" })
            assertEqual(names(Census.Find(crew, { hasProfession = true, onlineOnly = true })), { "Both", "Dig" })
            assertEqual(#Census.Find(crew, { hasProfession = false }), #crew)
        end)

        it("a specific profession takes precedence over hasProfession", function()
            assertEqual(names(Census.Find(crew, { profession = "tailor", hasProfession = true })),
                { "Both", "Stitch" })
        end)

        local smiths = {
            member("Novice", 20, "WARRIOR", "LW 40", true),
            member("Adept", 40, "WARRIOR", "LW 150, mining 120", false),
            member("Master", 60, "PRIEST", "healer, LW 300, BS: 275", true),
            member("Quiet", 55, "MAGE", "LW, mining", true),
            member("Miner", 50, "ROGUE", "mining (225)", true),
            member("None", 30, "DRUID", "resto", true),
        }

        it("reads skill levels from notes", function()
            local rules = Census.Rules(Config.Defaults())
            local a = Census.Analyze(smiths[3], rules)
            local skills = {}
            for _, hit in ipairs(a.professionHits) do skills[hit.key] = hit.skill end
            assertEqual(skills, { leatherworking = 300, blacksmith = 275 })
            assertEqual(Census.Analyze(smiths[4], rules).professionHits[1].skill, nil)
        end)

        it("filters a profession by skill range, inclusive", function()
            assertEqual(names(Census.Find(smiths, { profession = "leatherworking", minSkill = 150 })),
                { "Master", "Adept" })
            assertEqual(names(Census.Find(smiths, { profession = "leatherworking", maxSkill = 150 })),
                { "Adept", "Novice" })
            assertEqual(names(Census.Find(smiths, { profession = "leatherworking", minSkill = 150, maxSkill = 150 })),
                { "Adept" })
            assertEqual(names(Census.Find(smiths, { profession = "leatherworking", minSkill = 41, maxSkill = 149 })), {})
        end)

        it("leaves out members who do not write their skill once a bound is set", function()
            assertEqual(#Census.Find(smiths, { profession = "leatherworking" }), 4) -- no bound: Quiet is in
            local inRange = names(Census.Find(smiths, { profession = "leatherworking", minSkill = 1 }))
            assertEqual(inRange, { "Master", "Adept", "Novice" })
        end)

        it("applies the range to the chosen profession only", function()
            -- Master is 300 in leatherworking and 275 in blacksmithing; Adept is 120 in mining.
            assertEqual(names(Census.Find(smiths, { profession = "blacksmith", minSkill = 276 })), {})
            assertEqual(names(Census.Find(smiths, { profession = "blacksmith", minSkill = 275 })), { "Master" })
            assertEqual(names(Census.Find(smiths, { profession = "mining", minSkill = 200 })), { "Miner" })
            assertEqual(names(Census.Find(smiths, { profession = "mining", maxSkill = 130 })), { "Adept" })
        end)

        it("without a profession, any detected profession's skill may satisfy the range", function()
            assertEqual(names(Census.Find(smiths, { hasProfession = true, minSkill = 250 })), { "Master" })
            assertEqual(names(Census.Find(smiths, { hasProfession = true, minSkill = 225 })),
                { "Master", "Miner" })
            assertEqual(names(Census.Find(smiths, { minSkill = 100, maxSkill = 130 })), { "Adept" })
        end)

        it("combines skill with online only, role and level range", function()
            assertEqual(names(Census.Find(smiths, { profession = "leatherworking", minSkill = 100, onlineOnly = true })),
                { "Master" })
            assertEqual(names(Census.Find(smiths, { minSkill = 100, role = "healer" })), { "Master" })
            assertEqual(names(Census.Find(smiths, { minSkill = 100, minLevel = 45 })), { "Master", "Miner" })
        end)

        it("matches nobody when minSkill is above maxSkill", function()
            assertEqual(Census.Find(smiths, { profession = "leatherworking", minSkill = 200, maxSkill = 100 }), {})
        end)

        it("returns each profession with its skill", function()
            local r = Census.Find(smiths, { profession = "blacksmith" })[1]
            assertEqual(r.professions, { "Leatherworking", "Blacksmith" })
            assertEqual(r.professionDetails, {
                { key = "leatherworking", label = "Leatherworking", skill = 300 },
                { key = "blacksmith", label = "Blacksmith", skill = 275 },
            })
            local quiet
            for _, r in ipairs(Census.Find(smiths, { profession = "leatherworking" })) do
                if r.name == "Quiet" then quiet = r end
            end
            -- no skill written: the detail has no skill field at all
            assertEqual(quiet.professionDetails,
                { { key = "leatherworking", label = "Leatherworking" }, { key = "mining", label = "Mining" } })
        end)

        it("uses custom profession keywords when reading skills", function()
            local s = Config.Defaults()
            s.professions.leatherworking = "hides"
            local custom = { member("Tanner", 30, "ROGUE", "hides 200 LW 50") }
            assertEqual(names(Census.Find(custom, { profession = "leatherworking", minSkill = 150 }, s)), { "Tanner" })
        end)

        it("does not change what the charts count", function()
            local with = Census.Build({ member("A", 30, "MAGE", "LW 260") })
            local without = Census.Build({ member("A", 30, "MAGE", "LW") })
            assertEqual(with.professions, without.professions)
        end)

        it("rejects an unknown profession", function()
            local ok, err = pcall(Census.Find, crew, { profession = "cooking" })
            assertEqual(ok, false)
            assert(tostring(err):find("unknown profession: cooking", 1, true), tostring(err))
        end)

        it("onlineOnly returns only members who are online, treating unknown as offline", function()
            assertEqual(names(Census.Find(crew, { onlineOnly = true })), { "Both", "Dig", "Plain" })
            assertEqual(#Census.Find(crew, { onlineOnly = false }), #crew)
            assertEqual(#Census.Find(crew, {}), #crew)
        end)

        it("onlineOnly combines with every other criterion", function()
            assertEqual(names(Census.Find(crew, { onlineOnly = true, role = "tank" })), { "Both", "Dig" })
            assertEqual(names(Census.Find(crew, { onlineOnly = true, profession = "mining" })), { "Both", "Dig" })
            assertEqual(names(Census.Find(crew, { onlineOnly = true, profession = "mining", minLevel = 35 })), { "Both" })
            assertEqual(names(Census.Find(crew, { onlineOnly = true, role = "dps", maxLevel = 25 })), { "Plain" })
        end)

        it("onlineOnly still respects the alts filter", function()
            local s = Config.Defaults()
            s.includeAlts = false
            local list = { member("Real", 30, "MAGE", "", true), member("Spare", 30, "MAGE", "alt", true) }
            assertEqual(names(Census.Find(list, { onlineOnly = true }, s)), { "Real" })
        end)

        it("agrees with the chart counts for every role (single source of truth)", function()
            local census = Census.Build(roster)
            for _, def in ipairs(Config.ROLES) do
                local sliceCount = 0
                for _, slice in ipairs(census.roles) do
                    if slice.label == def.label then sliceCount = slice.count end
                end
                assertEqual(#Census.Find(roster, { role = def.key }), sliceCount)
            end
        end)
    end)

    describe("Census.Build whole-word matching", function()
        it("counts 'herbs' as Herbalism only, not Blacksmith", function()
            local census = Census.Build({ member("A", 30, "DRUID", "herbs") })
            assertEqual(census.professions, { { label = "Herbalism", count = 1 } })
        end)

        it("does not read a main or an alt inside another word", function()
            local rules = Census.Rules(Config.Defaults())
            local a = Census.Analyze(member("A", 30, "DRUID", "I maintain the salt mine"), rules)
            assertEqual(a.mainWord, nil)
            assertEqual(a.altWord, nil)
        end)

        it("matches the plural forms", function()
            local rules = Census.Rules(Config.Defaults())
            assertEqual(Census.Analyze(member("A", 30, "DRUID", "mains only"), rules).mainWord, "mains")
            assertEqual(Census.Analyze(member("A", 30, "DRUID", "my alts"), rules).altWord, "alts")
        end)

        it("a custom abbreviation no longer matches longer words", function()
            local s = Config.Defaults()
            s.roles.dps = "ret"
            local list = { member("A", 30, "PALADIN", "ret"), member("B", 30, "PALADIN", "secret return") }
            assertEqual(names(Census.Find(list, { role = "dps" }, s)), { "A" })
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

    describe("Game-reported professions (supplemental to notes)", function()
        local function member(note, professions)
            return { name = "A", level = 60, classFile = "MAGE", className = "Mage", note = note,
                online = true, professions = professions }
        end
        local function hits(m)
            return ns.Census.Analyze(m, ns.Census.Rules()).professionHits
        end

        it("uses the game's data when the note says nothing about professions", function()
            local h = hits(member("Raids Tue", { { key = "mining", skill = 300 } }))
            assertEqual(#h, 1)
            assertEqual(h[1].key, "mining")
            assertEqual(h[1].label, "Mining")
            assertEqual(h[1].skill, 300)
            assertEqual(h[1].word, nil)
            assertEqual(h[1].fromGame, true)
        end)

        it("falls back to the note when the game has no data", function()
            for _, game in ipairs({ false, {} }) do
                local h = hits(member("LW 260", game or nil))
                assertEqual(#h, 1)
                assertEqual(h[1].key, "leatherworking")
                assertEqual(h[1].skill, 260)
                assertEqual(h[1].fromGame, nil)
            end
        end)

        it("the game's skill wins over a number in the note, and the keyword is kept", function()
            local h = hits(member("LW 260", { { key = "leatherworking", skill = 275 } }))
            assertEqual(#h, 1)
            assertEqual(h[1].skill, 275)
            assertEqual(h[1].word, "lw")
        end)

        it("keeps the note's skill when the game gives a profession without a rank", function()
            local h = hits(member("LW 260", { { key = "leatherworking" } }))
            assertEqual(h[1].skill, 260)
        end)

        it("takes the union: a game profession plus one only the note mentions", function()
            local h = hits(member("Tailor 150", { { key = "mining", skill = 100 } }))
            assertEqual(#h, 2)
            assertEqual(h[1].key, "mining") -- Config order
            assertEqual(h[2].key, "tailor")
            assertEqual(h[2].skill, 150)
        end)

        it("feeds the census charts and the Finder", function()
            local members = {
                member("Raids Tue", { { key = "mining", skill = 300 } }),
                member("tank, LW 100", nil),
            }
            local census = ns.Census.Build(members)
            local counts = {}
            for _, slice in ipairs(census.professions) do counts[slice.label] = slice.count end
            assertEqual(counts, { Mining = 1, Leatherworking = 1 })

            local found = ns.Census.Find(members, { profession = "mining", minSkill = 250 })
            assertEqual(#found, 1)
            assertEqual(found[1].professionDetails, { { key = "mining", label = "Mining", skill = 300 } })
        end)

        it("never excludes anyone, and a third profession is logged with a readable message", function()
            local m = member("Tailor, Herb", { { key = "mining", skill = 1 }, { key = "alchemy", skill = 1 } })
            local census = ns.Census.Build({ m })
            assertEqual(census.total, 1)
            assertEqual(#census.conflicts, 1)
            assertEqual(census.conflicts[1].kind, "too-many-professions")
            -- game-only hits have no keyword, so they are listed by label alone (Config order)
            assert(string.find(census.conflicts[1].message, "Mining, Herbalism ('herb'), Tailor ('tailor'), Alchemy", 1, true),
                census.conflicts[1].message)
        end)
    end)
end
