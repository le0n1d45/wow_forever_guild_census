-- Headless UI tests: run the real addon files against the strict WoW stub.
return function()
    -- Loads the addon like the client does and fires ADDON_LOADED so settings initialise.
    local function loadAddon(options)
        InstallWowStub(options)
        GuildCensusDB = nil
        local ns = {}
        for _, file in ipairs(ADDON_FILES) do
            loadAddonFile(ns, file)
        end
        local frame = GuildCensusEventFrame
        frame.scripts.OnEvent(frame, "ADDON_LOADED", "GuildCensus")
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

    local function click(control)
        control.scripts.OnClick(control)
    end

    local function type_(box, text)
        box:SetText(text)
        box.scripts.OnTextChanged(box, true)
    end

    describe("Demo.Generate", function()
        local ns = loadAddon()

        it("returns the requested number of members", function()
            assertEqual(#ns.Demo.Generate(80), 80)
        end)

        it("is deterministic for a given seed", function()
            assertEqual(ns.Demo.Generate(20, 7), ns.Demo.Generate(20, 7))
        end)

        it("gives every member a unique, real-looking name", function()
            local seen = {}
            for _, m in ipairs(ns.Demo.Generate(200)) do
                assert(m.name:match("^%a"), "bad name: " .. m.name)
                assert(not m.name:find("Player"), "placeholder name: " .. m.name)
                assert(not seen[m.name], "duplicate name: " .. m.name)
                seen[m.name] = true
            end
            assertEqual(ns.Demo.Generate(1)[1].name, "Thalindra")
        end)

        it("gives members a believable mix of online and offline", function()
            local online = 0
            local members = ns.Demo.Generate(80)
            for _, m in ipairs(members) do
                assert(type(m.online) == "boolean", "online must be a boolean for " .. m.name)
                if m.online then online = online + 1 end
            end
            assert(online > 10 and online < 50, "expected a mix of online/offline, got " .. online .. " online")
        end)

        it("produces valid members and non-empty role/profession data", function()
            local members = ns.Demo.Generate(80)
            for _, m in ipairs(members) do
                assert(m.level >= 1 and m.level <= 60, "level out of range: " .. m.level)
                assert(m.classFile and m.className and m.note)
            end
            local census = ns.Census.Build(members, ns.settings)
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
            local ns = loadAddon({ guild = {
                { name = "A", level = 60, className = "Priest", classFile = "PRIEST", note = "healer" },
                { name = "B", level = 30, className = "Mage", classFile = "MAGE", note = "dps, tailoring", online = false },
            } })
            assertEqual(ns.Roster.Read(), {
                { name = "A", level = 60, className = "Priest", classFile = "PRIEST", note = "healer", online = true },
                { name = "B", level = 30, className = "Mage", classFile = "MAGE", note = "dps, tailoring", online = false },
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
            local census = ns.Census.Build(ns.Demo.Generate(80), ns.settings)
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

    describe("Census / Logs tabs (headless)", function()
        local function conflictedGuild()
            return { guild = {
                { name = "Bob-Realm", level = 60, className = "Mage", classFile = "MAGE", note = "healer" },
                { name = "Amy-Realm", level = 60, className = "Druid", classFile = "DRUID", note = "tank heal dps" },
            } }
        end

        it("opens on the Census tab with Logs hidden", function()
            loadAddon(conflictedGuild())
            SlashCmdList["GUILDCENSUS"]("")
            local w = GuildCensusWindow
            assertEqual(w.activeTab, "census")
            assertEqual(w.censusPane.shown, true)
            assertEqual(w.logsPane.shown, false)
            assertEqual(w.censusTab.enabled, false)
            assertEqual(w.logsTab.enabled, true)
        end)

        it("the Logs tab shows the conflict count", function()
            local ns = loadAddon(conflictedGuild())
            SlashCmdList["GUILDCENSUS"]("")
            assertEqual(GuildCensusWindow.logsTab.text, "Logs (1)")
            assertEqual(#ns.UI.lastCensus.conflicts, 1)
        end)

        it("switching tabs shows exactly one pane at a time", function()
            loadAddon(conflictedGuild())
            SlashCmdList["GUILDCENSUS"]("")
            local w = GuildCensusWindow
            click(w.logsTab)
            assertEqual(w.censusPane.shown, false)
            assertEqual(w.logsPane.shown, true)
            assertEqual(w.logsTab.enabled, false)
            assertEqual(w.censusTab.enabled, true)
            click(w.censusTab)
            assertEqual(w.censusPane.shown, true)
            assertEqual(w.logsPane.shown, false)
        end)

        it("lists the conflict with the player and the offending note", function()
            loadAddon(conflictedGuild())
            SlashCmdList["GUILDCENSUS"]("")
            click(GuildCensusWindow.logsTab)
            local pane = GuildCensusWindow.logsPane
            assertEqual(pane.summary.text, "1 conflict among 2 guild members")
            assert(pane.text.text:find("Bob", 1, true) and pane.text.text:find("Note: \"healer\"", 1, true),
                pane.text.text)
        end)

        it("/gcensus logs opens the window straight to the Logs tab", function()
            loadAddon(conflictedGuild())
            SlashCmdList["GUILDCENSUS"]("logs")
            assertEqual(GuildCensusWindow.shown, true)
            assertEqual(GuildCensusWindow.activeTab, "logs")
            assertEqual(GuildCensusWindow.logsPane.shown, true)
        end)

        it("says no conflicts when the guild is clean", function()
            loadAddon({ guild = {
                { name = "Amy", level = 60, className = "Druid", classFile = "DRUID", note = "tank heal dps" },
            } })
            SlashCmdList["GUILDCENSUS"]("")
            assertEqual(GuildCensusWindow.logsPane.text.text, "No conflicts detected.")
            assertEqual(GuildCensusWindow.logsTab.text, "Logs (0)")
        end)

        it("updates the logs when settings change", function()
            loadAddon({ guild = {
                { name = "Bob", level = 60, className = "Druid", classFile = "DRUID", note = "main alt" },
            } })
            SlashCmdList["GUILDCENSUS"]("")
            assertEqual(GuildCensusWindow.logsPane.summary.text, "1 conflict among 1 guild members")
            type_(GuildCensusOptionsPanel.controls.identity.alt, "twink")
            assertEqual(GuildCensusWindow.logsPane.summary.text, "0 conflicts among 1 guild members")
        end)

        it("demo mode produces conflicts to inspect", function()
            local ns = loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            assert(#ns.UI.lastCensus.conflicts > 0, "demo roster should contain conflicts")
            assert(GuildCensusWindow.logsPane.text.text:find("Note:", 1, true))
        end)

        it("keeps the selected tab when the window is reopened", function()
            loadAddon(conflictedGuild())
            SlashCmdList["GUILDCENSUS"]("logs")
            SlashCmdList["GUILDCENSUS"]("")
            SlashCmdList["GUILDCENSUS"]("")
            assertEqual(GuildCensusWindow.activeTab, "logs")
        end)
    end)

    describe("Finder tab (headless)", function()
        local function finderGuild(extra)
            local options = { guild = {
                { name = "Tanky", level = 15, className = "Warrior", classFile = "WARRIOR", note = "Tank, mining" },
                { name = "Bulwark", level = 20, className = "Paladin", classFile = "PALADIN", note = "prot / heal" },
                { name = "Mender", level = 18, className = "Priest", classFile = "PRIEST", note = "healer" },
                { name = "Zap", level = 18, className = "Mage", classFile = "MAGE", note = "" },
                { name = "Elder", level = 60, className = "Warrior", classFile = "WARRIOR", note = "main tank" },
            } }
            for k, v in pairs(extra or {}) do options[k] = v end
            return options
        end

        local function openFinder()
            SlashCmdList["GUILDCENSUS"]("finder")
            return GuildCensusWindow.finderPane
        end

        -- Reads the role dropdown's choices the way the client would, for any of the
        -- three selector kinds. Returns a list of { text, selected(), choose() }.
        local function roleChoices(pane)
            local choices = {}
            if pane.roleControl == "modern" then
                local root = { CreateRadio = function(_, text, isSelected, setSelected)
                    choices[#choices + 1] = { text = text, selected = isSelected, choose = setSelected }
                end }
                pane.roleWidget.menuGenerator(pane.roleWidget, root)
            elseif pane.roleControl == "legacy" then
                LegacyMenuItems = {}
                pane.roleWidget.dropdownInit()
                for _, info in ipairs(LegacyMenuItems) do
                    choices[#choices + 1] = {
                        text = info.text, selected = function() return info.checked end, choose = info.func,
                    }
                end
            end
            return choices
        end

        -- Picks a role by its label from the dropdown (or by cycling, in the fallback).
        local function chooseRole(pane, label)
            if pane.roleControl == "cycle" then
                for _ = 1, 4 do
                    if pane.roleWidget.text == label then return end
                    click(pane.roleWidget)
                end
                error("role not reachable: " .. label)
            end
            for _, choice in ipairs(roleChoices(pane)) do
                if choice.text == label then return choice.choose() end
            end
            error("no such role choice: " .. label)
        end

        local function visibleRows(pane)
            local rows = {}
            for _, row in ipairs(pane.rows) do
                if row.shown then rows[#rows + 1] = row end
            end
            return rows
        end

        local function rowNames(pane)
            local names = {}
            for _, row in ipairs(visibleRows(pane)) do
                names[#names + 1] = row.name.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            end
            return names
        end

        it("is a third tab and /gcensus finder opens straight to it", function()
            loadAddon(finderGuild())
            local pane = openFinder()
            local w = GuildCensusWindow
            assertEqual(w.shown, true)
            assertEqual(w.activeTab, "finder")
            assertEqual(pane.shown, true)
            assertEqual(w.censusPane.shown, false)
            assertEqual(w.logsPane.shown, false)
            assertEqual(w.finderTab.enabled, false)
            assertEqual(w.censusTab.enabled, true)
        end)

        it("switching tabs still shows exactly one pane", function()
            loadAddon(finderGuild())
            SlashCmdList["GUILDCENSUS"]("")
            local w = GuildCensusWindow
            for _, name in ipairs({ "finder", "logs", "census", "finder" }) do
                click(w.tabs[name])
                for other, pane in pairs(w.panes) do
                    assertEqual(pane.shown, other == name)
                end
            end
        end)

        it("lists everyone by default, highest level first", function()
            loadAddon(finderGuild())
            local pane = openFinder()
            assertEqual(pane.summary.text, "5 players found")
            assertEqual(rowNames(pane), { "Elder", "Bulwark", "Mender", "Zap", "Tanky" })
        end)

        for _, mode in ipairs({ "modern", "legacy", "none" }) do
            local expectedKind = mode == "none" and "cycle" or mode

            describe("role selector (" .. mode .. " client)", function()
                it("uses the " .. expectedKind .. " control", function()
                    loadAddon(finderGuild({ dropdown = mode }))
                    assertEqual(openFinder().roleControl, expectedKind)
                end)

                it("filters by role chosen from the selector", function()
                    loadAddon(finderGuild({ dropdown = mode }))
                    local pane = openFinder()
                    chooseRole(pane, "Tank")
                    assertEqual(pane.summary.text, "3 players found")
                    assertEqual(rowNames(pane), { "Elder", "Bulwark", "Tanky" })
                    chooseRole(pane, "Healer")
                    assertEqual(rowNames(pane), { "Bulwark", "Mender" })
                    chooseRole(pane, "DPS")
                    assertEqual(rowNames(pane), { "Zap" })
                    chooseRole(pane, "Any")
                    assertEqual(pane.summary.text, "5 players found")
                end)
            end)
        end

        it("the dropdown offers exactly the fixed choices, in order, with no free text", function()
            for _, mode in ipairs({ "modern", "legacy" }) do
                loadAddon(finderGuild({ dropdown = mode }))
                local texts = {}
                for _, choice in ipairs(roleChoices(openFinder())) do texts[#texts + 1] = choice.text end
                assertEqual(texts, { "Any", "Tank", "Healer", "DPS" })
            end
        end)

        it("the dropdown marks the current role as selected", function()
            for _, mode in ipairs({ "modern", "legacy" }) do
                loadAddon(finderGuild({ dropdown = mode }))
                local pane = openFinder()
                local function selectedText()
                    for _, choice in ipairs(roleChoices(pane)) do
                        if choice.selected() then return choice.text end
                    end
                end
                assertEqual(selectedText(), "Any")
                chooseRole(pane, "Healer")
                assertEqual(selectedText(), "Healer")
            end
        end)

        it("the legacy dropdown's displayed text follows the selection", function()
            loadAddon(finderGuild({ dropdown = "legacy" }))
            local pane = openFinder()
            assertEqual(pane.roleWidget.dropdownText, "Any")
            chooseRole(pane, "Tank")
            assertEqual(pane.roleWidget.dropdownText, "Tank")
        end)

        it("the fallback cycle button walks Any, Tank, Healer, DPS", function()
            loadAddon(finderGuild({ dropdown = "none" }))
            local pane = openFinder()
            assertEqual(pane.roleWidget.text, "Any")
            local seen = {}
            for _ = 1, 4 do
                click(pane.roleWidget)
                seen[#seen + 1] = pane.roleWidget.text
            end
            assertEqual(seen, { "Tank", "Healer", "DPS", "Any" })
        end)

        it("shows level, class, roles and professions per row", function()
            loadAddon(finderGuild())
            local pane = openFinder()
            chooseRole(pane, "Tank")
            local last = visibleRows(pane)[3]
            assertEqual(last.level.text, "15")
            assertEqual(last.class.text, "Warrior")
            assertEqual(last.roles.text, "Tank")
            assertEqual(last.professions.text, "Mining")
            assertEqual(visibleRows(pane)[2].roles.text, "Tank, Healer")
        end)

        it("colours names by class", function()
            loadAddon(finderGuild())
            local pane = openFinder()
            assert(visibleRows(pane)[1].name.text:match("^|cff%x%x%x%x%x%x.+|r$"), visibleRows(pane)[1].name.text)
        end)

        it("filters by level range as boxes are typed", function()
            loadAddon(finderGuild())
            local pane = openFinder()
            chooseRole(pane, "Tank")
            type_(pane.minBox, "16")
            assertEqual(rowNames(pane), { "Elder", "Bulwark" })
            type_(pane.maxBox, "25")
            assertEqual(rowNames(pane), { "Bulwark" })
            assertEqual(pane.summary.text, "1 player found")
            type_(pane.minBox, "")
            type_(pane.maxBox, "")
            assertEqual(pane.summary.text, "3 players found")
        end)

        it("shows a message and hides leftover rows when nobody matches", function()
            loadAddon(finderGuild())
            local pane = openFinder()
            assertEqual(#visibleRows(pane), 5)
            chooseRole(pane, "Tank")
            assertEqual(#visibleRows(pane), 3) -- rows are pooled; extras are hidden, not destroyed
            assertEqual(#pane.rows, 5)
            chooseRole(pane, "Healer")
            type_(pane.minBox, "50")
            assertEqual(pane.summary.text, "No players found.")
            assertEqual(#visibleRows(pane), 0)
        end)

        it("finds pure-DPS classes for DPS with no note", function()
            loadAddon(finderGuild())
            local pane = openFinder()
            chooseRole(pane, "DPS")
            assertEqual(rowNames(pane), { "Zap" })
        end)

        it("re-searches when settings change", function()
            loadAddon(finderGuild())
            local pane = openFinder()
            chooseRole(pane, "Tank")
            assertEqual(pane.summary.text, "3 players found")
            type_(GuildCensusOptionsPanel.controls.roles.tank, "wall")
            assertEqual(pane.summary.text, "No players found.")
        end)

        it("honours the alts filter from settings", function()
            loadAddon({ guild = {
                { name = "Main", level = 30, className = "Warrior", classFile = "WARRIOR", note = "tank" },
                { name = "Spare", level = 30, className = "Warrior", classFile = "WARRIOR", note = "tank alt" },
            } })
            local pane = openFinder()
            chooseRole(pane, "Tank")
            assertEqual(pane.summary.text, "2 players found")
            local c = GuildCensusOptionsPanel.controls
            c.includeAlts:SetChecked(false)
            click(c.includeAlts)
            assertEqual(rowNames(pane), { "Main" })
        end)

        it("says no players when you are not in a guild", function()
            loadAddon()
            assertEqual(openFinder().summary.text, "No players found.")
        end)

        it("searches demo data and agrees with the engine", function()
            local ns = loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local pane = openFinder()
            assertEqual(pane.summary.text, "80 players found")
            chooseRole(pane, "DPS")
            local expected = #ns.Census.Find(ns.Demo.Generate(80), { role = "dps" }, ns.settings)
            assertEqual(#visibleRows(pane), expected)
        end)

        it("caps the list for very large guilds", function()
            local ns = loadAddon()
            local pane = openFinder()
            pane:Update(ns.Demo.Generate(350), ns.settings)
            assertEqual(pane.summary.text, "Showing the first 300 of 350 players")
            assertEqual(#visibleRows(pane), 300)
        end)
    end)

    describe("Options panel (headless)", function()
        it("registers a canvas category with the Settings API", function()
            loadAddon()
            assert(Settings.registered, "category not registered")
            assertEqual(Settings.registered.panel, GuildCensusOptionsPanel)
        end)

        it("/gcensus config opens the registered category", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("config")
            assertEqual(Settings.openedId, 42)
        end)

        it("pre-populates every box with the default keyword lists", function()
            local ns = loadAddon()
            local c = GuildCensusOptionsPanel.controls
            assertEqual(c.includeAlts.checked, true)
            assertEqual(c.onlyMains.checked, false)
            assertEqual(c.identity.main.text, "main")
            assertEqual(c.identity.alt.text, "alt")
            assertEqual(c.roles.tank.text, "tank,bear,prot")
            assertEqual(c.roles.healer.text, "heal,resto,holy,disc")
            assertEqual(c.roles.dps.text, ns.Config.ROLES[3].default)
            for _, def in ipairs(ns.Config.PROFESSIONS) do
                assertEqual(c.professions[def.key].text, def.default)
            end
        end)

        it("typing in a box updates and persists the setting", function()
            local ns = loadAddon()
            type_(GuildCensusOptionsPanel.controls.roles.tank, "wall")
            assertEqual(ns.settings.roles.tank, "wall")
            assertEqual(GuildCensusDB.settings.roles.tank, "wall")
        end)

        it("ignores programmatic text changes (only user input is saved)", function()
            local ns = loadAddon()
            local box = GuildCensusOptionsPanel.controls.roles.tank
            box:SetText("ignored")
            box.scripts.OnTextChanged(box, false)
            assertEqual(ns.settings.roles.tank, "tank,bear,prot")
        end)

        it("checkboxes update settings", function()
            local ns = loadAddon()
            local c = GuildCensusOptionsPanel.controls
            c.includeAlts:SetChecked(false)
            click(c.includeAlts)
            c.onlyMains:SetChecked(true)
            click(c.onlyMains)
            assertEqual(ns.settings.includeAlts, false)
            assertEqual(ns.settings.onlyMains, true)
        end)

        it("changing a setting refreshes an open window", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            assertEqual(GuildCensusWindow.summary.text, "80 guild members (demo data)")
            local c = GuildCensusOptionsPanel.controls
            c.includeAlts:SetChecked(false)
            click(c.includeAlts)
            local count = tonumber(GuildCensusWindow.summary.text:match("^(%d+) guild members"))
            assert(count and count < 80, "expected fewer than 80 members, got " .. tostring(count))
        end)

        it("only-mains narrows the census to declared mains", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local c = GuildCensusOptionsPanel.controls
            c.onlyMains:SetChecked(true)
            click(c.onlyMains)
            local count = tonumber(GuildCensusWindow.summary.text:match("^(%d+) guild members"))
            assert(count and count > 0 and count < 80, "unexpected count " .. tostring(count))
        end)

        it("reset restores defaults and repopulates the boxes", function()
            local ns = loadAddon()
            local c = GuildCensusOptionsPanel.controls
            type_(c.roles.tank, "wall")
            type_(c.identity.alt, "twink")
            c.includeAlts:SetChecked(false)
            click(c.includeAlts)
            click(c.reset)
            assertEqual(c.roles.tank.text, "tank,bear,prot")
            assertEqual(c.identity.alt.text, "alt")
            assertEqual(c.includeAlts.checked, true)
            assertEqual(ns.settings.roles.tank, "tank,bear,prot")
            assertEqual(GuildCensusDB.settings, ns.Config.Defaults())
        end)

        it("keeps saved settings across a reload", function()
            loadAddon()
            type_(GuildCensusOptionsPanel.controls.roles.tank, "wall")
            local saved = GuildCensusDB
            InstallWowStub()
            local ns = {}
            for _, file in ipairs(ADDON_FILES) do loadAddonFile(ns, file) end
            GuildCensusDB = saved
            GuildCensusEventFrame.scripts.OnEvent(GuildCensusEventFrame, "ADDON_LOADED", "GuildCensus")
            assertEqual(ns.settings.roles.tank, "wall")
            assertEqual(GuildCensusOptionsPanel.controls.roles.tank.text, "wall")
        end)
    end)
end
