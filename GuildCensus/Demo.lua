local _, ns = ...

local Demo = {}
ns.Demo = Demo

-- Guilds on Forever can reach about 1000 members, so the default demo roster is big
-- enough to exercise the Finder's row cap as well as every filter.
Demo.DEFAULT_COUNT = 500

local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

-- The roster is built from one stream per role, each spread evenly across levels
-- 5-60, so every dungeon level range has tanks, healers and DPS to find. The note
-- words match the default keyword lists, and each stream cycles through profession
-- combinations and online/offline independently, so every profession and the
-- online-only filter have results across roles and levels.
local STREAMS = {
    { role = "tank", share = 0.25, classes = {
        { "WARRIOR", { "Tank", "Prot" } }, { "PALADIN", { "Prot", "Tank" } }, { "DRUID", { "Bear", "Tank" } },
    } },
    { role = "healer", share = 0.25, classes = {
        { "PRIEST", { "Healer", "Disc" } }, { "PALADIN", { "Holy", "Healer" } },
        { "DRUID", { "Resto", "Healer" } }, { "SHAMAN", { "Resto", "Healer" } },
    } },
    { role = "dps", share = 0.5, classes = {
        { "WARRIOR", { "Arms", "Fury" } }, { "PALADIN", { "Ret", "DPS" } }, { "HUNTER", { "", "DPS" } },
        { "ROGUE", { "", "dps" } }, { "PRIEST", { "Shadow", "DPS" } }, { "SHAMAN", { "Enh", "Ele" } },
        { "MAGE", { "", "DPS" } }, { "WARLOCK", { "", "dps" } }, { "DRUID", { "Feral", "Balance" } },
    } },
}

-- Two spellings per profession, both covered by the default keywords.
local PROFESSION_WORDS = {
    mining = { "Mining", "miner" }, blacksmith = { "BS", "Blacksmith" },
    herbalism = { "Herbalism", "herb" }, alchemy = { "Alchemy", "alch" },
    skinning = { "Skinning", "skinner" }, leatherworking = { "LW", "Leatherworker" },
    enchanting = { "Ench", "Enchanting" }, engineering = { "Engi", "Engineering" },
    tailor = { "Tailor", "Tailoring" },
}

-- 13 combinations (coprime with the step used to walk them) so every profession
-- appears in every stream; some members have none.
local PROFESSION_COMBOS = {
    {}, { "mining" }, { "mining", "blacksmith" }, { "herbalism", "alchemy" },
    { "skinning", "leatherworking" }, { "enchanting", "tailor" }, { "engineering", "mining" },
    { "alchemy" }, { "skinning", "herbalism" }, {}, { "leatherworking", "mining" },
    { "tailor", "herbalism" }, { "enchanting", "engineering" },
}

local SEPARATORS = { ", ", " / ", " - ", " " }

-- How a skill level is written after a profession ("LW 260", "Mining (300)", ...).
local SKILL_FORMATS = { " %d", " (%d)", ": %d", "-%d" }

-- Members given deliberately contradictory notes so the Logs tab has entries
-- (roughly one member in 25). A class means "make them this class".
local CONFLICT_CASES = {
    { note = "Main, alt of Bob" },
    { note = "Mining Skinning Herbalism dps" },
    { classFile = "MAGE", note = "healer" },
    { classFile = "WARRIOR", note = "healer" },
    { classFile = "PRIEST", note = "tank" },
    { note = "main / alt tank" },
    { note = "LW Mining Alch heals" },
    { classFile = "ROGUE", note = "tank" },
}

-- Members who can legitimately do all three roles (not a conflict).
local ALL_ROLES_NOTES = { PALADIN = "tank / heal / dps", DRUID = "Bear, Resto, Feral" }

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

-- Past the curated names, combine syllables (40 x 30 = 1200 more, enough for a
-- 1000-member guild) using a stride coprime with 1200 so they come out in a
-- scrambled but unique order.
local PREFIXES = {
    "Ael", "Bran", "Cor", "Dun", "Eld", "Fen", "Gar", "Hal", "Isel", "Jor",
    "Kel", "Lor", "Mor", "Nor", "Oro", "Pel", "Quin", "Ros", "Syl", "Thor",
    "Ul", "Val", "Wyn", "Xan", "Yor", "Zan", "Ash", "Bel", "Cal", "Dar",
    "Eri", "Fal", "Gor", "Hel", "Ith", "Jar", "Kor", "Lys", "Mal", "Nym",
}
local SUFFIXES = {
    "dor", "wyn", "ric", "ia", "mar", "thas", "len", "vik", "dra", "rin",
    "gard", "nis", "ros", "bar", "wen", "dil", "kar", "mond", "sen", "tor",
    "ven", "lyn", "grim", "fel", "dan", "ther", "mus", "ra", "wick", "bane",
}
local NAME_STRIDE = 37

local function makeNamer()
    local used = {}
    for _, name in ipairs(NAMES) do used[name] = true end
    local combos = #PREFIXES * #SUFFIXES

    return function(i)
        if i <= #NAMES then return NAMES[i] end
        local j = i - #NAMES
        local index = (j * NAME_STRIDE) % combos
        for _ = 1, combos do
            local name = PREFIXES[math.floor(index / #SUFFIXES) + 1] .. SUFFIXES[index % #SUFFIXES + 1]
            if not used[name] then
                used[name] = true
                return name
            end
            index = (index + 1) % combos
        end
        return "Member" .. i -- more members than distinct names: still unique
    end
end

local function buildStream(spec, streamIndex, count, rand, members)
    for k = 1, count do
        local classEntry = spec.classes[rand(#spec.classes)]
        local words = classEntry[2]
        local level = k == count and 60 or 5 + math.floor((k - 1) * 56 / count)

        local parts = {}
        local roleWord = words[k % #words + 1]
        if roleWord ~= "" then parts[#parts + 1] = roleWord end
        local combo = PROFESSION_COMBOS[(k * 5 + streamIndex * 3) % #PROFESSION_COMBOS + 1]
        for _, profession in ipairs(combo) do
            local spellings = PROFESSION_WORDS[profession]
            local text = spellings[(k + #parts) % #spellings + 1]
            -- About two in three members write their skill, roughly tracking their level.
            if (k + #parts) % 3 ~= 0 then
                local skill = math.min(300, math.max(1, math.floor(level * 4.6 + (k * 13 + #parts * 29) % 41)))
                text = text .. string.format(SKILL_FORMATS[(k + #parts) % #SKILL_FORMATS + 1], skill)
            end
            parts[#parts + 1] = text
        end
        local note = table.concat(parts, SEPARATORS[k % #SEPARATORS + 1])

        -- Declared mains and alts, so the alts/mains settings have something to act on.
        if k % 8 == 0 then
            note = note == "" and "Main" or ("Main, " .. note)
        elseif k % 8 == 4 then
            note = note == "" and "alt of Bob" or (note .. ", alt of Bob")
        end

        members[#members + 1] = {
            level = level,
            classFile = classEntry[1],
            className = CLASS_NAMES[classEntry[1]],
            note = note,
            online = (k + streamIndex) % 2 == 0,
        }
    end
end

-- A deterministic fake roster (Park-Miller LCG), so the same data renders every time.
-- count defaults to Demo.DEFAULT_COUNT.
function Demo.Generate(count, seed)
    count = count or Demo.DEFAULT_COUNT
    local state = seed or 12345
    local function rand(n)
        state = (state * 16807) % 2147483647
        return state % n + 1
    end

    local members = {}
    local remaining = count
    for streamIndex, spec in ipairs(STREAMS) do
        local streamCount = streamIndex == #STREAMS and remaining or math.floor(count * spec.share + 0.5)
        remaining = remaining - streamCount
        buildStream(spec, streamIndex, streamCount, rand, members)
    end

    -- Fisher-Yates, so the list isn't grouped by role and level.
    for i = #members, 2, -1 do
        local j = rand(i)
        members[i], members[j] = members[j], members[i]
    end

    local nameFor = makeNamer()
    for i, member in ipairs(members) do
        member.name = nameFor(i)

        if i % 25 == 7 then
            local case = CONFLICT_CASES[math.floor(i / 25) % #CONFLICT_CASES + 1]
            member.note = case.note
            if case.classFile then
                member.classFile, member.className = case.classFile, CLASS_NAMES[case.classFile]
            end
        elseif i % 40 == 11 and ALL_ROLES_NOTES[member.classFile] then
            member.note = ALL_ROLES_NOTES[member.classFile]
        end
    end
    return members
end
