-- Known and Engine: which recipes count under each filter, and the ranking.
return function()
    local function load()
        local ns = { Data = { Items = {}, Trainers = {}, Tailoring = { skillLine = 197, recipes = {} } } }
        for _, file in ipairs({ "Prices.lua", "Calculator.lua", "Known.lua", "Engine.lua" }) do
            loadAddonFile(ns, file, "CrafterArbitrage")
        end
        return ns
    end

    local knownSpells, skills
    local function game(faction)
        knownSpells, skills = {}, {}
        IsPlayerSpell = function(id) return knownSpells[id] or false end
        UnitFactionGroup = function() return faction or "Alliance" end
        UnitClass = function() return "Mage", "MAGE", 8 end
        C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function(line) return { skillLevel = skills[line] or 0 } end }
    end

    -- Three recipes make an item (vendor 100) from cloth (10 copper): known, trainer-taught, and book-only.
    local function setup(faction)
        game(faction)
        local ns = load()
        ns.Data.Items[10] = { sell = 1, buy = 1 }
        ns.Data.Items[20] = { sell = 100 }
        ns.Data.Items[21] = { sell = 300 }
        ns.Data.Items[22] = { sell = 200 }
        ns.Data.Trainers[1] = { "Eldrin", "Tailor", "A" }
        ns.Data.Trainers[2] = { "Horde Guy", "Tailor", "H" }
        local r = ns.Data.Tailoring.recipes
        r[100] = { out = { 20, 1 }, r = { { 10, 1 } } } -- known
        r[101] = { out = { 21, 1 }, r = { { 10, 1 } }, train = { 50, 450 }, trainers = { 1 } } -- Alliance trainer, skill 50
        r[102] = { out = { 22, 1 }, r = { { 10, 1 } }, recipeItems = { { 5000 } } } -- book only
        ns.Prices.Build({ { 10, 100, 1000 } }, 1)
        knownSpells[100] = true
        skills[197] = 60
        return ns
    end

    local function spells(results)
        local out = {}
        for _, r in ipairs(results) do out[#out + 1] = r.spell end
        return out
    end

    describe("Known.Status", function()
        it("tells known, trainer and other recipes apart", function()
            local ns = setup()
            local r = ns.Data.Tailoring.recipes
            assertEqual(ns.Known.Status(197, 100, r[100]), "known")
            assertEqual(ns.Known.Status(197, 101, r[101]), "trainer")
            assertEqual(ns.Known.Status(197, 102, r[102]), "other")
        end)

        it("needs enough skill for the trainer's recipe", function()
            local ns = setup()
            skills[197] = 49
            assertEqual(ns.Known.Status(197, 101, ns.Data.Tailoring.recipes[101]), "other")
            skills[197] = nil
            assertEqual(ns.Known.Status(197, 101, ns.Data.Tailoring.recipes[101]), "other")
        end)

        it("ignores trainers of the other faction", function()
            local ns = setup("Horde")
            assertEqual(ns.Known.Status(197, 101, ns.Data.Tailoring.recipes[101]), "other")
            ns.Data.Tailoring.recipes[101].trainers = { 1, 2 }
            assertEqual(ns.Known.Status(197, 101, ns.Data.Tailoring.recipes[101]), "trainer")
        end)

        it("skips recipes restricted to another class", function()
            local ns = setup()
            ns.Data.Tailoring.recipes[100].classMask = 1 -- warriors only
            assertEqual(ns.Known.Status(197, 100, ns.Data.Tailoring.recipes[100]), "other")
            ns.Data.Tailoring.recipes[100].classMask = 128 -- mages (class 8)
            assertEqual(ns.Known.Status(197, 100, ns.Data.Tailoring.recipes[100]), "known")
        end)

        it("reads a profession's skill from the classic skill list when the modern API is absent", function()
            local ns = setup()
            C_TradeSkillUI = nil
            GetSpellInfo = function(id) return id == 3908 and "Tailoring" or nil end
            GetNumSkillLines = function() return 2 end
            GetSkillLineInfo = function(i)
                if i == 1 then return "Professions", true end
                return "Tailoring", false, nil, 75
            end
            assertEqual(ns.Known.SkillLevel(197), 75)
            GetSpellInfo, GetNumSkillLines, GetSkillLineInfo = nil, nil, nil
        end)
    end)

    describe("Engine.Run", function()
        it("lists known recipes only under the known filter", function()
            local ns = setup()
            assertEqual(spells(ns.Engine.Run({ filter = "known" })), { 100 })
        end)

        it("adds trainer recipes under the learnable filter, best profit first", function()
            local ns = setup()
            assertEqual(spells(ns.Engine.Run({ filter = "learnable" })), { 101, 100 })
        end)

        it("lists every recipe under the all filter", function()
            local ns = setup()
            assertEqual(spells(ns.Engine.Run({ filter = "all" })), { 101, 102, 100 })
        end)

        it("drops results below the minimum profit", function()
            local ns = setup()
            -- 100 cloth is listed, so 100 crafts: 29,000 (item 21), 19,000 (item 22) and 9,000 (item 20)
            local results = ns.Engine.Run({ filter = "all", minProfit = 15000 })
            assertEqual(spells(results), { 101, 102 })
            results = ns.Engine.Run({ filter = "all", minProfit = 10 ^ 9 })
            assertEqual(#results, 0)
        end)

        it("carries the evaluation and status for the UI", function()
            local ns = setup()
            local first = ns.Engine.Run({ filter = "all" })[1]
            assertEqual(first.status, "trainer")
            assertEqual(first.prof, "Tailoring")
            assert(first.eval.crafts > 0 and first.eval.profit > 0)
        end)

        it("steps through the work in pieces", function()
            local ns = setup()
            local job = ns.Engine.NewJob({ filter = "all" })
            local steps = 0
            while not job:Step() do steps = steps + 1 end
            assertEqual(#job.results, 3)
        end)

        it("only lets a craft use an intermediate the filter allows", function()
            local ns = setup()
            local r = ns.Data.Tailoring.recipes
            ns.Data.Items[30] = { sell = 1 }
            ns.Data.Items[31] = { sell = 5000 }
            r[200] = { out = { 30, 1 }, r = { { 10, 1 } }, recipeItems = { { 5001 } } } -- intermediate: book only
            r[201] = { out = { 31, 1 }, r = { { 30, 1 } } } -- known recipe needing the intermediate
            knownSpells[201] = true
            ns.Prices.Build({ { 10, 100, 1000 }, { 30, 100, 1000000 } }, 1) -- the intermediate costs 10,000 to buy
            assertEqual(#ns.Engine.Run({ filter = "known" }), 1) -- only 100: 201 cannot get its intermediate
            local all = spells(ns.Engine.Run({ filter = "all" }))
            local has201 = false
            for _, s in ipairs(all) do has201 = has201 or s == 201 end
            assert(has201, "recipe 201 should pay when it may craft the intermediate itself")
        end)
    end)
end
