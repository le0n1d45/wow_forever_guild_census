local _, ns = ...

-- Pure matching logic for MobHunter; no WoW API calls, so it runs headlessly in tests.
local Hunt = {}
ns.Hunt = Hunt

-- Lowercases, trims and collapses whitespace so "  Defias   PILLAGER " == "defias pillager".
function Hunt.Normalize(text)
    if type(text) ~= "string" then return "" end
    return (string.lower(text):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- hunted must be normalized. A mob matches when its name contains the hunted text, so
-- "pillager" finds "Defias Pillager". Anything that isn't plain text never matches (the
-- client can hand addons "secret" values it won't let them read).
function Hunt.Matches(hunted, name)
    if hunted == "" or type(hunted) ~= "string" then return false end
    local ok, found = pcall(function()
        if type(name) ~= "string" then return false end
        return string.find(string.lower(name), hunted, 1, true) ~= nil
    end)
    return ok and found or false
end

-- "/mobhunt <name>" -> { action = "hunt", name }, plus "stop", "status" (empty), "help",
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
    if text == "debug" then return { action = "debug" } end
    if text == "macro" then return { action = "macro" } end
    if text == "button on" or text == "button off" then
        return { action = "button", on = text == "button on" }
    end
    if text == "button" then return { action = "button" } end
    return { action = "hunt", name = text }
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
