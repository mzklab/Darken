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
counters.hooked_texts = counters.hooked_texts or 0
counters.fired_texts  = counters.fired_texts  or 0
counters.absent_texts = counters.absent_texts or 0

--- The names of the game's functions that write a bar's value.
--
-- The names themselves live in the compatibility layer, which is the one
-- place in this addon that knows the game's own names: a second list here
-- would diverge from it silently, and a list diverged from the client makes
-- no complaint - the subsystem simply stops working.
--
-- ALL the ones found are taken rather than the first that turns up: the
-- inner one is not called from the outer one on every line, and hooking the
-- outer one alone can miss the updates that go through the inner one.
--
-- @return table array of declared names
function Texts.Writers()
    if type(ns.Compat) ~= "table"
        or type(ns.Compat.GetFrameNames) ~= "function" then
        return {}
    end
    return ns.Compat.GetFrameNames(ns.flavor, "bar-text-write")
end

-- What was not found. The report needs it: "zero hooks" and "there are no
-- hooks because no such functions exist on this client" are different
-- troubles, and they are cured differently.
Texts.MISSING = {}

-- The names of the game's functions whose hooks have already been
-- counted.
local counted = {}

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
function Texts.Anchor(position)
    local edge = Edge()
    if position == "left"   then return "LEFT",   "LEFT",    edge, 0 end
    if position == "center" then return "CENTER", "CENTER",  0,    0 end
    if position == "right"  then return "RIGHT",  "RIGHT",  -edge, 0 end
    return nil
end

-- The default settings: everything at the game's native look. A fresh install
-- changes not one letter on the bars until the player asks.
Texts.defaults = {
    health     = NATIVE,
    power      = NATIVE,
    abbreviate = false,
    position   = NATIVE,
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

--- The font string a bar writes its value on.
--
-- Why a field is not enough. The game's bar template keeps three labels
-- under keys of its own - the central one, the left one and the right one -
-- and the central one is the value. That is true wherever the template is
-- used, and on a line that builds its unit frames differently it is true of
-- nothing: the player frame of 1.60.1 is assembled by its own code, and the
-- key the template would have given is not there.
--
-- So the key is asked for first, and where there is none the bar is asked
-- for its own regions. A font string lying on a bar is the bar's text: this
-- is not a search through somebody else's tree but one question to one
-- object, and it is asked once per bar.
--
-- Of several the central one is taken, by the same rule the template
-- follows: the value stands in the middle, the percentage on the left and
-- the number on the right. With no anchor to judge by the first is taken -
-- a bar with one label has no second candidate to confuse it with.
--
-- @param bar table
-- @return table|nil the font string
function Texts.Label(bar)
    if type(bar) ~= "table" then return nil end

    local known = LABEL[bar]
    if known ~= nil then
        if known == false then return nil end
        return known
    end

    local found = field(bar, TEXT_PATHS, "SetText")

    if found == nil and type(bar.GetRegions) == "function" then
        local ok, regions = pcall(function() return { bar:GetRegions() } end)
        if ok and type(regions) == "table" then
            local first = nil
            for i = 1, #regions do
                local region = regions[i]
                if type(region) == "table"
                    and type(region.SetText) == "function"
                    and type(region.GetPoint) == "function" then
                    if first == nil then first = region end

                    local seen, point = pcall(region.GetPoint, region, 1)
                    if seen and point == "CENTER" then
                        found = region
                        break
                    end
                end
            end
            if found == nil then found = first end
        end
    end

    LABEL[bar] = found or false
    return found
end

-- Which group of the layer answers for which bar of which frame.
local CLIENT_BARS = {
    PlayerFrame = {
        health = "player-health-bar",
        power  = "player-power-bar",
    },
}

--- Ask the client itself for a bar.
--
-- A frame keeps its bars where its own build keeps them, and a list of
-- field spellings is a guess at that. Where the client offers a function
-- that returns the bar, the guess is unnecessary: the answer comes from the
-- same place the game's own code gets it.
--
-- @param frame string the frame's name
-- @param role string the bar's role
-- @return table|nil
function Texts.AskClient(frame, role)
    local groups = CLIENT_BARS[frame]
    if groups == nil then return nil end

    local group = groups[role]
    if group == nil then return nil end

    if type(ns.Compat) ~= "table"
        or type(ns.Compat.ResolveFunction) ~= "function" then
        return nil
    end

    local got, ask = pcall(ns.Compat.ResolveFunction, group)
    if not got or type(ask) ~= "function" then return nil end

    local fine, bar = pcall(ask)
    if not fine or type(bar) ~= "table" then return nil end
    if type(bar.GetValue) ~= "function" then return nil end

    return bar
end

--- The label's remembered native anchor.
-- Read once, before our first move, and unchanged after that: otherwise "the
-- native position" would restore our previous one rather than the native
-- one.
-- @param label table|nil the font string
-- @return table|nil { point, object, the object's point, x, y }
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

    local ok, point, relativeTo, relativePoint, x, y = pcall(label.GetPoint, label, 1)
    if not ok or type(point) ~= "string" then
        POINT_BASE[label] = false
        return nil
    end

    base = { point, relativeTo, relativePoint, x or 0, y or 0 }
    POINT_BASE[label] = base
    return base
end

--- Move the label.
--
-- A function of its own because it is called by two paths: at once out of
-- combat and from the queue after combat. Both paths have to do exactly the
-- same thing.
--
-- @param label table the font string
-- @param bar table the bar
-- @param position string|nil the position's key
-- @param show boolean|nil whether to show the label
-- @return boolean whether the object was touched
function Texts.Place(label, bar, position, show)
    if type(label) ~= "table" then return false end

    local base = Texts.BasePoint(label)
    local point, relativePoint, x, y = Texts.Anchor(position)

    local touched = false

    if point then
        if type(label.ClearAllPoints) == "function" then
            pcall(label.ClearAllPoints, label)
        end
        touched = pcall(label.SetPoint, label, point, bar, relativePoint, x, y)
            or touched
    elseif base then
        -- The native position is restored by exactly what was read: the
        -- anchor's object stays somebody else's, we do not choose it.
        if type(label.ClearAllPoints) == "function" then
            pcall(label.ClearAllPoints, label)
        end
        touched = pcall(label.SetPoint, label, base[1], base[2], base[3],
            base[4], base[5]) or touched
    end

    -- Showing the label. The game hides it when the display of values is
    -- switched off in the game's own settings; a player who chose a format
    -- asked for the opposite.
    if show and type(label.Show) == "function" then
        touched = pcall(label.Show, label) or touched
    end

    return touched
end

--- Whether the label has to be touched at all.
--
-- Three cases where it does: it was asked to be shown, it was asked to be
-- moved, or we have already moved it and are now restoring the native
-- position. In every other case the game's object is not touched at all — a
-- fresh install moves not one label, and in combat no work that changes
-- nothing lands in the queue.
--
-- @param label table|nil the font string
-- @param position string|nil the position's key
-- @param show boolean|nil whether to show the label
-- @return boolean
function Texts.NeedsPlace(label, position, show)
    if type(label) ~= "table" then return false end
    if show then return true end
    if Texts.Anchor(position) then return true end
    return type(POINT_BASE[label]) == "table"
end

--- Bring one bar's label into line with the settings.
--
-- Called both from ApplySettings and from the handlers by which the game
-- updates these same strings. The bar does not care what changed — a setting
-- or the health.
--
-- @param bar table|nil the bar
-- @return boolean whether we wrote anything
--- Say which value a bar carries.
--
-- The pass records this as it meets each bar: the game's handler hands us
-- the bar itself rather than a name, so the role has to be remembered
-- against the object. Exposed because a check needs to set it without
-- running the whole pass.
--
-- @param bar table
-- @param role string|nil
function Texts.Role(bar, role)
    if type(bar) ~= "table" then return end
    ROLE[bar] = role
end

function Texts.Refresh(bar)
    if type(bar) ~= "table" then return false end

    local role = ROLE[bar]
    if type(role) ~= "string" then return false end

    local settings = Settings()
    if not settings then return false end

    local format = settings[role]
    if format == nil or format == NATIVE then return false end

    local label = Texts.Label(bar)
    if not label then return false end

    if type(bar.GetValue) ~= "function"
        or type(bar.GetMinMaxValues) ~= "function" then
        return false
    end

    local okValue, current = pcall(bar.GetValue, bar)
    local okRange, _, maximum = pcall(bar.GetMinMaxValues, bar)
    if not okValue or not okRange then return false end

    local text = Texts.FormatValue(current, maximum, format, settings.abbreviate)
    if text == nil then return false end

    local wrote = pcall(label.SetText, label, text)

    -- And shown, because the game has just hidden it.
    --
    -- The game draws a bar's value only while the cursor is over the bar,
    -- unless the player says otherwise in its own options. It hides the
    -- label inside the very function this one is hooked to - so writing the
    -- text and stopping there left a correct string on a hidden label, and
    -- the values appeared on hover and nowhere else.
    --
    -- A player who has chosen a format has asked for the opposite, and that
    -- is the whole of the setting.
    --
    -- Showing a region of a protected frame is forbidden in combat, so in a
    -- fight it waits. The text itself is contents rather than visibility and
    -- is written immediately, in a fight too.
    if type(label.IsShown) == "function" and type(label.Show) == "function" then
        local seen, shown = pcall(label.IsShown, label)
        if seen and shown == false then
            if ns.Combat and ns.Combat.InCombat and ns.Combat.InCombat() then
                ns.Combat.Enqueue(ns.Combat.QueueFor(Texts.name), label,
                    function() pcall(label.Show, label) end)
            else
                pcall(label.Show, label)
            end
        end
    end

    return wrote
end

--- Take a bar onto the ledger. Doing nothing to it in the process.
--
-- === Why there is no longer a hook on the bar itself ===
--
-- There were two, and both turned out to be wrong — each in its own way, and
-- both on one and the same object: the health bar of the target and of the
-- player.
--
-- The first was a HookScript for OnValueChanged. HookScript stitches our
-- handler and the frame's handler into ONE, and it is our addon that stitches
-- it: the bar's whole handler has been ours ever since, and the engine
-- considers tainted every execution that passes through it. The author saw
-- that as a line saying the execution had been tainted by Darken.
--
-- The second, which I replaced it with, was a secure hook on the bar's
-- SetValue method. It looked correct: a protected hook instead of stitching.
-- But a hook on an OBJECT'S METHOD works differently from one on a global
-- function: it puts a SetValue field with its own wrapper onto the object
-- itself. That is, a write onto a foreign frame — precisely what this addon
-- has declared inadmissible and cleaned out of twelve places. The game then
-- failed on its own update of the bar — "attempt to call a nil value" — with
-- fifteen hundred errors and an interface with no bars.
--
-- What remains is what had been the main path from the start: a protected hook
-- on the game's FUNCTION that writes the values onto the bars
-- (TextStatusBar_UpdateTextString, see OnEnable). It touches not one bar and
-- instead receives the one the game has just updated.
--
-- What that costs, honestly: on a build where no such function exists the
-- labels will update not at that instant but on an event — a change of target,
-- entering the world, a change of the group's composition. That is cheaper
-- than a bar the game itself fails on.
--
-- The ledger nevertheless stays: by it the subsystem knows whose labels it has
-- already moved.
--
-- @param bar table
-- @return boolean whether it was taken onto the ledger now
function Texts.Hook(bar)
    if type(bar) ~= "table" then return false end
    if HOOKED[bar] then return false end

    HOOKED[bar] = true
    return true
end

--- Apply the settings.
--
-- The only path of application: entering the game, changing the profile and
-- editing any setting all lead here.
--
-- The frames are taken from the compatibility layer: it returns only those
-- that exist on this client. There are no checks of the client's version
-- here.
function Texts:ApplySettings()
    local settings = Settings()
    if not settings then return end

    local combat = inCombat()
    local names = ns.Compat.Resolve("unitframe")

    for i = 1, #names do
        local name = names[i]
        local frame = _G[name]

        if type(frame) == "table" then
            for j = 1, #BARS do
                local entry = BARS[j]
                local bar = field(frame, entry.paths, "GetValue")

                -- The client asked directly, where a field answers nothing.
                --
                -- On this line the player frame keeps no bar in a field and
                -- none exists as a global - there is no PlayerFrameHealthBar
                -- at all. The client does have a function that returns the
                -- bar, and that answer does not depend on where the frame
                -- happens to keep it.
                if bar == nil then
                    bar = Texts.AskClient(name, entry.role)
                end

                if bar then
                    -- The role is recorded for the bar itself: the game's
                    -- handler gives us the object rather than a name, so no
                    -- second "object -> role" table had to be created.
                    ROLE[bar] = entry.role

                    -- A label's contents are not protected by the engine:
                    -- they are applied at once, in the middle of a fight
                    -- too.
                    Texts.Hook(bar)
                    Texts.Refresh(bar)

                    local label = Texts.Label(bar)
                    local format = settings[entry.role]
                    local show = format ~= nil and format ~= NATIVE

                    if Texts.NeedsPlace(label, settings.position, show) then
                        -- The position and the display are protected
                        -- operations on a region of a protected frame. In
                        -- combat they are deferred.
                        if combat then
                            local queue, frames = Queue()
                            if queue then
                                frames.Enqueue(queue,
                                    "place:" .. name .. ":" .. entry.role,
                                    function()
                                        Texts.Place(label, bar,
                                            settings.position, show)
                                    end)
                            end
                        else
                            Texts.Place(label, bar, settings.position, show)
                        end
                    end
                end
            end
        end
    end
end

--- What the subsystem found on this client, in words.
--
-- Why it exists. Everything this subsystem does rests on three answers from
-- the client, and all three differ between builds: where the frame keeps its
-- bar, where the bar keeps its label, and what the game calls to write the
-- value. When one of them is missing the result on screen is the same in
-- every case - an empty bar with a format chosen - and the three are cured by
-- three different things. So they are reported apart.
--
-- It reads the interface and writes nothing to it.
--
-- @param globals table name -> object
-- @return table array of lines
function Texts.Diagnose(globals)
    local lines = {}
    if type(globals) ~= "table" then return lines end

    local settings = Settings()
    lines[#lines + 1] = "health = " .. tostring(settings and settings.health)
        .. ", power = " .. tostring(settings and settings.power)

    for _, name in ipairs(ns.Compat.Resolve("unitframe")) do
        local frame = globals[name]
        if type(frame) == "table" then
            for j = 1, #BARS do
                local entry = BARS[j]

                -- The route to the bar, named rather than counted: a bar
                -- found through a field and one the client handed over are
                -- the same object and a different fact about the build.
                local route, bar = "none", nil
                for i = 1, #entry.paths do
                    local found = field(frame, { entry.paths[i] }, "GetValue")
                    if found ~= nil then
                        route, bar = "field " .. entry.paths[i], found
                        break
                    end
                end
                if bar == nil then
                    bar = Texts.AskClient(name, entry.role)
                    if bar ~= nil then route = "client" end
                end

                local said = "no text object"
                if bar ~= nil then
                    local found = Texts.Label(bar)
                    if found ~= nil then
                        said = field(bar, TEXT_PATHS, "SetText") ~= nil
                            and TEXT_PATHS[1] or "a label on the bar"
                        if type(found.IsShown) == "function" then
                            local seen, shown = pcall(found.IsShown, found)
                            said = said .. (seen and shown and ", shown"
                                or ", hidden")
                        end
                    end
                end

                lines[#lines + 1] = name .. " " .. entry.role .. ": "
                    .. route .. ", " .. said
            end
        end
    end

    local writers = Texts.Writers()
    for i = 1, #writers do
        local name = writers[i]
        lines[#lines + 1] = name .. ": "
            .. (type(globals[name]) == "function" and "present" or "absent")
    end

    lines[#lines + 1] = "hooks taken " .. tostring(counters.hooked_texts)
        .. ", hooks run " .. tostring(counters.fired_texts)

    return lines
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
    if type(hooksecurefunc) == "function" then
        for _, name in ipairs(Texts.Writers()) do
            if type(_G[name]) ~= "function" then
                Texts.MISSING[#Texts.MISSING + 1] = name
                counters.absent_texts = counters.absent_texts + 1
            elseif not counted[name] then
                if pcall(hooksecurefunc, name, function(bar)
                    counters.fired_texts = counters.fired_texts + 1
                    Texts.Refresh(bar)
                end) then
                    counted[name] = true
                    counters.hooked_texts = counters.hooked_texts + 1
                end
            end
        end
    end

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
local positionValues, positionSorting = listFrom(POSITIONS)

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

local getHealth,     setHealth     = handlers("health")
local getPower,      setPower      = handlers("power")
local getAbbreviate, setAbbreviate = handlers("abbreviate")
local getPosition,   setPosition   = handlers("position")

Texts.options = {
    type = "group",
    name = ns.Localize("Bar Text"),
    args = {
        health = {
            type = "select",
            order = 1,
            width = "full",
            name = ns.Localize("Health Bar Value"),
            desc = ns.Localize("What the health bar says. The first entry " ..
                "leaves the text to the game, including the game's own " ..
                "setting for whether to show it at all. Any other choice " ..
                "shows the text even when the game would hide it - that is " ..
                "what choosing a format means."),
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
            desc = ns.Localize("Mana, rage, energy. The first entry leaves " ..
                "the text to the game."),
            values = formatValues,
            sorting = formatSorting,
            get = getPower,
            set = setPower,
        },
        abbreviate = {
            type = "toggle",
            order = 3,
            width = "full",
            name = ns.Localize("Shorten Large Numbers"),
            desc = ns.Localize("Writes 12400 as 12.4k and 2500000 as " ..
                "2.5m. Off by default, because the game writes numbers in " ..
                "full."),
            get = getAbbreviate,
            set = setAbbreviate,
        },
        position = {
            type = "select",
            order = 4,
            width = "full",
            name = ns.Localize("Value Position"),
            desc = ns.Localize("Where the value sits on the bar. Moving " ..
                "text on a unit frame is a protected operation: a change " ..
                "made in combat is applied as soon as combat ends. The " ..
                "format itself is not protected and applies immediately, " ..
                "in combat as well."),
            values = positionValues,
            sorting = positionSorting,
            get = getPosition,
            set = setPosition,
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
        hint = "What the health bar says: nothing, the current value, the "
            .. "value and the maximum, or a percentage.",
        values = formatValues,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Power Text",
        path = { "power" },
        apply = "texts",
        hint = "The same choice for the power bar.",
        values = formatValues,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Text Position",
        path = { "position" },
        apply = "texts",
        hint = "Where on the bar the number stands.",
        values = positionValues,
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Shorten Large Numbers",
        path = { "abbreviate" },
        apply = "texts",
        hint = "Write thousands as a short form instead of every digit.",
    })
end

ns.Registry:Register(Texts)
