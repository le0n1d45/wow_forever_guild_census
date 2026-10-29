local _, ns = ...

local Parser = {}
ns.Parser = Parser

-- "Tank, Bear ,,prot" -> { "tank", "bear", "prot" }
function Parser.ParseList(text)
    local words = {}
    if type(text) ~= "string" then return words end
    for item in string.gmatch(text, "[^,]+") do
        local word = string.match(string.lower(item), "^%s*(.-)%s*$")
        if word ~= "" then words[#words + 1] = word end
    end
    return words
end

-- defs: ordered list of { key, label, default } (Config.ROLES / Config.PROFESSIONS)
-- values: { [key] = "comma, separated" } from settings; a missing key uses the default.
function Parser.Compile(defs, values)
    local rules = {}
    for _, def in ipairs(defs) do
        local text = values and values[def.key]
        if text == nil then text = def.default end
        rules[#rules + 1] = { key = def.key, label = def.label, words = Parser.ParseList(text) }
    end
    return rules
end

-- Returns the first keyword present in the note, or nil. Matching is a
-- case-insensitive substring search, so "heal" matches "healer".
function Parser.FirstMatch(note, words)
    if type(note) ~= "string" or note == "" then return nil end
    local lowered = string.lower(note)
    for _, word in ipairs(words) do
        if string.find(lowered, word, 1, true) then return word end
    end
    return nil
end

function Parser.ContainsAny(note, words)
    return Parser.FirstMatch(note, words) ~= nil
end

-- Returns { key, label, word } for every rule with a keyword present in the
-- note, where `word` is the keyword that matched.
function Parser.Detect(note, rules)
    local hits = {}
    for _, rule in ipairs(rules) do
        local word = Parser.FirstMatch(note, rule.words)
        if word then
            hits[#hits + 1] = { key = rule.key, label = rule.label, word = word }
        end
    end
    return hits
end

-- Returns just the labels of every matching rule.
function Parser.Match(note, rules)
    local labels = {}
    for _, hit in ipairs(Parser.Detect(note, rules)) do
        labels[#labels + 1] = hit.label
    end
    return labels
end
