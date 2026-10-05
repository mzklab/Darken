local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("auras")

-- Darken's compact auras: a grid of buffs and debuffs of our own instead of
-- the standard one.
--
-- The file glues five parts together and does nothing else: the layout and the
-- time (Layout.lua), the order and the separation of one's own from other
-- people's (Sort.lua), the reversible moving away of the standard grid
-- (Grid.lua), the rules for a single aura (Rules.lua), the display and the
-- pool of icons (Icon.lua). Registration with the core goes through the public
-- contract (docs/module-api.md) — the module lives in a folder of its own and
-- is not part of the core.
--
-- What exists: an icon size of one's own, the number of icons per row, the
-- direction the grid grows in, the time and the stacks on an icon, the
-- separation of one's own effects from other people's, filtering auras by a
-- list of spells (Filter.lua), a tooltip on hover and cancelling a buff with
-- the right button (Mouse.lua), rules for a single aura — its own icon size,
-- its own border colour and a sound on ending (Rules.lua), and the return of
-- the standard grid without a reload of the interface.
--
-- Auras on unit frames (Units.lua) are the sixth part, and the only one where
-- the module works on foreign frames rather than its own. The game is left its
-- layout there in full: what comes from us is the filter and the border, and
-- there is not one engine-protected operation on that path. Why not a
-- replacement is in Units.lua's header.
--
-- What is not here and must not be: a place of its own in the grid for a
-- single aura (the argument is in Rules.lua's header), bars instead of icons,
-- reading other addons' filter lists. All of that is written down in the queue
-- of work.
--
-- Cancelling a buff is the only thing in the module the engine protects, and
-- it lives entirely in Mouse.lua: it also says there why it does nothing in
-- combat and why the engine keeps that promise rather than a check of ours.
--
-- === The rules that must not be broken here ===
--
-- The countdown. It is the only thing obliged to update continuously, and it
-- is also the place addons burn frames on. Walking every icon on every frame
-- is forbidden here. Instead each icon knows the instant its label will change
-- (Layout.Remaining returns it as its second value), and the module as a whole
-- knows the nearest of them. A frame on which that instant has not yet come
-- costs one comparison — regardless of whether there are forty auras on screen
-- or two.
--
-- Combat. There is not one deferred action in a repaint here, and that is not
-- forgetfulness: the player's auras are not protected by the engine, our icons
-- are children of UIParent, and deferring them until the end of a fight would
-- mean not showing them when they are needed. The only thing that goes through
-- the contract's handle:Secure is moving the standard grid's foreign frames:
-- protectedness is asked of the object, and on an unprotected one that means
-- "right now".
--
-- The pool. The icons are reused, and an icon that returned to the pool
-- carries nothing of the previous aura — see Icon.Release, Icon.Wipe and
-- Icon.Forget. It carries two tables through the pool — the record of the aura
-- and the marks of what was drawn — and both are wiped, both by walking the
-- keys and both on one line of Icon.Release.
--
-- Repainting. The icon at a position stays in its place, and only what
-- diverged from the marks is rewritten on it: an aura update almost always
-- changes one thing, while it used to cost a full rebuild of forty icons. That
-- was the most expensive thing the addon did in a combat frame. And the
-- comparison may be made only against what was drawn under the same settings —
-- what that cancels and where is stated in Redraw's header. The icons of the
-- tail leave the screen: a place that fell to nobody in this repaint is an
-- aura the filter stopped letting through, or one that expired.
--
-- The filter. It is described in Filter.lua and split in two by cost: the plan
-- is compiled when the settings change, and the decision about one aura costs
-- two comparisons. The plan lives here in one variable, and it is compiled
-- exactly in ApplySettings — the single place where entering the game,
-- changing the profile and editing any setting all converge.
--
-- The rules. They are built the same way and for the same reason (Rules.lua),
-- and they stand **after** the filter: the filter decides whether to show an
-- aura, a rule decides what it looks like. A rule is asked in exactly one
-- place in the whole module — in Read, inside the "the filter let it through"
-- branch — and it changes exactly two things on an icon: the size and the
-- border's colour. Both are written on every display and both through one door
-- (Icon.Place and Icon.Border), because a second writer of the size would
-- diverge from the first silently.

-- The core is not taken on trust even through the TOC's dependency line: the
-- behaviour of "## Dependencies" on classic clients is unconfirmed, and the
-- core's absence has to give one readable line rather than a Lua error.
if type(Darken) ~= "table" or type(Darken.RegisterModule) ~= "function" then
    print("|cffff4040" .. ADDON .. "|r: Darken is not loaded, so this addon "
        .. "does nothing. Install Darken, or disable this addon.")
    return
end

-- The contract version the module is written against. The seventh: the module
-- takes the font from the core (Darken:GetMedia), the palette
-- (Darken:GetSkin), event subscriptions, strings of its own, a slash-command
-- word of its own, deferred execution in combat and the shared aura filter
-- (Darken:GetAuraFilter) — otherwise the addon would have two parsers for one
-- and the same list of spells. The module claims none of the core's
-- subsystems: auras are not among the ones it replaces, and it moves the
-- standard grid away itself — reversibly.
--
-- The twelfth since the second increment: the labels on an icon take their
-- inset from the edge out of the skin's scale (Metrics.edge, contract version
-- 12). The time and the stacks used to stand here as two ones, while the same
-- two labels in the nameplates stood as two more numbers, and not one of the
-- four knew about the others.
--
-- The sixteenth. The core's mover places the grid
-- (handle:RegisterElement and handle:MoveElement, contract version 14), while
-- the module translates the label on its handle itself — that is version 16,
-- and before it no completeness check of the translations had seen the label's
-- key. The grid used to be placed by two sliders, as numbers from a corner of
-- the screen — a second way of placing a thing on screen, able to do less than
-- the first: no grid, no snapping, no "put it back as it was", and repeating
-- the position on a second character was only possible by retyping the numbers
-- by hand. The reduced answer to the request "put this aura over there" went
-- here as well — the request Rules.lua refuses, and refuses rightly.
local API = 16

-- The module takes the aura filter from the core: it is shared between two
-- modules and therefore lives in the core (Darken:GetAuraFilter, contract
-- version 7). An older core does not have this door, ns.Filter is then not
-- created at all, and that has to be said in one readable line — before the
-- file runs into the absence by itself.
if type(ns.Filter) ~= "table" then
    print("|cffff4040" .. ADDON .. "|r: this addon needs Darken module API "
        .. "version 7, and the installed Darken is older. Update Darken "
        .. "UI, or disable this addon.")
    return
end

local module

--- Translate one of the module's strings.
-- The dictionary, the choice of language and the fallback path belong to the
-- core (the contract, the section on one's own strings). The wrapper exists so
-- that the call sites need not know about the descriptor: the module's file is
-- read before the core hands it over.
-- @param key string|nil the English string that serves as the key
-- @return string
function ns.Localize(key)
    if module ~= nil then return module:Localize(key) end
    if key == nil or key == "" then return "" end
    return key
end

--- The core's skin right now.
--
-- Asked for on every application rather than remembered while the file is
-- read. A plain assignment of Darken:GetSkin() used to stand here, and on the
-- current core it made no difference: the door is defined by the moment our
-- files are read, and behind the door is one and the same table. The
-- contract's rule is nevertheless to ask: a remembered skin outlives a change
-- of palette silently, and the icons' borders would stay painted the old way
-- beside a window painted the new way.
--
-- It is asked for once per repaint of the grid rather than per icon: the
-- question costs one pcall, and the palette cannot change between two icons of
-- one grid.
--
-- @return table|nil
local function currentSkin()
    if type(Darken.GetSkin) ~= "function" then return nil end

    local ok, skin = pcall(Darken.GetSkin, Darken)
    if not ok or type(skin) ~= "table" then return nil end

    return skin
end

--- The core's media right now. The same way and for the same reason.
-- @return table|nil
local function currentMedia()
    if type(Darken.GetMedia) ~= "function" then return nil end

    local ok, media = pcall(Darken.GetMedia, Darken)
    if not ok or type(media) ~= "table" then return nil end

    return media
end

local Layout = ns.Layout
local BOUNDS = Layout.BOUNDS

-- Our frames. One holder per block, and the icons from a pool.
local holders = {}
local pool    = ns.Icon.NewPool()
local hidden          -- the hidden parent for the standard grid's frames
local ticker          -- the module's only OnUpdate
local origin          -- the grid's origin: this is what the core's mover
                      -- moves

-- The ledger of the standard grid we took: what exactly was taken and in
-- what state.
local grid = ns.Grid.NewState()

-- Auras on unit frames. The ledger of the foreign icons and our frame, where
-- the textures of their borders live: we do not put textures of ours on
-- foreign frames — there they would fall to the core's darkening as a second
-- owner (Units.lua's header).
local units = ns.Units.NewState()
local layer

-- The pass over the foreign icons waits for its frame rather than going
-- straight off the event. There is one reason and it is decisive: the game
-- updates a unit frame's auras on the same event we do, and the engine
-- promises no order between two frames subscribed to one event. A pass that
-- happened before the game would decide about an aura that is not on the icon
-- yet. The next frame comes after both handlers, whatever their order was.
--
-- This is the fallback path rather than the best one. The best is to stand
-- behind the game's own function that rearranges these icons (the core's
-- unitframe-auras-relayout group): hooksecurefunc puts us after it by
-- construction rather than after a delay that happened to be long enough.
-- Where such a function exists on the client, the pass happens in the same
-- frame as the game's layout, and the flag is cleared before its turn even
-- comes. Where it does not, waiting for a frame remains — entirely the same as
-- it was before the group existed.
local unitsPending = false

-- Whether we are already hooked onto the game's functions that rearrange the
-- foreign icons. There is nothing to undo a hooksecurefunc with, so the hook
-- is installed once per session and the setting itself serves as the switch:
-- the handler asks UnitsOn.
local unitsWatched = false

-- The time of the last pass made from under one of the game's functions.
-- There are several functions in the group, and the game calls some of them
-- once per frame: forty calls on one event would mean forty passes in a row
-- for one and the same appearance. Within one frame there is one pass from
-- under the hook.
local unitsStamp

-- Whether to search for the icons afresh. Icons appear later: there was no
-- focus and the player set one; a fifth member joined the group. The scan is
-- cheaper than a change of auras and happens only on a change of target, of
-- focus, of composition and on entering the world.
local unitsRescan = false

-- The pass over the foreign icons. Declared here and defined below: the
-- module's only OnUpdate calls it, and that stands higher up the file.
local UnitsPass

-- The icons shown right now. An array rather than a table by key: the walk
-- goes in order and only over the ones that are shown.
local active = {}

-- The nearest instant at which at least one time label will change. Until it
-- comes, a frame costs one comparison.
local nextChange = math.huge

-- The buffers for reading and splitting the auras. One set for the whole
-- module and reused: auras change during a fight, and three fresh tables per
-- change would cost the player frames.
local scratch, ownBuf, otherBuf = {}, {}, {}

-- The reserve of aura records. The array above is rebuilt on every reading,
-- while the records themselves are taken from here and rewritten in full:
-- otherwise the "reused buffer" would allocate forty tables per change of
-- auras, that is, precisely what it exists to prevent.
local spare = {}

local drawing = false

-- How many places of the grid are taken right now. The repaint's cursor: Fill
-- moves it across the places of both blocks, and the tail of the array of
-- shown icons behind it goes back to the pool.
local cursor = 0

-- Whether what was drawn is stale in its entirety. Set where repainting by
-- difference has no right to compare: a change of any setting, the module
-- being switched on, entering the world. In detail in Redraw's header.
local stale = true

-- The grid's common look for one repaint: what is the same for every icon.
-- One table for the whole module and reused — a fresh one per change of auras
-- would be rubbish during a fight.
local look = {}

-- The filter's plan. Compiled when the settings change and held until the
-- next change: on an aura itself it is only read.
local plan = ns.Filter.Compile(nil)

-- The plan of the rules for a single aura. Compiled in the same place and for
-- the same reason.
local rules = ns.Rules.Compile(nil)

-- The memory of endings: which auras under a rule with a sound were in the
-- previous set that was read. It lives beside the plans rather than on the
-- icons: an icon goes back to the pool and falls to another aura, while the
-- spell's id belongs to that aura specifically.
local watch = ns.Rules.NewWatch()

-- How many auras of one kind to read. A ceiling rather than a count: the
-- reading stops at the first empty slot, and the ceiling insures against a
-- client that returns something other than nil for an empty slot.
local MAX_AURAS = 40

--- The module's settings.
-- @return table|nil
local function Settings()
    return module and module:GetSettings() or nil
end

--- The current game time.
-- Outside the game the function does not exist, and that is not a failure: the
-- countdown then simply does not run, because there are no frames either.
-- @return number
local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    return ok and tonumber(value) or 0
end

--- The reading of this client's auras, asked of the core.
--
-- The module no longer has a fork of its own between the two spellings of the
-- game's aura call: there is one list of foreign names in the project
-- (Core/Compat.lua, the unit-aura group), and a second one inside the module's
-- folder would diverge from it silently — such a list does not complain when
-- it diverges from the client, it simply stops reading anything.
--
-- Asked for once and remembered: the answer to "how does this client return
-- auras" does not change until the player restarts the game, while it is asked
-- up to a hundred times per change of auras in a group.
local auraByRecord, auraByValues, auraAsked
local function auraReaders()
    if auraAsked then return auraByRecord, auraByValues end
    auraAsked = true

    local api = _G.Darken
    if type(api) == "table" and type(api.GetGameFunction) == "function" then
        local ok, fn = pcall(api.GetGameFunction, api, "unit-aura", "record")
        if ok and type(fn) == "function" then auraByRecord = fn end

        ok, fn = pcall(api.GetGameFunction, api, "unit-aura", "values")
        if ok and type(fn) == "function" then auraByValues = fn end
    end

    return auraByRecord, auraByValues
end
ns.AuraReaders = auraReaders

--- Read the auras of one kind into a reused array, filtering them by the
--- plan.
--
-- There are two paths in the game, and the one that exists on this client is
-- chosen: in new builds the reading moved into the per-index call, on classic
-- clients UnitAura lives on. The decision is made by an object's existence
-- rather than by the build number.
--
-- The filter stands here rather than as a second pass over a finished list: an
-- aura the player decided not to see need not even be recorded. The
-- enumeration nevertheless goes to the end — stopping at the first one that
-- did not pass would mean losing everything behind it.
--
-- The rule for a single aura is asked here and **only here** — by one call of
-- ns.Rules.For, and it stands inside the "the filter let it through" branch.
-- That is how the precedence is declared: the filter decides whether to show
-- an aura at all, the rule decides what it looks like. A rule does not show
-- what was hidden and does not hide what was shown, and that is impossible not
-- because of a check but because there is nowhere else to ask a rule.
--
-- @param unit string
-- @param filter string "HELPFUL" or "HARMFUL"
-- @param out table the array for the answer
-- @param harmful boolean whether debuffs are being read
-- @return table the same array
local function Read(unit, filter, out, harmful)
    for i = #out, 1, -1 do out[i] = nil end

    -- The reading is asked of the core (see auraReaders above): the module
    -- has no fork of its own between the game's two aura calls.
    local byIndex, byValues = auraReaders()

    -- Asked once for the whole list rather than per aura: the answer is the
    -- same for all forty, and the question itself is cheaper than a name key.
    -- Two parties need the key — the filter and the rules — and one key is
    -- made: two keys for one name would be two identical strings per aura.
    local ruled    = ns.Rules.Any(rules)
    local needsKey = ns.Filter.NeedsKey(plan)
        or (ruled and ns.Rules.NeedsKey(rules))
    local sounded  = ruled and ns.Rules.HasSound(rules)

    for index = 1, MAX_AURAS do
        local name, icon, count, duration, expires, source, spellId

        if byIndex then
            local ok, data = pcall(byIndex, unit, index, filter)
            if ok and type(data) == "table" then
                name, icon = data.name, data.icon
                count      = data.applications or data.charges
                duration   = data.duration
                expires    = data.expirationTime
                source     = data.sourceUnit
                spellId    = data.spellId
            end
        elseif byValues then
            local ok, a, b, c, _, e, f, g, _, _, j =
                pcall(byValues, unit, index, filter)
            if ok then
                name, icon, count = a, b, c
                duration, expires, source = e, f, g
                spellId = j
            end
        end

        if name == nil then break end

        -- "Mine" means applied by the player. The flag is asked of the game
        -- rather than derived from the spell's name: one and the same buff is
        -- applied by the player, by their pet and by a neighbour in the
        -- group.
        local mine = (source == "player")
        local key  = needsKey and ns.Filter.Key(name) or nil
        local id   = tonumber(spellId)

        if ns.Filter.Allows(plan, key, id, mine, harmful) then
            -- The only call of a rule in the whole module, and it stands
            -- after the filter: see the function's header.
            local rule = ruled and ns.Rules.For(rules, key, id) or nil

            -- An aura under a rule with a sound is recorded in the memory
            -- of endings by the aura's own name rather than by an icon: the
            -- pool then takes no part in the sound at all and cannot fake
            -- it.
            if sounded and rule ~= nil and rule.sound then
                local token = ns.Rules.Token(id, key)
                -- A client without a spell id and rules made of ids alone:
                -- there is nothing to name it by, so the name key is made
                -- right here. That happens only on an aura under a rule with
                -- a sound, that is, a handful of times rather than for every
                -- aura of the set.
                if token == nil then
                    token = ns.Rules.Token(nil, ns.Rules.Key(name))
                end
                ns.Rules.Watch(watch, token)
            end

            local slot = #out + 1
            local record = spare[slot]
            if type(record) ~= "table" then
                record = {}
                spare[slot] = record
            end
            out[slot] = record

            record.order    = index
            record.name     = name
            record.icon     = icon
            record.count    = count
            record.duration = duration
            record.expires  = expires
            record.mine     = mine
            record.spellId  = tonumber(spellId)
            -- Only whoever read the aura knows its kind. The mouse needs it
            -- twice: the game gives the tooltip by the kind, and only a buff
            -- can be cancelled off oneself.
            record.harmful  = harmful and true or false
            -- The rule is placed on the record of the aura rather than on
            -- the icon: the icon is reused, while the record is rewritten in
            -- full on every reading. The display reads it from here and does
            -- not ask a second time.
            record.rule     = rule
        end
    end

    return out
end

-- Whether the module's only OnUpdate is shown right now. Remembered here
-- rather than asked of the frame: asking the engine costs as much as writing
-- to it, and a repaint in which nothing changed is obliged to cost neither.
local tickerShown

--- Show or put out the module's only OnUpdate.
--
-- One door, and all four parties ask through it: the repaint, the countdown,
-- the waking of the pass over the foreign icons, and the pass itself. There is
-- nowhere to write "shown" to the engine twice in a row.
--
-- @param want any whether the handler is needed
local function Ticking(want)
    want = want and true or false
    if tickerShown == want then return end
    if not ticker or type(ticker.SetShown) ~= "function" then return end

    tickerShown = want
    ticker:SetShown(want)
end

--- Write the time onto an icon and remember when the label will change.
--
-- The only place where the next update's moment is set. It also moves the
-- shared nearest instant — which is why it was lifted out: two places
-- computing "when to wake up" would diverge silently, and some of the labels
-- would freeze.
--
-- @param frame table the icon
-- @param now number the current time
local function Countdown(frame, now)
    local record = frame.record
    if type(record) ~= "table" then return end

    if not record.timed then
        ns.Icon.SetTime(frame, "")
        record.due = nil
        return
    end

    local expires = tonumber(record.expires)
    if not expires or expires <= 0 then
        ns.Icon.SetTime(frame, "")
        record.due = nil
        return
    end

    local text, delay = Layout.Remaining(expires - now)
    ns.Icon.SetTime(frame, text)

    if delay == nil then
        record.due = nil
        return
    end

    record.due = now + delay
    if record.due < nextChange then nextChange = record.due end
end

--- The OnUpdate handler: the only one in the whole module.
--
-- The cheap path is the first three lines: the time, a comparison, a return.
-- No walk, no table, no call into the game, and its cost does not depend on
-- the number of auras on screen.
--
-- The expensive path happens only when at least one label really changes, and
-- it touches only those icons whose moment has come.
local function Tick()
    -- The foreign icons go first and exactly once: the frame after the event
    -- on which the game has already rearranged its own auras. The pass clears
    -- its own flag, so the next frame costs one comparison again.
    if unitsPending then
        unitsPending = false
        if UnitsPass then UnitsPass() end
        Ticking(nextChange ~= math.huge)
    end

    if nextChange == math.huge then return end

    local now = Now()
    if now < nextChange then return end

    nextChange = math.huge
    for i = 1, #active do
        local frame = active[i]
        local record = frame.record
        local due = record and record.due
        if due then
            if now >= due then
                Countdown(frame, now)
            elseif due < nextChange then
                nextChange = due
            end
        end
    end
end

--- Create a frame of ours, if the client allows it.
-- @param parent table|nil
-- @return table|nil
local function NewFrame(parent)
    if type(CreateFrame) ~= "function" then return nil end
    local ok, frame = pcall(CreateFrame, "Frame", nil, parent or UIParent)
    if not ok then return nil end
    return frame
end

--- The holder of one block of the grid.
-- @param key string "buffs" or "debuffs"
-- @return table|nil
local function Holder(key)
    if holders[key] == nil then
        holders[key] = NewFrame(UIParent) or false
    end
    return holders[key] or nil
end

-- The mover element's key. The core builds the name in the saved variables
-- out of the module's name and this key, and there must be no second place
-- where the key is written.
local ELEMENT = "grid"

--- The grid's origin: the very frame the core's mover moves.
--
-- Both blocks are anchored to its corner, and it to the screen. Its size is
-- constant (Layout.ORIGIN) and does not depend on the settings: the mover
-- holds a frame by its centre against the screen's centre, and an origin that
-- changed size along with the number of auras would carry the grid away with
-- every buff that appeared.
-- @return table|nil
local function Origin()
    if origin == nil then
        origin = NewFrame(UIParent) or false
        if origin and type(origin.SetSize) == "function" then
            origin:SetSize(Layout.ORIGIN.w, Layout.ORIGIN.h)
        end
    end
    return origin or nil
end

--- Put the grid's origin in its place.
--
-- Called from applying the settings rather than from enabling the module: the
-- core brings a disabled module back into service without repeating OnEnable.
--
-- The core's mover used to place the origin, and the position lived with it.
-- The mover was removed from the addon at the author's word, and the grid
-- again stands where the module places it: in the corner named by the
-- direction of growth, with its own insets.
--
-- @param handle table the module's descriptor
local function Publish(handle)
    local frame = Origin()
    if frame == nil then return end
    if type(frame.SetPoint) ~= "function" then return end
    if type(frame.ClearAllPoints) == "function" then
        pcall(frame.ClearAllPoints, frame)
    end

    local root = _G.UIParent
    if type(root) ~= "table" then return end

    pcall(frame.SetPoint, frame, Layout.ORIGIN.point, root,
        Layout.ORIGIN.point, Layout.ORIGIN.x, Layout.ORIGIN.y)
end

--============================================================================
-- Migrating the grid's old position onto the mover
--============================================================================

-- Before the mover, two sliders placed the grid, and their numbers lie in the
-- player's saved variables. They must not be lost: the player arranged the
-- grid by hand, and "I updated the addon and the grid moved" would be the
-- worst possible answer to an improvement.
--
-- The module's data shape is numbered from this release on. The first shape is
-- the sliders, the second the mover; the core assigns the number itself
-- (handle:Migrate), and the whole translation of data belongs to it as well: a
-- second mechanism beside the core's would diverge from it silently.
--
-- NOTE: the mover itself is no longer in the core — see Publish above, where
-- it says it was removed at the author's word. So handle:MoveElement, which
-- Adopt calls below, is not a core name any more (it is absent from
-- HANDLE_FIELD_VERSIONS in Core/Api.lua and from every core file), and this
-- migration step has nowhere left to put the numbers it computed. The step
-- fires only for a profile that still carries offsetX/offsetY.
local FORMAT = 2

-- Where the old position moved to. A migration step touches the data alone —
-- it has nothing to write to the mover with and it is not the moment: the
-- element is not declared by then. So the step leaves a pair of numbers here,
-- and whoever called the migration hands them to the mover — right after it
-- and once.
local adopted

--- The screen's size in UIParent units.
-- It is known only in the game; outside it there are zeroes, and then there is
-- nothing to convert.
-- @return number, number
local function ScreenSize()
    local root = UIParent
    if type(root) ~= "table" then return 0, 0 end

    local okW, w = pcall(root.GetWidth, root)
    local okH, h = pcall(root.GetHeight, root)
    return okW and tonumber(w) or 0, okH and tonumber(h) or 0
end

local MIGRATIONS = {
    -- The first shape -> the second: the numeric offsets are turned into the
    -- origin's position with the mover and then erased. Erased deliberately:
    -- left beside it, they would mean two places recording one and the same
    -- thing, and a second launch would convert what had already been
    -- converted.
    [1] = function(data)
        local width, height = ScreenSize()
        local x, y = Layout.MoverPoint(Layout.Anchor(data.direction),
            Layout.Clamp("offsetX", data.offsetX),
            Layout.Clamp("offsetY", data.offsetY),
            width, height, Layout.ORIGIN.w, Layout.ORIGIN.h)

        data.offsetX, data.offsetY = nil, nil
        adopted = { x = x, y = y }
    end,
}

--- Carry the grid's old position over to the mover, if there is one.
--
-- Called from applying the settings, after the element is declared: there is
-- nowhere to put the position while the mover has no element.
--
-- The shape's number is assigned here as well, and by the presence of the keys
-- rather than by their value: why exactly that way is in Layout.Legacy's
-- header.
--
-- @param handle table the module's descriptor
-- @param settings table the module's settings
local function Adopt(handle, settings)
    if ns.Layout.Legacy(settings) then
        -- Converting without the screen is not allowed. The conversion adds
        -- half the screen, and getting it wrong is not allowed at all: there
        -- will be no second time — the keys are erased and the shape is
        -- numbered. ScreenSize answers with zeroes every time UIParent has
        -- not been measured, and we are called from applying the settings,
        -- that is, on ADDON_LOADED, before entering the world. With zeroes
        -- the grid would travel from the screen's corner to its centre,
        -- forever and silently.
        --
        -- So there is no guess here but a refusal: we touch nothing and
        -- leave. The next application of the settings will find the screen
        -- and convert — the keys are intact, there is no number, and the
        -- occasion is not lost.
        local width, height = ScreenSize()
        if width <= 0 or height <= 0 then return end

        settings.version = 1
    end

    adopted = nil
    handle:Migrate(settings, MIGRATIONS, FORMAT)

    if adopted ~= nil then
        handle:MoveElement(ELEMENT, adopted.x, adopted.y)
        adopted = nil
    end
end

--- The hidden parent for the standard grid's frames.
-- @return table|nil
local function Hidden()
    if hidden == nil then
        hidden = NewFrame(UIParent) or false
        if hidden and type(hidden.Hide) == "function" then hidden:Hide() end
    end
    return hidden or nil
end

--============================================================================
-- Auras on unit frames
--============================================================================
--
-- What is done here and what is not is in Units.lua's header. In short: the
-- game is left its layout in full, and what comes from us is the filter (what
-- is hidden on oneself is hidden on the target too) and a border of the same
-- look our own icons have. There is not one engine-protected operation on this
-- path, so nothing is deferred: a filter frozen during a fight is the very
-- loss the rule about deferred execution is written for.

--- Read one of a unit's auras from the game.
--
-- Two paths in the game, and the one that exists on this client is chosen —
-- exactly as in Read. There is no second piece of knowledge about how the game
-- returns an aura here: the fields are named alike because the new path names
-- them that way, and the old one is rewritten into the same names.
--
-- @param unit string
-- @param index number
-- @param filter string "HELPFUL" or "HARMFUL"
-- @return table|nil

local unitAura = {}
local function AuraAt(unit, index, filter)
    local byRecord, byValues = auraReaders()

    if byRecord then
        local ok, data = pcall(byRecord, unit, index, filter)
        if ok and type(data) == "table" then return data end
        return nil
    end

    if not byValues then return nil end

    local ok, name, icon, _, _, _, _, source, _, _, spellId =
        pcall(byValues, unit, index, filter)
    if not ok or name == nil then return nil end

    -- The table is reused: recognising an icon asks for an aura twice per
    -- icon, and there can be close to a hundred icons on screen. A fresh
    -- table per question would mean two hundred tables per change of auras in
    -- a group.
    unitAura.name       = name
    unitAura.icon       = icon
    unitAura.sourceUnit = source
    unitAura.spellId    = spellId
    unitAura.harmful    = nil
    return unitAura
end

--- Our frame, where the border textures of the foreign icons live.
--
-- Ours rather than somebody else's, and that is decisive: textures on a
-- foreign icon would fall to the core's darkening as a second owner. The
-- stratum is above the unit frames — otherwise the border would end up
-- underneath the picture itself.
-- @return table|nil
local function Layer()
    if layer == nil then
        layer = NewFrame(UIParent) or false
        if layer then
            if type(layer.SetAllPoints) == "function" then
                pcall(layer.SetAllPoints, layer, UIParent)
            end
            if type(layer.SetFrameStrata) == "function" then
                pcall(layer.SetFrameStrata, layer, "HIGH")
            end
        end
    end
    return layer or nil
end

-- The groups of unit frames the aura icons lie under. Both are the core's,
-- and there is no list of names of our own beside them: the target, the focus,
-- the pet and the party live in unitframe, the compact party and raid frames
-- in raidframe-member. A client without one of them returns an empty list, and
-- that is not a refusal.
local UNIT_GROUPS = { "unitframe", "raidframe-member" }

-- The group of the aura icons themselves on those frames, and the group of
-- the game's functions that rearrange them. Both are the core's, and both may
-- turn out empty: the walk by construction then searches for the icons, and
-- the pass waits for a frame.
local AURA_BUTTON_GROUP = "unitframe-auras"
local AURA_RELAYOUT_GROUP = "unitframe-auras-relayout"

--- The live unit frames of this client.
-- @param out table the array for the answer
-- @return table the same array
local function UnitFrames(out)
    for i = #out, 1, -1 do out[i] = nil end
    if type(Darken.GetFrameNames) ~= "function" then return out end

    -- The frames themselves rather than the names: the door returns them as
    -- its second answer (contract 18). A name in a group can be a path into a
    -- foreign frame, and _G[path] is nil: the module would silently have found
    -- not one unit frame.
    for g = 1, #UNIT_GROUPS do
        local ok, names, objects =
            pcall(Darken.GetFrameNames, Darken, UNIT_GROUPS[g])
        if ok and type(names) == "table" and type(objects) == "table" then
            for i = 1, #names do
                local frame = objects[i]
                if type(frame) == "table" then out[#out + 1] = frame end
            end
        end
    end

    return out
end

--- The live aura icons of this client, found by the core by name.
--
-- There is no list of names of our own beside this one either: the
-- unitframe-auras group belongs to the compatibility layer, and a client on
-- which not one such name exists returns an empty list. An empty list is not a
-- refusal: the walk by construction then searches for the icons, as it did
-- before the group existed.
-- @param out table the array for the answer
-- @return table the same array
local function AuraButtons(out)
    for i = #out, 1, -1 do out[i] = nil end
    if type(Darken.GetFrameNames) ~= "function" then return out end

    -- The icons themselves rather than the names: see UnitFrames above.
    local ok, names, objects =
        pcall(Darken.GetFrameNames, Darken, AURA_BUTTON_GROUP)
    if ok and type(names) == "table" and type(objects) == "table" then
        for i = 1, #names do
            local button = objects[i]
            if type(button) == "table" then out[#out + 1] = button end
        end
    end

    return out
end

-- A reused array for the list of unit frames: a scan happens on a change of
-- target, and a fresh table per change would be rubbish for the sake of one
-- pass.
local unitFrames = {}

-- And one like it for the icons found by name: the same change of target,
-- the same cost.
local auraButtons = {}

--- Whether auras on unit frames are switched on right now.
-- @return boolean
local function UnitsOn()
    local settings = Settings()
    return drawing and settings ~= nil and settings.units and true or false
end

--- Stand behind the game where it rearranges the foreign icons.
--
-- A hook rather than a replacement: hooksecurefunc calls our handler **after**
-- the game's function and changes nothing inside it. That is the whole gain —
-- "the game has just rewritten this icon" instead of "the next frame after the
-- event".
--
-- The hook is installed once per session: there is nothing to undo
-- hooksecurefunc with, so the setting itself serves as the switch. A client on
-- which not one such function exists gets not one hook, and the flag stays
-- false: waiting for a frame then does the work.
local function UnitsWatch()
    if unitsWatched then return end
    if type(hooksecurefunc) ~= "function" then return end
    if type(Darken.GetFrameNames) ~= "function" then return end

    local ok, names = pcall(Darken.GetFrameNames, Darken, AURA_RELAYOUT_GROUP)
    if not ok or type(names) ~= "table" then return end

    unitsWatched = true

    for i = 1, #names do
        pcall(hooksecurefunc, names[i], function()
            if not UnitsOn() then return end

            -- No more often than once a frame. The game calls some of these
            -- functions once per frame, and forty passes in a row would cost
            -- the player a frame for one and the same appearance.
            --
            -- A call that was cut off is a frame the game rearranged after
            -- our pass: the decision about its icons has not been made yet.
            -- So the flag is raised **again** (this same hook has already
            -- cleared it a line below), and the next frame picks up all such
            -- frames in one pass. Waiting for a new UNIT_AURA is not an
            -- option: there may be none at all, and the icon would be left
            -- with somebody else's opacity until the fight ended.
            local now = Now()
            if unitsStamp == now then
                unitsPending = true
                if ticker and type(ticker.SetShown) == "function" then
                    Ticking(true)
                else
                    UnitsPass()
                end
                return
            end
            unitsStamp = now

            -- The flag is cleared: the work has just been done, and there
            -- is no reason to do it again on the next frame. That is what
            -- replaces waiting for a frame where the door was found.
            unitsPending = false
            UnitsPass()
        end)
    end
end

--- Wake the pass over the foreign icons.
--
-- A flag rather than the work: the work itself will happen on the next frame,
-- after the game has rearranged its own auras on the same event (see
-- unitsPending).
--
-- A client with no frames at all is the tests and only the tests: there the
-- next frame will never come, and the pass goes at once.
--
-- @param rescan any whether to search for the icons afresh
local function UnitsWake(rescan)
    if not UnitsOn() then return end

    if rescan then unitsRescan = true end

    if ticker and type(ticker.SetShown) == "function" then
        unitsPending = true
        Ticking(true)
        return
    end

    unitsPending = false
    if UnitsPass then UnitsPass() end
end

--- One pass over the foreign icons.
--
-- Units.Apply makes the decision about each icon — and makes it by the same
-- filter and the same rules our own grid uses: the plans here are exactly the
-- same two variables Read reads.
UnitsPass = function()
    local rescan = unitsRescan
    unitsRescan = false

    if not UnitsOn() then
        ns.Units.Forget(units, Layer())
        return
    end

    -- The hook onto the game's functions is installed here: by this moment
    -- the setting is already on, and before it was switched on an extra hook
    -- would be paying for nothing.
    UnitsWatch()

    if rescan or #units.buttons == 0 then
        ns.Units.Scan(units, UnitFrames(unitFrames), AuraButtons(auraButtons))
    end

    ns.Units.Apply(units, Layer(), currentSkin(), plan, rules, AuraAt)
end

--- Let go of every foreign icon.
--
-- Called when the setting is switched off, when the module is switched off and
-- when it fails. A foreign frame with something of ours left on it is a trace
-- nobody answers for any more: a transparent aura icon until the interface is
-- reloaded.
local function UnitsStop()
    unitsPending = false
    unitsRescan = false
    ns.Units.Forget(units, Layer())
end

--- Return every shown icon to the pool.
local function ReleaseAll()
    local skin = currentSkin()
    for i = #active, 1, -1 do
        ns.Icon.Release(pool, active[i], skin)
        active[i] = nil
    end
    cursor = 0
    nextChange = math.huge
end

--- Lay out one list of auras starting from a given place of the grid.
--
-- The grid's places are numbered through both blocks: the `cursor` is the
-- number of the last place taken, and the array of shown icons, `active`, is
-- built by it. The icon at a position already stands where it belongs, and
-- only what diverged from the marks is repainted on it (Icon.Changed).
--
-- What exactly is compared is four sets, and they are divided not for beauty's
-- sake but by cost: the place (the anchor and the side), the clothing (the
-- font, which follows the side), the border (the rule's colour) and the aura
-- itself (the picture, the stacks, the expiry, the index). A set in which
-- nothing diverged costs not one call into the engine.
--
-- @param list table the array of records
-- @param first number the number of the block's first place, from one
-- @param holder table|nil the block's holder
-- @param now number
local function Fill(list, first, holder, now)
    local size      = look.size
    local perRow    = look.perRow
    local spacing   = look.spacing
    local direction = look.direction
    local point     = look.point
    local skin      = look.skin
    local media     = look.media
    local edge      = look.edge
    local showTime  = look.showTime
    local showStacks = look.showStacks
    local mouse     = look.mouse

    for i = 1, #list do
        local aura = list[i]

        local slot  = cursor + 1
        local frame = active[slot]
        if frame == nil then
            frame = ns.Icon.Acquire(pool, skin)
            if frame == nil then return end
            active[slot] = frame
        end
        cursor = slot

        -- The size and the border's colour are everything a rule changes on
        -- an icon, and both are computed here **always** rather than only
        -- when there is a rule. Otherwise an icon taken from the pool after
        -- an aura under a rule would carry that rule's size over to an aura
        -- nobody named — and carry it silently. They are recorded into the
        -- marks, and the comparison against the marks decides whether they
        -- have to be written into the engine.
        local rule   = aura.rule
        local own    = ns.Rules.Size(rule, size)
        local tint   = ns.Rules.Color(rule, nil)
        local dx, dy = Layout.Inset(size, own, direction)
        local x, y   = Layout.Place(first + i - 1, perRow, size, spacing,
            direction)

        -- **Only what changes from aura to aura** is compared. The grid's
        -- common look — the skin, the media, the inset, the anchor corner,
        -- the switches for the time, the stacks and the mouse — is
        -- deliberately absent from the sets: all of that changes through one
        -- door (ApplySettings), and that door sets stale, so by construction
        -- there is nothing to compare after it. An extra value in a set is
        -- forty extra comparisons per aura update in combat.
        local marks  = ns.Icon.Marks(frame)
        local moved  = ns.Icon.Changed(marks, "spot", holder, x + dx, y + dy)
        local sized  = ns.Icon.Changed(marks, "cell", own)
        local tinted = ns.Icon.Changed(marks, "tint", tint)
        -- The mouse is the only thing where "nothing changed" does not mean
        -- "there is nothing to do". An icon born in combat arrives without
        -- the secure overlay: the engine does not allow creating a protected
        -- frame in combat, and the first repaint that can takes it on. Not
        -- asking about it because the aura is the same would mean leaving the
        -- player right-clicking at nothing — and silently.
        local moused = mouse and frame.cancel == nil
        -- The aura is compared in full — by everything of it that reaches
        -- the screen or the mouse overlay. Its index in the game's list
        -- stands here on equal terms with the picture: a buff is cancelled by
        -- that index, and an index that shifted while the picture stayed the
        -- same is a button that will cancel the wrong aura.
        local fresh  = ns.Icon.Changed(marks, "aura",
            aura.name, aura.icon, aura.count, aura.duration, aura.expires,
            aura.mine, aura.spellId, aura.harmful, aura.order)

        if moved or sized then
            ns.Icon.Place(frame, holder, point, x + dx, y + dy, own)
        end
        if tinted then ns.Icon.Border(frame, skin, tint) end
        if sized  then ns.Icon.Dress(frame, own, media, edge) end
        if fresh  then ns.Icon.SetAura(frame, aura, showTime, showStacks) end
        -- The mouse is aimed after the display rather than before: it is
        -- aimed at what is already written on the icon, and it reads that off
        -- the record itself.
        if fresh or moused then ns.Mouse.Update(frame, mouse) end

        if fresh then
            Countdown(frame, now)
        else
            -- The aura is the same — which means its time label is the same
            -- too, and there is no reason to write it: Tick carries it, and
            -- carries it by the very moment that lies in the record. The
            -- moment is only returned into the shared nearest instant, which
            -- the repaint collects afresh.
            --
            -- A moment that has come is updated right here, and by exactly
            -- the same comparison as in Tick: otherwise the label on an aura
            -- that did not change would lag behind the label on one that did
            -- by exactly one frame.
            local record = frame.record
            local due = record and record.due
            if due then
                if now >= due then
                    Countdown(frame, now)
                elseif due < nextChange then
                    nextChange = due
                end
            end
        end
    end
end

--- Repaint the grid by difference.
--
-- === Why not "tear it down and build it again" ===
--
-- The repaint used to begin with ReleaseAll: every shown icon went back to the
-- pool and the grid was assembled from nothing, however many auras had
-- actually changed. The walk was the same — forty records — but each record
-- cost a dozen calls into the engine: unanchor, hide, clear the picture, clear
-- two labels, clear the shade, clear the aim, put the border out — and then
-- all the same in the other direction.
--
-- The cost of that was measured on the addon as a whole: one UNIT_AURA on the
-- player cost more than all thirty nameplates together, and was the most
-- expensive line of a combat frame. The cause is one: **the event's frequency
-- multiplied by a full rebuild**. Almost every aura update changes one thing —
-- a stack ticked, one aura expired, one was applied — while forty icons were
-- rebuilt.
--
-- Now the icon at a position stays in place, and only what diverged from the
-- marks of what was drawn is rewritten on it (Icon.Changed). A repaint in
-- which nothing changed costs not one call into the engine.
--
-- === What cancels the comparison ===
--
-- The comparison may be made only against what was drawn under the same
-- settings. An edit of a setting, a change of profile, a change of the palette
-- or the font, the module being switched on and entering the world all set
-- `stale`, and the first repaint after that tears the grid down entirely —
-- that is, does exactly what was always done. All those paths converge in
-- ApplySettings, and the flag is set there: the module has no second place
-- where it learns the settings changed.
--
-- The filter and the rules belong here on equal terms with the rest: both are
-- compiled in ApplySettings, and any edit of them passes through the same
-- door.
--
-- === What the comparison does not touch ===
--
-- Reading the auras from the game goes as it went — in full, both blocks, on
-- every event: there is no other way to learn what changed. The memory of
-- endings is filled by that same reading and in the same way (by the aura
-- rather than by the icon), so repainting by difference does not touch the
-- ending sound at all and cannot fake it.
local function Redraw()
    if not drawing then return end

    local settings = Settings()
    if not settings then return end

    local size, perRow, spacing, direction = Layout.Grid(settings)
    local point = Layout.Anchor(direction)
    local way   = Layout.DIRECTIONS[direction]
    local now   = Now()

    -- The skin and the media are one question for the whole repaint: there
    -- are dozens of icons in the grid, and asking for each of them would mean
    -- paying for one and the same answer. The labels' inset from the edge
    -- comes from there and at the same time.
    local skin  = currentSkin()
    local media = currentMedia()

    look.size       = size
    look.perRow     = perRow
    look.spacing    = spacing
    look.direction  = direction
    look.point      = point
    look.skin       = skin
    look.media      = media
    look.edge       = ns.Icon.Edge(skin)
    look.showTime   = settings.showTime and true or false
    look.showStacks = settings.showStacks and true or false
    look.mouse      = settings.mouse and true or false

    -- What is stale is **rewritten rather than torn down**. Forgetting the
    -- marks is exactly what "there is nothing to compare against" means: the
    -- very next walk over the grid's places will diverge from emptiness on
    -- every set and rewrite everything on the icon.
    --
    -- A return to the pool is not needed for that and would be a pure loss:
    -- unanchor, hide, clear the picture, clear two labels, clear the shade,
    -- clear the aim and put the border out — precisely in order to write all
    -- the same things onto the same icon a moment later. Surplus icons still
    -- reach the pool: the repaint's tail removes them.
    if stale then
        for i = 1, #active do ns.Icon.Forget(active[i]) end
        for _, holder in pairs(holders) do ns.Icon.Forget(holder) end
        stale = false
    end

    cursor = 0
    nextChange = math.huge

    -- Where the grid stands is decided by its origin: the blocks hold onto
    -- its corner. There are no numeric offsets here any more — their place
    -- was taken by the point Publish anchors to the screen. The origin can be
    -- absent only where there are no frames at all (a client without
    -- CreateFrame); the screen then stands in for it.
    local anchor = Origin() or UIParent

    -- The buff block and the debuff block: the second under the first, at
    -- the first one's distance from the edge plus the gap. The first one's
    -- height is computed by the same arithmetic as its layout — otherwise the
    -- blocks would ride over each other by exactly one setting.
    local blocks = { "HELPFUL", "HARMFUL" }
    local y = 0

    for b = 1, #blocks do
        local filter = blocks[b]
        local holder = Holder(filter)
        local marks  = ns.Icon.Marks(holder)

        if holder and type(holder.ClearAllPoints) == "function"
            and ns.Icon.Changed(marks, "spot", anchor, point, y) then
            holder:ClearAllPoints()
            holder:SetPoint(point, anchor, point, 0, y)
        end

        local list = Read("player", filter, scratch, filter == "HARMFUL")
        local count = #list

        if settings.separate then
            local own, others = ns.Sort.Split(list, ownBuf, otherBuf)
            Fill(own, 1, holder, now)
            Fill(others, Layout.Offset(#own, perRow), holder, now)
            count = #own + #others
        else
            ns.Sort.Order(list)
            Fill(list, 1, holder, now)
        end

        local width, height = Layout.Block(count, perRow, size, spacing)
        if holder and type(holder.SetSize) == "function"
            and ns.Icon.Changed(marks, "size", width, height) then
            holder:SetSize(width, height)
        end
        -- An empty block is hidden entirely. The filter is entitled to leave
        -- a block without a single aura, and a shown empty holder is an
        -- invisible rectangle that catches the mouse where there is nothing on
        -- screen.
        if holder and type(holder.SetShown) == "function"
            and ns.Icon.Changed(marks, "lit", count > 0) then
            holder:SetShown(count > 0)
        end

        -- The second block stands under the first, and an empty first one
        -- takes no space: a hole one icon tall reads as "something did not
        -- draw".
        y = y + way.y * Layout.Advance(count, height, spacing)
    end

    -- The tail: the places that fell to nobody in this repaint. The auras
    -- behind them expired, and the icons behind them have to leave the screen
    -- along with everything of theirs — otherwise the picture of an aura that
    -- no longer exists would be left hanging on the grid. They leave from the
    -- end, because the numbering of places runs through both blocks.
    for i = #active, cursor + 1, -1 do
        ns.Icon.Release(pool, active[i], skin)
        active[i] = nil
    end

    -- The countdown is needed only when there is something to count down.
    -- Without a single timed aura the OnUpdate handler does not hang there at
    -- all — that is cheaper than the cheapest possible walk.
    --
    -- The second reason to keep the handler is a pass over the foreign icons
    -- waiting for its frame: it and the countdown deliberately share one
    -- OnUpdate, because a second per-frame walk in the module would mean a
    -- second place where frames are burnt.
    Ticking(nextChange ~= math.huge or unitsPending)

    -- The set has been read in full — both blocks — and only now can it be
    -- said what ended. By one question per repaint rather than per block: the
    -- buffs are read first, and an answer asked for after them would declare
    -- every debuff ended at once.
    --
    -- The first repaint after an edit of the settings, entering the world or
    -- the module being switched on only remembers the set: the memory is not
    -- armed then (Rules.Disarm), and no sound plays on it, however the set
    -- differs from the previous one.
    if ns.Rules.HasSound(rules) then
        ns.Rules.Play(ns.Rules.Settle(watch))
    end
end

--- Take the standard grid away.
--
-- The grid's names are asked of the core (Darken:GetFrameNames("auras")): the
-- compatibility layer is the only place that knows Blizzard's frame names, and
-- a list of our own beside it would diverge from the client silently. On a
-- client where these windows do not exist the list is empty, and there is
-- simply nothing to move away.
--
-- Exactly what was named and what exists on this client is taken, and every
-- frame taken is written into the ledger. The move goes through the contract's
-- handle:Secure: protectedness is asked of the object rather than guessed from
-- a name, and on the unprotected aura grid that means "right now".
--
-- @param handle table the module's descriptor
local function TakeGrid(handle)
    local holder = Hidden()
    local names, frames = ns.Grid.Names(Darken:GetFrameNames("auras"))

    for i = 1, #names do
        local frame = frames[i]
        if ns.Grid.Held(grid, frame) == nil then
            handle:Secure(frame, "grid:" .. names[i], function()
                ns.Grid.Take(grid, frame, holder)
            end)
        end
    end
end

--- Start drawing.
-- @param handle table
local function Start(handle)
    if drawing then return end
    drawing = true

    -- There is nothing to compare what was drawn against either, and for the
    -- same reason: a module that was switched on draws the grid from nothing
    -- rather than finishing what it left behind an hour ago.
    stale = true

    -- The memory of endings starts empty: before the first repaint there is
    -- nothing to compare against, and the module being switched on has no
    -- right to sound like forty auras that ended.
    ns.Rules.Disarm(watch)

    if ticker == nil then
        ticker = NewFrame(UIParent) or false
        if ticker then
            if type(ticker.SetScript) == "function" then
                ticker:SetScript("OnUpdate", Tick)
            end
            if type(ticker.Hide) == "function" then ticker:Hide() end
            tickerShown = false
        end
    end

    TakeGrid(handle)
end

--- Stop drawing and give the player their grid back.
--
-- The return happens here rather than at a reload of the interface, and that
-- is the specification's requirement: a module that was switched off is
-- obliged to give the standard grid back at once. The return is possible
-- because it was taken with a record — see Grid.lua.
local function Stop()
    if not drawing then return end
    drawing = false

    -- Everything drawn leaves the screen, and the next repaint will have
    -- nothing to compare against.
    stale = true

    -- A module that was switched off does not read auras, and everything it
    -- saw is stale: it will be switched on an hour later, and "it ended" would
    -- mean "it ended at some point".
    ns.Rules.Disarm(watch)

    -- The foreign icons are let go before our own: ours we hide, somebody
    -- else's we give back, and it has to be given back in any case, however
    -- the rest of the tidying ends.
    UnitsStop()

    ReleaseAll()
    for key, holder in pairs(holders) do
        if holder and type(holder.Hide) == "function" then holder:Hide() end
    end
    if ticker and type(ticker.Hide) == "function" then
        ticker:Hide()
        tickerShown = false
    end

    ns.Grid.Restore(grid)
end

-- The events. The subscription goes through the core (the contract,
-- handle:RegisterEvent): the module has no receiver of its own, and a handler
-- that raises will disable the module rather than bring the addon down.
--
-- There is not one timer in the list and there must not be: the set of auras
-- arrives as an event about a particular unit, while the time runs its own
-- course in Tick.
local EVENTS = {
    { "UNIT_AURA", function(_, unit)
        if unit == "player" then Redraw() end
        -- A change of another unit's auras wakes the pass only when that
        -- unit's icons are on our ledger: the event arrives for everybody
        -- around, and waking for somebody else's would mean paying for a scan
        -- for nothing.
        if ns.Units.Watches(units, unit) then UnitsWake(false) end
    end },
    -- The target, the focus and the group's composition: the icons under them
    -- are either different or new. The focus event does not exist on every
    -- client, and that is not a refusal — the core subscribes through pcall,
    -- and an unknown event simply is not created.
    { "PLAYER_TARGET_CHANGED", function() UnitsWake(true) end },
    { "PLAYER_FOCUS_CHANGED",  function() UnitsWake(true) end },
    { "GROUP_ROSTER_UPDATE",   function() UnitsWake(true) end },
    -- Entering the world creates the standard grid afresh, and what was
    -- taken has to be taken again: otherwise the player will see two grids at
    -- once.
    --
    -- Entering the world also creates the set of auras afresh, and the first
    -- reading after it has nothing to be compared with: the auras arrive one
    -- by one, and the zone may have changed along with half the buffs. So the
    -- memory of endings is disarmed — otherwise a change of zone would sound
    -- like the ending of everything the player carried.
    { "PLAYER_ENTERING_WORLD", function()
        if drawing and module then
            ns.Rules.Disarm(watch)
            -- What was drawn belongs to the previous world: the game's
            -- frames were created afresh, and it cannot be compared against
            -- for exactly the same reason the set of auras cannot. Once per
            -- loading screen.
            stale = true
            TakeGrid(module)
            Redraw()
        end
        -- After entering the world the unit frames were created afresh, and
        -- the former icons are objects of the previous world session.
        UnitsWake(true)
    end },
    -- Leaving combat. An icon born in combat arrives without the secure
    -- overlay: the engine does not allow creating a protected frame in combat
    -- (Mouse.Overlay), and nobody else will take it on — the next change of
    -- auras may not happen for hours, and all that time the player would be
    -- right-clicking at nothing, and silently. One repaint on leaving combat
    -- closes that by exactly the word that was promised: there is no overlay
    -- until the fight ends, not until the next change of auras.
    --
    -- The core keeps the order: it dispatches its own subscriptions before the
    -- modules' (Core/Events.lua, Events.Dispatch), so by this moment the
    -- combat queue has been drained, and the repaint's aims are written at
    -- once rather than landing under deferred work that would overwrite them
    -- with the former state.
    { "PLAYER_REGEN_ENABLED", function()
        if drawing then Redraw() end
        -- The foreign icons do not freeze in combat — the engine protects
        -- neither opacity nor taking the mouse — but the game rearranges its
        -- own auras on leaving combat, and deciding about them afresh costs
        -- one pass.
        UnitsWake(false)
    end },
}

--- The get/set handlers for a numeric setting.
-- @param field string
-- @return function, function
local function handlers(field)
    return function()
        local settings = Settings()
        return settings and settings[field]
    end,
    function(_, value)
        local settings = Settings()
        if not settings then return end
        settings[field] = value
        module:Apply()
    end
end

--- The get/set handlers for a switch.
-- @param field string
-- @return function, function
local function toggles(field)
    return function()
        local settings = Settings()
        return settings and settings[field] and true or false
    end,
    function(_, value)
        local settings = Settings()
        if not settings then return end
        settings[field] = value and true or false
        module:Apply()
    end
end

local getSize,    setSize    = handlers("size")
local getPerRow,  setPerRow  = handlers("perRow")
local getSpacing, setSpacing = handlers("spacing")
local getDirection, setDirection = handlers("direction")

local getMode,    setMode    = handlers("filterMode")
local getList,    setList    = handlers("filterList")

local getEnabled, setEnabled = toggles("enabled")
local getOnlyMine, setOnlyMine = toggles("onlyMine")
local getHideBuffs,   setHideBuffs   = toggles("hideBuffs")
local getHideDebuffs, setHideDebuffs = toggles("hideDebuffs")
local getTime,    setTime    = toggles("showTime")
local getStacks,  setStacks  = toggles("showStacks")
local getSeparate, setSeparate = toggles("separate")
local getMouse,   setMouse   = toggles("mouse")
local getUnits,   setUnits   = toggles("units")

--- The labels of the directions of growth, for the dropdown.
-- Assembled at the moment the list is drawn: before the core hands over the
-- descriptor there is nobody to translate them.
-- @return table name -> label
local function directionValues()
    return {
        downleft  = ns.Localize("Down and to the left"),
        downright = ns.Localize("Down and to the right"),
        upleft    = ns.Localize("Up and to the left"),
        upright   = ns.Localize("Up and to the right"),
    }
end

--- The labels of what the list of spells does.
--
-- Three values and not one more. The default is "nothing": the typed list
-- stays typed while the filter is off, and a fresh install hides nothing.
-- There is no separate "switch the filter off" beside the list: two settings,
-- each of which can switch the filter off, give the player two places for one
-- question — "why do I not see an aura".
--
-- @return table name -> label
local function modeValues()
    return {
        off   = ns.Localize("Nothing - keep the list, ignore it"),
        deny  = ns.Localize("Hide the Listed Spells"),
        allow = ns.Localize("Show Only the Listed Spells"),
    }
end

--============================================================================
-- The rules for a single aura: the settings section
--============================================================================
--
-- The construction is taken from the bag rules and the nameplate rules rather
-- than invented afresh: a choice list of rules with the number in the label
-- (the number is the precedence), the fields for the chosen rule, and the
-- buttons for adding, trying earlier, trying later and forgetting. A player
-- who learnt to create a rule in the bags does not learn it a third time.

--- The list of rules from the settings.
-- @return table
local function ruleList()
    return ns.Rules.List(Settings())
end

--- The chosen rule's name, if it still exists.
-- A rule may have been forgotten while the choice stayed: the comparison is
-- made against the live list rather than against the window's memory.
-- @return string|nil
local function chosenRule()
    local want = module and module.ruleChoice
    if want == nil then return nil end

    local _, rule = ns.Rules.Find(ruleList(), want)
    if rule == nil then return nil end
    return rule.name
end

--- The chosen rule in full.
-- @return table|nil
local function chosenEntry()
    local chosen = chosenRule()
    if chosen == nil then return nil end
    local _, rule = ns.Rules.Find(ruleList(), chosen)
    return rule
end

--- A readable refusal line for a refusal code.
-- The place that decides produces the code, the place that shows it chooses
-- the phrase: the translation lives here.
-- @param why string|nil
-- @return string
local function ruleProblem(why)
    if why == "noname" then
        return ns.Localize("a rule needs a name")
    elseif why == "notext" then
        return ns.Localize("a rule needs at least one spell name or id")
    elseif why == "taken" then
        return ns.Localize("there is already a rule with that name")
    elseif why == "long" then
        return ns.Localize("that name is too long")
    elseif why == "full" then
        return ns.Localize("there is no room for another rule")
    end
    return ns.Localize("that rule is gone")
end

--- The caption of the list of rules.
-- @return string
local function rulesText()
    local list = ruleList()
    if #list == 0 then
        return ns.Localize("No rules yet, so every icon looks the same. A "
            .. "rule names spells - by name, or by spell id for a name that "
            .. "is different in every language - and gives them their own "
            .. "icon size, their own border color and a sound when they run "
            .. "out. Rules are tried from the top down, and the first one "
            .. "that names a spell wins it.")
    end

    local out = {}
    for i = 1, #list do
        local rule = list[i]
        if type(rule) == "table" and rule.name ~= nil then
            out[#out + 1] = string.format(ns.Localize("%d. %s"), i, rule.name)
        end
    end
    return table.concat(out, "\n")
end

-- The labels of the palette's colours. The names come from the skin
-- (skin.Colors), and the choice list is built from them rather than from a
-- list of our own: the palette belongs to the core, and a copy of the names
-- would diverge from it silently. There is a translation for the names the
-- palette declares today; one that appears tomorrow will be shown under its
-- own name, and that is better than not being shown at all.
local function colorLabel(name)
    if name == "ink" then return ns.Localize("Ink") end
    if name == "panel" then return ns.Localize("Panel") end
    if name == "panelAlt" then return ns.Localize("Panel, darker") end
    if name == "line" then return ns.Localize("Line - the usual border") end
    if name == "lilac" then return ns.Localize("Lilac") end
    if name == "lilacDeep" then return ns.Localize("Lilac, deep") end
    if name == "text" then return ns.Localize("Text") end
    if name == "textDim" then return ns.Localize("Text, dim") end
    return tostring(name)
end

--- The names of the palette's colours, for the choice list.
-- @return table name -> label
local function colorValues()
    local out = {}
    local skin = currentSkin()
    if skin and type(skin.Colors) == "function" then
        local names = skin.Colors()
        for i = 1, #names do out[names[i]] = colorLabel(names[i]) end
    end
    -- There is no palette at all (a core without a skin) — then let the list
    -- hold at least the ordinary border: an empty choice list cannot be chosen
    -- from.
    if next(out) == nil then out[ns.Icon.BORDER_COLOR] = colorLabel(ns.Icon.BORDER_COLOR) end
    return out
end

local options = {
    type = "group",
    -- The labels are functions rather than strings: the table is assembled
    -- at file level, that is, before the core hands over the descriptor, and
    -- without it there is nobody to translate them.
    name = function() return ns.Localize("Darken Auras") end,
    args = {
        about = {
            type = "description",
            order = 1,
            width = "full",
            name = function() return ns.Localize("Draws Darken's own grid "
                .. "of buffs and debuffs instead of the game's: your own icon "
                .. "size, icons per row, growth direction, time left and "
                .. "stack count. Off by default - a fresh install changes "
                .. "nothing. Switching it off puts the game's own grid back "
                .. "straight away, with no interface reload.") end,
        },
        enabled = {
            type = "toggle",
            order = 2,
            width = "full",
            name = function() return ns.Localize("Draw Our Own Auras") end,
            desc = function() return ns.Localize("Off leaves the game's own "
                .. "buff and debuff grid exactly as it is, which is what a "
                .. "fresh install does.") end,
            get = getEnabled,
            set = setEnabled,
        },
        size = {
            type = "range",
            order = 3,
            width = "full",
            name = function() return ns.Localize("Icon Size") end,
            min = BOUNDS.size.min, max = BOUNDS.size.max, step = 1,
            get = getSize,
            set = setSize,
        },
        perRow = {
            type = "range",
            order = 4,
            width = "full",
            name = function() return ns.Localize("Icons Per Row") end,
            min = BOUNDS.perRow.min, max = BOUNDS.perRow.max, step = 1,
            get = getPerRow,
            set = setPerRow,
        },
        direction = {
            type = "select",
            order = 5,
            width = "full",
            name = function() return ns.Localize("Growth Direction") end,
            desc = function() return ns.Localize("Where the grid grows from "
                .. "its first icon: rows go one way, each row fills the "
                .. "other.") end,
            values = directionValues,
            get = getDirection,
            set = setDirection,
        },
        showTime = {
            type = "toggle",
            order = 6,
            width = "full",
            name = function() return ns.Localize("Show Time Left") end,
            get = getTime,
            set = setTime,
        },
        showStacks = {
            type = "toggle",
            order = 7,
            width = "full",
            name = function() return ns.Localize("Show Stack Count") end,
            desc = function() return ns.Localize("A single stack is not "
                .. "written out: a \"1\" on every icon takes room and says "
                .. "nothing.") end,
            get = getStacks,
            set = setStacks,
        },
        separate = {
            type = "toggle",
            order = 8,
            width = "full",
            name = function() return ns.Localize("Separate Your Own Effects") end,
            desc = function() return ns.Localize("Effects you cast yourself "
                .. "come first and everyone else's start on a fresh row.") end,
            get = getSeparate,
            set = setSeparate,
        },
        mouse = {
            type = "toggle",
            order = 9,
            width = "full",
            name = function() return ns.Localize("Tooltip and Right-Click to "
                .. "Cancel") end,
            desc = function() return ns.Localize("Pointing at an icon shows "
                .. "the game's own description of the aura, and right-"
                .. "clicking a buff cancels it - the two things the game's "
                .. "own grid does. Cancelling is an action the game forbids "
                .. "in combat, so in combat the right click does nothing at "
                .. "all: cancelling the wrong aura would be worse than "
                .. "cancelling none. The tooltip works in combat like "
                .. "everywhere else.") end,
            get = getMouse,
            set = setMouse,
        },
        units = {
            type = "toggle",
            -- Deliberately below the filter and below the grid's placement:
            -- the setting answers the question "where else does this apply",
            -- and the answer to that is read after "this" itself has been
            -- read.
            order = 18,
            width = "full",
            name = function() return ns.Localize("Also on Target, Focus and "
                .. "Party") end,
            desc = function() return ns.Localize("Carries the filter and the "
                .. "rules onto the auras the game draws on unit frames: a "
                .. "spell you hid here stops showing up on your target too, "
                .. "and a rule's border color reaches it. The game keeps the "
                .. "layout - those icons belong to its own frames, and "
                .. "taking them over would mean re-laying them out in "
                .. "combat, on frames the game protects. Off by default.") end,
            get = getUnits,
            set = setUnits,
        },
        -- The aura's kind as an axis of filtering. Two switches, one per
        -- block, and both deliberately above the list: they answer the
        -- question "do I need this block at all", while the list answers "what
        -- to remove from it". The broad is read before the narrow.
        --
        -- They do not reduce to one setting of three values: "only mine"
        -- narrows the buffs, while debuffs have no middle value at all — on
        -- the player they are applied by anybody but themselves.
        hideBuffs = {
            type = "toggle",
            order = 10,
            width = "full",
            name = function() return ns.Localize("Hide All Buffs") end,
            desc = function() return ns.Localize("The whole block of buffs "
                .. "stops being drawn - that is what this asks for, and an "
                .. "empty block takes no room on the screen. The spell list "
                .. "is senior to it: with the list set to \"Show Only the "
                .. "Listed Spells\", a listed buff still shows. Off by "
                .. "default.") end,
            get = getHideBuffs,
            set = setHideBuffs,
        },
        hideDebuffs = {
            type = "toggle",
            order = 11,
            width = "full",
            name = function() return ns.Localize("Hide All Debuffs") end,
            desc = function() return ns.Localize("The whole block of debuffs "
                .. "stops being drawn, the same way. Debuffs are what other "
                .. "things put on you, so this one has no \"only mine\" of "
                .. "its own: there would be nothing left to narrow. Off by "
                .. "default.") end,
            get = getHideDebuffs,
            set = setHideDebuffs,
        },
        -- The only line the player sees in just one combination of
        -- settings, and it exists precisely because that combination is an
        -- empty screen. Both settings are honestly named, and the sum of two
        -- "hide everything" is arithmetic rather than a trap; but the
        -- standard grid has been moved away by that moment, and it is we who
        -- have to say so, not the fight.
        --
        -- This is asked not of the two switches but of the compiled plan —
        -- ns.Filter.Blank — and asked for the same reason the filter lies in
        -- one file at all: "the block cannot show anything" has to be
        -- computed in one place. A list in the "show only these" mode
        -- outranks the switch, and while such a list is typed the line is not
        -- shown: there is no emptiness.
        hideBoth = {
            type = "description",
            order = 12,
            width = "full",
            hidden = function()
                return not (ns.Filter.Blank(plan, false)
                    and ns.Filter.Blank(plan, true))
            end,
            name = function() return ns.Localize("Both are on, so no aura is "
                .. "drawn at all - and the game's own grid is already gone. "
                .. "Only the spell list can bring anything back: set it to "
                .. "\"Show Only the Listed Spells\" and name what you want "
                .. "to keep.") end,
        },
        onlyMine = {
            type = "toggle",
            order = 13,
            width = "full",
            -- Greyed out where the buffs are hidden entirely: there is
            -- nothing left to narrow, and a live switch that changes nothing
            -- is a second place where the player looks for the answer to "why
            -- do I not see an aura".
            disabled = getHideBuffs,
            name = function() return ns.Localize("Show Only Buffs You Cast") end,
            desc = function() return ns.Localize("Buffs put on you by other "
                .. "players stop being drawn. Debuffs are never touched by "
                .. "this: what lands on you from outside is exactly what you "
                .. "need to see. With \"hide all buffs\" on there is nothing "
                .. "left for this to narrow, and it is greyed out.") end,
            get = getOnlyMine,
            set = setOnlyMine,
        },
        filterMode = {
            type = "select",
            order = 14,
            width = "full",
            name = function() return ns.Localize("What the Spell List Does") end,
            desc = function() return ns.Localize("An empty list does nothing "
                .. "whichever of these is chosen.") end,
            values = modeValues,
            get = getMode,
            set = setMode,
        },
        filterList = {
            type = "input",
            order = 15,
            width = "full",
            multiline = 5,
            name = function() return ns.Localize("Spell List") end,
            desc = function() return ns.Localize("One spell per line, or "
                .. "separated by commas. A spell id - a number - matches that "
                .. "one spell exactly and keeps working when you change the "
                .. "client's language; a name matches whatever this client "
                .. "calls the spell, and two different spells can share a "
                .. "name.") end,
            get = getList,
            set = setList,
        },
        spacing = {
            type = "range",
            order = 16,
            width = "full",
            name = function() return ns.Localize("Spacing Between Icons") end,
            min = BOUNDS.spacing.min, max = BOUNDS.spacing.max, step = 1,
            get = getSpacing,
            set = setSpacing,
        },
        -- Where the grid stands is no longer set by two sliders. A slider
        -- knew neither a grid nor snapping, and repeating a position on a
        -- second character with one was only possible by retyping the numbers
        -- by hand.
        --
        -- There is deliberately no "show the handles" button of our own here:
        -- the overlay has one switch for the whole addon, and a second one in
        -- a module's section would be a second switch for one and the same
        -- thing.
        --
        -- NOTE: the text below sends the player to the Darken mover, and the
        -- mover is no longer in the core — see the note by the migration of
        -- the grid's old position. Until it is back, or until the wording is
        -- changed, this line names a command that does nothing.
        place = {
            type = "description",
            order = 17,
            width = "full",
            name = function() return ns.Localize("The grid is placed with "
                .. "the Darken mover: type /darken move and drag the box "
                .. "labelled Compact Auras, the same way you place "
                .. "everything else on screen. \"Reset Every Element\" in "
                .. "the mover's own settings puts it back.") end,
        },

        -- === The rules for a single aura ===
        rulesAbout = {
            type = "description",
            order = 16,
            width = "full",
            name = function() return ns.Localize("A rule gives named spells "
                .. "an icon of their own: its own size, its own border color "
                .. "and a sound when it runs out. A rule never shows an aura "
                .. "the spell list hides, and never hides one it shows - "
                .. "what to draw is the list's answer, and a rule only says "
                .. "how. With no rules nothing changes.") end,
        },
        rulesList = {
            type = "description",
            order = 17,
            width = "full",
            name = rulesText,
        },
        rulePick = {
            type = "select",
            order = 18,
            width = "full",
            name = function() return ns.Localize("Rule to Edit") end,
            desc = function() return ns.Localize("Pick a rule to change it, "
                .. "move it or forget it. Leave it unpicked, and the fields "
                .. "below describe a new rule instead.") end,
            values = function()
                local out = {}
                local list = ruleList()
                for i = 1, #list do
                    local rule = list[i]
                    local name = type(rule) == "table" and rule.name or nil
                    if name ~= nil then
                        -- The number is in the label because the number is
                        -- the precedence: it settles two rules over one aura,
                        -- and a list in which it cannot be seen would hide
                        -- the only thing the dispute is settled by.
                        out[name] = string.format(ns.Localize("%d. %s"), i, name)
                    end
                end
                return out
            end,
            get = function() return chosenRule() end,
            set = function(_, value)
                if module then module.ruleChoice = value end
            end,
        },
        ruleNew = {
            type = "execute",
            order = 19,
            name = function() return ns.Localize("Start a New Rule") end,
            func = function()
                if not module then return end
                module.ruleChoice = nil
                module.ruleDraftName = nil
                module.ruleDraftText = nil
            end,
        },
        ruleName = {
            type = "input",
            order = 20,
            width = "full",
            name = function() return ns.Localize("Rule Name") end,
            desc = function() return ns.Localize("Yours, not the game's: it "
                .. "is how the rule is named in the list above.") end,
            get = function()
                local chosen = chosenRule()
                if chosen ~= nil then return chosen end
                return module and module.ruleDraftName or ""
            end,
            set = function(_, value)
                if not module then return end

                local chosen = chosenRule()
                if chosen == nil then
                    module.ruleDraftName = value
                    return
                end

                local ok, why = ns.Rules.Rename(ruleList(), chosen, value)
                if not ok then
                    module:Print(ruleProblem(why))
                    return
                end
                module.ruleChoice = value
                module:Apply()
            end,
        },
        ruleText = {
            type = "input",
            order = 21,
            width = "full",
            multiline = 4,
            name = function() return ns.Localize("Spells") end,
            desc = function() return ns.Localize("Spell names, separated by "
                .. "commas or written one per line, and capitals do not "
                .. "matter. An entry of digits only is read as a spell id "
                .. "instead - the same door the spell list above uses.") end,
            get = function()
                local chosen = chosenRule()
                if chosen ~= nil then
                    local rule = chosenEntry()
                    return rule and rule.text or ""
                end
                return module and module.ruleDraftText or ""
            end,
            set = function(_, value)
                if not module then return end

                local chosen = chosenRule()
                if chosen == nil then
                    module.ruleDraftText = value
                    return
                end

                local ok, why = ns.Rules.SetText(ruleList(), chosen, value)
                if not ok then
                    module:Print(ruleProblem(why))
                    return
                end
                module:Apply()
            end,
        },
        ruleSize = {
            type = "range",
            order = 22,
            width = "full",
            name = function() return ns.Localize("Size of Those Icons") end,
            desc = function() return ns.Localize("Multiplies the icon size "
                .. "set above, so one means no change at all. The icon grows "
                .. "inside its own cell of the grid and the grid itself does "
                .. "not move: the set of auras changes constantly, and a grid "
                .. "that laid itself out again around one aura would never "
                .. "stand still.") end,
            disabled = function() return chosenRule() == nil end,
            min = ns.Rules.SCALE.min, max = ns.Rules.SCALE.max, step = 0.05,
            get = function()
                local rule = chosenEntry()
                if rule == nil then return ns.Rules.SCALE.default end
                return ns.Rules.Scale(rule.scale)
            end,
            set = function(_, value)
                local chosen = chosenRule()
                if chosen == nil or not module then return end
                if ns.Rules.SetScale(ruleList(), chosen, value) then
                    module:Apply()
                end
            end,
        },
        ruleRecolor = {
            type = "toggle",
            order = 23,
            name = function() return ns.Localize("Give It Its Own Border") end,
            desc = function() return ns.Localize("Off leaves the border the "
                .. "usual color and the rule changes the size only.") end,
            disabled = function() return chosenRule() == nil end,
            get = function()
                local rule = chosenEntry()
                return type(rule) == "table" and type(rule.color) == "string"
            end,
            set = function(_, value)
                local chosen = chosenRule()
                if chosen == nil or not module then return end

                ns.Rules.SetColor(ruleList(), chosen, value and "lilac" or nil)
                module:Apply()
            end,
        },
        ruleColor = {
            type = "select",
            order = 24,
            width = "full",
            name = function() return ns.Localize("Border Color") end,
            desc = function() return ns.Localize("From the addon's own "
                .. "palette, so the icon stays part of the same interface "
                .. "when the palette changes.") end,
            disabled = function()
                local rule = chosenEntry()
                return type(rule) ~= "table" or type(rule.color) ~= "string"
            end,
            values = colorValues,
            get = function()
                local rule = chosenEntry()
                if type(rule) ~= "table" or type(rule.color) ~= "string" then
                    return ns.Icon.BORDER_COLOR
                end
                return rule.color
            end,
            set = function(_, value)
                local chosen = chosenRule()
                if chosen == nil or not module then return end
                if ns.Rules.SetColor(ruleList(), chosen, value) then
                    module:Apply()
                end
            end,
        },
        ruleSound = {
            type = "toggle",
            order = 25,
            width = "full",
            name = function() return ns.Localize("Sound When It Runs Out") end,
            desc = function() return ns.Localize("Plays the game's warning "
                .. "sound once when one of these auras is gone from you. "
                .. "Only that: an aura that stopped being drawn because you "
                .. "changed a setting, and auras missing because you have "
                .. "just zoned in, make no sound at all - a sound that lies "
                .. "is worse than no sound.") end,
            disabled = function() return chosenRule() == nil end,
            get = function()
                local rule = chosenEntry()
                return type(rule) == "table" and rule.sound and true or false
            end,
            set = function(_, value)
                local chosen = chosenRule()
                if chosen == nil or not module then return end
                if ns.Rules.SetSound(ruleList(), chosen, value) then
                    module:Apply()
                end
            end,
        },
        ruleAdd = {
            type = "execute",
            order = 26,
            name = function() return ns.Localize("Add This Rule") end,
            disabled = function() return chosenRule() ~= nil end,
            func = function()
                if not module then return end

                local rule, why = ns.Rules.Add(ruleList(),
                    module.ruleDraftName, module.ruleDraftText)
                if rule == nil then
                    module:Print(ruleProblem(why))
                    return
                end

                module.ruleChoice = rule.name
                module.ruleDraftName = nil
                module.ruleDraftText = nil
                module:Apply()
            end,
        },
        ruleUp = {
            type = "execute",
            order = 27,
            name = function() return ns.Localize("Try This Rule Earlier") end,
            disabled = function() return chosenRule() == nil end,
            func = function()
                local chosen = chosenRule()
                if chosen == nil then return end
                if ns.Rules.Move(ruleList(), chosen, -1) then module:Apply() end
            end,
        },
        ruleDown = {
            type = "execute",
            order = 28,
            name = function() return ns.Localize("Try This Rule Later") end,
            disabled = function() return chosenRule() == nil end,
            func = function()
                local chosen = chosenRule()
                if chosen == nil then return end
                if ns.Rules.Move(ruleList(), chosen, 1) then module:Apply() end
            end,
        },
        ruleForget = {
            type = "execute",
            order = 29,
            name = function() return ns.Localize("Forget This Rule") end,
            disabled = function() return chosenRule() == nil end,
            func = function()
                local chosen = chosenRule()
                if chosen == nil then return end
                if ns.Rules.Remove(ruleList(), chosen) then
                    module.ruleChoice = nil
                    module:Print(string.format(
                        ns.Localize("forgot the rule %s"), chosen))
                    module:Apply()
                end
            end,
        },
    },
}

local handle, reason = Darken:RegisterModule({
    name = "umbraauras",
    api  = API,

    -- The defaults: switched off. A fresh install changes nothing on screen,
    -- and the game's native behaviour stays not only the initial one but also
    -- a choice.
    defaults = {
        enabled    = false,
        size       = BOUNDS.size.default,
        perRow     = BOUNDS.perRow.default,
        spacing    = BOUNDS.spacing.default,
        direction  = Layout.DEFAULT_DIRECTION,
        showTime   = true,
        showStacks = true,
        separate   = true,

        -- The mouse is on: the standard grid the module moves away has a
        -- tooltip and buff cancelling, and switching them off by default
        -- would mean handing the player a replacement able to do less than
        -- the original. A fresh install is not changed by this at all: the
        -- module itself is off.
        mouse      = true,

        -- Auras on unit frames are off. This is the module's only part that
        -- touches foreign frames on screen all the time rather than only in
        -- place of the standard grid, and switching it on for the player is
        -- not allowed.
        units      = false,

        -- The filter: it hides nothing. The list is empty, the mode is
        -- "nothing", "only mine" is off. A filter's default has to be "show
        -- what the game would show": the player discovers something needed
        -- that was hidden in a raid.
        filterMode = ns.Filter.DEFAULT_MODE,
        filterList = "",
        onlyMine   = false,

        -- The aura's kind as an axis of filtering: one switch per block,
        -- both off. A switch that is on puts its block out entirely — the
        -- setting itself says so, and that is why it is a setting rather than
        -- a failure.
        hideBuffs   = false,
        hideDebuffs = false,

        -- There is not one rule. They deliberately have no switch of their
        -- own: with an empty list it would switch nothing off, and with a
        -- non-empty one it would be a second way of saying the same thing.
        rules      = {},
    },

    options = options,

    OnEnable = function(self)
        -- The descriptor is taken from self, and that is still correct but
        -- no longer required: since contract version 16 RegisterModule
        -- returns the descriptor before the core calls the handlers, and the
        -- module variable has been assigned by that moment. The line is left
        -- as it is — it works on any version of the contract, and there is no
        -- reason to touch ten modules for its sake.
        module = module or self

        -- The mouse goes outwards through two of the core's doors, and the
        -- descriptor provides both: deferring work on a protected object, and
        -- the question about combat. Mouse.lua deliberately has no combat
        -- check of its own — it would diverge from the core's silently, and
        -- cancelling a buff would miss in combat.
        ns.Mouse.Setup({
            Secure = function(object, key, action)
                return self:Secure(object, key, action)
            end,
            InCombat = function() return self:InCombat() end,
        })

        for i = 1, #EVENTS do
            self:RegisterEvent(EVENTS[i][1], EVENTS[i][2])
        end

        self:RegisterCommand("auras", function()
            local own = self:GetSettings()
            if not own then return end
            own.enabled = not own.enabled
            self:Apply()
            self:Print(own.enabled
                and ns.Localize("compact auras on")
                or  ns.Localize("compact auras off"))
        end)
    end,

    ApplySettings = function(self)
        module = module or self

        -- One path of application: entering the game, changing the profile
        -- and editing any setting all lead here.
        local settings = self:GetSettings()
        if not settings then return end

        -- The grid's origin is placed here rather than in the enabling: the
        -- core brings a disabled module back into service without repeating
        -- OnEnable, and a declaration made there would be gone along with the
        -- handle forever. It is done with the module switched off as well:
        -- the grid's position is a setting, and the player is entitled to set
        -- it before switching the auras on.
        Publish(self)

        -- And right after that comes the migration of the old numeric
        -- position, if it still lies in the saved variables. Exactly once in
        -- a profile's whole life: there will be no second occasion, because
        -- the keys are erased.
        Adopt(self, settings)

        -- The filter's plan is compiled here and only here: this is the
        -- single place where entering the game, changing the profile and
        -- editing any setting converge. Parsing the list's string on every
        -- change of auras would cost the player frames and would give one and
        -- the same answer.
        plan = ns.Filter.Compile(settings)

        -- The rules are compiled here as well and for the same reason. The
        -- memory of endings is disarmed along with them: an edit of any
        -- setting may have removed an aura from the set through the filter or
        -- rewritten the rule itself, and an aura's disappearance after an
        -- edit means the edit rather than an ending.
        rules = ns.Rules.Compile(ns.Rules.List(settings))
        ns.Rules.Disarm(watch)

        -- And here is where the comparison against what was drawn is
        -- cancelled. Entering the game, changing the profile, editing any of
        -- the module's settings, changing the palette and changing the font
        -- (the core applies those through this same ApplySettings across the
        -- whole addon) all converge here — that is, everything after which an
        -- icon on screen may stay the same while it has to look different.
        -- The module has no second place where it learns the settings
        -- changed, which is why the flag is set once and in one place.
        stale = true

        if not settings.enabled then
            Stop()
            return
        end

        Start(self)
        Redraw()

        -- The foreign icons are decided about afresh after an edit of any
        -- setting: the filter may have stopped letting an aura through, a rule
        -- may have been rewritten. A setting that is off means a return rather
        -- than doing nothing — otherwise a transparent icon would be left on
        -- the target.
        if settings.units then
            UnitsWake(true)
        else
            UnitsStop()
        end
    end,

    OnDisable = function()
        -- A module that was switched off is obliged to stop drawing and to
        -- give the player the standard grid back: the core removes the
        -- subscriptions, and we the frames.
        Stop()
    end,
})

if not handle then
    -- The core has already shown the player the reason; there is nothing
    -- more to do.
    return
end

module = handle

-- The module's strings go into the core as soon as there is somebody to hand
-- them to: the settings section asks for a translation at the window's very
-- first drawing.
for locale, strings in pairs(ns.Strings or {}) do
    module:RegisterStrings(locale, strings)
end

--============================================================================
-- The settings page, declared as data
--============================================================================

-- The texts were carried over word for word: the move changes the window, not
-- the words. Every paragraph here is already written, already translated into
-- two languages and already explains exactly what is needed.
--
-- The order of the rows is taken from the former section and was not chosen by
-- accident. The broad is read before the narrow: "do I need this block at all"
-- stands above "what to remove from it", and "where else does this apply"
-- below "this" itself.
--
-- The rules for a single aura are not declared here yet: they need a list
-- editor of the widget kind, and there is one for three places — the aura
-- rules, the bag rules, the panel's cells. Inventing it three times means
-- getting three different editors of one and the same thing.

if type(core.Schema) == "table" then
    local Schema = core.Schema
    local PAGE = "umbraauras"

    Schema.Page(PAGE, {
        title = "Auras",
        order = 12,
        section = "umbraauras",
    })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "Draws Darken's own grid of buffs and debuffs instead of the "
            .. "game's: your own icon size, icons per row, growth direction, "
            .. "time left and stack count. Off by default - a fresh install "
            .. "changes nothing. Switching it off puts the game's own grid "
            .. "back straight away, with no interface reload.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Draw Our Own Auras",
        path = { "enabled" },
        apply = "umbraauras",
        hint = "Off leaves the game's own buff and debuff grid exactly as it "
            .. "is, which is what a fresh install does.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Icon Size",
        path = { "size" },
        min = BOUNDS.size.min, max = BOUNDS.size.max, step = 1,
        apply = "umbraauras",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Icons Per Row",
        path = { "perRow" },
        min = BOUNDS.perRow.min, max = BOUNDS.perRow.max, step = 1,
        apply = "umbraauras",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Growth Direction",
        path = { "direction" },
        apply = "umbraauras",
        hint = "Where the grid grows from its first icon: rows go one way, "
            .. "each row fills the other.",
        values = function()
            return {
                { key = "downleft",
                  text = ns.Localize("Down and to the left") },
                { key = "downright",
                  text = ns.Localize("Down and to the right") },
                { key = "upleft",
                  text = ns.Localize("Up and to the left") },
                { key = "upright",
                  text = ns.Localize("Up and to the right") },
            }
        end,
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show Time Left",
        path = { "showTime" },
        apply = "umbraauras",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show Stack Count",
        path = { "showStacks" },
        apply = "umbraauras",
        hint = "A single stack is not written out: a \"1\" on every icon "
            .. "takes room and says nothing.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Separate Your Own Effects",
        path = { "separate" },
        apply = "umbraauras",
        hint = "Effects you cast yourself come first and everyone else's "
            .. "start on a fresh row.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Tooltip and Right-Click to Cancel",
        path = { "mouse" },
        apply = "umbraauras",
        hint = "Pointing at an icon shows the game's own description of the "
            .. "aura, and right-clicking a buff cancels it - the two things "
            .. "the game's own grid does. Cancelling is an action the game "
            .. "forbids in combat, so in combat the right click does nothing "
            .. "at all: cancelling the wrong aura would be worse than "
            .. "cancelling none. The tooltip works in combat like everywhere "
            .. "else.",
    })

    Schema.Add(PAGE, { kind = "header", label = "What Gets Drawn" })

    -- The aura's kind as an axis of filtering: one switch per block, and
    -- both deliberately above the list. They do not reduce to one setting of
    -- three values: "only mine" narrows the buffs, while debuffs have no
    -- middle value at all — on the player they are applied by anybody but
    -- themselves.
    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Hide All Buffs",
        path = { "hideBuffs" },
        apply = "umbraauras",
        hint = "The whole block of buffs stops being drawn - that is what "
            .. "this asks for, and an empty block takes no room on the "
            .. "screen. The spell list is senior to it: with the list set to "
            .. "\"Show Only the Listed Spells\", a listed buff still shows. "
            .. "Off by default.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Hide All Debuffs",
        path = { "hideDebuffs" },
        apply = "umbraauras",
        hint = "The whole block of debuffs stops being drawn, the same way. "
            .. "Debuffs are what other things put on you, so this one has no "
            .. "\"only mine\" of its own: there would be nothing left to "
            .. "narrow. Off by default.",
    })

    -- The only line the player sees in just one combination of settings, and
    -- it exists precisely because that combination is an empty screen. Both
    -- settings are honestly named, and the sum of two "hide everything" is
    -- arithmetic rather than a trap; but the standard grid has been moved away
    -- by that moment, and it is we who have to say so, not the fight.
    --
    -- This is asked not of the two switches but of the compiled plan, and for
    -- the same reason the filter lies in one file at all: "the block cannot
    -- show anything" has to be computed in one place. A list in the "show only
    -- these" mode outranks the switch, and while such a list is typed the line
    -- is not shown: there is no emptiness.
    Schema.Add(PAGE, {
        kind = "note",
        hidden = function()
            return not (ns.Filter.Blank(plan, false)
                and ns.Filter.Blank(plan, true))
        end,
        hint = "Both are on, so no aura is drawn at all - and the game's own "
            .. "grid is already gone. Only the spell list can bring anything "
            .. "back: set it to \"Show Only the Listed Spells\" and name "
            .. "what you want to keep.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show Only Buffs You Cast",
        path = { "onlyMine" },
        apply = "umbraauras",
        -- Greyed out where the buffs are hidden entirely: there is nothing
        -- left to narrow, and a live switch that changes nothing is a second
        -- place where the player looks for the answer to "why do I not see an
        -- aura".
        disabled = function()
            local settings = Settings()
            return settings ~= nil and settings.hideBuffs == true
        end,
        hint = "Buffs put on you by other players stop being drawn. Debuffs "
            .. "are never touched by this: what lands on you from outside is "
            .. "exactly what you need to see. With \"hide all buffs\" on "
            .. "there is nothing left for this to narrow, and it is greyed "
            .. "out.",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "What the Spell List Does",
        path = { "filterMode" },
        apply = "umbraauras",
        hint = "An empty list does nothing whichever of these is chosen.",
        values = function()
            return {
                { key = "off",
                  text = ns.Localize("Nothing - keep the list, ignore it") },
                { key = "deny",
                  text = ns.Localize("Hide the Listed Spells") },
                { key = "allow",
                  text = ns.Localize("Show Only the Listed Spells") },
            }
        end,
    })

    Schema.Add(PAGE, {
        kind = "text",
        label = "Spell List",
        path = { "filterList" },
        apply = "umbraauras",
        lines = 5,
        hint = "One spell per line, or separated by commas. A spell id - a "
            .. "number - matches that one spell exactly and keeps working "
            .. "when you change the client's language; a name matches "
            .. "whatever this client calls the spell, and two different "
            .. "spells can share a name.",
    })

    Schema.Add(PAGE, { kind = "header", label = "Spacing and Place" })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Spacing Between Icons",
        path = { "spacing" },
        min = BOUNDS.spacing.min, max = BOUNDS.spacing.max, step = 1,
        apply = "umbraauras",
    })

    -- Where the grid stands is not set by two sliders. There is deliberately
    -- no "show the handles" button of our own here: the overlay has one switch
    -- for the whole addon, and a second one in a module's section would be a
    -- second switch for one and the same thing.
    --
    -- NOTE: the text below sends the player to the Darken mover, and the mover
    -- is no longer in the core — see the note by the migration of the grid's
    -- old position. Until it is back, or until the wording is changed, this
    -- line names a command that does nothing.
    Schema.Add(PAGE, {
        kind = "note",
        hint = "The grid is placed with the Darken mover: type /darken move "
            .. "and drag the box labelled Compact Auras, the same way you "
            .. "place everything else on screen. \"Reset Every Element\" in "
            .. "the mover's own settings puts it back.",
    })

    -- Deliberately below the filter and below the grid's placement: the
    -- setting answers the question "where else does this apply", and the
    -- answer to that is read after "this" itself has been read.
    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Also on Target, Focus and Party",
        path = { "units" },
        apply = "umbraauras",
        hint = "Carries the filter and the rules onto the auras the game "
            .. "draws on unit frames: a spell you hid here stops showing up "
            .. "on your target too, and a rule's border color reaches it. "
            .. "The game keeps the layout - those icons belong to its own "
            .. "frames, and taking them over would mean re-laying them out "
            .. "in combat, on frames the game protects. Off by default.",
    })
end

--============================================================================
-- The rules for a single aura: the list in the new window
--============================================================================

-- An adapter to the shared list editor. Five functions and not one line of
-- arithmetic: the order, the search, the creation and the removal are all
-- written in Rules.lua already and tested there.
--
-- The draft is the same one the former editor held (ruleDraftName and
-- ruleDraftText on the descriptor). A draft of our own would be a second one,
-- and what was typed in one window would vanish in the other.

if type(core.Schema) == "table" and type(core.ListEditor) == "table" then
    local Schema = core.Schema
    local PAGE = "umbraauras"

    --- The list of rules from the settings.
    local function list()
        return ns.Rules.List(Settings())
    end

    --- The rule itself, by name.
    local function entryOf(name)
        local _, rule = ns.Rules.Find(list(), name)
        return rule
    end

    --- Apply: a rule changes what is already drawn.
    local function applied()
        if module ~= nil then module:Apply() end
    end

    Schema.Add(PAGE, { kind = "header", label = "Rules" })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "A rule gives named spells an icon of their own: its own "
            .. "size, its own border color and a sound when it runs out. A "
            .. "rule never shows an aura the spell list hides, and never "
            .. "hides one it shows - what to draw is the list's answer, and "
            .. "a rule only says how. With no rules nothing changes.",
    })

    Schema.Add(PAGE, {
        kind = "widget",
        label = "Rule to Edit",
        build = core.ListEditor.Build,
        hook = {
            Entries = function() return list() end,

            --- Create a rule from the draft.
            -- Returns the created rule's name: the editor switches to it.
            -- @return string|nil
            Add = function()
                if module == nil then return nil end

                local name = module.ruleDraftName
                local rule, why = ns.Rules.Add(list(), name,
                    module.ruleDraftText)
                if rule == nil then
                    -- The refusal is explained in the same words as in the
                    -- former window: why the rule was not created is the
                    -- player's question, not ours.
                    module:Print(ruleProblem(why))
                    return nil
                end

                module.ruleDraftName, module.ruleDraftText = "", ""
                applied()
                return rule.name
            end,

            Remove = function(name)
                if ns.Rules.Remove(list(), name) then applied() end
            end,

            Move = function(name, delta)
                if ns.Rules.Move(list(), name, delta) then applied() end
            end,

            --- The fields of the chosen rule, or, with nothing chosen, the
            --- fields of the draft.
            -- @param chosen string|nil
            -- @return table
            Fields = function(chosen)
                local rows = {}

                rows[#rows + 1] = {
                    kind = "text",
                    label = "Rule Name",
                    apply = "none",
                    hint = "Yours, not the game's: it is how the rule is "
                        .. "named in the list above.",
                    get = function()
                        if chosen == nil then
                            return module and module.ruleDraftName or ""
                        end
                        return chosen
                    end,
                    set = function(value)
                        if module == nil then return end
                        if chosen == nil then
                            module.ruleDraftName = value
                            return
                        end
                        local ok, why = ns.Rules.Rename(list(), chosen, value)
                        if not ok then
                            module:Print(ruleProblem(why))
                            return
                        end
                        applied()
                    end,
                }

                rows[#rows + 1] = {
                    kind = "text",
                    label = "Spells",
                    apply = "none",
                    lines = 4,
                    hint = "Spell names, separated by commas or written one "
                        .. "per line, and capitals do not matter. An entry "
                        .. "of digits only is read as a spell id instead - "
                        .. "the same door the spell list above uses.",
                    get = function()
                        if chosen == nil then
                            return module and module.ruleDraftText or ""
                        end
                        local rule = entryOf(chosen)
                        return rule and rule.text or ""
                    end,
                    set = function(value)
                        if module == nil then return end
                        if chosen == nil then
                            module.ruleDraftText = value
                            return
                        end
                        local ok, why = ns.Rules.SetText(list(), chosen, value)
                        if not ok then
                            module:Print(ruleProblem(why))
                            return
                        end
                        applied()
                    end,
                }

                -- What follows cannot belong to a draft: the size, the
                -- colour and the sound belong to a rule that was created.
                -- Showing them empty beside "Add" means promising that what
                -- is typed into them will go somewhere.
                if chosen == nil then return rows end

                rows[#rows + 1] = {
                    kind = "slider",
                    label = "Size of Those Icons",
                    apply = "none",
                    min = ns.Rules.SCALE.min,
                    max = ns.Rules.SCALE.max,
                    step = 0.05,
                    hint = "Multiplies the icon size set above, so one means "
                        .. "no change at all. The icon grows inside its own "
                        .. "cell of the grid and the grid itself does not "
                        .. "move: the set of auras changes constantly, and a "
                        .. "grid that laid itself out again around one aura "
                        .. "would never stand still.",
                    get = function()
                        local rule = entryOf(chosen)
                        if rule == nil then return ns.Rules.SCALE.default end
                        return ns.Rules.Scale(rule.scale)
                    end,
                    set = function(value)
                        if ns.Rules.SetScale(list(), chosen, value) then
                            applied()
                        end
                    end,
                }

                rows[#rows + 1] = {
                    kind = "toggle",
                    label = "Give It Its Own Border",
                    apply = "none",
                    hint = "Off leaves the border the usual color and the "
                        .. "rule changes the size only.",
                    get = function()
                        local rule = entryOf(chosen)
                        return type(rule) == "table"
                            and type(rule.color) == "string"
                    end,
                    set = function(value)
                        local colour = value and ns.Icon.BORDER_COLOR or nil
                        if ns.Rules.SetColor(list(), chosen, colour) then
                            applied()
                        end
                    end,
                }

                rows[#rows + 1] = {
                    kind = "select",
                    label = "Border Color",
                    apply = "none",
                    hint = "From the addon's own palette, so the icon stays "
                        .. "part of the same interface when the palette "
                        .. "changes.",
                    -- Greyed out while the rule has no border of its own: a
                    -- colour that paints nothing is a second place where the
                    -- player looks for the answer to "why does nothing
                    -- change".
                    disabled = function()
                        local rule = entryOf(chosen)
                        return not (type(rule) == "table"
                            and type(rule.color) == "string")
                    end,
                    values = function()
                        local out = {}
                        for key, said in pairs(colorValues()) do
                            out[#out + 1] = { key = key, text = said }
                        end
                        table.sort(out, function(a, b) return a.key < b.key end)
                        return out
                    end,
                    get = function()
                        local rule = entryOf(chosen)
                        if type(rule) ~= "table"
                            or type(rule.color) ~= "string" then
                            return ns.Icon.BORDER_COLOR
                        end
                        return rule.color
                    end,
                    set = function(value)
                        if ns.Rules.SetColor(list(), chosen, value) then
                            applied()
                        end
                    end,
                }

                rows[#rows + 1] = {
                    kind = "toggle",
                    label = "Sound When It Runs Out",
                    apply = "none",
                    hint = "Plays the game's warning sound once when one of "
                        .. "these auras is gone from you. Only that: an aura "
                        .. "that stopped being drawn because you changed a "
                        .. "setting, and auras missing because you have just "
                        .. "zoned in, make no sound at all - a sound that "
                        .. "lies is worse than no sound.",
                    get = function()
                        local rule = entryOf(chosen)
                        return type(rule) == "table" and rule.sound == true
                    end,
                    set = function(value)
                        if ns.Rules.SetSound(list(), chosen, value) then
                            applied()
                        end
                    end,
                }

                return rows
            end,
        },
    })
end
