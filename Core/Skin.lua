local ADDON, ns = ...

-- The palette and the colour arithmetic. This file does not call the game's
-- API: everything in it is tested outside the client. The styling of frames
-- lives in Skin/.
local Skin = {}
ns.Skin = Skin

--- Parse a hexadecimal colour into three channels from 0 to 1.
-- Accepts RRGGBB and #RRGGBB in any case. The three-character short form is
-- deliberately unsupported: it admits a typo that is hard to spot by eye.
-- @param hex string
-- @return number|nil red, green, blue
function Skin.HexToRGB(hex)
    if type(hex) ~= "string" then return nil end

    local body = hex:gsub("^#", "")
    if #body ~= 6 or body:find("[^0-9A-Fa-f]") then return nil end

    return tonumber(body:sub(1, 2), 16) / 255,
           tonumber(body:sub(3, 4), 16) / 255,
           tonumber(body:sub(5, 6), 16) / 255
end

--- An object addons must not touch.
--
-- The engine marks some of its objects forbidden, and that is not the same as
-- protected. A protected frame may be read by an addon and moved by it out of
-- combat; a forbidden one does not belong to addons at all — touching it
-- taints the execution, and the taint spreads further through the frames the
-- object touches. That is exactly what happened: the dimming pass reached the
-- cooldown viewer, tainted it, and the game then refused to give an action
-- button its own cooldown — Secret values are only allowed during untainted
-- execution. The player saw the error in somebody else's file while the cause
-- was here.
--
-- The question is put to the object itself — IsForbidden. The method may be
-- absent entirely (an old client, a frame of our own, a stand-in in the
-- tests), and then the answer is "not forbidden": a prohibition that cannot
-- be asked about does not exist. A question that raises, on the other hand,
-- counts as a prohibition: if an object fails even at that, there is all the
-- more reason not to touch it.
--
-- @param object any
-- @return boolean
function Skin.Forbidden(object)
    local kind = type(object)
    if kind ~= "table" and kind ~= "userdata" then return false end

    local ok, forbidden = pcall(function()
        local ask = object.IsForbidden
        if type(ask) ~= "function" then return false end
        return ask(object)
    end)

    if not ok then return true end
    return forbidden == true
end

-- The client's direct question "is this value secret", where the client
-- knows it.
--
-- That is the real answer, while the behavioural checks below work around its
-- absence. A client without secret values does not define this function at
-- all, so its absence is an ordinary "not secret" answer rather than an
-- error. A question that raises counts as "secret": a value that fails even
-- at a question about itself is not fit for work.
--
-- @param value any
-- @return boolean|nil true/false is the client's answer; nil means the
--     client does not know
local function askedSecret(value)
    local ask = _G and _G["issecretvalue"]
    if type(ask) ~= "function" then return nil end

    local ok, secret = pcall(ask, value)
    if not ok then return true end
    return secret == true
end
Skin.AskedSecret = askedSecret

-- A multiplication moved into a named function for one reason: it can be
-- called through pcall. Inside Skin.Numeric that is the only way to ask a
-- value whether it is fit for arithmetic without breaking the addon.
local function times(value, factor)
    return value * factor
end

--- Side memory about an object, leaving no trace on it.
--
-- === Why ===
--
-- A subsystem needs to remember one or two things about somebody else's
-- object: what its colour was before us, which generation of the plan it was
-- recorded in. The obvious place for that is a field on the object itself,
-- and for years that is where it lay.
--
-- That turned out to be wrong, and wrong expensively. Writing a field into a
-- game object's table marks the object itself: the engine considers it
-- touched by an addon, and the taint spreads further — to the frame the
-- object belongs to and to everything that frame touches. The player sees it
-- not in our file but in somebody else's:
--
--   Blizzard_ActionBar/Shared/ActionButton.lua:891: bad argument #1 to
--   'SetCooldown' ... Secret values are only allowed during untainted
--   execution for this argument.
--
-- The cooldown of an override bar's button. Our subsystem knows nothing about
-- that button and never calls it by name — what reaches it is the general
-- traversal of the interface, colouring everything in turn, because the
-- dimming has to lie on every window of the game. The traversal has every
-- right to look at the button and to colour it. What it has no right to do is
-- write on it.
--
-- === How it is built ===
--
-- A table with weak keys: the object is the key, and the record about it
-- disappears along with it. A frame the game discarded is not held in memory
-- because we remember something about it.
--
-- The value does not refer back to the key — otherwise the weakness of the
-- keys would achieve nothing: the pair would hold itself.
--
-- @return table
function Skin.Memory()
    return setmetatable({}, { __mode = "k" })
end

--- Whether the engine protects this object.
--
-- === How this differs from Skin.Forbidden ===
--
-- A forbidden object must NOT BE TOUCHED AT ALL: one reference to it taints
-- the execution. A protected one may be, and addons legitimately do plenty
-- with it: read it, move it out of combat, subscribe to its events.
--
-- The difference is the price of touching. A protected frame is one whose
-- actions the engine checks against whoever asked for them: an action button,
-- a bar, the holder of the raid frames. Everything an addon changed on it the
-- engine considers changed by an addon from then on, and the frame's own code
-- starts executing tainted. The player sees this not in our file and not at
-- once:
--
--   Blizzard_ActionBar/Shared/ActionButton.lua:891: bad argument #1 to
--   'SetCooldown' ... Secret values are only allowed during untainted
--   execution for this argument.
--
-- The cooldown of an action button whose texture is all we recoloured.
--
-- The question is put to the object itself and through a guarded call: not
-- every client has the method, and a texture does not have it at all. No
-- answer means we treat it as unprotected: unprotected objects are the
-- overwhelming majority on screen, and the opposite default would take almost
-- the whole interface away from the dimming.
--
-- @param object any
-- @return boolean
function Skin.Protected(object)
    if type(object) ~= "table" then return false end
    if type(object.IsProtected) ~= "function" then return false end

    local ok, protected = pcall(object.IsProtected, object)
    if not ok then return false end

    return Skin.Truth(protected)
end

--- A font object's native face, size and flags: object -> record.
--
-- Memory shared by more than one side, which is why it lives in the core. The
-- fonts subsystem (Modules/Fonts.lua) writes it on first touching an object.
-- It is the only reader today: the second one, the old window's column
-- styling, went with that window. It stays in the core for the same reason it
-- was put here — the styling layer must not depend on the fonts subsystem
-- being present in a build, and the name of a field written out in two files
-- as a string would diverge at the first edit to either of them.
Skin.FontBase = Skin.Memory()

--- The grey of a tapped mob — the one the game itself paints it with.
--
-- The numbers are not invented: a half on each channel is what the game's own
-- bar code sets when the kill is not yours. There must be no shade of our own
-- here: the player has recognised that grey for years and decides by it
-- whether to attack or walk on.
--
-- It lives in the core for the same reason the class colours do: two parties
-- ask for it — the unit frame's bar and the nameplate's bar — and two copies
-- would diverge at the first edit.
--
-- @return number, number, number
function Skin.TapColor()
    return 0.5, 0.5, 0.5
end

--- The game's class colours: a table of class token -> colour.
--
-- The addon has no copy of the class colours of its own and never will. Two
-- parties ask for them — the "by class" bar on the unit frames and the "class
-- colour" mode of the dimming — and two copies would diverge at the very
-- first edit.
--
-- CUSTOM_CLASS_COLORS takes precedence over RAID_CLASS_COLORS deliberately:
-- it is the shared conventional table that addons such as ClassColors set up,
-- and a player who installed one chose different shades knowingly. An addon
-- that fails to notice it paints the bar one blue and the name beside it
-- another, and the addon is the one that looks at fault.
--
-- @return table|nil
function Skin.GameClassColors()
    local custom = _G.CUSTOM_CLASS_COLORS
    if type(custom) == "table" then return custom end
    return _G.RAID_CLASS_COLORS
end

--- The player's class colour: three channels, or nothing.
--
-- Read under a guard and through ns.Skin.Numeric: the colour comes out of
-- somebody else's table, and anything can be in there — from a string to a
-- secret number.
--
-- @return number|nil, number|nil, number|nil
function Skin.PlayerClassColor()
    if type(_G.UnitClass) ~= "function" then return nil end

    local ok, _, token = pcall(_G.UnitClass, "player")
    if not ok then return nil end

    token = Skin.Textual(token)
    if token == nil then return nil end

    local colors = Skin.GameClassColors()
    local color = type(colors) == "table" and colors[token] or nil
    if type(color) ~= "table" then return nil end

    local r = Skin.Numeric(color.r)
    local g = Skin.Numeric(color.g)
    local b = Skin.Numeric(color.b)
    if r == nil or g == nil or b == nil then return nil end

    return r, g, b
end

--- A value one can compute with, or nil.
--
-- Why this exists. The client hands over some properties of protected and
-- restricted objects as secret numbers: such a value's type is number and it
-- can be passed anywhere, but the first arithmetic on it breaks the execution
-- while that execution is tainted by an addon (attempt to perform arithmetic
-- on a secret number value, while execution tainted by Darken). That is the
-- engine's behaviour rather than our mistake, and persistence does not get
-- around it.
--
-- So what is checked is not the type but the very possibility of computing:
-- the value is multiplied by one under pcall. A usable number passes and is
-- returned as itself, while a secret one makes the multiplication raise
-- inside the guarded call and leaves here as nil. A type check would be
-- useless in precisely the case the function was written for: a secret
-- number's type is that of an ordinary one.
--
-- There is no other way to ask the client "is this value secret": functions
-- such as issecure answer about the state of the execution rather than about
-- an individual value. The guarded call is the only check available, and its
-- price is named below.
--
-- A string is rejected separately: Lua coerces a numeric string in a
-- multiplication, and without that rejection any label that strayed into a
-- channel would become a colour.
--
-- The price: one guarded call per value checked. It is made where the colour
-- arrives from the game, that is, once per texture per pass, and comes
-- cheaper than investigating an error the player would otherwise see.
--
-- @param value any
-- @return number|nil the same number, if it can be computed with
function Skin.Numeric(value)
    if type(value) == "string" then return nil end
    if askedSecret(value) == true then return nil end

    local ok, result = pcall(times, value, 1)
    if not ok or type(result) ~= "number" then return nil end
    return result
end

-- Both dangerous operations on a string in one place, so that one guarded
-- call asks about them together: a comparison against the empty string and a
-- search in it. Those are exactly what anyone who received a string from the
-- game does — and it was exactly the first of them the general dimming pass
-- used to fail on.
local function readable(value)
    if value == "" then return false end
    string.find(value, "", 1, true)
    return true
end

--- A string one can work with, or nil.
--
-- The string counterpart to Skin.Numeric, and the same trouble. The client
-- hands over some properties of protected objects as secret strings: such a
-- string's type is string and it can be put into a variable and passed on,
-- but the first comparison or search on it breaks the execution while that
-- execution is tainted by an addon (attempt to compare local value, a secret
-- string value, while execution tainted by Darken). A type check misses
-- precisely the case it would be written for: a secret string's type is that
-- of an ordinary one.
--
-- So what is checked is not the type but the very possibility of working with
-- it: the string is compared against the empty string and searched in — under
-- a guarded call. A usable one passes and is returned as itself, a secret one
-- makes the check raise inside and leaves here as nil, that is, "this object
-- has no name as far as we are concerned". The empty string is nil too:
-- calling it a name would be dishonest, and every caller discarded it with a
-- condition of their own anyway.
--
-- The price: one guarded call per string taken from the game. It is made
-- where the string arrives from outside — an object's type, a frame's name, a
-- texture's path — and comes cheaper than an error the player would otherwise
-- see.
--
-- @param value any
-- @return string|nil the same string, if it can be worked with
function Skin.Textual(value)
    if type(value) ~= "string" then return nil end
    if askedSecret(value) == true then return nil end

    local ok, result = pcall(readable, value)
    if not ok or result ~= true then return nil end
    return value
end

-- Both dangerous operations on a boolean in one place: a comparison against
-- nil and a comparison against false. Anyone who received a yes/no answer
-- from the game does them — and on a secret value the first of them
-- raises.
local function decided(value)
    if value == nil then return false end
    if value == false then return false end
    return true
end

--- A yes-or-no answer one can work with.
--
-- The third counterpart to Numeric and Textual, and the last one found. The
-- client hands over not only numbers and strings as secret but booleans too:
-- whether a unit is a player, whether it is in combat, whether it is
-- connected. Such a value's type is ordinary, while the first comparison
-- against nil or false breaks the execution.
--
-- The trouble here is quieter than with its neighbours. A secret number
-- breaks the arithmetic at once and loudly; a secret yes can be stepped
-- around by accident — Lua tests truthiness in `and` and `if` without a
-- comparison — and then the answer turns out not false but arbitrary: a unit
-- the game is silent about counts as a player, and the class colouring goes
-- looking for a boar's class.
--
-- So the question is put directly: a comparison under a guarded call. A
-- refusal means no rather than maybe: a setting that works sometimes is worse
-- than one switched off.
--
-- @param value any
-- @return boolean
function Skin.Truth(value)
    if askedSecret(value) == true then return false end

    local ok, result = pcall(decided, value)
    if not ok then return false end
    return result
end

--- Multiply a colour by a factor, clamping the result to 0..1.
-- This is the same operation the engine uses to lay a colour onto a texture,
-- so dimming the interface and dimming a bar are computed the same way.
--
-- Every incoming value goes through Skin.Numeric, and that is not belt and
-- braces but a closed hole. Shade is a helper shared by the whole styling
-- layer, and some of its callers pass in a colour read from the game rather
-- than taken from our palette: Modules/Darkness.lua reads GetVertexColor,
-- Modules/UnitFrames.lua GetStatusBarColor. Any of them will sooner or later
-- receive a secret number, and a multiplication inside Shade would break the
-- caller wherever it was. Refusing is cheaper: a colour that cannot be
-- computed is a nil on the way out rather than an error on the player's
-- screen.
--
-- There may be one factor or three. One is ordinary dimming: all three
-- channels are dimmed equally and grey stays grey. Three is dimming with a
-- tint: the channels are dimmed differently and the chrome moves towards the
-- chosen colour. It is one and the same multiplication rather than two
-- mechanisms: a tint is simply a factor whose channels are not equal to each
-- other. The second and third arguments are optional and default to the
-- first, so older calls with one factor work as they did.
--
-- @param r number
-- @param g number
-- @param b number
-- @param fr number the red factor, and all three when the others are absent
-- @param fg number|nil the green factor
-- @param fb number|nil the blue factor
-- @return number|nil, number, number three channels, or a single nil if even
--         one of the incoming values cannot be computed with
function Skin.Shade(r, g, b, fr, fg, fb)
    if fg == nil then fg = fr end
    if fb == nil then fb = fr end

    r, g, b = Skin.Numeric(r), Skin.Numeric(g), Skin.Numeric(b)
    if r == nil or g == nil or b == nil then return nil end

    fr, fg, fb = Skin.Numeric(fr), Skin.Numeric(fg), Skin.Numeric(fb)
    if fr == nil or fg == nil or fb == nil then return nil end

    local function clamp(v, factor)
        v = v * factor
        if v < 0 then return 0 end
        if v > 1 then return 1 end
        return v
    end
    return clamp(r, fr), clamp(g, fg), clamp(b, fb)
end

-- The palette is derived from the addon's own textures: the white end of the
-- mzk.tga gradient and its lilac finish.
local HEX = {
    ink       = "0D0D11",
    panel     = "15151B",
    panelAlt  = "101016",
    line      = "2E2E39",
    lilac     = "B682BC",
    lilacDeep = "56365E",
    -- Almost white. It used to be noticeably greyer, and on the window's
    -- dark ground that reads as faded text rather than as soft: the ground is
    -- quiet by itself, and there is no reason to mute the letters on it as
    -- well.
    text      = "F2EFF6",
    textDim   = "8B8697",
    textFaint = "615E6A",

    -- The palette's only warm colour, added late and deliberately.
    --
    -- The palette went ten versions of the contract without an alarm colour,
    -- and not through oversight: a dark theme says "look here" with its
    -- accent and a step of brightness, while a red dot in it shouts louder
    -- than everything else put together. But nobody ever decided "there will
    -- be no red" — there simply was none. Meanwhile a watchdog module
    -- (durability, health, charges, food supply) has nothing to say "bad"
    -- with: the accent is taken by hover and selection, and a reading that
    -- turned accent-coloured reads as the row under the mouse. The only way
    -- out left was to invent a colour from numbers, and an invented colour is
    -- one the palette will never shift again.
    --
    -- So there is one colour, muted to the level of the rest of the palette
    -- (not pure red: pure red in this theme is a hole in the screen), and its
    -- scope is narrow. Allowed: a number or a short label reporting a state
    -- that needs the player to act. Forbidden: fills, borders, bars, icons,
    -- hover, selection and anything that repeats on screen more than once. An
    -- alarm that is always lit stops being an alarm.
    warn      = "D08770",
}

-- The parsing is checked right here. A typo in HEX would give a colour of
-- three nils, Skin.Get would return nil, and the failure would happen in the
-- game — inside SetColorTexture, one line per widget, with an unstyled window
-- on top. An addon must fail at load rather than in combat, so the guilty
-- entry is named here.
Skin.Palette = {}
for name, hex in pairs(HEX) do
    local r, g, b = Skin.HexToRGB(hex)
    if r == nil then
        error(string.format(
            "palette colour '%s' is malformed: %s", tostring(name), tostring(hex)), 0)
    end
    Skin.Palette[name] = { r, g, b }
end

--============================================================================
-- The accent
--============================================================================

-- The accent is the one colour a dark theme says "look here" with: the
-- heading of a section, a checkbox's tick, the filled part of a slider, the
-- scrollbar, the selected row and the hover are painted with it.
--
-- === Why it became a choice rather than staying lilac ===
--
-- The lilac is derived from the addon's own textures and was right for
-- exactly as long as the interface was one person's addon. The accent colour
-- is one of the few things in the styling the player has an opinion of their
-- own about, and that opinion is no worse than ours: a person looks at the
-- settings window longer than we look at their palette.
--
-- There are four sets, and each holds two colours rather than one. The second
-- is the deep one: the selected row and a pressed button are filled with it,
-- and it cannot be obtained by darkening the first. Darkened lilac goes grey,
-- darkened gold goes swampy, and each set is therefore stated as a pair
-- chosen by eye.
Skin.ACCENTS = {
    lilac = { accent = "B682BC", deep = "56365E" },
    steel = { accent = "7E8CA3", deep = "37414F" },
    moss  = { accent = "8FA396", deep = "3E4C42" },
    gold  = { accent = "C9A227", deep = "5A4614" },
}

-- The order in the list: lilac first, because it was first.
Skin.ACCENT_ORDER = { "lilac", "steel", "moss", "gold" }

-- The set chosen right now.
Skin.accent = "lilac"

--- Change the palette's accent.
--
-- Two palette colours change and only those: the rest — the blacks, the lines
-- and the text — is not tied to the accent at all, and the theme does not
-- come apart when it changes.
--
-- The palette's colour names stayed as they were, lilac and lilacDeep: they
-- are ROLES rather than names of shades, and renaming them to accent would
-- cost edits in three dozen places for the sake of a word. A role is read
-- from where the colour stands rather than from what it is called.
--
-- @param key any the set's name
-- @return boolean whether it changed
function Skin.SetAccent(key)
    local set = type(key) == "string" and Skin.ACCENTS[key] or nil
    if set == nil then return false end

    local ar, ag, ab = Skin.HexToRGB(set.accent)
    local dr, dg, db = Skin.HexToRGB(set.deep)
    if ar == nil or dr == nil then return false end

    Skin.Palette.lilac     = { ar, ag, ab }
    Skin.Palette.lilacDeep = { dr, dg, db }
    Skin.accent = key

    return true
end

--- A palette colour by name.
-- @param name string
-- @param alpha number|nil the opacity; 1 by default
-- @return number|nil red, green, blue, opacity
function Skin.Get(name, alpha)
    local c = Skin.Palette[name]
    if not c then return nil end
    return c[1], c[2], c[3], alpha or 1
end

-- Button colours by state.
--
-- Why this was needed at all. The styling suppresses a button's native
-- textures — pressed, highlighted and disabled — because a red Blizzard
-- button has no place in a dark flat window. But for a long time nothing was
-- drawn in their stead: the click worked and looked like nothing, and that
-- reads as a broken button. Feedback is not decoration: without it the player
-- does not know whether they hit the button and whether it took the press.
--
-- The table is here rather than in the widget styling for the same reason the
-- palette is: this is a rule rather than drawing, and it is tested outside
-- the client.
--
-- There are three kinds of button. The ordinary one is filled with the panel
-- colour. The primary one (a window's single action) differs by its fill
-- rather than by its border: the border is taken by the hover feedback. A
-- dropdown uses the same state machinery but a fill darker than its
-- surroundings: a list on panelAlt inside a panel block merged with it and
-- did not read as a separate control.
--
-- The focus state is declared only for the dropdown, and that is not an
-- omission. Keyboard focus belongs to exactly what is typed into: an edit box
-- and a slider's number field. A button never receives it, and the look of a
-- focused button would be a look that never occurs. Skin.ButtonColors treats
-- an unknown state as the ordinary one (see below), so calling it with focus
-- for a button gives that button's ordinary look rather than a hole.
--
-- The focus border is the text colour rather than lilac: lilac is taken by
-- hover, and two states with a border of the same colour are exactly what the
-- author complained about. Only the border changes: the focus fill is the
-- resting one, so a field under the cursor does not jump when it is clicked.
local BUTTON_COLORS = {
    normal = {
        normal   = { "panel",     "line",      "text"    },
        hover    = { "line",      "lilac",     "text"    },
        pressed  = { "lilacDeep", "lilac",     "text"    },
        disabled = { "panelAlt",  "line",      "textDim" },
    },
    primary = {
        normal   = { "lilacDeep", "lilac",     "text"    },
        hover    = { "lilac",     "lilac",     "ink"     },
        pressed  = { "lilacDeep", "text",      "text"    },
        disabled = { "panelAlt",  "line",      "textDim" },
    },
    select = {
        normal   = { "ink",       "lilacDeep", "text"    },
        hover    = { "ink",       "lilac",     "text"    },
        focus    = { "ink",       "text",      "text"    },
        pressed  = { "lilacDeep", "lilac",     "text"    },
        disabled = { "panelAlt",  "line",      "textDim" },
    },
}

--- The palette colour names for a button in a given state.
-- A pure function. An unknown state and an unknown kind count as the ordinary
-- ones: the values come from the styling code, and a typo in them must not
-- leave a button with no colour at all.
-- @param state string|nil "normal" | "hover" | "pressed" | "disabled"
-- @param kind string|nil "normal" | "primary" | "select"
-- @return string, string, string the fill, border and label colour names
function Skin.ButtonColors(state, kind)
    local byKind = BUTTON_COLORS[kind] or BUTTON_COLORS.normal
    local colors = byKind[state] or byKind.normal
    return colors[1], colors[2], colors[3]
end

--- The state of a field typed into from the keyboard.
--
-- The order of precedence is written down here, once for the whole window:
-- disabled beats focus, focus beats hover. The middle step is the important
-- one. Focus is the answer to "where will the letters go if I start typing",
-- and that answer has to be visible when the mouse cursor is already
-- somewhere else: the player clicks a field and moves the mouse towards the
-- next one — and if the focus goes out with the cursor, what they type goes
-- who knows where. That is exactly why hover does not override focus while
-- focus does override hover.
--
-- A pure function: three flags in, a state name out. It is what the tests
-- check, because the rule here is the order rather than the colours.
--
-- @param disabled any whether the field is disabled
-- @param focused any whether the field has keyboard focus
-- @param over any whether the cursor is over the field
-- @return string the state name for Skin.ButtonColors with the select
--     kind
function Skin.FieldState(disabled, focused, over)
    if disabled then return "disabled" end
    if focused then return "focus" end
    if over then return "hover" end
    return "normal"
end

-- The fill of a row in a list: a page's row in the column, a tab, a row of
-- an open dropdown.
--
-- Two states, and the difference between them is visible without comparing.
-- Selection is a nearly solid fill: it is what the player answers "where am
-- I" by, and it has to answer when the mouse is not in the window at all.
-- Hover is a transparent veil: it says "the cursor is here", lives exactly as
-- long as the cursor is over the row, and must not pass for selection.
--
-- The complaint was about precisely this: the selected row was filled with
-- the same colour as the row under the cursor, differing only in opacity —
-- 0.55 against 0.35. Two tenths of a difference on one and the same colour
-- does not read to the eye, and the page column ended up with two rows
-- highlighted alike.
--
-- So both quantities were separated at once: selection has a colour of its
-- own (the deep lilac, a fill) and a density of its own, hover the light
-- lilac and a veil's density. The numbers live here rather than in three
-- styling files, and the rule "a veil must not pass for a fill" is checked by
-- a test.
local ROW_COLORS = {
    selected = { "lilacDeep", 0.85 },
    hover    = { "lilac",     0.16 },
}

--- A row's fill colour and opacity, by state.
-- A pure function. An unknown state (an ordinary row included) means no fill
-- rather than a default one.
-- @param state string|nil "selected" | "hover"
-- @return string|nil the palette colour's name
-- @return number|nil the opacity
function Skin.RowColors(state)
    local row = ROW_COLORS[state]
    if not row then return nil end
    return row[1], row[2]
end

-- Two groups in the page column.
--
-- The addon's foundation is the dark theme and its settings. Everything else
-- is modules not everyone installs, and the profiles page, which is not about
-- the game at all but about the settings themselves. In a flat list of
-- identical rows that distinction disappears: the author called the column
-- impossibly confusing, and what confuses is precisely the sameness — nine
-- other people's pages look just like ours.
--
-- The distinction is made by tone rather than by a border. A border around
-- the second group is one more line in a window the author complained about
-- all day; a tone adds nothing to the drawing, and the difference is visible
-- without reading the labels.
--
-- A selected row is fully lit in both groups: a group is how the list reads
-- at rest rather than a ban on reading the row the player is standing on.
-- Dimming the label under a lilac fill would make the selection worse for the
-- sake of a shade.
--
-- textFaint is the same textDim dimmed to seven tenths: the colour has to
-- stay from the palette and stay in the same family, or the second group
-- reads not as weaker but as different.
local TREE_TONES = {
    theme = { normal = "textDim",   bright = "text" },
    aside = { normal = "textFaint", bright = "text" },
}

--- The colour name for a row's label in the page column.
-- A pure function: two flags in, a palette colour name out.
-- @param aside any whether the row is in the second group (modules,
--     profiles)
-- @param bright any whether the row is selected or under the cursor
-- @return string the palette colour's name
function Skin.TreeTone(aside, bright)
    local tone = aside and TREE_TONES.aside or TREE_TONES.theme
    return bright and tone.bright or tone.normal
end

--- The file path of a bar texture by its name, for the dropdown's preview.
--
-- A dropdown's rows show the chosen texture as a bar, but a dropdown can hold
-- anything: beside texture names the same lists hold font names, page keys
-- and the word for closing. This question was born here, and the name it is
-- asked by from the styling stays here.
--
-- === Why this is now a call rather than a second answer ===
--
-- The core held two answers to "texture name to file": this one and
-- ns.Media.BarPath (Core/Media.lua). The contract gave a module the second
-- (through MediaApi.BarTexture) while the core's own subsystems called the
-- first — that is, one and the same name was resolved by two different rules
-- depending on who asked.
--
-- The difference is not cosmetic. BarPath looks among the nine textures
-- shipped with the addon first, which are files inside it and are found
-- without any registry; the entry here started with the registry and found
-- nothing without LibSharedMedia. The consequence: in an installation
-- without the library, a texture of ours chosen by the player would land on
-- the engine's nameplates (it calls BarPath through the contract) and would
-- not land on the unit frames, the cast bar or the dropdown preview — those
-- would show the game's own texture and say nothing about it. That is
-- invisible today only because the library lies in Libs/ and always loads —
-- that is, the rule was held up by what we ship rather than by what we
-- declare.
--
-- There is one correct answer and it is BarPath: our nine belong to the
-- addon rather than to the shared registry and must always be found. The
-- name was left here while the body moved to where the knowledge about our
-- files lives.
--
-- The "is this a texture at all" filtering did not weaken: for a foreign name
-- BarPath does exactly what this function did — IsValid, then Fetch with
-- noDefault, both under pcall. The word for closing will not get a bar.
--
-- The library arrives as an argument rather than from LibStub: otherwise the
-- function would stop being pure and could not be tested. The library's
-- absence is an ordinary nil answer rather than an error.
--
-- @param media table|nil a LibSharedMedia-3.0 object, or a compatible one
-- @param name any the presumed texture name
-- @return string|nil the texture file's path
function Skin.MediaTexture(media, name)
    -- Core/Media.lua loads after this file, so the table is taken at call
    -- time rather than at load. Its absence is not "there is no texture" but
    -- "there is nobody to ask"; the answer is the same nil, and there is
    -- deliberately no second body here: a spare copy of the rule is exactly
    -- what was removed from this place.
    local media_ = ns.Media
    if type(media_) ~= "table" or type(media_.BarPath) ~= "function" then
        return nil
    end

    return media_.BarPath(media, name)
end

--============================================================================
-- The spacing scale
--============================================================================

-- One window, one scale. Any spacing that occurs more than once must have a
-- name here: a number spread across the styling files diverges at the first
-- edit, and that divergence looks exactly the way the author complained about
-- it — the elements float.
--
-- The scale is a multiple of four. Four is not aesthetics but the smallest
-- step the eye notices on a dark flat ground: a two-pixel difference between
-- neighbouring elements reads as an accident, a four-pixel one as a
-- decision.
--
-- What each number means.
--
--   hair   — the thickness of a border and of a seam. One pixel, because
--            every border in the addon is that, and it has no second
--            thickness.
--   edge   — the inset of a label from the edge of whatever it stands on. A
--            label pressed flush merges with the border into one pixel, while
--            one moved a scale step (four) eats a noticeable part of a short
--            bar's length. Two means "not flush", and nothing more is meant
--            here.
--
--            The name exists because this quantity was not in the scale while
--            the addon has four labels on an edge, and each wrote a number of
--            its own: EDGE = 2 for the bar texts, 2 for a nameplate cast
--            bar's label, -1 for the level on a nameplate and -1 for the
--            stack count on an aura icon. The sign is the side being moved
--            from rather than a different quantity: outwards from the left
--            edge and inwards from the right are written as one number with
--            different signs. A discrepancy of one between two and one does
--            not read to the eye at all — and that is exactly why it lives
--            for years, while the next label on an edge starts a fifth
--            number.
--
--            edge falls out of the multiple-of-four series along with hair
--            and flow, and for the same reason: it is not a layout step but
--            the thickness of air near a line. The layout step starts at
--            rail.
--   rail   — the left rail. The contents of every control are inset from
--            their widget's edge by exactly this, so a checkbox's square, a
--            dropdown's fill, a slider's groove and a label all stand on one
--            vertical. Four rather than zero: the border around the square
--            and the dropdown is built outwards from the fill and at zero
--            would hang past the edge.
--   gap    — the gap between neighbouring controls.
--   inset  — the inset of a block's contents from its border. It is also the
--            inset of the block's heading: a heading that does not stand over
--            its own contents reads as having slipped.
--   group  — the gap between blocks. Twice the gap: otherwise a block's
--            border is the only thing that distinguishes blocks from a
--            settings row.
--   header — the height of the window's header. Twenty-six was set by the
--            library: it places the window's contents at -27 and computes the
--            layout's height from that.
--   line   — the height of a line of text in a dense list. Not the same as
--            row, and the difference is not in the number but in the purpose:
--            row is a line that gets clicked and its height was chosen for a
--            finger, while line is a line that gets read. Twenty result lines
--            at twenty-six would have added two hundred pixels of height to
--            the item database's window, which is why that window kept a
--            number of its own (LINE = 16) at the top of its file. There was
--            nothing between gap and row in the scale, which means the next
--            dense list would have written the same number of its own — the
--            fourth quantity by now that the project has reconciled from
--            copies into one name. Sixteen coincides with group as header
--            coincides with row: a coincidence of number rather than of
--            meaning, and two entries exist so that editing one does not move
--            the other.
--   row    — the height of a row in the page list. The library set the
--            header, we chose the row: the library's eighteen the author
--            called stuffy, twenty-six roomy, and twenty-two is the place
--            between them where a finger still does not miss. It is a
--            separate entry from header precisely so that editing one does
--            not move the other.
--   field  — the height of a single-line edit box. The library assigns it no
--            height at all: the field is exactly what its template made it. A
--            number of our own is needed so that the edit box and the confirm
--            button inside it are computed from one value rather than each
--            from its own; it does not change the widget's own height — the
--            field is anchored to the widget's bottom edge and has nowhere to
--            grow.
--   footer — the height of the window's footer.
--   window — the inset of the window's contents from its edge; also set by
--            the library (17).
--   flow   — the gap AceGUI inserts between layout rows by itself (the number
--            3 written into Libs/AceGUI-3.0/AceGUI-3.0.lua). Our gap is the
--            element's height plus an addition, and that addition is computed
--            from this number.
--
-- === Density ===
--
-- The gap, row and field numbers were chosen dense on purpose. The settings
-- window shows six hundred settings, and every extra pixel of row height is
-- one more turn of the mouse wheel on a page. The author compared the window
-- with Bartender and called ours roomy: where the library gives eighteen we
-- gave twenty-six, and a page that used to fit whole stopped fitting.
--
-- The lower bound here is not taste but a finger: a row that gets clicked is
-- never shorter than twenty-two — below that the mouse misses into its
-- neighbour.
--
-- The gap stayed as it was, and that is not forgetfulness. The spacing scale
-- is a multiple of four (see tests/test_skin.lua), and the next value down is
-- four, that is, the rail itself: a gap equal to the inset from the edge
-- erases the difference between "beside" and "inside". The density was
-- therefore taken from the row and field heights, where a step of one pixel
-- breaks nothing.
Skin.Metrics = {
    hair   = 1,
    edge   = 2,
    rail   = 4,
    gap    = 8,
    inset  = 12,
    group  = 16,
    header = 26,
    line   = 16,
    row    = 22,
    field  = 18,
    footer = 28,
    window = 17,
    flow   = 3,
}

--- How much to stretch an element so the gap to the next becomes the given
--- one.
-- A pure function. There is no negative addition: a gap smaller than the one
-- the library inserts itself would mean the elements overlap.
-- @param gap number|nil the desired gap; Skin.Metrics.gap by default
-- @return number the addition to the element's height
function Skin.Slack(gap)
    local want = tonumber(gap) or Skin.Metrics.gap
    local slack = want - Skin.Metrics.flow
    if slack < 0 then return 0 end
    return slack
end
