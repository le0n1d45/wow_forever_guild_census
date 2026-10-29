return function(ns)
    local Config = ns.Config

    describe("Config", function()
        it("defaults match the specified keyword lists", function()
            local d = Config.Defaults()
            assertEqual(d.includeAlts, true)
            assertEqual(d.onlyMains, false)
            assertEqual(d.identity, { main = "main, mains", alt = "alt, alts" })
            assertEqual(d.roles.tank, "tank, tanks, tanking, bear, prot, protection")
            assertEqual(d.roles.healer, "heal, heals, healer, healers, healing, resto, restoration, holy, disc, discipline")
            assertEqual(d.professions.leatherworking, "lw, leatherworking, leatherworker")
            assertEqual(d.professions.blacksmith,
                "bs, blacksmith, blacksmithing, armorsmith, armorsmithing, weaponsmith, weaponsmithing")
            assertEqual(d.professions.alchemy, "alch, alchemy, alchemist")
        end)

        it("Init fills missing values but keeps user edits, including empty boxes", function()
            local db = { settings = { includeAlts = false, roles = { tank = "", healer = "mender" } } }
            local s = Config.Init(db)
            assertEqual(s.includeAlts, false)
            assertEqual(s.roles.tank, "")
            assertEqual(s.roles.healer, "mender")
            assertEqual(s.roles.dps, Config.Defaults().roles.dps)
            assertEqual(s.professions.mining, "mining, miner")
            assertEqual(db.settings, s)
        end)

        it("Init creates settings in an empty DB", function()
            local db = {}
            Config.Init(db)
            assertEqual(db.settings, Config.Defaults())
        end)

        it("Init upgrades a saved value that still equals an old default", function()
            local db = { settings = { professions = { leatherworking = "lw, leatherworker" } } }
            local s = Config.Init(db)
            assertEqual(s.professions.leatherworking, "lw, leatherworking, leatherworker")
        end)

        it("Init leaves an edited value alone, even one that merely resembles the old default", function()
            for _, edited in ipairs({ "lw", "lw, leatherworker, hides", "", "LW, leatherworker" }) do
                local db = { settings = { professions = { leatherworking = edited } } }
                assertEqual(Config.Init(db).professions.leatherworking, edited)
            end
        end)

        it("Init upgrades every untouched earlier default to the current one", function()
            for group, defs in pairs({ identity = Config.IDENTITY, roles = Config.ROLES, professions = Config.PROFESSIONS }) do
                for _, def in ipairs(defs) do
                    for _, old in ipairs(def.replaces or {}) do
                        local db = { settings = { [group] = { [def.key] = old } } }
                        assertEqual(Config.Init(db)[group][def.key], def.default)
                    end
                end
            end
        end)

        it("Init leaves edited versions of the other defaults alone", function()
            for group, defs in pairs({ identity = Config.IDENTITY, roles = Config.ROLES, professions = Config.PROFESSIONS }) do
                for _, def in ipairs(defs) do
                    local edited = def.default .. ", mine"
                    local db = { settings = { [group] = { [def.key] = edited } } }
                    assertEqual(Config.Init(db)[group][def.key], edited)
                end
            end
        end)

        it("Init is idempotent once upgraded", function()
            local db = { settings = { professions = { leatherworking = "lw, leatherworker" } } }
            Config.Init(db)
            assertEqual(Config.Init(db).professions.leatherworking, "lw, leatherworking, leatherworker")
        end)

        it("Reset restores defaults in place", function()
            local s = Config.Defaults()
            s.includeAlts, s.onlyMains, s.roles.tank, s.identity.alt = false, true, "x", "y"
            Config.Reset(s)
            assertEqual(s, Config.Defaults())
        end)
    end)
end
