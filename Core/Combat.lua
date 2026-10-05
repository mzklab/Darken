local ADDON, ns = ...

-- Work deferred until combat ends.
--
-- The engine forbids some work while the player is in combat: creating and
-- reparenting protected frames, editing a protected button's attributes,
-- moving a protected object. The prohibition is not ours and cannot be worked
-- around — the work can only be deferred until PLAYER_REGEN_ENABLED.
--
-- The core's rule, written here once: work is deferred when the operation is
-- protected AND the object answers IsProtected. Nobody forbids touching an
-- ordinary frame in combat, and deferring would make the addon sluggish for
-- nothing. Protectedness is asked of the object itself rather than inferred
-- from its name: it is inherited from the parent, and a list of names would
-- diverge from the client at the very first patch.
--
-- The queue keeps the order of keys separate from the actions: writing again
-- under the same key displaces the previous action while keeping its place in
-- the queue. What matters is the order of first appearance rather than of the
-- last edit — otherwise leaving combat would replay the whole history of
-- edits in a row, as a visible jolt through intermediate values.
--
-- The file was assembled from what had already been written and tested in the
-- unit frames subsystem: the queue moved here whole, and ns.UnitFrames.NewQueue
-- and its neighbours remained names for the very same function. There is no
-- second copy of the rule in the addon and there must not be — it was
-- precisely a second copy that made modules need this door.
-- The tally of work done (Core/Tally.lua). The reference is taken once while
-- the file is read, after which incrementing a counter is a single integer
-- addition: this path is hot. The table is created "if not already there":
-- the tests load the core one file at a time, and Core/Tally.lua is sometimes
-- not loaded at all.
local counters = ns.Counters or {}
ns.Counters = counters

-- The counters are claimed here and now. A claimed zero means "there was
-- nothing to defer", an unclaimed one means "this subsystem is not in the
-- build"; the difference is visible in the report and costs one line.
counters.deferred = counters.deferred or 0
counters.drained  = counters.drained  or 0

local Combat = {
    -- [module name] = queue. A module's queue is created by its first
    -- deferred piece of work and lives until the interface is reloaded. The
    -- name arrives as a closure from the descriptor (Core/Api.lua), so a
    -- module cannot reach another's queue.
    queues = {},
}
ns.Combat = Combat

--- An empty queue of deferred changes.
-- @return table
function Combat.NewQueue()
    return { order = {}, actions = {} }
end

--- Put an action into the queue under a key.
-- @param queue table the queue
-- @param key string the key
-- @param action function the action
-- @return boolean whether it was accepted
function Combat.Enqueue(queue, key, action)
    if type(queue) ~= "table" or type(queue.actions) ~= "table" then return false end
    if type(key) ~= "string" or key == "" then return false end
    if type(action) ~= "function" then return false end

    if queue.actions[key] == nil then
        queue.order[#queue.order + 1] = key
    end
    queue.actions[key] = action

    -- What is counted is what was put into the queue, not what displaced
    -- something: ten movements of one frame in combat are ten deferred
    -- operations, and that is exactly how much work the addon did not do
    -- during the fight.
    counters.deferred = counters.deferred + 1
    return true
end

--- How many actions are waiting in the queue.
-- @param queue table
-- @return number
function Combat.Pending(queue)
    if type(queue) ~= "table" or type(queue.order) ~= "table" then return 0 end
    return #queue.order
end

--- Run the queue and empty it.
--
-- The queue is emptied before the actions run, not after. An action may itself
-- cause a new deferred entry (a setting was applied and immediately re-read),
-- and clearing afterwards would erase it — exactly the kind of defect that
-- takes hours to find.
--
-- Every action runs guarded, and the caller chooses the guard: our own
-- subsystems make do with pcall, while a module's action is called through the
-- registry so that a failure disables that module by name. No guard here would
-- mean one failing action aborts the rest.
--
-- @param queue table
-- @param guard function|nil a guard of your own: guard(action) -> boolean
-- @return number how many actions ran without error
function Combat.Drain(queue, guard)
    if type(queue) ~= "table" or type(queue.order) ~= "table" then return 0 end

    local order, actions = queue.order, queue.actions
    queue.order, queue.actions = {}, {}

    local done = 0
    for i = 1, #order do
        local action = actions[order[i]]
        if type(action) == "function" then
            local ok
            if type(guard) == "function" then
                ok = guard(action) and true or false
            else
                ok = pcall(action)
            end
            if ok then
                done = done + 1
                counters.drained = counters.drained + 1
            end
        end
    end
    return done
end

--- Whether combat is in progress.
-- Outside the game the function does not exist — then there is no combat and
-- nothing to defer.
-- @return boolean
function Combat.InCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, locked = pcall(InCombatLockdown)
    return ok and locked and true or false
end

--- Whether the engine protects this object.
-- @param object table|nil
-- @return boolean
function Combat.Protected(object)
    if type(object) ~= "table" then return false end
    if type(object.IsProtected) ~= "function" then return false end

    local ok, isProtected = pcall(object.IsProtected, object)
    return ok and isProtected and true or false
end

--- Names of the "editmode" group, if the compatibility layer is ready to
--- answer.
--
-- It answers only after it has learned the client's build, and before that it
-- refuses out loud — deliberately, so that nobody asks at file scope. For our
-- two questions that is not an error but "we do not know yet", and the answer
-- is then "there is no edit mode": until the layer is ready the addon touches
-- nothing anyway.
local function editModeNames()
    if type(ns.Compat) ~= "table" then return nil end

    local ok, names = pcall(ns.Compat.Resolve, "editmode")
    if not ok or type(names) ~= "table" then return nil end
    return names
end

--- Whether the interface's edit mode is open.
--
-- === Why this lives here, next to combat ===
--
-- The question is the same one: MAY FRAMES BE TOUCHED RIGHT NOW. Combat is one
-- answer of "no", edit mode is the second, and both belong together rather
-- than apart.
--
-- What it is. On clients that have it, the position of the action bars and
-- unit frames belongs to edit mode: it moves them, it saves them in its own
-- layout. An addon moving the same frames at the same minute performs work
-- "only available to the Blizzard UI" — and the engine refuses it:
--
--   Darken has been blocked from an action only available to the
--   Blizzard UI.
--
-- The refusal does not merely cancel our action: it taints the execution, and
-- further along edit mode's own work the frames it rebuilds end up tainted
-- too. The author put it plainly: the popup arrives when edit mode is opened
-- and when it is closed.
--
-- The frame's name comes from the compatibility layer and from nowhere else.
-- On clients without edit mode there is no name at all — the answer is then
-- "not open", and that is the truth rather than caution.
--
-- @return boolean
function Combat.EditModeOpen()
    local names = editModeNames()
    if not names then return false end

    for i = 1, #names do
        local frame = _G[names[i]]
        if type(frame) == "table" and type(frame.IsShown) == "function" then
            local ok, shown = pcall(frame.IsShown, frame)
            if ok and shown then return true end
        end
    end

    return false
end

--- Whether this client has an interface edit mode at all.
--
-- === How this differs from EditModeOpen ===
--
-- EditModeOpen asks "is it open right now", and that answer changes every
-- minute. This one asks "does the client have it at all", and that answer is
-- the same for the whole session.
--
-- The difference lies in what follows from the answer. While edit mode is
-- OPEN, nobody may touch the frames. But on a client where edit mode EXISTS,
-- the position and size of the action bars belong to it ALWAYS, not only while
-- its window is open: it moves them, it saves them, and the engine protects
-- them from everybody else.
--
-- This is visible not in the taint log but in the blocked-action handler:
--
--   [Blocked] Darken tried to call the protected function
--   'MultiBarRight:SetPointBase()'
--   'MultiBarLeft:SetScaleBase()'
--   'MainActionBar:SetShownBase()'
--
-- A blocked call does not merely fail to run — it taints the execution, and
-- the taint spreads further through the engine's work. So "try it and see"
-- will not do here: every attempt costs a taint.
--
-- The addon neither argues with this nor works around it: on such a client the
-- bar layout belongs to edit mode, and what is left to us is what it does not
-- touch — the buttons' appearance, opacity, fading and texts.
--
-- @return boolean
function Combat.EditModePresent()
    local names = editModeNames()
    return names ~= nil and #names > 0
end

--- A module's queue, created on demand.
-- @param name string the module's name
-- @return table|nil
function Combat.QueueFor(name)
    if type(name) ~= "string" or name == "" then return nil end

    local queue = Combat.queues[name]
    if queue == nil then
        queue = Combat.NewQueue()
        Combat.queues[name] = queue
    end
    return queue
end

--- How much of a module's work is waiting for combat to end.
-- @param name string
-- @return number
function Combat.PendingFor(name)
    if type(name) ~= "string" then return 0 end
    return Combat.Pending(Combat.queues[name])
end

--- Perform a module's protected operation.
--
-- Immediately, if there is no combat or the engine does not protect the
-- object. Otherwise the action goes into the module's queue under a key and
-- runs when combat ends.
--
-- Immediate execution runs as is, unwrapped: the module calls this from its
-- own ApplySettings or event handler, that is, already inside the registry's
-- protection, and a second wrapper would only hide the stack. Deferred
-- execution has no protection around it — nobody called us there — so it goes
-- through the registry and disables its module by name.
--
-- @param name string the module's name
-- @param object table|nil the object being worked on
-- @param key string the queue key
-- @param action function the action
-- @return boolean whether it ran immediately (false means deferred or refused)
-- @return string|nil the reason, if the work was not accepted at all
function Combat.Secure(name, object, key, action)
    if type(action) ~= "function" or type(key) ~= "string" or key == ""
        or type(name) ~= "string" or name == "" then
        return false, ns.Localize(
            "deferring work needs a non-empty key and a function")
    end

    -- A switched-off module defers nothing. The same door as event
    -- subscription (Core/Events.lua): the core stopped calling the module, and
    -- there must be no way back in from its own timer. The core removes a
    -- disabled module's queue when it disables it, and creating that queue
    -- again on the first deferred piece of work would undo the disabling.
    if type(ns.Registry) == "table" and ns.Registry:IsFailed(name) then
        return false, ns.Localize(
            "a module that Darken switched off cannot defer work")
    end

    if Combat.InCombat() and Combat.Protected(object) then
        Combat.Enqueue(Combat.QueueFor(name), key, action)
        return false
    end

    action()
    return true
end

--- Remove a module's queue entirely.
-- Called by the registry when it disables a module — alongside removing its
-- subscriptions and for the same reason: nothing of a switched-off module
-- should stay alive. Its deferred actions would not run anyway (DrainFor calls
-- them through Protect, which refuses a disabled module), but they would hold
-- references to frames and closures until combat next ended.
-- @param name string
-- @return number how many actions were discarded
function Combat.DropModule(name)
    if type(name) ~= "string" or name == "" then return 0 end

    local pending = Combat.PendingFor(name)
    Combat.queues[name] = nil
    return pending
end

--- Run one module's deferred work.
-- @param name string
-- @return number how many actions ran without error
function Combat.DrainFor(name)
    local queue = Combat.queues[name]
    if queue == nil then return 0 end

    return Combat.Drain(queue, function(action)
        return (ns.Registry:Protect(name, "deferred work", action))
    end)
end

--- Run the deferred work of every module.
-- Ordered by name: the order must be the same from run to run, or two queues
-- touching the same frame would give a different result each time.
-- @return number how many actions ran without error
function Combat.DrainAll()
    local names = {}
    for name in pairs(Combat.queues) do names[#names + 1] = name end
    table.sort(names)

    local done = 0
    for i = 1, #names do
        done = done + Combat.DrainFor(names[i])
    end
    return done
end

-- Leaving combat is the only moment deferred work can run. A core
-- subscription rather than a module's: there are as many queues as modules,
-- and one event.
ns.Events.Core("PLAYER_REGEN_ENABLED", function()
    Combat.DrainAll()
end)
