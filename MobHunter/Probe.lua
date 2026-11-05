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

-- Scans the minimap for tooltips naming the hunted mob. Returns centres as offsets from the
-- minimap's centre in minimap units ({ { dx, dy }, ... }), or nil when the probe isn't
-- available. `step` is the grid spacing. The soft cursor is on only while probing.
function Probe.Find(minimap, hunted, step)
    if not Probe.Available(minimap) then return nil end
    local hits = {}
    pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(true) end
        hits = scan(minimap, hunted, step) or {}
    end)
    pcall(function()
        if minimap.SetUsingSoftCursor then minimap:SetUsingSoftCursor(false) end
    end)
    return Probe.Clusters(hits, step * 1.5)
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
