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

        it("lets the window be toggled closed", function()
            local ns = loadAddon()
            SlashCmdList["CRAFTERARBITRAGE"]("")
            SlashCmdList["CRAFTERARBITRAGE"]("")
            assertEqual(ns.UI.Window():IsShown(), false)
        end)
    end)
end
