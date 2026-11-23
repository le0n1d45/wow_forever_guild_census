local addonName, ns = ...

-- Text the window and tooltips show: money, and where a recipe comes from.

local Format = {}
ns.Format = Format

-- 12345 -> "1g 23s 45c"; zero parts are left out.
function Format.Money(copper)
    if not copper then return "?" end
    local sign = copper < 0 and "-" or ""
    copper = math.floor(math.abs(copper) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return sign .. table.concat(parts, " ")
end

-- "3 hours ago", for the age of the last scan.
function Format.Age(seconds)
    if seconds < 90 then return "just now" end
    if seconds < 5400 then return math.floor(seconds / 60 + 0.5) .. " minutes ago" end
    if seconds < 129600 then return math.floor(seconds / 3600 + 0.5) .. " hours ago" end
    return math.floor(seconds / 86400 + 0.5) .. " days ago"
end

function Format.ItemName(itemID)
    local info = ns.Data.Items and ns.Data.Items[itemID]
    return info and info.name or ("item " .. itemID)
end

local function zoneName(area)
    local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)
    return name or ("area " .. area)
end

-- "Eldrin (Elwynn Forest 79, 69)"; npc = { name, subtitle, faction, area, x, y }.
function Format.Where(npc)
    if not npc then return "an unknown NPC" end
    if npc[4] and npc[5] then
        return string.format("%s (%s %d, %d)", npc[1], zoneName(npc[4]), npc[5], npc[6])
    end
    return npc[1]
end

local function factionOk(npc, faction)
    return not npc or not faction or npc[3] == "" or npc[3] == "AH" or npc[3] == nil or npc[3] == faction
end

-- A recipe's own item: the first one the player's faction can get, with where it comes from.
-- Returns a short text for the list.
function Format.Source(recipe, status)
    if status == "known" then return "known" end
    if status == "trainer" then
        return "trainer " .. Format.Money(recipe.train[2])
    end
    local faction = ns.Known and ns.Known.Faction()
    local npcs = ns.Data.Npcs or {}
    local quests = ns.Data.Quests or {}
    for _, book in ipairs(recipe.recipeItems or {}) do
        for _, id in ipairs(book.vendors or {}) do
            if factionOk(npcs[id], faction) then
                local price = ns.Data.Items[book[1]] and ns.Data.Items[book[1]].buy
                local more = #book.vendors > 1 and (" +" .. (#book.vendors - 1)) or ""
                return "sold by " .. (npcs[id] and npcs[id][1] or "a vendor") .. more .. (price and (" " .. Format.Money(price)) or "")
            end
        end
    end
    for _, book in ipairs(recipe.recipeItems or {}) do
        if book.quests then return "quest: " .. (quests[book.quests[1]] ~= "" and quests[book.quests[1]] or "a quest") end
    end
    for _, book in ipairs(recipe.recipeItems or {}) do
        if book.drops then return "dropped by " .. (npcs[book.drops[1]] and npcs[book.drops[1]][1] or "a mob") end
        if book.objects then return "found in the world" end
    end
    if recipe.train then return "trainer, needs more skill" end
    return "source unknown"
end

-- Lines for a tooltip about where to learn a recipe.
function Format.SourceLines(recipe, status)
    local lines = {}
    local npcs = ns.Data.Npcs or {}
    local trainers = ns.Data.Trainers or {}
    if recipe.train and status ~= "known" then
        lines[#lines + 1] = string.format("Trainer: needs skill %d, costs %s", recipe.train[1], Format.Money(recipe.train[2]))
        local faction = ns.Known and ns.Known.Faction()
        local shown = 0
        for _, id in ipairs(recipe.trainers or {}) do
            local t = trainers[id]
            if t and factionOk(t, faction) and shown < 3 then
                lines[#lines + 1] = "  " .. Format.Where(t)
                shown = shown + 1
            end
        end
    end
    if status ~= "known" then
        for _, book in ipairs(recipe.recipeItems or {}) do
            lines[#lines + 1] = "Recipe item: " .. Format.ItemName(book[1])
            for i, id in ipairs(book.vendors or {}) do
                if i <= 3 then lines[#lines + 1] = "  sold by " .. Format.Where(npcs[id]) end
            end
            for i, id in ipairs(book.quests or {}) do
                if i <= 2 then lines[#lines + 1] = "  quest reward: " .. ((ns.Data.Quests or {})[id] or id) end
            end
            for i, id in ipairs(book.drops or {}) do
                if i <= 3 then lines[#lines + 1] = "  dropped by " .. Format.Where(npcs[id]) end
            end
            if book.objects then lines[#lines + 1] = "  found in " .. book.objects .. " world objects" end
        end
    end
    return lines
end
