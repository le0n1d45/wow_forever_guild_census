local _, ns = ...

-- Skill levels shared between Guild Census users. The game reports no skill level for other
-- players on WoW Forever (see Roster.DropPlaceholderRanks), so every client announces its own
-- over the GUILD addon-message channel (hidden from chat) and remembers what it hears.
--   "H1"                       hello: "send me your skills" (sent at login)
--   "P1|393:180,182:40"        a player's skills as <skill line ID>:<level>, at most two
-- Only the player's own Config.PROFESSIONS skills are sent. Reports are self-reported, kept in
-- GuildCensusDB.reports[name] = { t = time, skills = { [key] = level } }, and used by
-- Roster.Read where the game has no level. Receiving is always on; sending is the
-- "shareSkills" setting.
local Comms = {}
ns.Comms = Comms

Comms.PREFIX = "GuildCensus"
Comms.VERSION = 1
Comms.HELLO = "H" .. Comms.VERSION
Comms.MIN_INTERVAL = 120 -- seconds between our own broadcasts
Comms.REPLY_DELAY = { 2, 20 } -- jitter before answering a hello, so a guild doesn't answer at once
Comms.MAX_AGE = 60 * 24 * 3600 -- reports older than this are dropped
Comms.MAX_SKILL = 1000
Comms.MAX_PROFESSIONS = 2

Comms.stats = { sent = 0, received = 0, ignored = 0 }

local pendingBroadcast, pendingRefresh, pendingSkillCheck = false, false, false

local function now() return (time or os.time)() end

local function after(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

local function stripRealm(name)
    return type(name) == "string" and string.match(name, "^[^%-]+") or nil
end

local function sharing()
    return ns.settings == nil or ns.settings.shareSkills ~= false
end

local function keyForSkillLine(skillLine)
    for _, def in ipairs(ns.Config.PROFESSIONS) do
        if def.skillLine == skillLine then return def.key end
    end
end

-- entries: list of { skillLine, skill }.
function Comms.Encode(entries)
    local parts = {}
    for _, entry in ipairs(entries) do parts[#parts + 1] = entry.skillLine .. ":" .. entry.skill end
    return "P" .. Comms.VERSION .. "|" .. table.concat(parts, ",")
end

-- Returns "hello", or "skills" and a { [key] = level } table, or nil for anything malformed,
-- from another version, or out of range. Skill lines we don't track are skipped.
function Comms.Decode(text)
    if type(text) ~= "string" then return nil end
    if text == Comms.HELLO then return "hello" end
    local body = string.match(text, "^P" .. Comms.VERSION .. "|(.*)$")
    if not body or string.find(body, "^,") or string.find(body, ",,") or string.find(body, ",$") then return nil end
    local skills, count = {}, 0
    for item in string.gmatch(body, "[^,]+") do
        local line, skill = string.match(item, "^(%d+):(%d+)$")
        line, skill = tonumber(line), tonumber(skill)
        count = count + 1
        if not (line and skill) or count > Comms.MAX_PROFESSIONS or skill < 1 or skill > Comms.MAX_SKILL then
            return nil
        end
        local key = keyForSkillLine(line)
        if key then skills[key] = skill end
    end
    return "skills", skills
end

-- The player's own tracked professions, in Config order, as Encode wants them.
function Comms.OwnEntries()
    local own = ns.Roster.OwnSkills()
    local entries = {}
    for _, def in ipairs(ns.Config.PROFESSIONS) do
        local skill = own[def.skillLine]
        if skill and skill >= 1 and #entries < Comms.MAX_PROFESSIONS then
            entries[#entries + 1] = { skillLine = def.skillLine, skill = math.min(skill, Comms.MAX_SKILL) }
        end
    end
    return entries
end

local function send(text)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        Comms.stats.lastSend = "SendAddonMessage is missing"
        return false
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, Comms.PREFIX, text, "GUILD")
    Comms.stats.lastSend = ok and ("returned " .. tostring(result)) or ("error: " .. tostring(result))
    -- success is nil/true on older clients, Enum.SendAddonMessageResult.Success (0) on newer ones
    local sent = ok and (result == nil or result == true or result == 0)
    if sent then Comms.stats.sent = Comms.stats.sent + 1 end
    return sent
end

-- Sends our skills now, if sharing is on and we are in a guild. Returns whether it was sent.
function Comms.Broadcast()
    if not sharing() or not (IsInGuild and IsInGuild()) then return false end
    local text = Comms.Encode(Comms.OwnEntries())
    if not send(text) then return false end
    if ns.db then ns.db.lastBroadcast, ns.db.lastBroadcastText = now(), text end
    return true
end

-- Broadcasts after a random delay in [minDelay, maxDelay], and never sooner than MIN_INTERVAL
-- after the previous broadcast. One is pending at a time, so any number of hellos in a row
-- cause at most one message from this client.
function Comms.Schedule(minDelay, maxDelay)
    if pendingBroadcast or not sharing() then return end
    pendingBroadcast = true
    local wait = minDelay + math.random() * (maxDelay - minDelay)
    local last = ns.db and ns.db.lastBroadcast
    if last then wait = math.max(wait, Comms.MIN_INTERVAL - (now() - last)) end
    after(wait, function()
        pendingBroadcast = false
        Comms.Broadcast()
    end)
end

local function refreshSoon()
    if pendingRefresh then return end
    pendingRefresh = true
    after(3, function()
        pendingRefresh = false
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    end)
end

-- CHAT_MSG_ADDON handler.
function Comms.OnMessage(prefix, text, channel, sender)
    if prefix ~= Comms.PREFIX or channel ~= "GUILD" then return end
    local name = stripRealm(sender)
    if not name or (UnitName and name == stripRealm(UnitName("player"))) then return end
    local kind, skills = Comms.Decode(text)
    if not kind then
        Comms.stats.ignored = Comms.stats.ignored + 1
        return
    end
    Comms.stats.received = Comms.stats.received + 1
    Comms.stats.last = name .. ": " .. text
    if kind == "hello" then
        Comms.Schedule(Comms.REPLY_DELAY[1], Comms.REPLY_DELAY[2])
        return
    end
    if not ns.db then return end
    ns.db.reports[name] = { t = now(), skills = skills }
    refreshSoon()
end

-- What other players reported for `name`: { [key] = level }, or nil when nothing recent.
function Comms.SkillsFor(name)
    local report = ns.db and ns.db.reports and ns.db.reports[name]
    if report and now() - report.t <= Comms.MAX_AGE then return report.skills end
end

-- Call once ns.db exists (ADDON_LOADED): drops old reports and registers the message prefix.
function Comms.Init()
    ns.db.reports = type(ns.db.reports) == "table" and ns.db.reports or {}
    for name, report in pairs(ns.db.reports) do
        if type(report) ~= "table" or type(report.t) ~= "number" or now() - report.t > Comms.MAX_AGE then
            ns.db.reports[name] = nil
        end
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comms.PREFIX)
        Comms.stats.register = ok and tostring(result) or ("error: " .. tostring(result))
    else
        Comms.stats.register = "RegisterAddonMessagePrefix is missing"
    end
end

-- PLAYER_LOGIN: shortly after, ask the guild for everyone's skills (at most once per
-- MIN_INTERVAL, so /reload spam stays quiet) and announce ours.
function Comms.OnLogin()
    after(10, function()
        if not sharing() or not (IsInGuild and IsInGuild()) then return end
        local last = ns.db.lastHello
        if not last or now() - last >= Comms.MIN_INTERVAL then
            if send(Comms.HELLO) then ns.db.lastHello = now() end
        end
        Comms.Schedule(5, 15)
    end)
end

-- SKILL_LINES_CHANGED fires on every skill-up; wait, and announce only if our skills differ
-- from what we last announced.
function Comms.OnSkillsChanged()
    if pendingSkillCheck then return end
    pendingSkillCheck = true
    after(30, function()
        pendingSkillCheck = false
        if Comms.Encode(Comms.OwnEntries()) ~= ns.db.lastBroadcastText then Comms.Schedule(0, 5) end
    end)
end

-- Lines for /gcensus comms and the debug report.
function Comms.Status()
    local count = 0
    for _ in pairs(ns.db and ns.db.reports or {}) do count = count + 1 end
    local stats = Comms.stats
    return {
        "sharing your skills: " .. (sharing() and "on" or "off"),
        "prefix registration: " .. tostring(stats.register),
        "SendAddonMessage / RegisterAddonMessagePrefix present: " ..
            tostring(C_ChatInfo ~= nil and C_ChatInfo.SendAddonMessage ~= nil) .. " / " ..
            tostring(C_ChatInfo ~= nil and C_ChatInfo.RegisterAddonMessagePrefix ~= nil),
        "sent " .. stats.sent .. ", received " .. stats.received .. ", ignored " .. stats.ignored,
        "last send: " .. tostring(stats.lastSend),
        "last received: " .. tostring(stats.last),
        "players with reported skills: " .. count,
        "our message: " .. Comms.Encode(Comms.OwnEntries()),
    }
end
