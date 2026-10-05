local helpers = require("helpers")

-- Darkness: the slider arithmetic, reversibility and application by group.
--
-- The main thing checked here is reversibility. The styling in Skin/ is
-- one-way, and that has already produced a defect: a switch that switched
-- nothing off. A slider has no right to behave that way: a return to zero
-- must restore the former colour, however many times it was dragged before.

T.suite("darkness: the factor")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)

local Darkness = ns.Darkness

local function close(actual, expected)
    return math.abs(actual - expected) < 1e-9
end

T.eq(Darkness.Factor(0), 1, "zero on the slider means the native look")

-- The extreme position does not destroy the picture. A control that makes
-- what it governs indistinguishable at its extreme is not a regulator.
T.ok(close(Darkness.Factor(100), Darkness.DARKEST),
    "a hundred is the darkest there is")
T.eq(Darkness.DARKEST, 0.15,
    "the end of the scale is 0.15: the author picked the spot by eye, not by calculation")
-- Formerly a floor of 0.20 stood here with a ban on going lower, then black.
-- The current spot was named by the author: "the current 85 is the new 100".
-- The analysis of the whole curve and both of its moves is in tests/test_darkscale.lua.
T.ok(Darkness.Factor(90) < 0.21 and Darkness.Factor(90) > 0.19,
    "the former floor (0.20) stands inside the scale rather than at its end")
-- A scale of two straight lines with a kink at the former edge
-- (Modules/Darkness.lua). The detailed analysis of the curve and of
-- translating old values is in tests/test_darkscale.lua; here is only what a slider is not a slider without.
T.ok(close(Darkness.Factor(Darkness.EDGE), Darkness.EDGE_FACTOR),
    "at the former edge of the scale stands the former floor")
T.ok(close(Darkness.Factor(40),
    1 - (40 / Darkness.EDGE) * (1 - Darkness.EDGE_FACTOR)),
    "up to the kink the scale is linear")
T.ok(close(Darkness.Factor(50), 0.50), "half the slider gives a factor of 0.50")

-- Garbage comes from SavedVariables, where anything can turn up over the years.
T.eq(Darkness.Factor(nil), 1, "nil counts as zero")
T.eq(Darkness.Factor("garbage"), 1, "a string counts as zero")
T.eq(Darkness.Factor(-50), 1, "below zero is clamped")
T.ok(close(Darkness.Factor(500), Darkness.DARKEST), "above a hundred is clamped")
T.ok(close(Darkness.Factor("40"), Darkness.Factor(40)),
    "a numeric string is coerced to a number")

T.suite("darkness: the tint")

-- The tint is not a second mechanism but the same factor with unequal channels.
do
    local r, g, b = Darkness.Multipliers(0, nil)
    T.ok(r == 1 and g == 1 and b == 1, "with no tint and no darkening, ones")

    r, g, b = Darkness.Multipliers(0, { r = 1, g = 1, b = 1 })
    T.ok(r == 1 and g == 1 and b == 1, "a white tint changes nothing")

    -- White is the default: a fresh install does not repaint the interface.
    local white = Darkness.defaults.tint
    T.ok(white.r == 1 and white.g == 1 and white.b == 1,
        "the tint default is white")

    -- The tint applies even at zero on the slider: "in what colour" is a
    -- question separate from "how much darker".
    r, g, b = Darkness.Multipliers(0, { r = 1, g = 0.5, b = 0.8 })
    T.ok(close(r, 1) and close(g, 0.5) and close(b, 0.8),
        "the tint works without darkening")

    -- And it combines with the darkening in one multiplication.
    r, g, b = Darkness.Multipliers(50, { r = 1, g = 0.5, b = 0.8 })
    local factor = Darkness.Factor(50)
    T.ok(close(r, factor) and close(g, factor * 0.5) and close(b, factor * 0.8),
        "the darkening and the tint are one multiplication")

    -- Garbage in a channel counts as one: the setting comes from the profile.
    r, g, b = Darkness.Multipliers(0, { r = "garbage" })
    T.ok(r == 1 and g == 1 and b == 1, "an unusable channel counts as one")

    -- An area in "leave as is" mode gets ones, that is a return to the native
    -- look rather than merely the absence of a new one.
    r, g, b = Darkness.GroupMultipliers("minimap", { minimap = "native" }, 50)
    T.ok(r == 1 and g == 1 and b == 1, "an area left alone gets ones in every channel")
    r, g, b = Darkness.GroupMultipliers("minimap", {}, 50,
        { r = 1, g = 0.8, b = 0.6 })
    T.ok(close(r, 0.5) and close(g, 0.4) and close(b, 0.3),
        "an \"as the shared strength\" area gets the slider coloured by the tint")
end

T.suite("darkness: the area modes")

T.eq(Darkness.GroupFactor("unitframe", nil, 50), 0.5, "with no modes, the slider")
T.eq(Darkness.GroupFactor("unitframe", {}, 50), 0.5, "an empty list does not interfere")
T.eq(Darkness.GroupFactor("unitframe", { unitframe = "native" }, 50), 1,
    "\"leave as is\" gives a one rather than a skip")
T.eq(Darkness.GroupFactor("unitframe", { unitframe = "follow" }, 50), 0.5,
    "a return to \"as the shared strength\" brings the darkening back")
T.eq(Darkness.GroupFactor("unitframe", { actionbar = "native" }, 50), 0.5,
    "another area's mode does not affect this one")

-- A named mode does not listen to the slider: it IS the answer to "how
-- dark", and that number has no second owner.
T.ok(close(Darkness.GroupFactor("unitframe", { unitframe = "dimmed" }, 0), 0.50),
    "Dimmed is a factor of 0.50 at any slider position")
T.ok(close(Darkness.GroupFactor("unitframe", { unitframe = "dark" }, 0), 0.36),
    "Dark is a factor of 0.36")
T.ok(close(Darkness.GroupFactor("unitframe", { unitframe = "moredark" }, 0),
    0.20), "More Dark is a factor of 0.20, the former floor of the scale")

-- Garbage in the profile reads as "as the shared strength": the setting comes
-- from SavedVariables, and a mode the addon no longer knows has no right to
-- leave an area untouched silently.
T.eq(Darkness.ModeOf({ unitframe = "invention" }, "unitframe"), "follow",
    "an unknown mode reads as \"as the shared strength\"")
T.eq(Darkness.ModeOf(nil, "unitframe"), "follow", "and so does a missing table")
T.eq(Darkness.ModeAmount("unitframe", { unitframe = "native" }, 50), nil,
    "\"leave as is\" is not a strength but its absence")

-- === The page the text is printed on ===
--
-- The rule used to be: the text and what it is printed on darken together or
-- not at all. The subsystem never touched the text, so the page under it
-- stayed its own -- the "Quest and Dialog Text" area did not darken by
-- default.
--
-- The author cancelled that: "you can just make it light, since our
-- background is dark". The rule stayed the same -- together or not at all --
-- but is fulfilled by the other half: the page darkens along with everything,
-- and the dark text on it is lifted into light (Darkness.LiftText). The area
-- has no defaults of its own any more.
do
    T.eq(Darkness.ModeOf(nil, "questlog"), "follow",
        "a page with text darkens like everything else")
    T.eq(Darkness.ModeOf({}, "questlog"), "follow",
        "and in an empty profile too")
    T.eq(Darkness.ModeAmount("questlog", nil, 100), 100,
        "and the slider reaches it")

    -- The player's choice is still stronger.
    T.eq(Darkness.ModeOf({ questlog = "native" }, "questlog"), "native",
        "the native look of this area is chosen by hand")
    T.eq(Darkness.ModeOf({ questlog = "dark" }, "questlog"), "dark",
        "and so is any other step")

    -- Garbage in the profile reads as the shared default.
    T.eq(Darkness.ModeOf({ questlog = "invention" }, "questlog"), "follow",
        "garbage reads as \"as the shared strength\"")

    -- Only dark text is lifted: the yellow name of the speaker and the green
    -- quest title carry meaning in their colour and read fine on dark.
    T.eq(Darkness.DarkText(0.16, 0.13, 0.10), true,
        "the brown ink of the page is dark text")
    T.eq(Darkness.DarkText(1, 0.82, 0), false, "a yellow name is not dark")
    T.eq(Darkness.DarkText(1, 1, 1), false, "a white line all the less so")
    T.eq(Darkness.DarkText(nil, 1, 1), false, "an unreadable value is not dark")

    local r, g, b = Darkness.Ink()
    T.ok(Darkness.DarkText(r, g, b) == false,
        "the colour we lift into does not itself count as dark")

    T.eq(Darkness.ModeOf(nil, "unitframe"), "follow",
        "the other areas keep the former default")
    T.eq(Darkness.ModeOf(nil, "window"), "follow", "and so do the other windows")
end

T.suite("darkness: reversibility")

--- A fake texture: exactly the two methods the subsystem uses.
local function newTexture(r, g, b, a)
    local texture = { r = r, g = g, b = b, a = a, sets = 0 }
    -- The fake must name the object type: the selection rule lives in the
    -- same place the colour changes, and to it an object with no type is not a texture.
    function texture:GetObjectType() return "Texture" end
    -- A path to a trim image. Without it a coloured fake would fall under the
    -- rule about fills with no image (a coloured fill is a reading, not a
    -- backdrop), and that is not what this is about.
    function texture:GetTexture()
        return "Interface\\DialogFrame\\UI-DialogBox-Background"
    end
    function texture:GetVertexColor()
        if self.a == nil then return self.r, self.g, self.b end
        return self.r, self.g, self.b, self.a
    end
    function texture:SetVertexColor(nr, ng, nb, na)
        self.r, self.g, self.b = nr, ng, nb
        if na ~= nil then self.a = na end
        self.sets = self.sets + 1
    end
    return texture
end

local texture = newTexture(0.8, 0.6, 0.4, 0.5)

T.ok(Darkness.Tint(texture, 0.5), "the texture is darkened")
T.ok(close(texture.r, 0.4) and close(texture.g, 0.3) and close(texture.b, 0.2),
    "the colour was multiplied by the factor")
T.eq(texture.a, 0.5, "the alpha is untouched")

-- The second slider move is computed from the remembered colour rather than
-- the current one: otherwise the factors would multiply and "40 after 50"
-- would not give the same as "40 at once".
Darkness.Tint(texture, 0.25)
T.ok(close(texture.r, 0.2) and close(texture.g, 0.15) and close(texture.b, 0.1),
    "a repeated application is computed from the original colour")

-- Many moves in a row are the same: the remembered colour is written once.
for i = 1, 20 do
    Darkness.Tint(texture, i / 20)
end
Darkness.Tint(texture, 1)
T.ok(close(texture.r, 0.8) and close(texture.g, 0.6) and close(texture.b, 0.4),
    "a return to one restores the original colour after twenty moves")
T.eq(texture.a, 0.5, "the alpha survived every move")

-- Some clients return GetVertexColor with three values. Then three go back
-- too: the engine would read a nil fourth as "make it transparent".
local noAlpha = newTexture(1, 1, 1, nil)
Darkness.Tint(noAlpha, 0.5)
T.eq(noAlpha.a, nil, "with no alpha none is assigned")
T.ok(close(noAlpha.r, 0.5), "the colour is darkened anyway")

-- Unusable objects are survived silently: the regions are foreign, and one
-- of them will one day turn out to lack the needed method.
T.eq(Darkness.Tint(nil, 0.5), false, "nil instead of a texture")
T.eq(Darkness.Tint({}, 0.5), false, "an object with no methods")
T.eq(Darkness.Tint({ GetVertexColor = function() return nil end,
    SetVertexColor = function() end }, 0.5), false, "the colour could not be read")

T.suite("darkness: walking a frame")

--- A fake frame with regions.
local function newFrame(regions)
    return {
        GetRegions = function() return unpack(regions) end,
    }
end

local tex1 = newTexture(1, 1, 1, 1)
local tex2 = newTexture(0.5, 0.5, 0.5, 1)
local fontString = {
    GetObjectType = function() return "FontString" end,
    GetVertexColor = function() return 1, 1, 1, 1 end,
    SetVertexColor = function() error("a font string must not be touched") end,
}
tex1.GetObjectType = function() return "Texture" end
tex2.GetObjectType = function() return "Texture" end

local frame = newFrame({ tex1, fontString, tex2 })
T.eq(Darkness.ApplyToFrame(frame, 0.5), 2, "only the textures were processed")
T.ok(close(tex1.r, 0.5), "the first texture is darkened")
T.ok(close(tex2.r, 0.25), "the second texture is darkened")

T.eq(Darkness.ApplyToFrame(nil, 0.5), 0, "no frame means nothing to do")
T.eq(Darkness.ApplyToFrame({}, 0.5), 0, "an object without GetRegions is survived")

T.suite("darkness: walking the children")

-- The very defect the walk descends for: in current builds the textures of a
-- unit frame lie not in the regions of the frame itself but in its child
-- container frames. A one-level walk found zero textures and honestly
-- reported success -- the slider "changed nothing".

--- A fake frame with regions, children and a type.
local function newContainer(objectType, regions, children)
    return {
        GetObjectType = function() return objectType end,
        GetRegions = function() return unpack(regions or {}) end,
        GetChildren = function() return unpack(children or {}) end,
    }
end

local function newTinted(r, g, b)
    local texture = newTexture(r, g, b, 1)
    texture.GetObjectType = function() return "Texture" end
    return texture
end

do
    local art     = newTinted(1, 1, 1)   -- a container region, level 1
    local portrait = newTinted(0.8, 0.8, 0.8) -- level 2
    local barFill = newTinted(1, 1, 1)   -- a bar texture: not ours

    local container = newContainer("Frame", { art },
        { newContainer("Frame", { portrait }) })
    -- The health bar is a StatusBar. Its colour belongs to the unit frames,
    -- and the walk must pass it by entirely, along with its textures.
    local bar = newContainer("StatusBar", { barFill })

    local frame = newContainer("Frame", {}, { container, bar })

    T.eq(Darkness.ApplyToFrame(frame, 0.5), 2,
        "the child textures are darkened, the bar is skipped")
    T.ok(close(art.r, 0.5), "the container texture is darkened")
    T.ok(close(portrait.r, 0.4), "a texture two levels deep is darkened")
    T.eq(barFill.r, 1, "the bar texture is untouched")
    T.eq(Darkness.Remembered(barFill), nil, "and darkness did not remember it")
end

-- The depth is limited by a budget: a full walk of the game frame tree would
-- cost more than it is worth. But the budget must cover REAL windows, and in
-- current builds they are nested deep: the textures of the talent window lie
-- five levels below its border, and a walk that stopped at the fourth took
-- the border and nothing else.
do
    -- Eight levels: deeper than any real window and shallower than the budget.
    local deep = newTinted(1, 1, 1)
    local node = newContainer("Frame", { deep })
    for _ = 1, 8 do
        node = newContainer("Frame", {}, { node })
    end
    T.eq(Darkness.ApplyToFrame(node, 0.5), 1,
        "the walk reaches a texture on the eighth level")
    T.ok(close(deep.r, 0.5), "and darkens it")

    -- The budget does exist and it does run out: the walk does not walk a
    -- bottomless tree, otherwise one window of a foreign addon would eat a whole frame.
    local bottomless = newTinted(1, 1, 1)
    local far = newContainer("Frame", { bottomless })
    for _ = 1, 20 do
        far = newContainer("Frame", {}, { far })
    end
    T.eq(Darkness.ApplyToFrame(far, 0.5), 0, "we do not go deeper than the budget")
    T.eq(bottomless.r, 1, "and we tint nothing there")
end

T.suite("darkness: the module")

T.eq(Darkness.name, "darkness", "the module name")
T.ok(ns.Registry:Get("darkness") ~= nil, "the module is registered in the registry")
-- Eighty rather than the former sixty-four: the author sent a screenshot of
-- his settings saying "these should be the defaults".
T.eq(Darkness.defaults.amount, 80,
    "a fresh install is darkened by eighty")
T.ok(Darkness.defaults.desaturate == true,
    "and its trim is grey, not merely dark")
T.ok(Darkness.defaults.level == false,
    "while the brightness levelling is off: the author chose it so")
T.eq(type(Darkness.defaults.mode), "table", "the area modes are a table")
T.eq(Darkness.defaults.mode.unitframe, "follow",
    "and every area there stands at \"as the shared strength\"")
T.eq(type(Darkness.OnEnable), "function", "OnEnable is in place")
T.eq(type(Darkness.ApplySettings), "function", "ApplySettings is in place")
T.eq(type(Darkness.options), "table", "the settings section is in place")

T.suite("darkness: applying the settings")

-- Compat.Resolve looks into _G: with no client frames we substitute our own
-- and clean up after ourselves, so the state does not leak into neighbouring files of the suite.
local FRAME_NAMES = { "PlayerFrame", "TargetFrame", "PetFrame" }
local savedGlobals = {}
for i = 1, #FRAME_NAMES do savedGlobals[i] = _G[FRAME_NAMES[i]] end

local frames = {}
for i = 1, #FRAME_NAMES do
    local region = newTexture(1, 0.8, 0.6, 1)
    region.GetObjectType = function() return "Texture" end
    frames[FRAME_NAMES[i]] = region
    _G[FRAME_NAMES[i]] = newFrame({ region })
end

ns.flavor = "vanilla"
local profile = { darkness = { amount = 50, mode = {} } }
ns.Addon = { db = { profile = profile } }

Darkness:ApplySettings()
-- A white channel also comes under the brightness ceiling, see helpers.whiteAt.
local white50 = helpers.whiteAt(Darkness.Factor(50))
T.ok(close(frames.PlayerFrame.r, white50), "the player frame is darkened")
T.ok(close(frames.TargetFrame.r, white50), "the target frame is darkened")

-- Immediacy: editing the setting leads into the same ApplySettings, and the
-- second value is applied over the first with no reload.
profile.darkness.amount = 25
Darkness:ApplySettings()
T.ok(close(frames.PlayerFrame.r, helpers.whiteAt(Darkness.Factor(25))),
    "the new value was applied at once")

-- Zero restores the former look -- that IS reversibility at the module level.
profile.darkness.amount = 0
Darkness:ApplySettings()
T.ok(close(frames.PlayerFrame.r, 1) and close(frames.PlayerFrame.g, 0.8)
    and close(frames.PlayerFrame.b, 0.6), "zero restored the original colour")

-- An exception removes the darkening from a group rather than merely ceasing
-- to apply it.
profile.darkness.amount = 50
Darkness:ApplySettings()
T.ok(close(frames.PlayerFrame.r, white50), "the darkening was applied")
profile.darkness.mode.unitframe = "native"
Darkness:ApplySettings()
T.ok(close(frames.PlayerFrame.r, 1),
    "an area set to \"leave as is\" returned to its native look")

-- A named area mode does not listen to the slider.
profile.darkness.mode.unitframe = "moredark"
Darkness:ApplySettings()
T.ok(close(frames.PlayerFrame.r, helpers.whiteAt(0.20)),
    "while a named mode holds its own whatever the slider is")
profile.darkness.mode.unitframe = "follow"

-- There are no settings (the profile is not created yet) -- we stay silent rather than fail.
ns.Addon = { db = { profile = {} } }
Darkness:ApplySettings()
T.ok(true, "with no settings section ApplySettings does not fail")

-- A group absent from this client is skipped silently: Resolve returns an
-- empty list, and there are no client version checks in the module.
ns.flavor = "mists"
ns.Addon = { db = { profile = { darkness = { amount = 50, mode = {} } } } }
for i = 1, #FRAME_NAMES do _G[FRAME_NAMES[i]] = nil end
Darkness:ApplySettings()
T.ok(true, "non-existent frames do not break the application")

for i = 1, #FRAME_NAMES do _G[FRAME_NAMES[i]] = savedGlobals[i] end

T.suite("darkness: the settings")

-- The level lives in arg.level and only there: AceConfig does not know a
-- top-level level field and fails to open the window.
local args = Darkness.options.args
T.eq(args.amount.min, 0, "the slider starts at zero")
T.eq(args.amount.max, 100, "the slider ends at a hundred")

-- Every area the subsystem can darken has its own mode selection: an area
-- with no selection would darken while there would be nothing to govern it with.
local values = {}
for i = 1, #Darkness.MODES do
    values[Darkness.MODES[i].key] = true
end
T.ok(values.follow and values.native, "both special modes are in place")
T.ok(args[Darkness.OptionKey("unitframe")] ~= nil,
    "the unit frames have a mode selection")

-- The darkening is about the whole interface rather than about the unit
-- frames alone: that is exactly what the author called a defect. The group
-- list must cover what the player looks at, and every row of the list must
-- be a group the compatibility layer knows by name.
for _, key in ipairs({ "unitframe", "actionbar-art", "minimap", "bags",
                       "chat", "objectives", "tooltip", "character",
                       "questlog" }) do
    T.ok(args[Darkness.OptionKey(key)] ~= nil,
        "the area has a mode selection: " .. key)
    T.ok(ns.Compat.HasGroup("vanilla", key),
        "the compatibility layer knows the group: " .. key)
    T.ok(ns.Compat.HasGroup("mists", key),
        "and knows it on every served client: " .. key)
end

-- Reading and writing the setting go through the profile.
ns.Addon = { db = { profile = { darkness = { amount = 30, mode = {} } } } }
ns.flavor = "vanilla"
T.eq(args.amount.get(), 30, "the slider reads the value from the profile")
args.amount.set(nil, 70)
T.eq(ns.Addon.db.profile.darkness.amount, 70, "the slider writes the value into the profile")

local uf = args[Darkness.OptionKey("unitframe")]
T.eq(uf.get(), "follow", "the area stands at \"as the shared strength\"")
uf.set(nil, "native")
T.eq(ns.Addon.db.profile.darkness.mode.unitframe, "native",
    "the choice went into the profile")
T.eq(uf.get(), "native", "and reads back")

-- With no settings database the handlers stay silent: the settings window
-- may have been opened before the profile was created.
ns.Addon = nil
T.eq(args.amount.get(), 0, "with no database the slider shows zero")
T.eq(uf.get(), "follow", "with no database the area stands at \"as the shared strength\"")
args.amount.set(nil, 50)
uf.set(nil, "native")
T.ok(true, "with no database a write breaks nothing")
T.suite("darkness: trim and content")

-- The main rule of the subsystem after the changes: the interface trim
-- darkens, its content does not. Formerly the rule was the nesting depth,
-- and that gave exactly the opposite -- the author saw a darkened character
-- portrait in the client and called it a defect.

--- A fake region with an arbitrary set of markers.
local function newRegion(kind, opts)
    opts = opts or {}
    local region = {
        GetObjectType = function() return kind end,
    }
    if opts.layer then
        region.GetDrawLayer = function() return opts.layer end
    end
    if opts.name then
        region.GetName = function() return opts.name end
    end
    if opts.path then
        region.GetTexture = function() return opts.path end
    end
    return region
end

T.ok(Darkness.IsChrome(newRegion("Texture")), "an ordinary texture is trim")
T.eq(Darkness.IsChrome(newRegion("FontString")), false,
    "a font string is not darkened: the text must stay readable")
T.eq(Darkness.IsChrome(newRegion("PlayerModel")), false,
    "a character model is not darkened")
T.eq(Darkness.IsChrome(nil), false, "nothing is not trim")

T.eq(Darkness.IsChrome(newRegion("Texture", { layer = "HIGHLIGHT" })), false,
    "a highlight under the cursor is feedback rather than trim")
T.ok(Darkness.IsChrome(newRegion("Texture", { layer = "BORDER" })),
    "a border is trim")

T.eq(Darkness.IsChrome(newRegion("Texture", { name = "PlayerPortrait" })), false,
    "a unit portrait is not darkened")
T.eq(Darkness.IsChrome(newRegion("Texture", { name = "ActionButton1Icon" })), false,
    "a button icon is not darkened")
T.ok(Darkness.IsChrome(newRegion("Texture", { name = "MinimapBorderTop" })),
    "the map outline is trim")

T.eq(Darkness.IsChrome(newRegion("Texture",
    { path = "Interface\\Icons\\Spell_Fire_Fireball" })), false,
    "a texture from the icon folder is content")
T.ok(Darkness.IsChrome(newRegion("Texture",
    { path = "Interface\\DialogFrame\\UI-DialogBox-Border" })),
    "a dialog border texture is trim")

-- A portrait and an icon are assigned by numeric file id: they cannot be told
-- apart by the texture itself, but their owner keeps them in a field with a telling name.
do
    local portrait = newRegion("Texture")
    portrait.GetVertexColor = function() return 1, 1, 1, 1 end
    portrait.SetVertexColor = function() error("the portrait must not be touched") end

    local art = newTinted(1, 1, 1)

    local frame = {
        portrait = portrait,
        GetObjectType = function() return "Frame" end,
        GetRegions = function() return art, portrait end,
    }

    T.eq(Darkness.ApplyToFrame(frame, 0.5), 1,
        "the portrait from the frame field was skipped, the trim was darkened")
    T.ok(close(art.r, 0.5), "the trim is darkened")
end

-- The map itself is a picture of the world rather than a frame around it: the
-- walk does not go inside it at all, just as it does not go inside a bar.
do
    local inside = newTinted(1, 1, 1)
    local map = newContainer("Minimap", { inside })
    T.eq(Darkness.ApplyToFrame(map, 0.5), 0, "the walk does not go inside the map")
    T.eq(inside.r, 1, "and tints nothing there")
end

T.suite("darkness: the tint is applied to a texture")

do
    local texture = newTexture(1, 1, 1, 1)
    texture.GetObjectType = function() return "Texture" end

    Darkness.Tint(texture, 0.5, 0.25, 1)
    T.ok(close(texture.r, 0.5) and close(texture.g, 0.25)
        and close(texture.b, 1), "the channels are dimmed differently")

    -- A return to ones restores the original colour: the tint is as reversible
    -- as the darkening.
    Darkness.Tint(texture, 1, 1, 1)
    T.ok(close(texture.r, 1) and close(texture.g, 1) and close(texture.b, 1),
        "ones in every channel restore the native colour")
end

T.suite("darkening: windows with text on parchment")

-- The dialogue windows -- a quest, a guard, a trainer, a book -- are written
-- dark on light: the game draws parchment and lays brown letters over it.
-- Darkening the parchment we get dark letters on dark, that is a window in
-- which nothing can be read.
--
-- A list by name did not fix that, and it was verified twice by the author's
-- screenshots: in this client the quest log window lives INSIDE the world
-- map, and the common pass reaches it from above, from the map, where there is no quest log name at all.
-- Hence a rule by name prefix rather than a list.
do
    local Darkness = ns.Darkness

    T.eq(Darkness.TextWindow("QuestFrame"), true, "the quest window")
    T.eq(Darkness.TextWindow("QuestLogPopupDetailFrame"), true,
        "a detached quest window -- what the author sent as a screenshot")
    T.eq(Darkness.TextWindow("QuestMapDetailsScrollFrame"), true,
        "and the quest panel inside the map")
    T.eq(Darkness.TextWindow("GossipFrame"), true, "a conversation with a guard")
    T.eq(Darkness.TextWindow("ClassTrainerFrame"), true, "the trainer window")
    T.eq(Darkness.TextWindow("ItemTextFrame"), true, "a book")

    -- A prefix rather than a fragment: a foreign window with the word
    -- somewhere in the middle of its name has nothing to do with dialogue, and
    -- giving it another area's mode would mean leaving it light unasked.
    T.eq(Darkness.TextWindow("SearchQuestFrame"), false,
        "a name with the word in the middle is not a dialogue window")
    T.eq(Darkness.TextWindow("WorldMapFrame"), false, "the world map is not one")
    T.eq(Darkness.TextWindow("CharacterFrame"), false, "nor the character sheet")
    T.eq(Darkness.TextWindow(""), false, "an empty name")
    T.eq(Darkness.TextWindow(nil), false, "and no name at all")

    -- The area has no default of its own any more: the page darkens along with
    -- everything, and the dark text on it is lifted into light. The window name
    -- still decides which area it belongs to -- it is asked for the sake of
    -- the text lift.
    T.eq(Darkness.DEFAULT_MODES.questlog, nil,
        "the dialogue windows darken like everything else")
end

-- And the same by the walk rather than by a name alone: the trouble was NOT
-- that the name was not recognised but that the pass reached the dialogue
-- window from above -- from the world map, which has a name of its own. The area must travel down the tree.
do
    local Darkness = ns.Darkness

    local function paint(r)
        return {
            GetObjectType = function() return "Texture" end,
            GetVertexColor = function() return 1, 1, 1, 1 end,
            SetVertexColor = function() end,
            GetTexture = function() return [[Interface\FrameGeneral\UI-Background]] end,
            GetDrawLayer = function() return "BACKGROUND" end,
            GetName = function() return nil end,
            GetAtlas = function() return nil end,
        }
    end

    local function box(name, regions, children)
        return {
            GetName = function() return name end,
            GetObjectType = function() return "Frame" end,
            GetRegions = function() return unpack(regions or {}) end,
            GetChildren = function() return unpack(children or {}) end,
        }
    end

    -- The world map, with a quest panel and parchment inside it.
    local parchment = paint()
    local details = box("QuestMapDetailsScrollFrame", { parchment })
    local map = box("WorldMapFrame", { paint() }, { details })

    local areas = Darkness.AreasIn(map)

    T.eq(areas.questlog, 1,
        "the parchment inside the map went to the dialogue area")
    T.eq(areas.window, 1, "while the map itself stayed in the shared area")

    -- Beyond two levels the name is not asked for: there are no real cases
    -- there, and a read on every interface frame costs money. Parchment on the
    -- third level stays in the shared area -- and that is a deliberate boundary, not a miss.
    local deep = box("WorldMapFrame", {}, {
        box("Middle", {}, { box("QuestFrame", { paint() }) }),
    })
    local deepAreas = Darkness.AreasIn(deep)
    T.eq(deepAreas.questlog, 1, "on the second level the name is still asked for")
end
