local _, ns = ...

-- Pure matching logic for MobHunter; no WoW API calls, so it runs headlessly in tests.
local Hunt = {}
ns.Hunt = Hunt

-- Lowercases, trims and collapses whitespace so "  Defias   PILLAGER " == "defias pillager".
function Hunt.Normalize(text)
    if type(text) ~= "string" then return "" end
    return (string.lower(text):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- "raptor, Lion,,raptor" -> { "raptor", "lion" }: split on commas, normalized, empties and
-- repeats dropped, order kept. This is how one text box (or /mobhunt) names several mobs.
function Hunt.ParseNames(text)
    local names, seen = {}, {}
    if type(text) ~= "string" then return names end
    for piece in (text .. ","):gmatch("([^,]*),") do
        local name = Hunt.Normalize(piece)
        if name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

-- "raptor, lion" for messages; accepts a list or a single name.
function Hunt.Describe(hunted)
    if type(hunted) == "table" then return table.concat(hunted, ", ") end
    return tostring(hunted or "")
end

-- hunted is a normalized name, or a list of them (a mob matches when it matches any). A mob
-- matches when its name contains the hunted text, so "pillager" finds "Defias Pillager".
-- Anything that isn't plain text never matches (the client can hand addons "secret" values
-- it won't let them read).
function Hunt.Matches(hunted, name)
    if type(hunted) == "table" then
        for _, one in ipairs(hunted) do
            if Hunt.Matches(one, name) then return true end
        end
        return false
    end
    if hunted == "" or type(hunted) ~= "string" then return false end
    local ok, found = pcall(function()
        if type(name) ~= "string" then return false end
        return string.find(string.lower(name), hunted, 1, true) ~= nil
    end)
    return ok and found or false
end

-- "/mobhunt <name>[, <name>...]" -> { action = "hunt", names = { ... } }, plus "stop", "status" (empty), "help",
-- "target", "macro" and "button on|off" ({ action = "button", on = true|false }).
function Hunt.ParseCommand(msg)
    local text = Hunt.Normalize(msg)
    if text == "" then return { action = "status" } end
    if text == "stop" or text == "off" or text == "clear" then return { action = "stop" } end
    if text == "help" or text == "?" then return { action = "help" } end
    if text == "target" then return { action = "target" } end
    if text == "sound on" or text == "sound off" then return { action = "sound", on = text == "sound on" } end
    if text == "sound" then return { action = "sound" } end
    if text == "window" then return { action = "window" } end
    if text == "options" or text == "config" or text == "settings" then return { action = "options" } end
    if text == "quests" then return { action = "quests" } end
    if text == "debug" then return { action = "debug" } end
    if text == "macro" then return { action = "macro" } end
    if text == "button on" or text == "button off" then
        return { action = "button", on = text == "button on" }
    end
    if text == "button" then return { action = "button" } end
    local names = Hunt.ParseNames(text)
    if #names == 0 then return { action = "status" } end
    return { action = "hunt", names = names }
end

-- units: list of { token, name, guid, isDead, isPlayer } for what is currently in range.
-- tracker.seen remembers who was already reported, so each mob alerts once while it stays
-- in range and again if it leaves and comes back. Returns the newly found units.
function Hunt.Scan(tracker, hunted, units)
    local present, found = {}, {}
    for _, unit in ipairs(units) do
        local key = unit.guid or unit.token
        if key and not unit.isDead and not unit.isPlayer and Hunt.Matches(hunted, unit.name) then
            present[key] = true
            if not tracker.seen[key] then
                tracker.seen[key] = true
                found[#found + 1] = unit
            end
        end
    end
    for key in pairs(tracker.seen) do
        if not present[key] then tracker.seen[key] = nil end
    end
    return found
end

function Hunt.NewTracker()
    return { seen = {} }
end
