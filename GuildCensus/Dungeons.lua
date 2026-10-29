local _, ns = ...

local Dungeons = {}
ns.Dungeons = Dungeons

-- Dungeon presets for the Finder: selecting one fills in its level range.
--
-- PROVISIONAL: these are classic-era recommended ranges and are NOT correct for
-- WoW Forever. Forever's beta client data lists ~31 dungeons, including new ones
-- (Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran,
-- ...) and different levels (e.g. Deadmines 16, Wailing Caverns 17), and guides
-- disagree on the ranges. Replace this table with Forever's dungeon list and level
-- ranges (see bead wow_forever_guild_census-3mm.4). The Finder and the tests read
-- it purely as data, so only this table needs to change. Keep it sorted by
-- minLevel, then name.
Dungeons.LIST = {
    { key = "deadmines", name = "The Deadmines", minLevel = 10, maxLevel = 20 },
    { key = "ragefire-chasm", name = "Ragefire Chasm", minLevel = 13, maxLevel = 18 },
    { key = "wailing-caverns", name = "Wailing Caverns", minLevel = 15, maxLevel = 25 },
    { key = "shadowfang-keep", name = "Shadowfang Keep", minLevel = 18, maxLevel = 25 },
    { key = "blackfathom-deeps", name = "Blackfathom Deeps", minLevel = 20, maxLevel = 30 },
    { key = "stockade", name = "The Stockade", minLevel = 22, maxLevel = 30 },
    { key = "gnomeregan", name = "Gnomeregan", minLevel = 24, maxLevel = 34 },
    { key = "razorfen-kraul", name = "Razorfen Kraul", minLevel = 25, maxLevel = 35 },
    { key = "scarlet-monastery", name = "Scarlet Monastery", minLevel = 28, maxLevel = 38 },
    { key = "razorfen-downs", name = "Razorfen Downs", minLevel = 35, maxLevel = 45 },
    { key = "uldaman", name = "Uldaman", minLevel = 35, maxLevel = 45 },
    { key = "zulfarrak", name = "Zul'Farrak", minLevel = 42, maxLevel = 50 },
    { key = "maraudon", name = "Maraudon", minLevel = 45, maxLevel = 55 },
    { key = "sunken-temple", name = "The Temple of Atal'Hakkar", minLevel = 50, maxLevel = 60 },
    { key = "blackrock-depths", name = "Blackrock Depths", minLevel = 52, maxLevel = 60 },
    { key = "dire-maul", name = "Dire Maul", minLevel = 55, maxLevel = 60 },
    { key = "lower-blackrock-spire", name = "Lower Blackrock Spire", minLevel = 55, maxLevel = 60 },
    { key = "scholomance", name = "Scholomance", minLevel = 58, maxLevel = 60 },
    { key = "stratholme", name = "Stratholme", minLevel = 58, maxLevel = 60 },
    { key = "upper-blackrock-spire", name = "Upper Blackrock Spire", minLevel = 58, maxLevel = 60 },
}

function Dungeons.Get(key)
    for _, dungeon in ipairs(Dungeons.LIST) do
        if dungeon.key == key then return dungeon end
    end
    return nil
end
