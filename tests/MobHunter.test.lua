-- MobHunter tests. Hunt and Probe are pure Lua; the wiring in MobHunter.lua is loaded against a
-- small permissive fake client (any widget method is a no-op), so these prove the logic and
-- that the file loads and handles a hunt without erroring, not that the real client agrees.
return function()
    local function load(files)
        local ns = {}
        for _, file in ipairs(files) do loadAddonFile(ns, file, "MobHunter") end
        return ns
    end
    local ns = load({ "Hunt.lua", "Quests.lua", "Drops.lua", "Probe.lua" })
    local Hunt, Probe, Quests, Drops = ns.Hunt, ns.Probe, ns.Quests, ns.Drops

    describe("MobHunter Hunt.Normalize / Matches", function()
        it("lowercases, trims and collapses whitespace", function()
            assertEqual(Hunt.Normalize("  Defias   PILLAGER "), "defias pillager")
            assertEqual(Hunt.Normalize(nil), "")
        end)

        it("matches case-insensitively and by part of the name", function()
            assert(Hunt.Matches("defias pillager", "Defias Pillager"))
            assert(Hunt.Matches("pillager", "Defias Pillager"))
            assert(not Hunt.Matches("pillager", "Defias Bandit"))
        end)

        it("treats the hunted text as plain text, not a pattern", function()
            assert(not Hunt.Matches("a.c", "abc"))
            assert(Hunt.Matches("a.c", "xa.cx"))
            assert(Hunt.Matches("(x)", "A (x) B"))
        end)

        it("never matches an empty hunt or a name that isn't text", function()
            assert(not Hunt.Matches("", "Anything"))
            assert(not Hunt.Matches("x", nil))
            assert(not Hunt.Matches("x", 5))
            assert(not Hunt.Matches("x", setmetatable({}, { __tostring = function() error("secret") end })))
        end)
    end)

    describe("MobHunter Hunt.ParseNames / lists", function()
        it("splits on commas, normalizes, and drops empties and repeats", function()
            assertEqual(Hunt.ParseNames("Raptor, LION,,  raptor ,Dire  Wolf"), { "raptor", "lion", "dire wolf" })
            assertEqual(Hunt.ParseNames(""), {})
            assertEqual(Hunt.ParseNames(nil), {})
        end)

        it("Matches takes a list and matches any of it; Describe joins it", function()
            assert(Hunt.Matches({ "raptor", "lion" }, "Savannah Lion"))
            assert(Hunt.Matches({ "raptor", "lion" }, "Bloodtalon Raptor"))
            assert(not Hunt.Matches({ "raptor", "lion" }, "Wolf"))
            assert(not Hunt.Matches({}, "Wolf"))
            assertEqual(Hunt.Describe({ "raptor", "lion" }), "raptor, lion")
            assertEqual(Hunt.Describe("wolf"), "wolf")
        end)

        it("Scan alerts once for each hunted mob in a list", function()
            local tracker = Hunt.NewTracker()
            local units = { { token = "n1", name = "Bloodtalon Raptor", guid = "G1" },
                { token = "n2", name = "Savannah Lion", guid = "G2" }, { token = "n3", name = "Wolf", guid = "G3" } }
            assertEqual(#Hunt.Scan(tracker, { "raptor", "lion" }, units), 2)
            assertEqual(#Hunt.Scan(tracker, { "raptor", "lion" }, units), 0)
        end)
    end)

    describe("MobHunter Hunt.ParseCommand", function()
        it("reads hunt, stop, status and help", function()
            assertEqual(Hunt.ParseCommand("Defias Pillager"), { action = "hunt", names = { "defias pillager" } })
            assertEqual(Hunt.ParseCommand("Raptor, lion"), { action = "hunt", names = { "raptor", "lion" } })
            assertEqual(Hunt.ParseCommand(" , "), { action = "status" })
            assertEqual(Hunt.ParseCommand("  stop "), { action = "stop" })
            assertEqual(Hunt.ParseCommand("OFF"), { action = "stop" })
            assertEqual(Hunt.ParseCommand(""), { action = "status" })
            assertEqual(Hunt.ParseCommand(nil), { action = "status" })
            assertEqual(Hunt.ParseCommand("help"), { action = "help" })
            assertEqual(Hunt.ParseCommand("target"), { action = "target" })
            assertEqual(Hunt.ParseCommand("macro"), { action = "macro" })
            assertEqual(Hunt.ParseCommand("Options"), { action = "options" })
            assertEqual(Hunt.ParseCommand("Quests"), { action = "quests" })
            assertEqual(Hunt.ParseCommand("window"), { action = "window" })
            assertEqual(Hunt.ParseCommand("Sound OFF"), { action = "sound", on = false })
            assertEqual(Hunt.ParseCommand("sound"), { action = "sound" })
            assertEqual(Hunt.ParseCommand("Button OFF"), { action = "button", on = false })
            assertEqual(Hunt.ParseCommand("button on"), { action = "button", on = true })
            assertEqual(Hunt.ParseCommand("button"), { action = "button" })
        end)
    end)

    describe("MobHunter Hunt.Scan", function()
        local function unit(token, name, extra)
            local u = { token = token, name = name, guid = "G-" .. token }
            for k, v in pairs(extra or {}) do u[k] = v end
            return u
        end

        it("reports a matching mob once while it stays in range", function()
            local tracker = Hunt.NewTracker()
            local units = { unit("nameplate1", "Defias Pillager"), unit("nameplate2", "Defias Bandit") }
            assertEqual(#Hunt.Scan(tracker, "pillager", units), 1)
            assertEqual(#Hunt.Scan(tracker, "pillager", units), 0)
        end)

        it("reports it again after it leaves range and returns", function()
            local tracker = Hunt.NewTracker()
            local units = { unit("nameplate1", "Defias Pillager") }
            Hunt.Scan(tracker, "pillager", units)
            Hunt.Scan(tracker, "pillager", {})
            assertEqual(#Hunt.Scan(tracker, "pillager", units), 1)
        end)

        it("reports each of several matching mobs, and a new one that joins later", function()
            local tracker = Hunt.NewTracker()
            local a, b = unit("nameplate1", "Wolf"), unit("nameplate2", "Wolf")
            assertEqual(#Hunt.Scan(tracker, "wolf", { a, b }), 2)
            assertEqual(#Hunt.Scan(tracker, "wolf", { a, b, unit("nameplate3", "Wolf") }), 1)
        end)

        it("ignores dead mobs and players", function()
            local tracker = Hunt.NewTracker()
            local found = Hunt.Scan(tracker, "bob", {
                unit("nameplate1", "Bob", { isDead = true }),
                unit("nameplate2", "Bob", { isPlayer = true }),
            })
            assertEqual(#found, 0)
        end)

        it("falls back to the unit token when there is no guid", function()
            local tracker = Hunt.NewTracker()
            local u = { token = "nameplate1", name = "Wolf" }
            assertEqual(#Hunt.Scan(tracker, "wolf", { u }), 1)
            assertEqual(#Hunt.Scan(tracker, "wolf", { u }), 0)
        end)
    end)

    describe("MobHunter Quests", function()
        it("compiles the client's positional row formats (count first)", function()
            local parse = Quests.CompileFormat("%2$d/%3$d %1$s slain")
            assertEqual(parse("0/10 Sunscale Scytheclaw slain"), { "Sunscale Scytheclaw", "0", "10" })
            local items = Quests.CompileFormat("%2$d/%3$d %1$s")
            assertEqual(items("3/6 Intact Raptor Horn"), { "Intact Raptor Horn", "3", "6" })
            assertEqual(items("0/15  "), { " ", "0", "15" }) -- blank name: kept raw here, trimmed by ParseRow
        end)

        it("also reads plain sequential formats and other word orders", function()
            local plain = Quests.CompileFormat("%s: %d/%d")
            assertEqual(plain("Raptor Horn: 3/6"), { "Raptor Horn", "3", "6" })
            assertEqual(plain("no numbers here"), nil)
            local swapped = Quests.CompileFormat("%3$d of %2$d: %1$s (100%%)")
            assertEqual(swapped("2 of 5: Wolf (100%)"), { "Wolf", "5", "2" })
        end)

        it("ParseRow takes counts from the row and the name from its text, nil when blank", function()
            local row = Quests.ParseRow({ type = "item", text = "0/1 Piece of Krom'zar's Banner", numFulfilled = 0, numRequired = 1, finished = false })
            assertEqual(row, { type = "item", name = "Piece of Krom'zar's Banner", have = 0, need = 1, finished = false })
            local blank = Quests.ParseRow({ type = "item", text = "0/15  ", numFulfilled = 0, numRequired = 15 })
            assertEqual(blank.name, nil)
            assertEqual(blank.need, 15)
            local kill = Quests.ParseRow({ type = "monster", text = "2/10 Marine slain", numFulfilled = 2, numRequired = 10 })
            assertEqual(kill.name, "Marine")
            local other = Quests.ParseRow({ type = "object", text = "0/1 Thing", numFulfilled = 0, numRequired = 1 })
            assertEqual(other.name, nil)
        end)

        it("Read lists visible quests with parsed rows and skips headers and hidden ones", function()
            local infos = { { isHeader = true, title = "Barrens" },
                { questID = 891, title = "The Guns of Northwatch" },
                { questID = 5, title = "Hidden", isHidden = true } }
            local rows = { [891] = { { type = "monster", text = "0/1 Captain Fairmount slain", numFulfilled = 0, numRequired = 1 },
                { type = "item", text = "0/5 Theramore Medal", numFulfilled = 0, numRequired = 5 } } }
            C_QuestLog = { GetNumQuestLogEntries = function() return #infos end, GetInfo = function(i) return infos[i] end,
                GetQuestObjectives = function(id) return rows[id] end }
            local quests = Quests.Read()
            C_QuestLog = nil
            assertEqual(#quests, 1)
            assertEqual(quests[1].title, "The Guns of Northwatch")
            assertEqual(quests[1].objectives[2].name, "Theramore Medal")
            assertEqual(quests[1].objectives[2].index, 2)
            assertEqual(Quests.Read(), {}) -- no quest API: empty, no error
        end)

        it("TopMobs ranks by rate, drops rare extras but keeps the best", function()
            local top = Quests.TopMobs({ { name = "Ishamuhale", rate = 1.4 }, { name = "Scytheclaw", rate = 26 },
                { name = "Takk", rate = 6.9 }, { name = "Guard" } })
            assertEqual(#top, 1)
            assertEqual(top[1].name, "Scytheclaw")
            local medals = Quests.TopMobs({ { name = "Marine", rate = 45.8 }, { name = "Whessan", rate = 15.6 }, { name = "Rare", rate = 2 } })
            assertEqual(#medals, 2)
            local unrated = Quests.TopMobs({ { name = "B" }, { name = "A" } })
            assertEqual(unrated[1].name, "B") -- no rates: all kept, order given
            assertEqual(#unrated, 2)
        end)

        it("Suggest lists kill targets, resolved drop sources, and skips finished rows", function()
            local quests = { { questID = 891, title = "The Guns of Northwatch", objectives = {
                    { type = "monster", name = "Captain Fairmount", finished = false },
                    { type = "monster", name = "Cannoneer Smythe", finished = true },
                    { type = "item", name = "Theramore Medal", finished = false } } },
                { questID = 9, title = "Another", objectives = { { type = "monster", name = "Captain Fairmount", finished = false },
                    { type = "item", finished = false } } } }
            local calls = {}
            local function resolve(quest, row, position, total)
                calls[#calls + 1] = { quest.questID, position, total }
                if quest.questID == 891 then
                    return { { name = "Theramore Marine", rate = 45.8 }, { name = "Theramore Preserver", rate = 32 } }, "Theramore Medal"
                end
                return nil, nil
            end
            local list, wanted, unnamed = Quests.Suggest(quests, resolve)
            local names = {}
            for _, s in ipairs(list) do names[#names + 1] = s.name end
            assertEqual(names, { "Captain Fairmount", "Theramore Marine", "Theramore Preserver" })
            assertEqual(list[1].quests, { "The Guns of Northwatch", "Another" }) -- one entry, both quests
            assertEqual(list[1].quest, "The Guns of Northwatch")
            assertEqual(wanted, { ["theramore medal"] = true })
            assertEqual(unnamed, true) -- the second quest's item row has no name
            assertEqual(calls, { { 891, 1, 1 }, { 9, 1, 1 } })
        end)

        it("Suggest works without a resolver (kill targets only) and Collect never raises", function()
            local list = Quests.Suggest({ { title = "Q", objectives = { { type = "monster", name = "Wolf" }, { type = "item", name = "Pelt" } } } })
            assertEqual(#list, 1)
            local ok = pcall(Quests.Collect, function() error("boom") end)
            assert(ok)
        end)
    end)

    describe("MobHunter Drops", function()
        local WOWHEAD = "return {\n    [5055] = { -- Intact Raptor Horn\n        [3256] = 25.9831,\n        [3257] = 1.3871,\n        [5842] = 6.8528,\n    },\n    [5078] = { -- Theramore Medal\n        [3385] = 45.796,\n        [3386] = 31.9952,\n    },\n}"
        local function fakeLib(overrides)
            local lib = {
                RequireContract = function(n) return n == 4 end,
                Quest = { objectives = function(id)
                    if id == 865 then return { [3] = { { 5055, nil, 0 } } } end
                    if id == 891 then return { [1] = { { 3393, nil, 0 } }, [3] = { { 5078, nil, 0 } } } end
                end },
                Item = { name = function(id) return ({ [5055] = "Intact Raptor Horn", [5078] = "Theramore Medal" })[id] end,
                    npcDrops = function(id)
                        if id == 5055 then return { 3256, 3257, 5842 } end
                        if id == 5078 then return { 3385, 3386, 261485 } end
                    end },
                Npc = { name = function(id) return ({ [3256] = "Sunscale Scytheclaw", [3257] = "Ishamuhale", [5842] = "Takk the Leaper",
                    [3385] = "Theramore Marine", [3386] = "Theramore Preserver", [261485] = "Theramore Guard" })[id] end },
                Support = { Get = function() return { wowheadData = WOWHEAD } end },
            }
            for k, v in pairs(overrides or {}) do lib[k] = v end
            return lib
        end

        it("Bridge needs LibQuestieDB with a supported contract", function()
            LibQuestieDB = nil
            assertEqual(Drops.Bridge(), nil)
            LibQuestieDB = fakeLib({ RequireContract = function() return false end })
            assertEqual(Drops.Bridge(), nil)
            LibQuestieDB = fakeLib({ RequireContract = function() error("old") end })
            assertEqual(Drops.Bridge(), nil)
            LibQuestieDB = fakeLib()
            assert(Drops.Bridge())
            LibQuestieDB = nil
        end)

        it("MatchItem goes by name, then by position when the counts agree", function()
            local names = { [1] = "Alpha", [2] = "Beta" }
            local nameOf = function(id) return names[id] end
            assertEqual(Drops.MatchItem({ 1, 2 }, "beta", 1, 2, nameOf), 2)
            assertEqual(Drops.MatchItem({ 1, 2 }, nil, 2, 2, nameOf), 2)
            assertEqual(Drops.MatchItem({ 1, 2 }, nil, 1, 3, nameOf), nil)
            assertEqual(Drops.MatchItem({ 1 }, "Unknown", 1, 1, nameOf), 1)
        end)

        it("Rates cuts one item's block out of the Wowhead string", function()
            local lib = fakeLib()
            local rates = Drops.Rates(lib, 5055)
            assertEqual(rates[3256], 25.9831)
            assertEqual(rates[5842], 6.8528)
            assertEqual(rates[3385], nil) -- another item's block
            assertEqual(Drops.Rates(fakeLib({ Support = { Get = function() error("x") end } }), 9999), {})
        end)

        it("ForRow resolves a quest item row to the mobs that drop it, with rates", function()
            LibQuestieDB = fakeLib()
            local mobs, item = Drops.ForRow({ questID = 865 }, { name = nil }, 1, 1) -- blank row name
            LibQuestieDB = nil
            assertEqual(item, "Intact Raptor Horn")
            assertEqual(mobs[1], { name = "Sunscale Scytheclaw", rate = 25.9831 })
            assertEqual(#mobs, 3)
        end)

        it("through Suggest, Raptor Horns shows the Scytheclaws and the medal shows Marines and Preservers", function()
            LibQuestieDB = fakeLib()
            local list = Quests.Suggest({
                { questID = 865, title = "Raptor Horns", objectives = { { type = "item", finished = false } } },
                { questID = 891, title = "The Guns of Northwatch", objectives = { { type = "monster", name = "Captain Fairmount" },
                    { type = "item", name = "Theramore Medal", finished = false } } } }, Drops.ForRow)
            LibQuestieDB = nil
            local names = {}
            for _, s in ipairs(list) do names[#names + 1] = s.name end
            assertEqual(names, { "Sunscale Scytheclaw", "Captain Fairmount", "Theramore Marine", "Theramore Preserver" })
        end)

        it("a database error or an item with no mobs falls back to learned drops", function()
            MobHunterDB = {}
            Drops.Learn("Pelt", "Wolf"); Drops.Learn("pelt", "Wolf"); Drops.Learn("Pelt", "Bear")
            LibQuestieDB = fakeLib({ Quest = { objectives = function() error("bad") end } })
            local mobs = Drops.ForRow({ questID = 1 }, { name = "Pelt" }, 1, 1)
            assertEqual(mobs[1].name, "Wolf")
            assertEqual(#mobs, 2)
            LibQuestieDB = nil
            assertEqual(Drops.ForRow({ questID = 1 }, { name = "Nothing" }, 1, 1), {})
            assertEqual(Drops.ForRow({ questID = 1 }, {}, 1, 1), nil) -- no name at all: nothing known
            MobHunterDB = nil
        end)
    end)

    describe("MobHunter Probe", function()
        it("Grid covers a circle, centred on 0,0", function()
            local points = Probe.Grid(10, 5)
            local hasCentre = false
            for _, p in ipairs(points) do
                assert(p[1] * p[1] + p[2] * p[2] <= 100, "point outside the circle")
                if p[1] == 0 and p[2] == 0 then hasCentre = true end
            end
            assert(hasCentre)
            assert(#points > 9)
        end)

        -- A fake minimap whose soft cursor "hovers" a tracking dot named `dotName` at (dotX, dotY).
        local function fakeMinimap(dotName, dotX, dotY, radius)
            Probe.fitRadius, Probe.fitScans = nil, nil
            local m = { cursor = nil, soft = false, softCalls = {} }
            function m:GetLeft() return 0 end
            function m:GetBottom() return 0 end
            function m:GetEffectiveScale() return 1 end
            function m:GetWidth() return radius * 2 end
            function m:SetUsingSoftCursor(on) self.soft = on; self.softCalls[#self.softCalls + 1] = on end
            function m:UpdateMouseoverAtPoint(x, y) self.cursor = { x, y } end
            C_TooltipInfo = { GetMinimapMouseover = function()
                local x, y = m.cursor[1], m.cursor[2]
                if (x - dotX) ^ 2 + (y - dotY) ^ 2 <= 100 then
                    return { lines = { { leftText = dotName } } }
                end
            end }
            return m
        end

        it("Find locates a tracked dot by name and reports its offset from the centre", function()
            local m = fakeMinimap("Defias Pillager", 70, 80, 70) -- 0 px right of centre, 10 up
            local centres = Probe.Find(m, "pillager", 2)
            assertEqual(#centres, 1)
            assert(math.abs(centres[1][1] - 0) < 3, "dx " .. centres[1][1])
            assert(math.abs(centres[1][2] - 10) < 3, "dy " .. centres[1][2])
            assertEqual(m.soft, false) -- the soft cursor is always switched back off
        end)

        it("Find returns no centres when nothing matches", function()
            local m = fakeMinimap("Defias Bandit", 70, 80, 70)
            assertEqual(Probe.Find(m, "pillager", 2), {})
        end)

        it("Find is nil, not an error, when the client lacks the probe methods", function()
            C_TooltipInfo = nil
            assertEqual(Probe.Find({ GetWidth = function() return 100 end }, "x", 2), nil)
            assertEqual(Probe.Find(nil, "x", 2), nil)
        end)

        it("Find survives errors from the client and still restores the soft cursor", function()
            local m = fakeMinimap("x", 0, 0, 20)
            function m:UpdateMouseoverAtPoint() error("boom") end
            assertEqual(Probe.Find(m, "x", 2), {})
            assertEqual(m.soft, false)
        end)

        it("LineText reads leftText, or surfaces it from args", function()
            assertEqual(Probe.LineText({ leftText = "Wolf" }), "Wolf")
            assertEqual(Probe.LineText({ args = { { field = "x" }, { stringVal = "Prairie Stalker" } } }), "Prairie Stalker")
            TooltipUtil = { SurfaceArgs = function(line) line.leftText = "Surfaced" end }
            assertEqual(Probe.LineText({ args = {} }), "Surfaced")
            TooltipUtil = nil
            assertEqual(Probe.LineText(nil), nil)
        end)

        it("CountMatches counts every matching name, including repeats on one line", function()
            local data = { lines = { { leftText = "Greater Plainstrider\nGreater Plainstrider\nMoonlit Arz" },
                { leftText = "Greater Plainstrider" } } }
            assertEqual(Probe.CountMatches("plainstrider", data), 3)
            assertEqual(Probe.CountMatches("arz", data), 1)
            assertEqual(Probe.CountMatches("wolf", data), 0)
            assertEqual(Probe.CountMatches("wolf", { lines = {} }), 0)
            assertEqual(Probe.CountMatches("wolf", nil), 0)
        end)

        -- Probe results for dots with a 15-unit hit radius on a 3-unit grid: n = dots covering a point.
        local function counts(dots)
            local points = {}
            for x = 0, 120, 3 do
                for y = 0, 120, 3 do
                    local n = 0
                    for _, d in ipairs(dots) do
                        if (x - d[1]) ^ 2 + (y - d[2]) ^ 2 <= 225 then n = n + 1 end
                    end
                    points[#points + 1] = { x, y, n }
                end
            end
            return points
        end
        local function near(centres, x, y)
            for _, c in ipairs(centres) do
                if math.abs(c[1] - x) <= 4 and math.abs(c[2] - y) <= 4 then return true end
            end
            return false
        end

        it("Fit finds one dot at its middle", function()
            local centres = Probe.Fit(counts({ { 60, 60 } }), 15)
            assertEqual(#centres, 1)
            assert(near(centres, 60, 60))
        end)

        it("Fit separates dots that overlap, because the counts show two dots", function()
            local dots = { { 45, 60 }, { 58, 60 }, { 100, 20 } } -- the first two are 13 apart
            local centres = Probe.Fit(counts(dots), 15)
            assertEqual(#centres, 3)
            for _, d in ipairs(dots) do assert(near(centres, d[1], d[2]), "missing " .. d[1] .. "," .. d[2]) end
        end)

        it("FitBest works out the hit radius from the data", function()
            Probe.fitRadius, Probe.fitScans = nil, nil
            local function counts11(dots)
                local points = {}
                for x = 0, 120, 3 do
                    for y = 0, 120, 3 do
                        local n = 0
                        for _, d in ipairs(dots) do
                            if (x - d[1]) ^ 2 + (y - d[2]) ^ 2 <= 121 then n = n + 1 end
                        end
                        points[#points + 1] = { x, y, n }
                    end
                end
                return points
            end
            local dots = { { 40, 40 }, { 52, 40 }, { 90, 90 } } -- 11-unit blobs, the first two 12 apart
            local centres, radius = Probe.FitBest(counts11(dots))
            assertEqual(#centres, 3)
            assert(radius >= 10 and radius <= 12, "radius " .. tostring(radius))
            Probe.fitRadius, Probe.fitScans = nil, nil
        end)

        it("CountMatches counts dots of any hunted name", function()
            local data = { lines = { { leftText = "Savannah Lion\nBloodtalon Raptor\nWolf" } } }
            assertEqual(Probe.CountMatches({ "raptor", "lion" }, data), 2)
            assertEqual(Probe.CountMatches({ "raptor" }, data), 1)
        end)

        it("Diagnose tries other coordinate styles when nothing answers", function()
            local m = fakeMinimap("Defias Pillager", 100000, 100000, 20) -- dot far off the grid
            m.GetCenter = function() return 20, 20 end
            local report = table.concat(Probe.Diagnose(m, 8, "pillager"), "\n")
            assert(report:find("coordinates no scale: 0 points", 1, true), report)
            assert(report:find("coordinates centre of minimap: 0 points", 1, true), report)
        end)

        it("Diagnose reports the fit for the hunted name", function()
            local m = fakeMinimap("Defias Pillager", 70, 80, 70)
            local report = table.concat(Probe.Diagnose(m, 6, "pillager"), "\n")
            assert(report:find("revision", 1, true) and report:find("hunting: pillager", 1, true), report)
            assert(report:find("Hunting 'pillager': 1 dots", 1, true), report)
            assert(report:find("hit radius", 1, true), report)
        end)

        it("Fit of nothing is nothing", function()
            assertEqual(Probe.Fit(counts({}), 15), {})
        end)

        it("Find reports dots that sit close together separately", function()
            local m = fakeMinimap("Greater Plainstrider", 60, 70, 70)
            Probe.fitRadius, Probe.fitScans = nil, nil
            local dots = { { 55, 70 }, { 68, 70 }, { 105, 100 } }
            C_TooltipInfo = { GetMinimapMouseover = function()
                local x, y = m.cursor[1], m.cursor[2]
                local lines
                for _, d in ipairs(dots) do
                    if (x - d[1]) ^ 2 + (y - d[2]) ^ 2 <= 15 * 15 then
                        lines = lines or {}
                        lines[#lines + 1] = { leftText = "Greater Plainstrider" }
                    end
                end
                return { lines = lines or {} }
            end }
            assertEqual(#Probe.Find(m, "plainstrider", 6), 3)
        end)

        it("Advance spreads a scan over many calls and ends with the same dots as Find", function()
            local m = fakeMinimap("Defias Pillager", 70, 80, 70)
            local whole = Probe.Find(m, "pillager", 8)
            Probe.fitRadius, Probe.fitScans = nil, nil
            local job = Probe.StartScan(m, "pillager", 8)
            local calls, done, centres = 0, false, nil
            while not done do
                done, centres = Probe.Advance(job, 40)
                calls = calls + 1
                assert(calls < 500)
            end
            assert(calls > 5, "calls " .. calls)
            assertEqual(#centres, #whole)
            assertEqual(m.soft, false)
        end)

        it("Find passes screen coordinates: (left + x) * scale, (bottom + y) * scale, as NodeSight does", function()
            local calls = {}
            local m = {}
            function m:GetWidth() return 140 end
            function m:GetLeft() return 100 end
            function m:GetBottom() return 50 end
            function m:GetEffectiveScale() return 2 end
            function m:SetUsingSoftCursor() end
            function m:UpdateMouseoverAtPoint(x, y) calls[#calls + 1] = { x, y } end
            C_TooltipInfo = { GetMinimapMouseover = function() return { lines = {} } end }
            Probe.Find(m, "x", 70)
            -- first grid point is (-70, 0) from the centre: minimap-local (0, 70)
            assertEqual(calls[1], { (100 + 0) * 2, (50 + 70) * 2 })
        end)

        it("IsTracking assumes yes when the client can't say, and reads active flags otherwise", function()
            C_Minimap = nil
            assertEqual(Probe.IsTracking(), true)
            C_Minimap = { GetNumTrackingTypes = function() return 2 end,
                GetTrackingInfo = function(i) return { active = i == 2 } end }
            assertEqual(Probe.IsTracking(), true)
            C_Minimap.GetTrackingInfo = function() return { active = false } end
            assertEqual(Probe.IsTracking(), false)
            C_Minimap.GetTrackingInfo = function(i) return "Find Herbs", 1, i == 1 end
            assertEqual(Probe.IsTracking(), true)
            C_Minimap = nil
        end)
    end)

    describe("MobHunter.lua (against a permissive fake client)", function()
        local realPrint = print
        local printed, sounds, frames
        -- Runs a test body and puts the real print back afterwards (the fake client captures it).
        local function test(name, fn)
            it(name, function()
                local ok, err = pcall(fn)
                print = realPrint
                if not ok then error(err, 0) end
            end)
        end
        local function fakeWidget()
            local w = { attrs = {}, scripts = {}, shown = true }
            return setmetatable(w, { __index = function(t, k)
                if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
                if k == "SetAttribute" then return function(self, a, v) self.attrs[a] = v end end
                if k == "Show" then return function(self) self.shown = true end end
                if k == "Hide" then return function(self) self.shown = false end end
                if k == "SetChecked" then return function(self, on) self.checked = on and true or false end end
                if k == "SetShown" then return function(self, on) self.shown = on and true or false end end
                if k == "GetWidth" then return function() return 140 end end
                return function() return t end -- any other method: no-op returning itself
            end })
        end

        local function install(options)
            options = options or {}
            printed, sounds, frames = {}, {}, {}
            print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
            CreateFrame = function(_, name)
                local f = fakeWidget()
                frames[#frames + 1] = f
                if name then _G[name] = f end
                return f
            end
            UIParent = fakeWidget()
            Minimap = fakeWidget()
            C_TooltipInfo, C_Minimap = nil, nil
            InCombatLockdown = function() return options.combat or false end
            PlaySound = function(id) sounds[#sounds + 1] = id end
            GetCVar = function() return "1" end
            SOUNDKIT = nil
            UIErrorsFrame = nil
            C_Timer = { NewTicker = function() return { Cancel = function() end } end }
            C_NamePlate = {
                GetNamePlates = function() return options.plates or {} end,
                GetNamePlateForUnit = function() return fakeWidget() end,
            }
            local names = options.names or {}
            UnitName = function(t) return names[t] end
            UnitGUID = function(t) return "G-" .. t end
            UnitIsDead = function() return false end
            UnitIsPlayer = function() return false end
            SlashCmdList = {}
            local mh = {}
            for _, file in ipairs({ "Hunt.lua", "Quests.lua", "Drops.lua", "Probe.lua", "HuntWindow.lua", "Options.lua", "MobHunter.lua" }) do loadAddonFile(mh, file, "MobHunter") end
            return mh
        end

        test("loads, registers the slash commands and the keybind strings", function()
            install()
            assert(SlashCmdList["MOBHUNT"])
            assertEqual(SLASH_MOBHUNT1, "/mobhunt")
            assertEqual(_G["BINDING_NAME_CLICK MobHunterTargetButton:LeftButton"], "Target the hunted mob")
        end)

        test("/mobhunt <name> arms the secure button with a /target macro", function()
            install()
            SlashCmdList["MOBHUNT"]("Defias Pillager")
            assertEqual(MobHunterTargetButton.attrs.type, "macro")
            assertEqual(MobHunterTargetButton.attrs.macrotext, "/target defias pillager")
            assertEqual(MobHunterTargetButton.shown, false) -- nothing in range yet
            SlashCmdList["MOBHUNT"]("stop")
            assertEqual(MobHunterTargetButton.attrs.macrotext, "")
            assertEqual(MobHunterTargetButton.shown, false)
        end)

        test("alerts with a sound when a matching nameplate is in range, and only once", function()
            local mh = install({ plates = { { unitToken = "nameplate1" }, { unitToken = "nameplate2" } },
                names = { nameplate1 = "Defias Pillager", nameplate2 = "Defias Bandit" } })
            SlashCmdList["MOBHUNT"]("pillager")
            assertEqual(#sounds, 1)
            mh.MobHunter.Scan()
            assertEqual(#sounds, 1)
        end)

        test("once a mob is seen the button targets its full name, not the typed text", function()
            install({ plates = { { unitToken = "nameplate2" } }, names = { nameplate2 = "Defias Pillager" } })
            SlashCmdList["MOBHUNT"]("pillager")
            assertEqual(MobHunterTargetButton.attrs.macrotext, "/target Defias Pillager")
            assertEqual(MobHunterTargetButton.shown, true)
            local frame = MobHunterEventFrame
            frame.scripts.OnEvent(frame, "NAME_PLATE_UNIT_REMOVED", "nameplate2")
            assertEqual(MobHunterTargetButton.attrs.macrotext, "/target pillager")
            assertEqual(MobHunterTargetButton.shown, false)
        end)

        test("a hunted mob among the tracking dots gets MobHunter's icon on the minimap, removed when it goes", function()
            local mh = install()
            local dotUp = true
            local cursor
            rawset(Minimap, "GetLeft", function() return 0 end)
            rawset(Minimap, "GetBottom", function() return 0 end)
            rawset(Minimap, "GetEffectiveScale", function() return 1 end)
            rawset(Minimap, "SetUsingSoftCursor", function() end)
            rawset(Minimap, "UpdateMouseoverAtPoint", function(_, x, y) cursor = { x, y } end)
            C_TooltipInfo = { GetMinimapMouseover = function()
                if dotUp and (cursor[1] - 80) ^ 2 + (cursor[2] - 90) ^ 2 <= 100 then
                    return { lines = { { leftText = "Defias Pillager" } } }
                end
            end }
            local minimapChildren = {}
            local baseCreate = CreateFrame
            CreateFrame = function(kind, name, parent, ...)
                local f = baseCreate(kind, name, parent, ...)
                if parent == Minimap then minimapChildren[#minimapChildren + 1] = f end
                return f
            end
            local clock = 0
            GetTime = function() return clock end
            -- the scan is spread over frames: run the driver's OnUpdate until it stops itself
            local function pump()
                local frames = 0
                while MobHunterDriverFrame and MobHunterDriverFrame.scripts.OnUpdate do
                    MobHunterDriverFrame.scripts.OnUpdate()
                    frames = frames + 1
                    assert(frames < 2000, "the scan never finished")
                end
                return frames
            end
            SlashCmdList["MOBHUNT"]("pillager")
            assertEqual(#minimapChildren, 0) -- nothing yet: the scan has only been queued
            assert(pump() > 3, "the scan should take several frames, not one")
            assertEqual(#minimapChildren, 1)
            assertEqual(minimapChildren[1].shown, true)
            dotUp = false
            mh.MobHunter.Scan()
            pump()
            assertEqual(minimapChildren[1].shown, true) -- too soon: the next scan waits
            clock = 100
            mh.MobHunter.Scan()
            pump()
            assertEqual(minimapChildren[1].shown, false)
            GetTime = nil
        end)

        test("/mobhunt button off keeps the button hidden even with a mob in range; on brings it back", function()
            install({ plates = { { unitToken = "nameplate2" } }, names = { nameplate2 = "Defias Pillager" } })
            MobHunterDB = { showButton = true }
            SlashCmdList["MOBHUNT"]("button off")
            assertEqual(MobHunterDB.showButton, false)
            SlashCmdList["MOBHUNT"]("pillager")
            assertEqual(MobHunterTargetButton.shown, false)
            assertEqual(MobHunterTargetButton.attrs.macrotext, "/target Defias Pillager") -- /click still works
            SlashCmdList["MOBHUNT"]("button on")
            assertEqual(MobHunterTargetButton.shown, true)
            MobHunterDB = nil
        end)

        test("/mobhunt target explains the /click macro instead of trying to target", function()
            install()
            SlashCmdList["MOBHUNT"]("target")
            assert(printed[1]:find("/mobhunt macro", 1, true))
        end)

        test("/mobhunt macro makes a character macro that follows the hunt", function()
            install({ plates = { { unitToken = "nameplate2" } }, names = { nameplate2 = "Prairie Stalker" } })
            local macros = {}
            GetMacroIndexByName = function(name) return macros[name] and 1 or 0 end
            CreateMacro = function(name, _, body) macros[name] = body end
            EditMacro = function(_, _, _, body) macros.MobHunter = body end
            SlashCmdList["MOBHUNT"]("macro")
            assertEqual(macros.MobHunter, "/mobhunt")
            SlashCmdList["MOBHUNT"]("stalker")
            assertEqual(macros.MobHunter, "/target Prairie Stalker")
            SlashCmdList["MOBHUNT"]("stop")
            assertEqual(macros.MobHunter, "/mobhunt")
            GetMacroIndexByName, CreateMacro, EditMacro = nil, nil, nil
        end)

        test("/mobhunt debug reports what the minimap probe sees", function()
            install()
            rawset(Minimap, "GetLeft", function() return 0 end)
            rawset(Minimap, "GetBottom", function() return 0 end)
            rawset(Minimap, "GetEffectiveScale", function() return 1 end)
            rawset(Minimap, "SetUsingSoftCursor", function() end)
            rawset(Minimap, "UpdateMouseoverAtPoint", function() end)
            C_TooltipInfo = { GetMinimapMouseover = function() return { lines = { { leftText = "Herb" } } } end }
            SlashCmdList["MOBHUNT"]("debug")
            local all = table.concat(printed, "\n")
            assert(all:find("window", 1, true))
            assertEqual(MobHunterReportFrame.shown, true)
            assert(table.concat(MobHunterDB.lastDebug, "\n"):find("Herb", 1, true))
            C_TooltipInfo = nil
            SlashCmdList["MOBHUNT"]("debug")
            assert(table.concat(MobHunterDB.lastDebug, "\n"):find("unavailable", 1, true))
            MobHunterDB = nil
        end)

        test("registers an options page whose checkbox drives the button setting", function()
            local registered
            Settings = {
                RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name, GetID = function() return 7 end } end,
                RegisterAddOnCategory = function(c) registered = c end,
                OpenToCategory = function(id) Settings.opened = id end,
            }
            local mh = install()
            MobHunterDB = { showButton = true }
            local frame = MobHunterEventFrame
            frame.scripts.OnEvent(frame, "ADDON_LOADED", "MobHunter")
            assertEqual(registered.name, "MobHunter")
            local box = mh.Options.panel.controls.showButton
            rawset(box, "GetChecked", function() return false end)
            box.scripts.OnClick(box)
            assertEqual(MobHunterDB.showButton, false)
            assertEqual(mh.MobHunter.GetShowButton(), false)
            SlashCmdList["MOBHUNT"]("options")
            assertEqual(Settings.opened, 7)
            MobHunterDB, Settings = nil, nil
        end)

        test("the Hunt window starts and stops a hunt, and the options toggle it and the Target button", function()
            Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
                RegisterAddOnCategory = function() end }
            local mh = install({ plates = { { unitToken = "nameplate2" } }, names = { nameplate2 = "Prairie Stalker" } })
            MobHunterDB = { showButton = true }
            local frame = MobHunterEventFrame
            frame.scripts.OnEvent(frame, "ADDON_LOADED", "MobHunter")
            local c = mh.Options.panel.controls

            -- hidden by default; the options checkbox shows it
            assertEqual(MobHunterHuntFrame.shown, false)
            rawset(c.showWindow, "GetChecked", function() return true end)
            c.showWindow.scripts.OnClick(c.showWindow)
            assertEqual(MobHunterHuntFrame.shown, true)
            assertEqual(MobHunterDB.showHuntWindow, true)

            -- the window's box + Start hunts; the Target button lives in the window
            local edit
            for _, f in ipairs(frames) do if f.scripts and f.scripts.OnEnterPressed then edit = f end end
            rawset(edit, "GetText", function() return "  Prairie Stalker " end)
            edit.scripts.OnEnterPressed(edit)
            assertEqual(MobHunterTargetButton.attrs.macrotext, "/target Prairie Stalker")
            assertEqual(MobHunterTargetButton.shown, true)

            -- unticking "Target button in the Hunt window" hides it but the macro stays armed
            rawset(c.showButton, "GetChecked", function() return false end)
            c.showButton.scripts.OnClick(c.showButton)
            assertEqual(MobHunterTargetButton.shown, false)
            assertEqual(MobHunterTargetButton.attrs.macrotext, "/target Prairie Stalker")

            -- the macro button creates the MobHunter macro, like /mobhunt macro
            local macros = {}
            GetMacroIndexByName = function(n) return macros[n] and 1 or 0 end
            CreateMacro = function(n, _, body) macros[n] = body end
            EditMacro = function(_, _, _, body) macros.MobHunter = body end
            c.macro.scripts.OnClick(c.macro)
            assert(macros.MobHunter)
            GetMacroIndexByName, CreateMacro, EditMacro = nil, nil, nil

            SlashCmdList["MOBHUNT"]("stop")
            assertEqual(MobHunterTargetButton.attrs.macrotext, "")
            SlashCmdList["MOBHUNT"]("window")
            assertEqual(MobHunterHuntFrame.shown, false)
            MobHunterDB, Settings = nil, nil
        end)

        test("no alert sound for a hunted mob that is already the player's target", function()
            install({ plates = { { unitToken = "nameplate1" }, { unitToken = "nameplate2" } },
                names = { nameplate1 = "Prairie Stalker", nameplate2 = "Prairie Stalker" } })
            UnitIsUnit = function(token, other) return token == "nameplate1" and other == "target" end
            SlashCmdList["MOBHUNT"]("stalker")
            assertEqual(#sounds, 1) -- only nameplate2, the one not targeted
            UnitIsUnit = nil
        end)

        test("the sound checkbox (and /mobhunt sound) turns the alert sound off and on", function()
            Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
                RegisterAddOnCategory = function() end }
            local mh = install({ plates = { { unitToken = "nameplate1" } }, names = { nameplate1 = "Prairie Stalker" } })
            MobHunterDB = { showButton = true }
            local frame = MobHunterEventFrame
            frame.scripts.OnEvent(frame, "ADDON_LOADED", "MobHunter")
            assertEqual(MobHunterDB.playSound, true) -- on by default
            assertEqual(mh.MobHunter.GetWindow().sound.checked, true) -- the Hunt window's box shows it from the start
            local box = mh.Options.panel.controls.playSound
            rawset(box, "GetChecked", function() return false end)
            box.scripts.OnClick(box)
            assertEqual(MobHunterDB.playSound, false)
            SlashCmdList["MOBHUNT"]("sound on")
            assertEqual(mh.MobHunter.GetWindow().sound.checked, true) -- /mobhunt sound updates the window too
            SlashCmdList["MOBHUNT"]("sound off")
            assertEqual(mh.MobHunter.GetWindow().sound.checked, false)
            SlashCmdList["MOBHUNT"]("stalker")
            assertEqual(#sounds, 0) -- found, but silent
            SlashCmdList["MOBHUNT"]("stop")
            -- the Hunt window has the same checkbox
            local windowBox = mh.MobHunter.GetWindow().sound
            rawset(windowBox, "GetChecked", function() return true end)
            windowBox.scripts.OnClick(windowBox)
            assertEqual(MobHunterDB.playSound, true)
            rawset(windowBox, "GetChecked", function() return false end)
            windowBox.scripts.OnClick(windowBox)
            assertEqual(MobHunterDB.playSound, false)
            SlashCmdList["MOBHUNT"]("sound on")
            SlashCmdList["MOBHUNT"]("stalker")
            assertEqual(#sounds, 1)
            MobHunterDB, Settings = nil, nil
        end)

        test("/mobhunt raptor, lion hunts both: each alerts, and the window shows a box for each", function()
            local mh = install({ plates = { { unitToken = "nameplate1" }, { unitToken = "nameplate2" },
                { unitToken = "nameplate3" } },
                names = { nameplate1 = "Bloodtalon Raptor", nameplate2 = "Savannah Lion", nameplate3 = "Wolf" } })
            SlashCmdList["MOBHUNT"]("raptor, lion")
            assertEqual(#sounds, 2)
            assertEqual(mh.MobHunter.GetWindow().count, 2)
            SlashCmdList["MOBHUNT"]("")
            assert(printed[#printed]:find("raptor, lion", 1, true), printed[#printed])
            SlashCmdList["MOBHUNT"]("stop")
        end)

        test("the Hunt window: Add hunt adds a box, x removes it, Start sends every box's text", function()
            local mh = install({ plates = { { unitToken = "nameplate1" } }, names = { nameplate1 = "Savannah Lion" } })
            local window = mh.MobHunter.GetWindow()
            if not window then
                MobHunterDB = {}
                local frame = MobHunterEventFrame
                frame.scripts.OnEvent(frame, "ADDON_LOADED", "MobHunter")
                window = mh.MobHunter.GetWindow()
            end
            assertEqual(window.count, 1)
            window.addButton.scripts.OnClick(window.addButton)
            assertEqual(window.count, 2)
            window.rows[2].remove.scripts.OnClick(window.rows[2].remove)
            assertEqual(window.count, 1)
            window.addButton.scripts.OnClick(window.addButton)
            rawset(window.rows[1].edit, "GetText", function() return "raptor" end)
            rawset(window.rows[2].edit, "GetText", function() return " Lion " end)
            window.startButton.scripts.OnClick(window.startButton)
            SlashCmdList["MOBHUNT"]("")
            assert(printed[#printed]:find("raptor, lion", 1, true), printed[#printed])
            MobHunterDB = nil
        end)

        -- quest targets: a fake quest log with one kill quest, and whatever the test sets in `rows`
        local function questLog(rows)
            local infos = { { questID = 891, title = "The Guns of Northwatch" } }
            C_QuestLog = { GetNumQuestLogEntries = function() return #infos end, GetInfo = function(i) return infos[i] end,
                GetQuestObjectives = function() return rows end }
        end
        local function loaded()
            MobHunterDB = {}
            local mh = install()
            local frame = MobHunterEventFrame
            frame.scripts.OnEvent(frame, "ADDON_LOADED", "MobHunter")
            return mh, frame
        end

        test("quest targets from the log fill the Hunt window; clicking one hunts it without resetting the others", function()
            questLog({ { type = "monster", text = "0/1 Captain Fairmount slain", numFulfilled = 0, numRequired = 1 },
                { type = "monster", text = "0/1 Cannoneer Smythe slain", numFulfilled = 0, numRequired = 1 } })
            local mh, frame = loaded()
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            local window = mh.MobHunter.GetWindow()
            assertEqual(#window.suggestions, 2)
            assertEqual(window.suggestButtons[1].suggestion.name, "Captain Fairmount")
            SlashCmdList["MOBHUNT"]("wolf")
            window.suggestButtons[2].scripts.OnClick(window.suggestButtons[2])
            window.suggestButtons[1].scripts.OnClick(window.suggestButtons[1])
            window.suggestButtons[1].scripts.OnClick(window.suggestButtons[1]) -- again: no repeat
            SlashCmdList["MOBHUNT"]("")
            assert(printed[#printed]:find("wolf, cannoneer smythe, captain fairmount", 1, true), printed[#printed])
            SlashCmdList["MOBHUNT"]("stop")
            C_QuestLog, MobHunterDB = nil, nil
        end)

        test("with nothing hunted, clicking a quest target starts a hunt", function()
            questLog({ { type = "monster", text = "0/1 Captain Fairmount slain", numFulfilled = 0, numRequired = 1 } })
            local mh, frame = loaded()
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            mh.MobHunter.AddHunt("Captain Fairmount")
            assertEqual(MobHunterTargetButton.attrs.macrotext, "/target captain fairmount")
            SlashCmdList["MOBHUNT"]("stop")
            C_QuestLog, MobHunterDB = nil, nil
        end)

        test("/mobhunt quests lists them; the setting off hides them", function()
            questLog({ { type = "monster", text = "0/1 Captain Fairmount slain", numFulfilled = 0, numRequired = 1 } })
            local mh, frame = loaded()
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            SlashCmdList["MOBHUNT"]("quests")
            assert(printed[#printed]:find("Captain Fairmount", 1, true), printed[#printed])
            mh.MobHunter.SetShowSuggestions(false)
            assertEqual(#mh.MobHunter.GetSuggestions(), 0)
            assertEqual(#mh.MobHunter.GetWindow().suggestions, 0)
            SlashCmdList["MOBHUNT"]("quests")
            assert(printed[#printed]:find("no quest targets", 1, true), printed[#printed])
            C_QuestLog, MobHunterDB = nil, nil
        end)

        test("automatic adding hunts suggestions, drops finished ones, and respects Stop", function()
            local rows = { { type = "monster", text = "0/1 Captain Fairmount slain", numFulfilled = 0, numRequired = 1 } }
            questLog(rows)
            local mh, frame = loaded()
            mh.MobHunter.SetAutoAdd(true)
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            SlashCmdList["MOBHUNT"]("")
            assert(printed[#printed]:find("captain fairmount", 1, true), printed[#printed])
            -- objective done: the auto-added mob goes, and with nothing left the hunt stops
            rows[1].finished = true
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            SlashCmdList["MOBHUNT"]("")
            assert(printed[#printed]:find("not hunting", 1, true), printed[#printed])
            -- Stop by hand: the same target is not added again
            rows[1].finished = false
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            mh.MobHunter.UserStop()
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            SlashCmdList["MOBHUNT"]("")
            assert(printed[#printed]:find("not hunting", 1, true), printed[#printed])
            C_QuestLog, MobHunterDB = nil, nil
        end)

        test("a typed hunt keeps its names when a suggestion finishes", function()
            local rows = { { type = "monster", text = "0/1 Wolf slain", numFulfilled = 0, numRequired = 1 } }
            questLog(rows)
            local mh, frame = loaded()
            mh.MobHunter.SetAutoAdd(true)
            SlashCmdList["MOBHUNT"]("wolf") -- typed by hand, and also a quest target
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            rows[1].finished = true
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            SlashCmdList["MOBHUNT"]("")
            assert(printed[#printed]:find("hunting", 1, true) and printed[#printed]:find("wolf", 1, true), printed[#printed])
            SlashCmdList["MOBHUNT"]("stop")
            C_QuestLog, MobHunterDB = nil, nil
        end)

        test("looting a needed quest item from your target teaches that mob", function()
            local rows = { { type = "item", text = "0/5 Theramore Medal", numFulfilled = 0, numRequired = 5 } }
            questLog(rows)
            local mh, frame = loaded()
            frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
            UnitGUID = function(unit) return unit == "target" and "Creature-0-1" or nil end
            UnitName = function(unit) return unit == "target" and "Theramore Marine" or nil end
            GetNumLootItems = function() return 1 end
            GetLootSlotLink = function() return "|cffffffff|Hitem:5078|h[Theramore Medal]|h|r" end
            GetLootSourceInfo = function() return "Creature-0-1", 1 end
            frame.scripts.OnEvent(frame, "LOOT_OPENED")
            assertEqual(MobHunterDB.learnedDrops["theramore medal"], { ["Theramore Marine"] = 1 })
            assertEqual(mh.MobHunter.GetSuggestions()[1].name, "Theramore Marine") -- now suggested
            GetNumLootItems, GetLootSlotLink, GetLootSourceInfo = nil, nil, nil
            C_QuestLog, MobHunterDB = nil, nil
        end)

        test("the options page has the two quest-target checkboxes", function()
            Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
                RegisterAddOnCategory = function() end }
            local mh = loaded()
            local c = mh.Options.panel.controls
            rawset(c.showSuggestions, "GetChecked", function() return false end)
            c.showSuggestions.scripts.OnClick(c.showSuggestions)
            assertEqual(MobHunterDB.showSuggestions, false)
            rawset(c.autoAdd, "GetChecked", function() return true end)
            c.autoAdd.scripts.OnClick(c.autoAdd)
            assertEqual(MobHunterDB.autoAddSuggestions, true)
            mh.Options.panel.OnDefault()
            assertEqual(MobHunterDB.showSuggestions, true)
            assertEqual(MobHunterDB.autoAddSuggestions, false)
            MobHunterDB, Settings = nil, nil
        end)

        test("stays quiet when nothing matches", function()
            install({ plates = { { unitToken = "nameplate1" } }, names = { nameplate1 = "Wolf" } })
            SlashCmdList["MOBHUNT"]("pillager")
            assertEqual(#sounds, 0)
        end)

        test("in combat the macro change waits until combat ends", function()
            local combat = true
            install()
            InCombatLockdown = function() return combat end
            SlashCmdList["MOBHUNT"]("wolf")
            assertEqual(MobHunterTargetButton.attrs.macrotext, nil)
            combat = false
            -- fire PLAYER_REGEN_ENABLED through the handler the addon registered
            local frame = MobHunterEventFrame
            frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
            assertEqual(MobHunterTargetButton.attrs.macrotext, "/target wolf")
        end)

        test("/mobhunt with no name reports status without erroring", function()
            install()
            SlashCmdList["MOBHUNT"]("")
            assertEqual(#printed, 1)
        end)
    end)
end
