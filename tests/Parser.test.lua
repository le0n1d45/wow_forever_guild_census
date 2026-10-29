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

        it("matches the full word as well as the abbreviation", function()
            assertEqual(match("Healer", Config.ROLES), { "Healer" })
            assertEqual(match("heal", Config.ROLES), { "Healer" })
            assertEqual(match("tanking", Config.ROLES), { "Tank" })
            assertEqual(match("Retribution", Config.ROLES), { "DPS" })
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

        it("the default Leatherworking keywords match the word 'Leatherworking'", function()
            local hits = Parser.Detect("Leatherworking 300", rules, true)
            assertEqual(hits[1].key, "leatherworking")
            assertEqual(hits[1].skill, 300)
            assertEqual(Parser.Detect("leatherworker 225", rules, true)[1].skill, 225)
            assertEqual(Parser.Detect("LW 150", rules, true)[1].skill, 150)
        end)

        it("does not look for skills unless asked", function()
            assertEqual(Parser.Detect("LW 260", rules)[1].skill, nil)
        end)
    end)

    describe("Parser whole-word matching", function()
        local function words(list) return Parser.ParseList(list) end

        it("does not match inside a longer word (the 'herbs' / 'bs' case)", function()
            assert(not Parser.ContainsAny("herbs", words("bs")))
            assert(not Parser.ContainsAny("a secret", words("ret")))
            assert(not Parser.ContainsAny("return of the king", words("ret")))
            assert(not Parser.ContainsAny("salt and pepper", words("alt")))
            assert(not Parser.ContainsAny("maintain", words("main")))
            assert(not Parser.ContainsAny("tankard", words("tank")))
            assert(not Parser.ContainsAny("category", words("cat")))
        end)

        it("an abbreviation does not match its longer spelling unless that is listed too", function()
            assert(not Parser.ContainsAny("healer", words("heal")))
            assert(Parser.ContainsAny("healer", words("heal, healer")))
        end)

        it("treats punctuation, digits and the ends of the note as boundaries", function()
            for _, note in ipairs({ "tank", "(tank)", "tank,", "tank.", "tank/dps", "a-tank-b", "tank!", "tank2", "2tank", "LW260" }) do
                local keyword = note == "LW260" and "lw" or "tank"
                assert(Parser.ContainsAny(note, words(keyword)), note .. " should match " .. keyword)
            end
        end)

        it("is case-insensitive", function()
            assert(Parser.ContainsAny("TANK", words("tank")))
            assert(Parser.ContainsAny("tank", words("TANK")))
        end)

        it("finds a later whole-word occurrence after an embedded one", function()
            assert(Parser.ContainsAny("herbs bs", words("bs")))
            assert(not Parser.ContainsAny("herbs", words("bs")))
        end)

        it("matches keywords that contain punctuation as a whole", function()
            assert(Parser.ContainsAny("crit-chicken", words("crit-chicken")))
            assert(Parser.ContainsAny("my crit-chicken!", words("crit-chicken")))
            assert(not Parser.ContainsAny("supercrit-chicken", words("crit-chicken")))
            assert(not Parser.ContainsAny("crit-chickens", words("crit-chicken")))
        end)

        it("only checks the boundary on a side where the keyword has a letter", function()
            assert(Parser.ContainsAny("a+b", words("+")))
            assert(Parser.ContainsAny("x+y", words("+")))
        end)

        it("keeps 'herbs' from reading as Blacksmith with the default keywords", function()
            local rules = Parser.Compile(Config.PROFESSIONS)
            assertEqual(Parser.Match("herbs", rules), { "Herbalism" })
            assertEqual(Parser.Match("herbs 200", rules), { "Herbalism" })
            assertEqual(Parser.Match("herbs, bs", rules), { "Herbalism", "Blacksmith" })
        end)

        it("does not read a skill from a keyword buried in another word", function()
            local rules = Parser.Compile(Config.PROFESSIONS)
            local hits = Parser.Detect("herbs 200", rules, true)
            assertEqual(#hits, 1)
            assertEqual(hits[1].key, "herbalism")
            assertEqual(hits[1].skill, 200)
        end)
    end)

    describe("Default keyword lists", function()
        local function listed(def)
            local set = {}
            for _, word in ipairs(Parser.ParseList(def.default)) do set[word] = true end
            return set
        end

        it("keep every abbreviation from every earlier default", function()
            for _, group in ipairs({ Config.ROLES, Config.PROFESSIONS, Config.IDENTITY }) do
                for _, def in ipairs(group) do
                    local current = listed(def)
                    for _, old in ipairs(def.replaces or {}) do
                        for _, word in ipairs(Parser.ParseList(old)) do
                            assert(current[word], string.format("%s dropped '%s'", def.label, word))
                        end
                    end
                end
            end
        end)

        it("also list the full words players write", function()
            local expected = {
                tank = { "tank", "tanks", "tanking", "protection" },
                healer = { "healer", "healers", "healing", "heals", "restoration", "discipline" },
                dps = { "dps", "damage", "retribution", "enhancement", "elemental" },
                leatherworking = { "leatherworking", "leatherworker" },
                herbalism = { "herbalism", "herbalist", "herbs" },
                enchanting = { "enchanting", "enchanter" },
                blacksmith = { "blacksmith", "blacksmithing", "armorsmithing", "weaponsmithing" },
                engineering = { "engineer", "engineering" },
                tailor = { "tailor", "tailoring" },
                alchemy = { "alchemy", "alchemist" },
                skinning = { "skinning", "skinner" },
                mining = { "mining", "miner" },
                main = { "main", "mains" },
                alt = { "alt", "alts" },
            }
            for _, group in ipairs({ Config.ROLES, Config.PROFESSIONS, Config.IDENTITY }) do
                for _, def in ipairs(group) do
                    local current = listed(def)
                    for _, word in ipairs(expected[def.key] or {}) do
                        assert(current[word], string.format("%s should list '%s'", def.label, word))
                    end
                end
            end
        end)

        it("have a no-letter-touching match for each listed word on its own", function()
            for _, group in ipairs({ Config.ROLES, Config.PROFESSIONS, Config.IDENTITY }) do
                for _, def in ipairs(group) do
                    for _, word in ipairs(Parser.ParseList(def.default)) do
                        assert(Parser.ContainsAny("x, " .. word .. ".", { word }), def.label .. ": " .. word)
                    end
                end
            end
        end)
    end)
end
