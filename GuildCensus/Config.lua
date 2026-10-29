local _, ns = ...

local Config = {}
ns.Config = Config

-- Detection rules shown in the settings panel. `default` is a comma-separated
-- keyword list; `label` is what charts and the panel display.
Config.ROLES = {
    { key = "tank", label = "Tank", default = "tank,bear,prot" },
    { key = "healer", label = "Healer", default = "heal,resto,holy,disc" },
    {
        key = "dps",
        label = "DPS",
        default = "dps, fury, arms, ret, feral, cat, kitty, balance, moonkin, crit-chicken, enh, ele, enhance, elemental, shadow, shockadin",
    },
}

Config.PROFESSIONS = {
    { key = "leatherworking", label = "Leatherworking", default = "lw, leatherworker" },
    { key = "skinning", label = "Skinning", default = "skinning, skinner" },
    { key = "mining", label = "Mining", default = "mining, miner" },
    { key = "herbalism", label = "Herbalism", default = "herb, herbalism, herbs" },
    { key = "enchanting", label = "Enchanting", default = "ench, enchanting" },
    { key = "blacksmith", label = "Blacksmith", default = "bs, blacksmith, armorsmith, weaponsmith" },
    { key = "engineering", label = "Engineering", default = "engi, engineering" },
    { key = "tailor", label = "Tailor", default = "tailor, tailoring" },
    { key = "alchemy", label = "Alchemy", default = "alch, alchemy" },
}

-- Notes matching "alt" keywords mark alts; "main" keywords mark declared mains.
Config.IDENTITY = {
    { key = "main", label = "Main", default = "main" },
    { key = "alt", label = "Alt", default = "alt" },
}

local function fillDefaults(settings)
    if settings.includeAlts == nil then settings.includeAlts = true end
    if settings.onlyMains == nil then settings.onlyMains = false end
    settings.identity = settings.identity or {}
    for _, def in ipairs(Config.IDENTITY) do
        if settings.identity[def.key] == nil then settings.identity[def.key] = def.default end
    end
    settings.roles = settings.roles or {}
    settings.professions = settings.professions or {}
    for _, def in ipairs(Config.ROLES) do
        if settings.roles[def.key] == nil then settings.roles[def.key] = def.default end
    end
    for _, def in ipairs(Config.PROFESSIONS) do
        if settings.professions[def.key] == nil then settings.professions[def.key] = def.default end
    end
    return settings
end

function Config.Defaults()
    return fillDefaults({})
end

-- Fills any missing settings in the saved DB (keeping user edits, including
-- deliberately emptied boxes) and returns the settings table.
function Config.Init(db)
    if type(db.settings) ~= "table" then db.settings = {} end
    return fillDefaults(db.settings)
end

-- Resets a settings table to defaults in place, so existing references stay valid.
function Config.Reset(settings)
    settings.includeAlts = nil
    settings.onlyMains = nil
    settings.identity = {}
    settings.roles = {}
    settings.professions = {}
    fillDefaults(settings)
end
