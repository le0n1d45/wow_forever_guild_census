local addonName, ns = ...

-- Shift-clicking an item in the window: search the Auction House for it, or link it in chat when the Auction
-- House is closed. The search box is filled in and searched through the two auction house frames' own calls.

local Search = {}
ns.Search = Search

-- True when a search was started.
function Search.ForItem(name)
    if not (ns.Scanner and ns.Scanner.IsAuctionHouseOpen()) or not name then return false end
    local ok = pcall(function()
        local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
        if bar and bar.SearchBox then -- modern auction house
            bar.SearchBox:SetText(name)
            bar:StartSearch()
        elseif BrowseName and AuctionFrameBrowse_Search then -- classic auction house
            if AuctionFrameTab1 and AuctionFrameTab1.Click then AuctionFrameTab1:Click() end
            BrowseName:SetText(name)
            AuctionFrameBrowse_Search()
        else
            error("no auction house search box")
        end
    end)
    return ok
end

local function itemLink(deal)
    local link = GetItemInfo and select(2, GetItemInfo(deal.itemID))
    return link or string.format("|cffffffff|Hitem:%d::::::::|h[%s]|h|r", deal.itemID, deal.name)
end

-- Called with the clicked deal; returns what it did: "search", "link" or nil.
function Search.Click(deal)
    if not (IsShiftKeyDown and IsShiftKeyDown()) then return nil end
    if Search.ForItem(deal.name) then return "search" end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(itemLink(deal)) then return "link" end
    return nil
end
