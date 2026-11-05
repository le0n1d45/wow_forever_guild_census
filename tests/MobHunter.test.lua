-- MobHunter tests. Hunt and Probe are pure Lua; the wiring in MobHunter.lua is loaded against a
-- small permissive fake client (any widget method is a no-op), so these prove the logic and
-- that the file loads and handles a hunt without erroring, not that the real client agrees.
return function()
    local function load(files)
        local ns = {}
        for _, file in ipairs(files) do loadAddonFile(ns, file, "MobHunter") end
        return ns
    end
    local ns = load({ "Hunt.lua", "Probe.lua" })
    local Hunt, Probe = ns.Hunt, ns.Probe

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

    describe("MobHunter Hunt.ParseCommand", function()
        it("reads hunt, stop, status and help", function()
            assertEqual(Hunt.ParseCommand("Defias Pillager"), { action = "hunt", name = "defias pillager" })
            assertEqual(Hunt.ParseCommand("  stop "), { action = "stop" })
            assertEqual(Hunt.ParseCommand("OFF"), { action = "stop" })
            assertEqual(Hunt.ParseCommand(""), { action = "status" })
            assertEqual(Hunt.ParseCommand(nil), { action = "status" })
            assertEqual(Hunt.ParseCommand("help"), { action = "help" })
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

        it("Clusters groups touching points and returns each centre", function()
            local centres = Probe.Clusters({ { 0, 0 }, { 4, 0 }, { 8, 0 }, { 40, 40 }, { 44, 40 } }, 5)
            assertEqual(#centres, 2)
            table.sort(centres, function(a, b) return a[1] < b[1] end)
            assertEqual(centres[1], { 4, 0 })
            assertEqual(centres[2], { 42, 40 })
        end)

        it("Clusters of nothing is nothing", function()
            assertEqual(Probe.Clusters({}, 5), {})
        end)

        -- A fake minimap whose soft cursor "hovers" a tracking dot named `dotName` at (dotX, dotY).
        local function fakeMinimap(dotName, dotX, dotY, radius)
            local m = { cursor = nil, soft = false, softCalls = {} }
            function m:GetWidth() return radius * 2 end
            function m:SetUsingSoftCursor(on) self.soft = on; self.softCalls[#self.softCalls + 1] = on end
            function m:UpdateMouseoverAtPoint(x, y) self.cursor = { x, y } end
            C_TooltipInfo = { GetMinimapMouseover = function()
                local x, y = m.cursor[1], m.cursor[2]
                if (x - dotX) ^ 2 + (y - dotY) ^ 2 <= 16 then
                    return { lines = { { leftText = dotName } } }
                end
            end }
            return m
        end

        it("Find locates a tracked dot by name and reports its offset from the centre", function()
            local m = fakeMinimap("Defias Pillager", 70, 80, 70) -- 0 px right of centre, 10 up
            local centres = Probe.Find(m, "pillager", 2)
            assertEqual(#centres, 1)
            assert(math.abs(centres[1][1] - 0) < 1.5, "dx " .. centres[1][1])
            assert(math.abs(centres[1][2] - 10) < 1.5, "dy " .. centres[1][2])
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
            for _, file in ipairs({ "Hunt.lua", "Probe.lua", "MobHunter.lua" }) do loadAddonFile(mh, file, "MobHunter") end
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

        test("once a mob is seen the button targets its nameplate, not the typed name", function()
            install({ plates = { { unitToken = "nameplate2" } }, names = { nameplate2 = "Defias Pillager" } })
            SlashCmdList["MOBHUNT"]("pillager")
            assertEqual(MobHunterTargetButton.attrs.macrotext, "/target nameplate2")
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
            rawset(Minimap, "SetUsingSoftCursor", function() end)
            rawset(Minimap, "UpdateMouseoverAtPoint", function(_, x, y) cursor = { x, y } end)
            C_TooltipInfo = { GetMinimapMouseover = function()
                if dotUp and (cursor[1] - 80) ^ 2 + (cursor[2] - 90) ^ 2 <= 16 then
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
            SlashCmdList["MOBHUNT"]("pillager")
            assertEqual(#minimapChildren, 1)
            assertEqual(minimapChildren[1].shown, true)
            dotUp = false
            mh.MobHunter.Scan()
            assertEqual(minimapChildren[1].shown, false)
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
