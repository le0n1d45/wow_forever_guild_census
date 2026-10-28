local _, ns = ...

local Census = {}
ns.Census = Census

Census.LEVEL_BUCKET_SIZE = 10

local function increment(counts, key)
    counts[key] = (counts[key] or 0) + 1
end

local function bucketLabel(level)
    local size = Census.LEVEL_BUCKET_SIZE
    local low = math.floor((level - 1) / size) * size + 1
    return low .. "-" .. (low + size - 1), low
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

-- members: list of { level = number, classFile = string, className = string, note = string }
-- Returns { total, roles, professions, classes, levels }, each chart a slice list.
function Census.Build(members)
    local roles, professions, classes, levels = {}, {}, {}, {}
    local levelOrder = {}

    for _, member in ipairs(members) do
        for _, role in ipairs(ns.Parser.ParseRoles(member.note)) do
            increment(roles, role)
        end
        for _, profession in ipairs(ns.Parser.ParseProfessions(member.note)) do
            increment(professions, profession)
        end
        if member.classFile then
            increment(classes, member.classFile)
        end
        if member.level and member.level >= 1 then
            local label, low = bucketLabel(member.level)
            increment(levels, label)
            levelOrder[label] = low
        end
    end

    local classSlices = toSlices(classes)
    local classNames = {}
    for _, member in ipairs(members) do
        if member.classFile and member.className then
            classNames[member.classFile] = member.className
        end
    end
    for _, slice in ipairs(classSlices) do
        slice.classFile = slice.label
        slice.label = classNames[slice.label] or slice.label
    end

    return {
        total = #members,
        roles = toSlices(roles),
        professions = toSlices(professions),
        classes = classSlices,
        levels = toSlices(levels, function(slice) return levelOrder[slice.label] end),
    }
end
