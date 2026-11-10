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
    ns.Comms.Init()

    frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.GUILD_ROSTER_UPDATE()
    ns.UI.Refresh()
end

function handlers.PLAYER_LOGIN()
    ns.Comms.OnLogin()
end

function handlers.CHAT_MSG_ADDON(...)
    ns.Comms.OnMessage(...)
end

function handlers.SKILL_LINES_CHANGED()
    ns.Comms.OnSkillsChanged()
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then handler(...) end
end)

for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event) -- an event this client doesn't have must not stop the rest
end

SLASH_GUILDCENSUS1 = "/gcensus"
SLASH_GUILDCENSUS2 = "/guildcensus"
SlashCmdList["GUILDCENSUS"] = function(msg)
    local command = strtrim(msg or ""):lower()
    if command == "config" or command == "options" or command == "settings" then
        ns.Options.Open()
        return
    end
    if command == "roles" or command == "finder" then
        ns.UI.SelectTab("roles")
        return
    end
    if command == "professions" then
        ns.UI.SelectTab("professions")
        return
    end
    if command == "logs" then
        ns.UI.SelectTab("logs")
        return
    end
    if command == "comms" then
        ns.Comms.Broadcast()
        for _, line in ipairs(ns.Comms.Status()) do print("|cff33ff99GuildCensus:|r " .. line) end
        return
    end
    if command == "debug" then
        ns.Debug.Show()
        return
    end
    if command == "demo" then
        ns.demoMode = not ns.demoMode
        ns.UI.Show()
        return
    end
    ns.UI.Toggle()
end
