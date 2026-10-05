local helpers = require("helpers")

-- Unit frames: the name colour, the deferral queue and applying the settings.
--
-- Two subjects this file was written for. The first is the rule for choosing
-- the name colour: it has three modes and two fallback steps, and a mistake
-- in it shows "every other time", only on the right kind of unit. The second
-- is the queue: it exists for exactly one engine-protected operation (the
-- scale), and it can only be checked in the client in combat, that is inconveniently and unreliably.

local savedLibStub = LibStub

-- A fake texture library.
local fakeMedia = {
    List = function(_, kind)
        if kind == "statusbar" then return { "Darken Purple", "Darken Blue" } end
        return {}
    end,
    IsValid = function(_, kind, name)
        return kind == "statusbar"
            and (name == "Darken Purple" or name == "Darken Blue")
    end,
    Fetch = function(_, kind, name)
        if kind ~= "statusbar" then return nil end
        if name == "Darken Purple" then return "Media\\mzk.tga" end
        if name == "Darken Blue" then return "Media\\mzk-blue.tga" end
        return nil
    end,
}

LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return fakeMedia end
    return nil
end

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
-- Core/Media.lua: resolving a texture name to a file lives there, and ns.Skin.MediaTexture
-- calls it (Core/Skin.lua). Without that file the core would find no texture at all.
helpers.loadAddonFile("Core/Media.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Events.lua", ns)
helpers.loadAddonFile("Core/Combat.lua", ns)
helpers.loadAddonFile("Modules/UnitFrames.lua", ns)

local UF = ns.UnitFrames

T.suite("unit frames: the name colour")

local CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
}
local REACTIONS = {
    [1] = { r = 1, g = 0, b = 0 },
    [4] = { r = 1, g = 1, b = 0 },
    [5] = { r = 0, g = 1, b = 0 },
}

do
    local r, g, b = UF.NameColor("class", {
        class = "MAGE", classColors = CLASS_COLORS,
    })
    T.eq(r, 0.41, "by class: the red channel")
    T.eq(g, 0.80, "by class: the green channel")
    T.eq(b, 0.94, "by class: the blue channel")
end

-- The class is unknown (the unit is not a player) -- we fall back to the reaction rather than stay silent.
do
    local r, g, b = UF.NameColor("class", {
        class = nil, classColors = CLASS_COLORS,
        reaction = 4, reactionColors = REACTIONS,
        fixed = { r = 0.1, g = 0.2, b = 0.3 },
    })
    T.eq(r, 1, "no class -- the reaction is used (red)")
    T.eq(g, 1, "no class -- the reaction is used (green)")
    T.eq(b, 0, "no class -- the reaction is used (blue)")
end

-- There is a class but it is not in the palette -- the same fallback.
do
    local r = UF.NameColor("class", {
        class = "INVENTION", classColors = CLASS_COLORS,
        reaction = 5, reactionColors = REACTIONS,
    })
    T.eq(r, 0, "an unknown class -- the reaction is used")
end

do
    local r, g, b = UF.NameColor("reaction", {
        reaction = 1, reactionColors = REACTIONS,
    })
    T.eq(r, 1, "by reaction: hostile red")
    T.eq(g, 0, "by reaction: the green channel")
    T.eq(b, 0, "by reaction: the blue channel")
end

-- The reaction is unknown -- we fall back to the colour chosen by the player.
do
    local r, g, b = UF.NameColor("reaction", {
        reaction = nil, reactionColors = REACTIONS,
        fixed = { r = 0.1, g = 0.2, b = 0.3 },
    })
    T.eq(r, 0.1, "no reaction -- the own colour (red)")
    T.eq(g, 0.2, "no reaction -- the own colour (green)")
    T.eq(b, 0.3, "no reaction -- the own colour (blue)")
end

do
    local r, g, b = UF.NameColor("fixed", { fixed = { r = 0.5, g = 0.25, b = 0.75 } })
    T.eq(r, 0.5, "the own colour: red")
    T.eq(g, 0.25, "the own colour: green")
    T.eq(b, 0.75, "the own colour: blue")
end

-- An array of three numbers is the second accepted form of a colour.
do
    local r, g, b = UF.NameColor("fixed", { fixed = { 0.2, 0.4, 0.6 } })
    T.eq(r, 0.2, "a colour as an array: red")
    T.eq(g, 0.4, "a colour as an array: green")
    T.eq(b, 0.6, "a colour as an array: blue")
end

-- White is the last line: there must always be a colour, silence is worse.
do
    local r, g, b = UF.NameColor("invention", nil)
    T.eq(r, 1, "an unknown mode with no data gives white (red)")
    T.eq(g, 1, "an unknown mode with no data gives white (green)")
    T.eq(b, 1, "an unknown mode with no data gives white (blue)")
end

-- With no reaction palette of its own the built-in one is used: a colour will be found anyway.
do
    local r = UF.NameColor("reaction", { reaction = 4 })
    T.ok(type(r) == "number", "the built-in reaction palette answers with a number")
end

T.suite("unit frames: the deferral queue")

do
    local queue = UF.NewQueue()
    T.eq(UF.Pending(queue), 0, "a new queue is empty")
    T.eq(UF.Drain(queue), 0, "draining an empty queue does nothing")
end

-- The order is preserved, a repeated key displaces the action rather than queueing second.
do
    local queue = UF.NewQueue()
    local log = {}

    UF.Enqueue(queue, "scale:PlayerFrame", function() log[#log + 1] = "player-1" end)
    UF.Enqueue(queue, "scale:TargetFrame", function() log[#log + 1] = "target" end)
    UF.Enqueue(queue, "scale:PlayerFrame", function() log[#log + 1] = "player-2" end)

    T.eq(UF.Pending(queue), 2, "a repeated key does not lengthen the queue")
    T.eq(UF.Drain(queue), 2, "both actions ran")
    T.eq(#log, 2, "and exactly twice")
    T.eq(log[1], "player-2", "the place in the queue is the former one, the action is the last one")
    T.eq(log[2], "target", "the order of the rest is not broken")
    T.eq(UF.Pending(queue), 0, "after leaving combat the queue is empty")
end

-- A failing action does not cut the rest short.
do
    local queue = UF.NewQueue()
    local ran = false
    UF.Enqueue(queue, "bad", function() error("on purpose") end)
    UF.Enqueue(queue, "good", function() ran = true end)
    T.eq(UF.Drain(queue), 1, "only one counts as successful")
    T.ok(ran, "the second action ran anyway")
end

-- An action may put a new entry into the queue: the queue is cleared before
-- the run, so a new entry survives the drain.
do
    local queue = UF.NewQueue()
    UF.Enqueue(queue, "first", function()
        UF.Enqueue(queue, "second", function() end)
    end)
    UF.Drain(queue)
    T.eq(UF.Pending(queue), 1, "an entry added during the drain was kept")
end

-- The queue does not accept garbage on its input.
do
    local queue = UF.NewQueue()
    T.eq(UF.Enqueue(queue, "key", "not a function"), false, "the action must be a function")
    T.eq(UF.Enqueue(queue, "", function() end), false, "an empty key is not accepted")
    T.eq(UF.Enqueue(nil, "key", function() end), false, "no queue -- nothing to fill")
    T.eq(UF.Pending(queue), 0, "none of that went into the queue")
    T.eq(UF.Pending("garbage"), 0, "garbage instead of a queue counts as empty")
    T.eq(UF.Drain("garbage"), 0, "and drains without error")
end

T.suite("unit frames: the bar texture")

--- A fake bar: the methods the subsystem uses.
local function newBar(r, g, b)
    local bar = { texture = "Native", color = { r, g, b, 1 }, sets = 0 }
    function bar:SetStatusBarTexture(path)
        self.texture = path
        self.sets = self.sets + 1
        -- Some builds reset the colour along with the texture. That is exactly
        -- why the subsystem reads the colour before the swap and restores it after.
        self.color = { 1, 1, 1, 1 }
    end
    function bar:GetStatusBarColor()
        return self.color[1], self.color[2], self.color[3], self.color[4]
    end
    function bar:SetStatusBarColor(cr, cg, cb, ca)
        self.color = { cr, cg, cb, ca }
    end
    -- The engine returns a texture object, and the path is taken out of it by
    -- GetTexture. The fake repeats exactly that shape: the subsystem remembers
    -- the native texture through it.
    function bar:GetStatusBarTexture()
        local owner = self
        return { GetTexture = function() return owner.texture end }
    end
    return bar
end

do
    local bar = newBar(0.2, 0.8, 0.3)
    T.ok(UF.SetBarTexture(bar, "Media\\mzk.tga"), "the texture was applied")
    T.eq(bar.texture, "Media\\mzk.tga", "the path went onto the bar")
    T.eq(bar.color[1], 0.2, "the bar colour was preserved (red)")
    T.eq(bar.color[2], 0.8, "the bar colour was preserved (green)")
    T.eq(bar.color[3], 0.3, "the bar colour was preserved (blue)")

    -- Applying the same texture again does nothing: the settings are re-read
    -- on every change of target.
    UF.SetBarTexture(bar, "Media\\mzk.tga")
    T.eq(bar.sets, 1, "the same texture is not assigned a second time")

    UF.SetBarTexture(bar, "Media\\mzk-blue.tga")
    T.eq(bar.sets, 2, "a different texture is assigned")
end

-- A bar has one texture object for its whole life: SetStatusBarTexture changes
-- the image rather than the object. Everything the game configured on it for
-- its own image goes to ours -- and spoils it. The fake remembers those
-- settings, and the property checked here is: after the file swap nothing foreign is left on the object.
do
    local leftovers = {
        coords = { 0.15, 0.85, 0, 0.25 },   -- the native bar came from an atlas
        horizTile = true, vertTile = true,  -- and was tiled
        snap = true, bias = 0.25,           -- and snapped to the pixel grid
    }
    function leftovers:GetTexture() return self.path end
    function leftovers:SetTexCoord(l, r, t, b) self.coords = { l, r, t, b } end
    function leftovers:SetHorizTile(v) self.horizTile = v end
    function leftovers:SetVertTile(v) self.vertTile = v end
    function leftovers:SetSnapToPixelGrid(v) self.snap = v end
    function leftovers:SetTexelSnappingBias(v) self.bias = v end

    local bar = { color = { 0.2, 0.8, 0.3, 1 } }
    leftovers.path = "Native"
    function bar:SetStatusBarTexture(path) leftovers.path = path end
    function bar:GetStatusBarTexture() return leftovers end
    function bar:GetStatusBarColor()
        return self.color[1], self.color[2], self.color[3], self.color[4]
    end
    function bar:SetStatusBarColor(cr, cg, cb, ca)
        self.color = { cr, cg, cb, ca }
    end

    T.ok(UF.SetBarTexture(bar, "Media\\mzk.tga"), "the author texture went on")

    -- The cropping is NOT touched, and that is a correction to an earlier change.
    --
    -- It was touched, and that broke the very thing being fixed. A bar is a
    -- StatusBar, and a StatusBar shows its fill fraction by cropping the
    -- coordinates of its own texture: half the health is half the image rather
    -- than half the width, which is why the gradient does not squash.
    -- Resetting the coordinates to "the whole file" means taking away the thing
    -- the engine shows health with, and the image lands as it pleases -- the author sent a screenshot.
    --
    -- The coordinates belong to the engine entirely: it sets them anew on every
    -- SetValue.
    T.eq(leftovers.coords[1], 0.15, "the crop coordinates are untouched")
    T.eq(leftovers.coords[2], 0.85, "the engine shows the health fraction with them")
    T.eq(leftovers.horizTile, false, "the horizontal tiling was cleared")
    T.eq(leftovers.vertTile, false, "the vertical tiling was cleared")
    T.eq(leftovers.snap, false, "the pixel grid snapping was cleared")
    T.eq(leftovers.bias, 0, "the snap bias was zeroed")

    -- A client where half these methods do not exist at all: a missing method
    -- is not an error but "that does not happen here".
    local bare = { color = { 1, 1, 1, 1 } }
    local plain = { GetTexture = function() return "Native" end }
    function bare:SetStatusBarTexture() end
    function bare:GetStatusBarTexture() return plain end
    function bare:GetStatusBarColor() return 1, 1, 1, 1 end
    function bare:SetStatusBarColor() end
    local okBare = pcall(UF.SetBarTexture, bare, "Media\\mzk.tga")
    T.ok(okBare, "a bar without these methods does not break the texture application")

    T.eq(UF.NormalizeBarTexture(nil), false, "no bar -- nothing to clear")
    T.eq(UF.NormalizeBarTexture({}), false, "an object with no methods is skipped")
end

local OURS = "Media\\mzk.tga"

-- The game repaints the target bar itself: on a change of target and on a
-- change of resource type it reassigns the file without asking us. The memory
-- that we have already applied our texture then lies -- and did lie: the
-- subsystem answered "ours is already on" and never restored it until the
-- player cycled the setting by hand. The property: the application looks at
-- the bar rather than into memory.
do
    local bar = newBar(0.2, 0.8, 0.3)
    UF.SetBarTexture(bar, OURS)
    T.eq(bar.sets, 1, "our texture went on")

    -- The game reassigned the file behind our back.
    bar.texture = "Native"

    UF.SetBarTexture(bar, OURS)
    T.eq(bar.texture, OURS, "our texture came back onto the bar")
    T.eq(bar.sets, 2, "and that cost exactly one assignment")

    -- And when nobody touched anything, applying again still does nothing: the
    -- bar check does not turn quiet into work.
    UF.SetBarTexture(bar, OURS)
    T.eq(bar.sets, 2, "an untouched bar is not repainted a second time")
end

-- A bar whose path cannot be read (the client returns an object with no
-- GetTexture, or the value arrived secret) is assigned anew. The unknown is
-- read in favour of work: an extra assignment costs one call, a missed one
-- looks like a breakage.
do
    local bar = {
        color = { 1, 1, 1, 1 }, sets = 0,
        GetStatusBarColor = function() return 1, 1, 1, 1 end,
        SetStatusBarColor = function() end,
    }
    bar.SetStatusBarTexture = function(self) self.sets = self.sets + 1 end
    bar.GetStatusBarTexture = function() return {} end

    UF.SetBarTexture(bar, OURS)
    UF.SetBarTexture(bar, OURS)
    T.eq(bar.sets, 2, "an unreadable bar is assigned anew")

    T.eq(UF.CurrentTexture(nil), nil, "no bar -- nothing to read")
    T.eq(UF.CurrentTexture({}), nil, "an object with no methods is skipped")
end

T.eq(UF.SetBarTexture(nil, "x"), false, "no bar -- nothing to paint")
T.eq(UF.SetBarTexture({}, "x"), false, "an object with no methods is skipped")
T.eq(UF.SetBarTexture(newBar(1, 1, 1), nil), false, "no path -- we do nothing")

T.suite("unit frames: the colour under an author texture")

-- The author's words:
--
-- > why is a mob's HP green by default, what nonsense is that
--
-- The green was not a choice. Under an author texture the colour must be given
-- by us: the gradient is drawn from white and carries no colour of its own,
-- and untinted it shows the texture INSTEAD of a colour. The colour for that
-- is asked of the game tables by the player class or the creature reaction.
--
-- About the target the client returns both the class and the reaction as
-- secret. They are no good as keys -- RAID_CLASS_COLORS[a secret string] is
-- nil -- and the tables answer "I do not know". The computation then fell back
-- to the remembered native colour, and that one is frozen: it is the colour
-- that stood on the bar the moment we first touched it. That is the colour of
-- the PREVIOUS target, and at login the default green.
--
-- The live answer was at hand all that time and went unused: the game paints
-- the bar itself, our handler is hooked onto its own functions and runs after
-- it, and at that moment the bar carries exactly what the game would show without us.
-- It is read back off the bar itself as ordinary numbers -- there are no
-- secret values on that path at all.
--
-- === Why the scenario is exactly this one ===
--
-- What must be checked is a change of target rather than one target. On an
-- untouched bar the defect is invisible: we did not paint it, and it stays the
-- way the game painted it -- correct. The defect starts with the SECOND
-- target: we painted the first, so we keep painting, and there is nothing to
-- paint with -- and the frozen value goes to work.

do
    --- A bar that remembers its colour and its texture, like the engine.
    local function newLiveBar(r, g, b)
        local bar = { color = { r, g, b, 1 }, file = "Native" }
        function bar:SetStatusBarTexture(path) self.file = path end
        function bar:GetStatusBarTexture()
            local owner = self
            return { GetTexture = function() return owner.file end }
        end
        function bar:GetStatusBarColor()
            return self.color[1], self.color[2], self.color[3], self.color[4]
        end
        function bar:SetStatusBarColor(cr, cg, cb, ca)
            self.color = { cr, cg, cb, ca or 1 }
        end
        return bar
    end

    local WARLOCK = { r = 0.58, g = 0.51, b = 0.79 }

    -- The target bar before the first target: the game keeps it green. That
    -- green is what gets remembered as native -- the way back if the player removes the texture.
    local bar = newLiveBar(0, 1, 0)
    UF.SetBarTexture(bar, "Interface\\AddOns\\Darken\\Media\\mzk.tga")
    T.eq(UF.Textured(bar), true, "the bar carries an author texture")

    -- The first target: a warlock. About a player the client answers openly,
    -- the class is known, and the bar is painted in the class colour.
    bar:SetStatusBarColor(0.58, 0.51, 0.79, 1)
    local known = { class = "WARLOCK", classColors = { WARLOCK = WARLOCK },
                    reactionColors = {} }
    UF.ApplyBarColor(bar, UF.NATIVE, known, 1, "health")
    T.ok(math.abs(bar.color[1] - 0.58) < 0.01, "a player target is painted by class")

    -- The second target: a hostile creature. The game painted the bar red while
    -- answering "I do not know" to the questions about class and reaction --
    -- that is what a secret value looks like after a probe.
    bar:SetStatusBarColor(0.79, 0.22, 0.22, 1)

    local blind = { class = nil, reaction = nil,
                    classColors = { WARLOCK = WARLOCK }, reactionColors = {} }
    T.eq(UF.GameColor("health", blind), nil,
        "the game tables stay silent about this creature: there is no key for them")

    UF.ApplyBarColor(bar, UF.NATIVE, blind, 1, "health")

    T.ok(math.abs(bar.color[1] - 0.79) < 0.01,
        "the bar stayed red, as the game painted it")
    T.ok(math.abs(bar.color[2] - 0.22) < 0.01, "and the green share is the same")
    T.ok(math.abs(bar.color[3] - 0.22) < 0.01, "and the blue one")

    -- Exactly what the author saw, as a separate check: neither the colour of
    -- the previous target nor the default green.
    T.ok(math.abs(bar.color[1] - 0.58) > 0.01,
        "and it is not the colour of the previous target")
    T.ok(bar.color[2] < 0.9, "and not the default green")

    -- Our own colour is not taken for the game colour: otherwise the second
    -- pass would remember ours as "the game colour", the third the same, and
    -- our choice would become the "native" one.
    local seenR = UF.SeenColor(bar)
    UF.ApplyBarColor(bar, UF.NATIVE, blind, 1, "health")
    T.eq(UF.SeenColor(bar), seenR, "our own colour is not taken for the game colour")

    -- And when the tables DO answer, they are the ones answering. The observed
    -- colour comes second rather than first: for our own frame and for a player
    -- in the party the class is read openly, and the class colour is truer than what the game managed to put there.
    UF.ApplyBarColor(bar, UF.NATIVE, known, 1, "health")
    T.ok(math.abs(bar.color[1] - 0.58) < 0.01,
        "the class is known -- the colour is the class one rather than the observed one")
    T.ok(math.abs(bar.color[3] - 0.79) < 0.01, "and the blue share is the class one")

    -- An untouched bar remembers nothing: the observation starts along with the
    -- painting rather than living on its own.
    T.eq(UF.SeenColor(newLiveBar(0, 1, 0)), nil,
        "an untouched bar remembers nothing")
    T.eq(UF.SeenColor(nil), nil, "and empty space has no colour")
end

T.suite("unit frames: applying the settings")

local FAKE_GLOBALS = { "PlayerFrame", "TargetFrame", "PetFrame",
    "InCombatLockdown", "RAID_CLASS_COLORS", "FACTION_BAR_COLORS",
    "UnitClass", "UnitReaction", "UnitIsPlayer" }
local savedGlobals = {}
for i = 1, #FAKE_GLOBALS do savedGlobals[i] = _G[FAKE_GLOBALS[i]] end

--- A fake font string for the name.
local function newLabel()
    local label = { color = { 1, 1, 1, 1 } }
    function label:SetTextColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
    function label:GetTextColor()
        return self.color[1], self.color[2], self.color[3], self.color[4]
    end
    return label
end

--- A fake unit frame.
local function newFrame(unit)
    local frame = {
        unit = unit,
        scale = 1,
        name = newLabel(),
        healthbar = newBar(0.2, 0.8, 0.3),
        manabar = newBar(0, 0, 1),
    }
    function frame:GetScale() return self.scale end
    function frame:SetScale(value) self.scale = value end
    return frame
end

local combat = false
InCombatLockdown = function() return combat end
RAID_CLASS_COLORS = CLASS_COLORS
FACTION_BAR_COLORS = REACTIONS
UnitIsPlayer = function(unit) return unit == "player" or unit == "target" end
UnitClass = function(unit)
    if unit == "player" then return "Mage", "MAGE" end
    return nil, nil
end
UnitReaction = function(_, unit)
    if unit == "pet" then return 5 end
    return 1
end

ns.flavor = "vanilla"

local function setupFrames()
    PlayerFrame = newFrame("player")
    TargetFrame = newFrame("target")
    PetFrame    = newFrame("pet")
end

local function withSettings(settings)
    ns.Addon = { db = { profile = { unitframes = settings } } }
    return settings
end

-- Out of combat everything is applied at once.
do
    combat = false
    setupFrames()
    withSettings({
        health = "Darken Purple",
        power  = "Darken Blue",
        nameColor = "class",
        nameFixed = { r = 0.9, g = 0.9, b = 0.9 },
        scale = 1.2,
    })
    UF:ApplySettings()

    T.eq(PlayerFrame.healthbar.texture, "Interface\\AddOns\\Darken\\Media\\mzk.tga", "the health texture was applied")
    T.eq(PlayerFrame.manabar.texture, "Interface\\AddOns\\Darken\\Media\\mzk-blue.tga", "the resource texture was applied")
    T.eq(PlayerFrame.healthbar.color[2], 0.8, "the bar colour stayed the other one's")
    T.eq(PlayerFrame.name.color[1], 0.41, "the player name is painted by class")
    T.eq(PetFrame.name.color[2], 1, "a pet has no class -- the colour is by reaction")
    T.eq(PlayerFrame.scale, 1.2, "the scale was applied immediately out of combat")
    T.eq(UF.Pending(UF.queue), 0, "out of combat the queue is not needed")
end

-- In combat only the scale is deferred. The textures and the name colour are
-- operations the engine does not protect, and delaying them would mean making the addon sluggish.
do
    setupFrames()
    UF.Drain(UF.queue)
    combat = true
    local settings = withSettings({
        health = "Darken Blue",
        power  = "Darken Purple",
        nameColor = "fixed",
        nameFixed = { r = 0.5, g = 0.5, b = 0.5 },
        scale = 1.5,
    })
    UF:ApplySettings()

    T.eq(PlayerFrame.healthbar.texture, "Interface\\AddOns\\Darken\\Media\\mzk-blue.tga",
        "in combat the texture is applied at once")
    T.eq(PlayerFrame.name.color[1], 0.5, "in combat the name colour is applied at once")
    T.eq(PlayerFrame.scale, 1, "in combat the scale is untouched")
    T.eq(UF.Pending(UF.queue), 3, "one deferred entry per frame")

    -- A repeated edit in combat does not lengthen the queue: the key is the same.
    settings.scale = 1.4
    UF:ApplySettings()
    T.eq(UF.Pending(UF.queue), 3, "a repeated edit does not pile up entries")

    combat = false
    T.eq(UF.Drain(UF.queue), 3, "leaving combat applies the deferred work")
    T.eq(PlayerFrame.scale, 1.4, "and applies the last value rather than the first")
    T.eq(TargetFrame.scale, 1.4, "on every frame")
end

-- A scale that is already set is not deferred: otherwise every change of
-- target in combat would pile up work that changes nothing.
do
    setupFrames()
    UF.Drain(UF.queue)
    combat = false
    withSettings({
        health = "Darken Purple", power = "Darken Blue",
        nameColor = "class", nameFixed = { r = 1, g = 1, b = 1 }, scale = 1,
    })
    UF:ApplySettings()
    combat = true
    UF:ApplySettings()
    T.eq(UF.Pending(UF.queue), 0, "a matching scale is not put into the queue")
end

-- A garbage scale from SavedVariables is clamped rather than breaking the frame.
do
    setupFrames()
    UF.Drain(UF.queue)
    combat = false
    withSettings({
        health = "Darken Purple", power = "Darken Blue",
        nameColor = "class", nameFixed = { r = 1, g = 1, b = 1 }, scale = 99,
    })
    UF:ApplySettings()
    T.eq(PlayerFrame.scale, 2, "the scale is clamped from above")

    withSettings({
        health = "Darken Purple", power = "Darken Blue",
        nameColor = "class", nameFixed = { r = 1, g = 1, b = 1 }, scale = "garbage",
    })
    UF:ApplySettings()
    T.eq(PlayerFrame.scale, 1, "garbage counts as one")
end

-- A frame the client does not have is simply invisible to the subsystem.
do
    setupFrames()
    UF.Drain(UF.queue)
    combat = false
    TargetFrame = nil
    withSettings({
        health = "Darken Purple", power = "Darken Blue",
        nameColor = "class", nameFixed = { r = 1, g = 1, b = 1 }, scale = 1.1,
    })
    UF:ApplySettings()
    T.eq(PlayerFrame.scale, 1.1, "an existing frame is configured")
    T.eq(PetFrame.scale, 1.1, "and so is the second one")
end

-- Without a profile the subsystem silently does nothing.
do
    setupFrames()
    ns.Addon = nil
    UF:ApplySettings()
    T.eq(PlayerFrame.healthbar.texture, "Native", "with no profile the bar is untouched")
end

T.suite("unit frames: the settings section")

do
    -- The page is laid out in tabs (childGroups = "tab"), and a setting lies
    -- inside its own: the bars on "Health and Power", the name on "Name and
    -- Bar Text", the scale on "Size". The structure of the tabs and the
    -- identity of the nodes are checked by tests/test_unitframetabs.lua; here
    -- the tabs are named only to reach those same tables.
    local args  = UF.options.args.frames.args.bars.args
    local named = UF.options.args.frames.args.text.args
    local sized = UF.options.args.frames.args.size.args
    T.eq(args.health.type, "select", "the health texture is a select")
    T.eq(args.power.type, "select", "the resource texture is a select")
    T.eq(named.nameColor.type, "select", "the name colour is a mode select")
    T.eq(named.nameFixed.type, "color", "the own colour is a colour picker")
    T.eq(sized.scale.type, "range", "the scale is a slider")

    local values = args.health.values()
    T.eq(values["Darken Purple"], "Darken Purple", "the author textures are in the list")
    T.ok(values[UF.NATIVE] ~= nil, "the native game texture is a row of the list")
    T.eq(args.health.sorting()[1], UF.NATIVE, "the native texture comes first")
    T.eq(args.power.sorting()[1], UF.NATIVE, "and first in the resource list too")

    -- The native-look marker must not coincide with a name from the library:
    -- otherwise choosing "native" would silently mean somebody else's texture.
    T.eq(ns.Skin.MediaTexture(fakeMedia, UF.NATIVE), nil,
        "the native texture marker is not a name from the library")

    local modes = named.nameColor.values()
    T.ok(modes.class ~= nil and modes.reaction ~= nil and modes.fixed ~= nil,
        "all three name colour modes are in place")
    T.ok(modes[UF.NATIVE] ~= nil, "the native name colour is a separate mode")
    T.eq(named.nameColor.sorting()[1], UF.NATIVE,
        "the native name colour comes first")

    -- The scale description must name the combat restriction: it is the only
    -- place the player learns why the slider sometimes "did not take effect at once".
    T.ok(sized.scale.desc:find("combat") ~= nil,
        "the scale description mentions combat")

    -- The defaults are the native look of the game. A fresh install replaces
    -- nothing: otherwise there is nothing to compare the first login with and
    -- no way to tell the addon's work from the game's. The author look is set by an action in the "General" section.
    T.eq(UF.defaults.health, UF.NATIVE, "the health bar default is the native one")
    T.eq(UF.defaults.power, UF.NATIVE, "the resource bar default is the native one")
    T.eq(UF.defaults.scale, 1, "the scale default is the native size")
    T.eq(UF.defaults.nameColor, UF.NATIVE, "the name colour default is the native one")
end

-- The handlers write into the profile and apply at once.
do
    combat = false
    setupFrames()
    UF.Drain(UF.queue)
    local settings = withSettings({
        health = "Darken Purple", power = "Darken Blue",
        nameColor = "class", nameFixed = { r = 1, g = 1, b = 1 }, scale = 1,
    })

    local bars = UF.options.args.frames.args.bars.args
    local text = UF.options.args.frames.args.text.args

    bars.health.set(nil, "Darken Blue")
    T.eq(settings.health, "Darken Blue", "the texture choice went into the profile")
    T.eq(PlayerFrame.healthbar.texture, "Interface\\AddOns\\Darken\\Media\\mzk-blue.tga", "and was applied at once")
    T.eq(bars.health.get(), "Darken Blue", "get returns what was chosen")

    text.nameFixed.set(nil, 0.1, 0.2, 0.3)
    T.eq(settings.nameFixed.r, 0.1, "the colour went into the profile")
    text.nameColor.set(nil, "fixed")
    T.eq(PlayerFrame.name.color[3], 0.3, "and was applied to the name")

    local r, g, b = text.nameFixed.get()
    T.eq(r, 0.1, "the colour get: red")
    T.eq(g, 0.2, "the colour get: green")
    T.eq(b, 0.3, "the colour get: blue")
end

T.suite("unit frames and darkness do not interfere with each other")

-- Both subsystems edit the look of the same frames. The check below holds the
-- boundary between them: the darkness walks a frame and its children and tints
-- only the trim, while it skips StatusBar objects entirely -- their colour
-- belongs to the unit frames and is not subject to darkening at all. A bar
-- fill shows a magnitude, and dimming it is the same as dimming the needle of a gauge.
-- So every colour has exactly one owner, and the order of application decides
-- nothing -- which is what both orders check.

helpers.loadAddonFile("Modules/Darkness.lua", ns)
local Darkness = ns.Darkness

--- A fake frame trim texture: what the darkness sees.
local function newRegion(r, g, b)
    local region = { color = { r, g, b, 1 } }
    function region:GetObjectType() return "Texture" end
    function region:GetVertexColor()
        return self.color[1], self.color[2], self.color[3], self.color[4]
    end
    function region:SetVertexColor(cr, cg, cb, ca)
        self.color = { cr, cg, cb, ca }
    end
    return region
end

--- A frame with trim, bars and a name: everything both subsystems reach.
--
local function newSharedFrame()
    local frame = newFrame("player")
    frame.border = newRegion(1, 1, 1)
    -- The name font string is a region of the frame too but not a texture: the
    -- darkness must skip it, otherwise the name colour would have two owners.
    frame.name.GetObjectType = function() return "FontString" end
    function frame:GetRegions() return self.border, self.name end
    return frame
end

do
    combat = false
    local settings = {
        health = "Darken Purple", power = "Darken Blue",
        nameColor = "fixed", nameFixed = { r = 0.4, g = 0.5, b = 0.6 },
        scale = 1,
    }
    local darkness = { amount = 50, exclude = {} }

    -- The first order: the darkness first, then the unit frames.
    setupFrames()
    PlayerFrame = newSharedFrame()
    TargetFrame = nil
    PetFrame = nil
    ns.Addon = { db = { profile = { unitframes = settings, darkness = darkness } } }

    -- White trim arrives at the brightness ceiling, see helpers.whiteAt.
    local dim = helpers.whiteAt(Darkness.Factor(50))

    Darkness:ApplySettings()
    UF:ApplySettings()
    T.eq(PlayerFrame.border.color[1], dim, "the trim darkening holds")
    T.eq(PlayerFrame.healthbar.texture, "Interface\\AddOns\\Darken\\Media\\mzk.tga", "the bar texture is in place")
    -- The bar is darkened by neither subsystem: its native colour (0.8) stays
    -- as it was. That is by design -- the darkening is about the trim.
    T.eq(PlayerFrame.healthbar.color[2], 0.8, "the bar colour is not subject to darkening")
    T.eq(PlayerFrame.name.color[1], 0.4, "the name colour is ours rather than darkened")

    -- The second order: the unit frames first, then the darkness. The result
    -- must be the same.
    PlayerFrame = newSharedFrame()
    UF:ApplySettings()
    Darkness:ApplySettings()
    T.eq(PlayerFrame.border.color[1], dim, "the reverse order: the same darkening")
    T.eq(PlayerFrame.healthbar.texture, "Interface\\AddOns\\Darken\\Media\\mzk.tga", "the reverse order: the same texture")
    T.eq(PlayerFrame.healthbar.color[2], 0.8, "the reverse order: the same colour")
    T.eq(PlayerFrame.name.color[1], 0.4, "the reverse order: the name colour is intact")

    -- Repainting the unit frames does not upset the darkening: applying the bar
    -- settings again leaves the trim just as dark.
    UF:ApplySettings()
    T.eq(PlayerFrame.border.color[1], dim,
        "repeating the bar settings does not lighten the trim")

    -- And conversely: returning the darkness slider to zero restores the trim
    -- and touches neither the bar nor the name.
    darkness.amount = 0
    Darkness:ApplySettings()
    T.eq(PlayerFrame.border.color[1], 1, "zero on the slider restored the trim")
    T.eq(PlayerFrame.healthbar.color[2], 0.8, "the bar is as it was with its own colour")
    T.eq(PlayerFrame.healthbar.texture, "Interface\\AddOns\\Darken\\Media\\mzk.tga", "the bar texture is untouched")
    T.eq(PlayerFrame.name.color[1], 0.4, "the name is untouched by the darkness")

    -- The proof of the field separation: the subsystems write onto different
    -- objects and under different names. The bar colour is changed by one owner
    -- only -- the unit frames -- and a darkness field never appears on a bar.
    T.ok(ns.Darkness.Remembered(PlayerFrame.border) ~= nil,
        "the darkness remembers the trim colour")
    T.eq(ns.Darkness.Remembered(PlayerFrame.healthbar), nil,
        "the darkness did not touch the bar")
    local _, remembered = UF.Remembered(PlayerFrame.healthbar)
    T.ok(remembered ~= nil, "the unit frames remember the native bar colour")
    T.eq(ns.Darkness.Remembered(PlayerFrame.name), nil,
        "the darkness did not touch the font string")
    T.eq((UF.Remembered(PlayerFrame.healthbar)), "Interface\\AddOns\\Darken\\Media\\mzk.tga",
        "the unit frames remember the assigned texture")
    T.eq((UF.Remembered(PlayerFrame.border)), nil,
        "the unit frames did not touch the trim")
end

T.suite("unit frames: which texture is applied")

-- The decision "what ends up on the bar" is a pure function, and it is checked
-- here in full: in the client telling "the native one came back" from "ours
-- stayed" by eye is hard while getting it wrong is easy.

T.eq(UF.ResolveTexture(UF.NATIVE, fakeMedia, "Native"), "Native",
    "the native one is chosen -- the remembered native one is returned")
-- Our nine resolve as files inside the addon rather than as a registry entry:
-- the path here is ours, although the fake library answers the same name with its own.
T.eq(UF.ResolveTexture("Darken Blue", fakeMedia, "Native"),
    "Interface\\AddOns\\Darken\\Media\\mzk-blue.tga",
    "a known name gives an addon file rather than the registry answer")
T.eq(UF.ResolveTexture("Invention", fakeMedia, "Native"), "Native",
    "an unknown name gives the native one rather than a foreign default texture")
T.eq(UF.ResolveTexture(UF.NATIVE, fakeMedia, nil), nil,
    "the native one is not remembered -- there is nothing to change")
T.eq(UF.ResolveTexture(nil, fakeMedia, "Native"), "Native",
    "garbage in the setting gives the native one")
-- Here is where one answer differed from two. Formerly a texture name was
-- resolved by two different rules: the contract handed ns.Media.BarPath (our
-- nine as files, then the registry) to a module, while the core subsystems
-- called ns.Skin.MediaTexture (the registry only). In an installation without
-- LibSharedMedia an author texture chosen by the player would appear on the
-- engine nameplates and would not appear here: the bar would show the native
-- game texture without reporting anything. There is now one rule and one answer.
T.eq(UF.ResolveTexture("Darken Blue", nil, "Native"),
    "Interface\\AddOns\\Darken\\Media\\mzk-blue.tga",
    "without the library our texture is found anyway: it lies as a file inside the addon")
T.eq(UF.ResolveTexture("Foreign from the registry", nil, "Native"), "Native",
    "while a foreign name without the library has nobody to ask -- the native one")

T.suite("unit frames: the return to the native texture")

do
    local bar = newBar(0.2, 0.8, 0.3)

    -- The native look is not touched at all: not a single SetStatusBarTexture.
    T.eq(UF.ApplyBar(bar, UF.NATIVE, fakeMedia), false,
        "an untouched bar is not touched under the native setting")
    T.eq(bar.sets, 0, "the texture was never assigned")

    UF.ApplyBar(bar, "Darken Purple", fakeMedia)
    T.eq(bar.texture, "Interface\\AddOns\\Darken\\Media\\mzk.tga", "the author texture went on")

    UF.ApplyBar(bar, UF.NATIVE, fakeMedia)
    T.eq(bar.texture, "Native", "the return to the native one restored the native one")

    -- Switching back and forth any number of times: the remembered native one
    -- is written once and is not overwritten by our own texture.
    for _ = 1, 5 do
        UF.ApplyBar(bar, "Darken Blue", fakeMedia)
        UF.ApplyBar(bar, UF.NATIVE, fakeMedia)
    end
    T.eq(bar.texture, "Native", "five switches restore the same native one")
    T.eq(bar.color[1], 0.2, "the bar colour survives the switches")
end

-- A bar whose native texture cannot be read stays untouched: substituting
-- something of ours for an unknown native one would be worse.
do
    local bar = newBar(1, 1, 1)
    bar.GetStatusBarTexture = nil
    T.eq(UF.ApplyBar(bar, UF.NATIVE, fakeMedia), false, "there is nothing to restore")
    T.eq(bar.texture, "Native", "the bar is untouched")
end

T.suite("unit frames: the return to the native name colour")

do
    combat = false
    setupFrames()
    local settings = withSettings({
        health = UF.NATIVE, power = UF.NATIVE,
        nameColor = UF.NATIVE, nameFixed = { r = 0.1, g = 0.2, b = 0.3 },
        scale = 1,
    })

    -- The colour the game paints the name with itself.
    PlayerFrame.name.color = { 0.7, 0.6, 0.5, 1 }

    UF:ApplySettings()
    T.eq(PlayerFrame.name.color[1], 0.7, "a fresh profile does not repaint the name")
    T.eq(PlayerFrame.healthbar.sets, 0, "and does not swap the bar texture")

    settings.nameColor = "class"
    UF:ApplySettings()
    T.eq(PlayerFrame.name.color[1], 0.41, "by class -- the class colour")

    settings.nameColor = UF.NATIVE
    UF:ApplySettings()
    T.eq(PlayerFrame.name.color[1], 0.7, "the return to the native one restored the native colour")

    for _ = 1, 5 do
        settings.nameColor = "fixed"
        UF:ApplySettings()
        settings.nameColor = UF.NATIVE
        UF:ApplySettings()
    end
    T.eq(PlayerFrame.name.color[1], 0.7,
        "five switches do not shift the native colour")
end

T.suite("unit frames: the migration and the author set")

-- The native-look marker is written in the migration as a literal string (a
-- migration is a record of history and must not be rewritten). The check holds
-- them together: diverging, they would leave old profiles with the native look unasked.
helpers.loadAddonFile("Core/Defaults.lua", ns)

do
    local legacy = { version = 1, unitframes = {
        health = UF.NATIVE, power = UF.NATIVE, nameColor = UF.NATIVE,
    } }
    ns.MigrateProfile(legacy, ns.Migrations, ns.DB_VERSION)
    T.eq(legacy.unitframes.health, "Darken Purple",
        "the migration recognises today's native texture marker")
    T.eq(legacy.unitframes.nameColor, "class",
        "and today's native name colour marker")
end

-- The author set names textures the library knows.
do
    local ok = fakeMedia:IsValid("statusbar", ns.Recommended.unitframes.health)
    T.ok(ok, "the recommended health texture exists")
    T.ok(fakeMedia:IsValid("statusbar", ns.Recommended.unitframes.power),
        "the recommended resource texture exists")
end

-- Restore the globals: the next file of the suite must not see the stubs.
for i = 1, #FAKE_GLOBALS do _G[FAKE_GLOBALS[i]] = savedGlobals[i] end
LibStub = savedLibStub

T.suite("unit frames: a tapped mob is grey in any mode")

-- This is not our colour but the game's answer to "is this your kill": a mob
-- somebody else hit is painted grey by the game, and the player decides by
-- that grey whether to attack or move on. Painting it by reaction, we took the
-- answer away and gave nothing in return -- the author wrote "its hp does not
-- change to grey as it should".
do
    local r0, g0, b0 = ns.Skin.TapColor()

    local info = {
        class = "PRIEST",
        classColors = { PRIEST = { r = 1, g = 1, b = 1 } },
        reaction = 2,
        reactionColors = { [2] = { r = 1, g = 0, b = 0 } },
        fixed = { r = 0, g = 1, b = 0 },
        tapDenied = true,
    }

    -- The mode does not argue with the game's answer: "by class" does not
    -- concern a mob at all, while "by reaction" and "own colour" answer WHO is
    -- in front of you, whereas the grey answers WHOSE it is.
    for _, mode in ipairs({ "class", "reaction", "fixed" }) do
        local r, g, b = UF.NameColor(mode, info)
        T.eq(r, r0, mode .. ": grey in the red channel")
        T.eq(g, g0, mode .. ": and in the green one")
        T.eq(b, b0, mode .. ": and in the blue one")
    end

    -- Our own kill is painted as before.
    info.tapDenied = false
    local r = UF.NameColor("reaction", info)
    T.eq(r, 1, "our own kill is painted by reaction")
end
