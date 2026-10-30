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

local function stripRealm(name)
    return type(name) == "string" and string.match(name, "^[^%-]+") or nil
end

-- Supplemental data: the professions the game itself reports for each guild member
-- (C_Club), as { byGuid = { [guid] = list }, byName = { [name] = list } }. Notes stay
-- the fallback, so every failure here (API missing, clubs not ready, no guild club, a
-- member without data) just yields less data and never an error.
function Roster.ReadClubProfessions()
    local result = { byGuid = {}, byName = {} }
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then
        return result
    end
    pcall(function()
        local clubId = C_Club.GetGuildClubId()
        if not clubId then return end
        for _, memberId in ipairs(C_Club.GetClubMembers(clubId) or {}) do
            local ok, info = pcall(C_Club.GetMemberInfo, clubId, memberId)
            if ok and type(info) == "table" then
                local list = Roster.ProfessionsFromInfo(info)
                if #list > 0 then
                    if type(info.guid) == "string" then result.byGuid[info.guid] = list end
                    local name = stripRealm(info.name)
                    if name then result.byName[name] = list end
                end
            end
        end
    end)
    return result
end

-- Reads the cached guild roster into the member shape Census.Build expects.
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
            professions = (guid and club.byGuid[guid]) or club.byName[name], -- nil when the game has none
        }
    end
    return members
end
