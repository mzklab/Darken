local helpers = require("helpers")

-- The physics of the floating combat text.
--
-- The subject of the check is one pure function and its consequences. The
-- slider's value turns into the value of an engine console variable, and the
-- whole meaning of the setting rests on three of its answers: a zero means "as
-- in the game", rubbish out of SavedVariables means the same, and a value that
-- was set but went outside the sensible bounds is clamped to the bound rather than lost.
--
-- The second subject is reversibility. "As in the game" is obliged to restore
-- the engine's own default rather than silently leaving the variable with our
-- previous value: otherwise the slider's label lies, and the defect "a switch
-- that switches nothing off" repeats itself.
--
-- The file is separate from test_fonts.lua deliberately: an instance of the
-- module of its own and never touched is needed here — the remembered font of
-- the world labels is read once per load of the file.

local savedLibStub = LibStub

local fakeMedia = {
    List    = function(_, kind)
        if kind == "font" then return { "Font A" } end
        return {}
    end,
    IsValid = function(_, kind, name)
        return kind == "font" and name == "Font A"
    end,
    Fetch   = function(_, kind, name)
        if kind == "font" and name == "Font A" then return "Fonts\\A.ttf" end
        return nil
    end,
}

LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return fakeMedia end
    return nil
end

-- The world labels' native font has to lie in the client before the first
-- application: the subsystem remembers it at the first touch.
local savedDamageFont = _G.DAMAGE_TEXT_FONT
_G.DAMAGE_TEXT_FONT = "Fonts\\World.ttf"

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Fonts.lua", ns)

local Fonts = ns.Fonts
local INHERIT = Fonts.INHERIT

T.suite("the combat text: a slider's value into a variable's value")

-- A zero is "as in the game" rather than a zero of gravity. Without that
-- answer a fresh profile would change the game's behaviour, which the addon never does.
T.eq(Fonts.PhysicsValue("gravity", 0), nil, "a zero gravity is \"as in the game\"")
T.eq(Fonts.PhysicsValue("duration", 0), nil, "a zero duration is \"as in the game\"")

-- A value that was set is returned as a string: SetCVar expects a string, and
-- the conversion belongs here rather than by eye at the call site.
T.eq(Fonts.PhysicsValue("gravity", 0.5), "0.50", "the game's native value is expressible")
T.eq(Fonts.PhysicsValue("gravity", 2), "2.00", "an integer gravity")
T.eq(Fonts.PhysicsValue("duration", 1), "1.00", "the native duration is expressible")
T.eq(Fonts.PhysicsValue("duration", 2.5), "2.50", "a fractional duration")

-- The sensible bounds. A value beyond them is clamped to the bound: the
-- player's instruction is not lost over one extra unit.
T.eq(Fonts.PhysicsValue("gravity", 0.2), "0.50", "too weak a gravity is clamped from below")
T.eq(Fonts.PhysicsValue("gravity", 99), "10.00", "too strong a one is clamped from above")
T.eq(Fonts.PhysicsValue("duration", 0.05), "0.10", "too short a duration is clamped from below")
T.eq(Fonts.PhysicsValue("duration", 100), "3.00", "too long a one is clamped from above")

-- Anything at all gets into a profile over the years, and all of it reads as
-- "not set" rather than bringing the subsystem down.
T.eq(Fonts.PhysicsValue("gravity", -5), nil, "a negative is \"as in the game\"")
T.eq(Fonts.PhysicsValue("gravity", "rubbish"), nil, "a string that is not a number is \"as in the game\"")
T.eq(Fonts.PhysicsValue("gravity", nil), nil, "an empty value is \"as in the game\"")
T.eq(Fonts.PhysicsValue("gravity", {}), nil, "a table instead of a number is \"as in the game\"")
T.eq(Fonts.PhysicsValue("duration", "1.5"), "1.50", "a number as a string is read all the same")

-- An unfamiliar key gives an ordinary nil rather than an error: that way the
-- function also answers the question "is there such a physics setting".
T.eq(Fonts.PhysicsValue("speed", 1), nil, "an unfamiliar physics key")
T.eq(Fonts.PhysicsValue(nil, 1), nil, "no key at all")

T.suite("the combat text: the write into the console variables")

--- A stand-in client with a set of console variables.
-- The defaults and the current values are separated the same way as in the
-- game: GetCVarDefault answers with what the engine considers its own.
local function newClient(present)
    local client = { current = {}, defaults = {}, writes = 0 }
    for name, value in pairs(present) do
        client.current[name] = value
        client.defaults[name] = value
    end
    client.api = {
        Get     = function(name) return client.current[name] end,
        Set     = function(name, value)
            client.current[name] = value
            client.writes = client.writes + 1
        end,
        Default = function(name) return client.defaults[name] end,
    }
    return client
end

-- A client with no _v2 variable: it is not everywhere, and its absence is an
-- ordinary matter rather than an error.
local function newOldClient()
    return newClient({
        WorldTextGravity      = "0.5",
        WorldTextRampDuration = "1.0",
    })
end

-- A fresh profile touches not one variable: there is nothing set in it, and
-- the default stands anyway.
do
    local client = newOldClient()
    local written = Fonts.ApplyPhysics({ gravity = 0, duration = 0 }, client.api)
    T.eq(written, 0, "the defaults write nothing")
    T.eq(client.writes, 0, "and not one write went into the client")
    T.eq(client.current.WorldTextGravity, "0.5", "the gravity stayed the game's")
end

-- A value that was set reaches the variable.
do
    local client = newOldClient()
    Fonts.ApplyPhysics({ gravity = 3, duration = 2 }, client.api)
    T.eq(client.current.WorldTextGravity, "3.00", "the gravity was written")
    T.eq(client.current.WorldTextRampDuration, "2.00", "the duration was written")
end

-- A return to "as in the game" restores the engine's default rather than leaving ours.
do
    local client = newOldClient()
    Fonts.ApplyPhysics({ gravity = 3, duration = 2 }, client.api)
    Fonts.ApplyPhysics({ gravity = 0, duration = 0 }, client.api)
    T.eq(client.current.WorldTextGravity, "0.5", "the gravity came back to the game's")
    T.eq(client.current.WorldTextRampDuration, "1.0", "and so did the duration")
end

-- A later client: the variant with the _v2 suffix gets the same value.
do
    local client = newClient({
        WorldTextGravity         = "0.5",
        WorldTextGravity_v2      = "0.5",
        WorldTextRampDuration    = "1.0",
        WorldTextRampDuration_v2 = "1.0",
    })
    Fonts.ApplyPhysics({ gravity = 4, duration = 1.5 }, client.api)
    T.eq(client.current.WorldTextGravity_v2, "4.00", "the _v2 gravity was written")
    T.eq(client.current.WorldTextRampDuration_v2, "1.50", "the _v2 duration was written")
end

-- A client with no console variables at all the subsystem silently does not touch.
do
    local client = newClient({})
    T.eq(Fonts.ApplyPhysics({ gravity = 3 }, client.api), 0,
        "there are no variables, so there is nowhere to write")
end

-- With no functions of the client's the subsystem does nothing and does not fall over.
T.eq(Fonts.ApplyPhysics({ gravity = 3 }, { Get = 1, Set = 2 }), 0,
    "foreign stand-in functions were not accepted")

T.suite("the combat text: the world labels' font")

-- The font is put into an engine variable, where it is read from at the entry into the world.
do
    _G.DAMAGE_TEXT_FONT = "Fonts\\World.ttf"
    T.eq(Fonts.WorldTextFont("Fonts\\A.ttf"), true, "the font was assigned")
    T.eq(_G.DAMAGE_TEXT_FONT, "Fonts\\A.ttf", "and went into the engine's variable")

    -- The native value was remembered at the first touch, and the restoration
    -- restores exactly it rather than our previous choice.
    Fonts.WorldTextFont(nil)
    T.eq(_G.DAMAGE_TEXT_FONT, "Fonts\\World.ttf", "the native font came back")

    -- A repeated assignment of the same value does not write into the variable
    --
    -- A SECOND TIME. That is not thrift. A write into a global variable of the
    -- GAME's taints it: any code of the game's that reads it afterwards runs
    -- tainted. That variable is read by the three-dimensional combat text —
    -- the one that appears when the player casts — and it used to be written
    -- here at every application of the settings: at the entry into the world,
    -- at a change of profile, at every movement of a slider, at every re-layout of the bars.
    --
    -- And all for nothing: the engine reads it once, at the entry into the
    -- world, and a second write in the same session changes nothing at all.
    --
    -- That is checked by replacing the variable itself with a table that
    -- counts the writes into it: there is no other way to tell "the same thing
    -- was written" from "nothing was written" — the value is identical in both cases.
    local writes = 0
    local store = { value = "Fonts\\World.ttf" }
    local proxy = setmetatable({}, {
        __index = function(_, key)
            if key == "DAMAGE_TEXT_FONT" then return store.value end
            return rawget(_G, key)
        end,
        __newindex = function(_, key, value)
            if key == "DAMAGE_TEXT_FONT" then
                writes = writes + 1
                store.value = value
                return
            end
            rawset(_G, key, value)
        end,
    })

    local savedEnv = getfenv(Fonts.WorldTextFont)
    setfenv(Fonts.WorldTextFont, setmetatable({ _G = proxy }, { __index = _G }))

    Fonts.WorldTextFont("Fonts\\B.ttf")
    T.eq(writes, 1, "the new font was written")

    Fonts.WorldTextFont("Fonts\\B.ttf")
    T.eq(writes, 1, "the same font is not written a second time")

    Fonts.WorldTextFont("Fonts\\C.ttf")
    T.eq(writes, 2, "while a different one is")

    setfenv(Fonts.WorldTextFont, savedEnv)
end

T.suite("the combat text: applying the settings")

local FAKE_GLOBALS = { "CombatTextFont" }
local savedGlobals = {}
for i = 1, #FAKE_GLOBALS do savedGlobals[i] = _G[FAKE_GLOBALS[i]] end

local function newFont(path, size, flags)
    local object = { current = { path, size, flags } }
    function object:GetFont()
        return self.current[1], self.current[2], self.current[3]
    end
    function object:SetFont(p, s, f) self.current = { p, s, f } end
    return object
end

ns.flavor = "vanilla"

do
    CombatTextFont = newFont("Fonts\\Native.ttf", 12, "")
    ns.Addon = { db = { profile = { fonts = {
        skipGlobal = false,
        global = { font = INHERIT, adjust = 0, outline = INHERIT },
        categories = {
            combattext = {
                font = "Font A", size = 20, outline = INHERIT,
                gravity = 3, duration = 2,
            },
        },
    } } } }

    -- Outside the game there are no console functions at all: the application
    -- is obliged to run to the end and not bring the subsystem down.
    Fonts:ApplySettings()
    T.eq(CombatTextFont.current[1], "Fonts\\A.ttf", "the font object got the font")
    T.eq(CombatTextFont.current[2], 20, "and the size")
    T.eq(_G.DAMAGE_TEXT_FONT, "Fonts\\A.ttf", "the world labels got the same font")
end

T.suite("the combat text: the settings section")

do
    local options = Fonts.BuildOptions()
    local combat = options.args.combattext.args
    local physics = combat.physics.args

    -- The task's main requirement: the full logout is spoken of in the font's
    -- description, and spoken of exactly where the player reads it.
    T.ok(combat.font.desc:find("logout") ~= nil,
        "the combat text font's description speaks of a full logout")
    T.ok(combat.font.desc:find("reload is not enough") ~= nil,
        "and plainly denies an interface reload")

    -- The other categories do not carry that note: for them it would be a lie.
    T.eq(options.args.unitname.args.font.desc:find("logout"), nil,
        "the unit names give no warning about a logout")

    T.eq(physics.gravity.type, "range", "the gravity is a slider")
    T.eq(physics.duration.type, "range", "the duration is a slider")
    T.eq(physics.gravity.min, 0, "a zero gravity is available as \"as in the game\"")
    T.eq(physics.duration.min, 0, "and so is a zero duration")

    -- The game's native values are reachable by the slider: otherwise coming
    -- back to them would be possible only by cleaning the profile.
    T.eq(physics.gravity.step, 0.5, "the gravity's step lands on the native 0.5")
    T.eq(physics.duration.step, 0.1, "the duration's step lands on the native 1.0")

    T.eq(type(physics.gravity.arg.zeroLabel), "string", "the zero gravity has a label")
    T.ok(physics.gravity.arg.zeroLabel ~= "", "and it is not empty")
    T.eq(type(physics.duration.arg.zeroLabel), "string", "the zero duration has a label")

    -- There is no physics slider where there is nothing to fall.
    T.eq(options.args.unitname.args.physics, nil, "the unit names have no physics")

    -- The handlers write into the profile and apply at once.
    local settings = {
        skipGlobal = false,
        global = { font = INHERIT, adjust = 0, outline = INHERIT },
        categories = { combattext = { font = INHERIT, size = 0,
            outline = INHERIT, gravity = 0, duration = 0 } },
    }
    ns.Addon = { db = { profile = { fonts = settings } } }
    physics.gravity.set(nil, 4)
    T.eq(settings.categories.combattext.gravity, 4, "the gravity went into the profile")
    T.eq(physics.gravity.get(), 4, "get returns what was chosen")
end

T.suite("the combat text: the defaults")

do
    local combat = Fonts.defaults.categories.combattext
    T.eq(combat.gravity, 0, "a fresh profile sets no gravity")
    T.eq(combat.duration, 0, "nor a duration")
    T.eq(Fonts.defaults.categories.unitname.gravity, nil,
        "a different category did not get the physics")
end

ns.Addon = nil
for i = 1, #FAKE_GLOBALS do _G[FAKE_GLOBALS[i]] = savedGlobals[i] end
_G.DAMAGE_TEXT_FONT = savedDamageFont
LibStub = savedLibStub
