local addonName, ns = ...

local DB_DEFAULTS = {
    version = 1,
}

local frame = CreateFrame("Frame", addonName .. "EventFrame")
local handlers = {}

function handlers.ADDON_LOADED(loadedName)
    if loadedName ~= addonName then return end

    GuildCensusDB = GuildCensusDB or {}
    for key, value in pairs(DB_DEFAULTS) do
        if GuildCensusDB[key] == nil then
            GuildCensusDB[key] = value
        end
    end
    ns.db = GuildCensusDB
    ns.settings = ns.Config.Init(GuildCensusDB)
    ns.Options.Register()

    frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.GUILD_ROSTER_UPDATE()
    ns.UI.Refresh()
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then handler(...) end
end)

for event in pairs(handlers) do
    frame:RegisterEvent(event)
end

SLASH_GUILDCENSUS1 = "/gcensus"
SLASH_GUILDCENSUS2 = "/guildcensus"
SlashCmdList["GUILDCENSUS"] = function(msg)
    local command = strtrim(msg or ""):lower()
    if command == "config" or command == "options" or command == "settings" then
        ns.Options.Open()
        return
    end
    if command == "logs" then
        ns.UI.SelectTab("logs")
        return
    end
    if command == "demo" then
        ns.demoMode = not ns.demoMode
        ns.UI.Show()
        return
    end
    ns.UI.Toggle()
end
