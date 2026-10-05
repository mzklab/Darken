local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- Darken's nameplate engine: nameplates of our own instead of the skinning of
-- the standard ones.
--
-- The file glues four parts together and does nothing else: the colour
-- (Colors.lua), the measurements (Geometry.lua), the ledger of what is
-- attached and the decision to stand aside (Engine.lua), the display
-- (Plate.lua). Registration with the core goes through the public contract
-- (docs/module-api.md) — the module lives in a folder of its own and is not
-- part of the core.
--
-- What this increment has: the health bar in our own texture, the colour by
-- class for players and by reaction for everybody else, the name and the level
-- in our own font, the highlight of the target's nameplate, and the width, the
-- height and the scale as settings.
--
-- What the second increment added: the cast bar on a nameplate, the aura icons
-- with a filter, the colour by threat, the quest icon and the shortening of
-- long names. All five are off by default: a fresh install still changes
-- nothing on screen.
--
-- What the third increment added: rules for a single unit — a colour and a
-- nameplate size of its own for a creature the player named. On a fresh
-- install there is not one rule, and an empty list changes nothing on screen.
--
-- What the fourth increment added: the positions of a nameplate's parts. The
-- name, the level, the cast bar, the aura icons, the quest icon and the
-- nameplate itself stand where the player put them. An empty setting means the
-- former look letter for letter, and that is tested by comparison against the
-- numbers that stood in the display before it existed.
--
-- One pure function decides the positions (ns.Arrange.Spec), one line of the
-- display writes them (ns.Plate.Place), and there is no second place in the
-- module that moves the parts — the same one-owner rule the colour and the
-- scale live by.
--
-- === How the things people usually poll are updated here ===
--
-- The cast bar and the aura icons are the two features most often written on
-- an OnUpdate. Neither of them is polled here.
--
-- The cast bar: the engine runs the bar's motion as a scale animation, and the
-- engine's own code computes it. Lua wakes on the cast's own events — the
-- start, a delay, an interruption, the end. That is a handful of times per
-- spell instead of sixty times a second on each of thirty nameplates.
--
-- The aura icons: the contents arrive as a UNIT_AURA event about a particular
-- unit, and the time left is drawn by the sweeping shade — the engine again,
-- and its own code again. There is deliberately no countdown label of our own
-- on an icon: it is the one and only thing a clock would have to be created
-- for.
--
-- === The three rules that must not be broken here ===
--
-- The pool. The game reuses nameplates. Everything is attached on the
-- "appeared for a unit" event and detached on "went away", and a frame that
-- returned to the pool carries nothing of ours on it — see Engine.Wipe and
-- Plate.Release.
--
-- Combat. There is not one deferred action here, and that is not
-- forgetfulness: our frames are children of UIParent and are not protected by
-- the engine, while on a foreign nameplate we touch one alpha, which the
-- engine does not protect either. Deferring the colour or the health until the
-- end of combat would mean not showing them when they are needed. The full
-- explanation is in Plate.lua's header.
--
-- There are no sweeps. No OnUpdate, no timer, no polling of the screen. Our
-- frame travels after the game's nameplate by an anchor, the health arrives as
-- an event about a particular unit, and the hot path (Plate.SetHealth)
-- allocates not one table.

-- The core is not taken on trust even through the TOC's dependency line: the
-- behaviour of "## Dependencies" on classic clients is unconfirmed, and the
-- core's absence has to give one readable line rather than a Lua error.
if type(Darken) ~= "table" or type(Darken.RegisterModule) ~= "function" then
    print("|cffff4040" .. ADDON .. "|r: Darken is not loaded, so this addon "
        .. "does nothing. Install Darken, or disable this addon.")
    return
end

-- The contract version the module is written against. The seventh, and
-- declared directly rather than asked about through Supports: the module uses
-- the core's textures and fonts (Darken:GetMedia), a slash-command word of its
-- own, standing a core subsystem aside (handle:Replaces) and the shared aura
-- filter (Darken:GetAuraFilter). Without standing the subsystem aside two
-- owners would paint one nameplate, and that is precisely the defect an engine
-- is written to forbid; without the shared filter the addon would have two
-- parsers for one and the same list of spells.
--
-- The ninth since the third increment: the rules for a single unit fold the
-- case of the typed name, and fold it with the core's table
-- (Darken:GetCasefold, contract version 9). A table of our own beside it would
-- diverge from the core's on the letter nobody checks — this addon has already
-- reconciled such copies twice.
--
-- The twelfth since the fourth: the labels at the edge take their inset from
-- the skin's scale (Metrics.edge, contract version 12). The same quantity used
-- to stand here as three numbers — 2 for the cast bar's label, -1 for the
-- level, -1 for the stack counter — that is, three labels at the edge of one
-- nameplate were pushed in differently, and not one of the three knew about
-- the other two.
local API = 12

-- The module takes the aura filter and the case folding from the core: they
-- are shared between several modules and therefore live in the core
-- (Darken:GetAuraFilter, version 7; Darken:GetCasefold, version 9). An older
-- core does not have these doors, ns.Filter and ns.Rules are then not created
-- at all, and that has to be said in one readable line — before the file runs
-- into the absence by itself.
if type(ns.Filter) ~= "table" or type(ns.Rules) ~= "table" then
    print("|cffff4040" .. ADDON .. "|r: this addon needs Darken module API "
        .. "version 9, and the installed Darken is older. Update Darken "
        .. "UI, or disable this addon.")
    return
end

local module

-- The tally of what was done. The core returns the table (the contract,
-- handle:Counters, version 17) and returns the table itself rather than a
-- function that increments: the counter stands on the path every nameplate
-- passes along, and a function call there would cost more than everything it
-- counts. It can only be taken after registration, so here there is a
-- declaration, and the filling in is below, beside the descriptor.
local counters

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

--- The core's skin right now: the palette and the scale of insets.
--
-- Asked for on every application rather than remembered while the file is
-- read. A plain assignment of Darken:GetSkin() used to stand here, and on the
-- current core it made no difference: the door is defined by the moment our
-- files are read, and behind the door is one and the same table. The
-- contract's rule is nevertheless to ask: a remembered skin outlives a change
-- of palette silently, and the nameplates would stay painted the old way
-- beside a window painted the new way.
--
-- It is asked for once per repaint rather than per creature: the question
-- costs one pcall, and the palette cannot change between two icons of one
-- nameplate.
--
-- @return table|nil
local function currentSkin()
    if type(Darken.GetSkin) ~= "function" then return nil end

    local ok, skin = pcall(Darken.GetSkin, Darken)
    if not ok or type(skin) ~= "table" then return nil end

    return skin
end

--- The core's media right now: the bar textures and the fonts.
-- The same way and for the same reason.
-- @return table|nil
local function currentMedia()
    if type(Darken.GetMedia) ~= "function" then return nil end

    local ok, media = pcall(Darken.GetMedia, Darken)
    if not ok or type(media) ~= "table" then return nil end

    return media
end

-- The marker for "the game's native texture". Taken from the core rather
-- than written as a string: the value goes into SavedVariables, and two copies
-- would diverge silently. This is a value of the contract rather than a door:
-- a string may be remembered, the table behind a door may not.
local NATIVE = (currentMedia() or {}).NATIVE or "__native"

--- The gap between the bar and the name.
-- From the skin's scale of insets rather than as a number: one and the same
-- distance on screen has to be set by one value. Asked for at the same time as
-- the skin itself.
-- @param skin table|nil
-- @return number
local function gapOf(skin)
    if type(skin) ~= "table" or type(skin.Metrics) ~= "function" then
        return 2
    end
    local metrics = skin.Metrics()
    return tonumber(metrics.hair) or tonumber(metrics.gap) or 2
end

-- The ledger of what is attached, and the pool of our frames.
local state = ns.Engine.NewState()
local pool  = ns.Plate.NewPool()

-- Whether we are drawing right now. Separate from the setting: the setting
-- can be switched on in the middle of a session.
local drawing = false

-- Whether the core's nameplate skinning is currently stood aside. It is
-- stood aside at the moment we start drawing and given back at the moment we
-- stop: handle:Releases is the other side of handle:Replaces, and without it a
-- switched-off engine would leave the player the native nameplates without the
-- core's skinning until the interface was reloaded.
local stoodDown = false

-- The table of a unit's information for choosing the colour. One for the
-- whole module and reused: the colour is chosen for every creature that
-- appears and on every change of reaction, and a table there would cost the
-- player frames.
local info = {}

-- The fallback colour is our muted text colour from the core's palette. The
-- table is one and reused for the same reason info is: the colour is asked for
-- often.
local fallback = {}

-- The cast bar's fill colour. Two of them: the ordinary one and the one for
-- what cannot be interrupted. The tables are single ones and rewritten in
-- place — for the same reason.
local castColor = { r = 1, g = 1, b = 1 }
local castLocked = { r = 0.6, g = 0.6, b = 0.6 }

--- Rewrite a colour table from a name in the core's palette.
-- There is no palette at all (a core without a skin) — then what is already in
-- the table stays: the default colour rather than a black taken at random.
-- @param skin table|nil
-- @param out table
-- @param name string the colour's name in the palette
-- @return table the same table
local function paletteColor(skin, out, name)
    if type(skin) ~= "table" or type(skin.Color) ~= "function" then
        return out
    end

    local r, g, b = skin.Color(name)
    if r then out.r, out.g, out.b = r, g, b end
    return out
end

-- The parsed settings. Kept here rather than asked for on every event: a
-- read of the profile is a chain of tables, while events about health, auras
-- and casts arrive as often as there are creatures on screen.
--
-- The aura filter's plan (ns.Filter.Compile) is the main one of these: it
-- turns the string of the spell list into a map once per edit of a setting,
-- and the decision about one aura costs one lookup after that. Parsing the
-- string for every aura of every nameplate is precisely the way addons bring
-- the frame rate down in a raid.
local plan = ns.Filter.Compile(nil)
local castOn, threatOn, questOn, truncateOn = false, false, false, false
local plateWidth = ns.Geometry.BOUNDS.width.default
local plateScale = ns.Geometry.BOUNDS.scale.default
local castHeight, auraSize = nil, nil

-- The compiled rules for single units. The same device and for the same
-- reason as the filter's plan: the list of rules is parsed into two maps once
-- per edit of a setting, and the decision about one creature costs one lookup
-- after that. Walking the list for every nameplate on every repaint is thirty
-- passes over thirty rules per event, that is, precisely the cost whose
-- absence the engine is written for.
--
-- The default is an empty plan: a fresh install pays nothing for the rules,
-- and Rules.Any answers "no" before anything is done.
local rulePlan = ns.Rules.Compile(nil)

-- The positions of a nameplate's parts. The same device and for the same
-- reason as the two plans above: the setting is parsed into a finished plan
-- once per edit, and the placement receives it already parsed. Computing
-- "where the name stands" for every creature that appears would mean paying
-- for a feature the player uses once a month on every frame of a fight.
--
-- The default is a plan made of defaults alone, that is, exactly the look the
-- nameplate had before the positions existed: a fresh install changes nothing
-- on screen.
local arrangePlan = ns.Arrange.Compile(nil)

-- The name font's height. The shortening needs it, and it is asked of the
-- label itself, but not for every creature: the font is one for every
-- nameplate and changes only together with the settings. A nil means "ask at
-- the first opportunity".
local nameSize = nil

--- The current game time in seconds.
-- Outside the game the function does not exist, and that is not a failure:
-- without a client there are no frames either.
-- @return number
local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    return ok and tonumber(value) or 0
end

--- The game's nameplate API, if it exists on this client.
-- The names are asked of the core (the contract, Darken:GetFrameNames): a
-- second list of foreign names would diverge from the client at the very first
-- patch.
-- @return table|nil
local function NamePlateApi()
    -- The objects themselves rather than the names: the door returns them as
    -- its second answer (contract 18). A name in a group can be a path into a
    -- foreign table, and _G[path] is nil: the engine would silently have found
    -- nothing.
    local names, objects = Darken:GetFrameNames("nameplate")
    for i = 1, #names do
        local object = objects[i]
        if type(object) == "table"
            and type(object.GetNamePlateForUnit) == "function" then
            return object
        end
    end
    return nil
end

--- The game's nameplate for a unit.
-- @param unit string
-- @return table|nil
local function PlateForUnit(unit)
    local api = NamePlateApi()
    if not api then return nil end

    local ok, plate = pcall(api.GetNamePlateForUnit, unit)
    if not ok then return nil end
    return plate
end

--- The module's settings.
-- @return table|nil
local function Settings()
    return module and module:GetSettings() or nil
end

--- A unit's colour: threat, then the player's rule, then class, then
--- reaction.
--
-- The information is collected into a reused table, and a pure rule from
-- Colors.lua makes the decision. The precedence is declared there and only
-- there: two places deciding one bar's colour is the very two-owner defect the
-- project has paid for once already.
--
-- The only call of Plate.SetColor in the whole module stands in paint, and its
-- only source of colour is this function. A test guards both claims by walking
-- the sources.
--
-- @param unit string
-- @param rule table|nil the player's rule for this unit (ns.Rules.For)
-- @return number, number, number
local function colorOf(unit, rule)
    info.isPlayer, info.class, info.reaction = nil, nil, nil
    info.tapDenied = nil
    info.threatOn, info.threat = threatOn, nil
    info.rule = rule

    if threatOn and type(UnitThreatSituation) == "function" then
        local ok, value = pcall(UnitThreatSituation, "player", unit)
        if ok then info.threat = value end
    end

    if type(UnitIsPlayer) == "function" then
        local ok, isPlayer = pcall(UnitIsPlayer, unit)
        info.isPlayer = ok and isPlayer or false
    end

    if info.isPlayer and type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, unit)
        if ok then info.class = token end
    end

    if type(UnitReaction) == "function" then
        local ok, reaction = pcall(UnitReaction, unit, "player")
        if ok then info.reaction = reaction end
    end

    -- Whose kill this is. The core's layer is asked: on late clients the
    -- question is one, on early ones it is made of two, and this part has no
    -- reason to know about that.
    if type(Darken.IsTapDenied) == "function" then
        local ok, denied = pcall(Darken.IsTapDenied, Darken, unit)
        info.tapDenied = ok and denied or false
    end

    info.classColors    = _G.RAID_CLASS_COLORS or _G.CUSTOM_CLASS_COLORS
    info.reactionColors = _G.FACTION_BAR_COLORS
    info.fallback       = paletteColor(currentSkin(), fallback, "textDim")

    return ns.Colors.Bar(info)
end

--- Whether a quest is recorded against this unit.
--
-- Two paths in the game, and the one that exists on this client is chosen: in
-- new builds the question is put to the quest log, on classic ones there is
-- only the "important for a quest" flag. With neither of them there will be no
-- icon, and that is quieter than an error.
-- @param unit string
-- @return boolean
local function questOf(unit)
    if not questOn then return false end

    if type(C_QuestLog) == "table"
        and type(C_QuestLog.UnitIsRelatedToActiveQuest) == "function" then
        local ok, value = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok and value then return true end
    end

    if type(UnitIsQuestBoss) == "function" then
        local ok, value = pcall(UnitIsQuestBoss, unit)
        if ok and value then return true end
    end

    return false
end

--- Which of the player's rules this unit got.
--
-- A hot path, and the first question here is "are there any rules at all": on
-- a fresh install the answer is no, and after that not one action is
-- performed — neither folding the name's case nor reading a GUID.
--
-- The name arrives as an argument rather than being asked of the game a second
-- time: the repaint has already asked for it for the label.
--
-- The name key and the creature id are created only when the rules hold
-- something to compare against. A key is a new string, and an id is a read of
-- the GUID plus a parse of the string; there is no point paying for them for a
-- map that holds nothing.
--
-- @param unit string
-- @param name any the unit's name, already read by the display
-- @return table|nil the rule
local function ruleFor(unit, name)
    if not ns.Rules.Any(rulePlan) then return nil end

    local key
    if ns.Rules.NeedsKey(rulePlan) and type(name) == "string" then
        key = ns.Rules.Key(name)
    end

    local id
    if ns.Rules.NeedsId(rulePlan) and type(UnitGUID) == "function" then
        local ok, guid = pcall(UnitGUID, unit)
        if ok then id = ns.Rules.NpcId(guid) end
    end

    return ns.Rules.For(rulePlan, key, id)
end

--- Repaint everything that depends on the unit rather than on its health.
-- @param record table
local function paint(record)
    local unit, frame = record.unit, record.frame
    if not unit or not frame then return end

    local name
    if type(UnitName) == "function" then
        local ok, value = pcall(UnitName, unit)
        if ok then name = value end
    end

    local level
    if type(UnitLevel) == "function" then
        local ok, value = pcall(UnitLevel, unit)
        if ok then level = value end
    end

    -- The player's rule is read before the colour and before the size: it
    -- takes part in both, and two reads of one and the same thing would mean
    -- two different answers in one frame if the name managed to arrive between
    -- them.
    local rule = ruleFor(unit, name)

    ns.Plate.SetColor(frame, colorOf(unit, rule))

    -- The size. Written always rather than only when there is a rule: the
    -- frame is reused, and a creature with no rule that got the frame of a
    -- highlighted one has to receive the ordinary size without waiting for
    -- anything.
    ns.Plate.SetScale(frame, ns.Rules.Apply(rule, plateScale))

    -- The shortening of long names. The rule is pure and lives in Names.lua;
    -- here there are only the width and the font's height. Switched off, the
    -- name goes as it is.
    if truncateOn and type(name) == "string" then
        if nameSize == nil then
            nameSize = ns.Plate.NameHeight(frame)
                or ns.Geometry.Clamp("height", nil)
        end
        name = ns.Names.Fit(name, plateWidth, nameSize)
    end

    ns.Plate.SetLabels(frame, name, level)

    ns.Plate.ShowQuest(frame, questOf(unit), currentSkin())

    local isTarget = false
    if type(UnitIsUnit) == "function" then
        local ok, same = pcall(UnitIsUnit, unit, "target")
        isTarget = ok and same or false
    end
    ns.Plate.ShowTarget(frame, isTarget)
end

--- Update one unit's health.
-- The module's most frequent call. No tables, no settings, no strings.
-- @param unit string
local function health(unit)
    local record = ns.Engine.Held(state, unit)
    if not record then return end

    local current, maximum
    if type(UnitHealth) == "function" then
        local ok, value = pcall(UnitHealth, unit)
        if ok then current = value end
    end
    if type(UnitHealthMax) == "function" then
        local ok, value = pcall(UnitHealthMax, unit)
        if ok then maximum = value end
    end

    ns.Plate.SetHealth(record.frame, current, maximum)
end

--- Rebuild one unit's aura icons.
--
-- The only entrances are the UNIT_AURA event about a particular unit and the
-- attachment. No sweep of the screen and no clock: the time left is drawn by
-- the sweeping shade, which the engine runs.
--
-- Not one table is allocated here: the auras are not collected into a list but
-- laid out onto the icons at once. A key string is created only when the player
-- has typed a list of spells — in the other cases there is nothing to compare
-- against, and there is no point folding the name into a key.
--
-- @param unit string
local function auras(unit)
    local record = ns.Engine.Held(state, unit)
    if not record then return end

    local frame = record.frame
    local limit = ns.Filter.Limit(plan)
    if limit <= 0 then
        ns.Plate.HideAuras(frame, 1)
        return
    end

    local byIndex
    if type(C_UnitAuras) == "table"
        and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        byIndex = C_UnitAuras.GetAuraDataByIndex
    end

    local shown = 0
    for pass = 1, 2 do
        local harmful = (pass == 1)
        local filter = harmful and "HARMFUL" or "HELPFUL"

        local index = 1
        while shown < limit do
            local name, icon, count, duration, expires, source

            if byIndex then
                local ok, data = pcall(byIndex, unit, index, filter)
                if ok and type(data) == "table" then
                    name, icon = data.name, data.icon
                    count    = data.applications or data.charges
                    duration = data.duration
                    expires  = data.expirationTime
                    source   = data.sourceUnit
                end
            elseif type(UnitAura) == "function" then
                local ok, a, b, c, _, e, f, g = pcall(UnitAura, unit, index, filter)
                if ok then
                    name, icon, count = a, b, c
                    duration, expires, source = e, f, g
                end
            end

            if name == nil then break end

            local key
            if ns.Filter.NeedsKey(plan) then key = ns.Filter.Key(name) end

            if ns.Filter.Allows(plan, key, source == "player", harmful) then
                shown = shown + 1
                ns.Plate.SetAura(frame, shown, currentSkin(), icon, count,
                    duration, expires)
            end

            index = index + 1
        end
    end

    ns.Plate.HideAuras(frame, shown + 1)
end

--- Show or remove one unit's cast bar.
--
-- Called only from the cast's own events. After that the engine runs the bar's
-- motion: see the file's header and Cast.lua's header.
-- @param unit string
local function casting(unit)
    local record = ns.Engine.Held(state, unit)
    if not record then return end

    local frame = record.frame
    if not castOn then
        ns.Plate.StopCast(frame)
        return
    end

    -- The order of the values differs between the cast and the channel
    -- calls, but the name, the start and the end stand in the same places in
    -- both.
    local name, startMs, endMs, locked, channel

    if type(UnitCastingInfo) == "function" then
        local ok, a, _, _, d, e, _, _, h = pcall(UnitCastingInfo, unit)
        if ok and a then
            name, startMs, endMs, locked = a, d, e, h
        end
    end

    if name == nil and type(UnitChannelInfo) == "function" then
        local ok, a, _, _, d, e, _, g = pcall(UnitChannelInfo, unit)
        if ok and a then
            name, startMs, endMs, locked, channel = a, d, e, g, true
        end
    end

    if name == nil then
        ns.Plate.StopCast(frame)
        return
    end

    local from, to, seconds = ns.Cast.Progress(startMs, endMs, Now(), channel)
    if from == nil then
        ns.Plate.StopCast(frame)
        return
    end

    local skin = currentSkin()
    local color = locked
        and paletteColor(skin, castLocked, "textDim")
        or paletteColor(skin, castColor, "lilac")
    ns.Plate.StartCast(frame, from, to, seconds, name,
        color.r, color.g, color.b)
end

--- Detach a unit and put the native nameplate back.
-- @param unit string
local function detach(unit)
    local record = ns.Engine.Detach(state, unit)
    if not record then return end

    if record.plate ~= nil and record.alpha ~= nil then
        ns.Plate.Native(record.plate, record.alpha)
    end
    ns.Plate.Release(pool, record.frame)
end

--- Detach everything. A change of zone, the module being switched off, the
--- module being disabled by the core.
local function detachAll()
    local records = ns.Engine.DetachAll(state)
    for i = 1, #records do
        local record = records[i]
        if record.plate ~= nil and record.alpha ~= nil then
            ns.Plate.Native(record.plate, record.alpha)
        end
        ns.Plate.Release(pool, record.frame)
    end
end

--- Dress a frame by the current settings: the measurements, the positions,
--- the texture, the fonts.
--
-- One function for both places where this is done — the attachment of a new
-- nameplate and an edit of the settings. These used to be two identical
-- sequences of five calls at opposite ends of the file, and they would have
-- diverged silently: a feature added to one simply would not have appeared on
-- half the nameplates. The positions made the difference between them visible
-- — and, at the same time, impossible.
--
-- Everything measured arrives ready rather than being asked for here: the skin
-- and the media are asked for once per repaint rather than once per creature.
--
-- @param frame table|nil our frame
-- @param plate table|nil the game's nameplate
-- @param skin table|nil the core's skin
-- @param media table|nil the core's media
-- @param path string|nil the bar's texture
-- @param width number
-- @param height number
-- @param scale number
-- @param gap number
local function dress(frame, plate, skin, media, path, width, height, scale,
        gap)
    ns.Plate.Layout(frame, plate, width, height, scale, gap,
        ns.Plate.Edge(skin), arrangePlan)
    ns.Plate.SetTexture(frame, path)
    ns.Plate.LayoutExtras(frame, skin, width, height, gap, castHeight,
        auraSize, ns.Filter.Limit(plan), arrangePlan, questOn)
    ns.Plate.ApplyFont(frame, media)
    ns.Plate.ApplyExtraFonts(frame, media)
end

--- Attach to the nameplate the game created for a unit.
-- The only entrance is the NAME_PLATE_UNIT_ADDED event — the moment when the
-- nameplate exists, its unit is known and the player has not seen it yet.
-- @param unit string
local function attach(unit)
    if not drawing then return end
    if type(unit) ~= "string" or unit == "" then return end

    local plate = PlateForUnit(unit)
    if plate == nil then return end

    local skin = currentSkin()
    local media = currentMedia()
    local frame = ns.Plate.Acquire(pool, skin)
    if frame == nil then return end

    -- An attachment begins with an eviction: the same game frame may have
    -- been recorded for another unit, and the "went away" event for it may not
    -- have arrived at all.
    local record, stale = ns.Engine.Attach(
        state, unit, plate, frame, frame.record)
    if stale ~= nil then
        if stale.plate ~= nil and stale.alpha ~= nil then
            ns.Plate.Native(stale.plate, stale.alpha)
        end
        ns.Plate.Release(pool, stale.frame)
    end
    if record == nil then
        ns.Plate.Release(pool, frame)
        return
    end

    record.alpha = ns.Plate.Native(plate, nil)

    local settings = Settings()
    local width, height, scale = ns.Geometry.Plate(settings)
    local gap = gapOf(skin)
    local path = media and media.BarTexture(
        settings and settings.texture) or nil
    dress(frame, plate, skin, media, path, width, height, scale, gap)
    ns.Plate.Ready(frame)

    -- The only place where the engine takes a nameplate over. A zero here
    -- while the module is working is the proof that the engine did nothing,
    -- however many names the compatibility layer found.
    if counters then counters.plates_engine = counters.plates_engine + 1 end

    paint(record)
    health(unit)
    auras(unit)
    casting(unit)

    if type(frame.Show) == "function" then frame:Show() end
end

--- Rebuild the target's highlight on every attached nameplate.
-- A walk — but not a walk of the screen on a timer: it happens on a change of
-- target, that is, a handful of times per fight, and it goes over our records
-- rather than over the game's frames.
local function retarget()
    for _, record in pairs(state.byUnit) do
        local isTarget = false
        if type(UnitIsUnit) == "function" then
            local ok, same = pcall(UnitIsUnit, record.unit, "target")
            isTarget = ok and same or false
        end
        ns.Plate.ShowTarget(record.frame, isTarget)
    end
end

--- Rebuild the quest icon on every attached nameplate.
-- A walk over our records rather than over the screen, and only on the quest
-- log's event.
local function request()
    if not questOn then return end
    for _, record in pairs(state.byUnit) do
        ns.Plate.ShowQuest(record.frame, questOf(record.unit), currentSkin())
    end
end

--- Repaint a unit, if it is recorded for us.
-- @param unit string|nil
local function repaint(unit)
    if type(unit) ~= "string" then return end
    local record = ns.Engine.Held(state, unit)
    if record then paint(record) end
end

-- The events and their handlers. A list rather than ten calls in a row: the
-- subscription goes through the core (the contract, handle:RegisterEvent), and
-- all that differs between the rows is the event's name and one function.
--
-- The names are candidates: UNIT_HEALTH_FREQUENT does not exist on every
-- supported client, and an unfamiliar name the engine simply will not accept,
-- after which the subscription will never fire.
local EVENTS = {
    { "NAME_PLATE_UNIT_ADDED",   function(_, unit) attach(unit) end },
    { "NAME_PLATE_UNIT_REMOVED", function(_, unit)
        if type(unit) == "string" then detach(unit) end
    end },
    { "UNIT_HEALTH",             function(_, unit) health(unit) end },
    { "UNIT_HEALTH_FREQUENT",    function(_, unit) health(unit) end },
    { "UNIT_MAXHEALTH",          function(_, unit) health(unit) end },
    { "UNIT_NAME_UPDATE",        function(_, unit) repaint(unit) end },
    { "UNIT_LEVEL",              function(_, unit) repaint(unit) end },
    { "UNIT_FACTION",            function(_, unit) repaint(unit) end },
    { "UNIT_THREAT_LIST_UPDATE",      function(_, unit) repaint(unit) end },
    { "UNIT_THREAT_SITUATION_UPDATE", function(_, unit) repaint(unit) end },
    { "UNIT_AURA",               function(_, unit) auras(unit) end },
    -- The cast. Every event arrives about a particular unit, and after that
    -- the engine runs the bar: it has no clock of its own.
    { "UNIT_SPELLCAST_START",          function(_, unit) casting(unit) end },
    { "UNIT_SPELLCAST_STOP",           function(_, unit) casting(unit) end },
    { "UNIT_SPELLCAST_FAILED",         function(_, unit) casting(unit) end },
    { "UNIT_SPELLCAST_INTERRUPTED",    function(_, unit) casting(unit) end },
    { "UNIT_SPELLCAST_SUCCEEDED",      function(_, unit) casting(unit) end },
    { "UNIT_SPELLCAST_DELAYED",        function(_, unit) casting(unit) end },
    { "UNIT_SPELLCAST_CHANNEL_START",  function(_, unit) casting(unit) end },
    { "UNIT_SPELLCAST_CHANNEL_UPDATE", function(_, unit) casting(unit) end },
    { "UNIT_SPELLCAST_CHANNEL_STOP",   function(_, unit) casting(unit) end },
    { "PLAYER_TARGET_CHANGED",   function() retarget() end },
    -- The quest icon. The walk goes over our records, and it happens on a
    -- change of the quest log, that is, a few times per creature killed rather
    -- than per frame. Thirty records at one question to the game each is a
    -- cost visible in a measurement rather than in the game.
    { "QUEST_LOG_UPDATE",        function() request() end },
    { "UNIT_QUEST_LOG_CHANGED",  function(_, unit) repaint(unit) end },
    -- A change of zone takes every nameplate away at once, and the "went
    -- away" event for each of them may not arrive. We detach them ourselves:
    -- otherwise the ledger would hold frames that are no longer on screen.
    { "PLAYER_ENTERING_WORLD",   function() detachAll() end },
}

--- Start drawing.
-- Here and only here does the core stand its nameplate skinning aside, and
-- that is done at exactly the moment we really start drawing: a module that is
-- installed but switched off takes nothing away from the player.
local function start(handle)
    if drawing then return end
    drawing = true

    -- The tally's key is claimed exactly here: from this moment on a zero in
    -- it means the engine refused rather than that the engine is switched
    -- off.
    if counters then counters.plates_engine = counters.plates_engine or 0 end

    if not stoodDown then
        stoodDown = true
        handle:Replaces("nameplates")
    end
end

--- Stop drawing.
--
-- And give the core its nameplate skinning back. A line of apology into the
-- chat frame used to stand here — "the nameplates returned to the game's
-- native look, and our skinning is off until a reload": an apology instead of
-- a return. The argument is the same as for the bags: a player who switched
-- the engine off expects what was there before they switched it on, and before
-- that the native nameplates were dressed by the core's skinning.
--
-- The return goes after detachAll rather than before: the core skins the
-- nameplates that are on screen right now, and skinning them before we have
-- detached ours would mean two owners on one frame for one more moment.
--
-- The core says the one line about the return: it alone knows whether the
-- subsystem really came back into service.
local function stop(handle)
    if not drawing then return end
    drawing = false
    detachAll()

    if stoodDown then
        stoodDown = false
        handle:Releases("nameplates")
    end
end

--- The list of textures for the setting's dropdown.
-- Assembled at the moment the list is opened rather than when the table is
-- built: the registry of textures is shared for the session, and another addon
-- may have added its own to it after we loaded.
-- @return table name -> label
local function textureValues()
    local out = { [NATIVE] = ns.Localize("Game's Own Texture") }
    local media = currentMedia()
    if not media then return out end

    local names = media.BarTextures()
    for i = 1, #names do out[names[i]] = names[i] end
    return out
end

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

--- The get/set handlers for a boolean setting.
-- Separate from the numeric ones: the value is brought to true or false here
-- rather than somewhere in the display. Anything at all finds its way into
-- SavedVariables over the years, and "anything at all" in the role of a switch
-- means a switch that does not switch.
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

local getWidth,  setWidth  = handlers("width")
local getHeight, setHeight = handlers("height")
local getScale,  setScale  = handlers("scale")
local getTexture, setTexture = handlers("texture")

local getCastHeight, setCastHeight = handlers("castHeight")
local getAuraSize,   setAuraSize   = handlers("auraSize")
local getAuraLimit,  setAuraLimit  = handlers("auraLimit")
local getAuraMode,   setAuraMode   = handlers("auraMode")
local getAuraList,   setAuraList   = handlers("auraList")

local getTruncate,  setTruncate  = toggles("truncate")
local getThreat,    setThreat    = toggles("threat")
local getQuest,     setQuest     = toggles("quest")
local getCastBar,   setCastBar   = toggles("castbar")
local getAuras,     setAuras     = toggles("auras")
local getOnlyMine,  setOnlyMine  = toggles("auraOnlyMine")
local getHelpful,   setHelpful   = toggles("auraHelpful")
local getHarmful,   setHarmful   = toggles("auraHarmful")

local BOUNDS = ns.Geometry.BOUNDS
local LIMIT  = ns.Filter.LIMIT
local SIZE   = ns.Filter.SIZE
local CAST   = ns.Cast.HEIGHT
local RSCALE = ns.Rules.SCALE

-- === Rules for a single unit: the settings section =========================
--
-- The construction is taken from the bag rules rather than invented afresh: a
-- choice list, the fields for the chosen rule, and the buttons. The argument is
-- the same as everywhere in this addon: two forms of one and the same thing
-- diverge silently, and a player who learnt to create a rule in the bags must
-- not learn it a second time.
--
-- There is no nameplate editor here, and that is not the same thing: an editor
-- is about dragging elements around the nameplate itself rather than about
-- which creature gets which colour.

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

--- A readable refusal line for a refusal code.
-- The place that decides produces the code, the place that shows it chooses
-- the phrase: the translation lives here.
-- @param why string|nil
-- @return string
local function ruleProblem(why)
    if why == "noname" then
        return ns.Localize("a rule needs a name")
    elseif why == "notext" then
        return ns.Localize("a rule needs at least one creature name or id")
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
        return ns.Localize("No rules yet, so every nameplate looks the same. "
            .. "A rule names creatures - by name, or by creature id for a "
            .. "name that is different in every language - and gives them "
            .. "their own color and their own size. Rules are tried from the "
            .. "top down, and the first one that names a creature wins it.")
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

--- The labels of the spell list's modes.
-- A function rather than a table: it is assembled at file level, that is,
-- before the core hands over the descriptor, and without it there is nobody to
-- translate them.
-- @return table
local function auraModeValues()
    return {
        off   = ns.Localize("Show Every Aura That Passes"),
        allow = ns.Localize("Show Only the Listed Spells"),
        deny  = ns.Localize("Hide the Listed Spells"),
    }
end

-- === The nameplate editor: the settings section ============================
--
-- What it does: it puts every part of a nameplate — the name, the level, the
-- cast bar, the aura icons, the quest icon and the nameplate itself — on its
-- side and adjusts it by two numbers. ns.Arrange decides the positions,
-- ns.Plate.Place writes them, and there is no second place in the module that
-- moves the parts.
--
-- What it does not do, and why:
--
-- **It does not drag the parts around a sample nameplate.** A sample is a
-- second display beside the real one, with a pool of its own, measurements of
-- its own and an update of its own; and above all with a right of its own to
-- diverge from the real one silently. There are dozens of real nameplates on
-- screen, an edit of a setting reaches all of them at once and in combat, and
-- it is more correct to look at the result where it will really be.
--
-- **It does not go to the core's mover** (contract 14), even though the door
-- for that is open and the modules use it. A mover puts a frame at a point on
-- the screen and remembers that point in the profile. A nameplate has no point
-- on the screen: there are dozens of them, they appear and leave along with
-- the creatures, and a holder on one of them would mean positions recorded
-- from whichever creature happened to be nearby. A part's side exists only
-- relative to the health bar — that is a different quantity, and the mover
-- knows nothing about it.
--
-- **It does not show the positions surface when there is nothing to show it
-- on.** The nameplate engine has never once been run in a live client, and the
-- counter of what was attached (contract 17, handle:Counters) exists precisely
-- so that this is visible as a number rather than as a guess. Zero attached
-- means there is nothing to arrange, and the editor says so out loud instead
-- of offering to arrange the parts of a nameplate that is not on screen.

--- How many nameplates THIS engine took over during this session.
--
-- A key of its own (plates_engine) rather than the shared plates: the latter
-- is also incremented by the core's nameplate subsystem, which on a fresh
-- install works precisely because the engine is off. Somebody else's number
-- answered "there is something to arrange" in exactly the place where there is
-- nothing, and the editor opened over a switched-off engine.
--
-- A nil means "the core is older than the counter" rather than zero: those are
-- different answers, and taking the first for the second would mean hiding the
-- editor from somebody for whom everything works. The tally table exists but
-- the key is not in it — that is no longer ignorance but "the engine was not
-- run during this session", that is, zero.
-- @return number|nil
local function platesTaken()
    if type(counters) ~= "table" then return nil end
    return tonumber(counters.plates_engine) or 0
end

--- Whether there is anything to arrange.
-- @return boolean
local function arrangeable()
    local taken = platesTaken()
    if taken == nil then return true end
    return taken > 0
end

--- The part chosen for editing.
-- @return string
local function chosenPart()
    local want = module and module.partChoice
    if ns.Arrange.PLACES[want] ~= nil then return want end
    return ns.Arrange.PARTS[1]
end

--- The parts' labels.
-- A function rather than a table: it is assembled at file level, that is,
-- before the core hands over the descriptor, and without it there is nobody to
-- translate them.
-- @return table
local function partValues()
    return {
        name  = ns.Localize("Name"),
        level = ns.Localize("Level"),
        cast  = ns.Localize("Cast Bar"),
        auras = ns.Localize("Aura Icons"),
        quest = ns.Localize("Quest Mark"),
        plate = ns.Localize("The Whole Nameplate"),
    }
end

--- The places' labels.
-- The words are the same for every part: "above" for the name and "above" for
-- the aura icons are one and the same side, and two different words for it
-- would mean the player learns the positions afresh on every part.
-- @return table
local function placeWords()
    return {
        top    = ns.Localize("Above"),
        bottom = ns.Localize("Below"),
        left   = ns.Localize("Left"),
        right  = ns.Localize("Right"),
        over   = ns.Localize("On the Health Bar"),
        center = ns.Localize("Where the Game Puts It"),
    }
end

--- The places the chosen part can have.
-- @return table
local function placeValues()
    local words = placeWords()
    local out = {}
    local list = ns.Arrange.PLACES[chosenPart()] or {}
    for i = 1, #list do out[list[i]] = words[list[i]] or list[i] end
    return out
end

--- The get/set handlers for the chosen part's offset.
-- @param axis string
-- @return function, function
local function offsets(axis)
    return function()
        local entry = arrangePlan[chosenPart()]
        return entry and entry[axis] or ns.Arrange.OFFSET.default
    end,
    function(_, value)
        local settings = Settings()
        if not settings or not module then return end
        if ns.Arrange.SetOffset(settings, chosenPart(), axis, value) then
            module:Apply()
        end
    end
end

local getPartX, setPartX = offsets("x")
local getPartY, setPartY = offsets("y")

local OFFSET = ns.Arrange.OFFSET

local options = {
    type = "group",
    -- The labels are functions rather than strings: the table is assembled
    -- at file level, that is, before the core hands over the descriptor, and
    -- without it there is nobody to translate them.
    name = function() return ns.Localize("Darken Nameplates") end,
    args = {
        about = {
            type = "description",
            order = 1,
            width = "full",
            name = function() return ns.Localize("Draws Darken's own "
                .. "nameplates instead of dressing the "
                .. "game's: health bar, name, level, a mark on your target and - "
                .. "each switched on separately below - a cast bar, aura icons, "
                .. "threat color and a quest mark. Off by default - a fresh "
                .. "install changes nothing. Switching it on takes nameplates "
                .. "over from Darken's own plate styling, which stands down "
                .. "while this is on and comes back when it is switched "
                .. "off.") end,
        },
        enabled = {
            type = "toggle",
            order = 2,
            width = "full",
            name = function() return ns.Localize("Draw Our Own Nameplates") end,
            desc = function() return ns.Localize("Off leaves the game's "
                .. "nameplates exactly as they are, which is what a fresh "
                .. "install does.") end,
            get = function()
                local settings = Settings()
                return settings and settings.enabled or false
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.enabled = value and true or false
                module:Apply()
            end,
        },
        texture = {
            type = "select",
            order = 3,
            width = "full",
            name = function() return ns.Localize("Health Bar Texture") end,
            desc = function() return ns.Localize("The first entry is the "
                .. "game's own bar texture. The addon's own textures are a "
                .. "gradient from white to a color, and the bar color "
                .. "multiplies them.") end,
            values = textureValues,
            get = getTexture,
            set = setTexture,
        },
        width = {
            type = "range",
            order = 4,
            width = "full",
            name = function() return ns.Localize("Nameplate Width") end,
            min = BOUNDS.width.min, max = BOUNDS.width.max, step = 1,
            get = getWidth,
            set = setWidth,
        },
        height = {
            type = "range",
            order = 5,
            width = "full",
            name = function() return ns.Localize("Health Bar Height") end,
            min = BOUNDS.height.min, max = BOUNDS.height.max, step = 1,
            get = getHeight,
            set = setHeight,
        },
        scale = {
            type = "range",
            order = 6,
            width = "full",
            name = function() return ns.Localize("Nameplate Scale") end,
            desc = function() return ns.Localize("Scales the whole nameplate, "
                .. "text included. Width and height above are measured before "
                .. "this.") end,
            min = BOUNDS.scale.min, max = BOUNDS.scale.max, step = 0.05,
            get = getScale,
            set = setScale,
        },
        truncate = {
            type = "toggle",
            order = 7,
            width = "full",
            name = function() return ns.Localize("Shorten Long Names") end,
            desc = function() return ns.Localize("Cuts a name that does not "
                .. "fit the nameplate width and marks the cut with three "
                .. "dots. Off leaves long names running past the bar.") end,
            get = getTruncate,
            set = setTruncate,
        },
        threat = {
            type = "toggle",
            order = 8,
            width = "full",
            name = function() return ns.Localize("Color by Threat") end,
            desc = function() return ns.Localize("Colors the health bar of "
                .. "unfriendly creatures by how close they are to attacking "
                .. "you. Threat outranks class and reaction color, and only "
                .. "while it has something to say: a creature nobody is "
                .. "fighting keeps its own color.") end,
            get = getThreat,
            set = setThreat,
        },
        quest = {
            type = "toggle",
            order = 9,
            width = "full",
            name = function() return ns.Localize("Mark Quest Targets") end,
            desc = function() return ns.Localize("Puts a small mark beside "
                .. "the nameplate of a creature one of your quests wants.") end,
            get = getQuest,
            set = setQuest,
        },
        castbar = {
            type = "toggle",
            order = 10,
            width = "full",
            name = function() return ns.Localize("Cast Bar on the Nameplate") end,
            desc = function() return ns.Localize("Shows what the creature is "
                .. "casting under its health bar. The bar is moved by the "
                .. "engine itself, so it costs nothing per frame. This is "
                .. "the nameplate's own cast bar - your own cast bar belongs "
                .. "to Darken and to the cast bars module.") end,
            get = getCastBar,
            set = setCastBar,
        },
        castHeight = {
            type = "range",
            order = 11,
            width = "full",
            name = function() return ns.Localize("Cast Bar Height") end,
            min = CAST.min, max = CAST.max, step = 1,
            get = getCastHeight,
            set = setCastHeight,
        },
        auras = {
            type = "toggle",
            order = 12,
            width = "full",
            name = function() return ns.Localize("Aura Icons") end,
            desc = function() return ns.Localize("Shows aura icons above the "
                .. "nameplate. Which auras pass is set below. Time left is "
                .. "drawn by the engine's own sweep, so the icons cost "
                .. "nothing per frame.") end,
            get = getAuras,
            set = setAuras,
        },
        auraHarmful = {
            type = "toggle",
            order = 13,
            name = function() return ns.Localize("Show Harmful Auras") end,
            get = getHarmful,
            set = setHarmful,
        },
        auraHelpful = {
            type = "toggle",
            order = 14,
            name = function() return ns.Localize("Show Helpful Auras") end,
            get = getHelpful,
            set = setHelpful,
        },
        auraOnlyMine = {
            type = "toggle",
            order = 15,
            width = "full",
            name = function() return ns.Localize("Only Auras You Applied") end,
            desc = function() return ns.Localize("A creature in a raid "
                .. "carries everybody's auras. Off shows all of them, "
                .. "which in a busy fight is a wall of icons. On by "
                .. "default.") end,
            get = getOnlyMine,
            set = setOnlyMine,
        },
        auraLimit = {
            type = "range",
            order = 16,
            width = "full",
            name = function() return ns.Localize("How Many Icons at Most") end,
            min = LIMIT.min, max = LIMIT.max, step = 1,
            get = getAuraLimit,
            set = setAuraLimit,
        },
        auraSize = {
            type = "range",
            order = 17,
            width = "full",
            name = function() return ns.Localize("Aura Icon Size") end,
            min = SIZE.min, max = SIZE.max, step = 1,
            get = getAuraSize,
            set = setAuraSize,
        },
        auraMode = {
            type = "select",
            order = 18,
            width = "full",
            name = function() return ns.Localize("What to Do with the List") end,
            desc = function() return ns.Localize("An empty list means the "
                .. "list is not used at all, whichever entry is picked "
                .. "here.") end,
            values = auraModeValues,
            get = getAuraMode,
            set = setAuraMode,
        },
        auraList = {
            type = "input",
            order = 19,
            width = "full",
            multiline = 4,
            name = function() return ns.Localize("Spell List") end,
            desc = function() return ns.Localize("Spell names, separated by "
                .. "commas or written one per line. A name written in the "
                .. "list is shown even when \"only auras you applied\" is "
                .. "on - naming a spell is already an answer.") end,
            get = getAuraList,
            set = setAuraList,
        },

        -- === Rules for a single unit ===
        rulesAbout = {
            type = "description",
            order = 20,
            width = "full",
            name = function() return ns.Localize("A rule gives named "
                .. "creatures a nameplate of their own. Its color outranks "
                .. "class and reaction color, because you named the creature "
                .. "by hand and those are guesses - but threat color still "
                .. "outranks the rule, so a creature turning on you is never "
                .. "hidden by it. With no rules nothing changes.") end,
        },
        rulesList = {
            type = "description",
            order = 21,
            width = "full",
            name = rulesText,
        },
        rulePick = {
            type = "select",
            order = 22,
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
                        -- the precedence: it settles two rules over one
                        -- creature, and a list in which it cannot be seen
                        -- would hide the only thing the dispute is settled
                        -- by.
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
            order = 23,
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
            order = 24,
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
            order = 25,
            width = "full",
            multiline = 4,
            name = function() return ns.Localize("Creatures") end,
            desc = function() return ns.Localize("Creature names, separated "
                .. "by commas or written one per line, and capitals do not "
                .. "matter. An entry of digits only is read as a creature id "
                .. "instead: a name belongs to the language of your client "
                .. "and is not unique, an id is neither.") end,
            get = function()
                local chosen = chosenRule()
                if chosen ~= nil then
                    local _, rule = ns.Rules.Find(ruleList(), chosen)
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
        ruleColor = {
            type = "color",
            order = 26,
            name = function() return ns.Localize("Health Bar Color") end,
            desc = function() return ns.Localize("The color this rule paints "
                .. "the health bar and the name with. Threat color still "
                .. "outranks it.") end,
            disabled = function() return chosenRule() == nil end,
            get = function()
                local chosen = chosenRule()
                if chosen == nil then return 1, 1, 1 end

                local _, rule = ns.Rules.Find(ruleList(), chosen)
                local color = rule and rule.color
                if type(color) ~= "table" then return 1, 1, 1 end
                return tonumber(color[1]) or 1, tonumber(color[2]) or 1,
                    tonumber(color[3]) or 1
            end,
            set = function(_, r, g, b)
                local chosen = chosenRule()
                if chosen == nil or not module then return end
                if ns.Rules.SetColor(ruleList(), chosen, r, g, b) then
                    module:Apply()
                end
            end,
        },
        ruleRecolor = {
            type = "toggle",
            order = 27,
            name = function() return ns.Localize("Use That Color") end,
            desc = function() return ns.Localize("Off leaves the color alone "
                .. "and the rule changes the size only.") end,
            disabled = function() return chosenRule() == nil end,
            get = function()
                local chosen = chosenRule()
                if chosen == nil then return false end
                local _, rule = ns.Rules.Find(ruleList(), chosen)
                return type(rule) == "table" and type(rule.color) == "table"
            end,
            set = function(_, value)
                local chosen = chosenRule()
                if chosen == nil or not module then return end

                if value then
                    ns.Rules.SetColor(ruleList(), chosen, 1, 0.5, 0.2)
                else
                    ns.Rules.SetColor(ruleList(), chosen, nil, nil, nil)
                end
                module:Apply()
            end,
        },
        ruleScale = {
            type = "range",
            order = 28,
            width = "full",
            name = function() return ns.Localize("Size of Those Nameplates") end,
            desc = function() return ns.Localize("Multiplies the nameplate "
                .. "scale set above, so one means no change at all.") end,
            disabled = function() return chosenRule() == nil end,
            min = RSCALE.min, max = RSCALE.max, step = 0.05,
            get = function()
                local chosen = chosenRule()
                if chosen == nil then return RSCALE.default end
                local _, rule = ns.Rules.Find(ruleList(), chosen)
                return ns.Rules.Scale(rule and rule.scale)
            end,
            set = function(_, value)
                local chosen = chosenRule()
                if chosen == nil or not module then return end
                if ns.Rules.SetScale(ruleList(), chosen, value) then
                    module:Apply()
                end
            end,
        },
        ruleAdd = {
            type = "execute",
            order = 29,
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
            order = 30,
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
            order = 31,
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
            order = 32,
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

        -- === The positions of a nameplate's parts ===
        arrangeAbout = {
            type = "description",
            order = 40,
            width = "full",
            name = function()
                if not arrangeable() then
                    return ns.Localize("The engine has not taken a single "
                        .. "nameplate over this session, so there is nothing "
                        .. "here to arrange: a part cannot be placed on a "
                        .. "nameplate that is not on screen. Switch the "
                        .. "engine on above, go where there are creatures, "
                        .. "and these controls are here the next time you "
                        .. "open this window.")
                end
                return ns.Localize("Where each part of the nameplate sits. "
                    .. "Pick a part, pick the side it sits on, and nudge it "
                    .. "with the two offsets. Sides are counted from the "
                    .. "health bar, because a nameplate has no place on "
                    .. "screen of its own - the game moves it, and dozens of "
                    .. "them come and go. An offset is measured in the "
                    .. "nameplate's own units, so a rule that makes a "
                    .. "nameplate bigger makes its arrangement bigger with "
                    .. "it instead of pulling it apart. A fresh install "
                    .. "arranges everything exactly as it always was.")
            end,
        },
        partPick = {
            type = "select",
            order = 41,
            width = "full",
            hidden = function() return not arrangeable() end,
            name = function() return ns.Localize("Part to Place") end,
            values = partValues,
            get = chosenPart,
            set = function(_, value)
                if module and ns.Arrange.PLACES[value] ~= nil then
                    module.partChoice = value
                end
            end,
        },
        partPlace = {
            type = "select",
            order = 42,
            width = "full",
            -- The nameplate itself has no side: it does not stand beside
            -- itself, and only the offsets move it. A list of one value would
            -- ask for a choice that does not exist.
            hidden = function()
                if not arrangeable() then return true end
                return #(ns.Arrange.PLACES[chosenPart()] or {}) < 2
            end,
            name = function() return ns.Localize("Side It Sits On") end,
            values = placeValues,
            get = function()
                local entry = arrangePlan[chosenPart()]
                return entry and entry.place
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings or not module then return end
                if ns.Arrange.SetPlace(settings, chosenPart(), value) then
                    module:Apply()
                end
            end,
        },
        partX = {
            type = "range",
            order = 43,
            width = "full",
            hidden = function() return not arrangeable() end,
            name = function() return ns.Localize("Nudge Sideways") end,
            min = OFFSET.min, max = OFFSET.max, step = 1,
            get = getPartX,
            set = setPartX,
        },
        partY = {
            type = "range",
            order = 44,
            width = "full",
            hidden = function() return not arrangeable() end,
            name = function() return ns.Localize("Nudge Up and Down") end,
            min = OFFSET.min, max = OFFSET.max, step = 1,
            get = getPartY,
            set = setPartY,
        },
        partReset = {
            type = "execute",
            order = 45,
            hidden = function() return not arrangeable() end,
            -- Inert when there is nothing to reset: a button that does
            -- nothing and does not say so reads as broken.
            disabled = function()
                return not ns.Arrange.Moved(arrangePlan, chosenPart())
            end,
            name = function() return ns.Localize("Put This Part Back") end,
            func = function()
                local settings = Settings()
                if not settings or not module then return end
                if ns.Arrange.Reset(settings, chosenPart()) then
                    module:Apply()
                end
            end,
        },
        -- The way back is always visible, including when there is nothing
        -- to arrange: a player whose positions were left over from a previous
        -- session has to be able to reset them without waiting for a
        -- nameplate.
        arrangeReset = {
            type = "execute",
            order = 46,
            name = function()
                return ns.Localize("Put Every Part Back")
            end,
            desc = function() return ns.Localize("Arranges every part the "
                .. "way a fresh install does.") end,
            func = function()
                local settings = Settings()
                if not settings or not module then return end
                if ns.Arrange.ResetAll(settings) then
                    module:Print(ns.Localize("nameplate arrangement is back "
                        .. "to what it was"))
                    module:Apply()
                end
            end,
        },
    },
}

local handle, reason = Darken:RegisterModule({
    name = "umbraplates",
    api  = API,

    -- The defaults: switched off. A fresh install changes nothing on screen,
    -- and the game's native behaviour stays not only the initial one but also
    -- a choice. Every feature of the second increment starts switched off as
    -- well, and every default stays reachable: a switch comes back, a number
    -- lies within its slider's bounds, a list's mode is among its values.
    defaults = {
        enabled = false,
        width   = BOUNDS.width.default,
        height  = BOUNDS.height.default,
        scale   = BOUNDS.scale.default,
        texture = NATIVE,

        truncate = false,
        threat   = false,
        quest    = false,

        castbar    = false,
        castHeight = CAST.default,

        auras        = false,
        auraSize     = SIZE.default,
        auraLimit    = LIMIT.default,
        auraOnlyMine = true,
        auraHelpful  = false,
        auraHarmful  = true,
        auraMode     = "off",
        auraList     = "",

        -- There is not one rule. An empty list is not "the rules are
        -- switched off" but "the player has not named a single creature yet":
        -- the rules deliberately have no switch of their own, because with an
        -- empty list a switch would switch nothing off, and with a non-empty
        -- one it would be a second way of saying the same thing.
        rules = {},

        -- The parts' positions: empty. An empty record is not "the parts
        -- have not been placed anywhere" but "the player has not moved a
        -- single one yet": every part stands where it stood before the editor
        -- existed, and that is tested separately, by comparison against the
        -- very numbers that stood in the display.
        arrange = {},
    },

    options = options,

    OnEnable = function(self)
        -- The descriptor is taken from self, and that is still correct but
        -- no longer required: since contract version 16 RegisterModule
        -- returns the descriptor before the core calls the handlers, and the
        -- module variable has been assigned by that moment. The line is left
        -- as it is — it works on any version of the contract, and there is no
        -- reason to touch ten modules for its sake.
        --
        -- The translation wrapper and the reading of the settings receive the
        -- descriptor here rather than further down the file.
        module = module or self

        -- A foreign engine. The addon's name is asked of whichever API
        -- exists on this client: in new builds the function moved into
        -- C_AddOns.
        local isLoaded = IsAddOnLoaded
        if type(isLoaded) ~= "function" and type(C_AddOns) == "table" then
            isLoaded = C_AddOns.IsAddOnLoaded
        end

        local owner = ns.Engine.ForeignOwner(isLoaded, _G)
        local settings = self:GetSettings()
        local verdict = ns.Engine.Decide(settings and settings.enabled, owner)

        if verdict == "foreign" then
            -- We stand aside, not the foreign addon: it does not know about
            -- us and cannot yield. The core's skinning stands aside by itself
            -- in the process — it checks the same list.
            self:Print(string.format(ns.Localize("\"%s\" already draws "
                .. "nameplates, so Darken's nameplate engine stays out of "
                .. "the way: two engines on one frame give flicker and "
                .. "errors."), tostring(owner)))
            self.foreign = owner
            return
        end

        if NamePlateApi() == nil then
            self:Print(ns.Localize("this client has no nameplate API, so the "
                .. "nameplate engine does nothing here"))
            self.unsupported = true
            return
        end

        for i = 1, #EVENTS do
            self:RegisterEvent(EVENTS[i][1], EVENTS[i][2])
        end

        self:RegisterCommand("plates", function()
            local own = self:GetSettings()
            if not own then return end
            own.enabled = not own.enabled
            self:Apply()
            self:Print(own.enabled
                and ns.Localize("nameplate engine on")
                or  ns.Localize("nameplate engine off"))
        end)
    end,

    ApplySettings = function(self)
        module = module or self

        -- One path of application: entering the game, changing the profile
        -- and editing any setting all lead here.
        if self.foreign or self.unsupported then return end

        local settings = self:GetSettings()
        if not settings then return end

        -- The positions are parsed BEFORE the "is the engine on" check, and
        -- that is not a liberty but the condition for the settings window not
        -- to lie. The controls write the setting into settings.arrange and
        -- read it out of the compiled plan; while the parsing stood below the
        -- return, a switched-off engine meant this: the list and both sliders
        -- snap back to their former value before one's eyes, "put this part
        -- back" stays forbidden forever — and what was written nevertheless
        -- takes effect at the next login. "As if nothing happened, and then
        -- it happened" is the one wrong answer of all the possible ones.
        --
        -- The second possible answer — to close the controls and say so out
        -- loud — has already been given, and given further up the file: the
        -- positions surface is not shown at all while the engine has not
        -- attached a single nameplate (arrangeable). What is left here is the
        -- case where it is shown by right: the engine worked during this
        -- session and is switched off now. It is that case the saved value has
        -- to answer.
        --
        -- The cost is one table of six records per edit of a setting, and not
        -- one call to a frame.
        arrangePlan = ns.Arrange.Compile(settings)

        if not settings.enabled then
            stop(self)
            return
        end

        start(self)

        -- The attached nameplates are rebuilt by the new settings. The walk
        -- goes over our records and happens on an edit of a setting rather
        -- than per frame: there are dozens of them, and this is a handful of
        -- times per session.
        local width, height, scale = ns.Geometry.Plate(settings)
        local skin = currentSkin()
        local media = currentMedia()
        local gap = gapOf(skin)
        local path = media and media.BarTexture(settings.texture) or nil

        -- The settings are parsed here and only here. After this the already
        -- parsed values travel with the events: the filter's plan, three flags
        -- and two numbers. That is precisely what makes the filter's cost
        -- independent of the number of nameplates on screen.
        plan       = ns.Filter.Compile(settings)
        rulePlan   = ns.Rules.Compile(ns.Rules.List(settings))
        castOn     = settings.castbar and true or false
        threatOn   = settings.threat and true or false
        questOn    = settings.quest and true or false
        truncateOn = settings.truncate and true or false
        plateWidth = width
        plateScale = scale
        nameSize   = nil

        castHeight = castOn and ns.Cast.Height(settings.castHeight) or nil

        local limit = ns.Filter.Limit(plan)
        auraSize = nil
        if limit > 0 then
            auraSize = tonumber(settings.auraSize) or SIZE.default
            if auraSize < SIZE.min then auraSize = SIZE.min end
            if auraSize > SIZE.max then auraSize = SIZE.max end
        end

        for _, record in pairs(state.byUnit) do
            dress(record.frame, record.plate, skin, media, path, width,
                height, scale, gap)

            -- What was switched off has to disappear at once rather than
            -- after the creature leaves and comes back: otherwise the switch
            -- looks broken to exactly the person who pressed it.
            if not castOn then ns.Plate.StopCast(record.frame) end
            if limit <= 0 then ns.Plate.HideAuras(record.frame, 1) end
            if not questOn then ns.Plate.ShowQuest(record.frame, false, skin) end

            paint(record)
            health(record.unit)
            auras(record.unit)
            casting(record.unit)
        end

        -- The nameplates the game is already showing that we have not taken
        -- yet: the module may have been switched on in the middle of a
        -- session. The game returns the list itself, and it is asked for only
        -- here — not per frame and not on an event.
        local api = NamePlateApi()
        if api and type(api.GetNamePlates) == "function" then
            local ok, plates = pcall(api.GetNamePlates)
            if ok and type(plates) == "table" then
                for i = 1, #plates do
                    local plate = plates[i]
                    local unit = plate and plate.namePlateUnitToken
                    if type(unit) == "string"
                        and not ns.Engine.Held(state, unit) then
                        attach(unit)
                    end
                end
            end
        end
    end,

    OnDisable = function()
        -- A disabled module is obliged to stop drawing and to give the game
        -- its nameplates back: the core removes the subscriptions, and we our
        -- frames. The core also gives itself the nameplate skinning back: what
        -- a disabled module had stood aside it takes back at the same moment
        -- it puts the module out.
        drawing = false
        stoodDown = false
        detachAll()
    end,
})

if not handle then
    -- The core has already shown the player the reason; there is nothing
    -- more to do.
    return
end

module = handle

-- The tally table is taken here and now, while the file is read: the paths
-- every nameplate passes along are what increment it, and a field lookup on
-- each of them would cost more than the addition itself.
--
-- The key, on the other hand, is claimed not here but in start(), and the
-- engine's key is its own — plates_engine. The shared plates is incremented by
-- the core's nameplate subsystem, and one number for two owners answers
-- nobody's question: on a fresh install the engine is off, the core's
-- subsystem works, and its tally would read as the engine's work. A claimed
-- zero means "the engine was run and attached to no nameplate"; an unclaimed
-- one means "it was not run during this session", and the report keeps quiet
-- about an unclaimed one: a switched-off engine is the player's choice rather
-- than a failure.
if type(module.Counters) == "function" then
    counters = module:Counters()
end

-- The module's strings go into the core as soon as there is somebody to hand
-- them to: the settings section asks for a translation at the window's very
-- first drawing.
for locale, strings in pairs(ns.Strings or {}) do
    module:RegisterStrings(locale, strings)
end

--============================================================================
-- The settings page, declared as data
--============================================================================

-- The texts were carried over word for word rather than retyped by hand: they
-- were extracted by parsing the former table, because twenty paragraphs
-- retyped by eye are twenty chances to introduce a typo into something already
-- translated into two languages.
--
-- The order is taken from the former section, with one addition: the section
-- headers. There were none before, because AceConfig drew the section as one
-- solid list of twenty rows; in our own window there is nothing to divide a
-- list with but a header.
--
-- The parts' positions (which part is on which side) are NOT yet declared
-- here: that is a list of another kind — not named records but a nameplate's
-- parts with their sides — and the shared list editor does not suit it.

if type(core.Schema) == "table" then
    local Schema = core.Schema
    local PAGE = "umbraplates"

    Schema.Page(PAGE, {
        title = "Nameplates",
        order = 13,
        section = "umbraplates",
    })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "Draws Darken's own nameplates instead of dressing the game's: "
            .. "health bar, name, level, a mark on your target and - each "
            .. "switched on separately below - a cast bar, aura icons, threat "
            .. "color and a quest mark. Off by default - a fresh install "
            .. "changes nothing. Switching it on takes nameplates over from "
            .. "Darken's own plate styling, which stands down while this is on "
            .. "and comes back when it is switched off.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Draw Our Own Nameplates",
        path = { "enabled" },
        apply = "umbraplates",
        hint = "Off leaves the game's nameplates exactly as they are, which is "
            .. "what a fresh install does.",
    })

    Schema.Add(PAGE, { kind = "header", label = "Health Bar" })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Health Bar Texture",
        path = { "texture" },
        apply = "umbraplates",
        values = function()
            -- The game's texture FIRST, the rest alphabetically. In the
            -- former window the list was a map and the order in it was lost —
            -- while the hint promises the player that the first entry is the
            -- game's.
            local out = {}
            local all = textureValues()
            out[#out + 1] = { key = NATIVE, text = all[NATIVE] }
            local rest = {}
            for key in pairs(all) do
                if key ~= NATIVE then rest[#rest + 1] = key end
            end
            table.sort(rest)
            for i = 1, #rest do
                out[#out + 1] = { key = rest[i], text = all[rest[i]] }
            end
            return out
        end,
        hint = "The first entry is the game's own bar texture. The addon's own "
            .. "textures are a gradient from white to a color, and the bar "
            .. "color multiplies them.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Nameplate Width",
        path = { "width" },
        min = BOUNDS.width.min, max = BOUNDS.width.max, step = 1,
        apply = "umbraplates",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Health Bar Height",
        path = { "height" },
        min = BOUNDS.height.min, max = BOUNDS.height.max, step = 1,
        apply = "umbraplates",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Nameplate Scale",
        path = { "scale" },
        min = BOUNDS.scale.min, max = BOUNDS.scale.max, step = 0.05,
        apply = "umbraplates",
        hint = "Scales the whole nameplate, text included. Width and height "
            .. "above are measured before this.",
    })

    Schema.Add(PAGE, { kind = "header", label = "Name and Marks" })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Shorten Long Names",
        path = { "truncate" },
        apply = "umbraplates",
        hint = "Cuts a name that does not fit the nameplate width and marks the "
            .. "cut with three dots. Off leaves long names running past the "
            .. "bar.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Color by Threat",
        path = { "threat" },
        apply = "umbraplates",
        hint = "Colors the health bar of unfriendly creatures by how close they "
            .. "are to attacking you. Threat outranks class and reaction color, "
            .. "and only while it has something to say: a creature nobody is "
            .. "fighting keeps its own color.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Mark Quest Targets",
        path = { "quest" },
        apply = "umbraplates",
        hint = "Puts a small mark beside the nameplate of a creature one of "
            .. "your quests wants.",
    })

    Schema.Add(PAGE, { kind = "header", label = "Cast Bar" })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Cast Bar on the Nameplate",
        path = { "castbar" },
        apply = "umbraplates",
        hint = "Shows what the creature is casting under its health bar. The "
            .. "bar is moved by the engine itself, so it costs nothing per "
            .. "frame. This is the nameplate's own cast bar - your own cast bar "
            .. "belongs to Darken and to the cast bars module.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Cast Bar Height",
        path = { "castHeight" },
        min = CAST.min, max = CAST.max, step = 1,
        apply = "umbraplates",
    })

    Schema.Add(PAGE, { kind = "header", label = "Aura Icons" })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Aura Icons",
        path = { "auras" },
        apply = "umbraplates",
        hint = "Shows aura icons above the nameplate. Which auras pass is set "
            .. "below. Time left is drawn by the engine's own sweep, so the "
            .. "icons cost nothing per frame.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show Harmful Auras",
        path = { "auraHarmful" },
        apply = "umbraplates",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show Helpful Auras",
        path = { "auraHelpful" },
        apply = "umbraplates",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Only Auras You Applied",
        path = { "auraOnlyMine" },
        apply = "umbraplates",
        hint = "A creature in a raid carries everybody's auras. Off shows all "
            .. "of them, which in a busy fight is a wall of icons. On by "
            .. "default.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "How Many Icons at Most",
        path = { "auraLimit" },
        min = LIMIT.min, max = LIMIT.max, step = 1,
        apply = "umbraplates",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Aura Icon Size",
        path = { "auraSize" },
        min = SIZE.min, max = SIZE.max, step = 1,
        apply = "umbraplates",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "What to Do with the List",
        path = { "auraMode" },
        apply = "umbraplates",
        values = function()
            local all = auraModeValues()
            return {
                { key = "off",   text = all.off },
                { key = "allow", text = all.allow },
                { key = "deny",  text = all.deny },
            }
        end,
        hint = "An empty list means the list is not used at all, whichever "
            .. "entry is picked here.",
    })

    Schema.Add(PAGE, {
        kind = "text",
        label = "Spell List",
        path = { "auraList" },
        lines = 5,
        apply = "umbraplates",
        hint = "Spell names, separated by commas or written one per line. A "
            .. "name written in the list is shown even when \"only auras you "
            .. "applied\" is on - naming a spell is already an answer.",
    })

    --========================================================================
    -- Rules for a single unit
    --========================================================================

    if type(core.ListEditor) == "table" then
        --- Apply: a rule changes what is already on screen.
        local function applied()
            if module ~= nil then module:Apply() end
        end

        --- The rule itself, by name.
        local function entryOf(name)
            local _, rule = ns.Rules.Find(ruleList(), name)
            return rule
        end

        Schema.Add(PAGE, { kind = "header", label = "Rules" })

        Schema.Add(PAGE, {
            kind = "note",
            hint = "A rule gives named creatures a nameplate of their own. "
                .. "Its color outranks class and reaction color, because you "
                .. "named the creature by hand and those are guesses - but "
                .. "threat color still outranks the rule, so a creature "
                .. "turning on you is never hidden by it. With no rules "
                .. "nothing changes.",
        })

        Schema.Add(PAGE, {
            kind = "widget",
            label = "Rule to Edit",
            build = core.ListEditor.Build,
            hook = {
                Entries = function() return ruleList() end,

                Add = function()
                    if module == nil then return nil end

                    local rule, why = ns.Rules.Add(ruleList(),
                        module.ruleDraftName, module.ruleDraftText)
                    if rule == nil then
                        module:Print(ruleProblem(why))
                        return nil
                    end

                    module.ruleDraftName, module.ruleDraftText = nil, nil
                    applied()
                    return rule.name
                end,

                Remove = function(name)
                    if ns.Rules.Remove(ruleList(), name) then applied() end
                end,

                Move = function(name, delta)
                    if ns.Rules.Move(ruleList(), name, delta) then
                        applied()
                    end
                end,

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
                            local ok, why = ns.Rules.Rename(ruleList(),
                                chosen, value)
                            if not ok then
                                module:Print(ruleProblem(why))
                                return
                            end
                            applied()
                        end,
                    }

                    rows[#rows + 1] = {
                        kind = "text",
                        label = "Creatures",
                        apply = "none",
                        lines = 4,
                        hint = "Creature names, separated by commas or "
                            .. "written one per line, and capitals do not "
                            .. "matter. An entry of digits only is read as a "
                            .. "creature id instead: a name belongs to the "
                            .. "language of your client and is not unique, "
                            .. "an id is neither.",
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
                            local ok, why = ns.Rules.SetText(ruleList(),
                                chosen, value)
                            if not ok then
                                module:Print(ruleProblem(why))
                                return
                            end
                            applied()
                        end,
                    }

                    -- What follows cannot belong to a draft: the colour and
                    -- the size belong to a rule that was created.
                    if chosen == nil then return rows end

                    rows[#rows + 1] = {
                        kind = "toggle",
                        label = "Use That Color",
                        apply = "none",
                        hint = "Off leaves the color alone and the rule "
                            .. "changes the size only.",
                        get = function()
                            local rule = entryOf(chosen)
                            return type(rule) == "table"
                                and type(rule.color) == "table"
                        end,
                        set = function(value)
                            local list = ruleList()
                            if value then
                                -- Switched on without a chosen colour it
                                -- takes white: that is a colour on which it
                                -- is visible that the rule paints, and the
                                -- player goes straight to changing it.
                                -- Transparent or black would look like "it
                                -- does not work".
                                local rule = entryOf(chosen)
                                local had = type(rule) == "table"
                                    and type(rule.color) == "table"
                                    and rule.color or nil
                                if had ~= nil then return end
                                if ns.Rules.SetColor(list, chosen, 1, 1, 1)
                                then applied() end
                                return
                            end
                            -- Removal: there is no colour at all, and the
                            -- skin does the painting.
                            if ns.Rules.SetColor(list, chosen) then
                                applied()
                            end
                        end,
                    }

                    rows[#rows + 1] = {
                        kind = "color",
                        label = "Health Bar Color",
                        apply = "none",
                        hint = "The color this rule paints the health bar "
                            .. "and the name with. Threat color still "
                            .. "outranks it.",
                        -- Greyed out while the rule does not paint: a
                        -- colour that changes nothing is a second place where
                        -- the player looks for the answer to "why does it not
                        -- work".
                        disabled = function()
                            local rule = entryOf(chosen)
                            return not (type(rule) == "table"
                                and type(rule.color) == "table")
                        end,
                        -- A rule's colour lies as an ARRAY of three, while
                        -- the module's settings use the fields r, g, b. The
                        -- conversion is here rather than in the window: the
                        -- window is not obliged to know who stores what how,
                        -- and rewriting the saved variables for the sake of
                        -- uniformity is not allowed — the player's chosen
                        -- colours already lie there.
                        get = function()
                            local rule = entryOf(chosen)
                            local c = type(rule) == "table" and rule.color
                                or nil
                            if type(c) ~= "table" then
                                return { r = 1, g = 1, b = 1 }
                            end
                            return { r = c[1], g = c[2], b = c[3] }
                        end,
                        set = function(value)
                            if type(value) ~= "table" then return end
                            if ns.Rules.SetColor(ruleList(), chosen,
                                value.r, value.g, value.b) then
                                applied()
                            end
                        end,
                    }

                    rows[#rows + 1] = {
                        kind = "slider",
                        label = "Size of Those Nameplates",
                        apply = "none",
                        min = RSCALE.min, max = RSCALE.max, step = 0.05,
                        hint = "Multiplies the nameplate scale set above, so "
                            .. "one means no change at all.",
                        get = function()
                            local rule = entryOf(chosen)
                            if rule == nil then return RSCALE.default end
                            return ns.Rules.Scale(rule.scale)
                        end,
                        set = function(value)
                            if ns.Rules.SetScale(ruleList(), chosen, value)
                            then applied() end
                        end,
                    }

                    return rows
                end,
            },
        })
    end
    --========================================================================
    -- The parts' positions
    --========================================================================

    -- The same list editor the rules use, and that is no stretch: choosing a
    -- part and editing its fields is the same action as choosing a rule and
    -- editing its fields. The difference is only in what the list can do, and
    -- it is declared honestly: the parts are not created, not taken away and
    -- not rearranged. Their set is constant — the name, the level, the cast
    -- bar, the aura icons, the quest icon and the nameplate itself — and the
    -- order in it means nothing, because every part stands on its own side
    -- rather than in a queue.
    --
    -- The whole list goes away when it is not the module that draws the
    -- nameplates: it places the parts of OUR nameplate, and in that case there
    -- are none of those on screen at all. A setting that affects nothing is
    -- worse than a missing one — the player moves a number and does not
    -- understand why nothing happens.

    if type(core.ListEditor) == "table" then
        local Arrange = ns.Arrange

        --- The parts as records for the editor, in their declared order.
        local function parts()
            local out = {}
            for i = 1, #Arrange.PARTS do
                out[i] = { name = Arrange.PARTS[i] }
            end
            return out
        end

        --- Apply: the positions change what is already on screen.
        local function applied()
            if module ~= nil then module:Apply() end
        end

        Schema.Add(PAGE, {
            kind = "header",
            label = "Where the Parts Sit",
            hidden = function() return not arrangeable() end,
        })

        Schema.Add(PAGE, {
            kind = "note",
            hidden = function() return not arrangeable() end,
            hint = "Each part of the nameplate sits on one side of it and "
                .. "can be nudged two ways from there. A part left alone "
                .. "stays exactly where it was before this existed.",
        })

        Schema.Add(PAGE, {
            kind = "widget",
            label = "Part to Place",
            build = core.ListEditor.Build,
            hidden = function() return not arrangeable() end,
            hook = {
                Entries = parts,

                Fields = function(chosen)
                    if chosen == nil then return {} end

                    local rows = {}

                    rows[#rows + 1] = {
                        kind = "select",
                        label = "Side It Sits On",
                        apply = "none",
                        hint = "Which side of the nameplate this part sits "
                            .. "on. Not every side suits every part, and "
                            .. "only the ones that do are listed.",
                        -- The places are asked of the part itself: the name
                        -- and the aura icons have different ones, and a
                        -- shared list would offer the player what this part
                        -- cannot do.
                        values = function()
                            local words = placeWords()
                            local out = {}
                            for _, place in ipairs(Arrange.PLACES[chosen]
                                or {}) do
                                out[#out + 1] = { key = place,
                                    text = words[place] or place }
                            end
                            return out
                        end,
                        get = function()
                            local entry = Arrange.Entry(Settings(), chosen)
                            local place = type(entry) == "table"
                                and entry.place or nil
                            if Arrange.Has(chosen, place) then return place end
                            return Arrange.Default(chosen)
                        end,
                        set = function(value)
                            if Arrange.SetPlace(Settings(), chosen, value)
                            then applied() end
                        end,
                    }

                    for _, axis in ipairs({
                        { key = "x", label = "Nudge Sideways" },
                        { key = "y", label = "Nudge Up or Down" },
                    }) do
                        rows[#rows + 1] = {
                            kind = "slider",
                            label = axis.label,
                            apply = "none",
                            min = Arrange.OFFSET.min,
                            max = Arrange.OFFSET.max,
                            step = 1,
                            hint = "A correction measured from the side "
                                .. "above, so zero means the part sits "
                                .. "exactly where that side puts it.",
                            get = function()
                                local entry = Arrange.Entry(Settings(),
                                    chosen)
                                if type(entry) ~= "table" then
                                    return Arrange.OFFSET.default
                                end
                                return Arrange.Offset(entry[axis.key])
                            end,
                            set = function(value)
                                if Arrange.SetOffset(Settings(), chosen,
                                    axis.key, value) then applied() end
                            end,
                        }
                    end

                    rows[#rows + 1] = {
                        kind = "action",
                        label = "Put This Part Back",
                        apply = "none",
                        hint = "Returns this one part to where it sat "
                            .. "before you moved it. The others are left "
                            .. "alone.",
                        run = function()
                            if Arrange.Reset(Settings(), chosen) then
                                applied()
                            end
                        end,
                    }

                    return rows
                end,
            },
        })

        Schema.Add(PAGE, {
            kind = "action",
            label = "Put Every Part Back",
            apply = "none",
            hidden = function() return not arrangeable() end,
            hint = "Returns all six parts to where they sat before any of "
                .. "this was moved.",
            run = function()
                if Arrange.ResetAll(Settings()) then applied() end
            end,
        })
    end
end
