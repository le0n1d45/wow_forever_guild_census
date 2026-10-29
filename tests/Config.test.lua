return function(ns)
    local Config = ns.Config

    describe("Config", function()
        it("defaults match the specified keyword lists", function()
            local d = Config.Defaults()
            assertEqual(d.includeAlts, true)
            assertEqual(d.onlyMains, false)
            assertEqual(d.identity, { main = "main", alt = "alt" })
            assertEqual(d.roles.tank, "tank,bear,prot")
            assertEqual(d.roles.healer, "heal,resto,holy,disc")
            assertEqual(d.professions.leatherworking, "lw, leatherworker")
            assertEqual(d.professions.blacksmith, "bs, blacksmith, armorsmith, weaponsmith")
            assertEqual(d.professions.alchemy, "alch, alchemy")
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

        it("Reset restores defaults in place", function()
            local s = Config.Defaults()
            s.includeAlts, s.onlyMains, s.roles.tank, s.identity.alt = false, true, "x", "y"
            Config.Reset(s)
            assertEqual(s, Config.Defaults())
        end)
    end)
end
