local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("infopanel")

-- Access to the readouts of the LibDataBroker standard.
--
-- The whole point of the info panel is that the readouts in it belong to
-- others. Any addon of the player's that speaks LibDataBroker publishes its
-- value into a shared registry, and the panel shows it knowing nothing about
-- it. Our own readouts are published into the same place by the same call, so
-- in the panel they are no different from anybody else's: one and the same
-- road from the registry to a line on screen, and not one check of "is this
-- ours".
--
-- === Where the library itself comes from ===
--
-- LibDataBroker-1.1 is somebody else's library and is not part of the core's
-- distribution. But it is part of almost every addon that publishes readouts:
-- libraries live in LibStub, and the first addon to load creates it for
-- everybody. So the module does not bring it along but asks for it.
--
-- If it is absent entirely, then there is not one foreign readout either, and
-- nothing to show. A small replacement of our own is then created with the
-- same set of calls: our readouts are published into it and the panel reads
-- it with the same code. The replacement does not pass itself off as the
-- library and does not enter LibStub — declaring oneself somebody else's
-- library would take the name away from the real one.
--
-- The real library may also appear later than we do (an addon loaded on
-- demand). Our readouts then move into it all at once (Broker.Acquire), and
-- other people's become visible without a reload of the interface.

local Broker = {}
ns.Broker = Broker

-- The library's name in LibStub. As a string in one place: a typo in it
-- would silently give an empty panel.
local LIB = "LibDataBroker-1.1"
Broker.LIB = LIB

-- The library's event for a readout's value having changed, and the event
-- for a new readout appearing. The names are part of somebody else's
-- standard.
local CHANGED = "LibDataBroker_AttributeChanged"
local CREATED = "LibDataBroker_DataObjectCreated"
Broker.CHANGED = CHANGED
Broker.CREATED = CREATED

--- The real library, if this installation has it.
-- LibStub is a table with a __call metamethod, and the second argument `true`
-- means "absent is not an error".
-- @param libstub table|nil
-- @return table|nil
function Broker.Resolve(libstub)
    if type(libstub) ~= "table" and type(libstub) ~= "function" then
        return nil
    end

    local ok, lib = pcall(libstub, LIB, true)
    if not ok or type(lib) ~= "table" then return nil end
    if type(lib.NewDataObject) ~= "function" then return nil end
    if type(lib.DataObjectIterator) ~= "function" then return nil end

    return lib
end

--- Our own replacement for the library: the same set of calls and nothing
--- beyond it.
--
-- The construction repeats the standard: a readout is exposed not as a table
-- of values but as a proxy, writes into which are broadcast to the
-- subscribers. Otherwise the publisher would change a field and the panel
-- would never learn of it — and updating would turn into polling by a timer,
-- that is, into exactly what must not be in this module.
-- @return table
function Broker.NewShim()
    local shim = {}
    local values = {}      -- proxy -> its values
    local names = {}       -- proxy -> name
    local objects = {}     -- name -> proxy
    local listeners = {}   -- event -> { owner -> function }

    shim.shim = true

    local function fire(event, ...)
        local bucket = listeners[event]
        if not bucket then return end
        for _, fn in pairs(bucket) do
            -- One subscriber's error must not leave the rest without a
            -- value: the broadcast goes under a guard.
            pcall(fn, event, ...)
        end
    end

    local meta = {
        __index = function(self, key)
            local own = values[self]
            return own and own[key]
        end,
        __newindex = function(self, key, value)
            local own = values[self]
            if not own then return end
            if own[key] == value then return end
            own[key] = value
            fire(CHANGED, names[self], key, value, self)
        end,
    }

    function shim:NewDataObject(name, source)
        if type(name) ~= "string" or name == "" then return nil end
        if objects[name] then return objects[name] end

        local object = setmetatable({}, meta)
        values[object] = {}
        names[object] = name
        objects[name] = object

        if type(source) == "table" then
            for key, value in pairs(source) do values[object][key] = value end
        end

        fire(CREATED, name, object)
        return object
    end

    function shim:DataObjectIterator()
        return pairs(objects)
    end

    function shim:GetDataObjectByName(name)
        return objects[name]
    end

    function shim:GetNameByDataObject(object)
        return names[object]
    end

    -- The subscription is written the way CallbackHandler writes it for the
    -- real library: a function on the library itself, with the owner as the
    -- first argument.
    function shim.RegisterCallback(owner, event, fn)
        if owner == nil or type(event) ~= "string" then return end
        if type(fn) ~= "function" then return end
        listeners[event] = listeners[event] or {}
        listeners[event][owner] = fn
    end

    function shim.UnregisterCallback(owner, event)
        local bucket = listeners[event]
        if bucket then bucket[owner] = nil end
    end

    -- A snapshot of a readout's values. Needed only by the move to the real
    -- library: a proxy's values are hidden behind a metatable.
    function shim:Snapshot(name)
        local object = objects[name]
        if not object then return nil end

        local copy = {}
        for key, value in pairs(values[object] or {}) do copy[key] = value end
        return copy
    end

    function shim:Names()
        local list = {}
        for name in pairs(objects) do list[#list + 1] = name end
        table.sort(list)
        return list
    end

    return shim
end

--- The registry the module currently lives in.
--
-- Returns the real library when it exists and our replacement when it does
-- not. When the real one appeared later, the readouts move into it from the
-- replacement — otherwise ours would stay apart from everybody else's, and
-- that is exactly the separation that must not exist here.
-- @param libstub table|nil
-- @param previous table|nil the registry obtained last time
-- @return table the registry
-- @return boolean whether a move happened
function Broker.Acquire(libstub, previous)
    local real = Broker.Resolve(libstub)

    if real == nil then
        if type(previous) == "table" then return previous, false end
        return Broker.NewShim(), false
    end

    if previous == real then return real, false end

    if type(previous) == "table" and previous.shim
        and type(previous.Names) == "function" then
        local moved = false
        for _, name in ipairs(previous:Names()) do
            if real:GetDataObjectByName(name) == nil then
                real:NewDataObject(name, previous:Snapshot(name))
                moved = true
            end
        end
        return real, moved
    end

    return real, false
end

--- Whether this readout is shown in the panel.
--
-- One shared rule: a readout is shown when it has something to show. The
-- standard's launcher buttons (type "launcher") carry an icon and a click but
-- no text — this increment of the panel does not show them, and that is
-- written down here rather than as a check of a name.
-- @param object table|nil
-- @return boolean
function Broker.Displayable(object)
    if type(object) ~= "table" then return false end

    local ok, text = pcall(function() return object.text end)
    if ok and type(text) == "string" and text ~= "" then return true end

    ok, text = pcall(function() return object.value end)
    if ok and (type(text) == "string" or type(text) == "number") then
        return true
    end

    return false
end

--- A readout's label and value.
--
-- A foreign readout gives either finished text (text) or a number with a
-- value and a suffix (value and suffix) — both shapes are described by the
-- standard. Our readouts give the first and have no other path.
-- @param object table|nil
-- @return string|nil the label
-- @return string|nil the value
function Broker.Text(object)
    if type(object) ~= "table" then return nil, nil end

    local function attribute(key)
        local ok, value = pcall(function() return object[key] end)
        if ok then return value end
        return nil
    end

    local label = attribute("label")
    if type(label) ~= "string" or label == "" then label = nil end

    local text = attribute("text")
    if type(text) == "string" and text ~= "" then return label, text end

    local value = attribute("value")
    if type(value) == "number" then value = tostring(value) end
    if type(value) == "string" and value ~= "" then
        local suffix = attribute("suffix")
        if type(suffix) == "string" and suffix ~= "" then
            return label, value .. suffix
        end
        return label, value
    end

    return label, nil
end

--- The names of every readout in the registry the panel can show.
-- Ordered by name: the list goes into the settings and has to be the same
-- from run to run, while a table walk in Lua has no order.
-- @param broker table|nil
-- @return table array of names
function Broker.Names(broker)
    local list = {}
    if type(broker) ~= "table" then return list end
    if type(broker.DataObjectIterator) ~= "function" then return list end

    local ok, iterator, state, control = pcall(broker.DataObjectIterator, broker)
    if not ok or type(iterator) ~= "function" then return list end

    for name, object in iterator, state, control do
        if type(name) == "string" and Broker.Displayable(object) then
            list[#list + 1] = name
        end
    end

    table.sort(list)
    return list
end

--- Subscribe to a registry event.
-- The wrapper is needed because subscribing is written the same way for the
-- real library and for the replacement, while on somebody else's library the
-- subscription may raise.
-- @param broker table|nil
-- @param owner any
-- @param event string
-- @param fn function
-- @return boolean
function Broker.Subscribe(broker, owner, event, fn)
    if type(broker) ~= "table" or type(fn) ~= "function" then return false end
    if type(broker.RegisterCallback) ~= "function" then return false end

    local ok = pcall(broker.RegisterCallback, owner, event, fn)
    return ok and true or false
end
