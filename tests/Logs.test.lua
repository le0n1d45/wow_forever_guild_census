return function(ns)
    local Logs = ns.Logs

    local conflict = {
        name = "Bob", level = 60, className = "Mage",
        note = "Main, alt of Bob", message = "Detected as both a main ('main') and an alt ('alt')",
    }

    describe("Logs.FormatEntry", function()
        it("shows the player, level, class, message and the offending note", function()
            assertEqual(Logs.FormatEntry(conflict),
                "|cffffd100Bob|r (L60 Mage): Detected as both a main ('main') and an alt ('alt')\n"
                .. "    Note: \"Main, alt of Bob\"")
        end)

        it("escapes pipe characters so notes cannot inject colour codes", function()
            local entry = Logs.FormatEntry({
                name = "Bob", level = 1, className = "Mage", message = "m", note = "|cffff0000red|r",
            })
            assert(entry:find("||cffff0000red||r", 1, true), entry)
        end)

        it("tolerates missing level and class", function()
            local entry = Logs.FormatEntry({ name = "Bob", message = "m", note = "" })
            assert(entry:find("(L? ?)", 1, true), entry)
        end)
    end)

    describe("Logs.FormatAll", function()
        it("says so when there are no conflicts", function()
            assertEqual(Logs.FormatAll({}), "No conflicts detected.")
        end)

        it("separates entries with a blank line", function()
            local text = Logs.FormatAll({ conflict, conflict })
            assertEqual(select(2, text:gsub("\n\n", "")), 1)
        end)
    end)
end
