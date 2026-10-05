local helpers = require("helpers")

-- The away screen: the display rule, the missed-event tally and the drawing layer.
--
-- The order is the same as for the other parts: first what can be asked
-- without the game at all, then drawing on a fake engine. The first answers
-- "is it correct", the second "will it reach the player".
--
-- Why the rule is checked here and not in the client: checking it in the
-- client means sitting still for five minutes per attempt.

local FOLDER = "Features/Away"

local pure = helpers.loadModule(FOLDER, nil, { withRegistration = false })
local Rules, Missed, Screen = pure.Rules, pure.Missed, pure.Screen

--============================================================================
-- 1. The display rule
--============================================================================

T.suite("away: is the screen visible")

T.eq(type(Rules), "table", "the pure part was loaded")

T.eq(Rules.Shown(true, true, false), true,
    "module enabled, player away, nobody called -- the screen is visible")
T.eq(Rules.Shown(false, true, false), false,
    "a disabled module shows nothing")
T.eq(Rules.Shown(true, false, false), false,
    "player at the keyboard -- no screen")
T.eq(Rules.Shown(true, true, true), false,
    "the player was called -- no screen")

-- Dismissed with a click.
--
-- The canvas DOES catch the mouse, otherwise a stray click on the black
-- would hit the button beneath it. But that also means the game does not see
-- the click and does not clear the away state on it: without a rule of our
--
-- own the screen could only be dismissed from the keyboard. The module does
-- not clear the away state on the player's behalf: they have not stopped
-- being away by brushing the splash aside, and their "not here" is needed by
T.eq(Rules.Shown(true, true, false, true), false,
    "dismissed with a click -- no screen")
T.eq(Rules.Shown(true, true, false, false), true,
    "not dismissed -- the screen is visible")
T.eq(Rules.Shown(true, true, false, nil), true,
    "nothing said about a click -- the screen is visible")

-- And the dismissal applies only to THAT away period in which the click
-- happened: coming back and going away again, the player expects the splash
-- again. It is removed for good by a checkbox in the settings, not by a click.
T.eq(Rules.Shown(true, false, false, true), false,
    "back at the keyboard -- no screen anyway")

-- An interruption keeps the screen down until the END of the away period,
-- not until the end of combat: otherwise the canvas would come back on top
-- of a fight that just ended -- exactly when the player sat down again.
T.eq(Rules.Shown(true, true, true), false,
    "and stays down until the away period is over")

T.suite("away: the start of a new away period")

T.eq(Rules.Began(false, true), true, "the flag went up -- an away period began")
T.eq(Rules.Began(true, true), false, "the flag was up and stays up -- the same away period")
T.eq(Rules.Began(true, false), false, "the flag was cleared -- that is an end, not a start")
T.eq(Rules.Began(false, false), false, "there was nothing and there is nothing")

T.suite("away: the interruption list")

do
    T.ok(#Rules.INTERRUPTS >= 8,
        "interruptions listed: " .. #Rules.INTERRUPTS)

    -- Combat must be on the list: a screen over the interface in combat means
    -- dying blind, and it is the one interruption that costs a life.
    local found = {}
    for _, event in ipairs(Rules.INTERRUPTS) do found[event] = true end
    T.ok(found["PLAYER_REGEN_DISABLED"], "combat takes the screen down")
    T.ok(found["READY_CHECK"], "a ready check takes the screen down")

    -- Names are not repeated: a repeated name would subscribe one handler
    -- twice, and the core would silently refuse the second subscription.
    local seen, twice = {}, {}
    for _, event in ipairs(Rules.INTERRUPTS) do
        if seen[event] then twice[#twice + 1] = event end
        seen[event] = true
    end
    T.eq(#twice, 0, "event names are not repeated: "
        .. table.concat(twice, " "))

    -- The flag event cannot be in the interruption list: it both shows the
    -- screen and hides it, and in the interruption list it would take it down
    -- immediately after showing it.
    T.eq(found[Rules.FLAGS_EVENT], nil,
        "the flag event is not among the interruptions")
end

T.suite("away: time in words")

T.eq(Rules.Elapsed(0), "00:00", "zero is zero")
T.eq(Rules.Elapsed(7), "00:07", "seconds with a leading zero")
T.eq(Rules.Elapsed(257), "04:17", "minutes and seconds")
T.eq(Rules.Elapsed(3600), "1:00:00", "the hour is shown when there is one")
T.eq(Rules.Elapsed(3661), "1:01:01", "hours, minutes and seconds alike")

-- Anything can arrive from the game: the machine clock gets adjusted, and
-- GetTime starts over after entering the world.
T.eq(Rules.Elapsed(-5), "00:00", "a negative value is zero, not \"-00:-05\"")
T.eq(Rules.Elapsed(nil), "00:00", "nothing is zero")
T.eq(Rules.Elapsed("a lot"), "00:00", "a string is zero")
T.eq(Rules.Elapsed(0 / 0), "00:00", "NaN is zero, not \"-nan:-nan\"")

--============================================================================
-- 2. The missed-event tally
--============================================================================

T.suite("away: the missed-event tally")

do
    T.eq(type(Missed), "table", "the tally was loaded")

    local a, b = Missed.New(), Missed.New()
    T.ok(a ~= b, "each tally is its own, not a shared template by reference")

    T.eq(Missed.Any(a), false, "an empty tally has nothing to show")

    Missed.Add(a, "whisper")
    T.eq(a.whisper, 1, "a whisper is counted")
    Missed.Add(a, "whisper", 2)
    T.eq(a.whisper, 3, "and added to the previous ones")
    T.eq(Missed.Any(a), true, "now there is something to show")

    T.eq(b.whisper, 0, "the second tally is untouched")

    -- A typo at the call site must not create a new kind: it would never be
    -- printed (it is not in KINDS) and would never be noticed.
    Missed.Add(a, "whsiper", 5)
    T.eq(a.whsiper, nil, "an unknown kind does not create a key for itself")

    Missed.Add(a, "mail", 0)
    T.eq(a.mail, 0, "zero adds nothing")
    Missed.Add(a, "mail", -3)
    T.eq(a.mail, 0, "and a negative value does not either")
    Missed.Add(a, "mail", 0 / 0)
    T.eq(a.mail, 0, "nor does NaN")
end

T.suite("away: order and joining of the line")

do
    local tally = Missed.New()
    Missed.Add(tally, "mail", 1)
    Missed.Add(tally, "whisper", 3)

    local parts = Missed.Parts(tally)
    T.eq(#parts, 2, "both kinds made it into the line")
    T.eq(parts[1].kind, "whisper", "the order is set by the list, not by pair iteration")
    T.eq(parts[1].count, 3, "and the number beside the kind is the right one")
    T.eq(parts[2].kind, "mail", "mail comes second")

    local empty = Missed.New()
    T.eq(#Missed.Parts(empty), 0, "an empty tally has no parts")
    T.eq(Missed.Join({}), nil, "and no line comes out of them")

    T.eq(Missed.Join({ "3 whispers" }), "3 whispers", "a single part is itself")
    T.eq(Missed.Join({ "3 whispers", "1 letter" }),
        "3 whispers \194\183 1 letter",
        "two parts are separated by a middle dot, as in the info panel")

    -- Invites are not among the kinds, and that is a decision, not an
    -- omission: they are in the interruption list, the screen goes down on
    -- them, and there would be nowhere to show an invite tally.
    local kinds = {}
    for _, kind in ipairs(Missed.KINDS) do kinds[kind] = true end
    T.eq(kinds["invite"], nil, "invites are not counted: there is nowhere to show them")
end

-- Translation completeness is not checked here, and that is not an omission.
--
-- tests/test_optionwords.lua guards it with one check for the whole package:
-- it takes the file list from the TOC, collects keys from every part and
-- compares them against the ruRU and ukUA tables. A local copy of that check
-- was written here and thrown away: it read the sources with its own pattern,
-- found zero keys and silently called that a success. A second check of the
-- same thing diverges from the first quietly and always towards "all is well".

--============================================================================
-- 3. The drawing layer
--============================================================================

T.suite("away: the canvas on a fake engine")

do
    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }

    local built = {}
    local noop = function() end

    local function fake(kind)
        local object = { kind = kind, shown = false, points = {},
            texts = {}, children = {} }
        object.Show = function(self) self.shown = true end
        object.Hide = function(self) self.shown = false end
        object.IsShown = function(self) return self.shown end
        object.SetText = function(self, value) self.text = value end
        object.SetPoint = function(self, point, _, _, x, y)
            self.points[#self.points + 1] = { point, x, y }
        end
        object.SetColorTexture = function(self, r, g, b, a)
            self.ink, self.alpha = { r, g, b, a }, a
        end
        object.SetFont = function(self, face, size, flags)
            self.font = { face, size, flags }
        end
        object.GetFont = function(self)
            local f = self.font
            if f then return f[1], f[2], f[3] end
            return "Fonts" .. string.char(92) .. "FRIZQT__.TTF", 12, ""
        end
        object.SetAnimation = function(self, id) self.animation = id end
        object.SetUnit = function(self, unit) self.unit = unit end
        object.CreateTexture = function(self)
            local made = fake("Texture")
            self.children[#self.children + 1] = made
            return made
        end
        object.CreateFontString = function(self)
            local made = fake("FontString")
            self.children[#self.children + 1] = made
            return made
        end
        -- Only methods answer with an empty call: in the engine they are capitalised.
        -- A field that does not exist must stay empty.
        setmetatable(object, { __index = function(_, key)
            if type(key) == "string" and key:match("^%u") then return noop end
        end })
        built[#built + 1] = object
        return object
    end

    _G.UIParent = fake("Frame")
    _G.CreateFrame = function(kind) return fake(kind) end

    local frame = Screen.Build()
    T.ok(frame ~= nil, "the canvas was built")
    T.eq(Screen.Build(), frame, "a second call returns the same thing")

    T.eq(frame.shown, false, "the built canvas is hidden")
    T.eq(Screen.IsShown(), false, "and says so")

    -- The canvas is black and nearly opaque: the world is guessed as a
    -- silhouette while the card stays readable.
    local ink
    for _, child in ipairs(frame.children) do
        if child.ink then ink = child.ink end
    end
    T.ok(ink ~= nil, "the canvas fill is set")
    T.eq(ink and ink[1], 0, "the fill is black")
    T.ok(ink and ink[4] > 0.8 and ink[4] < 1,
        "and nearly opaque, but not solid: " .. tostring(ink and ink[4]))

    -- All six labels of the card are created.
    local lines = Screen.lines
    for _, key in ipairs({ "name", "who", "where", "timer", "missed",
        "clock" }) do
        T.ok(lines[key] ~= nil, "the card label is created: " .. key)
    end

    Screen.Paint({ name = "Someone", who = "Level 12 Priest",
        where = "Tirisfal Glades", timer = "Away 04:17" })

    T.eq(lines.name.text, "Someone", "the name is printed")
    T.eq(lines.timer.text, "Away 04:17", "and the away time too")
    T.eq(lines.name.shown, true, "a non-empty label is shown")

    -- An empty label hides rather than leaving a hole: a card with no guild
    -- must not have a gap where the guild would be.
    T.eq(lines.missed.shown, false, "an empty label is hidden")

    -- Line heights are assigned ON TOP of the core font. Otherwise the window
    -- font overwrites the large name template and the card comes out set in
    -- one size -- exactly what the author saw.
    T.ok(lines.name.font ~= nil, "the name was given a size")
    T.ok(lines.who.font ~= nil, "and the subtitle too")
    if lines.name.font and lines.who.font then
        T.ok(lines.name.font[2] > lines.who.font[2],
            "the name is larger than the subtitle: " .. tostring(lines.name.font[2])
            .. " against " .. tostring(lines.who.font[2]))
    end

    -- Density is set separately from building: the canvas is built once while
    -- the slider is dragged as often as one likes.
    Screen.Density(0.5)
    T.eq(Screen.ink.alpha, 0.5, "the density was set by the slider")
    Screen.Density(5)
    T.eq(Screen.ink.alpha, 1, "there is nothing above one")
    Screen.Density(-1)
    T.eq(Screen.ink.alpha, 0, "and nothing below zero either")
    Screen.Density("a lot")
    T.ok(Screen.ink.alpha > 0.9, "a non-number gives the default value")

    -- The animation is assigned once, not on every repaint: otherwise the
    -- dance would restart every second.
    Screen.Animate()
    T.eq(Screen.model.animation, 69, "the dance is set")
    Screen.model.animation = nil
    Screen.Animate()
    T.eq(Screen.model.animation, nil, "the same animation is not set again")

    -- And a repaint does not cancel it. SetUnit reloads the model and returns
    -- it to its idle pose, while a repaint happens once a second: if it
    -- called SetUnit, the dance would be cancelled a frame after it was set
    -- and the model would stand still. The author saw this as "I see no change".
    Screen.model.unit = nil
    Screen.Paint({ name = "Someone" })
    T.eq(Screen.model.unit, nil, "a repaint does not touch the model")

    local grown = lines.name.font and lines.name.font[2]
    Screen.Paint({ name = "Someone" })
    Screen.Paint({ name = "Someone" })
    T.eq(lines.name.font and lines.name.font[2], grown,
        "the size does not accumulate from repaint to repaint")

    Screen.SetShown(true)
    T.eq(Screen.IsShown(), true, "the canvas is shown")
    Screen.SetShown(false)
    T.eq(Screen.IsShown(), false, "and hidden again")

    Screen.frame, Screen.model, Screen.lines = nil, nil, nil
    Screen.ink, Screen.animation = nil, nil
    _G.CreateFrame, _G.UIParent = saved.CreateFrame, saved.UIParent
end

T.suite("away: nothing falls over without an engine")

do
    local saved = _G.CreateFrame
    _G.CreateFrame = nil

    Screen.frame, Screen.model, Screen.lines = nil, nil, nil
    Screen.ink, Screen.animation = nil, nil

    T.eq(Screen.Build(), nil, "without an engine no canvas is built")
    T.eq(Screen.IsShown(), false, "and there is nothing to show")

    -- None of the calls may fall over on a missing canvas: the module gets
    -- disabled and enabled, and the call order is set by the core, not by us.
    Screen.Paint({ name = "Someone" })
    Screen.SetShown(true)
    Screen.SetShown(false)
    Screen.Density(0.8)
    Screen.Animate("dance")
    T.ok(true, "repaint, show, density and animation pass silently without a canvas")

    _G.CreateFrame = saved
end
