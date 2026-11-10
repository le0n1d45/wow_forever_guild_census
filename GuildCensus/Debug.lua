local _, ns = ...

-- /gcensus debug: a diagnostic report of what the client's APIs return for professions,
-- skill levels and guild members, to copy out of a real client. Every call is wrapped in
-- pcall, and a missing API is reported as missing; nothing here may raise an error.
local Debug = {}
ns.Debug = Debug

local SAMPLE_FIRST, SAMPLE_WITH_PROFESSIONS, SAMPLE_WITHOUT = 3, 8, 3
local TRADESKILL_ROWS = 25
local SKILL_LINES = 60

-- Globals worth knowing about: present or not on this client.
local CANDIDATE_APIS = {
    "C_Club.GetGuildClubId", "C_Club.GetClubInfo", "C_Club.GetClubMembers", "C_Club.GetMemberInfo",
    "C_Club.GetMemberInfoForSelf", "C_Club.GetGuildClubId",
    "C_GuildInfo.GuildRoster", "C_GuildInfo.QueryGuildMemberRecipes", "C_GuildInfo.GetGuildRankOrder",
    "GetGuildRosterInfo", "GetNumGuildMembers", "GetGuildRosterShowOffline", "SetGuildRosterShowOffline",
    "GetGuildTradeSkillInfo", "GetNumGuildTradeSkill", "GetGuildTradeSkillView", "SetGuildTradeSkillView",
    "GetNumSkillLines", "GetSkillLineInfo", "ExpandSkillHeader",
    "GetProfessions", "GetProfessionInfo", "GetNumPrimaryProfessions",
    "C_TradeSkillUI.GetAllProfessionTradeSkillLines", "C_TradeSkillUI.GetProfessionInfoBySkillLineID",
    "C_TradeSkillUI.GetTradeSkillLine", "GetTradeSkillLine", "GetNumTradeSkills",
    "C_SpellBook.GetSkillLineInfo", "C_SpellBook.GetNumSpellBookSkillLines",
    "C_CreatureInfo.GetRaceInfo", "GetPlayerInfoByGUID", "GetBuildInfo", "UnitGUID",
}

local function safe(fn, ...)
    local packed = { pcall(fn, ...) }
    local ok = table.remove(packed, 1)
    return ok, packed
end

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

local function clientSection(lines)
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMeta and select(2, pcall(getMeta, "GuildCensus", "Version"))
    add(lines, "GuildCensus " .. fmt(version) .. " debug, " .. (date and date("%Y-%m-%d %H:%M") or "?"))
    if GetBuildInfo then add(lines, "GetBuildInfo: " .. callAll(GetBuildInfo)) end
    add(lines, "WOW_PROJECT_ID=" .. fmt(WOW_PROJECT_ID) .. " LE_EXPANSION_LEVEL_CURRENT=" .. fmt(LE_EXPANSION_LEVEL_CURRENT))
    add(lines, "locale=" .. fmt(GetLocale and GetLocale()))
    add(lines, "player guid=" .. fmt(UnitGUID and UnitGUID("player")) .. " name=" .. fmt(UnitName and UnitName("player")))
end

local function apiSection(lines)
    for _, path in ipairs(CANDIDATE_APIS) do
        add(lines, string.format("%-52s %s", path, type(resolve(path)) == "function" and "yes" or "NO"))
    end
end

local function guildSection(lines)
    add(lines, "IsInGuild: " .. callAll(IsInGuild))
    add(lines, "GetGuildInfo(player): " .. callAll(GetGuildInfo, "player"))
    add(lines, "GetNumGuildMembers: " .. callAll(GetNumGuildMembers))
    if GetGuildRosterShowOffline then add(lines, "GetGuildRosterShowOffline: " .. callAll(GetGuildRosterShowOffline)) end
    add(lines, "(GetGuildRosterInfo, first 2 members, every return value)")
    for i = 1, 2 do
        add(lines, "  [" .. i .. "] " .. callAll(GetGuildRosterInfo, i))
    end
end

-- Members picked for a full field dump: yourself, the first few, some with profession
-- data and some without, so the report shows what both look like.
local function pickSamples(clubId, memberIds)
    local chosen, seen = {}, {}
    local function take(id, why)
        if id and not seen[id] and #chosen < 20 then
            seen[id] = true
            chosen[#chosen + 1] = { id = id, why = why }
        end
    end
    local myGuid = UnitGUID and UnitGUID("player")
    local withProfessions, without = 0, 0
    for index, id in ipairs(memberIds) do
        local ok, info = pcall(C_Club.GetMemberInfo, clubId, id)
        if ok and type(info) == "table" then
            if myGuid and info.guid == myGuid then take(id, "you") end
            if index <= SAMPLE_FIRST then take(id, "first") end
            if info.profession1ID and withProfessions < SAMPLE_WITH_PROFESSIONS then
                withProfessions = withProfessions + 1
                take(id, "has profession1ID")
            elseif not info.profession1ID and without < SAMPLE_WITHOUT then
                without = without + 1
                take(id, "no profession1ID")
            end
        end
    end
    return chosen
end

local function clubSection(lines)
    if not (C_Club and C_Club.GetGuildClubId) then add(lines, "C_Club is missing") return end
    local ok, clubId = pcall(C_Club.GetGuildClubId)
    add(lines, "GetGuildClubId: " .. (ok and fmt(clubId) or "ERROR " .. fmt(clubId)))
    if not (ok and clubId) then return end
    if C_Club.GetClubInfo then add(lines, "GetClubInfo: " .. callAll(C_Club.GetClubInfo, clubId)) end
    if C_Club.GetMemberInfoForSelf then
        add(lines, "GetMemberInfoForSelf: " .. callAll(C_Club.GetMemberInfoForSelf, clubId))
    end

    local okIds, ids = pcall(C_Club.GetClubMembers, clubId)
    if not (okIds and type(ids) == "table") then add(lines, "GetClubMembers: " .. fmt(ids)) return end
    add(lines, "GetClubMembers: " .. #ids .. " members")

    -- Across every member: which fields exist, how many have professions, which ranks occur.
    local fieldCounts, rankCounts, withId, withRank, withName = {}, {}, 0, 0, 0
    local readErrors = 0
    for _, id in ipairs(ids) do
        local okInfo, info = pcall(C_Club.GetMemberInfo, clubId, id)
        if okInfo and type(info) == "table" then
            for key in pairs(info) do fieldCounts[key] = (fieldCounts[key] or 0) + 1 end
            for slot = 1, 2 do
                if info["profession" .. slot .. "ID"] then withId = withId + 1 end
                if info["profession" .. slot .. "Name"] then withName = withName + 1 end
                local rank = info["profession" .. slot .. "Rank"]
                if rank ~= nil then
                    withRank = withRank + 1
                    local key = fmt(rank)
                    rankCounts[key] = (rankCounts[key] or 0) + 1
                end
            end
        else
            readErrors = readErrors + 1
        end
    end
    add(lines, "members whose GetMemberInfo failed or was not a table: " .. readErrors)
    add(lines, "profession slots with ID / Name / Rank: " .. withId .. " / " .. withName .. " / " .. withRank)
    local rankParts = {}
    for _, key in ipairs(sortedKeys(rankCounts)) do rankParts[#rankParts + 1] = key .. " x" .. rankCounts[key] end
    add(lines, "profession rank values seen: " .. (#rankParts > 0 and table.concat(rankParts, ", ") or "none"))
    local fieldParts = {}
    for _, key in ipairs(sortedKeys(fieldCounts)) do fieldParts[#fieldParts + 1] = key .. " x" .. fieldCounts[key] end
    add(lines, "fields present on members: " .. table.concat(fieldParts, ", "))

    add(lines, "(full GetMemberInfo dumps)")
    for _, sample in ipairs(pickSamples(clubId, ids)) do
        local okInfo, info = pcall(C_Club.GetMemberInfo, clubId, sample.id)
        add(lines, "  member " .. fmt(sample.id) .. " (" .. sample.why .. "): " .. (okInfo and fmt(info) or "ERROR"))
        if okInfo and type(info) == "table" and ns.Roster then
            add(lines, "    as GuildCensus reads it: " .. fmt(ns.Roster.ProfessionsFromInfo(info)))
        end
    end
end

-- Your own professions through every API that might report skill level.
local function selfSkillSection(lines)
    if GetNumSkillLines and GetSkillLineInfo then
        local okCount, count = pcall(GetNumSkillLines)
        add(lines, "GetNumSkillLines: " .. fmt(count) .. " (non-header lines, every return)")
        if okCount and type(count) == "number" then
            for i = 1, math.min(count, SKILL_LINES) do
                add(lines, "  [" .. i .. "] " .. callAll(GetSkillLineInfo, i))
            end
        end
    end
    if GetProfessions and GetProfessionInfo then
        add(lines, "GetProfessions: " .. callAll(GetProfessions))
        local ok, indexes = safe(GetProfessions)
        if ok then
            for slot = 1, 5 do
                if indexes[slot] then add(lines, "  GetProfessionInfo(" .. indexes[slot] .. "): " .. callAll(GetProfessionInfo, indexes[slot])) end
            end
        end
    end
    local tradeSkillUI = C_TradeSkillUI
    if tradeSkillUI and tradeSkillUI.GetAllProfessionTradeSkillLines then
        local ok, lineIds = pcall(tradeSkillUI.GetAllProfessionTradeSkillLines)
        add(lines, "C_TradeSkillUI.GetAllProfessionTradeSkillLines: " .. fmt(ok and lineIds or "ERROR"))
        if ok and type(lineIds) == "table" and tradeSkillUI.GetProfessionInfoBySkillLineID then
            for _, lineId in ipairs(lineIds) do
                add(lines, "  GetProfessionInfoBySkillLineID(" .. fmt(lineId) .. "): " ..
                    callAll(tradeSkillUI.GetProfessionInfoBySkillLineID, lineId))
            end
        end
    end
    if GetTradeSkillLine then add(lines, "GetTradeSkillLine: " .. callAll(GetTradeSkillLine)) end
end

-- The old guild professions window API: crafters per profession, with a skill level.
local function guildTradeSkillSection(lines)
    if not GetNumGuildTradeSkill then add(lines, "GetNumGuildTradeSkill is missing") return end
    add(lines, "GetNumGuildTradeSkill: " .. callAll(GetNumGuildTradeSkill))
    if GetGuildTradeSkillView then add(lines, "GetGuildTradeSkillView: " .. callAll(GetGuildTradeSkillView)) end
    if GetGuildTradeSkillInfo then
        add(lines, "(GetGuildTradeSkillInfo rows, every return)")
        local ok, count = pcall(GetNumGuildTradeSkill)
        if ok and type(count) == "number" then
            for i = 1, math.min(count, TRADESKILL_ROWS) do
                add(lines, "  [" .. i .. "] " .. callAll(GetGuildTradeSkillInfo, i))
            end
        end
    end
end

local function pipelineSection(lines)
    local club = ns.Roster.ReadClubProfessions()
    local byName = 0
    for _ in pairs(club.byName) do byName = byName + 1 end
    add(lines, "Roster.ReadClubProfessions: " .. byName .. " members with tracked professions")
    local members = ns.Roster.Read()
    local withSkill = 0
    for _, member in ipairs(members) do
        for _, entry in ipairs(member.professions or {}) do
            if entry.skill then withSkill = withSkill + 1 end
        end
    end
    add(lines, "Roster.Read: " .. #members .. " members, " .. withSkill .. " professions with a skill level")
end

-- Builds the report as a list of lines.
function Debug.Report()
    local lines = {}
    guarded(lines, "Client", function() clientSection(lines) end)
    guarded(lines, "API availability", function() apiSection(lines) end)
    guarded(lines, "Guild roster", function() guildSection(lines) end)
    guarded(lines, "C_Club guild club (what GuildCensus reads)", function() clubSection(lines) end)
    guarded(lines, "Your own professions (skill level sources)", function() selfSkillSection(lines) end)
    guarded(lines, "Guild trade skill window API", function() guildTradeSkillSection(lines) end)
    guarded(lines, "GuildCensus pipeline", function() pipelineSection(lines) end)
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
