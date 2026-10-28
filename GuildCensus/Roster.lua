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

-- Reads the cached guild roster into the member shape Census.Build expects.
function Roster.Read()
    if ns.demoMode then return ns.Demo.Generate(80) end

    local members = {}
    if not IsInGuild() then return members end

    for i = 1, GetNumGuildMembers() do
        local _, _, _, level, className, _, note, _, _, _, classFile = GetGuildRosterInfo(i)
        members[#members + 1] = {
            level = level,
            className = className,
            classFile = classFile,
            note = note,
        }
    end
    return members
end
