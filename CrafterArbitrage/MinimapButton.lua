local addonName, ns = ...

-- A button on the minimap's edge: click to open the window, drag to move it around the minimap.
-- (No library: the angle is kept in the saved settings, db.minimapAngle, in degrees.)

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local DEFAULT_ANGLE = 200
local ICON = "Interface\\AddOns\\CrafterArbitrage\\icon"
local button

-- Degrees (0 = right of the minimap, counter-clockwise) of the cursor as seen from the minimap's centre.
function MinimapButton.AngleFrom(centerX, centerY, cursorX, cursorY)
    return math.deg(math.atan2(cursorY - centerY, cursorX - centerX)) % 360
end

local function place()
    if not button then return end
    local angle = math.rad((ns.settings and ns.settings.minimapAngle) or DEFAULT_ANGLE)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()
    ns.settings.minimapAngle = MinimapButton.AngleFrom(centerX, centerY, cursorX / scale, cursorY / scale)
    place()
end

local function showTooltip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("CrafterArbitrage")
    GameTooltip:AddLine("Left-click: open or close the window")
    GameTooltip:AddLine("Right-click: scan the Auction House (it must be open)")
    GameTooltip:AddLine("Drag: move this button around the minimap")
    GameTooltip:Show()
end

function MinimapButton.Create()
    if button or not Minimap then return end
    button = CreateFrame("Button", "CrafterArbitrageMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER")
    button.icon = icon
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ns.Scanner.Start() else ns.UI.Toggle() end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    place()
    MinimapButton.Refresh()
end

-- Shows or hides the button according to the saved setting.
function MinimapButton.Refresh()
    if not button then return end
    place()
    button:SetShown(not (ns.settings and ns.settings.minimapHide))
end

function MinimapButton.Button() return button end
