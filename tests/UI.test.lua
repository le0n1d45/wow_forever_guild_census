-- Headless UI tests: run the real addon files against the strict WoW stub.
return function()
    local function loadAddon()
        InstallWowStub()
        local ns = {}
        for _, file in ipairs({
            "Parser.lua", "Census.lua", "Demo.lua", "Roster.lua",
            "PieChart.lua", "UI.lua", "GuildCensus.lua",
        }) do
            loadAddonFile(ns, file)
        end
        return ns
    end

    -- Collapses the 360 pie lines into consecutive same-colour runs.
    local function runs(chart)
        local result = {}
        for _, line in ipairs(chart.lines) do
            local key = line.shown and table.concat(line.color, ",") or "hidden"
            local last = result[#result]
            if last and last.key == key then
                last.length = last.length + 1
            else
                result[#result + 1] = { key = key, length = 1 }
            end
        end
        return result
    end

    describe("Demo.Generate", function()
        local ns = loadAddon()

        it("returns the requested number of members", function()
            assertEqual(#ns.Demo.Generate(80), 80)
        end)

        it("is deterministic for a given seed", function()
            assertEqual(ns.Demo.Generate(20, 7), ns.Demo.Generate(20, 7))
        end)

        it("produces valid members and non-empty role/profession data", function()
            local members = ns.Demo.Generate(80)
            for _, m in ipairs(members) do
                assert(m.level >= 1 and m.level <= 60, "level out of range: " .. m.level)
                assert(m.classFile and m.className and m.note)
            end
            local census = ns.Census.Build(members)
            assert(#census.roles > 0 and #census.professions > 0)
        end)
    end)

    describe("UI (headless)", function()
        it("registers the slash command and event handlers without error", function()
            local ns = loadAddon()
            assert(SlashCmdList["GUILDCENSUS"])
            assert(ns.UI)
        end)

        it("shows 'not in a guild' with an empty roster", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("")
            assertEqual(GuildCensusWindow.summary.text, "You are not in a guild.")
        end)

        it("toggles the window on repeated /gcensus", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("")
            assertEqual(GuildCensusWindow.shown, true)
            SlashCmdList["GUILDCENSUS"]("")
            assertEqual(GuildCensusWindow.shown, false)
        end)

        it("reads the real roster API shape", function()
            InstallWowStub({ guild = {
                { name = "A", level = 60, className = "Priest", classFile = "PRIEST", note = "healer" },
                { name = "B", level = 30, className = "Mage", classFile = "MAGE", note = "dps, tailoring" },
            } })
            local ns = {}
            for _, f in ipairs({ "Parser.lua", "Census.lua", "Demo.lua", "Roster.lua", "PieChart.lua", "UI.lua", "GuildCensus.lua" }) do
                loadAddonFile(ns, f)
            end
            assertEqual(ns.Roster.Read(), {
                { level = 60, className = "Priest", classFile = "PRIEST", note = "healer" },
                { level = 30, className = "Mage", classFile = "MAGE", note = "dps, tailoring" },
            })
            SlashCmdList["GUILDCENSUS"]("")
            assertEqual(GuildCensusWindow.summary.text, "2 guild members")
        end)

        it("demo mode fills every chart with legends", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local w = GuildCensusWindow
            assertEqual(w.summary.text, "80 guild members (demo data)")
            for key, chart in pairs(w.charts) do
                assertEqual(chart.empty.shown, false)
                assert(chart.legend[1].shown and chart.legend[1].text:find("%("), key .. " has no legend")
            end
        end)

        it("demo mode toggles off on a second /gcensus demo", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            SlashCmdList["GUILDCENSUS"]("demo")
            assertEqual(GuildCensusWindow.summary.text, "You are not in a guild.")
        end)

        it("pie slices span the circle in proportion to their counts", function()
            local ns = loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local census = ns.Census.Build(ns.Demo.Generate(80))
            for _, key in ipairs({ "roles", "professions", "classes", "levels" }) do
                local chartRuns = runs(GuildCensusWindow.charts[key])
                local slices = census[key]
                assertEqual(#chartRuns, #slices)
                local total = 0
                for _, s in ipairs(slices) do total = total + s.count end
                for i, s in ipairs(slices) do
                    local expected = 360 * s.count / total
                    assert(math.abs(chartRuns[i].length - expected) <= 1.5,
                        string.format("%s slice %s: %d segments, expected ~%.1f",
                            key, s.label, chartRuns[i].length, expected))
                end
            end
        end)

        it("every pie segment ends on the circle edge", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            for _, chart in pairs(GuildCensusWindow.charts) do
                for _, line in ipairs(chart.lines) do
                    local r = math.sqrt(line.endX ^ 2 + line.endY ^ 2)
                    assert(math.abs(r - 70) < 1e-6, "segment radius " .. r)
                    assertEqual(line.startX, 0)
                    assertEqual(line.startY, 0)
                end
            end
        end)
    end)
end
