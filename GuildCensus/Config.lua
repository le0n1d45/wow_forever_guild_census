local _, ns = ...

local Config = {}
ns.Config = Config

-- Detection rules shown in the settings panel. `default` is a comma-separated
-- keyword list; `label` is what charts and the panel display. Keywords match whole
-- words only (see Parser.FirstMatch), so the defaults list the abbreviations players
-- write ("lw", "bs", "heal") AND the full words ("leatherworking", "healer").
-- `replaces` lists older defaults: a saved value that still equals one was never
-- edited, so Config.Init upgrades it to the current default (edited values are left
-- alone).
Config.ROLES = {
    {
        key = "tank",
        label = "Tank",
        default = "tank, tanks, tanking, bear, prot, protection",
        replaces = { "tank,bear,prot" },
    },
    {
        key = "healer",
        label = "Healer",
        default = "heal, heals, healer, healers, healing, resto, restoration, holy, disc, discipline",
        replaces = { "heal,resto,holy,disc" },
    },
    {
        key = "dps",
        label = "DPS",
        default = "dps, damage, fury, arms, ret, retribution, feral, cat, kitty, balance, moonkin, crit-chicken, enh, enhancement, ele, enhance, elemental, shadow, shockadin",
        replaces = {
            "dps, fury, arms, ret, feral, cat, kitty, balance, moonkin, crit-chicken, enh, ele, enhance, elemental, shadow, shockadin",
        },
    },
}

Config.PROFESSIONS = {
    {
        key = "leatherworking",
        label = "Leatherworking",
        default = "lw, leatherworking, leatherworker",
        replaces = { "lw, leatherworker" },
    },
    { key = "skinning", label = "Skinning", default = "skinning, skinner" },
    { key = "mining", label = "Mining", default = "mining, miner" },
    {
        key = "herbalism",
        label = "Herbalism",
        default = "herb, herbs, herbalism, herbalist",
        replaces = { "herb, herbalism, herbs" },
    },
    {
        key = "enchanting",
        label = "Enchanting",
        default = "ench, enchanting, enchanter",
        replaces = { "ench, enchanting" },
    },
    {
        key = "blacksmith",
        label = "Blacksmith",
        default = "bs, blacksmith, blacksmithing, armorsmith, armorsmithing, weaponsmith, weaponsmithing",
        replaces = { "bs, blacksmith, armorsmith, weaponsmith" },
    },
    {
        key = "engineering",
        label = "Engineering",
        default = "engi, engineer, engineering",
        replaces = { "engi, engineering" },
    },
    { key = "tailor", label = "Tailor", default = "tailor, tailoring" },
    {
        key = "alchemy",
        label = "Alchemy",
        default = "alch, alchemy, alchemist",
        replaces = { "alch, alchemy" },
    },
}

-- Notes matching "alt" keywords mark alts; "main" keywords mark declared mains.
Config.IDENTITY = {
    { key = "main", label = "Main", default = "main, mains", replaces = { "main" } },
    { key = "alt", label = "Alt", default = "alt, alts", replaces = { "alt" } },
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

-- Replaces saved values that still equal an older default (see `replaces` above).
local function upgradeOldDefaults(settings)
    for group, defs in pairs({
        identity = Config.IDENTITY, roles = Config.ROLES, professions = Config.PROFESSIONS,
    }) do
        for _, def in ipairs(defs) do
            for _, old in ipairs(def.replaces or {}) do
                if settings[group][def.key] == old then
                    settings[group][def.key] = def.default
                end
            end
        end
    end
end

-- Fills any missing settings in the saved DB (keeping user edits, including
-- deliberately emptied boxes), upgrades untouched old defaults, and returns the
-- settings table.
function Config.Init(db)
    if type(db.settings) ~= "table" then db.settings = {} end
    fillDefaults(db.settings)
    upgradeOldDefaults(db.settings)
    return db.settings
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
