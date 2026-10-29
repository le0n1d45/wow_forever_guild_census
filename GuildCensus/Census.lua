local _, ns = ...

local Census = {}
ns.Census = Census

Census.LEVEL_BUCKET_SIZE = 10
Census.MAX_PROFESSIONS = 2

-- Classes with no tank or healer spec are counted as DPS without needing a note.
local PURE_DPS_CLASSES = { WARLOCK = true, HUNTER = true, MAGE = true, ROGUE = true }

-- Roles a class can never fill. Only classes where this is clear-cut are listed, so
-- a conflict means the note (or a keyword) is wrong. Hybrids that can do all three,
-- or that can plausibly tank/heal off-spec, are deliberately left out.
local CLASS_ROLES = {
    WARRIOR = { tank = true, dps = true },
    PRIEST = { healer = true, dps = true },
    WARLOCK = { dps = true },
    HUNTER = { dps = true },
    MAGE = { dps = true },
    ROGUE = { dps = true },
}

local function increment(counts, key)
    counts[key] = (counts[key] or 0) + 1
end

local function bucketLabel(level)
    local size = Census.LEVEL_BUCKET_SIZE
    local low = math.floor((level - 1) / size) * size + 1
    return low .. "-" .. (low + size - 1), low
end

local function labelFor(defs, key)
    for _, def in ipairs(defs) do
        if def.key == key then return def.label end
    end
end

-- Converts a { key = count } map into a list of slices sorted by count desc,
-- then label asc for a stable order. `sortKey` optionally overrides ordering.
local function toSlices(counts, sortKey)
    local slices = {}
    for label, count in pairs(counts) do
        slices[#slices + 1] = { label = label, count = count }
    end
    table.sort(slices, function(a, b)
        if sortKey then return sortKey(a) < sortKey(b) end
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    return slices
end

-- "Mining ('miner'), Tailor ('tailor')"
local function describeHits(hits)
    local parts = {}
    for _, hit in ipairs(hits) do
        parts[#parts + 1] = string.format("%s ('%s')", hit.label, hit.word)
    end
    return table.concat(parts, ", ")
end

local function addConflict(conflicts, member, kind, message)
    conflicts[#conflicts + 1] = {
        name = member.name or "?",
        level = member.level,
        className = member.className,
        note = member.note or "",
        kind = kind,
        message = message,
    }
end

-- Flags notes whose detection results can't all be true, so keywords can be tuned.
-- Holding all three roles is NOT a conflict: some classes can do all three.
local function detectConflicts(conflicts, member, mainWord, altWord, roleHits, professionHits)
    if mainWord and altWord then
        addConflict(conflicts, member, "main-and-alt",
            string.format("Detected as both a main ('%s') and an alt ('%s')", mainWord, altWord))
    end

    if #professionHits > Census.MAX_PROFESSIONS then
        addConflict(conflicts, member, "too-many-professions",
            string.format("%d professions detected (max %d): %s",
                #professionHits, Census.MAX_PROFESSIONS, describeHits(professionHits)))
    end

    local allowed = CLASS_ROLES[member.classFile]
    if allowed then
        for _, hit in ipairs(roleHits) do
            if not allowed[hit.key] then
                addConflict(conflicts, member, "role-class-mismatch",
                    string.format("%s cannot fill the %s role, but the note matched '%s'",
                        member.className or member.classFile, hit.label, hit.word))
            end
        end
    end
end

-- members: list of { name, level, classFile, className, note }
-- settings: Config settings table (defaults when omitted)
-- Returns { total, roles, professions, classes, levels, conflicts }. The chart
-- fields are slice lists; conflicts are computed over ALL members regardless of
-- the alt/main filters, since their purpose is tuning detection.
function Census.Build(members, settings)
    settings = settings or ns.Config.Defaults()
    local roleRules = ns.Parser.Compile(ns.Config.ROLES, settings.roles)
    local professionRules = ns.Parser.Compile(ns.Config.PROFESSIONS, settings.professions)
    local dpsLabel = labelFor(ns.Config.ROLES, "dps")

    local identity = {}
    for _, rule in ipairs(ns.Parser.Compile(ns.Config.IDENTITY, settings.identity)) do
        identity[rule.key] = rule.words
    end

    local roles, professions, classes, levels = {}, {}, {}, {}
    local levelOrder, classNames = {}, {}
    local conflicts, total = {}, 0

    for _, member in ipairs(members) do
        local mainWord = ns.Parser.FirstMatch(member.note, identity.main)
        local altWord = ns.Parser.FirstMatch(member.note, identity.alt)
        local roleHits = ns.Parser.Detect(member.note, roleRules)
        local professionHits = ns.Parser.Detect(member.note, professionRules)

        detectConflicts(conflicts, member, mainWord, altWord, roleHits, professionHits)

        -- "Only mains" additionally requires a declared main, on top of the alts filter.
        local altOk = settings.includeAlts ~= false or not altWord
        local mainOk = not settings.onlyMains or mainWord
        if altOk and mainOk then
            total = total + 1

            local hasDps = false
            for _, hit in ipairs(roleHits) do
                increment(roles, hit.label)
                if hit.key == "dps" then hasDps = true end
            end
            if PURE_DPS_CLASSES[member.classFile] and not hasDps then
                increment(roles, dpsLabel)
            end

            for _, hit in ipairs(professionHits) do
                increment(professions, hit.label)
            end

            if member.classFile then
                increment(classes, member.classFile)
                if member.className then classNames[member.classFile] = member.className end
            end
            if member.level and member.level >= 1 then
                local label, low = bucketLabel(member.level)
                increment(levels, label)
                levelOrder[label] = low
            end
        end
    end

    local classSlices = toSlices(classes)
    for _, slice in ipairs(classSlices) do
        slice.classFile = slice.label
        slice.label = classNames[slice.label] or slice.label
    end

    table.sort(conflicts, function(a, b)
        local an, bn = string.lower(a.name), string.lower(b.name)
        if an ~= bn then return an < bn end
        return a.kind < b.kind
    end)

    return {
        memberCount = #members,
        total = total,
        roles = toSlices(roles),
        professions = toSlices(professions),
        classes = classSlices,
        levels = toSlices(levels, function(slice) return levelOrder[slice.label] end),
        conflicts = conflicts,
    }
end
