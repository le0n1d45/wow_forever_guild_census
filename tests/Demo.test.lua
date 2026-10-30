-- The demo roster exists so every Finder filter can be tried without a guild, so these
-- tests guard its coverage: no dungeon, role, profession or filter combination should
-- quietly come back empty.
return function(ns)
    local Census, Config, Dungeons, Demo = ns.Census, ns.Config, ns.Dungeons, ns.Demo
    local members = Demo.Generate()

    local function count(criteria, settings)
        return #Census.Find(members, criteria, settings)
    end

    describe("Demo roster coverage", function()
        it("is guild-sized, deterministic and larger than the Finder's 300-row cap", function()
            assertEqual(#members, 500)
            assertEqual(Demo.Generate(40, 9), Demo.Generate(40, 9))
            assert(#members > 300, "needs to exercise the row cap")
        end)

        it("has unique, real-looking names even beyond the curated list", function()
            local seen = {}
            for _, m in ipairs(Demo.Generate(1000)) do
                assert(m.name:match("^%a+$"), "bad name: " .. m.name)
                assert(not seen[m.name], "duplicate name: " .. m.name)
                seen[m.name] = true
            end
        end)

        it("spreads members across every ten-level bracket", function()
            local buckets = {}
            for _, m in ipairs(members) do
                assert(m.level >= 5 and m.level <= 60, "level out of range: " .. m.level)
                local b = math.floor((m.level - 1) / 10)
                buckets[b] = (buckets[b] or 0) + 1
            end
            for b = 0, 5 do
                assert((buckets[b] or 0) >= 40, string.format("bracket %d-%d has too few", b * 10 + 1, b * 10 + 10))
            end
        end)

        it("has about half the roster online", function()
            local online = 0
            for _, m in ipairs(members) do if m.online then online = online + 1 end end
            assert(online > #members * 0.4 and online < #members * 0.6, "online: " .. online)
        end)

        it("gives every dungeon tanks, healers and DPS to find", function()
            for _, d in ipairs(Dungeons.LIST) do
                for _, role in ipairs({ "tank", "healer", "dps" }) do
                    local n = count({ role = role, minLevel = d.minLevel, maxLevel = d.maxLevel })
                    assert(n >= 3, string.format("%s has only %d %s", d.name, n, role))
                end
            end
        end)

        it("gives every dungeon online players, overall and per role", function()
            for _, d in ipairs(Dungeons.LIST) do
                local range = { minLevel = d.minLevel, maxLevel = d.maxLevel, onlineOnly = true }
                assert(count(range) >= 3, d.name .. " has too few online players")
                for _, role in ipairs({ "tank", "healer", "dps" }) do
                    range.role = role
                    assert(count(range) >= 1, string.format("%s has no online %s", d.name, role))
                end
            end
        end)

        it("has plenty of players for every profession, online and across every role", function()
            for _, def in ipairs(Config.PROFESSIONS) do
                assert(count({ profession = def.key }) >= 20, def.label .. " is too rare")
                assert(count({ profession = def.key, onlineOnly = true }) >= 10, def.label .. " has too few online")
                for _, role in ipairs({ "tank", "healer", "dps" }) do
                    assert(count({ profession = def.key, role = role }) >= 3,
                        string.format("no %s %s", def.label, role))
                end
            end
        end)

        it("has skill levels for every profession, across the whole skill range", function()
            local brackets = { { 1, 75 }, { 76, 150 }, { 151, 225 }, { 226, 300 } }
            for _, def in ipairs(Config.PROFESSIONS) do
                for _, b in ipairs(brackets) do
                    local n = count({ profession = def.key, minSkill = b[1], maxSkill = b[2] })
                    assert(n >= 3, string.format("%s has only %d at skill %d-%d", def.label, n, b[1], b[2]))
                end
                assert(count({ profession = def.key, minSkill = 225, onlineOnly = true }) >= 1,
                    def.label .. " has nobody online at high skill")
            end
        end)

        it("leaves some members without a written skill, so the filter has something to exclude", function()
            for _, def in ipairs(Config.PROFESSIONS) do
                assert(count({ profession = def.key }) > count({ profession = def.key, minSkill = 1 }),
                    def.label .. " should include members with no written skill")
            end
        end)

        it("supports the full combination: dungeon + role + profession + online", function()
            local d = Dungeons.Get("deadmines")
            local n = count({ minLevel = d.minLevel, maxLevel = d.maxLevel, role = "tank",
                profession = "mining", onlineOnly = true })
            assert(n >= 1, "the combined search should find someone")
        end)
    end)

    describe("Demo roster alts, mains and conflicts", function()
        it("has declared mains and alts so the alts/mains settings do something", function()
            local all = Census.Build(members).total
            local noAlts = Config.Defaults()
            noAlts.includeAlts = false
            local onlyMains = Config.Defaults()
            onlyMains.onlyMains = true
            assertEqual(all, #members)
            local withoutAlts = Census.Build(members, noAlts).total
            local mains = Census.Build(members, onlyMains).total
            assert(withoutAlts < all and withoutAlts > all * 0.7, "alts excluded: " .. withoutAlts)
            assert(mains >= 30 and mains < all * 0.3, "only mains: " .. mains)
        end)

        it("has conflicts of every kind, and only the deliberately planted ones", function()
            local census = Census.Build(members)
            local kinds, planted = {}, {}
            for i, m in ipairs(members) do
                if i % 25 == 7 then planted[m.name] = true end
            end
            for _, c in ipairs(census.conflicts) do
                kinds[c.kind] = true
                assert(planted[c.name], "unplanted conflict (a note word is hitting a keyword): "
                    .. c.name .. " / " .. c.note .. " / " .. c.message)
            end
            for _, kind in ipairs({ "main-and-alt", "too-many-professions", "role-class-mismatch" }) do
                assert(kinds[kind], "no demo conflict of kind " .. kind)
            end
            assert(#census.conflicts >= 10, "the Logs tab should have enough entries to scroll")
        end)

        it("includes members who hold all three roles without it being a conflict", function()
            local census = Census.Build(members)
            local conflicted = {}
            for _, c in ipairs(census.conflicts) do conflicted[c.name] = true end
            local rules = Census.Rules(Config.Defaults())
            local allThree = 0
            for _, m in ipairs(members) do
                local a = Census.Analyze(m, rules)
                if #a.roleHits == 3 then
                    allThree = allThree + 1
                    assert(not conflicted[m.name], m.name .. " holding three roles must not be a conflict")
                end
            end
            assert(allThree >= 3, "expected some all-role members, got " .. allThree)
        end)

        it("counts pure-DPS classes as DPS even with empty notes", function()
            local pure = { WARLOCK = true, HUNTER = true, MAGE = true, ROGUE = true }
            local checked = 0
            for _, m in ipairs(members) do
                if pure[m.classFile] and m.note == "" then
                    checked = checked + 1
                    local found = false
                    for _, r in ipairs(Census.Find({ m }, { role = "dps" })) do found = true end
                    assert(found, m.name .. " (" .. m.classFile .. ") should count as DPS")
                end
            end
            assert(checked > 0, "demo should include pure-DPS members with empty notes")
        end)

        it("stands in for the game's profession data on some members, with and without a note", function()
            local withBoth, gameOnly = 0, 0
            local rules = ns.Census.Rules()
            for _, m in ipairs(ns.Demo.Generate()) do
                if m.professions then
                    for _, entry in ipairs(m.professions) do
                        assert(entry.key and entry.skill, "game data needs a profession and a skill")
                    end
                    if #ns.Parser.Detect(m.note, rules.professions) == 0 then
                        gameOnly = gameOnly + 1
                    else
                        withBoth = withBoth + 1
                    end
                end
            end
            assert(withBoth > 0, "demo should have members with both a note and game data")
            assert(gameOnly > 0, "demo should have members whose only profession source is game data")
        end)
    end)
end
