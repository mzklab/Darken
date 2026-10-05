local helpers = require("helpers")

-- The engine's refusal to register an event.
--
-- WHAT THE FILE IS FOR. A subscription to an event goes through a pcall: the
-- engine throws an exception on an unfamiliar name, and the core has no right to fall over because of somebody else's typo.
-- The price of that guard was the same as the name existence filter's: a
-- mistake becomes safe and invisible at a stroke. The refusal was recorded
-- nowhere — neither in the counters nor in the report — and a subsystem whose
-- event the engine did not accept looked exactly like a subsystem whose event
-- was accepted and never once sent.
--
-- The analysis of the nameplates' zero count stalled on that: "the game
-- showed not one nameplate" and "the game rejected our subscription to
-- NAME_PLATE_UNIT_ADDED" were indistinguishable by anything, and a third run
-- in the client would have given no answer any more than the second did.
--
-- Exactly one property is checked here: the refusal is **visible**. Not that
-- it happens (that is the engine's business) but that a refusal that happened
-- reaches the report by name.

T.suite("the events: the engine's refusal is recorded by name")

--- A fake client: a receiver whose RegisterEvent refuses by a list.
--
-- It is an exception that is faked rather than a return of false: that is
-- exactly how the engine answers with a refusal, and exactly a pcall that catches it.
--
-- @param refuse table event name -> true
-- @return function restore the globals as they were
local function fakeClient(refuse)
    local previous = _G.CreateFrame

    _G.CreateFrame = function()
        return {
            SetScript = function() end,
            RegisterEvent = function(_, event)
                if refuse[event] then
                    error("unknown event: " .. tostring(event), 0)
                end
            end,
            UnregisterEvent = function() end,
        }
    end

    return function() _G.CreateFrame = previous end
end

do
    local restore = fakeClient({ NAME_PLATE_UNIT_ADDED = true })

    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Events.lua", ns)
    local Events = ns.Events

    T.eq(Events.Subscribe("PLAYER_REGEN_DISABLED", "alpha", function() end),
        true, "an accepted subscription is accepted")
    T.eq(Events.Subscribe("NAME_PLATE_UNIT_ADDED", "alpha", function() end),
        true, "a subscription the engine rejected is recorded for the module all the same")

    -- The subscription is recorded and there will be no event: that is
    -- precisely what has to be tellable rather than hidden behind a refusal
    -- in Subscribe. The module has nothing to do with it, and there is nothing to switch it off for.
    T.eq(Events.asked["PLAYER_REGEN_DISABLED"], true, "the accepted one is marked")
    T.eq(Events.asked["NAME_PLATE_UNIT_ADDED"], nil,
        "while the rejected one stays unaccepted")

    local refused = Events.Refused()
    T.eq(#refused, 1, "there is exactly one refusal")
    T.eq(refused[1].event, "NAME_PLATE_UNIT_ADDED", "and it is named")
    T.eq(refused[1].tries, 1, "with a number of attempts")
    T.eq(Events.Accepted(), 1, "the accepted ones are counted separately")

    -- A second module tries the same event again: the engine refuses again,
    -- and that is the same trouble rather than a second one. The list stays by
    -- name; only the count of attempts grows.
    Events.Subscribe("NAME_PLATE_UNIT_ADDED", "beta", function() end)
    refused = Events.Refused()
    T.eq(#refused, 1, "there is still one refusal")
    T.eq(refused[1].tries, 2, "while the attempts became two")

    restore()
end

do
    -- The list's order is stable: it is read by eye and two runs are compared.
    local restore = fakeClient({ ZED_EVENT = true, ALPHA_EVENT = true })

    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Events.lua", ns)
    local Events = ns.Events

    Events.Subscribe("ZED_EVENT", "one", function() end)
    Events.Subscribe("ALPHA_EVENT", "one", function() end)

    local refused = Events.Refused()
    T.eq(#refused, 2, "both refusals are recorded")
    T.eq(refused[1].event, "ALPHA_EVENT", "the list is alphabetical: the first")
    T.eq(refused[2].event, "ZED_EVENT", "the list is alphabetical: the second")

    restore()
end

do
    -- What was accepted on the second attempt stops being a refusal. The
    -- report speaks of what there is now rather than of what there was in the middle of the login.
    local refuse = { LATE_EVENT = true }
    local restore = fakeClient(refuse)

    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Events.lua", ns)
    local Events = ns.Events

    Events.Subscribe("LATE_EVENT", "one", function() end)
    T.eq(#Events.Refused(), 1, "a refusal first")

    refuse.LATE_EVENT = nil
    Events.Subscribe("LATE_EVENT", "two", function() end)
    T.eq(#Events.Refused(), 0, "it was accepted, so there is no refusal any more")
    T.eq(Events.asked["LATE_EVENT"], true, "and the event is marked as accepted")

    restore()
end

do
    -- Outside the game there is no receiver at all, and that is not the
    -- engine's refusal: a record of "it did not work" would stand in every run of the checks, meaning nothing.
    local previous = _G.CreateFrame
    _G.CreateFrame = nil

    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Events.lua", ns)
    local Events = ns.Events

    Events.Subscribe("ANY_EVENT", "one", function() end)
    T.eq(#Events.Refused(), 0, "the client's absence does not count as a refusal")

    _G.CreateFrame = previous
end

T.suite("the tally: the engine's refusal reaches the report")

do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Tally.lua", ns)
    local Tally = ns.Tally

    -- A stand-in events subsystem: the analysis needs only two doors, and a
    -- separate fake client for their sake is not needed here.
    local events = {
        Accepted = function() return 7 end,
        Refused  = function()
            return { { event = "NAME_PLATE_UNIT_ADDED", tries = 3 } }
        end,
    }

    local parsed = Tally.Events(events)
    T.eq(parsed.accepted, 7, "the accepted ones are counted")
    T.eq(parsed.refusedCount, 1, "the refusals are counted")
    T.eq(parsed.refused[1].event, "NAME_PLATE_UNIT_ADDED", "and named")

    local built = Tally.Build({ plates = 0 }, nil, events)
    T.eq(built.events.refusedCount, 1, "the analysis puts the refusals into the report")

    local lines = Tally.Lines(built)
    local all = table.concat(lines, "\n")
    T.ok(all:find("NAME_PLATE_UNIT_ADDED", 1, true) ~= nil,
        "the refusal is named in the chat: " .. all)

    -- The order of the explanation: the registration's refusal stands before
    -- the "we did nothing" line, because it names its cause. The first lines are what gets read.
    T.ok(lines[1]:find("NAME_PLATE_UNIT_ADDED", 1, true) ~= nil,
        "and it stands as the first line: " .. lines[1])
    T.ok(all:find("Nameplates Attached", 1, true) ~= nil,
        "while the zero counter is named next")
end

do
    -- There were no refusals, so there is no line. "Zero refusals" is not
    -- news but a line read instead of an answer.
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Tally.lua", ns)
    local Tally = ns.Tally

    local quiet = {
        Accepted = function() return 4 end,
        Refused  = function() return {} end,
    }

    local lines = Tally.Lines(Tally.Build({ plates = 1 }, nil, quiet))
    local all = table.concat(lines, "\n")
    T.ok(all:find("refused to register", 1, true) == nil,
        "silence about what did not happen: " .. all)

    -- The events subsystem may be absent entirely (not every check reads it,
    -- and in a build the read order is its own). The analysis is obliged to survive that.
    local noEvents = Tally.Events(nil)
    T.eq(noEvents.refusedCount, 0, "with no events subsystem the refusals are zero")
    T.eq(#Tally.Build({}).events.refused, 0, "and the analysis is assembled all the same")
end

T.suite("the events: a refusal reaches the whole report about the client")

do
    -- The end-to-end path: the real Core/Events.lua under a stand-in client,
    -- the real Core/Report.lua, and the refusal is obliged to end up in the
    -- report's record. The intermediate doors are checked above; what is
    -- checked here is that they are connected.
    local restore = fakeClient({ NAME_PLATE_UNIT_ADDED = true })

    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Tally.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Report.lua", ns)

    ns.Events.Subscribe("NAME_PLATE_UNIT_ADDED", "nameplates", function() end)

    local report = ns.Report.Build("vanilla", {}, {}, nil, {}, nil, ns.Events)
    T.eq(report.tally.events.refusedCount, 1,
        "the engine's refusal lies in the report's record")
    T.eq(report.tally.events.refused[1].event, "NAME_PLATE_UNIT_ADDED",
        "and lies there by name")

    restore()
end
