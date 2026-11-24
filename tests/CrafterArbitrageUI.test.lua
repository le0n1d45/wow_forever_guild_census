-- The whole addon, loaded in the order its TOC lists, against the strict WoW stub.
return function()
    local printed
    local realPrint, realIt = print, it
    -- The addon's chat output is captured per test; restore the real print and clear the fake client's globals after.
    local function it(name, fn)
        realIt(name, function()
            local ok, err = pcall(fn)
            print, time, GameTooltip = realPrint, nil, nil
            IsPlayerSpell, UnitFactionGroup, UnitClass, C_TradeSkillUI, CrafterArbitrageDB = nil, nil, nil, nil, nil
            Minimap, GetCursorPosition = nil, nil
            if not ok then error(err, 0) end
        end)
    end

    local function loadAddon(options)
        InstallWowStub(options)
        options = options or {}
        printed = {}
        print = function(text) printed[#printed + 1] = text end
        time = function() return 2000000 end
        CrafterArbitrageDB = options.db
        IsPlayerSpell = function(id) return id == 2385 end -- Brown Linen Vest
        UnitFactionGroup = function() return "Alliance" end
        UnitClass = function() return "Mage", "MAGE", 8 end
        C_TradeSkillUI = { GetProfessionInfoBySkillLineID = function() return { skillLevel = 300 } end }
        Minimap = CreateFrame("Frame", "Minimap", UIParent)
        Minimap:SetSize(140, 140)
        GetCursorPosition = function() return 0, 0 end
        local ns = {}
        for line in io.lines("CrafterArbitrage/CrafterArbitrage.toc") do
            if line:match("%.lua$") then loadAddonFile(ns, (line:gsub("\\", "/")), "CrafterArbitrage") end
        end
        local frame = CrafterArbitrageEventFrame
        frame.scripts.OnEvent(frame, "ADDON_LOADED", "CrafterArbitrage")
        return ns, frame
    end

    local function click(control) control.scripts.OnClick(control) end

    -- Linen cloth bolts cost 5 on the AH, thread 10 at a vendor; a Brown Linen Vest sells to a vendor for 31.
    local function scanned(ns)
        ns.Prices.Build({ { 2996, 100, 500 }, { 2568, 3, 3000 } }, 1999000)
    end

    local function drain(ns)
        local window = ns.UI.Window()
        for _ = 1, 400 do window.scripts.OnUpdate(window, 0.016) end
    end

    describe("CrafterArbitrage addon", function()
        it("loads every file in its TOC and sets up saved settings", function()
            local ns = loadAddon()
            assertEqual(ns.settings.channel, "vendor")
            assertEqual(ns.settings.filter, "known")
            assert(SlashCmdList["CRAFTERARBITRAGE"], "slash command registered")
        end)

        it("keeps saved settings and restores the saved scan", function()
            local ns = loadAddon({ db = { channel = "ah", filter = "all", scan = { time = 5, items = { [2996] = { 7, 9 } } } } })
            assertEqual(ns.settings.channel, "ah")
            assertEqual(ns.settings.filter, "all")
            assertEqual(ns.Prices.Ladder(2996), { { 7, 9 } })
        end)

        it("repairs a settings file with a bad filter", function()
            local ns = loadAddon({ db = { filter = "nonsense", channel = "weird" } })
            assertEqual(ns.settings.filter, "known")
            assertEqual(ns.settings.channel, "vendor")
        end)

        it("opens the window, works the list out and shows what pays", function()
            local ns = loadAddon()
            scanned(ns)
            SlashCmdList["CRAFTERARBITRAGE"]("")
            local window = ns.UI.Window()
            assertEqual(window:IsShown(), true)
            drain(ns)
            local results = ns.UI.Results()
            assertEqual(results[1].spell, 2385)
            assertEqual(window.rows[1].name.text, "Brown Linen Vest")
            assertEqual(window.rows[1].source.text, "known")
            assert(window.summary.text:find("crafts pay"), window.summary.text)
            -- 31 sale - 5 bolt - 10 thread = 16 per craft
            assertEqual(results[1].eval.profit, results[1].eval.crafts * 16)
        end)

        it("asks for a scan first when there is none", function()
            local ns = loadAddon()
            SlashCmdList["CRAFTERARBITRAGE"]("")
            drain(ns)
            assert(ns.UI.Window().summary.text:find("Scan the Auction House first"))
            assert(ns.UI.Window().scanText.text:find("No scan yet"))
        end)

        it("switches to selling on the auction house from the checkbox", function()
            local ns = loadAddon()
            scanned(ns)
            SlashCmdList["CRAFTERARBITRAGE"]("")
            drain(ns)
            local window = ns.UI.Window()
            window.sellBox:SetChecked(true)
            click(window.sellBox)
            assertEqual(ns.settings.channel, "ah")
            drain(ns)
            -- vests list at 1000 each, reference price 1000 less the 5% cut, share limit of listed units
            local results = ns.UI.Results()
            assertEqual(#results, 1)
            assertEqual(results[1].eval.crafts, 1)
            assertEqual(window.sellBox:GetChecked(), true)
        end)

        it("changes the recipe filter with its buttons", function()
            local ns = loadAddon()
            scanned(ns)
            SlashCmdList["CRAFTERARBITRAGE"]("")
            drain(ns)
            local window = ns.UI.Window()
            assertEqual(window.filterButtons.known.enabled, false)
            click(window.filterButtons.all)
            assertEqual(ns.settings.filter, "all")
            drain(ns)
            assertEqual(window.filterButtons.all.enabled, false)
            assertEqual(window.filterButtons.known.enabled, true)
            assert(#ns.UI.Results() >= 1)
        end)

        it("pages through the results", function()
            local ns = loadAddon()
            SlashCmdList["CRAFTERARBITRAGE"]("")
            local window = ns.UI.Window()
            local fake = {}
            for i = 1, 30 do
                fake[i] = { spell = i, status = "known", recipe = { name = "R" .. i, out = { 2568, 1 }, r = {} }, eval = { crafts = 1, cost = 1, revenue = 2, profit = i, units = 1, why = "max" } }
            end
            ns.UI.SetResultsForTest(fake)
            assertEqual(window.pageText.text, "Page 1 of 3")
            assertEqual(window.rows[1].name.text, "R1")
            click(window.nextButton)
            assertEqual(window.rows[1].name.text, "R13")
            click(window.nextButton)
            click(window.nextButton)
            assertEqual(window.pageText.text, "Page 3 of 3")
            assertEqual(window.rows[7].shown, false) -- 30 results: 6 on the last page
            click(window.prevButton)
            assertEqual(window.pageText.text, "Page 2 of 3")
        end)

        it("shows a tooltip with the recipe's details", function()
            local ns = loadAddon()
            scanned(ns)
            local lines = {}
            GameTooltip = {
                SetOwner = function() end, AddLine = function(_, t) lines[#lines + 1] = t end, Show = function() end, Hide = function() end,
            }
            SlashCmdList["CRAFTERARBITRAGE"]("")
            drain(ns)
            local row = ns.UI.Window().rows[1]
            row.scripts.OnEnter(row)
            assertEqual(lines[1], "Brown Linen Vest")
            assert(lines[2]:find("crafts make"), lines[2])
            local text = table.concat(lines, "\n")
            assert(text:find("Bolt of Linen Cloth"), text)
            assert(text:find("profit"), text)
            GameTooltip = nil
        end)

        it("routes the auction house events to the scanner", function()
            local ns, frame = loadAddon()
            frame.scripts.OnEvent(frame, "AUCTION_HOUSE_SHOW")
            assertEqual(ns.Scanner.IsAuctionHouseOpen(), true)
            frame.scripts.OnEvent(frame, "AUCTION_HOUSE_CLOSED")
            assertEqual(ns.Scanner.IsAuctionHouseOpen(), false)
        end)

        it("handles the slash commands", function()
            local ns = loadAddon()
            local slash = SlashCmdList["CRAFTERARBITRAGE"]
            slash("ah")
            assertEqual(ns.settings.channel, "ah")
            slash("vendor")
            assertEqual(ns.settings.channel, "vendor")
            slash("filter learnable")
            assertEqual(ns.settings.filter, "learnable")
            slash("filter bogus")
            assertEqual(ns.settings.filter, "learnable")
            slash("neutral on")
            assertEqual(ns.settings.neutral, true)
            slash("neutral off")
            assertEqual(ns.settings.neutral, false)
            slash("scan")
            assert(printed[#printed]:find("Open the Auction House"))
            slash("help")
            assert(printed[#printed]:find("/carb opens the window"))
        end)

        it("still registers /carb when the client does not know one of the events", function()
            InstallWowStub()
            local known = { ADDON_LOADED = true, AUCTION_HOUSE_SHOW = true, AUCTION_HOUSE_CLOSED = true, AUCTION_ITEM_LIST_UPDATE = true }
            local realCreate = CreateFrame
            CreateFrame = function(...)
                local f = realCreate(...)
                function f:RegisterEvent(event)
                    if not known[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
                end
                return f
            end
            local ns = {}
            SlashCmdList = {}
            for line in io.lines("CrafterArbitrage/CrafterArbitrage.toc") do
                if line:match("%.lua$") then loadAddonFile(ns, (line:gsub("\\", "/")), "CrafterArbitrage") end
            end
            CreateFrame = realCreate
            assert(SlashCmdList["CRAFTERARBITRAGE"], "the slash command should exist")
        end)

        it("puts a minimap button on the minimap's edge, saved angle and all", function()
            local ns = loadAddon({ db = { minimapAngle = 0 } })
            local button = ns.MinimapButton.Button()
            assert(button, "button created")
            assertEqual(button.shown, true)
            assertEqual(button.icon.shown, true)
        end)

        it("opens the window on a left click and scans on a right click", function()
            local ns = loadAddon()
            local button = ns.MinimapButton.Button()
            button.scripts.OnClick(button, "LeftButton")
            assertEqual(ns.UI.Window():IsShown(), true)
            button.scripts.OnClick(button, "LeftButton")
            assertEqual(ns.UI.Window():IsShown(), false)
            button.scripts.OnClick(button, "RightButton")
            assert(printed[#printed]:find("Open the Auction House"))
        end)

        it("follows the cursor while dragged and saves the angle", function()
            local ns = loadAddon()
            local button = ns.MinimapButton.Button()
            Minimap.centerX, Minimap.centerY = 100, 100
            button.scripts.OnDragStart(button)
            GetCursorPosition = function() return 100, 200 end -- straight above the centre
            button.scripts.OnUpdate(button, 0.016)
            assertEqual(math.floor(ns.settings.minimapAngle + 0.5), 90)
            button.scripts.OnDragStop(button)
            assertEqual(button.scripts.OnUpdate, nil)
        end)

        it("measures the angle round the minimap", function()
            local ns = loadAddon()
            local angle = ns.MinimapButton.AngleFrom
            assertEqual(angle(0, 0, 10, 0), 0)
            assertEqual(angle(0, 0, 0, 10), 90)
            assertEqual(angle(0, 0, -10, 0), 180)
            assertEqual(angle(0, 0, 0, -10), 270)
        end)

        it("hides and shows the button with /carb minimap", function()
            local ns = loadAddon()
            SlashCmdList["CRAFTERARBITRAGE"]("minimap off")
            assertEqual(ns.MinimapButton.Button().shown, false)
            SlashCmdList["CRAFTERARBITRAGE"]("minimap on")
            assertEqual(ns.MinimapButton.Button().shown, true)
        end)

        it("shows a tooltip on the minimap button", function()
            local ns = loadAddon()
            local lines = {}
            GameTooltip = { SetOwner = function() end, AddLine = function(_, t) lines[#lines + 1] = t end, Show = function() end, Hide = function() end }
            local button = ns.MinimapButton.Button()
            button.scripts.OnEnter(button)
            assertEqual(lines[1], "CrafterArbitrage")
            assert(lines[2]:find("Left%-click"))
        end)

        it("lets the window be toggled closed", function()
            local ns = loadAddon()
            SlashCmdList["CRAFTERARBITRAGE"]("")
            SlashCmdList["CRAFTERARBITRAGE"]("")
            assertEqual(ns.UI.Window():IsShown(), false)
        end)

        it("shows auctions under the vendor price in their own list", function()
            local ns = loadAddon()
            ns.Deals.Import({ { itemID = 1, name = "Shiny Rock", units = 6, cost = 350, vendor = 100, revenue = 600, profit = 250, cheapest = 50 } })
            ns.UI.Show()
            local window = ns.UI.Window()
            click(window.modeButtons.deals)
            assertEqual(ns.settings.mode, "deals")
            assertEqual(#ns.UI.Results(), 1)
            assertEqual(window.rows[1].name.text, "|cffffffffShiny Rock|r")
            assertEqual(window.rows[1].crafts.text, "6")
            assertEqual(window.headers.crafts.text, "Units")
            click(window.modeButtons.crafts)
            assertEqual(window.headers.crafts.text, "Crafts")
        end)

        it("shift-click on a deal searches the Auction House, or links the item in chat", function()
            local ns = loadAddon()
            ns.Deals.Import({ { itemID = 1, name = "Shiny Rock", units = 6, cost = 350, vendor = 100, revenue = 600, profit = 250, cheapest = 50 } })
            ns.UI.Show()
            click(ns.UI.Window().modeButtons.deals)
            local row = ns.UI.Window().rows[1]
            local searched, linked, shift = nil, nil, false
            IsShiftKeyDown = function() return shift end
            ChatEdit_InsertLink = function(link) linked = link return true end
            AuctionHouseFrame = { SearchBar = { SearchBox = { SetText = function(_, t) searched = t end }, StartSearch = function() searched = searched .. "!" end } }
            local ok, err = pcall(function()
                row.scripts.OnMouseUp(row)
                assertEqual(searched, nil) -- no shift: nothing happens
                shift = true
                row.scripts.OnMouseUp(row) -- shift, Auction House closed: link
                assert(linked:find("Hitem:1:"), tostring(linked))
                ns.Scanner.OnShow()
                row.scripts.OnMouseUp(row)
                assertEqual(searched, "Shiny Rock!")
            end)
            IsShiftKeyDown, ChatEdit_InsertLink, AuctionHouseFrame = nil, nil, nil
            if not ok then error(err, 0) end
        end)
    end)
end
