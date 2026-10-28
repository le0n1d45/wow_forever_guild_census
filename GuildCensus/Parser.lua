local _, ns = ...

local Parser = {}
ns.Parser = Parser

-- Keyword -> canonical name. Notes are tokenised on non-letters, so every
-- key must be a single lowercase word.
local ROLE_KEYWORDS = {
    tank = "tank", tanks = "tank", tanking = "tank", mt = "tank", ot = "tank",
    heal = "healer", heals = "healer", healer = "healer", healers = "healer", healing = "healer",
    dps = "dps", dd = "dps", damage = "dps",
}

local PROFESSION_KEYWORDS = {
    alchemy = "Alchemy", alch = "Alchemy", alchemist = "Alchemy",
    blacksmithing = "Blacksmithing", blacksmith = "Blacksmithing", bs = "Blacksmithing",
    enchanting = "Enchanting", enchanter = "Enchanting", ench = "Enchanting",
    engineering = "Engineering", engineer = "Engineering", eng = "Engineering", engi = "Engineering",
    herbalism = "Herbalism", herbalist = "Herbalism", herb = "Herbalism", herbs = "Herbalism",
    leatherworking = "Leatherworking", leatherworker = "Leatherworking", lw = "Leatherworking",
    mining = "Mining", miner = "Mining",
    skinning = "Skinning", skinner = "Skinning",
    tailoring = "Tailoring", tailor = "Tailoring",
    jewelcrafting = "Jewelcrafting", jewelcrafter = "Jewelcrafting", jc = "Jewelcrafting",
    inscription = "Inscription", scribe = "Inscription",
    cooking = "Cooking", cook = "Cooking",
    fishing = "Fishing", fisher = "Fishing",
}

Parser.ROLES = { "tank", "healer", "dps" }

local function lookup(note, keywords)
    local found, seen = {}, {}
    if type(note) ~= "string" then return found end
    for word in string.gmatch(string.lower(note), "%a+") do
        local canonical = keywords[word]
        if canonical and not seen[canonical] then
            seen[canonical] = true
            found[#found + 1] = canonical
        end
    end
    return found
end

-- Returns a list of distinct roles ("tank", "healer", "dps") found in a note.
function Parser.ParseRoles(note)
    return lookup(note, ROLE_KEYWORDS)
end

-- Returns a list of distinct profession names found in a note.
function Parser.ParseProfessions(note)
    return lookup(note, PROFESSION_KEYWORDS)
end
