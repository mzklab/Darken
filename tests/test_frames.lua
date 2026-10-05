local helpers = require("helpers")

helpers.installValidator()

-- The shop window of the core's objects.
--
-- What it exists for: a module that adds to somebody else's object is
-- obliged to receive it and to learn of a repainting, or its additions are
-- erased by the very first edit of the core's settings. Ownership is not
-- handed over in the process — a module lays its own over the top while the object's look stays the core's.

local function core()
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Frames.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/Api.lua", ns)
    ns.Registry.report = function() end
    ns.Addon = { db = { profile = {} } }
    return ns
end

T.suite("An object is handed out by key")

do
    local ns = core()
    local bar = {}

    T.eq(ns.Frames.Get("castbar.player"), nil, "an unknown key gives nil")
    T.eq(ns.Frames.Get(nil), nil, "rubbish on the input does not bring it down")

    ns.Frames.Repaint("castbar.player", bar)
    T.eq(ns.Frames.Get("castbar.player"), bar, "the object is remembered")

    -- A key may be absent on this client: there is no focus in vanilla. That
    -- is not an error — the compatibility layer hands out only the frames that exist.
    T.eq(ns.Frames.Get("castbar.focus"), nil, "a missing object is a nil, not an error")
end

T.suite("The subscription to a repainting")

do
    local ns = core()
    local module = ns.Api:RegisterModule({ name = "decor", api = 1 })
    local bar = {}

    local seen = {}
    module:OnRepaint("castbar.player", function(frame, key)
        seen[#seen + 1] = tostring(key)
        T.eq(frame, bar, "the object itself arrived in the handler")
    end)

    T.eq(#seen, 0, "before the first repainting the handler stays silent")

    ns.Frames.Repaint("castbar.player", bar)
    T.eq(#seen, 1, "the repainting called the handler")
    T.eq(seen[1], "castbar.player", "the key was passed to the handler")

    ns.Frames.Repaint("castbar.player", bar)
    T.eq(#seen, 2, "and on the next repainting too")

    -- Somebody else's key passes by: otherwise a module of ticks on the
    -- player's bar would draw them on the target's bar as well.
    ns.Frames.Repaint("castbar.target", {})
    T.eq(#seen, 2, "a repainting of another object does not touch the subscriber")
end

T.suite("A subscription after the core has already repainted")

do
    -- The usual order for a third-party module: the core managed to draw
    -- everything before the game reached the dependent addon's files.
    -- Without an immediate call the module's additions would not appear
    -- until the player first touched a slider.
    local ns = core()
    local module = ns.Api:RegisterModule({ name = "late", api = 1 })
    local bar = {}
    ns.Frames.Repaint("castbar.player", bar)

    local calls = 0
    module:OnRepaint("castbar.player", function(frame)
        calls = calls + 1
        T.eq(frame, bar, "the object is the very one")
    end)

    T.eq(calls, 1, "the handler was called straight away at the subscription")
end

T.suite("A repeated subscription replaces the former one")

do
    -- ApplySettings is called at every change of profile, and a subscription
    -- from there is legitimate. Without the replacement the handlers would
    -- pile up, and the module would draw one copy of its additions per change of profile.
    local ns = core()
    local module = ns.Api:RegisterModule({ name = "decor", api = 1 })

    local first, second = 0, 0
    module:OnRepaint("castbar.player", function() first = first + 1 end)
    module:OnRepaint("castbar.player", function() second = second + 1 end)

    ns.Frames.Repaint("castbar.player", {})

    T.eq(first, 0, "the former handler is no longer called")
    T.eq(second, 1, "only the last one is called")
end

T.suite("Two modules on one object")

do
    local ns = core()
    local one = ns.Api:RegisterModule({ name = "one", api = 1 })
    local two = ns.Api:RegisterModule({ name = "two", api = 1 })

    local a, b = 0, 0
    one:OnRepaint("castbar.player", function() a = a + 1 end)
    two:OnRepaint("castbar.player", function() b = b + 1 end)

    ns.Frames.Repaint("castbar.player", {})

    T.eq(a, 1, "the first got the notification")
    T.eq(b, 1, "and so did the second")
end

T.suite("Rubbish on a subscription's input")

do
    local ns = core()
    local module = ns.Api:RegisterModule({ name = "decor", api = 1 })

    T.eq(module:OnRepaint(nil, function() end), false, "with no key there is no subscription")
    T.eq(module:OnRepaint("castbar.player", nil), false, "with no handler there is no subscription")
    T.eq(module:OnRepaint("castbar.player", function() end), true, "a correct subscription was accepted")

    -- A repainting of a key whose object nobody declared must neither call
    -- the handlers with a nil nor fall over.
    ns.Frames.Repaint("known.to.nobody")
    T.eq(ns.Frames.Get("known.to.nobody"), nil, "no object appeared out of nowhere")
end

T.suite("The core's object is available to a module directly")

do
    local ns = core()
    local module = ns.Api:RegisterModule({ name = "decor", api = 1 })
    local bar = {}

    T.eq(module:GetFrame("castbar.player"), nil, "before a repainting there is no object")
    ns.Frames.Repaint("castbar.player", bar)
    T.eq(module:GetFrame("castbar.player"), bar, "after a repainting the object is handed out")
end

helpers.removeValidator()
