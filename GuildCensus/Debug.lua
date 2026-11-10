local _, ns = ...

-- /gcensus debug: a diagnostic report for bug reports, copied out of the game. It says what
-- the addon is running on, which game APIs it relies on are there, what data each source
-- (game guild data, other players' reports, notes) gave for the guild, and how that ended up
-- in the Profession Finder. Every call is wrapped in pcall, and a missing API is reported as
-- missing; nothing here may raise an error.
local Debug = {}
ns.Debug = Debug

local SAMPLE_MEMBERS = 3
local REPORT_SAMPLE = 5

-- The APIs the addon relies on, so a report shows at a glance which are missing.
local USED_APIS = {
    "IsInGuild", "GetNumGuildMembers", "GetGuildRosterInfo", "C_GuildInfo.GuildRoster",
    "C_Club.GetGuildClubId", "C_Club.GetClubMembers", "C_Club.GetMemberInfo",
    "C_CreatureInfo.GetRaceInfo", "GetPlayerInfoByGUID",
    "GetProfessions", "GetProfessionInfo",
    "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "C_Timer.After",
}

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- A value as one line: strings quoted, tables expanded two levels deep, anything else tostring'd.
local function fmt(v, depth)
    local kind = type(v)
    if kind == "string" then return string.format("%q", v) end
    if kind == "table" then
        if (depth or 0) >= 2 then return "{...}" end
        local parts = {}
        for _, k in ipairs(sortedKeys(v)) do
            parts[#parts + 1] = tostring(k) .. "=" .. fmt(v[k], (depth or 0) + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    local ok, text = pcall(tostring, v)
    return ok and text or "<unprintable>"
end
Debug.Format = fmt

-- All the values of a pcall result list, including trailing nils: "1=..., 2=nil, 3=...".
local function formatReturns(values, count)
    local parts = {}
    for i = 1, count do parts[i] = i .. "=" .. fmt(values[i]) end
    return table.concat(parts, ", ")
end

-- Calls fn(...) and reports every return value (or the error).
local function callAll(fn, ...)
    local packed = { pcall(fn, ...) }
    if not table.remove(packed, 1) then return "ERROR " .. fmt(packed[1]) end
    local count = 0
    for i in pairs(packed) do if type(i) == "number" and i > count then count = i end end
    if count == 0 then return "(no return values)" end
    return formatReturns(packed, count)
end

local function resolve(path)
    local value = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

local function section(lines, title)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== " .. title .. " =="
end

local function add(lines, text) lines[#lines + 1] = text end

-- Runs one section, turning an unexpected error into a line of the report.
local function guarded(lines, title, fn)
    section(lines, title)
    local ok, err = pcall(fn)
    if not ok then add(lines, "SECTION ERROR: " .. fmt(err)) end
end

local function now() return (time or os.time)() end

local function ownName()
    return UnitName and UnitName("player") or nil
end

local function addonSection(lines)
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMeta and select(2, pcall(getMeta, "GuildCensus", "Version"))
    add(lines, "GuildCensus " .. fmt(version) .. ", report made " .. (date and date("%Y-%m-%d %H:%M") or "?"))
    local settings = ns.settings or {}
    add(lines, "settings: shareSkills=" .. fmt(settings.shareSkills) .. " includeAlts=" .. fmt(settings.includeAlts) ..
        " onlyMains=" .. fmt(settings.onlyMains) .. " demoMode=" .. fmt(ns.demoMode))
end

local function clientSection(lines)
    if GetBuildInfo then add(lines, "GetBuildInfo: " .. callAll(GetBuildInfo)) end
    add(lines, "WOW_PROJECT_ID=" .. fmt(WOW_PROJECT_ID) .. " locale=" .. fmt(GetLocale and GetLocale()))
    add(lines, "player: " .. fmt(ownName()) .. " " .. fmt(UnitGUID and UnitGUID("player")))
    local missing = {}
    for _, path in ipairs(USED_APIS) do
        if type(resolve(path)) ~= "function" then missing[#missing + 1] = path end
    end
    add(lines, "APIs the addon uses that are missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
end

local function guildSection(lines)
    add(lines, "in a guild: " .. callAll(IsInGuild))
    if GetGuildInfo then add(lines, "GetGuildInfo(player): " .. callAll(GetGuildInfo, "player")) end
    add(lines, "GetNumGuildMembers (total, online): " .. callAll(GetNumGuildMembers))
    if GetGuildRosterShowOffline then add(lines, "show offline members: " .. callAll(GetGuildRosterShowOffline)) end
    if C_Club and C_Club.GetGuildClubId then
        local ok, clubId = pcall(C_Club.GetGuildClubId)
        add(lines, "guild club id: " .. (ok and fmt(clubId) or "ERROR " .. fmt(clubId)))
        if ok and clubId and C_Club.GetClubMembers then
            local okIds, ids = pcall(C_Club.GetClubMembers, clubId)
            add(lines, "club members: " .. (okIds and type(ids) == "table" and #ids or "ERROR " .. fmt(ids)))
        end
    else
        add(lines, "C_Club is missing")
    end
end

-- The raw profession slots C_Club reports, before the addon touches them: how many members
-- have each field and which rank values occur (all 1 means the placeholder rank).
local function clubRawSection(lines)
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then
        add(lines, "C_Club is missing")
        return
    end
    local okClub, clubId = pcall(C_Club.GetGuildClubId)
    if not okClub then add(lines, "GetGuildClubId failed: " .. fmt(clubId)) return end
    if not clubId then add(lines, "no guild club") return end
    local okIds, ids = pcall(C_Club.GetClubMembers, clubId)
    if not okIds then add(lines, "GetClubMembers failed: " .. fmt(ids)) return end
    local members, withProfession, slots, failed = 0, 0, 0, 0
    local ranks, unknownIds = {}, {}
    for _, id in ipairs(ids or {}) do
        local ok, info = pcall(C_Club.GetMemberInfo, clubId, id)
        if ok and type(info) == "table" then
            members = members + 1
            local any = false
            for slot = 1, 2 do
                local line = info["profession" .. slot .. "ID"]
                if line then
                    any, slots = true, slots + 1
                    local rank = fmt(info["profession" .. slot .. "Rank"])
                    ranks[rank] = (ranks[rank] or 0) + 1
                    if not ns.Roster.ProfessionKey(line, info["profession" .. slot .. "Name"]) then
                        unknownIds[fmt(line) .. " " .. fmt(info["profession" .. slot .. "Name"])] = true
                    end
                end
            end
            if any then withProfession = withProfession + 1 end
        else
            failed = failed + 1
        end
    end
    add(lines, "members read: " .. members .. " (failed: " .. failed .. "), with a profession: " .. withProfession ..
        ", profession slots: " .. slots)
    local parts = {}
    for _, rank in ipairs(sortedKeys(ranks)) do parts[#parts + 1] = rank .. " x" .. ranks[rank] end
    add(lines, "rank values reported: " .. (#parts > 0 and table.concat(parts, ", ") or "none") ..
        (#parts == 1 and parts[1]:find("^1 ") and "  (a constant 1: a placeholder, ignored by the addon)" or ""))
    local unknown = sortedKeys(unknownIds)
    add(lines, "professions the addon does not track: " .. (#unknown > 0 and table.concat(unknown, ", ") or "none"))
end

-- Where each skill level in the Profession Finder came from, per profession.
local function coverageSection(lines)
    local members = ns.Roster.Read()
    local rules = ns.Census.Rules(ns.settings)
    local me = ownName()
    local byProfession, sources = {}, {}
    local withNote, withProfession, withRace, withReport = 0, 0, 0, 0
    local samples = {}
    for _, member in ipairs(members) do
        if member.note ~= "" then withNote = withNote + 1 end
        if member.race then withRace = withRace + 1 end
        local reported = ns.Comms and ns.Comms.SkillsFor(member.name)
        if reported then withReport = withReport + 1 end
        local analysis = ns.Census.Analyze(member, rules)
        if #analysis.professionHits > 0 then withProfession = withProfession + 1 end
        local described = {}
        for _, hit in ipairs(analysis.professionHits) do
            local stat = byProfession[hit.key] or { members = 0, withLevel = 0 }
            byProfession[hit.key] = stat
            stat.members = stat.members + 1
            local source = "none"
            if hit.skill then
                stat.withLevel = stat.withLevel + 1
                stat.min = stat.min and math.min(stat.min, hit.skill) or hit.skill
                stat.max = stat.max and math.max(stat.max, hit.skill) or hit.skill
                if member.name == me then source = "own"
                elseif reported and reported[hit.key] == hit.skill then source = "reported"
                else
                    local fromGame
                    for _, entry in ipairs(member.professions or {}) do
                        if entry.key == hit.key and entry.skill == hit.skill then fromGame = true end
                    end
                    source = fromGame and "game rank" or "note"
                end
            end
            sources[source] = (sources[source] or 0) + 1
            described[#described + 1] = hit.label .. " " .. (hit.skill or "-") .. " (" .. source .. ")"
        end
        if #samples < SAMPLE_MEMBERS and (member.name == me or (#described > 0 and #samples < SAMPLE_MEMBERS - 1)) then
            samples[#samples + 1] = member.name .. ": " .. (#described > 0 and table.concat(described, ", ") or "no professions") ..
                "; note " .. fmt(member.note)
        end
    end
    add(lines, "roster members: " .. #members .. ", with a note: " .. withNote .. ", with a profession: " .. withProfession ..
        ", with a race: " .. withRace .. ", with reported skills: " .. withReport)
    for _, def in ipairs(ns.Config.PROFESSIONS) do
        local stat = byProfession[def.key]
        if stat then
            add(lines, string.format("  %-16s %3d members, %3d with a level%s", def.label, stat.members, stat.withLevel,
                stat.min and (" (" .. stat.min .. " to " .. stat.max .. ")") or ""))
        end
    end
    local parts = {}
    for _, source in ipairs(sortedKeys(sources)) do parts[#parts + 1] = source .. " x" .. sources[source] end
    add(lines, "skill level sources: " .. table.concat(parts, ", "))
    add(lines, "(sources: own = your GetProfessionInfo, reported = another Guild Census user, game rank = C_Club, note = guild note)")
    add(lines, "samples:")
    for _, line in ipairs(samples) do add(lines, "  " .. line) end
end

-- Your professions as the game reports them, as the guild data lists them, and as sent.
local function ownSection(lines)
    if GetProfessions and GetProfessionInfo then
        local ok, indexes = pcall(function() return { GetProfessions() } end)
        for slot = 1, 5 do
            local index = ok and indexes[slot]
            if index then add(lines, "  GetProfessionInfo(" .. index .. "): " .. callAll(GetProfessionInfo, index)) end
        end
    else
        add(lines, "GetProfessions / GetProfessionInfo are missing")
    end
    if C_Club and C_Club.GetGuildClubId and C_Club.GetMemberInfoForSelf then
        local okClub, clubId = pcall(C_Club.GetGuildClubId)
        if okClub and clubId then
            local ok, info = pcall(C_Club.GetMemberInfoForSelf, clubId)
            if ok and type(info) == "table" then
                local parts = {}
                for slot = 1, 2 do
                    if info["profession" .. slot .. "ID"] then
                        parts[#parts + 1] = fmt(info["profession" .. slot .. "Name"]) .. " rank " ..
                            fmt(info["profession" .. slot .. "Rank"])
                    end
                end
                add(lines, "guild club lists you with: " .. (#parts > 0 and table.concat(parts, ", ") or "no professions"))
            end
        end
    end
end

local function commsSection(lines)
    if not ns.Comms then add(lines, "Comms is missing") return end
    for _, line in ipairs(ns.Comms.Status()) do add(lines, line) end
    local reports = ns.db and ns.db.reports or {}
    local names, newest, oldest = sortedKeys(reports), nil, nil
    for _, name in ipairs(names) do
        local age = now() - reports[name].t
        newest = newest and math.min(newest, age) or age
        oldest = oldest and math.max(oldest, age) or age
    end
    if #names > 0 then
        add(lines, string.format("report ages: newest %d min, oldest %.1f days", newest / 60, oldest / 86400))
        add(lines, "sample reports:")
        for i = 1, math.min(REPORT_SAMPLE, #names) do
            add(lines, "  " .. names[i] .. " " .. fmt(reports[names[i]].skills))
        end
    end
end

local function conflictSection(lines)
    local census = ns.Census.Build(ns.Roster.Read(), ns.settings)
    local kinds = {}
    for _, conflict in ipairs(census.conflicts or {}) do kinds[conflict.kind] = (kinds[conflict.kind] or 0) + 1 end
    local parts = {}
    for _, kind in ipairs(sortedKeys(kinds)) do parts[#parts + 1] = kind .. " x" .. kinds[kind] end
    add(lines, "census conflicts (Logs tab): " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
end

-- Builds the report as a list of lines.
function Debug.Report()
    local lines = {}
    guarded(lines, "Addon", function() addonSection(lines) end)
    guarded(lines, "Client", function() clientSection(lines) end)
    guarded(lines, "Guild", function() guildSection(lines) end)
    guarded(lines, "Guild data from C_Club (raw)", function() clubRawSection(lines) end)
    guarded(lines, "Profession levels in the Finder, by source", function() coverageSection(lines) end)
    guarded(lines, "Your professions", function() ownSection(lines) end)
    guarded(lines, "Skill sharing between Guild Census users", function() commsSection(lines) end)
    guarded(lines, "Census", function() conflictSection(lines) end)
    return lines
end

-- A window with the text in a selectable box, so it can be copied with Ctrl+C (chat can't be).
local reportFrame
local function showReport(title, text)
    if not reportFrame then
        reportFrame = CreateFrame("Frame", "GuildCensusReportFrame", UIParent, "BasicFrameTemplateWithInset")
        reportFrame:SetSize(720, 480)
        reportFrame:SetPoint("CENTER")
        reportFrame:SetFrameStrata("DIALOG")
        reportFrame:SetMovable(true)
        reportFrame:EnableMouse(true)
        reportFrame:RegisterForDrag("LeftButton")
        reportFrame:SetScript("OnDragStart", reportFrame.StartMoving)
        reportFrame:SetScript("OnDragStop", reportFrame.StopMovingOrSizing)
        if UISpecialFrames then table.insert(UISpecialFrames, "GuildCensusReportFrame") end -- Esc closes it
        local scroll = CreateFrame("ScrollFrame", "GuildCensusReportScroll", reportFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal or GameFontHighlight)
        box:SetWidth(660)
        box:SetScript("OnEscapePressed", function() reportFrame:Hide() end)
        scroll:SetScrollChild(box)
        reportFrame.box = box
    end
    if type(reportFrame.TitleText) == "table" then reportFrame.TitleText:SetText(title) end
    reportFrame.box:SetText(text)
    reportFrame:Show()
    reportFrame.box:SetFocus()
    reportFrame.box:HighlightText() -- selected: just press Ctrl+C
end

-- Builds the report, keeps it in the SavedVariables and shows it in a copyable window.
function Debug.Show()
    local lines = Debug.Report()
    if ns.db then ns.db.lastDebug = lines end -- also lands in GuildCensus.lua in WTF after /reload or logout
    showReport("Guild Census debug", table.concat(lines, "\n"))
    print("|cff33ff99GuildCensus:|r debug report is in the window (already selected: press Ctrl+C to copy). It is also saved to GuildCensus.lua in your WTF\\Account\\<account>\\SavedVariables folder after /reload.")
end
