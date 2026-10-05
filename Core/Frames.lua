local ADDON, ns = ...

-- Showcase of the core's objects.
--
-- Why it exists. Some modules create no frames of their own but extend
-- others': the cast-bar ticks module draws marks onto the bar the core
-- styles. Without the showcase such a module would have to find the frame by
-- its global name and guess the moment the core finished repainting it — that
-- is, duplicate the compatibility layer and the settings-application order.
-- The core's next repaint would wipe its additions, and that would look like
-- flicker on every change of a setting.
--
-- Ownership is not transferred. The core hands over a reference and says "I
-- have just repainted this"; the object's appearance stays the core's, while
-- the module adds its own on top and restores it on notification. A module has
-- no right to forbid the core's repaint and never will: otherwise a core
-- setting would stop working for whoever installed the module, and the core's
-- author would have to untangle it.
--
-- A key is a string like "castbar.player": subsystem, dot, qualifier. The
-- keys are listed in docs/module-api.md and live by the rules of a public
-- contract: adding is allowed, renaming is not.
local Frames = {
    objects   = {},   -- key -> frame, the last one known
    listeners = {},   -- key -> { [module name] = function }
}
ns.Frames = Frames

--- Get a core object by its key.
-- A key that does not exist on this client (there is no focus in vanilla)
-- yields nil, and that is not an error: the compatibility layer only exposes
-- frames that exist.
-- @param key string
-- @return table|nil
function Frames.Get(key)
    if type(key) ~= "string" then return nil end
    return Frames.objects[key]
end

--- Subscribe to an object's repaint.
-- The handler is called with (frame, key). If the object is already known the
-- handler is called immediately: a module that subscribed after the core had
-- already repainted the bar would otherwise wait for the next change of
-- settings, and its additions would not appear at all until the player first
-- touched a slider.
--
-- One handler per key-and-module pair: subscribing again replaces the
-- previous handler rather than adding a second. A module subscribing from
-- ApplySettings (which is legitimate: ApplySettings runs on every profile
-- change) would otherwise accumulate handlers and draw one copy per change.
-- @param key string the object's key
-- @param moduleName string name of the subscribing module
-- @param fn function the handler
-- @return boolean whether the subscription was accepted
function Frames.Subscribe(key, moduleName, fn)
    if type(key) ~= "string" or key == "" then return false end
    if type(moduleName) ~= "string" or moduleName == "" then return false end
    if type(fn) ~= "function" then return false end

    local forKey = Frames.listeners[key]
    if not forKey then
        forKey = {}
        Frames.listeners[key] = forKey
    end
    forKey[moduleName] = fn

    local frame = Frames.objects[key]
    if frame ~= nil then
        ns.Registry:Protect(moduleName, "OnRepaint", fn, frame, key)
    end

    return true
end

--- Declare an object repainted.
-- Called by the core after it applied its settings to the object, and only
-- then: notifying before the repaint would mean the module restores its own
-- work and the core wipes it straight after.
-- Every handler goes through the registry's protection: a subscriber that
-- raises is disabled, while the other subscribers of the same key still get
-- their notification.
-- @param key string the object's key
-- @param frame table|nil the object itself; nil means it does not exist on
--     this client
function Frames.Repaint(key, frame)
    if type(key) ~= "string" or key == "" then return end

    if frame ~= nil then
        Frames.objects[key] = frame
    end

    local known = Frames.objects[key]
    if known == nil then return end

    local forKey = Frames.listeners[key]
    if not forKey then return end

    -- Iterate over a list of names rather than over the table directly: a
    -- handler may raise, and then Disable edits the registry's state during
    -- the iteration. The subscriber list itself does not change, but relying
    -- on that inside a pairs loop is not worth it — the rule is cheaper than
    -- the exception.
    local names = {}
    for moduleName in pairs(forKey) do
        names[#names + 1] = moduleName
    end
    table.sort(names)

    for i = 1, #names do
        local moduleName = names[i]
        local fn = forKey[moduleName]
        if type(fn) == "function" then
            ns.Registry:Protect(moduleName, "OnRepaint", fn, known, key)
        end
    end
end
