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
end
