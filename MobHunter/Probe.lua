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

-- The text of one tooltip line. Raw tooltip data keeps its text in `args` until
-- TooltipUtil.SurfaceArgs copies it onto the line as leftText, so try both.
function Probe.LineText(line)
    if type(line) ~= "table" then return nil end
    if line.leftText == nil and type(TooltipUtil) == "table" and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, line)
    end
    if line.leftText ~= nil then return line.leftText end
    if type(line.args) == "table" then
        for _, arg in ipairs(line.args) do
            if type(arg) == "table" and arg.stringVal ~= nil then return arg.stringVal end
        end
    end
    return nil
end

-- Where the minimap sits on screen and at what scale. UpdateMouseoverAtPoint takes screen
-- coordinates: the point's offset from the minimap's bottom-left, plus the minimap's own
-- bottom-left, times its effective scale (NodeSight, github.com/Krelock/NodeSight, calls it
-- as `((left + x) * scale, (bottom + y) * scale)`). Nil when the minimap has no position yet.
local function origin(minimap)
    if type(minimap.GetLeft) ~= "function" or type(minimap.GetBottom) ~= "function" then return nil end
    local left, bottom = minimap:GetLeft(), minimap:GetBottom()
    if type(left) ~= "number" or type(bottom) ~= "number" then return nil end
    local scale = type(minimap.GetEffectiveScale) == "function" and minimap:GetEffectiveScale() or 1
    return left, bottom, type(scale) == "number" and scale or 1
end

local function hasLines(data)
    return type(data) == "table" and type(data.lines) == "table" and #data.lines > 0
end

-- How many names in a tooltip match the hunted text. The tooltip lists every tracked thing
-- under the point, one name per line (several per line when dots overlap), repeats included, so
-- this is the number of hunted dots whose hit area covers the point.
function Probe.CountMatches(hunted, data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return 0 end
    local count = 0
    for _, line in ipairs(data.lines) do
        local text = Probe.LineText(line)
        if type(text) == "string" then
            for name in (text .. "\n"):gmatch("([^\n]*)\n") do
                if name ~= "" and ns.Hunt.Matches(hunted, name) then count = count + 1 end
            end
        elseif text ~= nil and ns.Hunt.Matches(hunted, text) then
            count = count + 1
        end
    end
    return count
end

-- Probes one point (offsets from the minimap's centre) and returns the tooltip data.
local function probeAt(minimap, left, bottom, scale, radius, px, py)
    minimap:UpdateMouseoverAtPoint((left + radius + px) * scale, (bottom + radius + py) * scale)
    return C_TooltipInfo.GetMinimapMouseover()
end

-- Probes every grid point. With `hunted`, returns { x, y, n } per point (n = matching dots
-- under it); without, how many points had tooltip content and up to `maxSamples` distinct
-- first lines (for /mobhunt debug).
local function scan(minimap, hunted, step, maxSamples)
    local left, bottom, scale = origin(minimap)
    if not left then return nil end
    local radius = minimap:GetWidth() / 2
    local points, filled, samples, seen = {}, 0, {}, {}
    for _, p in ipairs(Probe.Grid(radius, step)) do
        local data = probeAt(minimap, left, bottom, scale, radius, p[1], p[2])
        if hunted then
            points[#points + 1] = { p[1], p[2], Probe.CountMatches(hunted, data) }
        elseif hasLines(data) then
            filled = filled + 1
            local text = Probe.LineText(data.lines[1])
            local shown = pcall(tostring, text) and tostring(text) or "<unreadable>"
            if maxSamples and #samples < maxSamples and not seen[shown] then
                seen[shown] = true
                samples[#samples + 1] = shown .. " @" .. p[1] .. "," .. p[2]
            end
        end
    end
    return points, filled, samples
end

-- A tracking dot answers the probe within about this many minimap units of its centre.
-- NodeSight starts at 15 and adapts it between 11 and 24; /mobhunt debug output (about 8 content
-- points per dot at 8-unit spacing) fits that. Estimated, not measured.

-- Finds the dots behind probe results. points = { { x, y, n } }: n is how many hunted dots
-- cover the point. Greedy fit: repeatedly place a dot where a HIT_RADIUS disc explains the most
-- still-unexplained counts (and contradicts the fewest), subtract it, and stop when a disc
-- would explain too little. Also returns the misfit: how many counts are left over or overshot. Because n counts overlapping dots, dots closer than the hit radius
-- still come out separately. Returns { { x, y }, ... }.
function Probe.Fit(points, radius, maxDots)
    local reach = radius * radius
    local cell = radius
    local buckets = {}
    local function key(cx, cy) return cx * 4096 + cy end
    for i, p in ipairs(points) do
        local k = key(math.floor(p[1] / cell), math.floor(p[2] / cell))
        local list = buckets[k]
        if not list then list = {}; buckets[k] = list end
        list[#list + 1] = i
    end
    local function inside(p)
        local found = {}
        local cx, cy = math.floor(p[1] / cell), math.floor(p[2] / cell)
        for gx = cx - 1, cx + 1 do
            for gy = cy - 1, cy + 1 do
                for _, j in ipairs(buckets[key(gx, gy)] or {}) do
                    local q = points[j]
                    if (q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2 <= reach then found[#found + 1] = j end
                end
            end
        end
        return found
    end
    local residual, candidates, around = {}, {}, {}
    for i, p in ipairs(points) do
        residual[i] = p[3]
        if p[3] > 0 then candidates[#candidates + 1] = i; around[i] = inside(p) end
    end
    local function gainOf(i)
        local gain = 0
        for _, j in ipairs(around[i]) do
            gain = gain + (residual[j] > 0 and 1 or -1)
        end
        return gain
    end
    local gains = {}
    for _, i in ipairs(candidates) do gains[i] = gainOf(i) end
    local centres, firstGain = {}, nil
    for _ = 1, maxDots or 16 do
        local best, bestGain = nil, 0
        for _, i in ipairs(candidates) do
            if gains[i] > bestGain then best, bestGain = i, gains[i] end
        end
        firstGain = firstGain or bestGain
        if not best or bestGain < math.max(1, firstGain * 0.2) then break end
        local c = points[best]
        centres[#centres + 1] = { c[1], c[2] }
        for _, j in ipairs(around[best]) do residual[j] = residual[j] - 1 end
        -- only discs that overlap the one just placed have a different gain now
        for _, i in ipairs(candidates) do
            local p = points[i]
            if (p[1] - c[1]) ^ 2 + (p[2] - c[2]) ^ 2 <= 4 * reach then gains[i] = gainOf(i) end
        end
    end
    local misfit = 0
    for _, r in ipairs(residual) do misfit = misfit + math.abs(r) end
    return centres, misfit
end

-- Radii tried when the real hit radius is unknown, and what one extra dot costs in misfit
-- (so a smaller radius can't win just by using many small discs).
local RADII = { 7, 8, 9, 10, 11, 12, 13, 15, 17, 20, 24 }
local DOT_COST = 6

-- Fits with every radius in RADII and keeps the one with the lowest misfit + DOT_COST per dot.
-- Returns the centres and that radius. The radius that won last time is tried first and, while it
-- still fits well, kept, so most scans cost one fit instead of eleven.
function Probe.FitBest(points)
    local function cost(r)
        local centres, misfit = Probe.Fit(points, r)
        return centres, misfit + DOT_COST * #centres
    end
    if Probe.fitRadius and (Probe.fitScans or 0) % 10 ~= 0 then
        Probe.fitScans = Probe.fitScans + 1
        local centres = Probe.Fit(points, Probe.fitRadius)
        if #centres > 0 then return centres, Probe.fitRadius end
    end
    Probe.fitScans = (Probe.fitScans or 0) + 1
    local bestCentres, bestCost, bestRadius = {}, math.huge, nil
    for _, r in ipairs(RADII) do
        local centres, c = cost(r)
        if #centres > 0 and c < bestCost then bestCentres, bestCost, bestRadius = centres, c, r end
    end
    Probe.fitRadius = bestRadius or Probe.fitRadius
    return bestCentres, bestRadius
end

-- Scans the minimap for tooltips naming the hunted mob. Returns the dots' positions as offsets
-- from the minimap's centre in minimap units ({ { dx, dy }, ... }), or nil when the probe isn't
-- available. `step` is the coarse grid spacing; the area around every coarse hit is re-probed
-- on a finer grid (FINE units) before Fit picks the dots out. The soft cursor is on only while
-- probing.
local FINE = 4
function Probe.Find(minimap, hunted, step)
    if not Probe.Available(minimap) then return nil end
    local centres = {}
    pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(true) end
        local points = scan(minimap, hunted, step)
        local coarse = {}
        for _, p in ipairs(points or {}) do
            if p[3] > 0 then coarse[#coarse + 1] = p end
        end
        if #coarse == 0 then return end
        local left, bottom, scale = origin(minimap)
        local radius = minimap:GetWidth() / 2
        local done = {}
        for _, c in ipairs(coarse) do
            for fx = -step, step, FINE do
                for fy = -step, step, FINE do
                    local px, py = c[1] + fx, c[2] + fy
                    local key = math.floor(px / FINE + 0.5) * 100000 + math.floor(py / FINE + 0.5)
                    if not done[key] and px * px + py * py <= radius * radius then
                        done[key] = true
                        local data = probeAt(minimap, left, bottom, scale, radius, px, py)
                        points[#points + 1] = { px, py, Probe.CountMatches(hunted, data) }
                    end
                end
            end
        end
        local radiusUsed
        centres, radiusUsed = Probe.FitBest(points)
        Probe.last = { points = #points, hits = #coarse, radius = radiusUsed, centres = centres }
    end)
    pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(false) end
    end)
    return centres
end

-- For /mobhunt debug: runs one scan and records what the client returned, so a probe that
-- finds nothing can be told apart from one that can't run. Returns a list of report lines.
function Probe.Diagnose(minimap, step, hunted)
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
    local left, bottom, scale = origin(minimap)
    add("Minimap width " .. tostring(minimap:GetWidth()) .. ", left " .. tostring(left) .. ", bottom "
        .. tostring(bottom) .. ", scale " .. tostring(scale))
    local ok, hits, filled, samples = pcall(function()
        minimap:SetUsingSoftCursor(true)
        return scan(minimap, nil, step, 6)
    end)
    pcall(function() minimap:SetUsingSoftCursor(false) end)
    if not ok then
        add("ERROR: " .. tostring(hits))
    elseif not hits then
        add("The minimap has no screen position yet.")
    else
        add(filled .. " points returned tooltip content")
        for _, sample in ipairs(samples) do add("  line 1: " .. sample) end
        if filled == 0 then
            add("Nothing under any point. Is something tracked, with a dot on the minimap right now?")
        end
    end
    if hunted and ok and hits then
        Probe.last = nil
        local found = Probe.Find(minimap, hunted, step) or {}
        local last = Probe.last
        add("Hunting '" .. hunted .. "': " .. #found .. " dots" .. (last and (", fitted with hit radius " .. tostring(last.radius)
            .. " from " .. last.hits .. " coarse hits and " .. last.points .. " probes") or ", no probe hit it"))
        for i, c in ipairs(found) do
            if i > 12 then add("  ...") break end
            add(string.format("  dot %d at %.0f,%.0f", i, c[1], c[2]))
        end
    end
    return report
end
