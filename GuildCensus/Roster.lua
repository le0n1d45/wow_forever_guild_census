local _, ns = ...

local Roster = {}
ns.Roster = Roster

-- Asks the server for a fresh roster; GUILD_ROSTER_UPDATE fires when it arrives.
function Roster.Request()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

-- The officer note is only filled in for members who may see it (the client gives
-- everyone else an empty string or nil), so it is optional: anything that isn't
-- non-empty text is ignored. Both notes are searched as one text, split by a
-- separator that can't join a keyword to a skill number ("LW | 260" is not "LW 260").
local NOTE_SEPARATOR = " | "

function Roster.CombineNotes(note, officerNote)
    local parts = {}
    for _, text in ipairs({ note, officerNote }) do
        if type(text) == "string" and string.find(text, "%S") then parts[#parts + 1] = text end
    end
    return table.concat(parts, NOTE_SEPARATOR)
end

-- Maps one of the game's profession slots (skill line ID, English name) to a
-- Config.PROFESSIONS key. Returns nil for anything we don't track (cooking, fishing...).
function Roster.ProfessionKey(id, name)
    local lowered = type(name) == "string" and string.lower(name) or nil
    for _, def in ipairs(ns.Config.PROFESSIONS) do
        if (id and id == def.skillLine) or (lowered and lowered == string.lower(def.apiName)) then
            return def.key
        end
    end
end

-- The game's own profession data for one member (a C_Club.GetMemberInfo result):
-- a list of { key, skill }. Slots that are empty, unknown or untracked are skipped,
-- and skill is nil when the rank isn't a positive number.
function Roster.ProfessionsFromInfo(info)
    local list = {}
    if type(info) ~= "table" then return list end
    for slot = 1, 2 do
        local key = Roster.ProfessionKey(info["profession" .. slot .. "ID"], info["profession" .. slot .. "Name"])
        if key then
            local rank = info["profession" .. slot .. "Rank"]
            list[#list + 1] = { key = key, skill = type(rank) == "number" and rank > 0 and rank or nil }
        end
    end
    return list
end

-- The game's name for a race id (C_Club reports race as an id), or nil when unknown.
function Roster.RaceName(raceId)
    if type(raceId) ~= "number" or not (C_CreatureInfo and C_CreatureInfo.GetRaceInfo) then return nil end
    local ok, info = pcall(C_CreatureInfo.GetRaceInfo, raceId)
    if ok and type(info) == "table" and type(info.raceName) == "string" and info.raceName ~= "" then
        return info.raceName
    end
end

-- Fallback when the club has no race: the client's own cache for that guid. It only
-- knows players it has seen, so offline members may come back empty.
local function raceFromGuid(guid)
    if type(guid) ~= "string" or not GetPlayerInfoByGUID then return nil end
    local ok, _, _, race = pcall(GetPlayerInfoByGUID, guid)
    if ok and type(race) == "string" and race ~= "" then return race end
end

local function stripRealm(name)
    return type(name) == "string" and string.match(name, "^[^%-]+") or nil
end

-- Supplemental data: the professions the game itself reports for each guild member
-- (C_Club), as { byGuid = { [guid] = list }, byName = { [name] = list } }, plus the
-- same two maps of race names under raceByGuid / raceByName. Notes stay the fallback,
-- so every failure here (API missing, clubs not ready, no guild club, a member
-- without data) just yields less data and never an error.
function Roster.ReadClubProfessions()
    local result = { byGuid = {}, byName = {}, raceByGuid = {}, raceByName = {} }
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then
        return result
    end
    local lists = {}
    pcall(function()
        local clubId = C_Club.GetGuildClubId()
        if not clubId then return end
        for _, memberId in ipairs(C_Club.GetClubMembers(clubId) or {}) do
            local ok, info = pcall(C_Club.GetMemberInfo, clubId, memberId)
            if ok and type(info) == "table" then
                local list = Roster.ProfessionsFromInfo(info)
                local race = Roster.RaceName(info.race)
                local name = stripRealm(info.name)
                if #list > 0 then
                    lists[#lists + 1] = list
                    if type(info.guid) == "string" then result.byGuid[info.guid] = list end
                    if name then result.byName[name] = list end
                end
                if race then
                    if type(info.guid) == "string" then result.raceByGuid[info.guid] = race end
                    if name then result.raceByName[name] = race end
                end
            end
        end
    end)
    Roster.DropPlaceholderRanks(lists)
    Roster.ApplyOwnSkills(result.byGuid[UnitGUID and UnitGUID("player") or false])
    return result
end

-- WoW Forever reports every member's profession rank as 1 (checked on 369 members, 711
-- slots, while the player's real skills were 180 and 40), so the rank is not a skill level
-- there. When no member in the whole list has a rank above 1 the ranks are a placeholder
-- and are dropped; if the game ever fills them in, the first rank above 1 keeps them all.
function Roster.DropPlaceholderRanks(lists)
    for _, list in ipairs(lists) do
        for _, entry in ipairs(list) do
            if entry.skill and entry.skill > 1 then return end
        end
    end
    for _, list in ipairs(lists) do
        for _, entry in ipairs(list) do entry.skill = nil end
    end
end

-- The player's own skill per skill line ID, from GetProfessions / GetProfessionInfo
-- (their 3rd return is the current skill, the 7th the skill line). Empty when unavailable.
function Roster.OwnSkills()
    local skills = {}
    if not (GetProfessions and GetProfessionInfo) then return skills end
    pcall(function()
        for _, index in pairs({ GetProfessions() }) do
            local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
            if type(rank) == "number" and type(skillLine) == "number" then skills[skillLine] = rank end
        end
    end)
    return skills
end

-- Puts the player's real skill levels onto their own profession list (the guild data has none).
function Roster.ApplyOwnSkills(list)
    if not list then return end
    local skills = Roster.OwnSkills()
    for _, entry in ipairs(list) do
        for _, def in ipairs(ns.Config.PROFESSIONS) do
            if def.key == entry.key and skills[def.skillLine] then entry.skill = skills[def.skillLine] end
        end
    end
end

-- Puts skill levels other Guild Census users reported (Comms) onto a member's profession list:
-- onto the entries the game listed, or, when the game has no list, as the list itself.
function Roster.ApplyReportedSkills(list, reported)
    if not reported then return list end
    if not list then
        list = {}
        for _, def in ipairs(ns.Config.PROFESSIONS) do
            if reported[def.key] then list[#list + 1] = { key = def.key, skill = reported[def.key] } end
        end
        return #list > 0 and list or nil
    end
    for _, entry in ipairs(list) do
        entry.skill = reported[entry.key] or entry.skill
    end
    return list
end

-- Reads the cached guild roster into the member shape Census.Build expects
-- ({ name, level, className, classFile, note, online, professions?, race? }).
function Roster.Read()
    if ns.demoMode then return ns.Demo.Generate() end

    local members = {}
    if not IsInGuild() then return members end

    local club = Roster.ReadClubProfessions()
    for i = 1, GetNumGuildMembers() do
        local fullName, _, _, level, className, _, note, officerNote, isOnline, _, classFile,
            _, _, _, _, _, guid = GetGuildRosterInfo(i)
        local name = fullName and string.match(fullName, "^[^%-]+") or fullName
        members[#members + 1] = {
            name = name, -- "-Realm" dropped
            level = level,
            className = className,
            classFile = classFile,
            note = Roster.CombineNotes(note, officerNote),
            online = isOnline and true or false,
            professions = Roster.ApplyReportedSkills(
                (guid and club.byGuid[guid]) or club.byName[name], -- nil when the game has none
                ns.Comms and ns.Comms.SkillsFor(name)),
            race = (guid and club.raceByGuid[guid]) or club.raceByName[name] or raceFromGuid(guid), -- nil when unknown
        }
    end
    return members
end
