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

T.suite("texts: the position of the label")

do
    local point, relative, x, y = TX.Anchor("left")
    T.eq(point, "LEFT", "left: the anchor of the label")
    T.eq(relative, "LEFT", "left: the anchor of the bar")
    T.ok(x > 0, "left: an inset into the bar")
    T.eq(y, 0, "left: we do not move it vertically")
end

do
    local point, _, x = TX.Anchor("right")
    T.eq(point, "RIGHT", "right: the anchor of the label")
    T.ok(x < 0, "right: an inset into the bar")
end

T.eq(TX.Anchor("center"), "CENTER", "centred")
T.eq(TX.Anchor(TX.NATIVE), nil, "the native position is not computed")
T.eq(TX.Anchor(nil), nil, "garbage is not computed either")

-- The secure hook is faked under the same name the engine calls it by.
-- What is counted is not the call but what the hook was attached to: the
-- subsystem must attach it to the bar rather than to a foreign function at random.
local savedHook = _G.hooksecurefunc
_G.hooksecurefunc = function(object, method, handler)
    if type(object) == "table" and type(method) == "string" then
        object.hooks = (object.hooks or 0) + 1
        object.handler = handler
        return
    end
    if savedHook then return savedHook(object, method, handler) end
end

T.suite("texts: applying the settings")

local FAKE_GLOBALS = { "PlayerFrame", "TargetFrame", "PetFrame",
    "InCombatLockdown" }
local savedGlobals = {}
for i = 1, #FAKE_GLOBALS do savedGlobals[i] = _G[FAKE_GLOBALS[i]] end

--- A fake font string for the value.
local function newLabel()
    local label = {
        value = "",
        point = { "CENTER", nil, "CENTER", 0, 0 },
        shown = false,
    }
    function label:SetText(text) self.value = text end
    function label:GetPoint()
        return self.point[1], self.point[2], self.point[3],
            self.point[4], self.point[5]
    end
    function label:ClearAllPoints() self.cleared = true end
    function label:SetPoint(p, rel, rp, x, y)
        self.point = { p, rel, rp, x or 0, y or 0 }
    end
    function label:Show() self.shown = true end
    return label
end

--- A fake bar with a value label.
local function newBar(current, maximum)
    -- A game bar: a value, a limit and the ability to accept a hook on SetValue.
    --
    -- Formerly the fake accepted HookScript, because the subsystem stitched
    -- its own handler onto the bar handler. A stitched handler becomes ours
    -- in its entirety, and from then on the engine treats as tainted every
    -- execution passing through it -- including what the bar does by itself.
    -- The author saw it as "attempt to compare a secret number value
    -- (execution tainted by 'Darken')" in a game file, on the health bar he
    -- looks at all the time.
    --
    -- So the fake now accepts a secure hook and exactly that: HookScript on
    -- a foreign bar is that very taint, and the check must fail if it comes
    -- back.
    local bar = { value = current, max = maximum, hooks = 0 }
    bar.TextString = newLabel()
    function bar:GetValue() return self.value end
    function bar:GetMinMaxValues() return 0, self.max end
    function bar:SetValue(value) self.value = value end
    -- The own method, remembered at creation. A wrapper put onto the object
    -- will stop matching it -- that is how the substitution shows.
    bar.nativeSetValue = bar.SetValue
    function bar:HookScript()
        self.stitched = true
    end
    return bar
end

local function newFrame()
    return { healthbar = newBar(4500, 9000), manabar = newBar(300, 1000) }
end

local combat = false
InCombatLockdown = function() return combat end

ns.flavor = "vanilla"

local function setupFrames()
    PlayerFrame = newFrame()
    TargetFrame = newFrame()
    PetFrame    = newFrame()
end

local function withSettings(settings)
    ns.Addon = { db = { profile = { texts = settings } } }
    return settings
end

-- Out of combat everything is applied at once.
do
    combat = false
    setupFrames()
    withSettings({
        health = "both", power = "percent",
        abbreviate = false, position = "right",
    })
    TX:ApplySettings()

    T.eq(PlayerFrame.healthbar.TextString.value, "4500/9000 50%",
        "the health value is assembled")
    T.eq(PlayerFrame.manabar.TextString.value, "30%", "the resource value is assembled")
    T.eq(PlayerFrame.healthbar.TextString.point[1], "RIGHT",
        "the label was moved out of combat")
    T.ok(PlayerFrame.healthbar.TextString.shown, "and shown")
    -- The subsystem hangs NOTHING on the bar itself, and that is a rule, not
    -- an omission. There were two hooks, and both were wrong:
    --
    --   HookScript stitches our handler and the frame handler into one, and
    --     the whole bar handler becomes ours;
    --   hooksecurefunc(bar, "SetValue") puts a SetValue field with our
    --     wrapper onto the object itself -- that is a write onto a foreign frame.
    --
    -- The client taint log named the second one outright:
    --
    --   StatusBar:SetValue()
    --   An attempt to compare a secret value was blocked because of taint
    --   from Darken
    --
    -- What remains is a secure hook on the game FUNCTION that writes values
    -- onto bars (TextStatusBar_UpdateTextString): it touches no bar at all
    -- and instead receives the one the game has just updated.
    T.eq(PlayerFrame.healthbar.hooks, 0,
        "the subsystem hangs nothing on the bar itself")
    T.eq(PlayerFrame.healthbar.stitched, nil, "and stitches no handlers")
    T.eq(PlayerFrame.healthbar.SetValue, PlayerFrame.healthbar.nativeSetValue,
        "and the bar method stayed its own, not wrapped in ours")
    T.eq(TargetFrame.healthbar.TextString.value, "4500/9000 50%",
        "not only the player bar was configured")
end

-- Applying again does not breed handlers.
do
    TX:ApplySettings()
    T.eq(PlayerFrame.healthbar.hooks, 0, "nor on a repeated application")
end

-- Abbreviation is switched on separately and affects both numbers but not the percentage.
do
    setupFrames()
    withSettings({
        health = "both", power = TX.NATIVE,
        abbreviate = true, position = TX.NATIVE,
    })
    TX:ApplySettings()
    T.eq(PlayerFrame.healthbar.TextString.value, "4.5k/9.0k 50%",
        "the large numbers are abbreviated")
    T.eq(PlayerFrame.manabar.TextString.value, "",
        "a bar with the native format is untouched")
end

-- In combat the format is applied at once while the position is deferred:
-- the label is a region of a protected unit frame, and the engine forbids moving it in combat.
do
    setupFrames()
    local frames = ns.UnitFrames
    local queue = TX.Queue()
    frames.Drain(queue)

    combat = true
    withSettings({
        health = "percent", power = TX.NATIVE,
        abbreviate = false, position = "left",
    })
    TX:ApplySettings()

    T.eq(PlayerFrame.healthbar.TextString.value, "50%",
        "in combat the format is applied at once")
    T.eq(PlayerFrame.healthbar.TextString.point[1], "CENTER",
        "in combat the position is untouched")
    -- The position is one setting shared by both bars, so there are two
    -- writes per frame: health and resource. The format has nothing to do
    -- with it: a bar with the native format still has to be moved.
    T.eq(frames.Pending(queue), 6, "two deferred writes per frame")

    -- A repeated edit in combat does not lengthen the queue: the key is the same.
    TX:ApplySettings()
    T.eq(frames.Pending(queue), 6, "a repeated edit does not pile up writes")

    combat = false
    T.eq(frames.Drain(queue), 6, "leaving combat applies the deferred work")
    T.eq(PlayerFrame.healthbar.TextString.point[1], "LEFT",
        "and moves the label")
end

-- A return to the native position restores the native one, not our previous one.
do
    combat = false
    setupFrames()
    local settings = withSettings({
        health = "value", power = TX.NATIVE,
        abbreviate = false, position = TX.NATIVE,
    })
    PlayerFrame.healthbar.TextString.point = { "TOPLEFT", nil, "TOPLEFT", 3, -1 }
    TX:ApplySettings()
    T.eq(PlayerFrame.healthbar.TextString.point[1], "TOPLEFT",
        "the native position is untouched")

    settings.position = "right"
    TX:ApplySettings()
    T.eq(PlayerFrame.healthbar.TextString.point[1], "RIGHT", "the label was moved")

    settings.position = TX.NATIVE
    TX:ApplySettings()
    T.eq(PlayerFrame.healthbar.TextString.point[1], "TOPLEFT",
        "the restore brought back the native position")

    for _ = 1, 5 do
        settings.position = "left"
        TX:ApplySettings()
        settings.position = TX.NATIVE
        TX:ApplySettings()
    end
    T.eq(PlayerFrame.healthbar.TextString.point[1], "TOPLEFT",
        "five switches in a row do not shift the native position")
end

-- A fresh profile writes not a letter on the bars.
do
    setupFrames()
    withSettings({
        health = TX.NATIVE, power = TX.NATIVE,
        abbreviate = false, position = TX.NATIVE,
    })
    TX:ApplySettings()
    T.eq(PlayerFrame.healthbar.TextString.value, "", "the health was not overwritten")
    T.eq(PlayerFrame.manabar.TextString.value, "", "the resource was not overwritten")
    T.eq(PlayerFrame.healthbar.TextString.shown, false, "and the label was not shown")
end

-- The game handler brings us the very bar it has updated.
do
    setupFrames()
    withSettings({
        health = "percent", power = TX.NATIVE,
        abbreviate = false, position = TX.NATIVE,
    })
    TX:ApplySettings()

    PlayerFrame.healthbar.value = 2250
    T.ok(TX.Refresh(PlayerFrame.healthbar), "the update was accepted")
    T.eq(PlayerFrame.healthbar.TextString.value, "25%",
        "the label was recomputed from the new value")

    -- A bar the subsystem never marked does not belong to it.
    T.eq(TX.Refresh(newBar(1, 2)), false, "a foreign bar is skipped")
    T.eq(TX.Refresh(nil), false, "garbage instead of a bar is skipped")
end

-- The subsystem does not see a frame the client does not have.
do
    setupFrames()
    TargetFrame = nil
    withSettings({
        health = "value", power = TX.NATIVE,
        abbreviate = false, position = TX.NATIVE,
    })
    TX:ApplySettings()
    T.eq(PlayerFrame.healthbar.TextString.value, "4500/9000",
        "an existing frame is configured")
    T.eq(PetFrame.healthbar.TextString.value, "4500/9000", "and the second one too")
end

-- Without a profile the subsystem silently does nothing.
do
    setupFrames()
    ns.Addon = nil
    TX:ApplySettings()
    T.eq(PlayerFrame.healthbar.TextString.value, "", "without a profile we write nothing")
end

T.suite("texts: the settings section")

do
    local args = TX.options.args
    T.eq(args.health.type, "select", "the health format is a select")
    T.eq(args.power.type, "select", "the resource format is a select")
    T.eq(args.abbreviate.type, "toggle", "abbreviation is a checkbox")
    T.eq(args.position.type, "select", "the position is a select")

    T.eq(args.health.sorting()[1], TX.NATIVE, "the native format comes first")
    T.eq(args.position.sorting()[1], TX.NATIVE, "the native position comes first")

    local values = args.health.values()
    T.ok(values.value ~= nil and values.percent ~= nil and values.both ~= nil,
        "all three formats are in place")

    -- The defaults are the native look of the game.
    T.eq(TX.defaults.health, TX.NATIVE, "the health default is native")
    T.eq(TX.defaults.power, TX.NATIVE, "the resource default is native")
    T.eq(TX.defaults.abbreviate, false, "there is no abbreviation by default")
    T.eq(TX.defaults.position, TX.NATIVE, "the position default is native")

    -- The position description must name the combat restriction: it is the
    -- only place the player learns why the label "did not move at once".
    T.ok(args.position.desc:find("combat") ~= nil,
        "the position description mentions combat")
end

-- The handlers write into the profile and apply at once.
do
    combat = false
    setupFrames()
    local settings = withSettings({
        health = TX.NATIVE, power = TX.NATIVE,
        abbreviate = false, position = TX.NATIVE,
    })

    TX.options.args.health.set(nil, "percent")
    T.eq(settings.health, "percent", "the format went into the profile")
    T.eq(PlayerFrame.healthbar.TextString.value, "50%", "and was applied at once")
    T.eq(TX.options.args.health.get(), "percent", "get returns what was chosen")

    TX.options.args.abbreviate.set(nil, true)
    TX.options.args.health.set(nil, "value")
    T.eq(PlayerFrame.healthbar.TextString.value, "4.5k/9.0k",
        "the abbreviation was applied at once")
end

T.suite("bar texts: it hooks every name the client happens to have")

-- The author's report from a live client showed zero hooks: the function
-- with the single name the subsystem counted on does not exist on his
-- client. The names differ between builds, and trying them all is cheaper than guessing.
do
    local Texts = ns.Registry and ns.Registry:Get("texts") or nil
    if Texts == nil then Texts = ns.Texts end

    T.ok(type(Texts) == "table", "the subsystem is in place")

    if type(Texts) == "table" then
        T.ok(type(Texts.HOOKS) == "table" and #Texts.HOOKS >= 2,
            "there is more than one name to try: " .. #(Texts.HOOKS or {}))

        -- ALL the ones found are taken, not the first at hand: the second is
        -- not called from the first everywhere, and hooking only the outer
        -- one can miss the updates that go through the inner one.
        local hooked, saved = {}, _G.hooksecurefunc
        _G.hooksecurefunc = function(name) hooked[name] = true end

        local kept = {}
        for _, name in ipairs(Texts.HOOKS) do
            kept[name] = _G[name]
            _G[name] = function() end
        end

        Texts.MISSING = {}
        Texts:OnEnable()

        for _, name in ipairs(Texts.HOOKS) do
            T.ok(hooked[name], "hooked onto " .. name)
        end
        T.eq(#Texts.MISSING, 0, "everything was found -- nothing to complain about")

        -- And what is missing is named: "zero hooks" and "nothing to hook"
        -- are different troubles, and they are cured by different things.
        for _, name in ipairs(Texts.HOOKS) do _G[name] = nil end
        Texts.MISSING = {}
        Texts:OnEnable()
        T.eq(#Texts.MISSING, #Texts.HOOKS,
            "not a single name exists -- all of them are named")

        for _, name in ipairs(Texts.HOOKS) do _G[name] = kept[name] end
        _G.hooksecurefunc = saved
    end
end

for i = 1, #FAKE_GLOBALS do _G[FAKE_GLOBALS[i]] = savedGlobals[i] end
