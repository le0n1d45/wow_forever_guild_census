local _, ns = ...

-- Which mobs drop an item a quest asks for. Two sources, neither bundled with MobHunter:
--  1) the QuestieDB addon (global LibQuestieDB), when installed: its quest, item and NPC
--     tables, plus Wowhead's drop rates, which rank the mobs. Every call is guarded, so an
--     older or missing QuestieDB just means no suggestions from it.
--  2) drops learned by looting: when you loot an item a quest still needs from a mob you were
--     targeting, the mob is remembered (MobHunterDB.learnedDrops).
local Drops = {}
ns.Drops = Drops

local CONTRACT = 4 -- the QuestieDB contract these calls were checked against

-- LibQuestieDB, or nil when it isn't there or doesn't support our contract.
function Drops.Bridge()
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" or type(lib.Quest) ~= "table" or type(lib.Item) ~= "table"
        or type(lib.Npc) ~= "table" then
        return nil
    end
    if type(lib.RequireContract) == "function" then
        local ok, supported = pcall(lib.RequireContract, CONTRACT)
        if not ok or not supported then return nil end
    end
    return lib
end

-- Which of a quest's item ids is this log row? By name when the row has one, else by position
-- (the nth item row is the nth item) when the counts agree. ids: item ids in database order.
function Drops.MatchItem(ids, rowName, position, total, nameOf)
    if rowName then
        local wanted = ns.Hunt.Normalize(rowName)
        for _, id in ipairs(ids) do
            if ns.Hunt.Normalize(nameOf(id) or "") == wanted then return id end
        end
    end
    if total == #ids then return ids[position] end
    return nil
end

local rateCache = {}

-- npc id -> drop rate in percent for one item, from Wowhead's table inside QuestieDB. That table
-- is a large Lua chunk held as a string (all items, about 570 KB), so only the one item's block
-- is cut out, and the answer is kept.
function Drops.Rates(lib, itemId)
    if rateCache[itemId] then return rateCache[itemId] end
    local rates = {}
    local ok, support = pcall(function() return lib.Support and lib.Support.Get("QuestieClassicItemDrops") end)
    local data = ok and type(support) == "table" and support.wowheadData
    if type(data) == "string" then
        local block = data:match("\n%s*%[" .. itemId .. "%]%s*=%s*{(.-)\n%s*}")
        if block then
            for npc, rate in block:gmatch("%[(%d+)%]%s*=%s*([%d%.]+)") do rates[tonumber(npc)] = tonumber(rate) end
        end
    end
    rateCache[itemId] = rates
    return rates
end

-- The mobs the database lists for a quest's item row, with rates: { { name, rate } }, and the
-- item's name.
local function fromDatabase(lib, questID, row, position, total)
    local objectives = lib.Quest.objectives(questID)
    local entries = type(objectives) == "table" and objectives[3]
    if type(entries) ~= "table" then return nil end
    local ids = {}
    for _, entry in ipairs(entries) do ids[#ids + 1] = entry[1] end
    local itemId = Drops.MatchItem(ids, row.name, position, total, lib.Item.name)
    if not itemId then return nil end
    local itemName = lib.Item.name(itemId)
    local rates = Drops.Rates(lib, itemId)
    local mobs = {}
    for _, npcId in ipairs(lib.Item.npcDrops(itemId) or {}) do
        local name = lib.Npc.name(npcId)
        if type(name) == "string" and name ~= "" then mobs[#mobs + 1] = { name = name, rate = rates[npcId] } end
    end
    return mobs, itemName
end

local function learned()
    MobHunterDB = MobHunterDB or {}
    MobHunterDB.learnedDrops = MobHunterDB.learnedDrops or {}
    return MobHunterDB.learnedDrops
end

-- itemName -> { { name } } of mobs seen dropping it, most often first.
function Drops.Learned(itemName)
    local seen = learned()[ns.Hunt.Normalize(itemName)]
    local mobs = {}
    for name, count in pairs(seen or {}) do mobs[#mobs + 1] = { name = name, count = count } end
    table.sort(mobs, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return mobs
end

function Drops.Learn(itemName, mobName)
    if type(itemName) ~= "string" or type(mobName) ~= "string" or mobName == "" then return end
    local store = learned()
    local key = ns.Hunt.Normalize(itemName)
    store[key] = store[key] or {}
    store[key][mobName] = (store[key][mobName] or 0) + 1
end

-- The resolver Quests.Suggest takes: the database's mobs for the row, else the learned ones.
function Drops.ForRow(quest, row, position, total)
    local mobs, itemName
    local lib = Drops.Bridge()
    if lib then
        local ok, found, name = pcall(fromDatabase, lib, quest.questID, row, position, total)
        if ok then mobs, itemName = found, name end
    end
    itemName = itemName or row.name
    if (not mobs or #mobs == 0) and itemName then mobs = Drops.Learned(itemName) end
    return mobs, itemName
end
