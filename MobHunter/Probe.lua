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

-- Groups points that touch (within `gap`, directly or through a chain of other points).
-- Returns the groups, each a list of points.
function Probe.BlobsOf(points, gap)
    local visited, blobs = {}, {}
    for i = 1, #points do
        if not visited[i] then
            visited[i] = true
            local stack, blob = { i }, {}
            while #stack > 0 do
                local current = points[table.remove(stack)]
                blob[#blob + 1] = current
                for j = 1, #points do
                    if not visited[j] then
                        local ddx, ddy = points[j][1] - current[1], points[j][2] - current[2]
                        if ddx * ddx + ddy * ddy <= gap * gap then
                            visited[j] = true
                            stack[#stack + 1] = j
                        end
                    end
                end
            end
            blobs[#blobs + 1] = blob
        end
    end
    return blobs
end

-- Each group's centre (see BlobsOf).
function Probe.Clusters(hits, gap)
    local centres = {}
    for _, blob in ipairs(Probe.BlobsOf(hits, gap)) do
        local sx, sy = 0, 0
        for _, p in ipairs(blob) do sx, sy = sx + p[1], sy + p[2] end
        centres[#centres + 1] = { sx / #blob, sy / #blob }
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

-- Probes every grid point. Returns the points whose tooltip names `hunted` (if given), how
-- many points had tooltip content, and up to `maxSamples` distinct first lines.
local function scan(minimap, hunted, step, maxSamples)
    local left, bottom, scale = origin(minimap)
    if not left then return nil end
    local radius = minimap:GetWidth() / 2
    local hits, filled, samples, seen = {}, 0, {}, {}
    for _, p in ipairs(Probe.Grid(radius, step)) do
        minimap:UpdateMouseoverAtPoint((left + radius + p[1]) * scale, (bottom + radius + p[2]) * scale)
        local data = C_TooltipInfo.GetMinimapMouseover()
        if hasLines(data) then
            filled = filled + 1
            local matched = false
            for i, line in ipairs(data.lines) do
                local text = Probe.LineText(line)
                if i == 1 and maxSamples and #samples < maxSamples then
                    local shown = pcall(tostring, text) and tostring(text) or "<unreadable>"
                    if not seen[shown] then seen[shown] = true; samples[#samples + 1] = shown .. " @" .. p[1] .. "," .. p[2] end
                end
                if hunted and not matched and ns.Hunt.Matches(hunted, text) then
                    hits[#hits + 1] = p
                    matched = true
                end
            end
        end
    end
    return hits, filled, samples
end

-- A tracking dot answers the probe within about this many minimap units of its centre.
-- Estimated, not measured: it decides how far apart two dots must be to count as two.
Probe.HIT_RADIUS = 5

-- Splits points that all hit (a blob of overlapping dots) into dot centres. A dot's centre is
-- where the most hit points lie within one hit-radius, so: rank points by that count, take the
-- best, skip any point closer than 1.2 radii to one already taken, and repeat. One dot gives
-- one centre; two dots 8 apart give two; dots closer than that merge.
function Probe.Split(points, radius)
    local density = {}
    for i, p in ipairs(points) do
        local n = 0
        for _, q in ipairs(points) do
            if (q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2 <= radius * radius then n = n + 1 end
        end
        density[i] = n
    end
    local order = {}
    for i = 1, #points do order[i] = i end
    table.sort(order, function(a, b)
        if density[a] ~= density[b] then return density[a] > density[b] end
        if points[a][1] ~= points[b][1] then return points[a][1] < points[b][1] end
        return points[a][2] < points[b][2]
    end)
    local centres, apart = {}, radius * 1.2
    for _, i in ipairs(order) do
        local p, near = points[i], false
        for _, c in ipairs(centres) do
            if (c[1] - p[1]) ^ 2 + (c[2] - p[2]) ^ 2 < apart * apart then near = true; break end
        end
        if not near then centres[#centres + 1] = { p[1], p[2] } end
    end
    return centres
end

-- Scans the minimap for tooltips naming the hunted mob. Returns centres as offsets from the
-- minimap's centre in minimap units ({ { dx, dy }, ... }), or nil when the probe isn't
-- available. `step` is the coarse grid spacing; every coarse hit is then re-probed on a finer
-- grid around it (FINE units apart) so that dots close together come out as separate centres.
-- The soft cursor is on only while probing.
local FINE = 2
function Probe.Find(minimap, hunted, step)
    if not Probe.Available(minimap) then return nil end
    local centres = {}
    pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(true) end
        local coarse = scan(minimap, hunted, step) or {}
        if #coarse == 0 then return end
        local left, bottom, scale = origin(minimap)
        local radius = minimap:GetWidth() / 2
        local fine, done = {}, {}
        for _, c in ipairs(coarse) do
            for fx = -step, step, FINE do
                for fy = -step, step, FINE do
                    local px, py = c[1] + fx, c[2] + fy
                    local key = math.floor(px / FINE + 0.5) * 100000 + math.floor(py / FINE + 0.5)
                    if not done[key] and px * px + py * py <= radius * radius then
                        done[key] = true
                        minimap:UpdateMouseoverAtPoint((left + radius + px) * scale, (bottom + radius + py) * scale)
                        local data = C_TooltipInfo.GetMinimapMouseover()
                        if hasLines(data) then
                            for _, line in ipairs(data.lines) do
                                if ns.Hunt.Matches(hunted, Probe.LineText(line)) then
                                    fine[#fine + 1] = { px, py }
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        for _, blob in ipairs(Probe.BlobsOf(fine, FINE * 1.5)) do
            for _, centre in ipairs(Probe.Split(blob, Probe.HIT_RADIUS)) do
                centres[#centres + 1] = centre
            end
        end
    end)
    pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(false) end
    end)
    return centres
end

-- For /mobhunt debug: runs one scan and records what the client returned, so a probe that
-- finds nothing can be told apart from one that can't run. Returns a list of report lines.
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
    return report
end
