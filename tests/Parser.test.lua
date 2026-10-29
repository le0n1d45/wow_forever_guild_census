return function(ns)
    local Parser = ns.Parser
    local Config = ns.Config

    local function match(note, defs, values)
        return Parser.Match(note, Parser.Compile(defs, values))
    end

    describe("Parser.ParseList", function()
        it("splits on commas, trims and lowercases", function()
            assertEqual(Parser.ParseList(" Tank, BEAR ,prot"), { "tank", "bear", "prot" })
        end)

        it("drops empty entries", function()
            assertEqual(Parser.ParseList(",, a ,,"), { "a" })
        end)

        it("handles empty and non-string input", function()
            assertEqual(Parser.ParseList(""), {})
            assertEqual(Parser.ParseList(nil), {})
        end)

        it("keeps hyphenated words intact", function()
            assertEqual(Parser.ParseList("crit-chicken, moonkin"), { "crit-chicken", "moonkin" })
        end)
    end)

    describe("Parser.Match (roles)", function()
        it("matches keywords case-insensitively", function()
            assertEqual(match("TANK", Config.ROLES), { "Tank" })
        end)

        it("matches by substring, so 'heal' finds 'healer'", function()
            assertEqual(match("Healer", Config.ROLES), { "Healer" })
        end)

        it("returns every role present, in rule order", function()
            assertEqual(match("dps / tank", Config.ROLES), { "Tank", "DPS" })
        end)

        it("matches spec words from the defaults", function()
            assertEqual(match("Resto Druid", Config.ROLES), { "Healer" })
            assertEqual(match("Moonkin", Config.ROLES), { "DPS" })
            assertEqual(match("crit-chicken", Config.ROLES), { "DPS" })
            assertEqual(match("bear", Config.ROLES), { "Tank" })
        end)

        it("returns nothing for notes without keywords", function()
            assertEqual(match("Raids Tue", Config.ROLES), {})
        end)

        it("handles nil and empty notes", function()
            assertEqual(match(nil, Config.ROLES), {})
            assertEqual(match("", Config.ROLES), {})
        end)

        it("uses custom keyword lists from settings", function()
            assertEqual(match("meat shield", Config.ROLES, { tank = "shield" }), { "Tank" })
            assertEqual(match("tank", Config.ROLES, { tank = "shield" }), {})
        end)

        it("an emptied box matches nothing", function()
            assertEqual(match("tank", Config.ROLES, { tank = "" }), {})
        end)
    end)

    describe("Parser.Match (professions)", function()
        it("finds abbreviations and full names", function()
            assertEqual(match("LW / Mining", Config.PROFESSIONS), { "Leatherworking", "Mining" })
        end)

        it("reports a profession once even when several keywords match", function()
            assertEqual(match("herb herbalism", Config.PROFESSIONS), { "Herbalism" })
        end)

        it("uses the user-facing labels", function()
            assertEqual(match("bs tailoring", Config.PROFESSIONS), { "Blacksmith", "Tailor" })
        end)

        it("ignores professions that are not configured", function()
            assertEqual(match("cooking fishing", Config.PROFESSIONS), {})
        end)
    end)

    describe("Parser.ContainsAny", function()
        it("detects alt and main keywords", function()
            assert(Parser.ContainsAny("Alt of Bob", Parser.ParseList("alt")))
            assert(Parser.ContainsAny("MAIN tank", Parser.ParseList("main")))
            assert(not Parser.ContainsAny("Raids Tue", Parser.ParseList("alt")))
        end)

        it("is false for nil notes or empty keyword lists", function()
            assert(not Parser.ContainsAny(nil, { "alt" }))
            assert(not Parser.ContainsAny("alt", {}))
        end)
    end)

    describe("Parser.SkillAfter", function()
        local lw = Parser.ParseList("lw, leatherworker")

        it("reads a number written after a keyword in the common formats", function()
            assertEqual(Parser.SkillAfter("LW 260", lw), 260)
            assertEqual(Parser.SkillAfter("lw: 260", lw), 260)
            assertEqual(Parser.SkillAfter("LW-260", lw), 260)
            assertEqual(Parser.SkillAfter("lw (260)", lw), 260)
            assertEqual(Parser.SkillAfter("LW[260]", lw), 260)
            assertEqual(Parser.SkillAfter("lw=260", lw), 260)
            assertEqual(Parser.SkillAfter("LW260", lw), 260)
            assertEqual(Parser.SkillAfter("LW - 260", lw), 260)
        end)

        it("takes the first number of 260/300 style notes", function()
            assertEqual(Parser.SkillAfter("LW 260/300", lw), 260)
        end)

        it("works anywhere in the note and with any of the keywords", function()
            assertEqual(Parser.SkillAfter("Tank, leatherworker 150, mining", lw), 150)
        end)

        it("returns nil when no number follows", function()
            assertEqual(Parser.SkillAfter("LW", lw), nil)
            assertEqual(Parser.SkillAfter("LW / Mining 300", lw), nil)
            assertEqual(Parser.SkillAfter("tank 260 LW", lw), nil)
            assertEqual(Parser.SkillAfter("", lw), nil)
            assertEqual(Parser.SkillAfter(nil, lw), nil)
        end)

        it("ignores numbers that are not 1-3 digits", function()
            assertEqual(Parser.SkillAfter("LW 2600", lw), nil)
            assertEqual(Parser.SkillAfter("LW 0", lw), nil)
        end)

        it("skips an occurrence without a number and finds a later one", function()
            assertEqual(Parser.SkillAfter("lw main, lw 225", lw), 225)
        end)
    end)

    describe("Parser.Detect with skills", function()
        local rules = Parser.Compile(Config.PROFESSIONS)

        it("attaches a skill to each profession that has one", function()
            local hits = Parser.Detect("LW 260, mining, BS: 310", rules, true)
            local skills = {}
            for _, h in ipairs(hits) do skills[h.key] = h.skill end
            assertEqual(skills, { leatherworking = 260, blacksmith = 310 })
            assertEqual(#hits, 3)
        end)

        it("does not look for skills unless asked", function()
            assertEqual(Parser.Detect("LW 260", rules)[1].skill, nil)
        end)
    end)
end
