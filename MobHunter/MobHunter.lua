local addonName, ns = ...

local frame = CreateFrame("Frame", addonName .. "EventFrame")
local handlers = {}

function handlers.ADDON_LOADED(loadedName)
    if loadedName ~= addonName then return end
    frame:UnregisterEvent("ADDON_LOADED")
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then handler(...) end
end)

for event in pairs(handlers) do
    frame:RegisterEvent(event)
end

SLASH_MOBHUNTER1 = "/mobhunter"
SlashCmdList["MOBHUNTER"] = function()
    print("MobHunter is loaded.")
end
