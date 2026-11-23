local addonName, ns = ...

-- Which recipes the player can make or could learn from a trainer.

local Known = {}
ns.Known = Known

-- The first-rank spell of each profession, whose name is the profession's name in the player's language.
local PROFESSION_SPELL = {
    [171] = 2259, [164] = 2018, [202] = 4036, [165] = 2108, [197] = 3908, [185] = 2550, [129] = 3273, [186] = 2575,
}

function Known.IsKnown(spell)
    if IsPlayerSpell and IsPlayerSpell(spell) then return true end
    if IsSpellKnown and IsSpellKnown(spell) then return true end
    return false
end

-- The player's skill in a profession (a skill line id), or nil when they do not have it.
function Known.SkillLevel(skillLine)
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
        if info and info.skillLevel and info.skillLevel > 0 then return info.skillLevel end
    end
    local spell = PROFESSION_SPELL[skillLine]
    local name = spell and GetSpellInfo and GetSpellInfo(spell)
    if name and GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, rank = GetSkillLineInfo(i)
            if not isHeader and skillName == name then return rank end
        end
    end
    return nil
end

-- "A" or "H" (nil when unknown).
function Known.Faction()
    local group = UnitFactionGroup and UnitFactionGroup("player")
    if group == "Alliance" then return "A" elseif group == "Horde" then return "H" end
end

-- Whether a class-restricted recipe is for this player's class.
local function classAllows(recipe)
    if not recipe.classMask or recipe.classMask == 0 then return true end
    local classID = select(3, UnitClass("player"))
    if not classID then return true end
    return math.floor(recipe.classMask / 2 ^ (classID - 1)) % 2 == 1
end

-- Whether some trainer of the recipe serves the player's faction.
local function trainerForFaction(recipe, faction)
    local trainers = ns.Data.Trainers or {}
    local any = false
    for _, npc in ipairs(recipe.trainers or {}) do
        local t = trainers[npc]
        any = true
        if not t or t[3] == "" or t[3] == "AH" or not faction or t[3] == faction then return true end
    end
    return not any
end

-- "known": the player knows it; "trainer": a trainer teaches it and the player has the skill for it now;
-- "other": anything else (needs a recipe item, a trainer asking more skill, a profession the player lacks...).
function Known.Status(skillLine, spell, recipe)
    if not classAllows(recipe) then return "other" end
    if Known.IsKnown(spell) then return "known" end
    if recipe.train then
        local skill = Known.SkillLevel(skillLine)
        if skill and skill >= recipe.train[1] and trainerForFaction(recipe, Known.Faction()) then return "trainer" end
    end
    return "other"
end
