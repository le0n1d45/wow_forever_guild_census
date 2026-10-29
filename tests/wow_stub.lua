-- Minimal, strict WoW widget API for running the addon headlessly.
-- Only methods listed here exist; calling anything else raises an error, so a
-- misspelled or unsupported widget method fails the test instead of passing silently.
-- The method lists reflect the retail widget API as best known; they are not proof
-- that the Forever client has each method.

local function class(name, methods)
    local cls = {}
    for _, m in ipairs(methods) do cls[m] = function() end end
    return setmetatable(cls, {
        __call = function(self, init)
            return setmetatable(init or {}, {
                __index = function(_, key)
                    local v = self[key]
                    if v == nil then error("unknown " .. name .. " member: " .. tostring(key), 2) end
                    return v
                end,
            })
        end,
    })
end

local Region = { "SetSize", "SetPoint", "Show", "Hide" }
local function extend(base, extra)
    local list = {}
    for _, m in ipairs(base) do list[#list + 1] = m end
    for _, m in ipairs(extra) do list[#list + 1] = m end
    return list
end

local Frame = class("Frame", extend(Region, {
    "SetMovable", "EnableMouse", "RegisterForDrag", "SetFrameStrata",
    "StartMoving", "StopMovingOrSizing", "RegisterEvent", "UnregisterEvent",
    "SetAutoFocus", "SetMaxLetters", "SetCursorPosition", "ClearFocus",
    "SetHeight", "SetScrollChild",
}))
local FontString = class("FontString", extend(Region, { "SetJustifyH", "SetWidth" }))
local Line = class("Line", extend(Region, { "SetThickness" }))

local function track(obj)
    obj.shown = true
    return obj
end

-- Stateful overrides for the members the tests inspect.
local function makeFontString()
    local fs = track(FontString())
    function fs:SetText(text) self.text = text end
    function fs:GetStringHeight() return 14 end
    function fs:SetShown(shown) self.shown = shown end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    return fs
end

local function makeLine()
    local line = track(Line())
    function line:SetStartPoint(_, _, x, y) self.startX, self.startY = x, y end
    function line:SetEndPoint(_, _, x, y) self.endX, self.endY = x, y end
    function line:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function line:Show() self.shown = true end
    function line:Hide() self.shown = false end
    return line
end

local function makeFrame(name, template)
    local f = Frame({ name = name })
    f.shown = true
    if name then _G[name] = f end -- named frames become globals, as in the client
    function f:GetName() return self.name end
    function f:SetScript(event, fn) rawset(self, "scripts", rawget(self, "scripts") or {}); self.scripts[event] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetShown(shown) self.shown = shown and true or false end
    f.enabled = true
    function f:Enable() self.enabled = true end
    function f:Disable() self.enabled = false end
    function f:CreateFontString() return makeFontString() end
    function f:CreateLine() return makeLine() end
    function f:SetText(text) self.text = text end
    function f:GetText() return self.text or "" end
    function f:SetChecked(checked) self.checked = checked and true or false end
    function f:GetChecked() return self.checked or false end
    if template == "BasicFrameTemplateWithInset" then
        f.TitleText = makeFontString()
    end
    return f
end

function InstallWowStub(options)
    options = options or {}
    UIParent = makeFrame("UIParent")
    UISpecialFrames = {}
    SlashCmdList = {}
    RAID_CLASS_COLORS = {}
    for i, classFile in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
                                 "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        RAID_CLASS_COLORS[classFile] = { r = i / 10, g = 1 - i / 10, b = 0.5 }
    end
    tinsert = table.insert
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    CreateFrame = function(_, name, _, template) return makeFrame(name, template) end

    local guild = options.guild or {}
    IsInGuild = function() return #guild > 0 end
    GetNumGuildMembers = function() return #guild end
    GetGuildRosterInfo = function(i)
        local m = guild[i]
        local online = m.online
        if online == nil then online = true end -- members default to online
        return m.name, "Rank", 1, m.level, m.className, "Zone", m.note, "", online, 0, m.classFile
    end
    C_GuildInfo = { GuildRoster = function() end }

    -- Retail Settings API (canvas categories); records what the addon registers/opens.
    Settings = {
        RegisterCanvasLayoutCategory = function(panel, name)
            return { panel = panel, name = name, GetID = function() return 42 end }
        end,
        RegisterAddOnCategory = function(category) Settings.registered = category end,
        OpenToCategory = function(id) Settings.openedId = id end,
    }
end
