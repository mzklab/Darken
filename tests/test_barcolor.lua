local helpers = require("helpers")

-- The colour of the health and power bars.
--
-- The rule of choosing a colour is a pure function, and it is checked here
-- entirely. In the client a mistake in it shows up "every other time": on a
-- player there is a class colour, a boar has no class, and a druid in cat
-- form has a different power from a minute ago. Catching that by eye costs more than writing a check.
--
-- The file's second subject is the folding of two multipliers. A bar's colour
-- and the darkening are both multipliers, and they fold into one
-- SetStatusBarColor call: a bar's colour has one owner — this subsystem.

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Events.lua", ns)
helpers.loadAddonFile("Core/Combat.lua", ns)
helpers.loadAddonFile("Modules/UnitFrames.lua", ns)

local UF = ns.UnitFrames

local function close(actual, expected)
    return type(actual) == "number" and math.abs(actual - expected) < 1e-9
end

-- The game's tables are faked in the same two shapes the client returns them
-- in: the power's string token and its numeric type.
local CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
}
local REACTIONS = {
    [1] = { r = 1, g = 0, b = 0 },
    [5] = { r = 0, g = 1, b = 0 },
}
-- The PowerBarColor shape: a token key and a number key point at one colour.
local POWER_COLORS = {
    MANA   = { r = 0, g = 0, b = 1 },
    RAGE   = { r = 1, g = 0, b = 0 },
    ENERGY = { r = 1, g = 1, b = 0 },
}
POWER_COLORS[0] = POWER_COLORS.MANA
POWER_COLORS[1] = POWER_COLORS.RAGE
POWER_COLORS[3] = POWER_COLORS.ENERGY

-- The ManaBarColor shape of the old builds: the numeric type alone.
local MANA_BAR_COLOR = {
    [0] = { 0.1, 0.1, 0.9 },
    [2] = { 0.9, 0.9, 0.1 },
}

T.suite("a bar's colour: the native look")

T.eq(UF.BarColor(UF.NATIVE, {}), nil,
    "the native look answers nil rather than white: the colour is not ours")
T.eq(UF.BarColor(nil, {}), nil, "there is no setting yet, so the native look again")

T.suite("a bar's colour: the health")

do
    local r, g, b = UF.BarColor("class", {
        class = "MAGE", classColors = CLASS_COLORS,
    })
    T.ok(close(r, 0.41) and close(g, 0.80) and close(b, 0.94),
        "by class means the class colour")
end

-- An unknown class falls back to the reaction: creatures have no class.
do
    local r, g, b = UF.BarColor("class", {
        class = "INVENTION", classColors = CLASS_COLORS,
        reaction = 5, reactionColors = REACTIONS,
    })
    T.ok(close(r, 0) and close(g, 1) and close(b, 0),
        "an unknown class means the reaction is taken")
end

-- Neither a class nor a reaction gives the colour the player chose rather than silence.
do
    local r = UF.BarColor("class", {
        classColors = CLASS_COLORS,
        reactionColors = REACTIONS,
        fixed = { r = 0.3, g = 0.3, b = 0.3 },
    })
    T.ok(close(r, 0.3), "everything unknown gives the custom colour")
end

do
    local r, g, b = UF.BarColor("fixed", { fixed = { r = 0.5, g = 0.25, b = 0.75 } })
    T.ok(close(r, 0.5) and close(g, 0.25) and close(b, 0.75), "the custom colour")
end

T.suite("a bar's colour: the power")

do
    local r, g, b = UF.BarColor("power", {
        power = "RAGE", powerType = 1, powerColors = POWER_COLORS,
    })
    T.ok(close(r, 1) and close(g, 0) and close(b, 0), "rage is red")
end

do
    local r, g, b = UF.BarColor("power", {
        power = "MANA", powerType = 0, powerColors = POWER_COLORS,
    })
    T.ok(close(r, 0) and close(g, 0) and close(b, 1), "mana is blue")
end

-- There is no token but there is a numeric type: the same table answers by the number.
do
    local r, g = UF.BarColor("power", {
        powerType = 3, powerColors = POWER_COLORS,
    })
    T.ok(close(r, 1) and close(g, 1), "energy was found by its numeric type")
end

-- The game's main table is silent, so we ask the fallback one (the old builds).
do
    local r, g, b = UF.BarColor("power", {
        power = "FOCUS", powerType = 2,
        powerColors = POWER_COLORS, powerFallback = MANA_BAR_COLOR,
    })
    T.ok(close(r, 0.9) and close(g, 0.9) and close(b, 0.1),
        "a power unknown to the main table was found in the fallback")
end

-- An unknown power: the addon has no list of colours of its own and must not
-- have one, so we fall back to the colour the player chose.
do
    local r, g, b = UF.BarColor("power", {
        power = "INVENTION", powerType = 99,
        powerColors = POWER_COLORS,
        fixed = { r = 0.2, g = 0.4, b = 0.6 },
    })
    T.ok(close(r, 0.2) and close(g, 0.4) and close(b, 0.6),
        "an unknown kind of power gives the custom colour")
end

-- And white at the very end: a bar with no colour would look broken.
do
    local r, g, b = UF.BarColor("power", {})
    T.ok(close(r, 1) and close(g, 1) and close(b, 1),
        "everything unknown gives white rather than silence")
end

T.suite("a bar's colour: the application")

--- A stand-in bar: the methods the subsystem uses.
local function newBar(r, g, b)
    local bar = { color = { r, g, b }, sets = 0 }
    function bar:GetStatusBarColor()
        return self.color[1], self.color[2], self.color[3], self.color[4]
    end
    function bar:SetStatusBarColor(cr, cg, cb, ca)
        self.color = { cr, cg, cb, ca }
        self.sets = self.sets + 1
    end
    return bar
end

-- A fresh install touches not one object of the game's: the native mode and
-- no darkening mean "do not call SetStatusBarColor at all".
do
    local bar = newBar(0, 1, 0)
    T.eq(UF.ApplyBarColor(bar, UF.NATIVE, {}, 1), false,
        "an untouched bar in the native mode is not touched")
    T.eq(bar.sets, 0, "the colour was never assigned once")
end

-- Reversibility: a return to the native mode restores the game's colour,
-- however many times it was switched before.
do
    local bar = newBar(0, 1, 0)

    UF.ApplyBarColor(bar, "class", {
        class = "MAGE", classColors = CLASS_COLORS,
    }, 1)
    T.ok(close(bar.color[1], 0.41), "the class colour went onto the bar")

    for _ = 1, 5 do
        UF.ApplyBarColor(bar, "fixed", { fixed = { r = 1, g = 1, b = 1 } }, 1)
        UF.ApplyBarColor(bar, UF.NATIVE, {}, 1)
    end
    T.ok(close(bar.color[1], 0) and close(bar.color[2], 1)
        and close(bar.color[3], 0),
        "switching five times restores the game's native colour")
end

T.suite("a bar's colour: the game's colour is observed rather than derived")

-- The very case off the author's screen. The target's bar is covered by our
-- texture while the target has no class and no reaction: the client returns
-- them as secret values, and they arrive here as nils. That used to be the end
-- of it — no colour was found, the bar stayed unpainted and showed the
-- texture's gradient from white. One's own bar looked right meanwhile,
-- because about one's own unit the client answers in the open — and the author saw the difference at once.
--
-- Now the colour is taken from where it always exists: off the bar itself, at
-- the minute the game painted it.
do
    local bar = newBar(0.8, 0.2, 0.2)
    -- A bar under our texture: otherwise "the native mode" means "do not
    -- touch", and there is no point observing.
    bar[UF.APPLIED_FIELD] = "Darken"

    UF.ApplyBarColor(bar, UF.NATIVE,
        { class = nil, reaction = nil, classColors = CLASS_COLORS }, 1, "health")

    T.ok(close(bar.color[1], 0.8) and close(bar.color[2], 0.2)
        and close(bar.color[3], 0.2),
        "the game's colour was kept although the addon knows neither the class nor the reaction")
end

-- And it does not drift from repeats. Without telling our own write from
-- somebody else's the second pass would take our own for "the game's colour",
-- and "as in the game" would mean "as we painted it last time".
do
    local bar = newBar(0.8, 0.2, 0.2)
    bar[UF.APPLIED_FIELD] = "Darken"

    for _ = 1, 10 do
        UF.ApplyBarColor(bar, UF.NATIVE, {}, 1, "health")
    end
    T.ok(close(bar.color[1], 0.8) and close(bar.color[2], 0.2),
        "ten passes in a row did not shift the colour")

    -- While a real change of target — somebody else's write — is picked up at once.
    bar:SetStatusBarColor(0.24, 0.74, 0.30)
    UF.ApplyBarColor(bar, UF.NATIVE, {}, 1, "health")
    T.ok(close(bar.color[2], 0.74),
        "the game's new colour was picked up on the very first update")
end

-- A secret colour does not spoil the previously observed one: an unusable
-- value means "we did not read it" rather than "there is no colour".
do
    local bar = newBar(0.8, 0.2, 0.2)
    bar[UF.APPLIED_FIELD] = "Darken"
    UF.ApplyBarColor(bar, UF.NATIVE, {}, 1, "health")

    local secret = setmetatable({}, { __mul = function() error("secret", 0) end })
    function bar:GetStatusBarColor() return secret, secret, secret end

    T.eq(UF.NoteGameColor(bar), false, "a secret colour is not remembered")
    UF.ApplyBarColor(bar, UF.NATIVE, {}, 1, "health")
    T.ok(close(bar.color[1], 0.8), "and the previously observed one stayed in force")
end

-- Two multipliers fold into one call: the chosen colour is multiplied by the
-- brightness factor.
do
    local bar = newBar(0, 1, 0)
    UF.ApplyBarColor(bar, "fixed", { fixed = { r = 0.8, g = 0.6, b = 0.4 } }, 0.5)
    T.ok(close(bar.color[1], 0.4) and close(bar.color[2], 0.3)
        and close(bar.color[3], 0.2),
        "the custom colour was darkened by the factor")

    -- The slider's second movement is computed from the chosen colour rather
    -- than from the current one: otherwise the factors would multiply together.
    UF.ApplyBarColor(bar, "fixed", { fixed = { r = 0.8, g = 0.6, b = 0.4 } }, 0.25)
    T.ok(close(bar.color[1], 0.2), "the repeat is computed from the chosen colour")

    UF.ApplyBarColor(bar, "fixed", { fixed = { r = 0.8, g = 0.6, b = 0.4 } }, 1)
    T.ok(close(bar.color[1], 0.8), "returning the slider to zero removes the darkening")
end

-- The native colour darkens too: the slider promises "a darker interface"
-- rather than "darker everywhere except the bars".
do
    local bar = newBar(0, 1, 0)
    UF.ApplyBarColor(bar, UF.NATIVE, {}, 0.5)
    T.ok(close(bar.color[2], 0.5), "the native colour was multiplied by the factor")

    UF.ApplyBarColor(bar, UF.NATIVE, {}, 1)
    T.ok(close(bar.color[2], 1), "and comes back at a zero darkening")
end

-- Unusable objects are survived silently: the bars are somebody else's, and
-- the fields holding them are named differently on different builds.
T.eq(UF.ApplyBarColor(nil, "fixed", {}, 1), false, "no bar means nothing to paint")
T.eq(UF.ApplyBarColor({}, "fixed", {}, 1), false, "an object with no methods is skipped")
