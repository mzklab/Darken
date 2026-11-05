local ADDON, ns = ...

-- The text on the bars: the value's format, the shortening of large numbers
-- and the label's position.
--
-- There is no font here and there must not be. These very font strings already
-- belong to the fonts subsystem's "bar values" category
-- (Modules/Fonts.lua, CATEGORIES.barvalue, the paths healthbar.TextString and
-- manabar.TextString). A second mechanism for choosing a font would mean two
-- owners of one SetFont and a war of repaints on every application of the
-- settings. So this subsystem answers for WHAT is written and WHERE, while the
-- fonts subsystem answers for WHAT IT IS WRITTEN WITH. Both reach the objects
-- themselves the same way: ns.Fonts.Field by a dotted path.
--
-- What is rewritten. The game draws the value on a bar itself, and draws it
-- afresh on every change: a change of target, damage, regeneration. So our
-- label is not laid once but laid behind the game — by a handler on top of
-- TextStatusBar_UpdateTextString (the one function that writes these strings)
-- and by an OnValueChanged handler on the bar itself. The second is needed not
-- for reliability's own sake: when the display of values is switched off in
-- the game's settings, the first function does not touch the strings at all.
--
-- Combat restrictions. The health and power bars are descendants of the unit
-- frames, and those are built on a secure template, that is, protected by the
-- engine. The protection extends to their regions: SetPoint, Show and Hide on
-- a font string of a protected frame are forbidden in combat. SetText is not
-- protected — it is contents rather than geometry or visibility. So the format
-- is applied at once, in combat too, while the label's position and display
-- are deferred until combat ends.
--
-- No queue of deferred changes of our own is created: it is already written
-- and tested in the unit frames subsystem (ns.UnitFrames.NewQueue and its
-- neighbours). A second copy would diverge from the first at the very first
-- edit, and the rule "a repeated write evicts the former one, keeping its
-- place in the queue" has one owner.
--
-- The defaults are the game's native look. The "as in the game" format means
-- the subsystem does not touch the string at all, and it is what stands in a
-- fresh profile.

local Texts = {
    name = "texts",
}
ns.Texts = Texts

-- The tally of what was done (Core/Tally.lua). The reference is taken once
-- while the file is read: the handler on top of the game's function fires as
-- often as the game calls its own function, and it must not cost more than one
-- addition of integers.
local counters = ns.Counters or {}
ns.Counters = counters

-- Hooks installed and hooks fired. The first, were it zero, would mean that
-- not one guessed name of a game function was found; the second, with the
-- first non-zero, would mean the name was found and came to nothing.

-- The marker for "as the game draws it". The same value the neighbouring
-- subsystems use: it reaches SavedVariables and has to mean one and the same
-- thing across the whole addon.
local NATIVE = "__native"
Texts.NATIVE = NATIVE

-- What the subsystem remembers about foreign objects, in side memory.
local ROLE = ns.Skin.Memory()   -- "health" | "power", for a bar itself
local POINT_BASE = ns.Skin.Memory()  -- a font string's native anchor
local HOOKED = ns.Skin.Memory() -- the bar is already on the ledger
local LABEL = ns.Skin.Memory()  -- the bar's value label, once found

-- The rule for writing a number is the core's (ns.Format, which is also
-- Darken:GetFormat(), contract version 12). There is not one threshold, not
-- one format string and not one rounding of our own left here.
--
-- They used to be here, and they are exactly what diverged from the info
-- panel's cell: the bar wrote 12.4k, the cell beneath it 12k, and 999,999 was
-- 1.0m to one and 1000.0k to the other. The rule was taken from this
-- subsystem letter for letter — the thresholds, the format strings and the
-- truncation of the fractional part below a thousand — so not one number
-- shifted on screen.
--
-- The core's file is listed in Darken.toc above this one, so the table is in
-- place by the time this is read. There is no point fetching it through a
-- global: it is the same addon.
local Format = ns.Format

-- A unit frame's bars and their role in the settings. Candidates rather than
-- facts: the field is named differently in different builds, and whatever is
-- absent is silently skipped. The paths are written with dots and parsed by
-- ns.Fonts.Field — the same way the fonts subsystem reaches these objects.
local BARS = {
    { role = "health", paths = { "healthbar", "healthBar", "HealthBar" } },
    { role = "power",  paths = { "manabar", "manaBar", "ManaBar",
                                "powerBar", "PowerBar" } },
}

-- The value's font string inside a bar.
local TEXT_PATHS = { "TextString" }

-- The value's formats. An array rather than a map: the order of the list's
-- rows is set here, and the native look stands first by the addon's general
-- rule.
local FORMATS = {
    { key = NATIVE,    label = "Game's Own Bar Text" },
    { key = "value",   label = "Number" },
    { key = "percent", label = "Percent" },
    { key = "both",    label = "Number and Percent" },
}

-- The label's positions on a bar.
--
-- The list is exposed under a name (Texts.POSITIONS) because the position of
-- the label on the cast bar lives by the same list (Modules/CastBar.lua):
-- "where on a bar the text stands" is one and the same question, and the words
-- of its answer in two sections have to match the player's to the letter. A
-- second table just like it beside this one would diverge from it silently —
-- first in the order of the rows, then in a word.
local POSITIONS = {
    { key = NATIVE,   label = "Game's Own Position" },
    { key = "left",   label = "Left Edge" },
    { key = "center", label = "Center" },
    { key = "right",  label = "Right Edge" },
}
Texts.POSITIONS = POSITIONS

--- The label's inset from a bar's edge.
--
-- From the skin's scale of insets (ns.Skin.Metrics.edge) rather than as a
-- number: "how far to push a label from the edge so that it does not merge
-- with the border" is one quantity for the whole addon, and it used to be
-- written as four numbers in three subsystems. Version 12 of the contract
-- introduced the name in the scale, and this is the first of the four to adopt
-- it.
--
-- Asked for in place rather than remembered while the file is read: the
-- contract's rule is one for the colour, the font and the inset, and a
-- remembered scale would outlive its own edit silently.
--
-- The two stays the answer only to "there is no skin at all" — the tests of
-- the pure functions, which have no core beside them, take that path. It is
-- not a second record of the quantity: it adds up with the first nowhere and
-- is compared with it nowhere, and stands in for a missing answer.
-- @return number
local function Edge()
    local metrics = ns.Skin and ns.Skin.Metrics
    local value = metrics and tonumber(metrics.edge)
    return value or 2
end

--- Shorten a large number.
--
-- The name is kept: Texts.Number uses it, and a test compares it with the
-- core's by the identity of the function rather than by matching answers. It
-- has no body: the shortening is entirely the core's (Core/Format.lua).
--
-- @param value number|nil
-- @return string|nil such as 12.4k; nil when there is nothing to shorten
Texts.Abbreviate = Format.Abbreviate

--- The number for a label: shortened or in full.
--
-- Both paths are the core's, and neither has a body of its own here. In full
-- is ns.WholeNumber, the very rule the core writes a number below a thousand
-- by: the fractional part is truncated towards zero and the sign stands
-- outside the "%d".
--
-- It used to be written here a second time. Both records agreed on every
-- number — which is why a comparison of answers kept quiet, and not one of the
-- eleven scans of past knowledge looked for this sign. They would have
-- diverged on the day one of the two was edited: 999.9 would be written as
-- 1000 with shortening and as 999 without it — one label, one value, two
-- answers.
--
-- @param value number|nil
-- @param abbreviate boolean|nil
-- @return string
function Texts.Number(value, abbreviate)
    local number = tonumber(value) or 0

    if abbreviate then
        return Texts.Abbreviate(number) or "0"
    end

    return ns.WholeNumber(number)
end

--- The share of the maximum, as a percentage.
--
-- The same again: the name is ours, the rule is the core's. A maximum equal to
-- zero gives zero per cent — that is the core's decision, and it is the same
-- one that stood here: a bar with a zero maximum turns up on a unit outside
-- one's field of view and on a class without a resource, that is, constantly.
--
-- The core's rounding is symmetric: a half travels away from zero on both
-- sides. What used to stand here rounded by adding a half, which gave -12 for
-- -12.5% and 13 for +12.5%. Negative percentages do not occur on a bar, so
-- nothing of this is visible on screen.
--
-- @param current number|nil
-- @param maximum number|nil
-- @return number a whole number of per cent
Texts.Percent = Format.Percent

--- The label on a bar, from the pair "current and maximum".
--
-- A pure function and the only place where this decision is made. A nil means
-- "do not touch": the native look was chosen, and the label stays the one the
-- game put there. An empty string instead of a nil would wipe the native label
-- and would look like a failure of the addon.
--
-- @param current number|nil
-- @param maximum number|nil
-- @param format string|nil the format's key
-- @param abbreviate boolean|nil whether to shorten large numbers
-- @return string|nil
function Texts.FormatValue(current, maximum, format, abbreviate)
    if format == "value" then
        return Texts.Number(current, abbreviate) .. "/"
            .. Texts.Number(maximum, abbreviate)
    end

    if format == "percent" then
        return string.format("%d%%", Texts.Percent(current, maximum))
    end

    if format == "both" then
        return Texts.Number(current, abbreviate) .. "/"
            .. Texts.Number(maximum, abbreviate) .. " "
            .. string.format("%d%%", Texts.Percent(current, maximum))
    end

    return nil
end

--- The label's anchor for the chosen position.
--
-- A pure function. A nil means "do not move": the native look was chosen, and
-- the anchor has to be restored from memory rather than computed.
--
-- The inset's sign is the side one is pushed away from rather than a different
-- quantity: from the left edge the label goes right, from the right edge left,
-- and the number is one for both.
--
-- @param position string|nil the position's key
-- @return string|nil the point on the label
-- @return string|nil the point on the bar
-- @return number|nil the horizontal offset
-- @return number|nil the vertical offset
-- The game's own console variables for the text on a bar.
--
-- === Why this subsystem writes nothing on a bar ===
--
-- The game already has this setting. It shows the value on every bar it
-- draws, in one of three shapes, and it does it from inside its own update -
-- the only place that knows the number, knows when it changed and is allowed
-- to touch a protected frame's label.
--
-- This subsystem used to write the label itself: find the bar, find its font
-- string, hook whatever function the client writes values with, rewrite
-- after it, move it, show the label the game had hidden. Every one of those
-- is a guess at somebody else's build, every one was spelt differently on
-- this client line, and together they managed to break the game's own text
-- as well as never showing ours - which is what the author reported, in
-- those words.
--
-- So the setting does what he asked for in the first place: it turns the
-- game's own on and chooses its shape. "Number and Percent" is the game's
-- BOTH, which puts the percentage at the left end of the bar and the number
-- at the right - the two of them apart, which is the other thing he asked
-- for. Nothing of the game's is touched until he picks a shape, and picking
-- "the game's own" back puts the variables to the value the client itself
-- calls default.
local CVAR_SHOW = "statusText"
local CVAR_SHAPE = "statusTextDisplay"

-- Our formats in the game's words.
local SHAPES = {
    value   = "NUMERIC",
    percent = "PERCENT",
    both    = "BOTH",
}

--- What the console variables should hold for these settings.
--
-- A pure function, and nil means "the client's own default" - which is how
-- "as in the game" is written everywhere in this addon.
--
-- The game shows one shape on every bar it draws; there is no separate
-- switch for health and for power. Between two different choices the health
-- one is taken, and the settings page says so.
--
-- @param settings table|nil
-- @return string|nil what statusText should hold
-- @return string|nil what statusTextDisplay should hold
function Texts.Wanted(settings)
    if type(settings) ~= "table" then return nil, nil end

    local chosen = nil
    local health, power = settings.health, settings.power
    if health ~= nil and health ~= NATIVE and SHAPES[health] then
        chosen = SHAPES[health]
    elseif power ~= nil and power ~= NATIVE and SHAPES[power] then
        chosen = SHAPES[power]
    end

    if chosen == nil then return nil, nil end
    return "1", chosen
end

-- Where a label may be put, in the game's words.
local SIDE_POINT = { left = "LEFT", center = "CENTER", right = "RIGHT" }

-- A label's own anchor, read once before we move it and never again:
-- otherwise "as the game had it" would restore our previous move rather than
-- the game's placing.
local POINT_BASE = ns.Skin.Memory()

--- The anchor the game gave a label.
-- @param label table the font string
-- @return table|nil { point, relativeTo, relativePoint, x, y }
function Texts.BasePoint(label)
    if type(label) ~= "table" then return nil end

    local base = POINT_BASE[label]
    if base ~= nil then
        if base == false then return nil end
        return base
    end

    if type(label.GetPoint) ~= "function" then
        POINT_BASE[label] = false
        return nil
    end

    local ok, point, relativeTo, relativePoint, x, y =
        pcall(label.GetPoint, label, 1)
    if not ok or type(point) ~= "string" then
        POINT_BASE[label] = false
        return nil
    end

    base = { point, relativeTo, relativePoint, x or 0, y or 0 }
    POINT_BASE[label] = base
    return base
end

--- Sort a bar's labels by where the game itself put them.
--
-- The classification comes from the game's own placing rather than from a
-- field's name, and that is the point: the names differ between client
-- lines, the layout does not. In the game's two-ended shape the percentage
-- stands at the left end and the number at the right - that is its own code,
-- not a guess - while the single-valued shapes use the one in the middle.
--
-- @param bar table
-- @return table|nil the label at the left end
-- @return table|nil the one at the right end
-- @return table|nil the one in the middle
function Texts.Sort(bar)
    if type(bar) ~= "table" then return nil, nil, nil end
    if type(bar.GetRegions) ~= "function" then return nil, nil, nil end

    local ok, regions = pcall(function() return { bar:GetRegions() } end)
    if not ok or type(regions) ~= "table" then return nil, nil, nil end

    local left, right, middle = nil, nil, nil
    for i = 1, #regions do
        local region = regions[i]
        if type(region) == "table"
            and type(region.SetText) == "function"
            and type(region.GetPoint) == "function" then
            local base = Texts.BasePoint(region)
            local point = base and base[1] or nil

            if point == "LEFT" and left == nil then
                left = region
            elseif point == "RIGHT" and right == nil then
                right = region
            elseif middle == nil then
                middle = region
            end
        end
    end

    return left, right, middle
end

--- Put one label where the player asked, or back where the game had it.
--
-- Moving a region of a protected frame is a protected operation and is
-- refused in combat; the caller defers it. Nothing is written into the label
-- and nothing is shown or hidden: what it says and whether it says anything
-- is the game's business.
--
-- @param label table|nil the font string
-- @param bar table the bar it belongs to
-- @param side string|nil "left", "center", "right", or the native marker
-- @return boolean whether the label was moved
function Texts.MoveLabel(label, bar, side)
    if type(label) ~= "table" or type(bar) ~= "table" then return false end
    if type(label.SetPoint) ~= "function" then return false end
    if type(label.ClearAllPoints) ~= "function" then return false end

    local base = Texts.BasePoint(label)

    local point = SIDE_POINT[side]
    if point == nil then
        -- Back to the game's own placing, which is only possible if we read
        -- it before the first move.
        if base == nil then return false end
        if not pcall(label.ClearAllPoints, label) then return false end
        return pcall(label.SetPoint, label, base[1], base[2], base[3],
            base[4], base[5]) == true
    end

    local inset = Edge()
    local x = 0
    if point == "LEFT" then x = inset end
    if point == "RIGHT" then x = -inset end

    if not pcall(label.ClearAllPoints, label) then return false end
    return pcall(label.SetPoint, label, point, bar, point, x, 0) == true
end

--- Which of a bar's labels carries the percentage and which the number.
--
-- A pure function of the shape the game was asked for: in the two-ended
-- shape the percentage is at the left end and the number at the right, in
-- the single-valued shapes there is one label in the middle and it carries
-- whichever was asked for.
--
-- @param shape string|nil the game's shape (NUMERIC, PERCENT, BOTH)
-- @param left table|nil
-- @param right table|nil
-- @param middle table|nil
-- @return table|nil the label with the percentage
-- @return table|nil the label with the number
function Texts.Carriers(shape, left, right, middle)
    if shape == "BOTH" then return left, right end
    if shape == "PERCENT" then return middle, nil end
    if shape == "NUMERIC" then return nil, middle end
    return nil, nil
end

--- Apply the settings to the game's own console variables.
--
-- The client's functions arrive as an argument rather than out of _G, as
-- they do for the fonts' physics: that way this is checked outside the game,
-- and a client without one of them is an ordinary answer rather than an
-- error.
--
-- Nothing is written while a variable already holds the wanted value, so a
-- fresh install writes nothing at all.
--
-- @param settings table|nil
-- @param api table|nil { Get, Set, Default }
-- @return number how many variables were written
function Texts.ApplyGame(settings, api)
    if type(api) ~= "table" then
        api = { Get = GetCVar, Set = SetCVar, Default = GetCVarDefault }
    end
    if type(api.Get) ~= "function" or type(api.Set) ~= "function" then
        return 0
    end

    local show, shape = Texts.Wanted(settings)
    local wanted = { [CVAR_SHOW] = show, [CVAR_SHAPE] = shape }
    local written = 0

    for _, name in ipairs({ CVAR_SHOW, CVAR_SHAPE }) do
        local want = wanted[name]

        if want == nil and type(api.Default) == "function" then
            local told, value = pcall(api.Default, name)
            if told and type(value) == "string" and value ~= "" then
                want = value
            end
        end

        if want ~= nil then
            -- An empty answer means the variable does not exist on this
            -- client: there is nowhere to write, and that is not an error.
            local read, current = pcall(api.Get, name)
            if read and type(current) == "string" and current ~= want then
                if pcall(api.Set, name, want) then written = written + 1 end
            end
        end
    end

    return written
end

-- The default settings: everything at the game's native look. A fresh install
-- changes not one letter on the bars until the player asks.
Texts.defaults = {
    health    = NATIVE,
    power     = NATIVE,

    -- Where each of the two stands. The game's own placing until the player
    -- says otherwise, like everything else here.
    percentAt = NATIVE,
    valueAt   = NATIVE,
}

--- The subsystem's settings from the profile.
-- @return table|nil
local function Settings()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    if not profile then return nil end
    return profile[Texts.name]
end

--- Whether a fight is on.
-- Outside the game the function does not exist — then there is no combat and
-- nothing to defer.
-- @return boolean
local function inCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, locked = pcall(InCombatLockdown)
    return ok and locked and true or false
end

--- The subsystem's queue of deferred changes.
-- Taken from the unit frames: the rule "a repeated write evicts the former
-- one, keeping its place in the queue" is written and tested there, and it
-- must have no second copy. The unit frames subsystem may not be loaded (the
-- test suite loads the files one at a time) — then there is no queue and
-- nothing to defer.
-- @return table|nil the queue, table|nil the unit frames module
local function Queue()
    local frames = ns.UnitFrames
    if type(frames) ~= "table" or type(frames.NewQueue) ~= "function" then
        return nil, nil
    end
    if Texts.queue == nil then
        Texts.queue = frames.NewQueue()
    end
    return Texts.queue, frames
end
Texts.Queue = Queue

--- Fetch an object by a path out of a list of candidates.
-- ns.Fonts.Field parses the path: there must be no second path parser in the
-- addon.
-- @param root table|nil
-- @param paths table array of dotted paths
-- @param method string the name of a method the object found must have
-- @return table|nil
local function field(root, paths, method)
    local fonts = ns.Fonts
    if type(fonts) ~= "table" or type(fonts.Field) ~= "function" then
        return nil
    end

    for i = 1, #paths do
        local object = fonts.Field(root, paths[i])
        if type(object) == "table" and type(object[method]) == "function" then
            return object
        end
    end
    return nil
end
Texts.Field = field

--- Apply the settings.
--
-- The only path of application: entering the game, changing the profile and
-- editing any setting all lead here.
--
-- The frames are taken from the compatibility layer: it returns only those
-- that exist on this client. There are no checks of the client's version
-- here.
--- Put the game's labels where the player asked.
--
-- The text itself stays the game's: this moves what the game draws and
-- writes nothing. A bar whose labels cannot be found keeps the game's
-- layout, which is the right failure - the values are still there.
--
-- @param settings table
-- @param globals table|nil name -> object, _G by default
-- @return number how many labels were moved
function Texts.Arrange(settings, globals)
    if type(settings) ~= "table" then return 0 end
    if type(globals) ~= "table" then globals = _G end

    local percentAt = settings.percentAt
    local valueAt = settings.valueAt
    if (percentAt == nil or percentAt == NATIVE)
        and (valueAt == nil or valueAt == NATIVE)
        and next(POINT_BASE) == nil then
        -- Nothing asked for and nothing moved before: not one label of the
        -- game's is touched.
        return 0
    end

    local _, shape = Texts.Wanted(settings)
    local combat = inCombat()
    local moved = 0

    local names = ns.Compat.Resolve("unitframe")
    for i = 1, #names do
        local frame = globals[names[i]]
        if type(frame) == "table" then
            for j = 1, #BARS do
                local bar = field(frame, BARS[j].paths, "GetValue")
                if bar ~= nil then
                    local left, right, middle = Texts.Sort(bar)
                    local percent, value =
                        Texts.Carriers(shape, left, right, middle)

                    local work = {
                        { label = percent, side = percentAt },
                        { label = value, side = valueAt },
                    }
                    for k = 1, #work do
                        local item = work[k]
                        if item.label ~= nil then
                            if combat then
                                local queue, frames = Queue()
                                if queue then
                                    frames.Enqueue(queue,
                                        "place:" .. names[i] .. ":" .. k,
                                        function()
                                            Texts.MoveLabel(item.label, bar,
                                                item.side)
                                        end)
                                end
                            elseif Texts.MoveLabel(item.label, bar, item.side)
                            then
                                moved = moved + 1
                            end
                        end
                    end
                end
            end
        end
    end

    return moved
end

function Texts:ApplySettings()
    local settings = Settings()
    if not settings then return end

    -- The game's own setting, turned on and given a shape. Not one label of
    -- the game's is written - see the note above CVAR_SHOW for what used to
    -- be here and why it went.
    Texts.ApplyGame(settings)

    -- And the game's own labels put where the player asked, which is the
    -- one thing the game's setting cannot do for him.
    Texts.Arrange(settings)
end

--- Enabling the subsystem.
--
-- Here and only here are the subscriptions and the shared handler created.
--
-- TextStatusBar_UpdateTextString is the one function of the game that writes
-- the values onto the bars. The handler on top of it receives the very bar the
-- game has just updated and rewrites the label behind it. The function may be
-- absent (a build in which it was renamed) — then what remains is the event
-- path below, because Texts.Hook only keeps the ledger.
function Texts:OnEnable()
    -- The subscription goes through the core's door (ns.Events) rather than
    -- through AceEvent. The reason was measured rather than guessed: AceEvent
    -- stores one handler per "event + object" pair, and the object is one and
    -- the same for every subsystem of the core — ns.Addon. Five subsystems
    -- asked for PLAYER_ENTERING_WORLD and four for PLAYER_REGEN_ENABLED, and
    -- exactly the last one registered survived in each pair; the other
    -- subscriptions vanished silently. The core's door stores a subscription
    -- under the subsystem's name, so they cannot collide.
    --
    -- The door can be absent only where it was not loaded (the tests of a
    -- single subsystem); in the game it is always there.
    local me = ns.Registry:NameOf(Texts)
    if type(ns.Events) ~= "table" or me == nil then return end

    -- Leaving combat is the only moment when what was deferred can be
    -- applied.
    ns.Events.Subscribe("PLAYER_REGEN_ENABLED", me, function()
        local queue, frames = Queue()
        if queue then frames.Drain(queue) end
    end)

    -- A change of target or focus slips another unit into the same frame:
    -- the label has to be placed afresh. Each event is subscribed to
    -- separately and under a guard: the engine meets an event that does not
    -- exist on this client with an error, and losing every other subscription
    -- because of one name is not allowed.
    local events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED",
        "UNIT_PET",
        "GROUP_ROSTER_UPDATE",
        "PARTY_MEMBERS_CHANGED",
    }
    for i = 1, #events do
        ns.Events.Subscribe(events[i], me, function()
            Texts:ApplySettings()
        end)
    end

end

--- A list's labels and order from an array of { key, label } records.
-- @param list table
-- @return function the values, function the order
local function listFrom(list)
    return function()
        local values = {}
        for i = 1, #list do
            values[list[i].key] = ns.Localize(list[i].label)
        end
        return values
    end,
    function()
        local keys = {}
        for i = 1, #list do keys[i] = list[i].key end
        return keys
    end
end

local formatValues,   formatSorting   = listFrom(FORMATS)

--- The get/set handlers for a plain settings field.
-- @param field_ string
-- @return function, function
local function handlers(field_)
    return function()
        local settings = Settings()
        return settings and settings[field_]
    end,
    function(_, value)
        local settings = Settings()
        if not settings then return end
        settings[field_] = value
        Texts:ApplySettings()
    end
end

local getHealth,    setHealth    = handlers("health")
local getPower,     setPower     = handlers("power")
local getPercentAt, setPercentAt = handlers("percentAt")
local getValueAt,   setValueAt   = handlers("valueAt")

local positionValues, positionSorting = listFrom(POSITIONS)

Texts.options = {
    type = "group",
    name = ns.Localize("Bar Text"),
    args = {
        health = {
            type = "select",
            order = 1,
            width = "full",
            name = ns.Localize("Health Bar Value"),
            desc = ns.Localize("What the bars say. The first entry leaves " ..
                "it to the game. Any other turns the game's own bar text " ..
                "on and chooses its shape - number, percentage, or both, " ..
                "which puts the percentage at the left end of the bar and " ..
                "the number at the right. The game shows one shape on " ..
                "every bar it draws, so this choice decides for the " ..
                "resource bar as well."),
            values = formatValues,
            sorting = formatSorting,
            get = getHealth,
            set = setHealth,
        },
        power = {
            type = "select",
            order = 2,
            width = "full",
            name = ns.Localize("Power Bar Value"),
            desc = ns.Localize("Mana, rage, energy. The game has one " ..
                "setting for every bar, so this one is used when the " ..
                "health bar is left to the game."),
            values = formatValues,
            sorting = formatSorting,
            get = getPower,
            set = setPower,
        },
        percentAt = {
            type = "select",
            order = 3,
            width = "full",
            name = ns.Localize("Percentage Position"),
            desc = ns.Localize("Where the percentage stands. The game " ..
                "writes the text; this moves what it wrote, so the two " ..
                "values can stand at the two ends of the bar or anywhere " ..
                "else you put them. Moving text on a unit frame is a " ..
                "protected operation: a change made in combat is applied " ..
                "as soon as combat ends."),
            values = positionValues,
            sorting = positionSorting,
            get = getPercentAt,
            set = setPercentAt,
        },
        valueAt = {
            type = "select",
            order = 4,
            width = "full",
            name = ns.Localize("Number Position"),
            desc = ns.Localize("The same for the number."),
            values = positionValues,
            sorting = positionSorting,
            get = getValueAt,
            set = setValueAt,
        },
    },
}

--============================================================================
-- The settings page, declared as data
--============================================================================

if type(ns.Schema) == "table" then
    local Schema = ns.Schema
    local PAGE = "texts"

    Schema.Page(PAGE, {
        title = "Bar Text",
        order = 7,
        section = "texts",
    })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "The numbers written across the health and power bars. The "
            .. "first entry in every list is the game's own.",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Health Text",
        path = { "health" },
        apply = "texts",
        hint = "What the bars say. The game's own setting is turned on and "
            .. "given this shape; both puts the percentage at the left end "
            .. "of the bar and the number at the right. One shape goes to "
            .. "every bar the game draws.",
        values = formatValues,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Power Text",
        path = { "power" },
        apply = "texts",
        hint = "Used when the health bar is left to the game: the game "
            .. "has one setting for every bar it draws.",
        values = formatValues,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Percentage Position",
        path = { "percentAt" },
        apply = "texts",
        hint = "Where the percentage stands. The game writes the text; "
            .. "this moves what it wrote.",
        values = positionValues,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Number Position",
        path = { "valueAt" },
        apply = "texts",
        hint = "The same for the number, so the two can stand apart.",
        values = positionValues,
    })

end

ns.Registry:Register(Texts)
