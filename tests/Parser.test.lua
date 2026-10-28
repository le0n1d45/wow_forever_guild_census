return function(ns)
    local Parser = ns.Parser

    describe("Parser.ParseRoles", function()
        it("finds a single role", function()
            assertEqual(Parser.ParseRoles("Tank"), { "tank" })
        end)

        it("is case-insensitive and ignores punctuation", function()
            assertEqual(Parser.ParseRoles("HEALER!!"), { "healer" })
        end)

        it("finds multiple roles in order of appearance", function()
            assertEqual(Parser.ParseRoles("Tank/DPS"), { "tank", "dps" })
        end)

        it("does not double count aliases of the same role", function()
            assertEqual(Parser.ParseRoles("dps dd damage"), { "dps" })
        end)

        it("does not match keywords inside other words", function()
            assertEqual(Parser.ParseRoles("tankard of ale, healthy"), {})
        end)

        it("handles nil and empty notes", function()
            assertEqual(Parser.ParseRoles(nil), {})
            assertEqual(Parser.ParseRoles(""), {})
        end)
    end)

    describe("Parser.ParseProfessions", function()
        it("finds full names and abbreviations", function()
            assertEqual(Parser.ParseProfessions("LW / Mining"), { "Leatherworking", "Mining" })
        end)

        it("dedupes alias and full name", function()
            assertEqual(Parser.ParseProfessions("herb herbalism"), { "Herbalism" })
        end)

        it("returns nothing for notes without professions", function()
            assertEqual(Parser.ParseProfessions("Alt of Bob, raids Tue"), {})
        end)

        it("handles nil notes", function()
            assertEqual(Parser.ParseProfessions(nil), {})
        end)
    end)
end
