local helpers = require("helpers")

-- The button on the minimap: the third door into the settings window.
--
-- What is checked is what can be checked without a client: the place by the
-- angle and the angle by the cursor. Both are pure functions, and both stand
-- apart from the drag handler precisely so that they can be asked here.

T.suite("the minimap button: the place by the angle")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Modules/Launcher.lua", ns)

local Launcher = ns.Launcher
T.ok(Launcher ~= nil, "the subsystem was read")

local function close(a, b)
    return math.abs(a - b) < 0.001
end

do
    -- Zero degrees is to the right of the centre, ninety is up: the same
    -- coordinate system the game itself computes in.
    local x, y = Launcher.Place(0, 80)
    T.ok(close(x, 80), "zero degrees means right by the radius")
    T.ok(close(y, 0), "and with no vertical offset")

    x, y = Launcher.Place(90, 80)
    T.ok(close(x, 0), "ninety means no horizontal offset")
    T.ok(close(y, 80), "and up by the radius")

    -- The radius is observed at any angle: the button walks a circle rather
    -- than a square.
    for _, angle in ipairs({ 13, 47, 160, 225, 300 }) do
        x, y = Launcher.Place(angle, 80)
        T.ok(close(math.sqrt(x * x + y * y), 80),
            "the radius is the same at the angle " .. angle)
    end

    -- Rubbish on the input counts as the default: the angle arrives from the
    -- saved file, and anything at all can get in there over the years.
    local dx, dy = Launcher.Place(nil, nil)
    T.ok(close(math.sqrt(dx * dx + dy * dy), 80),
        "with no angle the button is on the circle all the same")
end

T.suite("the minimap button: the angle by the cursor")

do
    -- The cursor to the right of the centre is zero degrees, above it ninety.
    T.ok(close(Launcher.AngleOf(0, 0, 10, 0), 0), "to the right, zero")
    T.ok(close(Launcher.AngleOf(0, 0, 0, 10), 90), "above, ninety")
    T.ok(close(Launcher.AngleOf(0, 0, -10, 0), 180), "to the left, a hundred and eighty")

    -- An angle that went negative is brought round the circle: saved as a
    -- negative it would put the button back in the same place, but it could not be read in the file.
    T.ok(close(Launcher.AngleOf(0, 0, 0, -10), 270), "below, two hundred and seventy")

    -- The centre is in the middle of the screen rather than at zero: it is the
    -- difference that is computed rather than the numbers themselves.
    T.ok(close(Launcher.AngleOf(500, 400, 510, 400), 0),
        "to the right of the minimap's centre is the same zero")
end

T.suite("the minimap button: a fresh install shows it")

do
    -- A door the player does not know about is not a door.
    T.eq(Launcher.globals.shown, true, "the button is shown")
    T.eq(type(Launcher.globals.angle), "number", "and it has an angle")

    -- With no database the question "is it shown" does not fall over and answers "yes".
    T.eq(Launcher.Shown(), true, "with no database the button counts as shown")

    -- The section is in place, and it is read without the database.
    local args = Launcher.options and Launcher.options.args or {}
    T.eq(type(args.shown), "table", "the setting is in place")
    T.eq(args.shown.get(), true, "and is read without the database")
end

T.suite("the addon's button: the radius is computed from the map itself")

-- The minimap comes in any size: it is changed both by the player in the
-- game's settings and by other addons. With a constant radius the button of a
-- large map ended up INSIDE it, over the terrain — the author sent in such a screenshot.
do
    local Launcher = ns.Launcher

    -- The edge of a map 200 wide is a hundred from the centre, and the button
    -- sits on it rather than on the terrain.
    local x, y = Launcher.Place(0, 200 / 2 + 10)
    T.ok(math.abs(x - 110) < 1e-9, "the button did not sit on a large map's edge")
    T.ok(math.abs(y) < 1e-9, "and did not drift in height")

    -- A map half the size means the button comes exactly that much closer.
    local nx = select(1, Launcher.Place(0, 100 / 2 + 10))
    T.ok(math.abs(nx - 60) < 1e-9, "on a small map the button stayed far away")
end

T.suite("the addon's button: the icon stands on a background of its own")

-- The icon is drawn transparent: on a dark map it reads as a hole in the ring
-- and on light terrain it vanishes altogether. So beneath it lies our own
-- dark tone, the same one the addon paints the background of its windows with.
do
    local keys = require("localekeys")
    local source = keys.read("Modules/Launcher.lua")

    T.ok(source:find("frame.backdrop", 1, true) ~= nil,
        "there is no backing beneath the icon at all")
    T.ok(source:find('ns.Skin.Get("ink")', 1, true) ~= nil,
        "the backing is painted in a tone other than ours")
    T.ok(source:find("ROUND_MASK", 1, true) ~= nil,
        "the backing is not trimmed into a circle")
end

T.suite("the addon's button: a toggle and a response to hovering")

-- Two complaints of the author about one thing: there was no hover and no closing.
--
-- The button is a toggle and is obliged to behave like one: a press with the
-- window open closes it. A second press used to call the opening once more,
-- that is, did nothing, and the window could be closed only by the cross.
--
-- There was no response to hovering at all: the button showed a tooltip and
-- answered with nothing else. A tooltip appears half a second later and to
-- one side of the button — not one button of the interface behaves that way.
do
    local keys = require("localekeys")
    local source = keys.read("Modules/Launcher.lua")

    T.ok(source:find("addon:ToggleConfig()", 1, true) ~= nil,
        "the press does not toggle the window but only opens it")
    T.ok(source:find("Launcher.Recolour()", 1, true) ~= nil,
        "the mouse leaving does not restore the icon's resting look")
    T.ok(source:find("self.icon.SetVertexColor", 1, true) ~= nil,
        "hovering does not change the icon's look")

    -- The resting state is obliged to be darker than white, or there is
    -- nowhere to brighten to and no difference to see: the icon's picture is drawn light.
    local rest = tonumber(source:match("\nlocal REST = ([%d%.]+)"))
    T.ok(rest ~= nil, "the resting brightness is not declared as a number")
    T.ok(rest ~= nil and rest > 0.5 and rest < 1,
        "the resting brightness is outside the range that leaves room to brighten: " .. tostring(rest))

    -- And the core is obliged to be able to close rather than only to open.
    local core = keys.read("Core/Init.lua")
    T.ok(core:find("function Addon:ToggleConfig()", 1, true) ~= nil,
        "the core cannot close the settings window")
    T.ok(core:find("function Addon:ConfigOpen()", 1, true) ~= nil,
        "the core cannot ask whether the window is open")

    -- Whether it is open is asked of the window's OWNER rather than kept in a
    -- field of our own: a window closed by the cross our accounting would
    -- count as open, and the button would stop opening it at all.
    --
    -- The owner changed: the window used to be built by somebody else's
    -- library and it was asked; now the window is our own and it is asked. The
    -- argument is the same — there must be no second accounting of one and the same thing.
    T.ok(core:find("ns.Window.IsShown()", 1, true) ~= nil,
        "whether the window is open is asked of the window itself")
    T.ok(core:find("AceDialog", 1, true) == nil,
        "and no traces of the former library are left in the core")
end
