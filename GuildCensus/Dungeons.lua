local _, ns = ...

local Dungeons = {}
ns.Dungeons = Dungeons

-- Dungeon presets for the Finder: selecting one fills in its level range.
--
-- Source: Wowhead's "Dungeons Overview for Forever" guide (updated 2026-09-23, patch
-- 1.60.1, beta): the table of new Forever dungeons plus its level-range chart. Wowhead
-- notes the guide may change before release. Scarlet Monastery and Maraudon are listed
-- per wing, as the chart does.
--
-- INCOMPLETE: the saved copy of the chart was clipped at the right edge, so the
-- dungeons above roughly level 50 are missing (Sunken Temple, Blackrock Depths,
-- Blackrock Spire, Dire Maul, Stratholme, Scholomance, ...). Add them here once their
-- ranges are known (see the follow-up bead). The Finder and the tests read this table
-- purely as data. Keep it sorted by minLevel, then name.
Dungeons.LIST = {
    { key = "ragefire-chasm", name = "Ragefire Chasm", minLevel = 13, maxLevel = 18 },
    { key = "hall-of-thanes", name = "The Hall of Thanes", minLevel = 13, maxLevel = 18 },
    { key = "ruins-of-lordaeron", name = "Ruins of Lordaeron", minLevel = 15, maxLevel = 20 },
    { key = "wailing-caverns", name = "Wailing Caverns", minLevel = 15, maxLevel = 25 },
    { key = "deadmines", name = "The Deadmines", minLevel = 18, maxLevel = 23 },
    { key = "shadowfang-keep", name = "Shadowfang Keep", minLevel = 22, maxLevel = 30 },
    { key = "stockade", name = "The Stockade", minLevel = 22, maxLevel = 30 },
    { key = "blackfathom-deeps", name = "Blackfathom Deeps", minLevel = 24, maxLevel = 32 },
    { key = "excavation-site-wetlands", name = "Excavation Site: Wetlands", minLevel = 24, maxLevel = 29 },
    { key = "city-of-dalaran", name = "City of Dalaran", minLevel = 28, maxLevel = 33 },
    { key = "scarlet-monastery-graveyard", name = "Scarlet Monastery: Graveyard", minLevel = 28, maxLevel = 38 },
    { key = "gnomeregan", name = "Gnomeregan", minLevel = 29, maxLevel = 38 },
    { key = "scarlet-monastery-library", name = "Scarlet Monastery: Library", minLevel = 29, maxLevel = 39 },
    { key = "razorfen-kraul", name = "Razorfen Kraul", minLevel = 30, maxLevel = 40 },
    { key = "scarlet-monastery-armory", name = "Scarlet Monastery: Armory", minLevel = 32, maxLevel = 42 },
    { key = "scarlet-monastery-cathedral", name = "Scarlet Monastery: Cathedral", minLevel = 35, maxLevel = 45 },
    { key = "drowned-city", name = "The Drowned City", minLevel = 35, maxLevel = 40 },
    { key = "krol-dok-stronghold", name = "Krol'dok Stronghold", minLevel = 40, maxLevel = 45 },
    { key = "razorfen-downs", name = "Razorfen Downs", minLevel = 40, maxLevel = 50 },
    { key = "uldaman", name = "Uldaman", minLevel = 42, maxLevel = 52 },
    { key = "zulfarrak", name = "Zul'Farrak", minLevel = 44, maxLevel = 54 },
    { key = "maraudon-foulspore-cavern", name = "Maraudon: Foulspore Cavern", minLevel = 45, maxLevel = 53 },
    { key = "maraudon-wicked-grotto", name = "Maraudon: Wicked Grotto", minLevel = 45, maxLevel = 53 },
    { key = "alcaz-prison", name = "Alcaz Prison", minLevel = 48, maxLevel = 53 },
    { key = "maraudon-earth-song-falls", name = "Maraudon: Earth Song Falls", minLevel = 48, maxLevel = 57 },
    { key = "blackmaw-hold", name = "Blackmaw Hold", minLevel = 55, maxLevel = 60 },
    { key = "shapers-terrace", name = "Shaper's Terrace", minLevel = 58, maxLevel = 60 },
}

function Dungeons.Get(key)
    for _, dungeon in ipairs(Dungeons.LIST) do
        if dungeon.key == key then return dungeon end
    end
    return nil
end
