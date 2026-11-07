local _, ns = ...

-- Reads the quest log and turns it into hunt suggestions: the mobs named in "kill X" objectives,
-- and (through ns.Drops, when it knows them) the mobs that drop an item a quest still needs.
-- Parsing and ranking are plain Lua so they run headlessly in tests; only Quests.Read touches
-- the client.
local Quests = {}
ns.Quests = Quests

-- Mobs that drop a needed item are listed best first. Below this drop rate (percent) a mob is
-- left out, unless it is the best one, so rare extra sources (Raptor Horns also drop from two
-- rare raptors at 1% and 7%) don't crowd the list.
local MIN_RATE = 10
Quests.MIN_RATE = MIN_RATE

-- The client's own row formats, which put the count first and use positional arguments:
-- QUEST_MONSTERS_KILLED = "%2$d/%3$d %1$s slain", QUEST_ITEMS_NEEDED = "%2$d/%3$d %1$s".
local DEFAULT_KILLED = "%2$d/%3$d %1$s slain"
local DEFAULT_ITEMS = "%2$d/%3$d %1$s"

local function trim(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    return text
end

-- A format string ("%2$d/%3$d %1$s slain", or the plain "%s: %d/%d") becomes a function that
-- takes a row's text and returns { [argument number] = captured text }, or nil if the text
-- doesn't fit. Reading the argument order out of the format keeps other locales working.
function Quests.CompileFormat(format)
    if type(format) ~= "string" then return nil end
    local pattern, order, nextArg = { "^" }, {}, 1
    local i = 1
    while i <= #format do
        local _, stop, num, spec = format:find("^%%(%d+)%$([sd])", i)
        if not stop then
            _, stop, spec = format:find("^%%([sd])", i)
            if stop then num, nextArg = nextArg, nextArg + 1 end
        end
        if stop then
            pattern[#pattern + 1] = spec == "s" and "(.-)" or "(%d+)"
            order[#order + 1] = tonumber(num)
            i = stop + 1
        else
            local c = format:sub(i, i)
            if c == "%" and format:sub(i + 1, i + 1) == "%" then
                pattern[#pattern + 1] = "%%"
                i = i + 2
            else
                pattern[#pattern + 1] = c:match("%w") and c or ("%" .. c)
                i = i + 1
            end
        end
    end
    pattern[#pattern + 1] = "$"
    local compiled = table.concat(pattern)
    return function(text)
        if type(text) ~= "string" then return nil end
        local captures = { text:match(compiled) }
        if captures[1] == nil then return nil end
        local out = {}
        for k, arg in ipairs(order) do out[arg] = captures[k] end
        return out
    end
end

local parsers = {}
local function parserFor(kind)
    if not parsers[kind] then
        local format
        if kind == "monster" then
            format = _G.QUEST_MONSTERS_KILLED or DEFAULT_KILLED
        else
            format = _G.QUEST_ITEMS_NEEDED or DEFAULT_ITEMS
        end
        parsers[kind] = Quests.CompileFormat(format) or false
    end
    return parsers[kind]
end

-- One row of C_QuestLog.GetQuestObjectives -> { type, name, have, need, finished }. The name
-- comes from the row's text and is nil when the text has none: an item that isn't cached yet
-- reads "0/15  ". Counts and the finished flag come from the row's own fields.
function Quests.ParseRow(row)
    local parsed = { type = row.type, have = row.numFulfilled or 0, need = row.numRequired or 0,
        finished = row.finished and true or false }
    if row.type == "monster" or row.type == "item" then
        local parse = parserFor(row.type)
        local parts = parse and parse(row.text)
        parsed.name = trim(parts and parts[1])
    end
    return parsed
end

-- Every visible quest in the log with its parsed rows: { { questID, title, objectives } }.
function Quests.Read()
    local list = {}
    local log = C_QuestLog
    if not (log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives) then return list end
    for i = 1, log.GetNumQuestLogEntries() do
        local info = log.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID then
            local objectives = {}
            for index, row in ipairs(log.GetQuestObjectives(info.questID) or {}) do
                local parsed = Quests.ParseRow(row)
                parsed.index = index
                objectives[#objectives + 1] = parsed
            end
            list[#list + 1] = { questID = info.questID, title = info.title, objectives = objectives }
        end
    end
    return list
end

-- mobs: { { name, rate } } -> best first, rare extras dropped (see MIN_RATE). Without any rates
-- (drops we learned by looting) every mob stays, in the order given.
function Quests.TopMobs(mobs)
    local ranked = {}
    for index, mob in ipairs(mobs) do ranked[#ranked + 1] = { mob = mob, index = index } end
    table.sort(ranked, function(a, b)
        local ra, rb = a.mob.rate, b.mob.rate
        if ra ~= rb then
            if ra == nil then return false end
            if rb == nil then return true end
            return ra > rb
        end
        return a.index < b.index
    end)
    local anyRate = false
    for _, entry in ipairs(ranked) do
        if entry.mob.rate then anyRate = true end
    end
    local kept = {}
    for position, entry in ipairs(ranked) do
        local rate = entry.mob.rate
        if not anyRate or position == 1 or (rate and rate >= MIN_RATE) then kept[#kept + 1] = entry.mob end
    end
    return kept
end

-- quests: from Quests.Read. resolve(quest, row, position, total) (optional) returns the mobs
-- that drop an item objective's item as { { name, rate } } and the item's name; position/total
-- say which of the quest's item rows this is. Returns the suggestions
-- { { name, quest (first quest asking), quests (all their titles), rate } } in log order, and
-- the set of item names (normalized) still needed, which loot learning watches for, and whether
-- some needed item has no name yet (its info hasn't loaded, so a later look may know more).
function Quests.Suggest(quests, resolve)
    local out, byName, wanted, unnamed = {}, {}, {}, false
    local function add(name, quest, rate)
        local key = ns.Hunt.Normalize(name)
        if key == "" then return end
        local suggestion = byName[key]
        if not suggestion then
            suggestion = { name = name, quest = quest.title, quests = {}, rate = rate }
            byName[key] = suggestion
            out[#out + 1] = suggestion
        end
        for _, title in ipairs(suggestion.quests) do
            if title == quest.title then return end
        end
        suggestion.quests[#suggestion.quests + 1] = quest.title
    end
    for _, quest in ipairs(quests) do
        local total = 0
        for _, objective in ipairs(quest.objectives) do
            if objective.type == "item" then total = total + 1 end
        end
        local position = 0
        for _, objective in ipairs(quest.objectives) do
            if objective.type == "monster" then
                if not objective.finished and objective.name then add(objective.name, quest) end
            elseif objective.type == "item" then
                position = position + 1
                if not objective.finished then
                    local mobs, itemName
                    if resolve then mobs, itemName = resolve(quest, objective, position, total) end
                    itemName = itemName or objective.name
                    if itemName then wanted[ns.Hunt.Normalize(itemName)] = true else unnamed = true end
                    for _, mob in ipairs(Quests.TopMobs(mobs or {})) do add(mob.name, quest, mob.rate) end
                end
            end
        end
    end
    return out, wanted, unnamed
end

-- Read + Suggest in one go; never raises (a quest log in a half-loaded state is just empty).
function Quests.Collect(resolve)
    local ok, quests = pcall(Quests.Read)
    if not ok then return {}, {}, false end
    local done, suggestions, wanted, unnamed = pcall(Quests.Suggest, quests, resolve)
    if not done then return {}, {}, false end
    return suggestions, wanted, unnamed
end
