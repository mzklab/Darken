local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("infopanel")

-- The module's own readouts: gold, durability, bags, latency, frames, the
-- clock, experience, reputation.
--
-- Every readout is split in two, and the split is visible to the eye here: the
-- value is assembled by a Value function that knows nothing about the panel or
-- about frames and receives everything it needs from the game as an access
-- table (env); the repaint is triggered by a game event from the events field
-- or by a period from the period field. No formatting is done in Value at all
-- — that lives entirely in Format.lua.
--
-- === Why an access table rather than direct calls into the game ===
--
-- Outside the client there is neither GetMoney nor GetNetStats. If Value
-- called them directly, the path from "the game gave a number" to "the player
-- saw a string" could only be checked inside the game, that is, by eye and
-- from memory. The access table is built from a set of globals
-- (Sources.Environment), and the tests need only hand it a set of their own:
-- then the whole path is under test rather than one half of it.
--
-- === How these readouts reach the panel ===
--
-- Exactly as other people's do: each is published into the LibDataBroker
-- registry (Sources.Publish) and read from there by the panel on equal terms
-- with everybody. There is no separate road from our readout to a cell inside
-- the module, and if one ever appears it is a defect, not an
-- optimisation.

local Sources = {}
ns.Sources = Sources

-- The prefix for our readouts' names in the shared registry. The registry is
-- shared across the whole game, and an unprefixed name would sooner or later
-- collide with somebody else's.
local PREFIX = "Darken "
Sources.PREFIX = PREFIX

--- A safe call of one of the client's globals.
-- The name may be absent on this client, and the call may raise: a readout
-- that does not exist is obliged to give an empty value rather than a Lua
-- error.
-- @param g table the set of globals
-- @param name string
-- @param ... any the arguments
-- @return ... whatever the function returned, or nothing
local function call(g, name, ...)
    if type(g) ~= "table" then return nil end
    local fn = g[name]
    if type(fn) ~= "function" then return nil end

    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e
end

-- The compatibility layer's groups in which the game's container functions
-- are declared; these words are the core's contract (docs/module-api.md,
-- section 11) rather than the names of foreign functions. The names live in
-- Core/Compat.lua and nowhere else.
local BAG_SLOTS = "container-slots"
local BAG_FREE  = "container-free-slots"

--- Ask the core for a group's game function.
--
-- The door arrives as an argument rather than being taken from a global for
-- good, for the same reason the set of globals arrives as an argument in
-- Sources.Environment: that way the whole path is tested outside the game.
-- When it is absent, the core's real door is used.
--
-- @param group string the layer group's name
-- @param door function|nil a door of the shape door(group, shape) -> function
-- @return function|nil
local function gameFunction(group, door)
    if type(door) ~= "function" then
        if type(Darken) ~= "table"
            or type(Darken.GetGameFunction) ~= "function" then return nil end
        door = function(g, s) return Darken:GetGameFunction(g, s) end
    end

    local ok, fn = pcall(door, group)
    if not ok or type(fn) ~= "function" then return nil end
    return fn
end

--- The access table to the game.
-- @param g table|nil the set of globals (in the game, _G)
-- @param door function|nil the core's door to the game's functions
-- @return table
function Sources.Environment(g, door)
    local env = {}

    -- The container functions are resolved once per access table rather
    -- than once per bag: the readout is rebuilt on the bags event, and
    -- walking the group for every container would be paying for nothing.
    --
    -- Lazily rather than at once: the access table is built while the
    -- module's file is read, and by that moment the core has not yet
    -- determined the client, so the door would answer with emptiness
    -- forever.
    local containers

    local function bagApi()
        if containers == nil then
            containers = {
                slots = gameFunction(BAG_SLOTS, door),
                free  = gameFunction(BAG_FREE, door),
            }
        end
        return containers
    end

    -- Ask the core afresh. Called when the module is enabled: before that
    -- the door answers with emptiness, and that answer must not be remembered
    -- forever.
    function env.BindGame()
        containers = nil
        return bagApi()
    end

    function env.Money()
        return call(g, "GetMoney")
    end

    function env.MoneySymbols()
        if type(g) ~= "table" then return nil end
        return {
            gold = type(g.GOLD_AMOUNT_SYMBOL) == "string"
                and g.GOLD_AMOUNT_SYMBOL or nil,
            silver = type(g.SILVER_AMOUNT_SYMBOL) == "string"
                and g.SILVER_AMOUNT_SYMBOL or nil,
            copper = type(g.COPPER_AMOUNT_SYMBOL) == "string"
                and g.COPPER_AMOUNT_SYMBOL or nil,
        }
    end

    -- Durability is asked for by the equipped inventory slots. The slot
    -- numbers are the same on every supported client, and for an item without
    -- durability the game simply returns no numbers — such a slot does not
    -- reach the list.
    function env.DurabilitySlots()
        local slots = {}
        for slot = 1, 18 do
            local current, maximum = call(g, "GetInventoryItemDurability", slot)
            if type(current) == "number" and type(maximum) == "number" then
                slots[#slots + 1] = { current = current, maximum = maximum }
            end
        end
        return slots
    end

    -- Bags. Which of the two spellings this client calls container work by
    -- — the C_Container table or the globals — is no longer decided by the
    -- module: the core's compatibility layer decides, and decides once for
    -- the whole addon. There used to be a fork of our own here, the fifth in
    -- a row on one and the same question.
    --
    -- Both functions answer the same way in the two spellings, so the shape
    -- of the answer is not named here: there is nothing to name it for —
    -- nothing to confuse.
    function env.BagSpace()
        local api = bagApi()
        local free, total = 0, 0
        local last = type(g) == "table" and tonumber(g.NUM_BAG_SLOTS) or nil
        if not last then last = 4 end

        local sawAny = false
        for bag = 0, last do
            local slots, freeSlots

            if api.slots ~= nil then
                local ok, value = pcall(api.slots, bag)
                if ok then slots = value end
            end
            if api.free ~= nil then
                local ok, value = pcall(api.free, bag)
                if ok then freeSlots = value end
            end

            if type(slots) == "number" then
                sawAny = true
                total = total + slots
            end
            if type(freeSlots) == "number" then free = free + freeSlots end
        end

        if not sawAny then return nil, nil end
        return free, total
    end

    -- Latency. Old clients return three numbers, new ones four: the third
    -- and the fourth are the latency to one's own realm and to the world
    -- server.
    function env.Latency()
        local a, b, c, d = call(g, "GetNetStats")
        if type(d) == "number" then return c, d end
        if type(c) == "number" then return c, nil end
        return nil, nil
    end

    function env.Framerate()
        return call(g, "GetFramerate")
    end

    -- Time. The local time of the player's machine is taken rather than the
    -- game's: a clock in the panel is there so one does not miss things
    -- outside the game.
    function env.Time()
        if type(g) ~= "table" or type(g.date) ~= "function" then
            return nil, nil, nil
        end

        local ok, t = pcall(g.date, "*t")
        if not ok or type(t) ~= "table" then return nil, nil, nil end
        return t.hour, t.min, t.sec
    end

    function env.Experience()
        local current = call(g, "UnitXP", "player")
        local maximum = call(g, "UnitXPMax", "player")
        local rested = call(g, "GetXPExhaustion")
        return current, maximum, rested
    end

    -- The watched faction. In new builds the information is returned as a
    -- table, in old ones as a list of values; whichever exists is asked
    -- for.
    function env.Reputation()
        local reputation = type(g) == "table" and g.C_Reputation or nil
        if type(reputation) == "table"
            and type(reputation.GetWatchedFactionData) == "function" then
            local ok, data = pcall(reputation.GetWatchedFactionData)
            if ok and type(data) == "table" then
                return data.name, nil,
                    (data.currentStanding or 0) - (data.currentReactionThreshold or 0),
                    (data.nextReactionThreshold or 0) - (data.currentReactionThreshold or 0)
            end
        end

        local name, standing, minimum, maximum, value =
            call(g, "GetWatchedFactionInfo")
        if type(name) ~= "string" or name == "" then return nil end
        if type(minimum) ~= "number" or type(maximum) ~= "number"
            or type(value) ~= "number" then
            return name, nil, nil, nil
        end

        return name, standing, value - minimum, maximum - minimum
    end

    return env
end

-- Translation. The real one is installed in InfoPanel.lua once the core hands
-- over the descriptor; a fallback is declared here so the file lives without
-- it: an untranslated label stays English, and that is right — it is the key
-- itself.
if type(ns.Localize) ~= "function" then
    function ns.Localize(key)
        if key == nil or key == "" then return "" end
        return key
    end
end

-- The description of the readouts.
--
-- events are the game events the value is rebuilt on. period is the interval
-- in seconds for the three that have no event at all: frames, latency and the
-- clock. No readout has both fields at once, and none must: when there is an
-- event, a period would be polling laid over it.
local LIST = {
    {
        key = "gold",
        events = { "PLAYER_MONEY" },
        Label = function() return ns.Localize("Gold") end,
        Value = function(env)
            return ns.Format.Money(env.Money(), env.MoneySymbols())
        end,
    },
    {
        key = "durability",
        events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" },
        Label = function() return ns.Localize("Durability") end,
        Value = function(env)
            local percent = ns.Format.Durability(env.DurabilitySlots())
            if percent == nil then return ns.Format.NONE end
            return percent .. "%"
        end,
    },
    {
        key = "bags",
        events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },
        Label = function() return ns.Localize("Bags") end,
        Value = function(env)
            local free, total = env.BagSpace()
            return ns.Format.Bags(free, total)
        end,
    },
    {
        key = "latency",
        -- Five seconds rather than one: the game itself recomputes the
        -- latency once every thirty seconds, and asking it more often means
        -- showing the same number and paying frames for it.
        period = 5,
        Label = function() return ns.Localize("Latency") end,
        Value = function(env)
            local home, world = env.Latency()
            return ns.Format.Latency(home, world)
        end,
    },
    {
        key = "fps",
        period = 1,
        Label = function() return ns.Localize("Frames") end,
        Value = function(env)
            return ns.Format.Fps(env.Framerate())
        end,
    },
    {
        key = "clock",
        period = 1,
        Label = function() return ns.Localize("Clock") end,
        Value = function(env, settings)
            local hour, minute, second = env.Time()
            local twelve = type(settings) == "table" and settings.clock12 or false
            local seconds = type(settings) == "table"
                and settings.clockSeconds or false
            return ns.Format.Clock(hour, minute, second, twelve, seconds)
        end,
    },
    {
        key = "experience",
        events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
            "PLAYER_ENTERING_WORLD" },
        Label = function() return ns.Localize("Experience") end,
        Value = function(env, settings)
            local current, maximum, rested = env.Experience()
            local mode = type(settings) == "table" and settings.xpMode or nil
            return ns.Format.Experience(current, maximum, rested, mode)
        end,
    },
    {
        key = "reputation",
        events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },
        Label = function() return ns.Localize("Reputation") end,
        Value = function(env, settings)
            local name, standing, value, maximum = env.Reputation()
            local mode = type(settings) == "table" and settings.repMode or nil
            return ns.Format.Reputation(name, standing, value, maximum, mode)
        end,
    },
}
Sources.LIST = LIST

--- A readout's name in the shared registry.
-- English and unchanging: it goes into the player's profile as the order of
-- cells, and a translation in its place would change that order when the
-- client's language changed.
-- @param key string
-- @return string
function Sources.Name(key)
    return PREFIX .. tostring(key)
end

--- The readouts that have no event and do have a period.
-- @return table array of descriptions
function Sources.Timed()
    local out = {}
    for i = 1, #LIST do
        if LIST[i].period then out[#out + 1] = LIST[i] end
    end
    return out
end

--- Which of the timed readouts are due to be rebuilt.
--
-- This is the whole answer to "how do the frames and the latency update": one
-- shared tick rather than a timer per cell, and on every tick only what has
-- come due is rebuilt. The tick lives on the panel's own frame, so a hidden
-- panel counts nothing.
-- @param list table array of descriptions
-- @param state table|nil the time of the last rebuild, by key
-- @param now number the current time
-- @param wanted table|nil the set of displayed names; nil means all of them
-- @return table array of descriptions
function Sources.Due(list, state, now, wanted)
    local out = {}
    if type(list) ~= "table" or type(now) ~= "number" then return out end

    for i = 1, #list do
        local entry = list[i]
        local period = tonumber(entry.period)
        if period and period > 0 then
            local skip = false
            if type(wanted) == "table" and not wanted[Sources.Name(entry.key)] then
                skip = true
            end

            if not skip then
                local last = type(state) == "table" and state[entry.key] or nil
                if type(last) ~= "number" or now - last >= period then
                    out[#out + 1] = entry
                end
            end
        end
    end

    return out
end

--- Record a rebuild.
-- @param state table
-- @param key string
-- @param now number
function Sources.Mark(state, key, now)
    if type(state) ~= "table" then return end
    state[key] = now
end

--- Every game event of our readouts, without repeats.
-- @return table array of event names
function Sources.Events()
    local seen, out = {}, {}
    for i = 1, #LIST do
        for _, event in ipairs(LIST[i].events or {}) do
            if not seen[event] then
                seen[event] = true
                out[#out + 1] = event
            end
        end
    end
    return out
end

--- The readouts this event rebuilds.
-- @param event string
-- @return table array of descriptions
function Sources.For(event)
    local out = {}
    for i = 1, #LIST do
        for _, name in ipairs(LIST[i].events or {}) do
            if name == event then out[#out + 1] = LIST[i] end
        end
    end
    return out
end

--- Publish our readouts into the registry.
-- By the same call any other addon does it with. A table of key -> registry
-- object is returned, so that there is somewhere to write a new value.
-- @param broker table the registry
-- @return table
function Sources.Publish(broker)
    local published = {}
    if type(broker) ~= "table" or type(broker.NewDataObject) ~= "function" then
        return published
    end

    for i = 1, #LIST do
        local entry = LIST[i]
        local name = Sources.Name(entry.key)

        -- The name in the registry may already be taken: by our own object
        -- from a previous move, or by another addon with the same name.
        -- Creating it a second time is not allowed — the standard forbids it,
        -- and rightly so.
        local object
        if type(broker.GetDataObjectByName) == "function" then
            local ok, found = pcall(broker.GetDataObjectByName, broker, name)
            if ok then object = found end
        end

        if object == nil then
            object = broker:NewDataObject(name, {
                type = "data source",
                label = entry.Label(),
                text = ns.Format.NONE,
            })
        end

        if object ~= nil then published[entry.key] = object end
    end

    return published
end

--- Rebuild one readout's value and write it into the registry.
-- Writing into the registry object is the only way the module shows its value:
-- the panel reads the registry and knows nothing about this function.
-- @param entry table the readout's description
-- @param object table|nil the registry object
-- @param env table the access table
-- @param settings table|nil the module's settings
-- @return string|nil the value that was written
function Sources.Update(entry, object, env, settings)
    if type(entry) ~= "table" or object == nil then return nil end

    local ok, value = pcall(entry.Value, env, settings)
    if not ok or type(value) ~= "string" then value = ns.Format.NONE end

    object.label = entry.Label()
    object.text = value
    return value
end
