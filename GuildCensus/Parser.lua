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

local function isLetter(char)
    return char ~= "" and string.find(char, "^%a") ~= nil
end

-- Finds the next occurrence of `word` in `text` (both lowercase), at or after `init`,
-- that is a whole word: the letter at either edge of the keyword must not touch another
-- letter. Digits, punctuation and spaces count as boundaries, so "lw260" and "herb-251"
-- still match "lw" and "herb", while "bs" does not match inside "herbs". A keyword that
-- starts or ends with a non-letter (like a "+") has no boundary to check on that side.
-- Returns first, last, or nil.
local function findWord(text, word, init)
    if word == "" then return nil end
    local startsWithLetter = isLetter(string.sub(word, 1, 1))
    local endsWithLetter = isLetter(string.sub(word, -1))
    local first, last = string.find(text, word, init, true)
    while first do
        local before = string.sub(text, first - 1, first - 1)
        local after = string.sub(text, last + 1, last + 1)
        if (not startsWithLetter or not isLetter(before)) and (not endsWithLetter or not isLetter(after)) then
            return first, last
        end
        first, last = string.find(text, word, first + 1, true)
    end
    return nil
end

-- Returns the first keyword present in the note as a whole word, or nil. Matching is
-- case-insensitive; "heal" does not match "healer" (list "healer" too), and "bs" does
-- not match "herbs".
function Parser.FirstMatch(note, words)
    if type(note) ~= "string" or note == "" then return nil end
    local lowered = string.lower(note)
    for _, word in ipairs(words) do
        if findWord(lowered, word, 1) then return word end
    end
    return nil
end

function Parser.ContainsAny(note, words)
    return Parser.FirstMatch(note, words) ~= nil
end

-- Finds a skill level written right after any keyword, e.g. "LW 260", "BS: 310",
-- "mining (300)" or "alch-225". Only spaces and : = - ( [ may sit between the keyword
-- and the number, which must have 1-3 digits ("LW 260/300" reads as 260). Returns
-- the first one found, or nil.
function Parser.SkillAfter(note, words)
    if type(note) ~= "string" or note == "" then return nil end
    local lowered = string.lower(note)
    for _, word in ipairs(words) do
        local init = 1
        while true do
            local first, last = findWord(lowered, word, init)
            if not first then break end
            local digits = string.match(lowered, "^[%s:=%-%(%[]*(%d+)", last + 1)
            if digits and #digits <= 3 and tonumber(digits) >= 1 then
                return tonumber(digits)
            end
            init = first + 1
        end
    end
    return nil
end

-- Returns { key, label, word, skill } for every rule with a keyword present in the
-- note, where `word` is the keyword that matched. `skill` is only looked up (see
-- Parser.SkillAfter) when `withSkill` is true, and is nil when none is written.
function Parser.Detect(note, rules, withSkill)
    local hits = {}
    for _, rule in ipairs(rules) do
        local word = Parser.FirstMatch(note, rule.words)
        if word then
            hits[#hits + 1] = {
                key = rule.key, label = rule.label, word = word,
                skill = withSkill and Parser.SkillAfter(note, rule.words) or nil,
            }
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
