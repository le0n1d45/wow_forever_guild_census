-- Headless UI tests: run the real addon files against the strict WoW stub.
return function()
    local DEMO_COUNT = 500 -- checked against Demo.DEFAULT_COUNT below
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

        it("returns the requested number of members, defaulting to a guild-sized roster", function()
            assertEqual(#ns.Demo.Generate(80), 80)
            assertEqual(ns.Demo.DEFAULT_COUNT, DEMO_COUNT)
            assertEqual(#ns.Demo.Generate(), DEMO_COUNT)
        end)

        it("is deterministic for a given seed", function()
            assertEqual(ns.Demo.Generate(20, 7), ns.Demo.Generate(20, 7))
        end)

        it("gives every member a unique, real-looking name", function()
            local seen = {}
            for _, m in ipairs(ns.Demo.Generate(700)) do
                assert(m.name:match("^%a"), "bad name: " .. m.name)
                assert(not m.name:find("Player"), "placeholder name: " .. m.name)
                assert(not seen[m.name], "duplicate name: " .. m.name)
                seen[m.name] = true
            end
            assertEqual(ns.Demo.Generate(1)[1].name, "Thalindra")
        end)

        it("gives members a believable mix of online and offline", function()
            local online = 0
            local members = ns.Demo.Generate()
            for _, m in ipairs(members) do
                assert(type(m.online) == "boolean", "online must be a boolean for " .. m.name)
                if m.online then online = online + 1 end
            end
            assert(online > #members * 0.3 and online < #members * 0.7,
                "expected a mix of online/offline, got " .. online .. " online")
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

        it("also reads the officer note, and copes when it is hidden", function()
            local ns = loadAddon({ guild = {
                { name = "A", level = 60, className = "Priest", classFile = "PRIEST", note = "main", officerNote = "healer" },
                { name = "B", level = 30, className = "Mage", classFile = "MAGE", note = "", officerNote = "LW 260" },
                { name = "C", level = 30, className = "Mage", classFile = "MAGE", note = "dps", officerNote = "   " },
                { name = "D", level = 30, className = "Mage", classFile = "MAGE", note = "dps" },
            } })
            local notes = {}
            for i, m in ipairs(ns.Roster.Read()) do notes[i] = m.note end
            assertEqual(notes, { "main | healer", "LW 260", "dps", "dps" })
        end)

        it("CombineNotes ignores anything that is not text", function()
            local ns = loadAddon()
            assertEqual(ns.Roster.CombineNotes(nil, nil), "")
            assertEqual(ns.Roster.CombineNotes("tank", false), "tank")
            assertEqual(ns.Roster.CombineNotes(12, "tank"), "tank")
        end)

        it("an officer-note skill number is not glued onto a public-note profession", function()
            local ns = loadAddon()
            local note = ns.Roster.CombineNotes("LW", "260")
            assertEqual(ns.Parser.SkillAfter(note, ns.Parser.ParseList("lw")), nil)
        end)

        it("demo mode fills every chart with legends", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local w = GuildCensusWindow
            assertEqual(w.summary.text, DEMO_COUNT .. " guild members (demo data)")
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
            local census = ns.Census.Build(ns.Demo.Generate(), ns.settings)
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

    -- Shared helpers for the two finder tabs. -------------------------------------
    local function finderGuild(extra)
        local options = { guild = {
            { name = "Tanky", level = 15, className = "Warrior", classFile = "WARRIOR", note = "Tank, mining", online = true },
            { name = "Bulwark", level = 20, className = "Paladin", classFile = "PALADIN", note = "prot / heal, mining", online = false },
            { name = "Mender", level = 18, className = "Priest", classFile = "PRIEST", note = "healer, tailoring", online = true },
            { name = "Zap", level = 18, className = "Mage", classFile = "MAGE", note = "", online = false },
            { name = "Elder", level = 60, className = "Warrior", classFile = "WARRIOR", note = "main tank", online = true },
        } }
        for k, v in pairs(extra or {}) do options[k] = v end
        return options
    end

    local function openRoles()
        SlashCmdList["GUILDCENSUS"]("roles")
        return GuildCensusWindow.rolesPane
    end

    local function openProfessions()
        SlashCmdList["GUILDCENSUS"]("professions")
        return GuildCensusWindow.professionsPane
    end

    -- Reads a selector's choices the way the client would, for any of the three
    -- selector kinds. Returns a list of { text, selected(), choose() }.
    -- `root` optionally replaces the fake menu root (modern selectors only).
    local function choicesOf(selector, root)
        local choices = {}
        if selector.kind == "modern" then
            root = root or {}
            root.CreateRadio = function(_, text, isSelected, setSelected)
                choices[#choices + 1] = { text = text, selected = isSelected, choose = setSelected }
            end
            selector.widget.menuGenerator(selector.widget, root)
        elseif selector.kind == "legacy" then
            LegacyMenuItems = {}
            selector.widget.dropdownInit()
            for _, info in ipairs(LegacyMenuItems) do
                choices[#choices + 1] = {
                    text = info.text, selected = function() return info.checked end, choose = info.func,
                }
            end
        end
        return choices
    end

    local function textsOf(selector)
        local texts = {}
        for _, choice in ipairs(choicesOf(selector)) do texts[#texts + 1] = choice.text end
        return texts
    end

    local function selectedText(selector)
        for _, choice in ipairs(choicesOf(selector)) do
            if choice.selected() then return choice.text end
        end
    end

    -- Picks an option by label (or by cycling, in the fallback).
    local function choose(selector, label)
        if selector.kind == "cycle" then
            for _ = 1, 40 do
                if selector.widget.text == label then return end
                click(selector.widget)
            end
            error("option not reachable: " .. label)
        end
        for _, choice in ipairs(choicesOf(selector)) do
            if choice.text == label then return choice.choose() end
        end
        error("no such choice: " .. label)
    end

    -- What the selector currently displays, whichever kind it is.
    local function displayedText(selector)
        if selector.kind == "legacy" then return selector.widget.dropdownText end
        if selector.kind == "cycle" then return selector.widget.text end
        return selectedText(selector)
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

    local function checkOnline(pane, checked)
        pane.onlineBox:SetChecked(checked)
        click(pane.onlineBox)
    end

    local MODES = { "modern", "legacy", "none" }
    local function kindFor(mode) return mode == "none" and "cycle" or mode end

    describe("Role Finder tab (headless)", function()
        local function chooseRole(pane, label) choose(pane.selectors.role, label) end

        it("/gcensus roles and /gcensus finder both open it", function()
            for _, command in ipairs({ "roles", "finder" }) do
                loadAddon(finderGuild())
                SlashCmdList["GUILDCENSUS"](command)
                local w = GuildCensusWindow
                assertEqual(w.shown, true)
                assertEqual(w.activeTab, "roles")
                assertEqual(w.rolesPane.shown, true)
                assertEqual(w.rolesTab.enabled, false)
                assertEqual(w.censusTab.enabled, true)
            end
        end)

        it("switching between the four tabs shows exactly one pane", function()
            loadAddon(finderGuild())
            SlashCmdList["GUILDCENSUS"]("")
            local w = GuildCensusWindow
            for _, name in ipairs({ "roles", "professions", "logs", "census", "professions", "roles" }) do
                click(w.tabs[name])
                for other, pane in pairs(w.panes) do
                    assertEqual(pane.shown, other == name)
                end
            end
        end)

        it("lists everyone by default, highest level first", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            assertEqual(pane.summary.text, "5 players found")
            assertEqual(rowNames(pane), { "Elder", "Bulwark", "Mender", "Zap", "Tanky" })
        end)

        it("has role and dungeon selectors but no profession controls", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            assert(pane.selectors.role and pane.selectors.dungeon)
            assertEqual(pane.selectors.profession, nil)
            local criteria = pane:Criteria()
            assertEqual(criteria.profession, nil)
            assertEqual(criteria.hasProfession, nil)
        end)

        for _, mode in ipairs(MODES) do
            describe("selectors (" .. mode .. " client)", function()
                it("both use the " .. kindFor(mode) .. " control", function()
                    loadAddon(finderGuild({ dropdown = mode }))
                    local pane = openRoles()
                    for _, name in ipairs({ "role", "dungeon" }) do
                        assertEqual(pane.selectors[name].kind, kindFor(mode))
                    end
                end)

                it("filters by role chosen from the selector", function()
                    loadAddon(finderGuild({ dropdown = mode }))
                    local pane = openRoles()
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

                it("a dungeon fills in the level range and filters by it", function()
                    loadAddon(finderGuild({ dropdown = mode }))
                    local pane = openRoles()
                    choose(pane.selectors.dungeon, "Ruins of Lordaeron (15-20)")
                    assertEqual(pane.minBox.text, "15")
                    assertEqual(pane.maxBox.text, "20")
                    assertEqual(rowNames(pane), { "Bulwark", "Mender", "Zap", "Tanky" })
                end)

                it("Clear puts everything back to its defaults", function()
                    loadAddon(finderGuild({ dropdown = mode }))
                    local pane = openRoles()
                    chooseRole(pane, "Tank")
                    choose(pane.selectors.dungeon, "Ruins of Lordaeron (15-20)")
                    checkOnline(pane, true)
                    assertEqual(rowNames(pane), { "Tanky" })

                    click(pane.clearButton)

                    assertEqual(pane.roleIndex, 1)
                    assertEqual(pane.dungeonIndex, 1)
                    assertEqual(pane.minBox.text, "")
                    assertEqual(pane.maxBox.text, "")
                    assertEqual(pane.onlineOnly, false)
                    assertEqual(pane.onlineBox:GetChecked(), false)
                    assertEqual(displayedText(pane.selectors.role), "Any")
                    assertEqual(displayedText(pane.selectors.dungeon), "Custom")
                    assertEqual(pane.summary.text, "5 players found")
                    assertEqual(rowNames(pane), { "Elder", "Bulwark", "Mender", "Zap", "Tanky" })
                end)
            end)
        end

        it("Clear refreshes the modern dropdowns so they show the defaults again", function()
            loadAddon(finderGuild({ dropdown = "modern" }))
            local pane = openRoles()
            local role, dungeon = pane.selectors.role.widget, pane.selectors.dungeon.widget
            local before = { rawget(role, "menuGenerations") or 0, rawget(dungeon, "menuGenerations") or 0 }
            click(pane.clearButton)
            assertEqual(rawget(role, "menuGenerations"), before[1] + 1)
            assertEqual(rawget(dungeon, "menuGenerations"), before[2] + 1)
        end)

        it("Clear also removes hand-typed levels and is harmless when already default", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            click(pane.clearButton)
            assertEqual(pane.summary.text, "5 players found")
            type_(pane.minBox, "30")
            assertEqual(rowNames(pane), { "Elder" })
            click(pane.clearButton)
            assertEqual(pane.minBox.text, "")
            assertEqual(pane.summary.text, "5 players found")
        end)

        it("the role dropdown offers exactly the fixed choices, in order, with no free text", function()
            for _, mode in ipairs({ "modern", "legacy" }) do
                loadAddon(finderGuild({ dropdown = mode }))
                assertEqual(textsOf(openRoles().selectors.role), { "Any", "Tank", "Healer", "DPS" })
            end
        end)

        it("the dungeon dropdown offers Custom plus every dungeon with its level range", function()
            local ns = loadAddon(finderGuild())
            local texts = textsOf(openRoles().selectors.dungeon)
            assertEqual(#texts, #ns.Dungeons.LIST + 1)
            assertEqual(texts[1], "Custom")
            assertEqual(texts[2], "Ragefire Chasm (13-18)") -- sorted by minimum level, then name
            local hasDeadmines = false
            for _, text in ipairs(texts) do
                if text == "The Deadmines (18-23)" then hasDeadmines = true end
            end
            assert(hasDeadmines, "Deadmines should be listed with Forever's range")
        end)

        it("long menus ask for scrolling and short ones do not", function()
            local ns = loadAddon(finderGuild())
            local pane = openRoles()
            local scroll = {}
            local function root(name)
                return { SetScrollMode = function(_, extent) scroll[name] = extent end }
            end
            choicesOf(pane.selectors.role, root("role"))
            choicesOf(pane.selectors.dungeon, root("dungeon"))
            assertEqual(scroll.role, nil)
            assert(scroll.dungeon, "dungeon menu should scroll")
            assert(#ns.Dungeons.LIST > 12)
        end)

        it("the dropdowns mark the current choice as selected", function()
            for _, mode in ipairs({ "modern", "legacy" }) do
                loadAddon(finderGuild({ dropdown = mode }))
                local pane = openRoles()
                assertEqual(selectedText(pane.selectors.role), "Any")
                chooseRole(pane, "Healer")
                assertEqual(selectedText(pane.selectors.role), "Healer")
            end
        end)

        it("the legacy dropdown's displayed text follows the selection", function()
            loadAddon(finderGuild({ dropdown = "legacy" }))
            local pane = openRoles()
            assertEqual(pane.selectors.role.widget.dropdownText, "Any")
            chooseRole(pane, "Tank")
            assertEqual(pane.selectors.role.widget.dropdownText, "Tank")
            assertEqual(pane.selectors.dungeon.widget.dropdownText, "Custom")
        end)

        it("the fallback cycle button walks Any, Tank, Healer, DPS", function()
            loadAddon(finderGuild({ dropdown = "none" }))
            local widget = openRoles().selectors.role.widget
            assertEqual(widget.text, "Any")
            local seen = {}
            for _ = 1, 4 do
                click(widget)
                seen[#seen + 1] = widget.text
            end
            assertEqual(seen, { "Tank", "Healer", "DPS", "Any" })
        end)

        it("online only limits every search to online members", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            checkOnline(pane, true)
            assertEqual(rowNames(pane), { "Elder", "Mender", "Tanky" })
            chooseRole(pane, "Tank")
            assertEqual(rowNames(pane), { "Elder", "Tanky" })
            checkOnline(pane, false)
            assertEqual(rowNames(pane), { "Elder", "Bulwark", "Tanky" })
        end)

        it("online only combines with the level range", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            checkOnline(pane, true)
            type_(pane.minBox, "16")
            assertEqual(rowNames(pane), { "Elder", "Mender" })
        end)

        it("online only is off by default", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            assertEqual(pane.onlineBox:GetChecked(), false)
            assertEqual(pane.onlineOnly, false)
        end)

        it("editing a level by hand switches the dungeon back to Custom", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            choose(pane.selectors.dungeon, "Ruins of Lordaeron (15-20)")
            assertEqual(selectedText(pane.selectors.dungeon), "Ruins of Lordaeron (15-20)")
            type_(pane.minBox, "17")
            assertEqual(pane.dungeonIndex, 1)
            assertEqual(selectedText(pane.selectors.dungeon), "Custom")
            assertEqual(rowNames(pane), { "Bulwark", "Mender", "Zap" }) -- 17-20, boxes keep what was typed
        end)

        it("setting level text from code does not reset the dungeon", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            choose(pane.selectors.dungeon, "Ruins of Lordaeron (15-20)")
            pane.minBox.scripts.OnTextChanged(pane.minBox, false)
            assertEqual(selectedText(pane.selectors.dungeon), "Ruins of Lordaeron (15-20)")
        end)

        it("choosing Custom after a dungeon keeps the current range", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            choose(pane.selectors.dungeon, "Ruins of Lordaeron (15-20)")
            choose(pane.selectors.dungeon, "Custom")
            assertEqual(pane.minBox.text, "15")
            assertEqual(pane.maxBox.text, "20")
        end)

        it("a dungeon combines with role and online only", function()
            loadAddon(finderGuild())
            local pane = openRoles()
            choose(pane.selectors.dungeon, "Ruins of Lordaeron (15-20)")
            chooseRole(pane, "Tank")
            assertEqual(rowNames(pane), { "Bulwark", "Tanky" })
            checkOnline(pane, true)
            assertEqual(rowNames(pane), { "Tanky" })
        end)

        it("shows level, class, roles and professions per row", function()
            loadAddon(finderGuild())
            local pane = openRoles()
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
            local pane = openRoles()
            assert(visibleRows(pane)[1].name.text:match("^|cff%x%x%x%x%x%x.+|r$"), visibleRows(pane)[1].name.text)
        end)

        it("filters by level range as boxes are typed", function()
            loadAddon(finderGuild())
            local pane = openRoles()
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
            local pane = openRoles()
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
            local pane = openRoles()
            chooseRole(pane, "DPS")
            assertEqual(rowNames(pane), { "Zap" })
        end)

        it("re-searches when settings change", function()
            loadAddon(finderGuild())
            local pane = openRoles()
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
            local pane = openRoles()
            chooseRole(pane, "Tank")
            assertEqual(pane.summary.text, "2 players found")
            local c = GuildCensusOptionsPanel.controls
            c.includeAlts:SetChecked(false)
            click(c.includeAlts)
            assertEqual(rowNames(pane), { "Main" })
        end)

        it("says no players when you are not in a guild", function()
            loadAddon()
            assertEqual(openRoles().summary.text, "No players found.")
        end)

        it("searches demo data, shows the row cap, and agrees with the engine", function()
            local ns = loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local pane = openRoles()
            -- An unfiltered search returns the whole 500-member roster, which is over the cap.
            assertEqual(pane.summary.text, "Showing the first 300 of " .. DEMO_COUNT .. " players")
            local members = ns.Demo.Generate()

            chooseRole(pane, "DPS")
            local dps = #ns.Census.Find(members, { role = "dps" }, ns.settings)
            assertEqual(#visibleRows(pane), math.min(dps, 300))

            checkOnline(pane, true)
            local online = #ns.Census.Find(members, { role = "dps", onlineOnly = true }, ns.settings)
            assertEqual(#visibleRows(pane), math.min(online, 300))
            assert(online > 0 and online < dps, "online filter should narrow the demo results")
        end)

        it("every demo role filter combination is testable: dungeon + role + online", function()
            local ns = loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local pane = openRoles()
            choose(pane.selectors.dungeon, "The Deadmines (18-23)")
            chooseRole(pane, "Tank")
            checkOnline(pane, true)
            local expected = #ns.Census.Find(ns.Demo.Generate(),
                { minLevel = 18, maxLevel = 23, role = "tank", onlineOnly = true }, ns.settings)
            assert(expected > 0, "this combination should have results in the demo roster")
            assertEqual(#visibleRows(pane), expected)
            assertEqual(pane.summary.text, expected .. (expected == 1 and " player found" or " players found"))
        end)

        it("caps the list for very large guilds", function()
            local ns = loadAddon()
            local pane = openRoles()
            pane:Update(ns.Demo.Generate(350), ns.settings)
            assertEqual(pane.summary.text, "Showing the first 300 of 350 players")
            assertEqual(#visibleRows(pane), 300)
        end)
    end)

    describe("Profession Finder tab (headless)", function()
        local function chooseProfession(pane, label) choose(pane.selectors.profession, label) end

        it("/gcensus professions opens it, as the only visible pane", function()
            loadAddon(finderGuild())
            local pane = openProfessions()
            local w = GuildCensusWindow
            assertEqual(w.shown, true)
            assertEqual(w.activeTab, "professions")
            assertEqual(pane.shown, true)
            assertEqual(w.rolesPane.shown, false)
            assertEqual(w.censusPane.shown, false)
            assertEqual(w.logsPane.shown, false)
            assertEqual(w.professionsTab.enabled, false)
        end)

        it("only asks for a profession: no role, level or dungeon controls", function()
            loadAddon(finderGuild())
            local pane = openProfessions()
            assertEqual(pane.selectors.role, nil)
            assertEqual(pane.selectors.dungeon, nil)
            assert(pane.selectors.profession, "needs a profession selector")
            assertEqual(rawget(pane, "minBox"), nil)
            assertEqual(rawget(pane, "maxBox"), nil)
            assertEqual(rawget(pane, "roleIndex"), nil)
            local criteria = pane:Criteria()
            assertEqual(criteria.role, nil)
            assertEqual(criteria.minLevel, nil)
            assertEqual(criteria.maxLevel, nil)
        end)

        it("by default lists everyone with at least one profession", function()
            loadAddon(finderGuild())
            local pane = openProfessions()
            assertEqual(pane.summary.text, "3 players found")
            assertEqual(rowNames(pane), { "Bulwark", "Mender", "Tanky" })
        end)

        it("offers Any profession plus every configured profession", function()
            for _, mode in ipairs({ "modern", "legacy" }) do
                local ns = loadAddon(finderGuild({ dropdown = mode }))
                local expected = { "Any profession" }
                for _, def in ipairs(ns.Config.PROFESSIONS) do expected[#expected + 1] = def.label end
                assertEqual(textsOf(openProfessions().selectors.profession), expected)
            end
        end)

        for _, mode in ipairs(MODES) do
            describe("selector (" .. mode .. " client)", function()
                it("uses the " .. kindFor(mode) .. " control", function()
                    loadAddon(finderGuild({ dropdown = mode }))
                    assertEqual(openProfessions().selectors.profession.kind, kindFor(mode))
                end)

                it("filters by the chosen profession", function()
                    loadAddon(finderGuild({ dropdown = mode }))
                    local pane = openProfessions()
                    chooseProfession(pane, "Mining")
                    assertEqual(rowNames(pane), { "Bulwark", "Tanky" })
                    chooseProfession(pane, "Tailor")
                    assertEqual(rowNames(pane), { "Mender" })
                    chooseProfession(pane, "Alchemy")
                    assertEqual(pane.summary.text, "No players found.")
                    chooseProfession(pane, "Any profession")
                    assertEqual(pane.summary.text, "3 players found")
                end)

                it("Clear puts everything back to its defaults", function()
                    loadAddon(finderGuild({ dropdown = mode }))
                    local pane = openProfessions()
                    chooseProfession(pane, "Mining")
                    checkOnline(pane, true)
                    assertEqual(rowNames(pane), { "Tanky" })

                    click(pane.clearButton)

                    assertEqual(pane.professionIndex, 1)
                    assertEqual(pane.onlineOnly, false)
                    assertEqual(pane.onlineBox:GetChecked(), false)
                    assertEqual(displayedText(pane.selectors.profession), "Any profession")
                    assertEqual(rowNames(pane), { "Bulwark", "Mender", "Tanky" })
                end)
            end)
        end

        it("online only limits the search to online members", function()
            loadAddon(finderGuild())
            local pane = openProfessions()
            checkOnline(pane, true)
            assertEqual(rowNames(pane), { "Mender", "Tanky" })
            chooseProfession(pane, "Mining")
            assertEqual(rowNames(pane), { "Tanky" })
            checkOnline(pane, false)
            assertEqual(rowNames(pane), { "Bulwark", "Tanky" })
        end)

        it("online only is off by default", function()
            loadAddon(finderGuild())
            local pane = openProfessions()
            assertEqual(pane.onlineBox:GetChecked(), false)
            assertEqual(pane.onlineOnly, false)
        end)

        it("shows each player's level, class, roles and professions", function()
            loadAddon(finderGuild())
            local pane = openProfessions()
            chooseProfession(pane, "Tailor")
            local row = visibleRows(pane)[1]
            assertEqual(row.level.text, "18")
            assertEqual(row.class.text, "Priest")
            assertEqual(row.roles.text, "Healer")
            assertEqual(row.professions.text, "Tailor")
        end)

        it("re-searches when settings change", function()
            loadAddon(finderGuild())
            local pane = openProfessions()
            chooseProfession(pane, "Mining")
            assertEqual(pane.summary.text, "2 players found")
            type_(GuildCensusOptionsPanel.controls.professions.mining, "pickaxe")
            assertEqual(pane.summary.text, "No players found.")
        end)

        it("honours the alts filter from settings", function()
            loadAddon({ guild = {
                { name = "Real", level = 30, className = "Warrior", classFile = "WARRIOR", note = "mining" },
                { name = "Spare", level = 30, className = "Warrior", classFile = "WARRIOR", note = "mining alt" },
            } })
            local pane = openProfessions()
            chooseProfession(pane, "Mining")
            assertEqual(pane.summary.text, "2 players found")
            local c = GuildCensusOptionsPanel.controls
            c.includeAlts:SetChecked(false)
            click(c.includeAlts)
            assertEqual(rowNames(pane), { "Real" })
        end)

        it("says no players when you are not in a guild", function()
            loadAddon()
            assertEqual(openProfessions().summary.text, "No players found.")
        end)

        -- Notes that write profession skill levels, the way players do.
        local function skilledGuild(extra)
            return { guild = {
                { name = "Novice", level = 20, className = "Warrior", classFile = "WARRIOR", note = "LW 40", online = true },
                { name = "Adept", level = 40, className = "Warrior", classFile = "WARRIOR", note = "LW 150, mining 120", online = false },
                { name = "Master", level = 60, className = "Priest", classFile = "PRIEST", note = "healer, LW 300, BS: 275", online = true },
                { name = "Quiet", level = 55, className = "Mage", classFile = "MAGE", note = "LW, mining", online = true },
                { name = "Miner", level = 50, className = "Rogue", classFile = "ROGUE", note = "mining (225)", online = true },
            }, dropdown = extra and extra.dropdown }
        end

        it("has a skill level range (not a player level range)", function()
            loadAddon(skilledGuild())
            local pane = openProfessions()
            assert(pane.minSkillBox and pane.maxSkillBox, "needs skill boxes")
            assertEqual(pane:Criteria().minSkill, nil)
            type_(pane.minSkillBox, "100")
            type_(pane.maxSkillBox, "280")
            assertEqual(pane:Criteria().minSkill, 100)
            assertEqual(pane:Criteria().maxSkill, 280)
        end)

        it("shows each profession with the skill written in the note", function()
            loadAddon(skilledGuild())
            local pane = openProfessions()
            local byName = {}
            for _, row in ipairs(visibleRows(pane)) do
                byName[row.name.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")] = row.professions.text
            end
            assertEqual(byName.Master, "Leatherworking (300), Blacksmith (275)")
            assertEqual(byName.Adept, "Leatherworking (150), Mining (120)")
            assertEqual(byName.Miner, "Mining (225)")
            assertEqual(byName.Quiet, "Leatherworking, Mining") -- no skill written
        end)

        it("the Role Finder shows skills too", function()
            loadAddon(skilledGuild())
            local pane = openRoles()
            local texts = {}
            for _, row in ipairs(visibleRows(pane)) do texts[#texts + 1] = row.professions.text end
            local joined = table.concat(texts, " | ")
            assert(joined:find("Leatherworking (300), Blacksmith (275)", 1, true), joined)
        end)

        it("filters the chosen profession by skill range as the boxes are typed", function()
            loadAddon(skilledGuild())
            local pane = openProfessions()
            chooseProfession(pane, "Leatherworking")
            assertEqual(pane.summary.text, "4 players found") -- Quiet writes no skill but is listed
            type_(pane.minSkillBox, "100")
            assertEqual(rowNames(pane), { "Master", "Adept" })
            type_(pane.maxSkillBox, "200")
            assertEqual(rowNames(pane), { "Adept" })
            assertEqual(pane.summary.text, "1 player found")
            type_(pane.minSkillBox, "")
            assertEqual(rowNames(pane), { "Adept", "Novice" })
            type_(pane.maxSkillBox, "")
            assertEqual(pane.summary.text, "4 players found")
        end)

        it("members with no written skill drop out as soon as a bound is typed", function()
            loadAddon(skilledGuild())
            local pane = openProfessions()
            chooseProfession(pane, "Leatherworking")
            type_(pane.minSkillBox, "1")
            assertEqual(rowNames(pane), { "Master", "Adept", "Novice" })
        end)

        it("with Any profession, any profession's skill can satisfy the range", function()
            loadAddon(skilledGuild())
            local pane = openProfessions()
            type_(pane.minSkillBox, "225")
            assertEqual(rowNames(pane), { "Master", "Miner" })
            type_(pane.maxSkillBox, "250")
            assertEqual(rowNames(pane), { "Miner" })
        end)

        it("the skill range combines with online only", function()
            loadAddon(skilledGuild())
            local pane = openProfessions()
            chooseProfession(pane, "Mining")
            type_(pane.minSkillBox, "100")
            assertEqual(rowNames(pane), { "Miner", "Adept" })
            checkOnline(pane, true)
            assertEqual(rowNames(pane), { "Miner" })
        end)

        for _, mode in ipairs(MODES) do
            it("Clear resets the skill range, profession and online only (" .. mode .. " client)", function()
                loadAddon(skilledGuild({ dropdown = mode }))
                local pane = openProfessions()
                chooseProfession(pane, "Leatherworking")
                type_(pane.minSkillBox, "100")
                type_(pane.maxSkillBox, "200")
                checkOnline(pane, true)
                assertEqual(rowNames(pane), {})

                click(pane.clearButton)

                assertEqual(pane.minSkillBox.text, "")
                assertEqual(pane.maxSkillBox.text, "")
                assertEqual(pane.professionIndex, 1)
                assertEqual(pane.onlineBox:GetChecked(), false)
                assertEqual(displayedText(pane.selectors.profession), "Any profession")
                assertEqual(pane.summary.text, "5 players found")
            end)
        end

        it("skill ranges work on the demo roster and agree with the engine", function()
            local ns = loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local pane = openProfessions()
            local members = ns.Demo.Generate()
            for _, def in ipairs(ns.Config.PROFESSIONS) do
                chooseProfession(pane, def.label)
                type_(pane.minSkillBox, "226")
                type_(pane.maxSkillBox, "300")
                local expected = #ns.Census.Find(members,
                    { profession = def.key, minSkill = 226, maxSkill = 300 }, ns.settings)
                assert(expected > 0, def.label .. " should have high-skill demo members")
                assertEqual(#visibleRows(pane), math.min(expected, 300))
                click(pane.clearButton)
                assertEqual(pane.minSkillBox.text, "")
            end
        end)

        it("every profession has results in the demo roster, and online only narrows them", function()
            local ns = loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local pane = openProfessions()
            local members = ns.Demo.Generate()
            for _, def in ipairs(ns.Config.PROFESSIONS) do
                chooseProfession(pane, def.label)
                local all = #ns.Census.Find(members, { profession = def.key }, ns.settings)
                assert(all > 0, def.label .. " should have demo results")
                assertEqual(#visibleRows(pane), math.min(all, 300))

                checkOnline(pane, true)
                local online = #ns.Census.Find(members, { profession = def.key, onlineOnly = true }, ns.settings)
                assert(online > 0 and online < all, def.label .. " online filter should narrow the results")
                assertEqual(#visibleRows(pane), math.min(online, 300))
                click(pane.clearButton)
            end
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
            assertEqual(c.identity.main.text, ns.Config.IDENTITY[1].default)
            assertEqual(c.identity.alt.text, ns.Config.IDENTITY[2].default)
            assertEqual(c.roles.tank.text, ns.Config.ROLES[1].default)
            assertEqual(c.roles.healer.text, ns.Config.ROLES[2].default)
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
            assertEqual(ns.settings.roles.tank, ns.Config.ROLES[1].default)
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
            assertEqual(GuildCensusWindow.summary.text, DEMO_COUNT .. " guild members (demo data)")
            local c = GuildCensusOptionsPanel.controls
            c.includeAlts:SetChecked(false)
            click(c.includeAlts)
            local count = tonumber(GuildCensusWindow.summary.text:match("^(%d+) guild members"))
            assert(count and count < DEMO_COUNT, "expected fewer than " .. DEMO_COUNT .. " members, got " .. tostring(count))
        end)

        it("only-mains narrows the census to declared mains", function()
            loadAddon()
            SlashCmdList["GUILDCENSUS"]("demo")
            local c = GuildCensusOptionsPanel.controls
            c.onlyMains:SetChecked(true)
            click(c.onlyMains)
            local count = tonumber(GuildCensusWindow.summary.text:match("^(%d+) guild members"))
            assert(count and count > 0 and count < DEMO_COUNT, "unexpected count " .. tostring(count))
        end)

        it("reset restores defaults and repopulates the boxes", function()
            local ns = loadAddon()
            local c = GuildCensusOptionsPanel.controls
            type_(c.roles.tank, "wall")
            type_(c.identity.alt, "twink")
            c.includeAlts:SetChecked(false)
            click(c.includeAlts)
            click(c.reset)
            assertEqual(c.roles.tank.text, ns.Config.ROLES[1].default)
            assertEqual(c.identity.alt.text, ns.Config.IDENTITY[2].default)
            assertEqual(c.includeAlts.checked, true)
            assertEqual(ns.settings.roles.tank, ns.Config.ROLES[1].default)
            assertEqual(GuildCensusDB.settings, ns.Config.Defaults())
        end)

        it("upgrades an untouched old Leatherworking default when a saved profile loads", function()
            InstallWowStub()
            local ns = {}
            for _, file in ipairs(ADDON_FILES) do loadAddonFile(ns, file) end
            GuildCensusDB = { settings = { professions = { leatherworking = "lw, leatherworker", mining = "pickaxe" } } }
            GuildCensusEventFrame.scripts.OnEvent(GuildCensusEventFrame, "ADDON_LOADED", "GuildCensus")
            local boxes = GuildCensusOptionsPanel.controls.professions
            assertEqual(boxes.leatherworking.text, "lw, leatherworking, leatherworker")
            assertEqual(boxes.mining.text, "pickaxe") -- an edited box is left alone
            assertEqual(GuildCensusDB.settings.professions.leatherworking, "lw, leatherworking, leatherworker")
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
