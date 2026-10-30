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

-- Reads the cached guild roster into the member shape Census.Build expects.
function Roster.Read()
    if ns.demoMode then return ns.Demo.Generate() end

    local members = {}
    if not IsInGuild() then return members end

    for i = 1, GetNumGuildMembers() do
        local fullName, _, _, level, className, _, note, officerNote, isOnline, _, classFile = GetGuildRosterInfo(i)
        members[#members + 1] = {
            name = fullName and string.match(fullName, "^[^%-]+") or fullName, -- drop "-Realm"
            level = level,
            className = className,
            classFile = classFile,
            note = Roster.CombineNotes(note, officerNote),
            online = isOnline and true or false,
        }
    end
    return members
end
