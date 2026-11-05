local _, ns = ...

-- Finds hunted mobs among the minimap's tracking dots.
--
-- The client has no call that lists minimap blips. The technique (also used by the
-- NodeSight addon) is to move the minimap's soft cursor across a grid of points and read the
-- tooltip the game would show there. Everything here is feature-detected and wrapped so a
-- client without these methods just reports "unavailable" instead of erroring.
-- Unverified on a real client: the coordinate space of UpdateMouseoverAtPoint (assumed: units
-- from the minimap's BOTTOMLEFT), and whether tracked creatures list their name on line 1.
local Probe = {}
ns.Probe = Probe

-- Points on a square grid inside a circle, as offsets from its centre.
function Probe.Grid(radius, step)
    local points = {}
    for dx = -radius, radius, step do
        for dy = -radius, radius, step do
            if dx * dx + dy * dy <= radius * radius then
                points[#points + 1] = { dx, dy }
            end
        end
    end
    return points
end

-- Groups hit points that touch (within `gap`, directly or through a chain of other hits) and
-- returns each group's centre. Several tracking dots of the same name give several centres.
function Probe.Clusters(hits, gap)
    local visited, centres = {}, {}
    for i = 1, #hits do
        if not visited[i] then
            visited[i] = true
            local stack, sx, sy, n = { i }, 0, 0, 0
            while #stack > 0 do
                local current = hits[table.remove(stack)]
                sx, sy, n = sx + current[1], sy + current[2], n + 1
                for j = 1, #hits do
                    if not visited[j] then
                        local ddx, ddy = hits[j][1] - current[1], hits[j][2] - current[2]
                        if ddx * ddx + ddy * ddy <= gap * gap then
                            visited[j] = true
                            stack[#stack + 1] = j
                        end
                    end
                end
            end
            centres[#centres + 1] = { sx / n, sy / n }
        end
    end
    return centres
end

function Probe.Available(minimap)
    return minimap ~= nil
        and type(minimap.UpdateMouseoverAtPoint) == "function"
        and type(C_TooltipInfo) == "table" and type(C_TooltipInfo.GetMinimapMouseover) == "function"
end

-- True when any tracking type is switched on. If the client can't tell us, assume yes
-- rather than silently never scanning.
function Probe.IsTracking()
    local C = C_Minimap
    if not (C and C.GetNumTrackingTypes and C.GetTrackingInfo) then return true end
    local ok, tracking = pcall(function()
        for i = 1, C.GetNumTrackingTypes() do
            local info, _, active = C.GetTrackingInfo(i)
            if type(info) == "table" then active = info.active end
            if active then return true end
        end
        return false
    end)
    return not ok or tracking
end

-- Scans the minimap for tooltips naming the hunted mob. Returns centres as offsets from the
-- minimap's centre in minimap units ({ { dx, dy }, ... }), or nil when the probe isn't
-- available. `step` is the grid spacing.
function Probe.Find(minimap, hunted, step)
    if not Probe.Available(minimap) then return nil end
    local radius = minimap:GetWidth() / 2
    local hits = {}
    pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(true) end
        for _, p in ipairs(Probe.Grid(radius, step)) do
            minimap:UpdateMouseoverAtPoint(radius + p[1], radius + p[2])
            local data = C_TooltipInfo.GetMinimapMouseover()
            if data and data.lines then
                for _, line in ipairs(data.lines) do
                    if ns.Hunt.Matches(hunted, line.leftText) then
                        hits[#hits + 1] = p
                        break
                    end
                end
            end
        end
    end)
    pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(false) end
    end)
    return Probe.Clusters(hits, step * 1.5)
end

-- For /mobhunt debug: runs the same scan as Find, but records what the client actually returned
-- so a probe that finds nothing can be told apart from one that can't run. Returns a list of
-- report lines.
function Probe.Diagnose(minimap, step)
    local report = {}
    local function add(text) report[#report + 1] = text end
    add("Minimap: " .. (minimap and "found" or "MISSING")
        .. ", UpdateMouseoverAtPoint: " .. tostring(minimap and type(minimap.UpdateMouseoverAtPoint) or "n/a")
        .. ", SetUsingSoftCursor: " .. tostring(minimap and type(minimap.SetUsingSoftCursor) or "n/a")
        .. ", C_TooltipInfo.GetMinimapMouseover: "
        .. tostring(type(C_TooltipInfo) == "table" and type(C_TooltipInfo.GetMinimapMouseover) or "missing"))
    add("Tracking something: " .. tostring(Probe.IsTracking()))
    if not Probe.Available(minimap) then
        add("Probe unavailable, so no minimap icons can be placed.")
        return report
    end
    local radius = minimap:GetWidth() / 2
    local points, withTooltip, samples, seen = 0, 0, {}, {}
    local ok, err = pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(true) end
        for _, p in ipairs(Probe.Grid(radius, step)) do
            points = points + 1
            minimap:UpdateMouseoverAtPoint(radius + p[1], radius + p[2])
            local data = C_TooltipInfo.GetMinimapMouseover()
            if data then
                withTooltip = withTooltip + 1
                local first = data.lines and data.lines[1] and data.lines[1].leftText
                local text = pcall(tostring, first) and tostring(first) or "<unreadable>"
                if not seen[text] and #samples < 6 then
                    seen[text] = true
                    samples[#samples + 1] = text .. " @" .. p[1] .. "," .. p[2]
                end
            end
        end
    end)
    pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(false) end
    end)
    add("Minimap width " .. tostring(minimap:GetWidth()) .. ", probed " .. points .. " points, "
        .. withTooltip .. " returned a tooltip" .. (ok and "" or (", ERROR: " .. tostring(err))))
    for _, s in ipairs(samples) do add("  tooltip line 1: " .. s) end
    if withTooltip == 0 then
        add("No tooltips at all: the soft cursor or its coordinates may not work this way on this client.")
    end
    return report
end
