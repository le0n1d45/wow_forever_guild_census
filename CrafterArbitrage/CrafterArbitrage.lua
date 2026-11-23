local addonName, ns = ...

-- /carb: finds crafts that pay, from a scan of the auction house. This file sets up the saved settings and
-- connects the game's events and the slash command to the modules.

local DEFAULTS = { channel = "vendor", filter = "known", neutral = false, useBags = false, minProfit = 100 }
local FILTER_NAMES = { known = true, learnable = true, all = true }

function ns.Print(text)
    print("|cff66ccffCrafterArbitrage:|r " .. text)
end

-- The vendor sell price the game knows, for items the generated data lacks (items new to Forever).
function ns.LiveSellPrice(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local price = select(11, get(itemID))
    return price
end

local handlers = {}

function handlers.ADDON_LOADED(loadedName)
    if loadedName ~= addonName then return end
    CrafterArbitrageDB = CrafterArbitrageDB or {}
    local db = CrafterArbitrageDB
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    if not FILTER_NAMES[db.filter] then db.filter = DEFAULTS.filter end
    if db.channel ~= "ah" then db.channel = "vendor" end
    ns.db, ns.settings = db, db
    ns.Prices.Import(db.scan)
    local ok, err = pcall(ns.MinimapButton.Create) -- a problem with the button must not stop the rest of the addon
    if not ok then ns.Print("the minimap button could not be created: " .. tostring(err)) end
    ns.frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.AUCTION_HOUSE_SHOW() ns.Scanner.OnShow() end
function handlers.AUCTION_HOUSE_CLOSED() ns.Scanner.OnClosed() end
function handlers.REPLICATE_ITEM_LIST_UPDATE() ns.Scanner.OnListUpdate() end
function handlers.AUCTION_ITEM_LIST_UPDATE() ns.Scanner.OnListUpdate() end

local frame = CreateFrame("Frame", "CrafterArbitrageEventFrame")
ns.frame = frame
-- A client that lacks one of the auction house events (the modern or the classic one) raises an error when it is
-- registered; skip that event instead of losing the rest of the addon.
for event in pairs(handlers) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)
frame:SetScript("OnUpdate", function(_, elapsed) ns.Scanner.OnUpdate(elapsed) end)

local function status()
    local s = ns.settings
    ns.Print(string.format("selling to %s, recipes: %s%s%s.", s.channel == "ah" and "the Auction House" or "a vendor", s.filter,
        s.neutral and ", neutral AH" or "", s.useBags and ", using bag reagents" or ""))
    ns.Print(ns.Prices.HasScan() and ("last scan " .. ns.Format.Age(time() - ns.Prices.ScanTime()) .. ".") or "no scan yet.")
end

local function slash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    local s = ns.settings
    if cmd == "" then
        ns.UI.Toggle()
    elseif cmd == "scan" then
        ns.Scanner.Start()
    elseif cmd == "ah" or cmd == "vendor" then
        s.channel = cmd
        if ns.UI.Window() then ns.UI.Recompute() end
        status()
    elseif cmd == "filter" and FILTER_NAMES[arg] then
        s.filter = arg
        if ns.UI.Window() then ns.UI.Recompute() end
        status()
    elseif cmd == "neutral" then
        s.neutral = arg ~= "off"
        status()
    elseif cmd == "minimap" then
        s.minimapHide = arg == "off"
        ns.MinimapButton.Refresh()
        ns.Print("minimap button " .. (s.minimapHide and "hidden." or "shown."))
    elseif cmd == "status" then
        status()
    else
        ns.Print("/carb opens the window. /carb scan, /carb ah, /carb vendor, /carb filter known|learnable|all, /carb neutral on|off, /carb minimap on|off, /carb status.")
    end
end

SLASH_CRAFTERARBITRAGE1 = "/carb"
SLASH_CRAFTERARBITRAGE2 = "/crafterarbitrage"
SlashCmdList["CRAFTERARBITRAGE"] = slash
