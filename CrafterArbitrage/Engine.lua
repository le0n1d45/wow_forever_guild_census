local addonName, ns = ...

-- Runs the calculator over every recipe and ranks what pays. Work is done in small steps (Job:Step) so the
-- game does not stall: about 2,000 recipes.

local Engine = {}
ns.Engine = Engine

local STEP_RECIPES = 60 -- recipes per step when there is no timer to go by
local STEP_MS = 8

local function now()
    return debugprofilestop and debugprofilestop() or nil
end

-- options: channel ("vendor" or "ah"), filter ("known", "learnable" or "all"), neutral (neutral AH),
-- useBags (reagents in bags cost nothing), minProfit (copper, for the whole run of crafts).
function Engine.NewJob(options)
    local list, bySpell = {}, {}
    for name, prof in pairs(ns.Data) do
        if type(prof) == "table" and prof.recipes then
            for spell, recipe in pairs(prof.recipes) do
                local entry = { prof = name, skillLine = prof.skillLine, spell = spell, recipe = recipe }
                list[#list + 1] = entry
                bySpell[spell] = entry
            end
        end
    end
    table.sort(list, function(a, b) return a.spell < b.spell end)

    local statusOf = {}
    local function status(entry)
        local s = statusOf[entry.spell]
        if not s then
            s = ns.Known.Status(entry.skillLine, entry.spell, entry.recipe)
            statusOf[entry.spell] = s
        end
        return s
    end
    local allowed = { known = { known = true }, learnable = { known = true, trainer = true } }
    local filter = allowed[options.filter]
    local function permitted(entry) return filter == nil or filter[status(entry)] or false end

    local have
    if options.useBags and GetItemCount then
        have = setmetatable({}, { __index = function(t, id) local n = GetItemCount(id) or 0; t[id] = n; return n end })
    end
    local ctx = {
        channel = options.channel or "vendor", neutral = options.neutral, have = have or {},
        canCraft = function(_, spell)
            return filter == nil or permitted(bySpell[spell])
        end,
    }
    local job = { results = {}, done = false, total = #list, index = 0 }
    local minProfit = options.minProfit or 0

    function job:Step()
        local started, count = now(), 0
        while self.index < self.total do
            self.index = self.index + 1
            local entry = list[self.index]
            if permitted(entry) then
                local r = ns.Calc.Evaluate(entry.recipe, ctx)
                if r and r.crafts > 0 and r.profit > 0 and r.profit >= minProfit then
                    self.results[#self.results + 1] = {
                        spell = entry.spell, prof = entry.prof, recipe = entry.recipe,
                        status = status(entry), eval = r,
                    }
                end
            end
            count = count + 1
            if started then
                if now() - started > STEP_MS then break end
            elseif count >= STEP_RECIPES then
                break
            end
        end
        if self.index >= self.total then
            self.done = true
            table.sort(self.results, function(a, b)
                if a.eval.profit ~= b.eval.profit then return a.eval.profit > b.eval.profit end
                return a.spell < b.spell
            end)
        end
        return self.done
    end

    return job
end

-- Runs a job to completion at once (tests, slash command).
function Engine.Run(options)
    local job = Engine.NewJob(options)
    while not job:Step() do end
    return job.results
end
