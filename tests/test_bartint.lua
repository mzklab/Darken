local helpers = require("helpers")

-- The texture lies over the colour rather than replacing it.
--
-- The defect the file is written for the author saw in the client: our own
-- texture on the health bar showed its own light gradient and nothing more.
-- The sequence that led to it was this one.
-- A bar the game has not painted yet (the target at login) or does not intend
-- to paint (its colour is drawn in the native texture's own file) the
-- subsystem reads before the replacement and gets white. Then it sets its own
-- texture and honestly restores what it read — white. And then it does
-- nothing: with "the game's colour" chosen ApplyBarColor left at its very
-- first line, because the bar has no colour of its own. The colour under our
-- texture turned out to have no owner at all, and the gradient stayed untinted.
--
-- That cannot be fixed in the texture's replacement: a colour the bar never
-- had cannot be assigned by reading the bar's own colour. So the rule lives
-- in the colour: under our texture "the game's colour" means not "do not
-- touch" but "compute from the game's tables" (UnitFrames.GameColor). What is
-- checked here is exactly the sequence that gave white, and its three
-- continuations: the replacement's early exit, the game repainting after us,
-- and the return to the native texture.

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Events.lua", ns)
helpers.loadAddonFile("Core/Combat.lua", ns)
helpers.loadAddonFile("Modules/UnitFrames.lua", ns)

local UF = ns.UnitFrames

local OURS = "Interface\\AddOns\\Darken\\Media\\mzk.tga"
local NATIVE_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local CLASS_COLORS = {
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}
local REACTIONS = {
    [1] = { r = 1, g = 0, b = 0 },
    [5] = { r = 0, g = 1, b = 0 },
}
local POWER_COLORS = {
    MANA = { r = 0, g = 0, b = 1 },
    RAGE = { r = 1, g = 0, b = 0 },
}
POWER_COLORS[0] = POWER_COLORS.MANA
POWER_COLORS[1] = POWER_COLORS.RAGE

local function close(actual, expected)
    return type(actual) == "number" and math.abs(actual - expected) < 1e-9
end

--- Whether the bar really is white.
-- White is not "some colour" but the very defect: our gradient is almost
-- white in itself, and untinted that is exactly how it looks.
local function white(bar)
    return close(bar.color[1], 1) and close(bar.color[2], 1)
        and close(bar.color[3], 1)
end

--- A stand-in bar.
--
-- It repeats the two traits of the client the defect arose from. The first:
-- SetStatusBarTexture resets the vertex colour to white — that is how some
-- builds behave. The second: the bar's colour is white to begin with, that
-- is, the game has not painted it yet. It is with such a bar that entering the game begins.
--
-- @param r number|nil the colour already on the bar; nil means white
local function newBar(r, g, b)
    local bar = {
        texture = NATIVE_BAR,
        color   = { r or 1, g or 1, b or 1, 1 },
        sets    = 0,
    }
    function bar:SetStatusBarTexture(path)
        self.texture = path
        self.sets = self.sets + 1
        self.color = { 1, 1, 1, 1 }
    end
    function bar:GetStatusBarTexture()
        local owner = self
        return { GetTexture = function() return owner.texture end }
    end
    function bar:GetStatusBarColor()
        return self.color[1], self.color[2], self.color[3], self.color[4]
    end
    function bar:SetStatusBarColor(cr, cg, cb, ca)
        self.color = { cr, cg, cb, ca }
    end
    return bar
end

--- The facts about a unit as the game returns them for a health bar.
local function healthInfo(class, reaction)
    return {
        class          = class,
        classColors    = CLASS_COLORS,
        reaction       = reaction,
        reactionColors = REACTIONS,
        fixed          = { r = 0.3, g = 0.3, b = 0.3 },
    }
end

--- The full application onto one bar: the texture first, then the colour.
-- The same order as in ApplyFrameTextures and ApplyFrameColors.
local function dress(bar, path, mode, info)
    UF.BaseTexture(bar)
    UF.SetBarTexture(bar, path)
    UF.ApplyBarColor(bar, mode, info, 1, "health")
end

T.suite("the bar: the game's colour under our texture")

-- The pure rule apart from the bar: there is no white at the end and there must not be.
do
    local r, g, b = UF.GameColor("health", healthInfo("MAGE", 5))
    T.ok(close(r, 0.41) and close(g, 0.80) and close(b, 0.94),
        "a player's health is the class colour")

    r, g, b = UF.GameColor("health", healthInfo(nil, 1))
    T.ok(close(r, 1) and close(g, 0) and close(b, 0),
        "a creature has no class, so the colour comes by its reaction to the player")

    r = UF.GameColor("health", healthInfo(nil, nil))
    T.eq(r, nil, "the game does not know the colour, so nil rather than white")

    r, g, b = UF.GameColor("power", {
        power = "RAGE", powerType = 1, powerColors = POWER_COLORS,
    })
    T.ok(close(r, 1) and close(g, 0) and close(b, 0), "rage is red")

    T.eq(UF.GameColor("power", { powerColors = POWER_COLORS }), nil,
        "an unknown kind of power gives nil")
    T.eq(UF.GameColor(nil, healthInfo("MAGE", 5)), nil,
        "a bar with no kind is not painted")
end

-- The very sequence. The bar has not been painted by the game yet, our
-- texture is laid onto it — and the result is obliged to be coloured.
do
    local bar = newBar()
    T.ok(white(bar), "before everything the bar is white: the game has not painted it yet")

    dress(bar, OURS, UF.NATIVE, healthInfo("MAGE", 5))

    T.eq(bar.texture, OURS, "our texture is on the bar")
    T.ok(not white(bar), "the bar is not white: the texture lay over a colour")
    T.ok(close(bar.color[1], 0.41) and close(bar.color[2], 0.80)
        and close(bar.color[3], 0.94),
        "the game's colour was computed from its own table of classes")
end

-- The first continuation: the game paints the bar after us. It will erase our
-- colour, and the repainting (Repaint -> ApplyFrameColors) is obliged to put it back.
do
    local bar = newBar()
    dress(bar, OURS, UF.NATIVE, healthInfo("MAGE", 5))

    bar:SetStatusBarColor(1, 1, 1, 1)
    T.ok(white(bar), "the game repainted the bar its own way")

    UF.ApplyBarColor(bar, UF.NATIVE, healthInfo("MAGE", 5), 1, "health")
    T.ok(close(bar.color[1], 0.41), "after the game the colour went on afresh")
end

-- The second continuation: the texture replacement's early exit. A second
-- application of the same texture does not touch the file — and that does not stop it fixing the colour.
do
    local bar = newBar()
    dress(bar, OURS, UF.NATIVE, healthInfo(nil, nil))
    T.ok(white(bar), "there is no target yet, the game does not know the colour, the bar is untouched")

    dress(bar, OURS, UF.NATIVE, healthInfo("WARRIOR", 5))
    T.eq(bar.sets, 1, "the same texture is not assigned a second time")
    T.ok(close(bar.color[1], 0.78) and close(bar.color[3], 0.43),
        "while the colour of a target that appeared went on despite the early exit")
end

-- The third continuation: the return to the native texture restores the
-- native look entirely — both the texture and the colour that stood on the bar before us.
do
    local bar = newBar(0, 1, 0)
    dress(bar, OURS, UF.NATIVE, healthInfo("MAGE", 5))
    T.ok(close(bar.color[1], 0.41), "under our texture the colour is our computed one")

    UF.SetBarTexture(bar, NATIVE_BAR)
    UF.ApplyBarColor(bar, UF.NATIVE, healthInfo("MAGE", 5), 1, "health")

    T.eq(bar.texture, NATIVE_BAR, "the native texture came back")
    T.ok(close(bar.color[1], 0) and close(bar.color[2], 1)
        and close(bar.color[3], 0),
        "and the game's native colour with it rather than our computed one")
end

-- The native texture owns the colour itself: a fresh install does not touch
-- the bar with a single call. The rule is the old one and should not have moved.
do
    local bar = newBar(0, 1, 0)
    UF.BaseTexture(bar)
    T.eq(UF.Textured(bar), false, "the native texture is on the bar")
    T.eq(UF.ApplyBarColor(bar, UF.NATIVE, healthInfo("MAGE", 5), 1, "health"),
        false, "and its colour stays the game's business")
    T.ok(close(bar.color[2], 1), "the bar is untouched")
end

-- The colour the player chose outranks the computed one: "a custom colour" means custom.
do
    local bar = newBar()
    UF.BaseTexture(bar)
    UF.SetBarTexture(bar, OURS)
    UF.ApplyBarColor(bar, "fixed", {
        fixed = { r = 0.5, g = 0.25, b = 0.75 },
    }, 1, "health")
    T.ok(close(bar.color[1], 0.5) and close(bar.color[3], 0.75),
        "under our texture the chosen colour is replaced by nobody")
end

-- The power bar goes the same path and by its own kind of power.
do
    local bar = newBar()
    UF.BaseTexture(bar)
    UF.SetBarTexture(bar, OURS)
    UF.ApplyBarColor(bar, UF.NATIVE, {
        power = "MANA", powerType = 0, powerColors = POWER_COLORS,
    }, 1, "power")
    T.ok(close(bar.color[3], 1) and close(bar.color[1], 0),
        "mana under our texture is blue")
end

T.suite("the bar: our own texture on it or the native one")

do
    T.eq(UF.Textured(nil), false, "no bar means no texture either")
    T.eq(UF.Textured({}), false, "an untouched bar wears the native one")

    local bar = newBar()
    UF.BaseTexture(bar)
    UF.SetBarTexture(bar, OURS)
    T.eq(UF.Textured(bar), true, "after the replacement ours is on the bar")

    UF.SetBarTexture(bar, NATIVE_BAR)
    T.eq(UF.Textured(bar), false, "a return to the remembered native one means not ours again")
end

-- The native texture could not be read: then everything on the bar that came
-- from us counts as ours — ours we set ourselves.
do
    local bar = newBar()
    bar.GetStatusBarTexture = nil
    UF.BaseTexture(bar)
    UF.SetBarTexture(bar, OURS)
    T.eq(UF.Textured(bar), true,
        "the native one could not be read, our texture is ours all the same")
end
