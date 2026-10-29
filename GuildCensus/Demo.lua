local _, ns = ...

local Demo = {}
ns.Demo = Demo

local CLASSES = {
    { "WARRIOR", "Warrior" }, { "PALADIN", "Paladin" }, { "HUNTER", "Hunter" },
    { "ROGUE", "Rogue" }, { "PRIEST", "Priest" }, { "SHAMAN", "Shaman" },
    { "MAGE", "Mage" }, { "WARLOCK", "Warlock" }, { "DRUID", "Druid" },
}

local NOTES = {
    "", "", "", "Tank", "Healer", "DPS", "dps",
    "Tank - Blacksmithing/Mining", "Healer, Alchemy + Herbalism",
    "DPS | Engineering", "LW / Skinning dps", "Tailoring, Enchanting",
    "alt of Bob", "Main", "main - Healer, Alchemy", "Main tank, Mining",
    "Main, alt of Bob", "Mining Skinning Herbalism dps", "healer", "Healer/DPS Cooking", "tank Fishing", "Jewelcrafting dps",
}

local NAMES = {
    "Thalindra", "Gorrik", "Mirelle", "Brannoc", "Sylvaris", "Durgan", "Elowen", "Kaldor",
    "Nyssa", "Torvald", "Ilyana", "Hargrim", "Vesperia", "Rurik", "Aelwyn", "Bromm",
    "Seraphine", "Garrok", "Lunaria", "Dunstan", "Morwenna", "Fenrick", "Calista", "Orsin",
    "Yvaine", "Thrak", "Rosalind", "Baldric", "Zephyra", "Grimsby", "Anwen", "Korvus",
    "Tamsin", "Haldor", "Isolde", "Brogan", "Lysandra", "Ulfric", "Marisol", "Dagny",
    "Eldric", "Fiora", "Gundar", "Halwyn", "Ravenna", "Jorund", "Kestrel", "Leofric",
    "Maelis", "Norbert", "Ophira", "Perrin", "Quillon", "Rhosyn", "Sorrel", "Tobias",
    "Ursa", "Valdis", "Wynne", "Xander", "Ysolde", "Zorin", "Alaric", "Brielle",
    "Cassian", "Delphine", "Evander", "Freya", "Gideon", "Helga", "Ignatius", "Jocasta",
    "Kellan", "Lenore", "Magnus", "Nerissa", "Osric", "Petra", "Quentin", "Rowena",
}

-- Deterministic fake roster so the same data renders every time (Park-Miller LCG).
function Demo.Generate(count, seed)
    local state = seed or 12345
    local function rand(n)
        state = (state * 16807) % 2147483647
        return state % n + 1
    end

    local members = {}
    for i = 1, count do
        local class = CLASSES[rand(#CLASSES)]
        members[i] = {
            -- Unique even when asked for more members than there are names.
            name = i <= #NAMES and NAMES[i] or (NAMES[(i - 1) % #NAMES + 1] .. i),
            level = math.max(1, math.ceil(60 * (rand(1000) / 1000) ^ 0.6)),
            classFile = class[1],
            className = class[2],
            note = NOTES[rand(#NOTES)],
        }
    end
    return members
end
