local helpers = require("helpers")

-- A value you are not allowed to compute with.
--
-- The client hands out some properties of protected and restricted objects
-- in such a way that the value can be taken but an addon may not multiply
-- it: the engine aborts execution. The former darkness pass fell over on
-- exactly that -- in the client, at the author's, on a window nobody had
-- listed -- and disabled itself along with its settings page.
--
-- Here it is reproduced outside the game. An exact fake is impossible: a
-- real secret number has type "number", and plain Lua has no value with a
-- number type and a failing multiplication. So what is faked is not the
-- type but the behaviour -- the one property everything rested on: the value
-- is passed around freely, and the very first arithmetic on it fails.
-- That is exactly why the fitness check in ns.Skin.Numeric asks about
-- multiplication rather than about the type: a type check would miss the real case.
--
-- What is checked here is not "we handle secret numbers" but three rules:
--   1. The error does not reach the player at any slider position.
--   2. The refusal is not silent: it lands in the counter.
--   3. One uncomputable object does not cancel the darkening of the rest.

T.suite("darkness: an uncomputable value")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)

local Darkness = ns.Darkness
local Skin = ns.Skin

local function close(actual, expected)
    return type(actual) == "number" and math.abs(actual - expected) < 1e-9
end

-- A value that can be passed anywhere and fails on arithmetic.
local secret = setmetatable({}, {
    __mul = function() error("secret number value", 0) end,
    __add = function() error("secret number value", 0) end,
})

T.suite("Skin.Numeric: whether a value is fit for arithmetic")

T.eq(Skin.Numeric(0.5), 0.5, "an ordinary number passes as itself")
T.eq(Skin.Numeric(0), 0, "zero is as much a number as the rest")
T.eq(Skin.Numeric(secret), nil, "an uncomputable value is rejected")
T.eq(Skin.Numeric(nil), nil, "nil does not count as a number")
T.eq(Skin.Numeric(true), nil, "nor does a boolean")
T.eq(Skin.Numeric("0.5"), nil,
    "a string is rejected even though Lua can multiply it")

-- The main thing: the check itself does not fail. That is what it was written for.
T.ok(pcall(Skin.Numeric, secret), "the check does not break its caller")

--============================================================================
-- Strings: the same thing, only it is not multiplication that fails
--============================================================================

-- The second kind of secret value, and it was found just as expensively:
-- the common darkness pass fell over on "attempt to compare local 'value'
-- (a secret string value)" -- comparing a texture name with an empty string.
-- A secret string has an ordinary type too, so a type check would miss it.
--
-- It cannot be faked in plain Lua for the same reason as the number: there
-- is no value with a string type and a failing comparison. So the dangerous
-- operation is faked -- the string search -- rather than the value: exactly
-- the library function the check calls.
T.suite("Skin.Textual: whether a string is fit to work with")

T.eq(Skin.Textual("Texture"), "Texture", "an ordinary string passes as itself")
T.eq(Skin.Textual(""), nil, "an empty string does not count as a name")
T.eq(Skin.Textual(nil), nil, "nil does not count as a string")
T.eq(Skin.Textual(5), nil, "nor does a number, even though Lua can search it")
T.eq(Skin.Textual(true), nil, "nor a boolean")

do
    local SECRET = "a secret string"
    local realFind = string.find

    string.find = function(haystack, ...)
        if haystack == SECRET then
            error("a secret string value, while execution tainted", 0)
        end
        return realFind(haystack, ...)
    end

    local ok, answer = pcall(Skin.Textual, SECRET)

    string.find = realFind

    T.ok(ok, "the check does not break its caller")
    T.eq(answer, nil, "a string that cannot be searched is rejected")
    T.eq(Skin.Textual(SECRET), SECRET,
        "while the same string without the ban passes: what is rejected is not the value "
            .. "but the impossibility of working with it")
end

--============================================================================
-- Booleans: the same thing, only it is the comparison with nil and false that fails
--============================================================================

-- The third kind of secret value, and the quietest of the three. A secret
-- number fails arithmetic at once and loudly; a secret "yes" can be bypassed
-- by accident -- Lua tests truth in "and" and "if" without comparing -- and
-- then the answer is not false but random: a unit the game stays silent
-- about counts as the player, and a class colour gets looked up for a boar.
--
-- What is faked here is the same as for its neighbours: not the value but
-- the failing operation. A comparison cannot be faked, so the dangerous
-- operation is moved into a table with an __eq metamethod -- it fires when
-- two tables are compared, and fails the comparison the way the client does.
T.suite("Skin.Truth: whether a yes/no answer is fit to use")

T.eq(Skin.Truth(true), true, "an ordinary true passes")
T.eq(Skin.Truth(false), false, "and an ordinary false")
T.eq(Skin.Truth(nil), false, "the absence of an answer is a \"no\"")
T.eq(Skin.Truth(1), true, "a non-empty value is a \"yes\", as in the game itself")

do
    local angry = setmetatable({}, {
        __eq = function() error("a secret boolean value", 0) end,
    })

    -- The metamethod does not affect comparison with nil or false (different
    -- types are compared), so the failure is faked by breaking the check call
    -- from inside: the secrecy question itself is substituted.
    local realGet = _G.issecretvalue
    _G.issecretvalue = function(value)
        if value == angry then return true end
        return false
    end

    local ok, answer = pcall(Skin.Truth, angry)

    _G.issecretvalue = realGet

    T.ok(ok, "the check does not break its caller")
    T.eq(answer, false,
        "a secret answer counts as \"no\" rather than \"maybe\": "
            .. "a setting that works sometimes is worse than one switched off")
end

T.suite("Skin.Shade: an uncomputable colour is a refusal, not an error")

-- Shade is called not only from the darkness, and some callers pass in a
-- colour read from the game. A failure here would break any of them.
T.ok(pcall(Skin.Shade, secret, 0.5, 0.5, 0.5),
    "an uncomputable channel does not break Shade")
T.eq(Skin.Shade(secret, 0.5, 0.5, 0.5), nil, "it returns nil instead")
T.eq(Skin.Shade(0.5, secret, 0.5, 0.5), nil, "any of the three channels")
T.eq(Skin.Shade(0.5, 0.5, secret, 0.5), nil, "the third one too")
T.eq(Skin.Shade(0.5, 0.5, 0.5, secret), nil, "an uncomputable factor is a refusal as well")
T.ok(close(select(1, Skin.Shade(0.5, 0.5, 0.5, 0.5)), 0.25),
    "an ordinary colour is computed as before")

T.suite("darkness: a texture with an uncomputable colour")

--- A fake trim texture. The colour is handed back as it was given.
local function newTexture(colour)
    local texture = {
        r = colour, g = colour, b = colour, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function()
            return "Interface\\DialogFrame\\UI-DialogBox-Border"
        end,
    }
    function texture:GetVertexColor() return self.r, self.g, self.b, self.a end
    function texture:SetVertexColor(cr, cg, cb, ca)
        self.r, self.g, self.b = cr, cg, cb
        if ca ~= nil then self.a = ca end
    end
    return texture
end

do
    local blind = newTexture(secret)
    -- The refusal counter lives in the shared tally table (Core/Tally.lua):
    -- a second body of it in the subsystem would silently drift from the
    -- report, and the report is the only place the author will read this number from.
    local counters = ns.Counters
    local before = counters.blocked_darkness

    local ok, applied = pcall(Darkness.Tint, blind, 0.5)
    T.ok(ok, "darkening an uncomputable texture does not break the caller")
    T.eq(applied, false, "and it honestly reports that nothing was applied")

    T.eq(blind.r, secret, "the colour stayed the one the game put there")
    T.eq(Darkness.Remembered(blind), nil,
        "and no remembered colour appeared on the texture")

    T.eq(counters.blocked_darkness, before + 1,
        "the refusal is counted: there is no silent inaction here")

    -- The second pass tries again: uncomputability is a property of the
    -- execution state, not of the texture, and crossing a window off forever would be worse.
    Darkness.Tint(blind, 0.5)
    T.eq(counters.blocked_darkness, before + 2, "and it is counted again on the next pass")
end

T.suite("darkness: the neighbour of an uncomputable texture darkens as usual")

--- A fake frame.
local function newFrame(kind, name, regions, children)
    local frame = {
        GetObjectType = function() return kind end,
        GetRegions = function() return unpack(regions or {}) end,
        GetChildren = function() return unpack(children or {}) end,
    }
    if name then frame.GetName = function() return name end end
    return frame
end

do
    local blind = newTexture(secret)
    local plain = newTexture(1)
    local window = newFrame("Frame", "AuctionHouseFrame", { blind, plain })

    local ok, count = pcall(Darkness.ApplyToFrame, window, 0.5, 0.5, 0.5)
    T.ok(ok, "a pass over a window with an uncomputable texture does not fail")
    T.eq(count, 1, "exactly one darkening was counted")
    T.ok(close(plain.r, 0.5), "the neighbouring texture is darkened")
    T.eq(blind.r, secret, "while the uncomputable one stayed native")
end

T.suite("darkness: the pass skips a forbidden object instead of tinting it")

-- The second lesson from the same client, and the price for it was paid not
--
-- by the addon but by the game. The engine marks some of its objects as
-- forbidden to addons -- IsForbidden. That is not protection: a protected
-- frame may be read and may be moved out of combat, while a forbidden one
-- does not belong to addons at all, and one single access to it taints the
-- execution. The taint spreads further along the frames the object touches
-- and surfaces somewhere else entirely: the player saw "Secret values are
-- only allowed during untainted execution" in a game file, on an action bar
-- button cooldown, eight times in a row. The pass meanwhile reached
--
-- CooldownViewer and dutifully wrote its memory of the native colour onto
-- it. So the question is asked before all others: every next question is already an access.
do
    local counters = ns.Counters
    local before = counters.forbidden

    local function newForbidden(name, regions)
        local frame = newFrame("Frame", name, regions)
        frame.IsForbidden = function() return true end
        return frame
    end

    local art = newTexture(1)
    local frame = newForbidden("CooldownViewer", { art })

    T.eq(Darkness.ShouldSweep(frame), false,
        "a forbidden frame is not taken into the pass at all")

    local ok, count = pcall(Darkness.ApplyToFrame, frame, 0.5, 0.5, 0.5)
    T.ok(ok, "and an attempt to walk it does not fail")
    T.eq(count, 0, "zero objects were darkened in it")
    T.eq(art.r, 1, "its texture stayed native")
    T.eq(Darkness.Remembered(frame), nil,
        "and we left no memory of the native colour on it -- "
            .. "that is exactly what used to taint the object")
    T.ok(counters.forbidden > before,
        "while the skip itself is counted: this is a guard doing its work, not a silent omission")
end

-- A single texture inside an allowed frame can be forbidden too, and its
-- neighbour darkens as usual: the ban is a property of the object, not of
-- the window it lies in.
do
    local forbidden = newTexture(1)
    forbidden.IsForbidden = function() return true end

    local plain = newTexture(1)
    local window = newFrame("Frame", "SomeWindow", { forbidden, plain })

    local ok, count = pcall(Darkness.ApplyToFrame, window, 0.5, 0.5, 0.5)
    T.ok(ok, "a pass over a window with a forbidden texture does not fail")
    T.eq(count, 1, "exactly one was darkened -- the allowed one")
    T.eq(forbidden.r, 1, "the forbidden one stayed native")
    T.ok(close(plain.r, 0.5), "while the neighbouring one is darkened as usual")
end

-- A failing question counts as a ban. An object that fails even a question
-- about itself is all the more not to be touched, and a silent "oh well,
-- let us tint it" would be exactly the behaviour all of this started from.
do
    local angry = newTexture(1)
    angry.IsForbidden = function() error("not allowed", 0) end
    T.eq(ns.Skin.Forbidden(angry), true, "a failing question is a ban")

    local quiet = newTexture(1)
    T.eq(ns.Skin.Forbidden(quiet), false,
        "while an object without that method is not forbidden at all: "
            .. "a ban that cannot be asked about does not exist")
end

T.suite("darkness: applying the settings survives an uncomputable window")

-- The very case from the client: the common pass reached a window whose
-- colour reads as a secret number. Formerly an error went from here into the
-- core, the core disabled the module, and the settings page vanished from the screen.
do
    local savedUIParent = _G.UIParent

    local blindArt = newTexture(secret)
    local blindWindow = newFrame("Frame", "ProtectedThing", { blindArt })

    local plainArt = newTexture(1)
    local plainWindow = newFrame("Frame", "MerchantFrame", { plainArt })

    _G.UIParent = newFrame("Frame", "UIParent", {},
        { blindWindow, plainWindow })

    ns.flavor = "vanilla"
    local profile = { darkness = { amount = 100, exclude = {} } }
    ns.Addon = { db = { profile = profile } }

    for _, amount in ipairs({ 0, 1, 50, 99, 100 }) do
        profile.darkness.amount = amount
        T.ok(pcall(Darkness.ApplySettings, Darkness),
            "the application does not fail at darkening " .. amount)
    end

    T.ok(close(plainArt.r, helpers.whiteAt(Darkness.Factor(100))),
        "the other windows are darkened all the way along the slider")
    -- An uncomputable window now darkens instead of staying light.
    --
    -- Formerly it stayed native, and that was honest exactly as long as such
    -- windows were rare. With the game's protected windows (talents) they
    -- became visible: a light patch in the middle of a dark interface, which
    -- the player has no way to explain. The native colour counts as white --
    -- trim is tinted white anyway -- and the factor over white gives exactly
    -- the colour the slider chose.
    --
    -- The write goes under a protected call (applyPlan), so an engine that
    -- refuses the write leaves the texture as it was, and there is no failure.
    T.ok(close(blindArt.r, helpers.whiteAt(Darkness.Factor(100))),
        "an uncomputable window is darkened from white rather than left light")

    -- And the tint is computed the same way: it has no code of its own.
    profile.darkness.tint = { r = 1, g = 0.5, b = 0.25 }
    T.ok(pcall(Darkness.ApplySettings, Darkness),
        "and with a tint the application does not fail either")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedUIParent
end

--============================================================================
-- Taint: we do not write onto a foreign object
--============================================================================

-- The engine words the author saw:
--
-- > Blizzard_ActionBar/Shared/ActionButton.lua:891: bad argument #1 to
-- > 'SetCooldown' (Usage: self:SetCooldown(start, duration [, modRate]).
-- > Secret values are only allowed during untainted execution for this
-- > argument.)
--
-- The cooldown of an override bar button. The numbers there are fine -- the
-- engine says it will not let them through "during tainted execution", that
-- is what breaks is not the number but the execution. Our subsystem knows
-- nothing about that button and never calls it by name; what reaches it is
-- the common interface walk, which tints everything, because the darkening must lie on every window of the game.
--
-- Looking at a foreign object and tinting it is allowed. Writing onto it is
-- not: writing a field into the table of a game object taints the object
-- itself, and the taint spreads to the frame it belongs to and on to everything that frame touches.
-- Formerly the subsystem wrote two fields onto a texture -- the remembered
-- colour and the plan generation number -- and that is exactly that write.
--
-- What is checked here is a property, not the move of two fields: AFTER A
-- FULL PASS A FOREIGN OBJECT HAS NOT GAINED A SINGLE KEY. Then any new
-- field put onto a foreign object at any later time will be discovered
-- here, not by the player in a yellow line about someone else's file.

T.suite("darkness: no fields of ours are left on a foreign object")

do
    --- All keys of the object except methods: the methods are put there by the mock itself.
    local function keys(object)
        local out = {}
        for key, value in pairs(object) do
            if type(value) ~= "function" then out[#out + 1] = tostring(key) end
        end
        table.sort(out)
        return out
    end

    local texture = newTexture(1)
    local frame = newFrame("Frame", "SomeGameWindow", { texture })

    local beforeTexture = table.concat(keys(texture), " ")
    local beforeFrame = table.concat(keys(frame), " ")

    -- A real pass, with tinting: that is what used to write the fields.
    local count = Darkness.ApplyToFrame(frame, 0.5, 0.5, 0.5)
    T.ok(count > 0, "the pass really did tint the object rather than walk past it")
    T.ok(texture.r < 1, "and the colour on it changed")

    T.eq(table.concat(keys(texture), " "), beforeTexture,
        "the foreign texture gained not a single field")
    T.eq(table.concat(keys(frame), " "), beforeFrame,
        "and neither did the foreign frame")

    -- We are still obliged to remember: without a memory of the native colour
    -- returning the slider to zero would restore nothing, and two moves in a
    -- row would multiply the factors.
    local base = Darkness.Remembered(texture)
    T.eq(type(base), "table", "the native colour is remembered")
    T.eq(base[1], 1, "and the one remembered is the one from before us")

    -- The second pass computes from the remembered value rather than the
    -- current one: "sixty after forty" must give the same as "sixty at once".
    Darkness.ApplyToFrame(frame, 0.5, 0.5, 0.5)
    T.eq(texture.r, 0.5, "the second pass did not multiply the factors")
end

T.suite("a secret texture id does not become a table key")

-- The engine hands out the ids of protected textures as "secret": such a
-- number can be compared but cannot be used as a table key -- the attempt
-- ends with "attempted to index a table that cannot be indexed with secret
-- keys" in a foreign file. The author sent it in: the walk reached
-- CooldownViewer right after dying, and the id there is secret.
do
    local hidden = setmetatable({}, {
        __mul = function() error("secret number value", 0) end,
        __add = function() error("secret number value", 0) end,
        __index = function() error("secret key", 0) end,
    })

    local region = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function() return hidden end,
    }
    function region:GetVertexColor() return self.r, self.g, self.b, self.a end
    function region:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    local ok, reason = pcall(ns.Darkness.ContentReason, region)
    T.eq(ok, true, "the selection rule does not fail on a secret id")
    T.eq(reason, nil, "and counts such a texture as trim: its colour can be read")
end
