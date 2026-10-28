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
    "alt of Bob", "Healer/DPS Cooking", "tank Fishing", "Jewelcrafting dps",
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
            level = math.max(1, math.ceil(60 * (rand(1000) / 1000) ^ 0.6)),
            classFile = class[1],
            className = class[2],
            note = NOTES[rand(#NOTES)],
        }
    end
    return members
end
