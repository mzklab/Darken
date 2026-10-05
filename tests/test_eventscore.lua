local helpers = require("helpers")

-- The core's own subscription: one handler per "event + function" pair.
--
-- What the file is written for. Events.Subscribe names its deduplication rule
-- outright — "a repeated subscription replaces the former handler rather than
-- adding a second" — and holds to it, because a module may subscribe from
-- ApplySettings, and that is called at every change of profile. Events.Core
-- had no such rule: the list grew by appending, and there was nothing to take
-- a handler off it with — Events.DropModule walks only Events.listeners, and
-- the core has no name under which it could be switched off.
--
--
-- Today that cost nothing: the only caller (Core/Combat.lua) stands at file
-- read level and runs once. It becomes a defect on the day a second caller
-- turns out to be inside OnEnable: Registry:Retry calls OnEnable afresh, and
-- the core's handler would double silently — and the core's door is open
-- precisely for such moves (AceEvent kept one handler per pair and lost the
-- rest silently; the replacement keeps them all).
--
-- So the rule here is the same as Subscribe's, and it is checked before the
-- second caller appears.

T.suite("the core's events: one handler per pair")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Events.lua", ns)

local Events = ns.Events

do
    local ran = 0
    local function handler() ran = ran + 1 end

    T.eq(Events.Core("PLAYER_REGEN_DISABLED", handler), true,
        "the first subscription was accepted")
    T.eq(Events.Core("PLAYER_REGEN_DISABLED", handler), true,
        "the repeated one answers \"accepted\" too")

    Events.Dispatch("PLAYER_REGEN_DISABLED")
    T.eq(ran, 1, "but the work was done once rather than twice")
end

do
    -- Two different handlers of one event are a legitimate pair: the core has
    -- many subsystems, and forbidding a second would be a ban on growth.
    local first, second = 0, 0

    Events.Core("PLAYER_LOGIN", function() first = first + 1 end)
    Events.Core("PLAYER_LOGIN", function() second = second + 1 end)

    Events.Dispatch("PLAYER_LOGIN")
    T.eq(first, 1, "the first handler ran")
    T.eq(second, 1, "and so did the second")
end

do
    -- Rubbish on the input does not bring the load down and creates no subscriptions.
    T.eq(Events.Core("", function() end), false, "an empty event name was rejected")
    T.eq(Events.Core("PLAYER_DEAD", nil), false, "a non-function was rejected")
    T.eq(Events.Dispatch("PLAYER_DEAD"), 0, "and nothing got subscribed")
end
