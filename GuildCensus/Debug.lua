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

-- Every guild/recipe/profession API the client has, to spot a request function we don't know yet.
local DISCOVERY_PATTERNS = { "Recipe", "Profession", "TradeSkill" }

local function discoverySection(lines)
    local function matches(name)
        for _, pattern in ipairs(DISCOVERY_PATTERNS) do
            if string.find(name, pattern, 1, true) then return true end
        end
    end
    local globals = {}
    for name, value in pairs(_G) do
        if type(name) == "string" and type(value) == "function" and matches(name) then globals[#globals + 1] = name end
    end
    table.sort(globals)
    add(lines, "global functions: " .. table.concat(globals, ", "))
    for _, tableName in ipairs({ "C_GuildInfo", "C_Club", "C_TradeSkillUI", "C_Professions" }) do
        local names = {}
        for name, value in pairs(type(_G[tableName]) == "table" and _G[tableName] or {}) do
            if type(value) == "function" and (tableName ~= "C_Club" or matches(name) or string.find(name, "Member", 1, true)) then
                names[#names + 1] = tostring(name)
            end
        end
        table.sort(names)
        add(lines, tableName .. ": " .. (#names > 0 and table.concat(names, ", ") or "(missing or empty)"))
    end
    local frames = {}
    for _, name in ipairs({ "GuildFrame", "GuildRosterFrame", "GuildFrameTab", "CommunitiesFrame", "FriendsFrame",
        "GuildInfoFrame", "GuildRosterContainer", "GuildTradeSkillFrame" }) do
        if _G[name] then frames[#frames + 1] = name end
    end
    add(lines, "frames present: " .. table.concat(frames, ", "))
end

-- The old guild professions window API: crafters per profession, with a skill level. Its
-- rows came back as collapsed headers only, so this tries the things that might fill it
-- (a roster refresh, expanding, collapsing, a recipe query), reading it after each step
-- and after a delay, and logs the events that fire meanwhile.
local function after(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

local function isHeaderRow(row) return row[8] == nil and row[4] ~= nil end

local function readRow(index)
    local packed = { pcall(GetGuildTradeSkillInfo, index) }
    if not table.remove(packed, 1) then return nil end
    return packed
end

local function rowCount()
    local ok, count = pcall(GetNumGuildTradeSkill)
    return ok and type(count) == "number" and count or 0
end

local function probe(lines, label)
    local headers, players, flags, samples = 0, 0, {}, {}
    local minSkill, maxSkill
    for i = 1, rowCount() do
        local row = readRow(i)
        if row then
            if isHeaderRow(row) then
                headers = headers + 1
                flags[#flags + 1] = tostring(row[4]) .. "=" .. tostring(row[2]) .. "/" .. tostring(row[7])
            else
                players = players + 1
                local skill = row[13]
                if type(skill) == "number" then
                    minSkill = minSkill and math.min(minSkill, skill) or skill
                    maxSkill = maxSkill and math.max(maxSkill, skill) or skill
                end
                if #samples < 6 then samples[#samples + 1] = "    " .. formatReturns(row, 16) end
            end
        end
    end
    add(lines, label .. ": count=" .. rowCount() .. " headers=" .. headers .. " player rows=" .. players ..
        " skill min/max " .. fmt(minSkill) .. "/" .. fmt(maxSkill))
    add(lines, "    headers (name=collapsedFlag/numPlayers): " .. table.concat(flags, ", "))
    for _, sample in ipairs(samples) do add(lines, sample) end
end

local function forEachHeader(fn, apply)
    for i = rowCount(), 1, -1 do -- last first, so earlier indexes stay valid
        local row = readRow(i)
        if row and isHeaderRow(row) then pcall(apply, i) end
    end
end

local function guildTradeSkillExperiment(lines, finish)
    section(lines, "Guild trade skill window API (experiments)")
    if not (GetNumGuildTradeSkill and GetGuildTradeSkillInfo) then
        add(lines, "GetNumGuildTradeSkill / GetGuildTradeSkillInfo missing")
        return finish()
    end
    local events, eventFrame = {}, CreateFrame("Frame")
    for _, event in ipairs({ "GUILD_TRADESKILL_UPDATE", "GUILD_RECIPE_KNOWN_BY_MEMBERS", "TRADE_SKILL_SHOW",
        "GUILD_ROSTER_UPDATE", "GUILD_RANKS_UPDATE", "TRADE_SKILL_LIST_UPDATE" }) do
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        local entry = events[event] or { count = 0 }
        events[event] = entry
        entry.count = entry.count + 1
        if entry.count == 1 then entry.args = formatReturns({ ... }, select("#", ...)) end
    end)

    local expand = ExpandGuildTradeSkillHeader
    local collapse = CollapseGuildTradeSkillHeader
    local steps = {
        function() probe(lines, "baseline") end,
        function()
            add(lines, "-- C_GuildInfo.GuildRoster()")
            if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        end,
        function() probe(lines, "2s after GuildRoster") end,
        function()
            add(lines, "-- ExpandGuildTradeSkillHeader on every header")
            if expand then forEachHeader(nil, expand) end
            probe(lines, "right after Expand")
        end,
        function() probe(lines, "2s after Expand") end,
        function()
            add(lines, "-- CollapseGuildTradeSkillHeader on every header")
            if collapse then forEachHeader(nil, collapse) end
            probe(lines, "right after Collapse")
        end,
        function() probe(lines, "2s after Collapse") end,
        function()
            local guid = UnitGUID and UnitGUID("player")
            add(lines, "-- C_GuildInfo.QueryGuildMemberRecipes(your guid, 393 Skinning)")
            if C_GuildInfo and C_GuildInfo.QueryGuildMemberRecipes then
                add(lines, "returned: " .. callAll(C_GuildInfo.QueryGuildMemberRecipes, guid, 393))
            end
        end,
        function() probe(lines, "3s after QueryGuildMemberRecipes") end,
        function()
            add(lines, "-- guild tradeskill switches and the Cataclysm-style recipe query")
            local function show(label, fn, ...)
                if type(fn) == "function" then add(lines, label .. ": " .. callAll(fn, ...)) else add(lines, label .. ": missing") end
            end
            show("C_TradeSkillUI.IsGuildTradeSkillsEnabled", C_TradeSkillUI and C_TradeSkillUI.IsGuildTradeSkillsEnabled)
            show("CanViewGuildRecipes(393)", CanViewGuildRecipes, 393)
            show("CanViewGuildRecipes(165)", CanViewGuildRecipes, 165)
            show("GetGuildRosterSelection", GetGuildRosterSelection)
            show("SetGuildTradeSkillItemNameFilter(nil)", SetGuildTradeSkillItemNameFilter, nil)
            show("SetGuildTradeSkillCategoryFilter(0)", SetGuildTradeSkillCategoryFilter, 0)
            show("QueryGuildRecipes", QueryGuildRecipes)
        end,
        function()
            probe(lines, "2s after QueryGuildRecipes and filter reset")
            local function show(label, fn, ...)
                if type(fn) == "function" then add(lines, label .. ": " .. callAll(fn, ...)) end
            end
            show("GetGuildRecipeInfoPostQuery", GetGuildRecipeInfoPostQuery)
            show("GetGuildRecipeMember(1)", GetGuildRecipeMember, 1)
            show("GetGuildMemberRecipes(your name, 393)", GetGuildMemberRecipes, "Graze Runner", 393)
            show("GetGuildMemberRecipes(your name)", GetGuildMemberRecipes, "Graze Runner")
            show("GetGuildMemberRecipes(your guid, 393)", GetGuildMemberRecipes, UnitGUID and UnitGUID("player"), 393)
            add(lines, "-- expand once more, now that the filters are reset")
            if expand then forEachHeader(nil, expand) end
            probe(lines, "after Expand (filters reset)")
            if collapse then forEachHeader(nil, collapse) end -- leave the headers as they were
        end,
    }
    local delays = { 0, 0, 2, 0, 2, 0, 2, 0, 3, 0, 2 } -- seconds to wait before each step
    local function run(index)
        if index > #steps then
            local names = {}
            for name in pairs(events) do names[#names + 1] = name end
            table.sort(names)
            add(lines, "events seen during the experiment:")
            for _, name in ipairs(names) do
                add(lines, "  " .. name .. " x" .. events[name].count .. ", first args: " .. events[name].args)
            end
            if #names == 0 then add(lines, "  none") end
            eventFrame:UnregisterAllEvents()
            return finish()
        end
        after(delays[index], function()
            local ok, err = pcall(steps[index])
            if not ok then add(lines, "STEP ERROR: " .. fmt(err)) end
            run(index + 1)
        end)
    end
    run(1)
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

-- Builds the report as a list of lines. The guild trade skill experiments wait for the
-- client between steps, so `done(lines)` is called when the whole report is ready (at once
-- on a client without C_Timer); the lines are also returned.
function Debug.Report(done)
    local lines = {}
    guarded(lines, "Client", function() clientSection(lines) end)
    guarded(lines, "API availability", function() apiSection(lines) end)
    guarded(lines, "API discovery", function() discoverySection(lines) end)
    guarded(lines, "Guild roster", function() guildSection(lines) end)
    guarded(lines, "C_Club guild club (what GuildCensus reads)", function() clubSection(lines) end)
    guarded(lines, "Your own professions (skill level sources)", function() selfSkillSection(lines) end)
    guarded(lines, "GuildCensus pipeline", function() pipelineSection(lines) end)
    local ok, err = pcall(guildTradeSkillExperiment, lines, function() if done then done(lines) end end)
    if not ok then
        add(lines, "EXPERIMENT ERROR: " .. fmt(err))
        if done then done(lines) end
    end
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
    print("|cff33ff99GuildCensus:|r collecting the debug report (about 12 seconds)...")
    Debug.Report(function(lines)
        if ns.db then ns.db.lastDebug = lines end -- also lands in GuildCensus.lua in WTF after /reload or logout
        showReport("Guild Census debug", table.concat(lines, "\n"))
        print("|cff33ff99GuildCensus:|r debug report is in the window (already selected: press Ctrl+C to copy). It is also saved to GuildCensus.lua in your WTF\\Account\\<account>\\SavedVariables folder after /reload.")
    end)
end
