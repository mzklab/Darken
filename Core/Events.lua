local ADDON, ns = ...

-- Game events for modules.
--
-- Why this lives in the core. Every module needs events before it needs
-- settings: the bags redraw on BAG_UPDATE_DELAYED, the panel on a form
-- change, the bar on a cast starting. The public contract said nothing about
-- events, and every module created a receiver frame of its own. That works
-- right up to the first error in a handler: a raw SetScript("OnEvent") is
-- unguarded, and a foreign module's handler that raises shows the player a
-- yellow error in the middle of combat. The one who looks at fault is Darken,
-- not whoever wrote the handler.
--
-- So there is one receiver and it is ours, while module handlers are called
-- through the same door as everything else foreign — ns.Registry:Protect. A
-- handler that raises disables its own module and touches neither the core
-- nor its neighbours, exactly like an ApplySettings that raises.
--
-- Isolation: a subscription is stored under the module's name, and that name
-- comes from the descriptor (a closure in Core/Api.lua) rather than from a
-- table the module can rewrite. A module cannot reach another's
-- subscription — neither read it nor remove it.
local Events = {
    -- [event] = { [module name] = function }
    listeners = {},

    -- [event] = array of core functions. The core is not a module: there is
    -- nobody to disable it, so its handlers go through a plain pcall.
    core = {},

    -- [event] = true once we have asked the game for that event.
    asked = {},

    -- [event] = how many times the engine refused to register it.
    --
    -- The refusal used to be swallowed silently, and that was a hole in the
    -- diagnostics themselves rather than a detail. A subsystem whose event
    -- the engine did not accept does nothing — and looks exactly like a
    -- subsystem whose event was accepted and never delivered. That is
    -- precisely where the investigation of the nameplates' zero count stalled:
    -- "the game showed no nameplates" and "the game rejected our subscription
    -- to NAME_PLATE_UNIT_ADDED" were indistinguishable.
    --
    -- Only a real refusal by the engine is recorded — an exception out of
    -- RegisterEvent. A missing receiver does not count as a refusal: outside
    -- the game there is none at all, and a "failed" entry would stand in
    -- every test run meaning nothing.
    refused = {},

    -- [event] = array of subscriber names, alphabetically.
    --
    -- The dispatch order must be stable (pairs does not give that), and the
    -- list of names must not be taken per event: at the height of combat the
    -- door opens a hundred times a frame, and a table plus a sort per opening
    -- is a hundred tables of garbage per frame. Measured on the whole addon:
    -- the door itself cost 86 bytes and 0.0004 ms per event, that is, more
    -- than the work of the nameplate handler, which honestly documents that
    -- it allocates nothing.
    --
    -- The list is rebuilt only on subscribe and unsubscribe. Dispatch keeps it
    -- in a local, so a handler that removes somebody's subscription during
    -- dispatch (it raised and the registry disabled it) replaces the table
    -- with a new one while the running loop finishes on the old — exactly the
    -- property a copy used to be taken for.
    order = {},

    -- The addon's single receiver frame. Outside the game there is none, and
    -- that is not a failure: Dispatch stays callable, and the rule is tested
    -- entirely without a client.
    frame = nil,
}
ns.Events = Events

--- Create the receiver, if the engine allows it.
-- @return table|nil the frame
local function ensure()
    if Events.frame ~= nil then return Events.frame end
    if type(CreateFrame) ~= "function" then return nil end

    local ok, frame = pcall(CreateFrame, "Frame")
    if not ok or type(frame) ~= "table" then return nil end

    Events.frame = frame

    if type(frame.SetScript) == "function" then
        pcall(frame.SetScript, frame, "OnEvent", function(_, event, ...)
            Events.Dispatch(event, ...)
        end)
    end

    return frame
end

--- Ask the game for an event.
-- @param event string
local function ask(event)
    if Events.asked[event] then return end

    local frame = ensure()
    if frame == nil or type(frame.RegisterEvent) ~= "function" then return end

    -- The event name came from a module's author, and a typo in it is not
    -- our mistake — but we have no right to fail because of it either: the
    -- engine raises on an unknown name.
    if pcall(frame.RegisterEvent, frame, event) then
        Events.asked[event] = true
        -- Accepted on a later attempt: the earlier refusal is no longer a
        -- fact about the client. The report must describe what holds now.
        Events.refused[event] = nil
    else
        Events.refused[event] = (Events.refused[event] or 0) + 1
    end
end

--- What the engine refused to register.
--
-- An array rather than a map: the list is read by eye from disk and in chat,
-- and the order must be stable between runs. Called once, at report time.
--
-- @return table array of { event = event name, tries = refusal count }
function Events.Refused()
    local out = {}
    for event, tries in pairs(Events.refused) do
        out[#out + 1] = { event = event, tries = tonumber(tries) or 0 }
    end
    table.sort(out, function(a, b) return a.event < b.event end)
    return out
end

--- How many events the engine accepted.
-- @return number
function Events.Accepted()
    local count = 0
    for _ in pairs(Events.asked) do count = count + 1 end
    return count
end

--- Whether an event has any listener at all.
-- @param event string
-- @return boolean
local function used(event)
    local byModule = Events.listeners[event]
    if type(byModule) == "table" and next(byModule) ~= nil then return true end

    local byCore = Events.core[event]
    return type(byCore) == "table" and #byCore > 0
end

--- Drop an event nobody is watching any more.
-- Without this a switched-off module would keep costing the player frames:
-- the event would arrive, the receiver would wake up and find nobody to hand
-- it to.
-- @param event string
local function forget(event)
    if not Events.asked[event] then return end
    if used(event) then return end

    local frame = Events.frame
    if frame ~= nil and type(frame.UnregisterEvent) == "function" then
        pcall(frame.UnregisterEvent, frame, event)
    end
    Events.asked[event] = nil
end

--- Rebuild the dispatch order for an event.
-- A new table rather than an edit of the old one: a running dispatch holds
-- the old one in a local and must finish on it.
-- @param event string
local function reorder(event)
    local byModule = Events.listeners[event]
    if byModule == nil then
        Events.order[event] = nil
        return
    end

    local names = {}
    for moduleName in pairs(byModule) do names[#names + 1] = moduleName end
    table.sort(names)
    Events.order[event] = names
end

--- Subscribe a module to an event.
-- One handler per event-and-module pair: subscribing again replaces the
-- previous handler rather than adding a second. A module subscribing from
-- ApplySettings (which is legitimate: ApplySettings runs on every profile
-- change) would otherwise accumulate handlers and do the work once per
-- change.
-- @param event string the game event's name
-- @param moduleName string the module's name
-- @param fn function the handler; called with (event, ...)
-- @return boolean whether the subscription was accepted
function Events.Subscribe(event, moduleName, fn)
    if type(event) ~= "string" or event == "" then return false end
    if type(moduleName) ~= "string" or moduleName == "" then return false end
    if type(fn) ~= "function" then return false end

    -- A switched-off module does not resubscribe, and that is not strictness
    -- for its own sake. The core removes subscriptions once — at the moment
    -- it disables a module — while the module's own code keeps running: its
    -- timer, its OnUpdate, a hook on somebody else's frame. One line from
    -- there was enough to bring the subscription back, and there was nobody
    -- left to remove it a second time: Disable stays quiet for a name already
    -- disabled. The core's receiver would then wake on every such event until
    -- the interface is reloaded, while Protect would refuse it entry into the
    -- module anyway — a pure waste of the player's frames.
    --
    -- The table is checked for presence: the registry is not always loaded
    -- first, and in tests it may be absent entirely.
    if type(ns.Registry) == "table" and ns.Registry:IsFailed(moduleName) then
        return false
    end

    local byModule = Events.listeners[event]
    if not byModule then
        byModule = {}
        Events.listeners[event] = byModule
    end
    byModule[moduleName] = fn
    reorder(event)

    ask(event)
    return true
end

--- Remove a module's subscription.
-- @param event string
-- @param moduleName string
-- @return boolean whether there was a subscription
function Events.Unsubscribe(event, moduleName)
    if type(event) ~= "string" or type(moduleName) ~= "string" then
        return false
    end

    local byModule = Events.listeners[event]
    if not byModule or byModule[moduleName] == nil then return false end

    byModule[moduleName] = nil
    if next(byModule) == nil then Events.listeners[event] = nil end
    reorder(event)
    forget(event)
    return true
end

--- Remove every subscription of a module.
-- Called by the registry when it disables a module: the core stops calling
-- inside, and events must stop arriving too. Otherwise a module that raised
-- would keep waking up on every event until the interface is reloaded —
-- Protect would refuse it entry, but the event would still travel through the
-- engine.
-- @param moduleName string
-- @return number how many subscriptions were removed
function Events.DropModule(moduleName)
    if type(moduleName) ~= "string" or moduleName == "" then return 0 end

    local dropped = 0
    -- The event names are taken before the loop: Unsubscribe edits the same
    -- table.
    local names = {}
    for event in pairs(Events.listeners) do names[#names + 1] = event end

    for i = 1, #names do
        if Events.Unsubscribe(names[i], moduleName) then
            dropped = dropped + 1
        end
    end
    return dropped
end

--- The core's own subscription.
-- A separate list, because the core is not a module: it has no name it could
-- be disabled under, and the registry's protection does not apply to it. A
-- core handler is our code, and a failure in it must be visible during
-- development rather than disable somebody else's module.
--
-- Subscribing the same function to the same event again does not add a second
-- handler: see the explanation inside.
-- @param event string
-- @param fn function
-- @return boolean
function Events.Core(event, fn)
    if type(event) ~= "string" or event == "" then return false end
    if type(fn) ~= "function" then return false end

    local list = Events.core[event]
    if not list then
        list = {}
        Events.core[event] = list
    end

    -- Deduplication, by the same rule as Events.Subscribe: one function on
    -- one event lives in the list once. There is nothing to remove a core
    -- handler with — Events.DropModule walks only Events.listeners, and the
    -- core has no name to be disabled under — so a duplicate would be
    -- permanent and silent. The cost is one walk of the list per core
    -- subscription: there are a handful of those, created while the files are
    -- read.
    for i = 1, #list do
        if list[i] == fn then
            ask(event)
            return true
        end
    end

    list[#list + 1] = fn

    ask(event)
    return true
end

--- Dispatch an event to its subscribers.
-- Called by the receiver, and in tests directly: the dispatch rule must not
-- require a client in order to be tested.
--
-- The loop walks a pre-taken list of names rather than the table itself: a
-- handler that raises disables its own module, and disabling edits the
-- registry's state and removes subscriptions — that is, the very table pairs
-- would be walking.
--
-- @param event string
-- @param ... the event's arguments
-- @return number how many handlers ran without error
function Events.Dispatch(event, ...)
    if type(event) ~= "string" or event == "" then return 0 end

    local done = 0

    local byCore = Events.core[event]
    if type(byCore) == "table" then
        for i = 1, #byCore do
            if pcall(byCore[i], event, ...) then done = done + 1 end
        end
    end

    local byModule = Events.listeners[event]
    if type(byModule) ~= "table" then return done end

    -- The list of names was taken at subscribe time, not here: see the note
    -- on Events.order.
    local names = Events.order[event]
    if type(names) ~= "table" then return done end

    for i = 1, #names do
        local moduleName = names[i]
        local fn = byModule[moduleName]
        if type(fn) == "function" then
            local ok = ns.Registry:Protect(
                moduleName, "event " .. event, fn, event, ...)
            if ok then done = done + 1 end
        end
    end

    return done
end

--- How many modules listen to an event.
-- Needed by the tests and by the core itself; not exposed — a foreign module
-- has no business knowing how many neighbours it has.
-- @param event string
-- @return number
function Events.Count(event)
    local byModule = Events.listeners[event]
    if type(byModule) ~= "table" then return 0 end

    local count = 0
    for _ in pairs(byModule) do count = count + 1 end
    return count
end
