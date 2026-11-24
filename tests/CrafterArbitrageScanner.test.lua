-- Scanner: reading the auction house's full listing into the price index.
return function()
    local printed, now
    local function load()
        now = 1000000
        time = function() return now end
        local ns = { Data = { Items = {}, Test = { recipes = { [1] = { out = { 11, 1 }, r = { { 10, 2 } } } } } }, db = {} }
        ns.Print = function(text) printed[#printed + 1] = text end
        for _, file in ipairs({ "Format.lua", "Prices.lua", "Calculator.lua", "Deals.lua", "Scanner.lua" }) do loadAddonFile(ns, file, "CrafterArbitrage") end
        return ns
    end

    -- listings: { itemID, count, buyout }; the modern API numbers them from 0.
    local function modern(listings)
        local requested = 0
        C_AuctionHouse = {
            ReplicateItems = function() requested = requested + 1 end,
            GetNumReplicateItems = function() return #listings end,
            GetReplicateItemInfo = function(i)
                local l = listings[i + 1]
                return "name", 0, l[2], 1, true, 1, 0, 0, 1, l[3], 0, false, "", "owner", "owner", 0, l[1], true
            end,
        }
        QueryAuctionItems, GetNumAuctionItems, GetAuctionItemInfo = nil, nil, nil
        return function() return requested end
    end

    local function classic(listings)
        local requested = 0
        C_AuctionHouse = nil
        QueryAuctionItems = function(_, _, _, _, _, _, getAll) assert(getAll == true) requested = requested + 1 end
        GetNumAuctionItems = function() return #listings, #listings end
        GetAuctionItemInfo = function(_, i)
            local l = listings[i]
            return "name", 0, l[2], 1, true, 1, 0, 0, 1, l[3], 0, false, "", "owner", "owner", 0, l[1], true
        end
        return function() return requested end
    end

    local function run(ns, seconds)
        for _ = 1, seconds do ns.Scanner.OnUpdate(1) end
    end

    describe("Scanner", function()
        it("will not scan with the auction house closed", function()
            printed = {}
            local ns = load()
            modern({})
            assertEqual(ns.Scanner.Start(), false)
            assert(printed[1]:find("Open the Auction House"))
        end)

        it("requests a scan, waits for the listing to settle, and keeps only items crafts use", function()
            printed = {}
            local ns = load()
            local requested = modern({ { 10, 5, 50 }, { 11, 1, 300 }, { 999, 1, 5 }, { 10, 1, 0 } })
            ns.Scanner.OnShow()
            assertEqual(ns.Scanner.Start(), true)
            assertEqual(requested(), 1)
            run(ns, 3)
            assertEqual(ns.Scanner.state, "waiting") -- not settled yet
            run(ns, 3)
            assertEqual(ns.Scanner.state, "idle")
            assertEqual(ns.Prices.Ladder(10), { { 10, 5 } })
            assertEqual(ns.Prices.Ladder(11), { { 300, 1 } })
            assertEqual(ns.Prices.Ladder(999), nil)
            assertEqual(ns.Prices.ScanTime(), 1000000)
            assertEqual(ns.db.scan.time, 1000000)
        end)

        it("reads the classic auction house the same way", function()
            printed = {}
            local ns = load()
            local requested = classic({ { 10, 4, 40 }, { 11, 2, 600 } })
            ns.Scanner.OnShow()
            assertEqual(ns.Scanner.Start(), true)
            assertEqual(requested(), 1)
            run(ns, 8)
            assertEqual(ns.Prices.Ladder(10), { { 10, 4 } })
            assertEqual(ns.Prices.Ladder(11), { { 300, 2 } })
        end)

        it("keeps the server's 15 minute limit", function()
            printed = {}
            local ns = load()
            modern({ { 10, 1, 10 } })
            ns.Scanner.OnShow()
            assertEqual(ns.Scanner.Start(), true)
            run(ns, 8)
            now = now + 300
            assertEqual(ns.Scanner.SecondsUntilNextScan(), 600)
            assertEqual(ns.Scanner.Start(), false)
            assert(printed[#printed]:find("10:00"), printed[#printed])
            now = now + 600
            assertEqual(ns.Scanner.Start(), true)
        end)

        it("reads a scan another addon asked for, and counts it against the limit", function()
            printed = {}
            local ns = load()
            local requested = modern({ { 10, 2, 20 } })
            ns.Scanner.OnShow()
            ns.Scanner.OnListUpdate()
            run(ns, 8)
            assertEqual(ns.Prices.Ladder(10), { { 10, 2 } })
            assertEqual(requested(), 0)
            assertEqual(ns.Scanner.SecondsUntilNextScan(), 900)
        end)

        it("ignores a list update that holds nothing", function()
            printed = {}
            local ns = load()
            modern({})
            ns.Scanner.OnShow()
            ns.Scanner.OnListUpdate()
            assertEqual(ns.Scanner.state, "idle")
        end)

        it("stops when the auction house closes mid-scan, and keeps the old prices", function()
            printed = {}
            local ns = load()
            modern({ { 10, 1, 10 } })
            ns.Prices.Build({ { 10, 1, 77 } }, 5)
            ns.Scanner.OnShow()
            ns.Scanner.Start()
            ns.Scanner.OnClosed()
            assertEqual(ns.Scanner.state, "idle")
            assertEqual(ns.Prices.Min(10), 77)
        end)

        it("gives up when the server never answers", function()
            printed = {}
            local ns = load()
            modern({})
            ns.Scanner.OnShow()
            ns.Scanner.Start()
            run(ns, 130)
            assertEqual(ns.Scanner.state, "idle")
            assert(ns.Scanner.statusText:find("did not answer"))
        end)

        it("reports progress through the status callback", function()
            printed = {}
            local ns = load()
            local seen = {}
            ns.OnScanStatus = function(t) seen[#seen + 1] = t end
            local done = false
            ns.OnScanDone = function() done = true end
            modern({ { 10, 1, 10 } })
            ns.Scanner.OnShow()
            ns.Scanner.Start()
            run(ns, 8)
            assertEqual(done, true)
            assertEqual(seen[1], "Waiting for the server...")
            assert(seen[#seen]:find("Scanned 1 listings"))
        end)

        it("lists auctions priced under what a vendor pays, whatever the item is", function()
            printed = {}
            local ns = load()
            ns.Data.Items[500] = { name = "Shiny Rock", sell = 100 }
            -- 4 for 200 = 50 each (vendor pays 100); 1 for 100 is not a deal; 2 for 150 = 75 each is; item 501 is unknown
            modern({ { 500, 4, 200 }, { 500, 1, 100 }, { 500, 2, 150 }, { 501, 1, 1 }, { 500, 1, 0 } })
            ns.Scanner.OnShow()
            ns.Scanner.Start()
            run(ns, 8)
            local deals = ns.Deals.List()
            assertEqual(#deals, 1)
            assertEqual(deals[1].itemID, 500)
            assertEqual(deals[1].units, 6)
            assertEqual(deals[1].cost, 350)
            assertEqual(deals[1].profit, 250)
            assertEqual(deals[1].cheapest, 50)
            assertEqual(ns.db.deals[1].itemID, 500)
        end)

        it("ranks deals by profit and reads them back from the saved list", function()
            printed = {}
            local ns = load()
            ns.Data.Items[500] = { name = "A", sell = 100 }
            ns.Data.Items[501] = { name = "B", sell = 1000 }
            modern({ { 500, 1, 10 }, { 501, 1, 500 } })
            ns.Scanner.OnShow()
            ns.Scanner.Start()
            run(ns, 8)
            assertEqual(ns.Deals.List()[1].itemID, 501)
            ns.Deals.Import(ns.db.deals)
            assertEqual(#ns.Deals.List(), 2)
            ns.Deals.Import(nil)
            assertEqual(#ns.Deals.List(), 0)
        end)
    end)
end
