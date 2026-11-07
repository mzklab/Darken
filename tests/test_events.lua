local helpers = require("helpers")


T.suite("events: the door times every subsystem that passes through it")

-- The author spent an evening being told that the darkening costs nothing
-- while his game stuttered, and he was right to refuse the answer: an
-- accounting that measures one subsystem out of nine answers the wrong
-- question. Every subsystem's answer to an event passes through this one
-- door, so this is the only place that can say which of them spends
-- anything without a timer in each.
do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)

    local clock = 1000
    local savedClock = _G.debugprofilestop
    _G.debugprofilestop = function() return clock end

    ns.Registry:Register({
        name = "slow",
        OnEnable = function() end,
    })
    ns.Registry:Register({
        name = "quick",
        OnEnable = function() end,
    })

    ns.Events.Subscribe("TEST_EVENT", "slow", function() clock = clock + 5 end)
    ns.Events.Subscribe("TEST_EVENT", "quick", function() clock = clock + 1 end)

    ns.Events.Dispatch("TEST_EVENT")

    local spent = ns.Events.Spent()
    T.eq(spent.slow, 5, "the subsystem that took five milliseconds is named")
    T.eq(spent.quick, 1, "and so is the one that took one")

    -- The tally is of the second now running: a second later it starts over,
    -- because the question is always "what is it costing me now".
    clock = clock + 2000
    T.eq(next(ns.Events.Spent()), nil, "a second later the tally is fresh")

    _G.debugprofilestop = savedClock
end
