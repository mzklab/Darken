local wholecost = require("wholecost")

-- The whole addon's cost rather than subsystem by subsystem.
--
-- Every subsystem is measured on its own, and several have a ceiling of their
-- own. All those numbers were taken in solitude. In the client the subsystems
-- work in one frame, in one thread, while the game draws, and the question the
-- author will ask — why the frame rate dropped — had no answer in a single set
-- until now.
--
-- Here it has one. The addon is brought up whole by the cold boot, configured
-- with the profile of a player in a fight (everything on), given a client with
-- real data — thirty nameplates, a party with auras, a cast under way — and
-- then four moments are measured: a frame at the height of a fight, entering
-- the world, a change of setting, and a frame of a fight with the bags open.
--
-- The ceilings here are by the shape of the work rather than by today's milliseconds:
--
--   * in a frame of a fight the interface's tree is not walked once;
--   * in a frame of a fight exactly those subsystems wake up that have
--     something to do in a fight — and no others;
--   * an event about one unit asks the game about one unit rather than about
--     everybody on the screen;
--   * the events' door creates no tables;
--   * the reconnaissance of the interface happens once per application,
--     however many subsystems are applied.
--
-- An edit that breaks any of those shapes fails the set rather than reaching
-- the player.
--
-- THE HONEST BOUNDARY. This is not the game: no drawing, no real frame, no C
-- side of the game's functions. The absolute numbers read as an order of
-- magnitude and as a subsystem's share rather than as milliseconds at the
-- player's end. What only the client can say is listed in the measurement's own report.

--============================================================================
-- The scene: one for the whole file
--============================================================================

-- One and only one: bringing the whole addon up costs about a hundredth of a
-- second, and four scenes for four moments would stretch the set out without a
-- single new assertion.
local bootStarted = os.clock()
local scene = wholecost.scene({})
local bootCost = os.clock() - bootStarted

T.suite("the whole cost: the scene came up")

T.eq(scene.boot.coreLoaded, true, "the core was read: "
    .. tostring(scene.boot.coreError))
T.eq(#scene.boot.errors, 0, "not one error while the fight scene came up")

do
    local live = 0
    for _, name in scene.ns.Registry:Each() do
        if not scene.ns.Registry:IsFailed(name) then live = live + 1 end
    end
    -- The core's "nameplates" subsystem yields to the nameplate engine out of
    -- the module — that is declared behaviour rather than a failure.
    T.ok(live >= 11, "subsystems in service: " .. live)
end

do
    -- There is one door. AceEvent keeps one handler per "event + object" pair,
    -- and the object is one and the same for every subsystem of the core
    -- (ns.Addon): two subsystems that asked for one event overwrote each other
    -- silently, and two thirds of the core's subscriptions were lost that way.
    -- An empty AceEvent registry after a full bring-up is a limit by shape: there is nowhere to collide, because there is no second door.
    local ace = LibStub("AceEvent-3.0")
    local left = 0
    for _ in pairs(ace.events.events) do left = left + 1 end
    T.eq(left, 0,
        "after a full bring-up not one subscription is left in AceEvent: "
        .. left)
end

T.ok(scene.ns.Darkness.PlanSize() == wholecost.treeTextures,
    string.format("the darkness found the whole stand-in interface: %d out of %d",
        scene.ns.Darkness.PlanSize(), wholecost.treeTextures))

--============================================================================
-- Entering the world
--============================================================================

T.suite("the whole cost: entering the world")

do
    -- The counters were not cleared since the scene's very beginning: they
    -- hold the whole bring-up, the entry into the world and thirty attachments of nameplates.
    local children = wholecost.counters.children

    -- The reconnaissance of the interface belongs to one subsystem and happens
    -- once per moment when the interface could have changed rather than once
    -- per subsystem. There are two such moments per startup: the first
    -- application of the settings and the entry into the world. A limit by
    -- shape: there are eighteen subsystems in the addon, and each could ask for a walk of its own if it wished — then there would be eighteen here.
    local WALK = wholecost.treeFrames + 1
    T.eq(children, WALK * 2,
        string.format("the whole startup reconnoitred the interface twice rather than once "
            .. "per subsystem: %d approaches with %d frames",
            children, wholecost.treeFrames))

    wholecost.reset()
    local enter = wholecost.cost(function()
        wholecost.enterWorld(scene)
    end, 50)

    -- Entering the world is the one moment outside a fight when a walk is
    -- legitimate: the game's windows were created afresh, and the former plan
    -- points at objects of the previous world. One walk rather than one per subsystem.
    T.eq(wholecost.counters.children % WALK, 0,
        "entering the world reconnoitres the interface in whole walks: "
        .. wholecost.counters.children)
    T.eq(wholecost.counters.children / WALK, 51,
        string.format("exactly one walk per entry into the world: %d walks per 51 entries",
            wholecost.counters.children / WALK))

    -- The whole bring-up is the reading of files off the disk, the raising of
    -- the libraries, eight modules and the first application of the settings.
    -- It happens once per entry into the game, and beside it the event of entering the world costs nothing.
    io.write(string.format(
        "  [whole cost] bringing the whole addon up (files, libraries, nine "
        .. "modules, the first application): %.0f ms%s", bootCost * 1000,
        string.char(10)))
    io.write(string.format(
        "  [whole cost] entering the world (a change of zone: the event to every subsystem, "
        .. "the reconnaissance of the interface, thirty nameplates afresh): %.3f ms%s",
        enter * 1000, string.char(10)))

    -- Entering the world arrives outside a fight and not every frame, but the
    -- player must not hang on it: the zone changes in mid-flight.
    T.ok(enter * 1000 < 20,
        string.format("entering the world fits into a frame of the loading screen: "
            .. "%.3f ms", enter * 1000))
end

--============================================================================
-- The height of a fight
--============================================================================

T.suite("the whole cost: the height of a fight")

do
    wholecost.reset()
    wholecost.busyFrame(scene)

    -- The file's most important assertion. The darkness is the only subsystem
    -- that can walk the interface, and it once hung the game already. Nothing
    -- must wake it in a fight.
    --
    T.eq(wholecost.counters.children, 0,
        "a frame of a fight does not walk the interface's tree once")
    T.eq(wholecost.counters.regions, 0, "nor does it re-read the regions")
    T.eq(wholecost.counters.writes, 0, "nor does it repaint the interface")
end

do
    -- Who wakes up. A limit by composition rather than by time: a subsystem
    -- that has nothing to do in a fight is obliged not to wake up in a fight,
    -- and an edit that subscribed the bags to UNIT_AURA will fail here rather than at the player's end.
    local woke, undo = wholecost.watch(scene)
    wholecost.busyFrame(scene)
    undo()

    local names = {}
    for name in pairs(woke) do names[#names + 1] = name end
    table.sort(names)

    T.eq(table.concat(names, ","), "umbraauras,umbraplates",
        "in a fight exactly two subsystems wake up: " ..
        table.concat(names, ","))
end

do
    -- An event about one unit asks the game about one unit. A limit by shape
    -- against the most expensive of the possible defects: a walk of all thirty
    -- nameplates at every event about any of them.
    local asked = 0
    local real = _G.UnitHealth
    _G.UnitHealth = function(...) asked = asked + 1 return real(...) end
    scene.dispatch("UNIT_HEALTH", scene.units.plates[1])
    _G.UnitHealth = real

    T.ok(asked <= 2, string.format(
        "one unit's health is asked of the game once with %d "
        .. "nameplates on the screen: %d", #scene.units.plates, asked))
end

do
    -- The events' door. After the edit of Core/Events.lua it creates no
    -- tables: the subscribers' names are taken at the subscription. The limit
    -- guards exactly that — at the height of a fight the door is opened a hundred times a frame.
    local dispatch = scene.dispatch
    local unit = scene.units.plates[1]
    dispatch("UNIT_HEALTH", unit)

    collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 2000 do dispatch("UNIT_HEALTH", unit) end
    local perEvent = (collectgarbage("count") - before) / 2000 * 1024

    T.ok(perEvent < 16, string.format(
        "the events' door creates no tables: %.1f bytes per event", perEvent))
end

do
    local frame = wholecost.cost(function() wholecost.busyFrame(scene) end, 400)

    collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 100 do wholecost.busyFrame(scene) end
    local perFrameKb = (collectgarbage("count") - before) / 100

    -- The shares. They are measured on a second run and apart from the total
    -- number: a wrapper around a handler costs two approaches to the clock, and
    -- in a frame with a hundred calls that charge is a noticeable share of the measured quantity itself.
    local tally, calls, undo = wholecost.instrument(scene)
    local ROUNDS = 200
    for _ = 1, ROUNDS do wholecost.busyFrame(scene) end
    undo()

    local shares, total = wholecost.shares(tally)
    local NL = string.char(10)
    io.write(string.format(
        "  [whole cost] a frame at the height of a fight: %.3f ms, %.1f KB of garbage, "
        .. "%d nameplates%s", frame * 1000, perFrameKb,
        #scene.units.plates, NL))
    for i = 1, #shares do
        if shares[i].seconds > 0 then
            io.write(string.format(
                "    %-14s %5.1f%%  %.4f ms  handler calls %d%s",
                shares[i].name, shares[i].seconds / total * 100,
                shares[i].seconds / ROUNDS * 1000,
                calls[shares[i].name] / ROUNDS, NL))
        end
    end

    -- A frame at sixty frames a second is 16.7 ms. In the worst frame of a
    -- fight the addon is obliged to fit into a small share of it: the rest belongs to the game.
    T.ok(frame * 1000 < 2, string.format(
        "the worst frame of a fight fits into an eighth of the game's frame: %.3f ms",
        frame * 1000))
    T.ok(perFrameKb < 12, string.format(
        "a frame of a fight barely litters: %.1f KB", perFrameKb))
end

--============================================================================
-- A change of setting
--============================================================================

T.suite("the whole cost: a change of setting")

do
    wholecost.reset()
    wholecost.settingsChange(scene)

    -- The repainting spreads across all eighteen subsystems while the interface
    -- is walked once in the process. A limit by shape: the reconnaissance
    -- belongs to the darkness and only it, and adding a subsystem has no right
    -- to add a second walk.
    T.eq(wholecost.counters.children, wholecost.treeFrames + 1,
        string.format("one application means one walk of the tree: %d approaches",
            wholecost.counters.children))

    local apply = wholecost.cost(function()
        wholecost.settingsChange(scene)
    end, 50)

    -- Who costs what in a repainting: the registry can apply one subsystem at
    -- a time, and that is the very cut the author needs.
    local NL = string.char(10)
    local rows, sum = {}, 0
    for module, name in scene.ns.Registry:Each() do
        local one = wholecost.cost(function()
            scene.ns.Registry:ApplyOne(module)
        end, 50)
        sum = sum + one
        rows[#rows + 1] = { name = name, seconds = one }
    end
    table.sort(rows, function(a, b) return a.seconds > b.seconds end)

    io.write(string.format(
        "  [whole cost] a change of setting: %.3f ms for the whole tree%s",
        apply * 1000, NL))
    for i = 1, #rows do
        if rows[i].seconds * 1000 >= 0.02 then
            io.write(string.format("    %-14s %5.1f%%  %.4f ms%s",
                rows[i].name, rows[i].seconds / sum * 100,
                rows[i].seconds * 1000, NL))
        end
    end

    T.ok(apply * 1000 < 12, string.format(
        "a change of setting fits into the game's frame: %.3f ms", apply * 1000))
end

do
    -- A division of a slider that has nothing to do with the darkness. There
    -- cannot be a single walk of the tree here: the subsystem applies its own.
    local plates = scene.ns.Registry:Get("umbraplates")
    wholecost.reset()
    local step = wholecost.cost(function()
        scene.ns.Registry:ApplyOne(plates)
    end, 50)

    T.eq(wholecost.counters.children, 0,
        "a division of the nameplates' slider does not walk the interface")
    T.eq(wholecost.counters.writes, 0, "nor does it repaint it")

    io.write(string.format(
        "  [whole cost] a division of the nameplates' slider: %.3f ms%s",
        step * 1000, string.char(10)))
end

do
    -- A division of the darkening slider — in the live addon rather than in
    -- solitude. The check tests/test_darkcost.lua measures the same shape on
    -- the subsystem separately; what matters here is that the neighbours did not spoil it.
    local dark = scene.ns.Darkness
    wholecost.reset()
    for _ = 1, 40 do dark.Schedule() end
    scene.runTimers()

    T.eq(wholecost.counters.children, 0,
        "forty divisions of the darkening slider do not walk the tree")
    T.eq(wholecost.counters.writes, wholecost.treeTextures,
        string.format("and merge into one application: %d writes with a plan "
            .. "of %d textures", wholecost.counters.writes,
            wholecost.treeTextures))
end