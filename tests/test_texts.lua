local helpers = require("helpers")

-- Bar texts: the value format and its boundaries.
--
-- What this file is for. Formatting the "current and maximum" pair is almost
-- the whole value of the subsystem, and nearly everything in it breaks at
-- the edges rather than in the middle: a maximum equal to zero happens all
-- the time (a unit out of sight, a class with no resource), and dividing by
-- it would break a bar update in combat. Abbreviation thresholds break not
-- where they were written but one unit away: 999 and 1000, 999,999 and
-- 1,000,000. All of that is checked here and in no client at all.

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Events.lua", ns)
helpers.loadAddonFile("Core/Combat.lua", ns)
-- The font subsystem is loaded not for the fonts: it holds the parser for
-- paths like "healthbar.TextString", which this subsystem uses to reach the
-- same objects. There must be no second path parser in the addon.
local savedLibStub = LibStub
LibStub = function() return nil end
helpers.loadAddonFile("Modules/Fonts.lua", ns)
-- The unit frame subsystem is loaded for the deferral queue: the rule "a
-- repeated write displaces the former one" is written and checked there.
helpers.loadAddonFile("Modules/UnitFrames.lua", ns)
-- The bar labels take their number formatting from the core:
-- Core/Format.lua must be in the namespace before Modules/Texts.lua, or the
-- subsystem does not load at all.
helpers.loadAddonFile("Core/Format.lua", ns)
helpers.loadAddonFile("Modules/Texts.lua", ns)
LibStub = savedLibStub

local TX = ns.Texts

T.suite("texts: abbreviating large numbers")

T.eq(TX.Abbreviate(0), "0", "zero is written as zero")
T.eq(TX.Abbreviate(1), "1", "one in full")
T.eq(TX.Abbreviate(999), "999", "below the thousand threshold, in full")
T.eq(TX.Abbreviate(1000), "1.0k", "exactly a thousand is already abbreviated")
T.eq(TX.Abbreviate(12400), "12.4k", "the example from the spec")
T.eq(TX.Abbreviate(999499), "999.5k", "below the million threshold, thousands")

-- The million threshold is corrected for rounding: 999,999 in thousands
-- would give "1000.0k" -- the same magnitude as "1.0m" but three times longer.
T.eq(TX.Abbreviate(999999), "1.0m", "almost a million is written as a million")
T.eq(TX.Abbreviate(1000000), "1.0m", "exactly a million")
T.eq(TX.Abbreviate(2500000), "2.5m", "two and a half million")

T.eq(TX.Abbreviate(-1500), "-1.5k", "the sign is not lost")
T.eq(TX.Abbreviate(nil), nil, "nothing to abbreviate gives nil, not zero")
T.eq(TX.Abbreviate("garbage"), nil, "garbage gives nil too")

T.suite("texts: percentages")

T.eq(TX.Percent(50, 100), 50, "a half")
T.eq(TX.Percent(0, 100), 0, "zero health is zero percent")
T.eq(TX.Percent(100, 100), 100, "full health is a hundred percent")
T.eq(TX.Percent(1, 3), 33, "a third rounds down")
T.eq(TX.Percent(2, 3), 67, "two thirds round up")

-- A maximum equal to zero happens all the time: a unit out of sight, a class
-- with no resource. A division by zero here would break a bar update in combat.
T.eq(TX.Percent(0, 0), 0, "a zero maximum does not divide by zero")
T.eq(TX.Percent(50, 0), 0, "nor with a non-zero current value")
T.eq(TX.Percent(nil, nil), 0, "garbage on the input gives zero percent")

T.suite("texts: the value format")

T.eq(TX.FormatValue(4500, 9000, "value", false), "4500/9000", "the number in full")
T.eq(TX.FormatValue(4500, 9000, "percent", false), "50%", "the percentage")
T.eq(TX.FormatValue(4500, 9000, "both", false), "4500/9000 50%",
    "the number and the percentage together")

T.eq(TX.FormatValue(12400, 20000, "value", true), "12.4k/20.0k",
    "the abbreviation applies to both numbers")
T.eq(TX.FormatValue(12400, 20000, "both", true), "12.4k/20.0k 62%",
    "the abbreviation does not affect the percentage")

-- The native format means "do not touch". An empty string would wipe the
-- native label and would look like a broken addon rather than a refusal to override.
T.eq(TX.FormatValue(4500, 9000, TX.NATIVE, false), nil,
    "the native format writes nothing")
T.eq(TX.FormatValue(4500, 9000, nil, false), nil, "garbage as the format gives nil too")

T.suite("texts: the boundaries of the format")

-- Zero, the maximum and the values on both sides of every abbreviation threshold.
T.eq(TX.FormatValue(0, 9000, "value", false), "0/9000", "a current value of zero")
T.eq(TX.FormatValue(0, 9000, "percent", false), "0%", "zero percent")
T.eq(TX.FormatValue(9000, 9000, "percent", false), "100%", "the full maximum")
T.eq(TX.FormatValue(9000, 9000, "both", true), "9.0k/9.0k 100%",
    "the full maximum with abbreviation")

T.eq(TX.FormatValue(999, 1000, "value", true), "999/1.0k",
    "on either side of the thousand threshold")
T.eq(TX.FormatValue(999499, 999999, "value", true), "999.5k/1.0m",
    "on either side of the million threshold")

-- A maximum equal to zero is the main boundary: it happens every time the
-- target goes out of sight, and no format may divide by it.
T.eq(TX.FormatValue(0, 0, "percent", false), "0%", "zero maximum: the percentage")
T.eq(TX.FormatValue(0, 0, "value", false), "0/0", "zero maximum: the number")
T.eq(TX.FormatValue(0, 0, "both", true), "0/0 0%", "zero maximum: both")

-- Garbage from SavedVariables and from foreign code counts as zero rather
-- than breaking a bar update.
T.eq(TX.FormatValue(nil, nil, "value", false), "0/0", "garbage counts as zero")
T.eq(TX.FormatValue("garbage", "garbage", "both", true), "0/0 0%",
    "and with abbreviation too")

do
    local args = TX.options.args
    T.eq(args.health.type, "select", "the health format is a select")
    T.eq(args.power.type, "select", "the resource format is a select")
    -- Two lists and nothing else. The shortening of numbers and the place
    -- of the text used to stand here; both belonged to a label this
    -- subsystem wrote itself, and the game writes its own.
    T.eq(args.abbreviate, nil, "there is no checkbox of our own invention")
    T.eq(args.position, nil, "and no place for a label we do not write")

    T.eq(args.health.sorting()[1], TX.NATIVE, "the native format comes first")

    local values = args.health.values()
    T.ok(values.value ~= nil and values.percent ~= nil and values.both ~= nil,
        "all three formats are in place")

    -- The defaults are the native look of the game.
    T.eq(TX.defaults.health, TX.NATIVE, "the health default is native")
    T.eq(TX.defaults.power, TX.NATIVE, "the resource default is native")

    -- And the description says what the choice really does, because what it
    -- does changed: it turns the game's own setting on rather than writing
    -- a label of ours, and the game applies one shape to every bar.
    T.ok(args.health.desc:find("game") ~= nil,
        "the description names whose setting is being turned on")
end

-- The handlers write into the profile, and what is applied is the game's
-- own setting.
do
    local wrote = {}
    local api = {
        Get = function(name) return wrote[name] or "0" end,
        Set = function(name, value) wrote[name] = value return true end,
        Default = function() return "0" end,
    }

    local settings = { health = TX.NATIVE, power = TX.NATIVE }
    ns.Addon = { db = { profile = { texts = settings } } }

    T.eq(select(1, TX.Wanted(settings)), nil,
        "with both at the game's own look nothing is wanted")

    settings.health = "percent"
    local show, shape = TX.Wanted(settings)
    T.eq(show, "1", "a format chosen asks the game to show the text")
    T.eq(shape, "PERCENT", "in the shape chosen")

    TX.ApplyGame(settings, api)
    T.eq(wrote.statusText, "1", "and the variable is written")
    T.eq(wrote.statusTextDisplay, "PERCENT", "with the shape beside it")

    -- Number and percent is the game's own BOTH: the percentage at the left
    -- end of the bar and the number at the right, which is the other half
    -- of what was asked for.
    settings.health = "both"
    TX.ApplyGame(settings, api)
    T.eq(wrote.statusTextDisplay, "BOTH",
        "number and percent is the game's own two-ended shape")

    -- Back to the game's own look: the variables go to what the client
    -- itself calls default, not to a value of ours.
    settings.health = TX.NATIVE
    TX.ApplyGame(settings, api)
    T.eq(wrote.statusText, "0", "going back restores the client's default")

    -- A client without the variables at all is an ordinary answer.
    T.eq(TX.ApplyGame(settings, { Get = nil, Set = nil }), 0,
        "and a client that cannot be asked is written to not at all")
end
