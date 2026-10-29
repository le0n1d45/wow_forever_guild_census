-- Run from the repo root: lua tests/run.lua
local failures, passed = 0, 0

function describe(name, fn)
    print(name)
    fn()
end

function it(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  ok   " .. name)
    else
        failures = failures + 1
        print("  FAIL " .. name .. "\n       " .. tostring(err))
    end
end

local function serialize(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. serialize(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

function assertEqual(actual, expected)
    if serialize(actual) ~= serialize(expected) then
        error("expected " .. serialize(expected) .. " got " .. serialize(actual), 2)
    end
end

-- Loads an addon file the way the WoW client does: chunk called with (addonName, ns).
function loadAddonFile(ns, name)
    local chunk = assert(loadfile("GuildCensus/" .. name))
    chunk("GuildCensus", ns)
end

-- Same order as the .toc.
ADDON_FILES = {
    "Config.lua", "Parser.lua", "Census.lua", "Demo.lua", "Roster.lua",
    "PieChart.lua", "Logs.lua", "Dungeons.lua", "Finder.lua", "UI.lua", "Options.lua", "GuildCensus.lua",
}

local ns = {}
for _, file in ipairs({ "Config.lua", "Parser.lua", "Census.lua", "Logs.lua", "Dungeons.lua", "Demo.lua" }) do
    loadAddonFile(ns, file)
end

dofile("tests/Config.test.lua")(ns)
dofile("tests/Parser.test.lua")(ns)
dofile("tests/Census.test.lua")(ns)
dofile("tests/Logs.test.lua")(ns)
dofile("tests/Dungeons.test.lua")(ns)
dofile("tests/Demo.test.lua")(ns)

dofile("tests/wow_stub.lua")
dofile("tests/UI.test.lua")()

print(string.format("\n%d passed, %d failed", passed, failures))
os.exit(failures == 0 and 0 or 1)
