local addonName, ns = ...

-- Reads the auction house's full listing into the price index (Prices). The game allows one full scan per
-- account every 15 minutes, so the addon also reads a scan another addon (Auctionator...) asked for.
--  * Modern auction house: C_AuctionHouse.ReplicateItems, then REPLICATE_ITEM_LIST_UPDATE
--  * Classic auction house: QueryAuctionItems(getAll), then AUCTION_ITEM_LIST_UPDATE
-- The server sends the listing in batches, so a scan counts as complete once the number of auctions has stayed
-- the same for STABLE_SECONDS.

local Scanner = { state = "idle" }
ns.Scanner = Scanner

local SERVER_LIMIT = 15 * 60 -- seconds between full scans
local STABLE_SECONDS = 4
local TIMEOUT = 120 -- give up waiting for the server
local BATCH = 300 -- auctions read per frame

local ahOpen = false
local relevant -- itemID -> true for every item a recipe makes or uses

local function relevantItems()
    if not relevant then
        relevant = {}
        for _, prof in pairs(ns.Data or {}) do
            for _, recipe in pairs(prof.recipes or {}) do
                relevant[recipe.out[1]] = true
                for _, reagent in ipairs(recipe.r) do relevant[reagent[1]] = true end
            end
        end
    end
    return relevant
end
function Scanner.ResetRelevant() relevant = nil end

local function say(text) if ns.Print then ns.Print(text) end end

local function setStatus(text)
    Scanner.statusText = text
    if ns.OnScanStatus then ns.OnScanStatus(text) end
end

-- The two auction house APIs, each as { count = fn, get = fn(i) -> itemID, units, buyout }.
local function modernAPI()
    local ah = C_AuctionHouse
    if not (ah and ah.GetNumReplicateItems and ah.GetReplicateItemInfo) then return nil end
    return {
        request = function() ah.ReplicateItems() end,
        count = function() return ah.GetNumReplicateItems() end,
        base = 1, -- replicate items are numbered from 0
        get = function(i)
            local info = { ah.GetReplicateItemInfo(i) }
            return info[17], info[3], info[10] -- itemID, count, buyoutPrice
        end,
    }
end

local function classicAPI()
    if not (QueryAuctionItems and GetNumAuctionItems and GetAuctionItemInfo) then return nil end
    return {
        request = function() QueryAuctionItems("", nil, nil, 0, false, 0, true) end,
        count = function() return (GetNumAuctionItems("list")) end,
        get = function(i)
            local info = { GetAuctionItemInfo("list", i) }
            return info[17], info[3], info[10]
        end,
    }
end

local function api()
    return modernAPI() or classicAPI()
end

function Scanner.IsAuctionHouseOpen() return ahOpen end

function Scanner.SecondsUntilNextScan()
    local db = ns.db
    local last = db and db.lastScanRequest
    if not last then return 0 end
    return math.max(0, SERVER_LIMIT - (time() - last))
end

local function markRequested()
    if ns.db then ns.db.lastScanRequest = time() end
end

function Scanner.IsBusy() return Scanner.state ~= "idle" end

-- The Scan button.
function Scanner.Start()
    if Scanner.IsBusy() then say("A scan is already running.") return false end
    if not ahOpen then say("Open the Auction House to scan it.") return false end
    local wait = Scanner.SecondsUntilNextScan()
    if wait > 0 then
        local msg = string.format("The server allows one full scan every 15 minutes: you can scan again in %d:%02d.",
            math.floor(wait / 60), wait % 60)
        say(msg)
        setStatus(msg)
        return false
    end
    local client = api()
    if not client then say("This client has no auction house scan call the addon knows.") return false end
    Scanner.client = client
    markRequested()
    Scanner.state, Scanner.waited, Scanner.lastCount, Scanner.stable = "waiting", 0, -1, 0
    setStatus("Waiting for the server...")
    client.request()
    return true
end

-- An auction list update arrived: ours, or another addon's scan.
function Scanner.OnListUpdate()
    if not ahOpen then return end
    if Scanner.state == "reading" then return end
    if Scanner.state == "idle" then
        local client = api()
        if not client or (client.count() or 0) == 0 then return end
        Scanner.client = client
        markRequested() -- someone else used the server's scan
    end
    Scanner.state, Scanner.waited, Scanner.stable = "waiting", 0, 0
    Scanner.lastCount = -1
end

function Scanner.OnShow() ahOpen = true end

function Scanner.OnClosed()
    ahOpen = false
    if Scanner.state ~= "idle" then
        Scanner.state = "idle"
        setStatus("Scan stopped: the Auction House was closed.")
    end
end

local function finish()
    ns.Prices.Build(Scanner.auctions, time())
    if ns.db then ns.db.scan = ns.Prices.Export() end
    local kept = #Scanner.auctions
    Scanner.auctions, Scanner.state = nil, "idle"
    setStatus(string.format("Scanned %d listings of items crafts use.", kept))
    if ns.OnScanDone then ns.OnScanDone() end
end

-- Called every frame with the seconds since the last call.
function Scanner.OnUpdate(elapsed)
    local state = Scanner.state
    if state == "idle" then return end
    if state == "waiting" then
        Scanner.waited = Scanner.waited + elapsed
        local count = Scanner.client.count() or 0
        if count > 0 and count == Scanner.lastCount then
            Scanner.stable = Scanner.stable + elapsed
        else
            Scanner.stable, Scanner.lastCount = 0, count
        end
        if count > 0 and Scanner.stable >= STABLE_SECONDS then
            Scanner.state, Scanner.index, Scanner.total, Scanner.auctions = "reading", 0, count, {}
            setStatus("Reading the listings...")
        elseif Scanner.waited >= TIMEOUT then
            Scanner.state = "idle"
            setStatus("The server did not answer the scan.")
        end
        return
    end
    -- reading
    local items = relevantItems()
    local last = math.min(Scanner.index + BATCH, Scanner.total)
    for i = Scanner.index + 1, last do
        local itemID, units, buyout = Scanner.client.get(i - (Scanner.client.base or 0))
        if itemID and items[itemID] then Scanner.auctions[#Scanner.auctions + 1] = { itemID, units, buyout } end
    end
    Scanner.index = last
    if Scanner.index >= Scanner.total then finish() end
end

