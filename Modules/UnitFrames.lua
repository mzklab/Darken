local ADDON, ns = ...

-- Unit frames: the addon's own textures on the health and power bars, the
-- name's colour and the frame's scale. The addon creates no frames of its own
-- — the game's own are repainted.
--
-- Why a bar's colour is our business too. Our textures are a horizontal
-- gradient from white to a colour, and the engine lays the bar's colour over
-- them by multiplication: the white end gives the pure colour, the pastel end
-- a muted shade. That is, a texture without a chosen colour does not work at
-- all: the game paints health green, and our texture on it stays green. So
-- the subsystem sets both the texture and the colour — by class, by reaction,
-- by the kind of power, or a custom one — and by default sets neither: the
-- game's native look stays both the initial one and a choice.
--
-- Hence also the rule about "the game's colour under our texture". The choice
-- "the game's colour" on a native bar means "do not touch": the game owns the
-- colour there. On a bar with our texture there is nobody to own it — there is
-- no colour in the gradient — and the same "do not touch" would give a white
-- bar on which the texture did not lie over the colour but replaced it. So
-- under our texture the game's colour is not inaction but work: it is computed
-- from the game's own tables (UnitFrames.GameColor) and applied afresh after
-- every repaint of the game's.
--
-- The colour has one owner. The game repaints the bars itself on every update
-- of a unit, and our colour would be gone after its call. So the subsystem
-- does not argue with it but stands behind it: a hook through hooksecurefunc
-- on the game's own repainting functions (the unitframe-recolor group in
-- Core/Compat.lua) plus the events for a change of target, of power and of
-- form.
--
-- How this gets along with the dimming. It does not — and that is a decision
-- rather than an oversight. The dimming walks a frame and its children but
-- skips objects of the StatusBar type entirely: a bar's fill shows a quantity
-- and is not subject to dimming either here or there (see BAR_FACTOR below).
-- The dimming writes into its own native-colour memory for the frame's chrome,
-- this subsystem into its own records for the bars and into the colour of the
-- name's font string. They have no objects in common, so the order of
-- application decides nothing.
--
-- Combat restrictions. The engine forbids changing a protected frame's
-- position, size, visibility, parent and scale: SetPoint, ClearAllPoints,
-- SetAllPoints, SetWidth, SetHeight, SetSize, Show, Hide, SetParent,
-- SetScale. All of those are protected methods, and a call in combat gives
-- ADDON_ACTION_BLOCKED. Of what this subsystem does, exactly one operation
-- falls under the prohibition — SetScale. Assigning a bar's texture
-- (SetStatusBarTexture), its colour (SetStatusBarColor) and the text's colour
-- (SetTextColor) is not protected: that is the look rather than geometry or
-- visibility. So only the scale is deferred, while the textures and the name's
-- colour are applied at once, in combat too. Deferring them would mean making
-- the addon sluggish for no reason.

local UnitFrames = {
    name = "unitframes",
}
ns.UnitFrames = UnitFrames

-- The tally of what was done (Core/Tally.lua). The reference is taken once
-- while the file is read: the handler on top of the game's function fires as
-- often as the game calls its own function, and it must not cost more than one
-- addition of integers.
local counters = ns.Counters or {}
ns.Counters = counters

-- Hooks installed and hooks fired. The first, were it zero, would mean that
-- not one guessed name of a game function was found; the second, with the
-- first non-zero, would mean the name was found and came to nothing.
counters.hooked_unitframes = counters.hooked_unitframes or 0
counters.fired_unitframes  = counters.fired_unitframes  or 0

-- The names of the game's functions whose hooks have already been
-- counted.
local counted = {}

-- The bars whose texture the subsystem really replaced. A zero means the
-- player stayed on the game's native textures — that is their right; this
-- counter answers not "is it broken" but "did the chosen texture reach the
-- screen".
counters.retextured = counters.retextured or 0

-- The last texture path we assigned to a bar. Side memory, because the bar
-- is somebody else's object.
-- It exists not for reversibility but so as not to touch a bar for nothing:
-- the settings are re-read on a change of target, of pet and of the group's
-- composition, and replacing the texture each time would make the engine
-- reload the file.
local APPLIED = ns.Skin.Memory()
-- Exposed for the tests' sake: the record's identity is knowledge, and a
-- second spelling of it in the tests would diverge from this one silently.
UnitFrames.APPLIED_FIELD = APPLIED

-- The marker for "the game's native texture". It is not a texture's name but
-- a refusal to replace, so the value was chosen so as not to collide with a
-- name from the LibSharedMedia registry: two leading underscores, as in
-- Fonts.INHERIT. The value reaches SavedVariables, and changing it after the
-- fact is not allowed — a choice the player saved would stop being found.
local NATIVE = "__native"
UnitFrames.NATIVE = NATIVE

-- A bar's original texture. Written once — before our first replacement —
-- and unchanged after that, however many times the player switches the list:
-- the computation always goes from what was remembered rather than from what
-- is current. The same scheme as the dimming subsystem's native-colour memory.
-- A value of false means "it could not be read": without it a repeated read
-- after a replacement would remember our own texture as the native one, and
-- the restoration would stop restoring.
local BASE = ns.Skin.Memory()

-- The original colour of the name's font string. Exactly the same meaning as
-- BASE, and it is written once as well.
local NAME_BASE = ns.Skin.Memory()

-- A bar's original colour. The same meaning as BASE and NAME_BASE: read
-- once, before our first repaint, and unchanged after that. Without it a
-- return to the native look would restore not the native colour but our
-- previous one — precisely the defect that is invisible to the eye in the
-- client.
local COLOR_BASE = ns.Skin.Memory()

-- The marker for "we have already assigned this bar's colour". It exists
-- precisely for the rule "a fresh install touches not one object of the
-- game's": in the native mode and with no dimming an untouched bar stays
-- untouched, while a touched one is returned to the remembered colour.
local COLOR_SET = ns.Skin.Memory()

-- The colour that stood on a bar the last time the game itself painted it.
-- Observed rather than derived from the game's tables: the tables can only be
-- asked about something whose name we know, and for the target those names
-- arrive as secret values and are of no use as keys.
local COLOR_GAME = ns.Skin.Memory()

-- The colour we last laid on a bar. It exists precisely to tell somebody
-- else's write from our own: without it the second look would remember our own
-- colour as "the game's colour", the third the same again, and our choice
-- would become "the native one".
local COLOR_WROTE = ns.Skin.Memory()

-- The fields the engine keeps the bars in. These are candidates rather than
-- facts: different builds of the client name the field differently, and
-- whatever is absent is silently skipped. The names are not invented: the
-- engine itself uses them.
local HEALTH_FIELDS = { "healthbar", "healthBar", "HealthBar" }
local POWER_FIELDS  = { "manabar", "manaBar", "ManaBar", "powerBar", "PowerBar" }

-- The unit name's font string.
local NAME_FIELDS = { "name" }

-- A fallback palette of reactions in case the client has no table of faction
-- bar colours. The indices are the engine's own: 1-3 hostile, 4 neutral, 5-8
-- friendly.
local REACTION_COLORS = {
    [1] = { r = 0.79, g = 0.22, b = 0.22 },
    [2] = { r = 0.79, g = 0.22, b = 0.22 },
    [3] = { r = 0.87, g = 0.44, b = 0.22 },
    [4] = { r = 0.94, g = 0.87, b = 0.32 },
    [5] = { r = 0.24, g = 0.74, b = 0.30 },
    [6] = { r = 0.24, g = 0.74, b = 0.30 },
    [7] = { r = 0.24, g = 0.74, b = 0.30 },
    [8] = { r = 0.24, g = 0.74, b = 0.30 },
}

-- The events after which the name's colour may be stale: the target, the
-- focus, the pet, the group's composition or the unit's attitude to the player
-- changed. The list holds candidates: some of the events do not exist on every
-- supported client (there is no focus on vanilla, and the group's composition
-- is named differently there), and each is subscribed to separately and under
-- a guard.
local REFRESH_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "UNIT_PET",
    "UNIT_FACTION",
    "GROUP_ROSTER_UPDATE",
    "PARTY_MEMBERS_CHANGED",
    -- The kind of power changes without a change of unit: a druid in cat
    -- form spends energy and in bear form rage, while the bar stays the
    -- same.
    "UNIT_DISPLAYPOWER",
    "UPDATE_SHAPESHIFT_FORM",
}

--- The colour channels out of a table of either shape.
-- The engine returns class colours as { r = , g = , b = }, and a colour
-- setting in AceConfig is stored the same way; an array of three numbers turns
-- up in other people's tables. Both shapes are parsed, everything else gives a
-- nil.
-- @param color table|nil
-- @return number|nil, number|nil, number|nil
local function channels(color)
    if type(color) ~= "table" then return nil end

    local r, g, b = color.r, color.g, color.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        r, g, b = color[1], color[2], color[3]
    end

    -- A third shape: a colour object that returns the channels by a method.
    -- That is how the game keeps RAID_CLASS_COLORS on later builds, and it may
    -- have no r/g/b fields at all. A field is preferred over a call — a call is
    -- more expensive — but a missing field here does not mean "there is no
    -- colour" but "ask differently".
    if (type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number")
        and type(color.GetRGB) == "function" then
        local ok, cr, cg, cb = pcall(color.GetRGB, color)
        if ok then r, g, b = cr, cg, cb end
    end

    -- The channels may arrive as secret values: the colour is read from the
    -- game rather than taken from our palette. An unusable channel means
    -- "there is no colour" rather than "the colour is black".
    r, g, b = ns.Skin.Numeric(r), ns.Skin.Numeric(g), ns.Skin.Numeric(b)
    if r == nil or g == nil or b == nil then return nil end

    return r, g, b
end

--- A unit name's colour.
--
-- A pure function: everything it needs arrives as arguments, so the rule is
-- tested outside the client. There are three modes, and each can fall back: by
-- class — when the class is unknown (the unit is not a player), by reaction —
-- when the reaction is unknown (the unit is outside one's field of view). The
-- fall-back goes down the list, to the colour the player chose, and white at
-- the very end. A silent nil here would be worse: the name would stay the
-- colour it was, and the "by class" rule would look like it worked every other
-- time.
--
-- @param mode string "class" | "reaction" | "fixed"
-- @param info table|nil { class, classColors, reaction, reactionColors, fixed }
-- @return number, number, number
function UnitFrames.NameColor(mode, info)
    info = type(info) == "table" and info or {}

    -- A creature somebody else tagged is grey, and no chosen mode overrides
    -- that.
    --
    -- It is not our colour but the game's answer to "is this your kill": a
    -- creature somebody else struck the game paints grey, and the player
    -- decides by that grey whether to strike or to walk on. By painting it by
    -- reaction we took the answer away and gave nothing in exchange — the
    -- author wrote exactly that: its health does not turn grey the way it
    -- should.
    --
    -- It stands first, before every mode: "by class" does not apply to a
    -- creature at all, while "by reaction" and "a custom colour" are about WHO
    -- is in front of you, and the grey is about WHOSE it is.
    if info.tapDenied == true then
        return ns.Skin.TapColor()
    end

    if mode == "class" then
        local colors = info.classColors
        local token = info.class
        if type(colors) == "table" and type(token) == "string" then
            local r, g, b = channels(colors[token])
            if r then return r, g, b end
        end
        mode = "reaction"
    end

    if mode == "reaction" then
        local colors = type(info.reactionColors) == "table"
            and info.reactionColors or REACTION_COLORS
        local index = tonumber(info.reaction)
        if index then
            local r, g, b = channels(colors[index])
            if r then return r, g, b end
        end
    end

    local r, g, b = channels(info.fixed)
    if r then return r, g, b end

    return 1, 1, 1
end

--- The power colour's channels out of the game's own tables.
--
-- The numbers here are not invented and cannot be: the power colours live in
-- the client's tables (PowerBarColor, and ManaBarColor on old builds), and
-- both arrive as arguments — otherwise the function would stop being pure. The
-- game's table is keyed two ways: both by the power's string token ("MANA",
-- "RAGE") and by its numeric type. Both are checked, first in the main table
-- and then in the fallback one.
--
-- @param info table { power, powerType, powerColors, powerFallback }
-- @return number|nil, number|nil, number|nil
local function powerChannels(info)
    local token = info.power
    local index = tonumber(info.powerType)

    for i = 1, 2 do
        local colors = (i == 1) and info.powerColors or info.powerFallback
        if type(colors) == "table" then
            if type(token) == "string" then
                local r, g, b = channels(colors[token])
                if r then return r, g, b end
            end
            if index then
                local r, g, b = channels(colors[index])
                if r then return r, g, b end
            end
        end
    end

    return nil
end

--- A bar's colour.
--
-- A pure function and the only place where this decision is made. There are
-- four modes, and three of them are exactly the ones the name's colour already
-- has: "by class", "by reaction" and "a custom colour". There is no second
-- copy of the fall-back rule here: that branch calls UnitFrames.NameColor. The
-- fourth mode — "by the kind of power" — lives on the power bar alone and
-- takes its numbers from the game's table.
--
-- The native look answers nil, and that is not a refusal: a nil means "the
-- colour is not ours", that is, the bar has to be returned to the remembered
-- colour of the game's rather than painted in something of ours. The caller is
-- obliged to tell that apart from "paint it white", which is why the native
-- look has an answer of its own.
--
-- An unknown class falls back to the reaction, an unknown kind of power to the
-- colour the player chose, and white at the very end of both paths: a bar
-- without a colour would look broken, while silence would leave the previous
-- unit's colour on it.
--
-- @param mode string|nil "__native" | "class" | "reaction" | "power" | "fixed"
-- @param info table|nil { class, classColors, reaction, reactionColors,
--                         power, powerType, powerColors, powerFallback, fixed }
-- @return number|nil, number|nil, number|nil
function UnitFrames.BarColor(mode, info)
    if mode == nil or mode == NATIVE then return nil end

    info = type(info) == "table" and info or {}

    if mode == "power" then
        local r, g, b = powerChannels(info)
        if r then return r, g, b end

        r, g, b = channels(info.fixed)
        if r then return r, g, b end

        return 1, 1, 1
    end

    return UnitFrames.NameColor(mode, info)
end

--- The colour the game itself paints this bar with.
--
-- A pure function and the second answer to "which colour is native here". The
-- first is the remembered COLOR_BASE, that is, the colour that stood on the
-- bar before us. It is good for a restoration and no good for display: for the
-- target it freezes on the very first opponent, and for a bar the game has not
-- painted yet it does not exist at all. What has to be displayed is what the
-- game would display now, and that is taken from its own tables:
-- RAID_CLASS_COLORS, FACTION_BAR_COLORS, PowerBarColor. There are no numbers
-- of our own here — the tables arrive as arguments.
--
-- The difference from BarColor: that one answers the player's choice and
-- always returns something in the end — the custom colour, and if it will not
-- give that, then white. There is no white at the end here and there must not
-- be: white is the very defect the function is written for. The game does not
-- know the colour — we answer nil, and the caller does not touch the bar at
-- all.
--
-- @param kind string|nil "health" | "power"
-- @param info table|nil the same data as BarColor's
-- @return number|nil, number|nil, number|nil
function UnitFrames.GameColor(kind, info)
    if type(info) ~= "table" then return nil end

    if kind == "power" then return powerChannels(info) end
    if kind ~= "health" then return nil end

    -- Health: a class belongs to players only, creatures have none, and then
    -- the game paints the bar by the attitude to the player. The order is the
    -- same as the name's.
    local colors, token = info.classColors, info.class
    if type(colors) == "table" and type(token) == "string" then
        local r, g, b = channels(colors[token])
        if r then return r, g, b end
    end

    local reactions = type(info.reactionColors) == "table"
        and info.reactionColors or REACTION_COLORS
    local index = tonumber(info.reaction)
    if index then
        local r, g, b = channels(reactions[index])
        if r then return r, g, b end
    end

    return nil
end

-- The queue of deferred changes lives in the core (Core/Combat.lua) and is
-- only given its former names here.
--
-- It was written here, and three other subsystems took it from here. When the
-- same queue was needed by modules outside the core, it became clear its place
-- was not in the unit frames subsystem: the rule "a repeated write evicts the
-- former one, keeping its place in the queue" is the core's rule rather than
-- one subsystem's. So it moved there entirely while these four names stayed:
-- they are already written in the subsystems and in the tests, and rewriting
-- them for the move's sake would mean touching four files instead of one.
UnitFrames.NewQueue = ns.Combat.NewQueue
UnitFrames.Enqueue  = ns.Combat.Enqueue
UnitFrames.Pending  = ns.Combat.Pending
UnitFrames.Drain    = ns.Combat.Drain

-- The subsystem's only queue: there is nothing to defer here but the
-- scale.
UnitFrames.queue = UnitFrames.NewQueue()

--- The first existing field of an object out of a list of candidates.
-- @param frame table|nil
-- @param fields table array of field names
-- @param method string the name of a method the object found must have
-- @return table|nil
local function pick(frame, fields, method)
    if type(frame) ~= "table" then return nil end
    for i = 1, #fields do
        local object = frame[fields[i]]
        if type(object) == "table" and type(object[method]) == "function" then
            return object
        end
    end
    return nil
end
UnitFrames.Pick = pick

--- Which file is on the bar right now.
--
-- Not the one we remembered but the one really there: between our application
-- and this question anybody could have repainted the bar — the game on a
-- change of target, another addon, a reload of its layout.
--
-- The path may arrive as a secret value: then it cannot be compared, and the
-- answer is nil, that is, "unknown". Uncertainty here is resolved towards
-- work: since we do not know what is on the bar, we will assign the texture
-- afresh.
--
-- @param bar table|nil the bar
-- @return string|nil the path to the file, or nil if it could not be read
function UnitFrames.CurrentTexture(bar)
    if type(bar) ~= "table" then return nil end
    if type(bar.GetStatusBarTexture) ~= "function" then return nil end

    local ok, texture = pcall(bar.GetStatusBarTexture, bar)
    if not ok then return nil end

    local value
    if type(texture) == "string" then
        value = texture
    elseif type(texture) == "table" and type(texture.GetTexture) == "function" then
        local okPath, path = pcall(texture.GetTexture, texture)
        if okPath then value = path end
    end

    if type(value) ~= "string" then return nil end

    -- Through the secrecy probe: a path that arrived as a secret value
    -- passes the type check and raises an error at the very first
    -- comparison.
    local probe = ns.Skin and ns.Skin.Textual
    if type(probe) == "function" then return probe(value) end
    return value
end

--- Strip from a bar's texture everything left over from the previous one.
--
-- === Why our own texture used to lie crookedly ===
--
-- SetStatusBarTexture replaces the file but not the object: the engine keeps
-- one and the same texture on a bar for its whole life and only reassigns its
-- picture. Everything the game set up on that object for its own picture
-- remains on ours — and it set up a fair amount, each setting spoiling
-- somebody else's file in its own way.
--
--   Tiling (SetHorizTile, SetVertTile). A tiled picture repeats instead of
--   stretching, and a gradient from dark to light turns into a palisade of
--   identical strips.
--
--   Snapping to the pixel grid (SetSnapToPixelGrid, SetTexelSnappingBias).
--   The game switches it on for its own bars, and a texture's edge creeps half
--   a pixel to wherever it finds it convenient to lie. On the native picture,
--   drawn for that snapping, it is unnoticeable; on a gradient it is blur and
--   a shivering edge at every change of health.
--
-- Some of the methods on this list may be absent: the clients differ, and some
-- of them appeared later than others. A missing method is not an error but
-- "this does not happen here": then there is nothing to spoil either.
--
-- @param bar table|nil the bar
-- @return boolean whether a texture was found that had anything to strip
function UnitFrames.NormalizeBarTexture(bar)
    if type(bar) ~= "table" then return false end
    if type(bar.GetStatusBarTexture) ~= "function" then return false end

    local ok, texture = pcall(bar.GetStatusBarTexture, bar)
    if not ok or type(texture) ~= "table" then return false end

    -- The trimming (SetTexCoord) is deliberately absent here, and that is a
    -- correction rather than forgetfulness.
    --
    -- It used to be here, and with it I broke what I was fixing. A bar is a
    -- StatusBar, and a StatusBar shows the share it is filled to by TRIMMING
    -- THE COORDINATES OF ITS OWN texture: half the health is half the picture
    -- rather than half the width, which is why a gradient does not get
    -- squeezed. Resetting the coordinates to "the whole file" means taking
    -- away from the engine the thing it shows health with, and the picture
    -- lies however it happens to. The author sent in a screenshot of a bat's
    -- bar with the words "the texture lay badly".
    --
    -- The coordinates belong to the engine entirely: it sets them afresh on
    -- every SetValue, and there is no point clearing them after replacing the
    -- file — the very first repaint of the health will rewrite them.
    if type(texture.SetHorizTile) == "function" then
        pcall(texture.SetHorizTile, texture, false)
    end
    if type(texture.SetVertTile) == "function" then
        pcall(texture.SetVertTile, texture, false)
    end
    if type(texture.SetSnapToPixelGrid) == "function" then
        pcall(texture.SetSnapToPixelGrid, texture, false)
    end
    if type(texture.SetTexelSnappingBias) == "function" then
        pcall(texture.SetTexelSnappingBias, texture, 0)
    end

    return true
end

--- Assign a texture to a bar, preserving its colour.
--
-- The colour is read before the replacement and restored after: some builds
-- reset a bar's vertex colour along with the texture's file, and the bar would
-- turn white — that is, the gradient would stop being tinted by the class
-- colour, which is what all this is for. Exactly what was read is restored:
-- the colour stays somebody else's, we do not choose it.
--
-- What this restoration cannot do and cannot be made to do: assign a colour
-- the bar never had. A bar the game has not painted yet (the target at login)
-- or does not intend to paint (its colour lives inside the native texture's
-- own file) returns white — and gets white back. Then our gradient stays
-- untinted, and the texture looks as though it replaced the colour rather than
-- lay over it. The colour under our texture has one owner, and that is
-- ApplyBarColor: that work is not moved here.
--
-- The native colour is remembered here and before the replacement — not for
-- this call's sake but for the sake of a return to the native look: read after
-- the replacement, it would remember white as "the game's colour", and "the
-- native texture" would restore a white bar.
--
-- @param bar table|nil the bar
-- @param path string|nil the path to the texture's file
-- @return boolean whether it was applied
function UnitFrames.SetBarTexture(bar, path)
    if type(bar) ~= "table" then return false end
    if type(bar.SetStatusBarTexture) ~= "function" then return false end
    if type(path) ~= "string" or path == "" then return false end

    -- The same texture is already there — nothing to touch. The settings are
    -- re-read on every change of target, and an extra replacement of the file
    -- would improve nothing.
    --
    -- "Already there" is checked against the bar itself rather than against
    -- our memory, and here is why. Between our application and this question
    -- the game repaints the bar: for the target it reassigns the file on a
    -- change of target and on a change of the kind of power. Our memory knows
    -- nothing of that, answers "ours is already there" — and the texture never
    -- comes back until the player cycles the setting by hand. That is exactly
    -- how our texture "was not applied to the target" while staying applied to
    -- everybody else.
    --
    -- It could not be read (the path arrived as a secret value) — we treat it
    -- as not being there and assign it afresh: an extra assignment costs one
    -- call, a skipped one looks like a failure.
    if APPLIED[bar] == path and UnitFrames.CurrentTexture(bar) == path then
        return true
    end

    -- Before the replacement and only before it. After that the record does
    -- not change.
    local base = UnitFrames.BaseBarColor(bar)

    local r, g, b, a
    if type(bar.GetStatusBarColor) == "function" then
        local ok, cr, cg, cb, ca = pcall(bar.GetStatusBarColor, bar)
        if ok and type(cr) == "number" then r, g, b, a = cr, cg, cb, ca end
    end
    if r == nil and base then r, g, b, a = base[1], base[2], base[3], base[4] end

    if not pcall(bar.SetStatusBarTexture, bar, path) then return false end

    -- Right after the file was replaced and before the colour is restored:
    -- the texture object stayed the same, and the trimming, the tiling and the
    -- snapping to the grid the game set up for its own picture are still on
    -- it.
    UnitFrames.NormalizeBarTexture(bar)

    if r and type(bar.SetStatusBarColor) == "function" then
        pcall(bar.SetStatusBarColor, bar, r, g, b, a or 1)
    end

    APPLIED[bar] = path
    counters.retextured = counters.retextured + 1
    return true
end

--- Whether a bar wears a texture other than the native one.
--
-- The question is not idle: under our texture and under the native one the
-- colour has different owners. The game's native texture owns the colour too —
-- in some places as a vertex colour, in others drawn inside the file itself —
-- and there is no point reaching in there. Our texture is a gradient from
-- white and has no colour in it at all: we are the ones obliged to tint it, or
-- the bar comes out white.
--
-- The comparison is made against the remembered native texture rather than
-- against the NATIVE marker: the choice "the native one" lays exactly the
-- remembered path onto the bar, and from the setting's value those two cases
-- can no longer be told apart. The native one could not be read
-- (BASE[bar] == false) — then what is on the bar is ours: ours we set
-- ourselves.
--
-- @param bar table|nil the bar
-- @return boolean
function UnitFrames.Textured(bar)
    if type(bar) ~= "table" then return false end

    local applied = APPLIED[bar]
    if type(applied) ~= "string" then return false end

    return applied ~= BASE[bar]
end

--- A bar's remembered native texture.
--
-- Read exactly once, while the bar has not yet been touched by us, and after
-- that the record does not change. GetStatusBarTexture returns a texture
-- object from the engine (on some builds a string straight away), so both
-- shapes are parsed; the path is obtained by the GetTexture method. It did not
-- work — false is remembered and we do not try again: a second attempt would
-- land on our own texture.
--
-- @param bar table|nil the bar
-- @return string|nil the path to the native texture
function UnitFrames.BaseTexture(bar)
    if type(bar) ~= "table" then return nil end

    local base = BASE[bar]
    if base ~= nil then
        if base == false then return nil end
        return base
    end

    local path
    if type(bar.GetStatusBarTexture) == "function" then
        local ok, texture = pcall(bar.GetStatusBarTexture, bar)
        if ok then
            if type(texture) == "string" then
                path = texture
            elseif type(texture) == "table"
                and type(texture.GetTexture) == "function" then
                local okPath, value = pcall(texture.GetTexture, texture)
                if okPath and type(value) == "string" then path = value end
            end
        end
    end
    if path == "" then path = nil end

    BASE[bar] = path or false
    return path
end

--- Which texture has to end up on the bar.
--
-- A pure function and the only place where this decision is made. There are
-- three cases. The native one was chosen — the remembered one is returned. A
-- name the library knows was chosen — its file is returned. The name is
-- unknown (the texture was brought by an addon that is no longer there, or the
-- record in SavedVariables was corrupted) — the native one again: substituting
-- somebody else's default texture for a vanished choice would mean silently
-- choosing on the player's behalf.
--
-- A nil means "there is nothing to change": the native one is not remembered,
-- that is, we have not touched the bar yet, and there is no point touching it
-- now.
--
-- @param value any the setting's value
-- @param media table|nil a LibSharedMedia-3.0 object or a compatible one
-- @param base string|nil the remembered native texture
-- @return string|nil the path to the texture's file
function UnitFrames.ResolveTexture(value, media, base)
    if value == NATIVE then return base end

    local path = ns.Skin.MediaTexture(media, value)
    if path then return path end

    return base
end

--- Bring a bar into line with the setting's chosen value.
-- The native texture is remembered before the replacement — and only because
-- of that does a return to "the native one" really restore the native one
-- rather than our previous choice.
-- @param bar table|nil the bar
-- @param value any the setting's value
-- @param media table|nil a LibSharedMedia-3.0 object or a compatible one
-- @return boolean whether it was applied
function UnitFrames.ApplyBar(bar, value, media)
    if type(bar) ~= "table" then return false end

    local base = UnitFrames.BaseTexture(bar)
    local path = UnitFrames.ResolveTexture(value, media, base)

    -- We have not touched the bar yet, and what is proposed to be laid on it
    -- is exactly what is already there. We do nothing at all: a fresh install
    -- is obliged to touch not one object of the game's rather than to "set the
    -- same thing".
    if APPLIED[bar] == nil and path == base then return false end

    return UnitFrames.SetBarTexture(bar, path)
end

--- A bar's remembered native colour.
--
-- Read exactly once, while the colour is still the game's own, and after that
-- the record does not change. It could not be read — false is remembered and a
-- second attempt is not made: it would land on our own colour.
--
-- @param bar table|nil the bar
-- @return table|nil { r, g, b, a }
function UnitFrames.BaseBarColor(bar)
    if type(bar) ~= "table" then return nil end

    local base = COLOR_BASE[bar]
    if base ~= nil then
        if base == false then return nil end
        return base
    end

    if type(bar.GetStatusBarColor) ~= "function" then
        COLOR_BASE[bar] = false
        return nil
    end

    local ok, r, g, b, a = pcall(bar.GetStatusBarColor, bar)
    if not ok or type(r) ~= "number" or type(g) ~= "number"
        or type(b) ~= "number" then
        COLOR_BASE[bar] = false
        return nil
    end

    base = { r, g, b, a }
    COLOR_BASE[bar] = base
    return base
end

--- Remember the colour that is on a bar right now, if we were not the ones
--- who put it there.
--
-- Called before every painting, that is, on every update of a unit: the game
-- paints the bar itself, our handler is hooked onto the game's own functions
-- and goes behind them, and at that minute what lies on the bar is exactly
-- what the game would show without us.
--
-- The comparison against our own last colour is not an optimisation but the
-- whole point. Without it the second pass would remember our own colour as
-- "the game's colour", the third the same again, and our choice would become
-- "the native one". With it somebody else's write is distinguishable from our
-- own.
--
-- A secret colour will not reach here: every channel passes through
-- ns.Skin.Numeric, and an unusable one leaves the record as it was — the
-- previous observed colour is better than none.
--
-- @param bar table|nil the bar
-- @return boolean whether a new colour was remembered
function UnitFrames.NoteGameColor(bar)
    if type(bar) ~= "table" then return false end
    if type(bar.GetStatusBarColor) ~= "function" then return false end

    local ok, cr, cg, cb = pcall(bar.GetStatusBarColor, bar)
    if not ok then return false end

    cr, cg, cb = ns.Skin.Numeric(cr), ns.Skin.Numeric(cg), ns.Skin.Numeric(cb)
    if cr == nil or cg == nil or cb == nil then return false end

    local wrote = COLOR_WROTE[bar]
    if type(wrote) == "table" then
        local same = math.abs(cr - (wrote[1] or -1)) < 0.002
            and math.abs(cg - (wrote[2] or -1)) < 0.002
            and math.abs(cb - (wrote[3] or -1)) < 0.002
        if same then return false end
    end

    COLOR_GAME[bar] = { cr, cg, cb }
    return true
end

--- What the subsystem remembers about this bar: the texture we assigned and
--- the remembered native colour.
--
-- Exposed for the same reason Darkness.Remembered is: the question "have you
-- touched this object" used to be put to a field on the object itself, the
-- field is gone (the memory moved to the side), and the question remains and
-- is now put to whoever knows the answer.
--
-- @param bar table|nil
-- @return string|nil the texture path we assigned
-- @return table|nil the remembered native colour
function UnitFrames.Remembered(bar)
    if type(bar) ~= "table" then return nil, nil end

    local applied = APPLIED[bar]
    if type(applied) ~= "string" then applied = nil end

    local base = COLOR_BASE[bar]
    if type(base) ~= "table" then base = nil end

    return applied, base
end

--- The observed colour of the game's, or nil.
--
-- The third answer to "what colour this bar is to be", and the best of the
-- three where the others keep quiet.
--
--   The game's tables (UnitFrames.GameColor) know the answer when they know
--     the key: a player's class, a creature's reaction. About the target the
--     client returns both as secret values, they are of no use as keys, and
--     there is no answer.
--   The remembered COLOR_BASE always knows the answer, but a frozen one: for
--     the target it is the colour of the first opponent of the session.
--   Here lies what the game last laid on this bar — a live answer, and there
--     are no secret values on this path at all: the colour is read back off
--     the bar itself as ordinary numbers.
--
-- @param bar table|nil the bar
-- @return number|nil, number|nil, number|nil
function UnitFrames.SeenColor(bar)
    if type(bar) ~= "table" then return nil end

    local seen = COLOR_GAME[bar]
    if type(seen) ~= "table" then return nil end

    return seen[1], seen[2], seen[3]
end

--- Bring a bar's colour into line with the chosen mode.
--
-- The colour and the brightness factor are folded into one SetStatusBarColor
-- call rather than into a black film over the bar. Today the factor is always
-- one (BAR_FACTOR): the dimming does not reach the bars. The multiplication
-- mechanism itself stays — it is covered by tests, and it is the way back if
-- the rule about the bars ever turns out to be a different one.
--
-- Our textures are a gradient from white to a colour, and the engine
-- multiplies them by the bar's colour. So the colour here is not decoration:
-- without it the gradient stays the colour the game laid down (health is green
-- for it), and our look does not come out at all.
--
-- The native colour under our texture. A bar with the native texture is
-- painted by the game, and "the game's colour" there means "do not touch": any
-- touch of ours would be an argument with the owner. Under our texture the
-- colour has no owner at all: the gradient runs from white, no colour is drawn
-- in the file, and the bar's vertex colour we reset by that very replacement.
-- Not painting it means showing the texture instead of the colour, exactly
-- what the author complained about.
--
-- So "the game's colour" here is not a refusal but work: the colour is taken
-- from the game's own tables (UnitFrames.GameColor) — by class, by attitude,
-- by the kind of power. The game does not know the colour (no target is
-- selected) — then we really do not touch it.
--
-- Why not the remembered COLOR_BASE: it freezes. For the target it is the
-- colour of the first opponent, and for a bar the game has not yet reached it
-- does not exist at all, so entering the game would give a white bar until the
-- first change of target. The remembered colour stays what it was — the way
-- back: take our texture off, and the bar returns to exactly what was there
-- before us.
--
-- @param bar table|nil the bar
-- @param mode string|nil the colour mode
-- @param info table|nil the data for computing the colour
-- @param factor number|nil the brightness factor; 1 means do not dim
-- @param kind string|nil the bar's kind: "health" | "power"
-- @return boolean whether it was applied
function UnitFrames.ApplyBarColor(bar, mode, info, factor, kind)
    if type(bar) ~= "table" then return false end
    if type(bar.SetStatusBarColor) ~= "function" then return false end

    factor = tonumber(factor) or 1

    -- Observe BEFORE painting our own: after that our colour will be on the
    -- bar, and it is what would be observed.
    UnitFrames.NoteGameColor(bar)

    local base = UnitFrames.BaseBarColor(bar)
    local r, g, b = UnitFrames.BarColor(mode, info)
    local alpha

    if r == nil and UnitFrames.Textured(bar) then
        r, g, b = UnitFrames.GameColor(kind, info)

        -- The game's tables kept quiet. That is what the target looks like:
        -- the client returns its class and its attitude as secret values,
        -- they are of no use as keys, and no colour can be found by them. And
        -- the colour is badly needed meanwhile — under our texture there is
        -- nowhere else to take it from: a gradient from white carries no
        -- colour, and untinted it shows the texture INSTEAD of the colour.
        -- That is exactly what the author saw: why is a creature's health the
        -- default green. The green was not a choice but a frozen COLOR_BASE —
        -- the colour that stood on the bar before us.
        --
        -- The observed colour answers where the tables keep quiet, and
        -- answers with a live value: the game paints the bar itself, our
        -- handler is hooked onto the game's own functions and goes behind
        -- them, and it was observed an instant before this line.
        if r == nil then r, g, b = UnitFrames.SeenColor(bar) end
    end

    if r == nil then
        -- The native look. We have not touched the bar yet and there is
        -- nothing to touch: neither a colour of our own nor any dimming.
        if COLOR_SET[bar] == nil and factor == 1 then return false end
        if not base then return false end
        r, g, b, alpha = base[1], base[2], base[3], base[4]
    end

    if factor ~= 1 then
        r, g, b = ns.Skin.Shade(r, g, b, factor)
    end

    local ok
    if type(alpha) == "number" then
        ok = pcall(bar.SetStatusBarColor, bar, r, g, b, alpha)
    else
        ok = pcall(bar.SetStatusBarColor, bar, r, g, b)
    end
    if not ok then return false end

    -- What was laid down is remembered: the next look is obliged to tell the
    -- game's colour from our own, or our choice becomes "the game's
    -- colour".
    COLOR_WROTE[bar] = { r, g, b }

    COLOR_SET[bar] = true
    return true
end

--- Whether the scale has to be changed.
-- The comparison against the current value is not decoration but part of the
-- decision about deferring: without it every change of target in combat would
-- put work that changes nothing into the queue, and leaving combat would jerk
-- the frames for nothing.
-- @param frame table
-- @param scale number
-- @return boolean
local function needsScale(frame, scale)
    if type(frame) ~= "table" or type(frame.SetScale) ~= "function" then
        return false
    end
    if type(frame.GetScale) ~= "function" then return true end

    local ok, current = pcall(frame.GetScale, frame)
    if not ok or type(current) ~= "number" then return true end
    return math.abs(current - scale) > 0.001
end

--- Whether combat is under way.
-- Outside the game the function does not exist — then there is no combat and
-- nothing to defer.
-- @return boolean
local function inCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, locked = pcall(InCombatLockdown)
    return ok and locked and true or false
end

--- A unit's class and reaction as the client sees them.
--
-- The class is returned for players only: for creatures UnitClass returns
-- whatever it happens to, and a "colour by class" on a boar would look
-- random.
--
-- The kind of power is asked of the same function of the game's that the
-- engine itself uses: UnitPowerType returns the numeric type and a string
-- token ("MANA", "RAGE"). Both keys are usable with the game's colour table,
-- and both are passed on.
--
-- All four answers pass through ns.Skin.Textual and ns.Skin.Numeric, and that
-- is not over-insurance. About a unit other than our own — the target, the
-- focus, a party member — the client returns these values as secret ones: a
-- secret string's type is "string", a secret number's is "number", and a type
-- check lets them through as usable. They turn out not to be usable at exactly
-- the point they were taken for: RAID_CLASS_COLORS[a secret string] is nil,
-- because the key is not the right one, and the colour quietly fails to be
-- found. Further down the chain the target's bar was left with no colour at
-- all and showed our texture as it is — a gradient from white — and that is
-- precisely what the author saw on the target while his own bar looked right:
-- about our own unit the client answers in the open.
--
-- Hence the rule: an unusable value is obliged to become nil, that is,
-- "unknown", rather than to pretend to be known.
--
-- @param unit string|nil
-- @return string|nil the class
-- @return number|nil the reaction
-- @return string|nil the power token
-- @return number|nil the numeric power type
local function unitInfo(unit)
    if type(unit) ~= "string" or unit == "" then return nil, nil, nil, nil end

    local class, reaction, power, powerType

    -- "Is this a player" arrives from the game as a boolean, and booleans
    -- about protected units can be secret as well. Their truth must not be
    -- tested inside an "and": Lua tests it without a comparison and lets
    -- anything through, and then the class would be looked up on a boar.
    local isPlayer = true
    if type(UnitIsPlayer) == "function" then
        local ok, value = pcall(UnitIsPlayer, unit)
        isPlayer = ok and ns.Skin.Truth(value)
    end

    if isPlayer and type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, unit)
        if ok then class = ns.Skin.Textual(token) end
    end

    if type(UnitReaction) == "function" then
        local ok, value = pcall(UnitReaction, "player", unit)
        if ok then reaction = ns.Skin.Numeric(value) end
    end

    if type(UnitPowerType) == "function" then
        local ok, index, token = pcall(UnitPowerType, unit)
        if ok then
            powerType = ns.Skin.Numeric(index)
            power = ns.Skin.Textual(token)
        end
    end

    return class, reaction, power, powerType,
        ns.Compat.UnitTapDenied(unit)
end

--============================================================================
-- Settings of each frame's own
--============================================================================

-- === Why one set of settings for every frame is not enough ===
--
-- The player's frame and the target's frame show different things and are
-- looked at differently. One's own is watched out of the corner of the eye and
-- one wants to tell the colour of the power apart; the target is watched in
-- combat and one wants to tell the class apart. One setting for both means the
-- player chooses not what he needs but what gets in the way least — and both
-- halves of the choice stay wrong.
--
-- === The arrangement: two levels, as with the fonts ===
--
-- There are two levels, and they are the same ones as in the fonts section: a
-- common choice and one frame's choice over it. There is no third inheritance
-- rule in the addon and there will not be: the player is not obliged to tell
-- two different rules of "what is in effect" apart.
--
-- Empty at a frame's level means "as the common one" and goes on following the
-- common one rather than copying it at the moment of editing. A copy would
-- diverge from the common one at its very first edit — silently.

-- The frames' keys. A key's value is not a frame's name but the name of the
-- unit the frame shows: the frames' names live in the compatibility layer
-- (Core/Compat.lua), and a second list of them here would diverge from it at
-- the very first build of the client where a frame is named differently. The
-- unit, in turn, is asked of the frame itself.
local UNITS = {
    { key = "player",       label = "Player"           },
    { key = "target",       label = "Target"           },
    { key = "targettarget", label = "Target of Target" },
    { key = "focus",        label = "Focus"            },
    { key = "pet",          label = "Pet"              },
    { key = "party",        label = "Party"            },
}
UnitFrames.UNITS = UNITS

local UNIT_KEY = {}
for i = 1, #UNITS do UNIT_KEY[UNITS[i].key] = UNITS[i] end

--- The settings key for a unit's name.
--
-- There are four party members and one setting between them: "party1" and
-- "party3" are two places in one row rather than two different frames in
-- meaning. A setting per member would be four copies of one choice, and they
-- would begin to diverge on the very first evening.
--
-- An unfamiliar unit answers nil — "it has no settings of its own", that is,
-- the common level is in effect. That is an ordinary answer: the client shows
-- units we never listed, and there is nothing to deny them styling for.
--
-- @param unit any
-- @return string|nil
function UnitFrames.UnitKey(unit)
    local name = ns.Skin.Textual(unit)
    if not name then return nil end

    name = string.lower(name)
    if UNIT_KEY[name] then return name end

    -- "party1".."party4" and "partypet1" — one key for the whole row.
    if string.match(name, "^party%d+$") then return "party" end

    return nil
end

--- A setting's value for this frame.
--
-- A pure function and the only place where it is decided whose word carries.
-- There is no second such fork in the subsystem: having diverged, they would
-- give a frame its colour from one level and its texture from another.
--
-- @param settings table|nil the subsystem's settings
-- @param key string|nil the frame's key; nil asks about the common level
-- @param field string the field's name
-- @return any the value
-- @return boolean whether it is set at the frame's level
function UnitFrames.Own(settings, key, field)
    if type(settings) ~= "table" or type(field) ~= "string" then
        return nil, false
    end

    if key ~= nil then
        local units = settings.units
        local entry = type(units) == "table" and units[key] or nil
        if type(entry) == "table" and entry[field] ~= nil then
            return entry[field], true
        end
    end

    return settings[field], false
end

--- One frame's settings gathered into a single table.
--
-- It exists because the application asks for several fields of one frame at
-- once, and asking for them one at a time would mean walking two levels per
-- field — in a raid that is noticeable.
--
-- @param settings table|nil
-- @param key string|nil
-- @param fields table array of field names
-- @return table field -> value
function UnitFrames.Effective(settings, key, fields)
    local out = {}
    if type(fields) ~= "table" then return out end

    for i = 1, #fields do
        out[fields[i]] = UnitFrames.Own(settings, key, fields[i])
    end
    return out
end

-- The fields that can be a frame's own. The group sizes are deliberately not
-- among them: they are about the grid as a whole rather than about one frame
-- in it.
local PER_UNIT_FIELDS = {
    "health", "healthColor", "healthFixed",
    "power", "powerColor", "powerFixed",
    "nameColor", "nameFixed",
    "scale",
}
UnitFrames.PER_UNIT_FIELDS = PER_UNIT_FIELDS

--- The table of class colours the client is using right now.
--
-- CUSTOM_CLASS_COLORS is not an invention of ours and not a name out of the
-- future: that is what the shared replacement of class colours has been called
-- for many years, the one installed by players who cannot tell all eight
-- shades apart. An addon that fails to notice it paints a bar one blue and the
-- name beside it another, and the addon is the one that looks at fault.
--
-- We have no copy of the class colours of our own and will not have one: both
-- "by class" on a bar and "by class" on a name ask the same table.
--
-- @return table|nil
local function classColors()
    -- A door of the core's rather than a reading of globals of our own: the
    -- same colours are asked for by the dimming's "class colour" mode, and
    -- there must be no second copy of that knowledge
    -- (ns.Skin.GameClassColors).
    return ns.Skin.GameClassColors()
end
UnitFrames.ClassColors = classColors

--- The unit a frame shows.
-- Asked of the frame itself rather than taken from a "frame name -> unit"
-- table: such a table would be a second list of names beside ns.Compat and
-- would diverge from it at the very first edit.
-- @param frame table
-- @return string|nil
local function frameUnit(frame)
    if type(frame) ~= "table" then return nil end

    if type(frame.unit) == "string" and frame.unit ~= "" then
        return frame.unit
    end

    if type(frame.GetAttribute) == "function" then
        local ok, unit = pcall(frame.GetAttribute, frame, "unit")
        if ok and type(unit) == "string" and unit ~= "" then return unit end
    end

    return nil
end

-- The default settings. A fresh install replaces nothing: the bars stay
-- native, the name's colour native, the scale one. The rule is common to the
-- whole addon — what the game draws itself stands as the default — and it
-- rests on more than politeness: when the look seems wrong, the first question
-- is "is this the addon or the game", and the only way to answer it is a return
-- to the native look. That is why the native value stays selectable rather than
-- merely initial.
--
-- Our own look has not gone anywhere: it is set by a single action in the
-- "General" section (ns.Recommended, Core/Defaults.lua), that is, at the
-- player's request.
local textR, textG, textB = ns.Skin.Get("text")

UnitFrames.defaults = {
    health      = NATIVE,
    healthColor = NATIVE,
    healthFixed = { r = textR, g = textG, b = textB },
    power       = NATIVE,
    powerColor  = NATIVE,
    powerFixed  = { r = textR, g = textG, b = textB },
    nameColor   = NATIVE,
    nameFixed   = { r = textR, g = textG, b = textB },
    scale       = 1,

    -- The settings of individual frames. Empty on a fresh install: until the
    -- player has overridden anything, every frame follows the common choice
    -- above and goes on following its edits.
    units       = {},

    -- The party and raid frames. The switch stands off, and while it is off we
    -- force not one number on the game: a party member's size stays what the
    -- game laid down itself. The numbers beside it are not "the game's native
    -- sizes" but the sliders' initial positions: the real native numbers are
    -- read out of the client's layout table before our first edit
    -- (UnitFrames.BaseSetup) and are restored there when the switch goes out.
    groupSize   = false,
    groupWidth  = 72,
    groupHeight = 36,
    groupScale  = 1,
}

--- The subsystem's settings out of the profile.
-- @return table|nil
local function Settings()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    if not profile then return nil end
    return profile[UnitFrames.name]
end

--- The texture library. Its absence is an ordinary nil answer rather than an
--- error.
-- @return table|nil
local function Media()
    if not LibStub then return nil end
    local ok, media = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok and type(media) == "table" then return media end
    return nil
end

--- A font string's remembered native colour.
-- Read once, before our first repainting, and after that it does not change.
-- It could not be read — false is remembered and a second attempt is not made:
-- it would land on our own colour.
-- @param label table|nil the font string
-- @return table|nil { r, g, b, a }
function UnitFrames.BaseColor(label)
    if type(label) ~= "table" then return nil end

    local base = NAME_BASE[label]
    if base ~= nil then
        if base == false then return nil end
        return base
    end

    if type(label.GetTextColor) ~= "function" then
        NAME_BASE[label] = false
        return nil
    end

    local ok, r, g, b, a = pcall(label.GetTextColor, label)
    if not ok or type(r) ~= "number" or type(g) ~= "number"
        or type(b) ~= "number" then
        NAME_BASE[label] = false
        return nil
    end

    base = { r, g, b, a }
    NAME_BASE[label] = base
    return base
end

--- Paint a unit's name on a frame.
-- @param frame table
-- @param settings table the subsystem's settings
-- @return boolean whether it was applied
function UnitFrames.ApplyName(frame, settings)
    local label = pick(frame, NAME_FIELDS, "SetTextColor")
    if not label then return false end

    -- The native colour is remembered in every mode and before any
    -- repainting: otherwise the path "native -> by class -> native" would
    -- restore something other than the native one.
    local base = UnitFrames.BaseColor(label)

    local unit = frameUnit(frame)
    local own = UnitFrames.Effective(settings, UnitFrames.UnitKey(unit),
        UnitFrames.PER_UNIT_FIELDS)

    if own.nameColor == NATIVE then
        -- The native colour is unknown — we keep quiet. Setting white
        -- instead of a native colour that could not be read would be worse
        -- than doing nothing at all.
        if not base then return false end
        return (pcall(label.SetTextColor, label, base[1], base[2], base[3],
            type(base[4]) == "number" and base[4] or 1))
    end

    local class, reaction, _, _, tapDenied = unitInfo(unit)
    local r, g, b = UnitFrames.NameColor(own.nameColor, {
        class          = class,
        classColors    = classColors(),
        reaction       = reaction,
        reactionColors = FACTION_BAR_COLORS,
        fixed          = own.nameFixed,
        tapDenied      = tapDenied,
    })

    return (pcall(label.SetTextColor, label, r, g, b))
end

-- The brightness factor for the bars is one, that is, do not dim.
--
-- It used to be asked of the dimming subsystem and multiplied into the chosen
-- colour. The rule changed, and it changed not out of taste: the dimming is
-- about the interface's framing, while the health bar is about the character's
-- state. A bar's fill shows a magnitude; dimming it is the same as dimming a
-- gauge's needle, and it is worst of all exactly where that needle is read
-- fastest. That is precisely what the dimming addons considered exemplary do:
-- the framing darkens, the bars stay green and blue.
--
-- The one is left named rather than written into the calls: ApplyBarColor can
-- do the multiplier and can do it provably, and taking that ability away from
-- it would mean closing the way back.
local BAR_FACTOR = 1

--- Paint one frame's bars.
-- The health colour is computed by the same rules as the name's colour, the
-- power colour by the kind of power out of the game's table. The colour tables
-- are taken from the client (PowerBarColor, ManaBarColor on older builds) and
-- passed into a pure function as arguments: the addon has no numbers of its own
-- here and must not have any.
-- @param frame table the frame
-- @param settings table the subsystem's settings
-- @param factor number the brightness factor
function UnitFrames.ApplyFrameColors(frame, settings, factor)
    if type(frame) ~= "table" or type(settings) ~= "table" then return end

    local unit = frameUnit(frame)
    local class, reaction, power, powerType, tapDenied = unitInfo(unit)

    -- Whose settings are in effect on this frame: its own if the player set
    -- them, and the common ones until he has. Decided once per frame rather
    -- than once per field.
    local own = UnitFrames.Effective(settings, UnitFrames.UnitKey(unit),
        UnitFrames.PER_UNIT_FIELDS)

    UnitFrames.ApplyBarColor(
        pick(frame, HEALTH_FIELDS, "SetStatusBarColor"),
        own.healthColor,
        {
            class          = class,
            classColors    = classColors(),
            reaction       = reaction,
            reactionColors = FACTION_BAR_COLORS,
            fixed          = own.healthFixed,
            -- Whose kill this is. The power bar knows no such question: grey
            -- is what the game paints health with, and health alone.
            tapDenied      = tapDenied,
        },
        factor, "health")

    UnitFrames.ApplyBarColor(
        pick(frame, POWER_FIELDS, "SetStatusBarColor"),
        own.powerColor,
        {
            power         = power,
            powerType     = powerType,
            powerColors   = PowerBarColor,
            powerFallback = ManaBarColor,
            fixed         = own.powerFixed,
        },
        factor, "power")
end

--- Lay the chosen textures onto one frame's bars.
--
-- Split out of ApplySettings not for beauty's sake: the same two bars exist on
-- a nameplate too (Modules/NamePlates.lua), and the fields the engine keeps
-- them in are listed here. A second list of field names in another subsystem
-- would diverge from this one at the very first build of the client where a
-- field is named differently.
--
-- A nameplate has no power bar — then pick returns nil and ApplyBar answers
-- false. That is an ordinary answer rather than a refusal.
--
-- @param frame table the frame
-- @param settings table the subsystem's settings
-- @param media table|nil a LibSharedMedia-3.0 object or a compatible one
function UnitFrames.ApplyFrameTextures(frame, settings, media)
    if type(frame) ~= "table" or type(settings) ~= "table" then return end

    local own = UnitFrames.Effective(settings, UnitFrames.UnitKey(frameUnit(frame)),
        UnitFrames.PER_UNIT_FIELDS)

    UnitFrames.ApplyBar(pick(frame, HEALTH_FIELDS, "SetStatusBarTexture"),
        own.health, media)
    UnitFrames.ApplyBar(pick(frame, POWER_FIELDS, "SetStatusBarTexture"),
        own.power, media)
end

--- Repaint every frame's bars.
--
-- A path separate from ApplySettings is needed not for convenience: the game
-- repaints the bars itself on every update of a unit, and after its call our
-- colour would be gone. The subscription to its functions (OnEnable) leads
-- here rather than into the full application: there are the scale, the textures
-- and the queue there, while after a repainting only the colour is needed.
function UnitFrames:ApplyColors()
    local settings = Settings()
    if not settings then return end

    local factor = BAR_FACTOR
    local names = ns.Compat.Resolve("unitframe")

    for i = 1, #names do
        UnitFrames.ApplyFrameColors(_G[names[i]], settings, factor)
    end
end

-- Protection against re-entry. Our colour is assigned inside a handler of a
-- function of the game's, and another addon hooked onto the same function can
-- call it again. The flag breaks the chain on its very first turn.
local repainting = false

--- Repaint the bars after the game has repainted them.
-- @return boolean whether it was carried out
function UnitFrames.Repaint()
    if repainting then return false end

    repainting = true
    local ok = pcall(function() UnitFrames:ApplyColors() end)
    repainting = false

    return ok
end

--- Apply the settings.
--
-- The only path of application: entering the game, changing the profile,
-- editing a setting and the events of a unit changing all lead here.
--
-- The frames are taken from the compatibility layer: it returns only the ones
-- that exist in this client. What is not there is simply not there here, and
-- there are no checks of the client's version in the subsystem.
function UnitFrames:ApplySettings()
    local settings = Settings()
    if not settings then return end

    local media = Media()
    local factor = BAR_FACTOR

    --- This frame's scale, brought within the slider's bounds.
    -- A frame's own: the target's frame is kept larger than one's own more
    -- often than the other way round, and one scale for both would mean a
    -- choice in favour of neither.
    local function scaleFor(frame)
        local value = UnitFrames.Own(settings,
            UnitFrames.UnitKey(frameUnit(frame)), "scale")
        local scale = tonumber(value) or 1
        if scale < 0.5 then scale = 0.5 end
        if scale > 2   then scale = 2   end
        return scale
    end

    local combat = inCombat()
    local names = ns.Compat.Resolve("unitframe")

    for i = 1, #names do
        local name  = names[i]
        local frame = _G[name]

        if type(frame) == "table" then
            -- The bars' look and the name's colour are not protected by the
            -- engine: they go on at once, in the middle of combat
            -- included.
            UnitFrames.ApplyFrameTextures(frame, settings, media)
            UnitFrames.ApplyFrameColors(frame, settings, factor)
            UnitFrames.ApplyName(frame, settings)

            -- The scale is a protected operation: in combat the engine
            -- forbids it. It alone is deferred, and only when the value really
            -- does change.
            local scale = scaleFor(frame)
            if needsScale(frame, scale) then
                if combat then
                    UnitFrames.Enqueue(UnitFrames.queue, "scale:" .. name,
                        function()
                            -- The frame is looked up afresh: between the
                            -- queueing and the exit from combat the profile
                            -- can change, and a reference to the object would
                            -- outlive another addon's reload of the
                            -- interface.
                            local later = _G[name]
                            if type(later) == "table"
                                and type(later.SetScale) == "function" then
                                later:SetScale(scale)
                            end
                        end)
                else
                    pcall(frame.SetScale, frame, scale)
                end
            end
        end
    end

    -- The party and raid frames go a path of their own: they have their own
    -- table of numbers, their own container and their own owner of the
    -- layout.
    UnitFrames:ApplyGroupFrames()
end

-- ============================================================================
-- The size of the party and raid frames
-- ============================================================================
--
-- The scale and the size are not one and the same, and the difference is
-- visible to the eye. The scale multiplies everything at once: the bar, the
-- portrait, the drawn framing and the text. The size changes the box and leaves
-- the text as it was. A player who asks to "make the frames bigger" may mean
-- either.
--
-- So what is offered is not an identical pair of sliders in every section but
-- whatever really works on these particular frames.
--
-- The native unit frames of the player, the target and the pet have no width
-- and height and cannot have them. Their look is assembled out of drawn
-- framing, a portrait and bars nailed to the frame by points with pixel
-- offsets: SetWidth changes the frame's rectangle — that is, the area the
-- cursor hovers over — and moves not one texture. A "width" slider there would
-- show a number that changes nothing on the screen but the click zone. A
-- setting that lies is worse than a missing one, so these frames keep the scale
-- alone.
--
-- With the compact party and raid frames it is the other way round. The game
-- assembles them out of two numbers — a party member's width and height — and
-- everything drawn on them is laid out from those numbers. So here the size
-- really works, and here it is offered — together with the scale and with the
-- difference between them written out plainly in the description.
--
-- They combine by multiplication, and that is written in the description too:
-- a frame a hundred and twenty wide at a scale of one and a half takes up a
-- hundred and eighty on the screen.
--
-- Who owns the layout. Not us. A group's composition changes constantly, and
-- after every change the game lays the compact frames out afresh, taking a
-- party member's size from its own table (the "raidframe-setup" group in
-- Core/Compat.lua). A size laid onto the frames alone would be gone after the
-- very first change of composition — and that is exactly the kind of setting
-- that lies. So the number is first put into the table the game will read it
-- from, and only then onto the frames themselves, so that it takes effect at
-- once rather than by the next re-layout. On top of that the subsystem stands
-- behind the layout functions through hooksecurefunc and repeats its own work
-- on the event of the group's composition changing.
--
-- What this path does not do: it does not replace the raid frames' manager with
-- one of ours. Replacing it would mean writing our own party frames entirely —
-- that is different work and a different size of it. Should the table of
-- numbers be absent in some build of the client, the subsystem will silently do
-- nothing: the names there are candidates, and existence is the filter.

-- The records of the remembered native size. The meaning is the same as BASE's
-- and COLOR_BASE's: read once, before our first edit, and after that it does
-- not change. Without it switching the setting off would restore not the native
-- size but our previous one.
local GROUP_BASE = ns.Skin.Memory()

-- The marker "we have already changed this frame's size". Needed for exactly
-- the rule "a fresh install touches not one object of the game's".
local GROUP_SET = ns.Skin.Memory()

-- The same again for the container's scale. Records of their own, because a
-- scale of one has a special meaning here: the scale of the raid frames'
-- container is set by the game itself out of its own set of settings, and it is
-- not obliged to be one. So a one on our side means not "set it to one" but
-- "leave it to the game": an untouched container stays untouched, and a touched
-- one returns to the remembered value rather than to our one.
local GROUP_SCALE_BASE = ns.Skin.Memory()
local GROUP_SCALE_SET = ns.Skin.Memory()

-- The module that draws the party frames in the game's stead. The name is
-- already known to the core: it is listed in ns.ROOT_MODULES
-- (Config/Options.lua).
local GROUP_MODULE = "umbraraid"

-- The bounds of the size sliders. The numbers are not the game's native sizes
-- but the limits of the reasonable: a frame narrower than forty pixels does not
-- fit a name, and one wider than a hundred and sixty does not fit four in a
-- row.
local GROUP_WIDTH_MIN,  GROUP_WIDTH_MAX  = 40, 160
local GROUP_HEIGHT_MIN, GROUP_HEIGHT_MAX = 16, 80

-- The scale's bounds are the same as the other frames': one rule per
-- addon.
local SCALE_MIN, SCALE_MAX = 0.5, 2

--- A number within bounds, or nil.
-- A pure function. A nil means "the value is no good": rubbish in the profile
-- counts neither as a zero nor as the minimum but as the absence of a choice,
-- and then the size stays what the game assigned.
-- @param value any
-- @param min number
-- @param max number
-- @return number|nil
function UnitFrames.ClampSize(value, min, max)
    local number = tonumber(value)
    if number == nil then return nil end
    if number < min then return min end
    if number > max then return max end
    return number
end

--- The width and height of a party member as chosen by the player.
--
-- Both nil mean "the size is left to the game" — and that is not a refusal but
-- the initial state: while the switch is off we have no numbers at all, and
-- what goes into the game's table is what lay there before us.
--
-- @param settings table|nil the subsystem's settings
-- @return number|nil the width
-- @return number|nil the height
function UnitFrames.GroupNumbers(settings)
    if type(settings) ~= "table" then return nil, nil end
    if not settings.groupSize then return nil, nil end

    return UnitFrames.ClampSize(settings.groupWidth,
            GROUP_WIDTH_MIN, GROUP_WIDTH_MAX),
        UnitFrames.ClampSize(settings.groupHeight,
            GROUP_HEIGHT_MIN, GROUP_HEIGHT_MAX)
end

--- The remembered native numbers out of the game's layout table.
--
-- Read once, while the table has not yet been touched by us. No numbers means
-- no remembering either: a table built to somebody else's design does not
-- belong to us, and we will not write fields of our own into it on a guess.
--
-- @param options table|nil the game's layout table
-- @return table|nil { width, height }
function UnitFrames.BaseSetup(options)
    if type(options) ~= "table" then return nil end

    local base = GROUP_BASE[options]
    if base ~= nil then
        if base == false then return nil end
        return base
    end

    if type(options.width) ~= "number" or type(options.height) ~= "number" then
        GROUP_BASE[options] = false
        return nil
    end

    base = { width = options.width, height = options.height }
    GROUP_BASE[options] = base
    return base
end

--- Put a size into the table the game assembles its layout from.
--
-- This is the main step rather than an auxiliary one: the frames are laid out
-- by the game, and the number is what it will take from here.
--
-- === Why the write happens only on a change ===
--
-- Above this function it used to say: "the operation is not a protected one —
-- an ordinary write into a table". The first half is true, the second is not,
-- and it cost dearly.
--
-- The table here belongs to the GAME
-- (DefaultCompactUnitFrameSetupOptions), and a write into somebody else's
-- table taints it. Every party frame assembled out of these numbers is tainted
-- from birth, and the game's code runs tainted on it. The client's log calls
-- that by our name:
--
--   CompactUnitFrame.lua:1206: attempt to compare local 'maxHealth'
--   (a secret number value, while execution tainted by 'Darken')
--
-- And we used to write into it ALWAYS — even when the player never set a party
-- size at all. With the setting switched off two nils arrive here, the native
-- value is taken out of memory and put back into the same table: a write
-- without a single change, that is, a pure taint. And all of that is called on
-- every change of the group's composition and every re-layout of the raid
-- list.
--
-- Now we compare and write only what differs. A fresh install writes nothing at
-- all. A player who did set a size will get the taint — otherwise his numbers
-- would never reach the game — but he will get it once rather than forty times
-- a fight.
--
-- A nil in the width or the height means "restore the native one": exactly what
-- was read before our first edit is restored.
--
-- @param options table|nil the game's layout table
-- @param width number|nil
-- @param height number|nil
-- @return number|nil the width that ended up in the table
-- @return number|nil the height
-- @return boolean whether we wrote into the table just now
function UnitFrames.ApplySetup(options, width, height)
    local base = UnitFrames.BaseSetup(options)
    if not base then return nil end

    local w = width  or base.width
    local h = height or base.height

    local wrote = false
    if options.width ~= w then
        options.width = w
        wrote = true
    end
    if options.height ~= h then
        options.height = h
        wrote = true
    end

    return w, h, wrote
end

--- A frame's remembered native size.
-- @param frame table|nil
-- @return table|nil { width, height }
function UnitFrames.BaseFrameSize(frame)
    if type(frame) ~= "table" then return nil end

    local base = GROUP_BASE[frame]
    if base ~= nil then
        if base == false then return nil end
        return base
    end

    if type(frame.GetWidth) ~= "function"
        or type(frame.GetHeight) ~= "function" then
        GROUP_BASE[frame] = false
        return nil
    end

    local okW, w = pcall(frame.GetWidth, frame)
    local okH, h = pcall(frame.GetHeight, frame)
    if not okW or not okH or type(w) ~= "number" or type(h) ~= "number"
        or w <= 0 or h <= 0 then
        GROUP_BASE[frame] = false
        return nil
    end

    base = { width = w, height = h }
    GROUP_BASE[frame] = base
    return base
end

--- Whether the size has to be changed.
-- The comparison against the current value is part of the decision about
-- deferring, exactly as with the scale: without it every change of the group's
-- composition in combat would put work that changes nothing into the queue.
-- @param frame table
-- @param width number
-- @param height number
-- @return boolean
function UnitFrames.NeedsSize(frame, width, height)
    if type(frame) ~= "table" then return false end
    if type(frame.SetSize) ~= "function"
        and type(frame.SetWidth) ~= "function" then
        return false
    end
    if type(frame.GetWidth) ~= "function"
        or type(frame.GetHeight) ~= "function" then
        return true
    end

    local okW, w = pcall(frame.GetWidth, frame)
    local okH, h = pcall(frame.GetHeight, frame)
    if not okW or not okH or type(w) ~= "number" or type(h) ~= "number" then
        return true
    end

    return math.abs(w - width) > 0.5 or math.abs(h - height) > 0.5
end

--- Assign a size to a frame.
-- @param frame table
-- @param width number
-- @param height number
-- @return boolean
local function setSize(frame, width, height)
    if type(frame.SetSize) == "function" then
        return (pcall(frame.SetSize, frame, width, height))
    end
    if type(frame.SetWidth) ~= "function" then return false end

    local ok = pcall(frame.SetWidth, frame, width)
    if type(frame.SetHeight) == "function" then
        ok = pcall(frame.SetHeight, frame, height) and ok
    end
    return ok and true or false
end

--- Carry out a protected operation on a frame of the game's.
--
-- The core's rule, written down once in Core/Combat.lua: what gets deferred is
-- the pair "the operation is protected AND the object answers IsProtected".
-- Nobody forbids touching an ordinary frame in combat, and deferring would make
-- the addon sluggish for no reason — and compact frames are created and torn
-- down precisely in combat, when a group's composition changes most often.
--
-- @param frame table the frame
-- @param key string the queue's key
-- @param action function the action
-- @return boolean whether it was carried out at once
local function secure(frame, key, action)
    if inCombat() and ns.Combat.Protected(frame) then
        UnitFrames.Enqueue(UnitFrames.queue, key, action)
        return false
    end

    action()
    return true
end

--- Bring one compact frame's size into line.
--
-- A nil in the width or the height means "restore the native one". A frame we
-- have not touched yet stays untouched in the process: a fresh install changes
-- nothing.
--
-- @param name string the frame's name
-- @param frame table the frame
-- @param width number|nil
-- @param height number|nil
-- @return boolean whether we took the work on (deferred included)
function UnitFrames.ApplyGroupFrame(name, frame, width, height)
    if type(name) ~= "string" or name == "" then return false end
    if type(frame) ~= "table" then return false end

    local base = UnitFrames.BaseFrameSize(frame)
    local w = width  or (base and base.width)
    local h = height or (base and base.height)
    if type(w) ~= "number" or type(h) ~= "number" then return false end

    if GROUP_SET[frame] == nil and width == nil then return false end
    if not UnitFrames.NeedsSize(frame, w, h) then return false end

    GROUP_SET[frame] = true

    secure(frame, "size:" .. name, function()
        -- The frame is looked up afresh for the same reason as with the
        -- scale: between the queueing and the exit from combat the group's
        -- composition could have changed.
        local later = _G[name]
        if type(later) == "table" then setSize(later, w, h) end
    end)

    return true
end

--- Whether somebody other than us draws the party frames.
--
-- === Why this question is asked at all ===
--
-- The "Party and Raid Frames" tab configures THE GAME'S COMPACT FRAMES: their
-- size, their scale. It is needed by whoever has no raid frames module or has
-- it switched off.
--
-- When the module is on, there are no frames of the game's on the screen at
-- all — it builds its own. The tab then configures emptiness, and the author
-- asked exactly that: why are the party frames here when there is Raid Frames,
-- which is supposed to answer for the party too.
--
-- The answer: there is no reason. The tab goes away, and the application goes
-- with it — and with that the write into the game's layout table, the write
-- that taints that table.
--
-- Why not handle:Replaces, the way the module takes the nameplates over. A
-- takeover removes THE WHOLE SUBSYSTEM: its section out of the tree, its
-- application, its handlers. Here one tab out of two is taken over, while the
-- other — "Individual Frames" — stays with the core and works as before.
-- Creating a second meaning for the word "take over" for that purpose would be
-- worse than a direct question.
--
-- The module's name is known to the core without this anyway: it is listed in
-- ns.ROOT_MODULES (Config/Options.lua) — the modules whose place is at the root
-- of the column.
--
-- @return boolean
function UnitFrames.GroupFramesTaken()
    if type(ns.Registry) ~= "table" then return false end

    local module = ns.Registry:Get(GROUP_MODULE)
    if type(module) ~= "table" then return false end
    if not ns.Registry:IsEnabled(module) then return false end

    local profile = ns.Addon and ns.Addon.db and ns.Addon.db.profile
    local own = type(profile) == "table" and profile[GROUP_MODULE] or nil

    return type(own) == "table" and own.enabled == true
end

--- Bring the party and raid frames into line with the settings.
--
-- A path separate from ApplySettings is needed not for convenience: the
-- subscription to the game's layout functions leads here, and calling the full
-- application from there would mean repainting every unit frame on every
-- re-layout of the raid list.
--
-- === While the edit mode is open the subsystem does nothing ===
--
-- On the clients that have it, the position of the panels and the unit frames
-- belongs to the edit mode: it moves them and it saves them. An addon that
-- moves the same frames at the same minute does work "only available to the
-- Blizzard UI" and gets blocked:
--
--   Darken has been blocked from an action only available to the
--   Blizzard UI.
--
-- The block does not merely cancel our action — it taints the execution, and
-- further along the edit mode's work the frames it reassembles turn out to be
-- tainted. In the client's log that is visible from end to end: leaving the
-- edit mode, ResetPartyFrames, CompactUnitFrame_SetUpFrame — and "tainted by
-- Darken" on a comparison of health.
--
-- The refusal here is no loss: closing the edit mode lays the frames out
-- afresh, and a re-layout leads back here (the subscription to the layout
-- functions), so the settings will go onto them right after it closes.
function UnitFrames:ApplyGroupFrames()
    -- The party frames are drawn by the module — there are none of the game's
    -- on the screen, and there is nothing in them to configure. A silent
    -- refusal is right here: this is not a failure but a different owner.
    if UnitFrames.GroupFramesTaken() then return end

    if ns.Combat.EditModeOpen() then return end

    local settings = Settings()
    if not settings then return end

    local width, height = UnitFrames.GroupNumbers(settings)

    -- First the numbers the game will assemble its layout from itself. Should
    -- the table be absent in this client, the size will stay on the frames
    -- alone — and that is an honest half of the work rather than a quiet
    -- refusal: the frames will take it at once, the next re-layout will restore
    -- the native one, and a repeated application will arrive with the event of
    -- the group's composition changing.
    local setups = ns.Compat.Resolve("raidframe-setup")
    for i = 1, #setups do
        local w, h = UnitFrames.ApplySetup(_G[setups[i]], width, height)
        -- The return to the native look: the numbers for the frames
        -- themselves are taken from the same table, so that "switch off"
        -- restores exactly what was there before us.
        if w and width == nil then width, height = w, h end
    end

    local members = ns.Compat.Resolve("raidframe-member")
    for i = 1, #members do
        local name = members[i]
        UnitFrames.ApplyGroupFrame(name, _G[name], width, height)
    end

    -- The scale goes onto the container rather than onto each frame: it is
    -- inherited by the children, and forty separate calls would give the same
    -- look at the price of forty protected operations.
    local scale = UnitFrames.ClampSize(settings.groupScale,
        SCALE_MIN, SCALE_MAX) or 1

    local holders = ns.Compat.Resolve("raidframe-container")
    for i = 1, #holders do
        local name  = holders[i]
        local frame = _G[name]
        if type(frame) == "table" then
            local target = scale
            if scale == 1 then
                -- A one means "leave it to the game". A container we have
                -- not touched yet stays untouched; a touched one returns to
                -- the game's remembered scale rather than to our one.
                if GROUP_SCALE_SET[frame] == nil then
                    target = nil
                else
                    target = GROUP_SCALE_BASE[frame]
                end
            elseif GROUP_SCALE_BASE[frame] == nil
                and type(frame.GetScale) == "function" then
                local ok, current = pcall(frame.GetScale, frame)
                GROUP_SCALE_BASE[frame] =
                    (ok and type(current) == "number") and current or 1
            end

            if type(target) == "number" and needsScale(frame, target) then
                GROUP_SCALE_SET[frame] = true
                local value = target
                secure(frame, "groupscale:" .. name, function()
                    local later = _G[name]
                    if type(later) == "table"
                        and type(later.SetScale) == "function" then
                        pcall(later.SetScale, later, value)
                    end
                end)
            end
        end
    end
end

-- Protection against re-entry: our size is assigned inside a handler of a
-- layout function, and on some builds that function calls itself down a
-- chain.
local reflowing = false

--- Repeat our own work after the game has laid the party list out afresh.
-- @return boolean whether it was carried out
function UnitFrames.Reflow()
    if reflowing then return false end

    reflowing = true
    local ok = pcall(function() UnitFrames:ApplyGroupFrames() end)
    reflowing = false

    return ok
end

--- Enabling the subsystem.
--
-- Here and only here are the event subscriptions created. The settings are not
-- applied in OnEnable: right after it the registry calls ApplyAll, and a second
-- path of application would be a second owner of one action.
--
-- Every subscription is guarded separately: an event that does not exist in
-- this client is met with an error by the engine, and losing all the other
-- subscriptions because of one name is not allowed.
function UnitFrames:OnEnable()
    -- The subscription goes through the core's door (ns.Events) rather than
    -- through AceEvent. The reason was measured rather than guessed: AceEvent
    -- keeps one handler per "event + object" pair, and the object is one and
    -- the same for every subsystem of the core — ns.Addon. Five subsystems
    -- asked for PLAYER_ENTERING_WORLD, four for PLAYER_REGEN_ENABLED, and out
    -- of each pair exactly the last one registered survived; the rest of the
    -- subscriptions vanished silently. The core's door keeps a subscription
    -- under the subsystem's name, so they cannot collide. The door can be
    -- absent only where it was not loaded (one subsystem's tests); in the game
    -- it is always there.
    local me = ns.Registry:NameOf(UnitFrames)
    if type(ns.Events) ~= "table" or me == nil then return end

    -- Leaving combat is the only moment when what was deferred can be
    -- applied.
    ns.Events.Subscribe("PLAYER_REGEN_ENABLED", me, function()
        UnitFrames.Drain(UnitFrames.queue)
    end)

    -- The subscription to the game's functions that paint the bars
    -- themselves. Through hooksecurefunc — after their work rather than instead
    -- of it: they are called both by the engine and by other addons, and they
    -- must not be replaced. The names are taken from the compatibility layer,
    -- which may be absent from a client entirely: what is not there never
    -- reaches us, and there are no checks of the client's version here. The
    -- subscription in Modules/ActionBars.lua is arranged the same way.
    if type(hooksecurefunc) == "function" then
        local painters = ns.Compat.Resolve("unitframe-recolor")
        for i = 1, #painters do
            if type(_G[painters[i]]) == "function" then
                if pcall(hooksecurefunc, painters[i], function()
                    counters.fired_unitframes = counters.fired_unitframes + 1
                    UnitFrames.Repaint()
                end) then
                    if not counted[painters[i]] then
                        counted[painters[i]] = true
                        counters.hooked_unitframes = counters.hooked_unitframes + 1
                    end
                end
            end
        end

        -- The layout of the compact frames is done by the game itself and
        -- redone on every change of the group's composition. We stand behind
        -- it rather than instead of it: the size the game has just taken out
        -- of its own table we confirm on the frames themselves. There may be
        -- no names at all — some builds keep the layout in an object's
        -- methods; then what remains is the event of the group's composition
        -- changing, which is subscribed to anyway.
        local layouts = ns.Compat.Resolve("raidframe-relayout")
        for i = 1, #layouts do
            if type(_G[layouts[i]]) == "function" then
                if pcall(hooksecurefunc, layouts[i], function()
                    counters.fired_unitframes = counters.fired_unitframes + 1
                    UnitFrames.Reflow()
                end) then
                    if not counted[layouts[i]] then
                        counted[layouts[i]] = true
                        counters.hooked_unitframes = counters.hooked_unitframes + 1
                    end
                end
            end
        end
    end

    for i = 1, #REFRESH_EVENTS do
        ns.Events.Subscribe(REFRESH_EVENTS[i], me, function()
            UnitFrames:ApplySettings()
        end)
    end
end

local NATIVE_BAR_LABEL = "Game's Own Texture"

--- The names of the bar textures out of LibSharedMedia.
-- The list is gathered at the moment the window opens rather than when the
-- tree is built: addons add textures of their own at any time after we are
-- loaded.
-- @return table name -> label
local function BarValues()
    -- The native entry is always added, including when the library is absent:
    -- it means not a texture out of the registry but a refusal to replace one,
    -- and a choice without it would be a one-way road.
    local values = { [NATIVE] = ns.Localize(NATIVE_BAR_LABEL) }

    local media = Media()
    if not media or type(media.List) ~= "function" then return values end

    local ok, list = pcall(media.List, media, "statusbar")
    if not ok or type(list) ~= "table" then return values end

    for i = 1, #list do
        values[list[i]] = list[i]
    end
    return values
end
UnitFrames.BarValues = BarValues

--- The order of the texture list's entries: the native one first, the rest
--- alphabetically.
-- Without an order of our own AceConfigDialog sorts the entries by label, and
-- "the game's own texture" would be lost in the middle of ours — that is, it
-- would be looked for where one rarely looks.
-- @return table array of keys
local function BarSorting()
    local keys = {}
    for key in pairs(BarValues()) do
        if key ~= NATIVE then keys[#keys + 1] = key end
    end
    table.sort(keys)
    table.insert(keys, 1, NATIVE)
    return keys
end
UnitFrames.BarSorting = BarSorting

-- The modes of the name's colour. An array rather than a table: the order in
-- the select list is set here, and the native colour stands first by the same
-- rule as the texture.
local NAME_MODES = {
    { key = NATIVE,     label = "Game's Own Name Color" },
    { key = "class",    label = "By Class" },
    { key = "reaction", label = "By Reaction" },
    { key = "fixed",    label = "Custom Color" },
}

--- The labels of the name colour modes.
-- @return table key -> label
local function NameModeValues()
    local values = {}
    for i = 1, #NAME_MODES do
        values[NAME_MODES[i].key] = ns.Localize(NAME_MODES[i].label)
    end
    return values
end
UnitFrames.NameModeValues = NameModeValues

--- The order of the name colour modes is the one they are declared in.
-- @return table array of keys
local function NameModeSorting()
    local keys = {}
    for i = 1, #NAME_MODES do keys[i] = NAME_MODES[i].key end
    return keys
end

-- The modes of the health bar's colour. The same three as the name's, plus
-- the game's own look as the first entry — by the same rule as the
-- texture's.
local HEALTH_MODES = {
    { key = NATIVE,     label = "Game's Own Bar Color" },
    { key = "class",    label = "By Class" },
    { key = "reaction", label = "By Reaction" },
    { key = "fixed",    label = "Custom Color" },
}

-- The modes of the power bar's colour. A power has no class and no reaction:
-- mana is blue, rage is red, energy is yellow — that is a property of the
-- power rather than of the unit.
local POWER_MODES = {
    { key = NATIVE,  label = "Game's Own Bar Color" },
    { key = "power", label = "By Power Type" },
    { key = "fixed", label = "Custom Color" },
}

--- The labels of the modes out of a list.
-- @param modes table array of { key, label }
-- @return function returning a table of key -> label
local function modeValues(modes)
    return function()
        local values = {}
        for i = 1, #modes do
            values[modes[i].key] = ns.Localize(modes[i].label)
        end
        return values
    end
end

--- The order of the modes is the one they are declared in.
-- @param modes table array of { key, label }
-- @return function returning an array of keys
local function modeSorting(modes)
    return function()
        local keys = {}
        for i = 1, #modes do keys[i] = modes[i].key end
        return keys
    end
end

UnitFrames.HealthModeValues = modeValues(HEALTH_MODES)
UnitFrames.PowerModeValues  = modeValues(POWER_MODES)

-- The orders of the entries are exposed for the same reason as the labels:
-- the same list of modes stands in the nameplates section
-- (Modules/NamePlates.lua), and a second copy of the order would diverge from
-- the first at the first new mode.
UnitFrames.HealthModeSorting = modeSorting(HEALTH_MODES)
UnitFrames.NameModeSorting   = NameModeSorting

-- Which frame is being edited right now.
--
-- Not a setting but the window's position: the player picked a tab by eye and
-- is editing what he sees. There is no point storing that between sessions — at
-- the window's next opening the right answer is "the shared ones", because that
-- is where one starts.
--
-- ALL means the common level: the choice every frame follows until it is
-- overridden.
local ALL = "__all"
UnitFrames.ALL = ALL

local editing = ALL

--- The key of the level being edited: nil for the common one.
local function editedKey()
    if editing == ALL then return nil end
    return editing
end

--- The get/set handlers of one field.
--
-- They write into whichever level is being edited. Empty at a frame's level
-- means "as the common one", and it is cleared by writing a nil — the same
-- movement by which "as the common one" is chosen in the list.
local function handlers(field)
    return function()
        local settings = Settings()
        if not settings then return nil end
        return (UnitFrames.Own(settings, editedKey(), field))
    end,
    function(_, value)
        local settings = Settings()
        if not settings then return end

        local key = editedKey()
        if key == nil then
            settings[field] = value
        else
            settings.units = type(settings.units) == "table"
                and settings.units or {}
            settings.units[key] = type(settings.units[key]) == "table"
                and settings.units[key] or {}
            settings.units[key][field] = value
        end

        UnitFrames:ApplySettings()
    end
end

--- Whether the player is editing one frame rather than the common level.
local function editingOne() return editing ~= ALL end

--- Whether this field is set at the level of the frame being edited.
local function ownHere(field)
    local settings = Settings()
    if not settings then return false end
    local _, own = UnitFrames.Own(settings, editedKey(), field)
    return own
end

--- The labels of the "which frame are we editing" list.
local function UnitValues()
    local values = { [ALL] = ns.Localize("All Frames") }
    for i = 1, #UnitFrames.UNITS do
        values[UnitFrames.UNITS[i].key] =
            ns.Localize(UnitFrames.UNITS[i].label)
    end
    return values
end

--- The order in that list. "All frames" stands first not alphabetically but
--- by meaning: one starts from the shared choice and comes to a single frame
--- afterwards.
local UNIT_ORDER = { ALL }
for i = 1, #UnitFrames.UNITS do
    UNIT_ORDER[#UNIT_ORDER + 1] = UnitFrames.UNITS[i].key
end
local function UnitSorting() return UNIT_ORDER end

local getHealth,      setHealth      = handlers("health")
local getHealthColor, setHealthColor = handlers("healthColor")
local getPower,       setPower       = handlers("power")
local getPowerColor,  setPowerColor  = handlers("powerColor")
local getMode,        setMode        = handlers("nameColor")
local getScale,       setScale       = handlers("scale")
local getGroupSize,   setGroupSize   = handlers("groupSize")
local getGroupWidth,  setGroupWidth  = handlers("groupWidth")
local getGroupHeight, setGroupHeight = handlers("groupHeight")
local getGroupScale,  setGroupScale  = handlers("groupScale")

--- The party frames tab is gone: the module draws them itself.
--
-- Asked of the module at every redraw rather than remembered: the frames are
-- taken over on entering the world, that is, later than this file is read, and
-- a remembered answer would stay "not taken" forever.
local function groupTabGone()
    return UnitFrames.GroupFramesTaken and UnitFrames.GroupFramesTaken()
        and true or false
end

--- Whether the group size sliders are switched off.
-- A greyed-out slider next to a switch reads by itself: it shows that the
-- number has been dialled in but is not in effect yet. Without it the two
-- sliders would look as though they worked while the size stayed the game's,
-- and there would be nothing to explain that with.
-- @return boolean
local function groupSizeOff()
    local settings = Settings()
    return not (settings and settings.groupSize)
end

--- The get/set handlers of a colour field.
-- A colour arrives and leaves in AceConfig as three numbers, while in the
-- profile it lies as a table with named channels — the very shape the game
-- returns.
-- @param field string
-- @return function, function
local function colorHandlers(field)
    return function()
        local settings = Settings()
        local color = settings and settings[field]
        if type(color) ~= "table" then return 1, 1, 1 end
        return color.r or 1, color.g or 1, color.b or 1
    end,
    function(_, r, g, b)
        local settings = Settings()
        if not settings then return end
        settings[field] = { r = r, g = g, b = b }
        UnitFrames:ApplySettings()
    end
end

local getHealthFixed, setHealthFixed = colorHandlers("healthFixed")
local getPowerFixed,  setPowerFixed  = colorHandlers("powerFixed")
local getNameFixed,   setNameFixed   = colorHandlers("nameFixed")

-- The section's layout. The page is laid out in tabs (childGroups = "tab"):
-- as a single ribbon it was a canvas of fifteen-odd rows, and the author said
-- so outright — do you think scrolling this canvas is convenient; I would move
-- it into inner tabs, like the fonts.
--
-- There are three tabs, and they divide the page not by our headers but by what
-- the player came here for: to change HOW A BAR LOOKS, what is WRITTEN on the
-- frame, or WHAT SIZE it is.
--
--   * "Health and Power" — the texture and the colour of both bars. The health
--     bar and the power bar are configured identically and almost always
--     together: splitting them across two tabs would mean making the player
--     click back and forth for one and the same pair of actions.
--   * "Name and Bar Text" — everything written on the frame: the name's colour
--     and the block of bar labels that arrives here from its own subsystem
--     (Modules/Texts.lua, ns.INLINE_SECTIONS). It stays on this page for the
--     old reason — the health and power bars are a unit frame's children, and
--     labels on them are not entitled to a row of their own in the column; the
--     tab chosen is the one that already holds the frame's other label, its
--     name.
--   * "Size" — both the scale of the individual frames and the size of the
--     party frames. They are on ONE tab deliberately: the player's, the
--     target's and the pet's frames have no width and height at all (the
--     framing is nailed down with pixel offsets), while the party frames have a
--     real size. That difference is not a trifle, the author asked about it,
--     and it is visible only when both halves and the explanation between them
--     lie on one screen.
--
-- Rejected: a tab per former header. There would be five or six of them with
-- two settings each — one scroll would be exchanged for a handful of clicks,
-- and the window's tab ribbon is single and horizontal.
--
-- Rejected too: the live "what is in effect now" line from the fonts page.
-- There it answers a question about levels (the global font or one's own),
-- while here there are no levels — each setting has exactly one value of its
-- own, and the line would repeat the widget standing beside it.
--
-- Inside a tab the settings stand one per row (width = "full") and are gathered
-- into meaningful parts with a header before each. Without headers and with
-- differing widths AceConfigDialog lays the contents out as a flow: it gives a
-- setting without a width a hundred and seventy pixels, and two or three
-- settings alien to one another end up side by side. The orders go in steps of
-- ten: between any two neighbours there is always room for a new setting, and
-- there is no need to renumber the tab for its sake. The settings' orders were
-- not rewritten when they were distributed across the tabs — inside a tab they
-- are independent, and untouched numbers are visible in a diff.
--
-- The storage does not move: every node has the same get and set it had, and
-- the key in the profile is known to them alone
-- (tests/test_unitframetabs.lua — the identity of the tables).
UnitFrames.options = {
    type = "group",
    name = ns.Localize("Unit Frames"),
    childGroups = "tab",
    args = {
        -- The choice of frame stands above the tabs rather than as a tab
        -- beside them, and that is not decoration. The tabs answer the
        -- question "what are we configuring" — the bars, the name, the size;
        -- this list answers a different one: "whose". Laid in one row with
        -- them, it would make a "Target" tab read as yet another setting of
        -- the target's.
        --
        -- It also stands outside the tabs so as not to vanish when moving from
        -- tab to tab: the chosen frame stays chosen, and the player configures
        -- the target as a whole rather than choosing it three times.
        frames = {
            type = "group",
            order = 10,
            name = ns.Localize("Individual Frames"),
            childGroups = "tab",
            args = {
        unit = {
            type = "select",
            order = 1,
            width = "full",
            name = ns.Localize("These Settings Are For"),
            desc = ns.Localize("\"All Frames\" is the choice every frame " ..
                "follows until you give that frame one of its own. What " ..
                "you set on a single frame wins over it and keeps winning; " ..
                "what you leave as \"Same as All Frames\" follows the " ..
                "shared choice and keeps following it as you change it. " ..
                "Your own frame and the target frame are looked at " ..
                "differently - one out of the corner of the eye, the other " ..
                "in a fight - and one setting for both means choosing what " ..
                "gets in the way least rather than what you want."),
            values = UnitValues,
            sorting = UnitSorting,
            get = function() return editing end,
            set = function(_, value)
                editing = value
                if type(ns.RefreshOptions) == "function" then
                    ns.RefreshOptions()
                end
            end,
        },

        sameAsAll = {
            type = "execute",
            order = 2,
            width = "full",
            name = ns.Localize("Back to the Shared Settings"),
            desc = ns.Localize("Drops everything set on this frame alone, " ..
                "so it follows the shared choice again - and goes on " ..
                "following it."),
            hidden = function() return not editingOne() end,
            disabled = function()
                local settings = Settings()
                local units = settings and settings.units
                local entry = type(units) == "table" and units[editedKey()]
                if type(entry) ~= "table" then return true end
                for _ in pairs(entry) do return false end
                return true
            end,
            func = function()
                local settings = Settings()
                if not settings or type(settings.units) ~= "table" then return end
                settings.units[editedKey()] = nil
                UnitFrames:ApplySettings()
            end,
        },

        -- The page is laid out in two tiers, and the tiers answer different
        -- questions.
        --
        -- The upper one is about WHAT is being configured: the individual
        -- frames or the party grid. Those are different things, and they became
        -- different for more than beauty's sake. An individual frame has a unit
        -- of its own, and settings of its own with it; the party grid has no
        -- unit at all — it is one for everybody, and there is nobody in it to
        -- choose.
        --
        -- They used to lie mixed together, on one "Size" tab, and a label
        -- beneath them apologised in prose: the frame chosen above does not
        -- reach these. Prose that explains a layout is itself the layout's
        -- failure: the "whose frame" list hung over settings it did not command.
        -- Now it hangs over exactly the ones it does command, and the party grid
        -- stands beside them as a tab of its own.
        --
        -- A ribbon of a single tab went away along with it. There was one tab —
        -- "Individual Frames" — and a ribbon with a single button reads as
        -- unfinished: there is room for a choice and nothing to choose.
        --
        -- The lower ribbon, inside the first, is about WHICH SIDE is being
        -- configured: the bars, the labels, the size. And the "whose frame"
        -- choice stands ABOVE those inner tabs and inside the upper one: it
        -- commands all of them and only them, and its place is where its power
        -- ends.

        bars = {
            type = "group",
            order = 10,
            name = ns.Localize("Health and Power"),
            args = {
                healthHeader = {
                    type = "header",
                    order = 10,
                    name = ns.Localize("Health Bar"),
                },
                health = {
                    type = "select",
                    order = 11,
                    width = "full",
                    name = ns.Localize("Health Bar Texture"),
                    desc = ns.Localize("The first entry is the game's own " ..
                        "texture: the addon leaves it alone until asked, " ..
                        "and going back to it restores exactly the look " ..
                        "you had before, at once and without an interface " ..
                        "reload. The addon's own textures are a gradient " ..
                        "from white to a color. The engine multiplies them " ..
                        "by the bar color, so the white end gives the pure " ..
                        "color and the pastel end its muted shade. Which " ..
                        "color that is, is chosen right below."),
                    values = BarValues,
                    sorting = BarSorting,
                    get = getHealth,
                    set = setHealth,
                },
                healthColor = {
                    type = "select",
                    order = 12,
                    width = "full",
                    name = ns.Localize("Health Bar Color"),
                    desc = ns.Localize("The color the texture is tinted " ..
                        "by. \"By Class\" applies to players only: " ..
                        "creatures have no class, so their bar is colored " ..
                        "by reaction to you. The first entry leaves the " ..
                        "color to the game, and switching back to it " ..
                        "restores the native color at once."),
                    values = UnitFrames.HealthModeValues,
                    sorting = modeSorting(HEALTH_MODES),
                    get = getHealthColor,
                    set = setHealthColor,
                },
                healthFixed = {
                    type = "color",
                    order = 13,
                    -- The default colour sits beside the setting as a
                    -- reference to the defaults table itself rather than as a
                    -- rewritten number: otherwise "restore the default" and
                    -- "what a new player has" would diverge at the first edit
                    -- of either. It is read by the colour swatch's styling
                    -- (Skin.DefaultColor).
                    arg = { default = UnitFrames.defaults.healthFixed },
                    width = "full",
                    name = ns.Localize("Custom Health Bar Color"),
                    desc = ns.Localize("Used in \"Custom Color\" mode, and " ..
                        "also when neither the class nor the reaction of a " ..
                        "unit is known."),
                    hasAlpha = false,
                    get = getHealthFixed,
                    set = setHealthFixed,
                },

                powerHeader = {
                    type = "header",
                    order = 20,
                    name = ns.Localize("Power Bar"),
                },
                power = {
                    type = "select",
                    order = 21,
                    width = "full",
                    name = ns.Localize("Power Bar Texture"),
                    desc = ns.Localize("Mana, rage, energy. The texture is " ..
                        "tinted by the bar color just as on the health " ..
                        "bar. The first entry is the game's own texture, " ..
                        "and going back to it restores the native look at " ..
                        "once."),
                    values = BarValues,
                    sorting = BarSorting,
                    get = getPower,
                    set = setPower,
                },
                powerColor = {
                    type = "select",
                    order = 22,
                    width = "full",
                    name = ns.Localize("Power Bar Color"),
                    desc = ns.Localize("\"By Power Type\" takes the color " ..
                        "from the game itself: mana blue, rage red, energy " ..
                        "yellow, and so on for whatever this client has. " ..
                        "The first entry leaves the color to the game, and " ..
                        "switching back to it restores the native color at " ..
                        "once."),
                    values = UnitFrames.PowerModeValues,
                    sorting = modeSorting(POWER_MODES),
                    get = getPowerColor,
                    set = setPowerColor,
                },
                powerFixed = {
                    type = "color",
                    order = 23,
                    -- The default colour sits beside the setting as a
                    -- reference to the defaults table itself rather than as a
                    -- rewritten number: otherwise "restore the default" and
                    -- "what a new player has" would diverge at the first edit
                    -- of either. It is read by the colour swatch's styling
                    -- (Skin.DefaultColor).
                    arg = { default = UnitFrames.defaults.powerFixed },
                    width = "full",
                    name = ns.Localize("Custom Power Bar Color"),
                    desc = ns.Localize("Used in \"Custom Color\" mode, and " ..
                        "also when the game has no color for this kind of " ..
                        "power."),
                    hasAlpha = false,
                    get = getPowerFixed,
                    set = setPowerFixed,
                },
            },
        },

        text = {
            type = "group",
            order = 20,
            name = ns.Localize("Name and Bar Text"),
            args = {
                nameHeader = {
                    type = "header",
                    order = 30,
                    name = ns.Localize("Unit Name"),
                },
                nameColor = {
                    type = "select",
                    order = 31,
                    width = "full",
                    name = ns.Localize("Name Color"),
                    desc = ns.Localize("\"Game's Own Name Color\" leaves " ..
                        "the name to the game; switching back to it " ..
                        "restores the native color at once. \"By Class\" " ..
                        "applies to players only: creatures have no class, " ..
                        "so their name is colored by reaction to you. When " ..
                        "that is unknown too, the color chosen below is " ..
                        "used."),
                    values = NameModeValues,
                    sorting = NameModeSorting,
                    get = getMode,
                    set = setMode,
                },
                nameFixed = {
                    type = "color",
                    order = 32,
                    -- The default colour sits beside the setting as a
                    -- reference to the defaults table itself rather than as a
                    -- rewritten number: otherwise "restore the default" and
                    -- "what a new player has" would diverge at the first edit
                    -- of either. It is read by the colour swatch's styling
                    -- (Skin.DefaultColor).
                    arg = { default = UnitFrames.defaults.nameFixed },
                    width = "full",
                    name = ns.Localize("Custom Name Color"),
                    desc = ns.Localize("Used in \"Custom Color\" mode, and " ..
                        "also when neither the class nor the reaction of a " ..
                        "unit is known."),
                    hasAlpha = false,
                    get = getNameFixed,
                    set = setNameFixed,
                },
            },
        },

        size = {
            type = "group",
            order = 30,
            name = ns.Localize("Size"),
            args = {
                scale = {
                    type = "range",
                    order = 41,
                    width = "full",
                    name = ns.Localize("Frame Scale"),
                    desc = ns.Localize("One is the native size. Scale is a " ..
                        "protected operation: a change made in combat is " ..
                        "queued and applied as soon as combat ends. " ..
                        "Textures and colors are not protected and apply " ..
                        "immediately, in combat as well."),
                    min = 0.5, max = 2, step = 0.05, isPercent = true,
                    get = getScale,
                    set = setScale,
                },
                frameNote = {
                    type = "description",
                    order = 42,
                    width = "full",
                    name = ns.Localize("Scale multiplies everything at " ..
                        "once: the bars, the portrait, the artwork and the " ..
                        "text. There is no width or height here on purpose " ..
                        "- the player, target and pet frames are drawn " ..
                        "from artwork pinned to the frame at fixed " ..
                        "offsets, so a width would change the click area " ..
                        "and move nothing you can see. Group and raid " ..
                        "frames are built from numbers instead, and there " ..
                        "size is real: they have a tab of their own."),
                },
            },
        },
            },
        },

        group = {
            type = "group",
            order = 20,
            name = ns.Localize("Group and Raid Frames"),
            -- The tab goes away when the module draws the party frames: it
            -- configures THE GAME'S compact frames, and in that case there are
            -- none of them on the screen at all. A setting that affects
            -- nothing is worse than a missing one: the player moves a slider
            -- and does not understand why nothing happens.
            hidden = function() return UnitFrames.GroupFramesTaken() end,
            args = {
            groupSize = {
                type = "toggle",
                order = 51,
                width = "full",
                name = ns.Localize("Set the Group Frame Size Myself"),
                desc = ns.Localize("Off leaves the size of a group " ..
                    "member to the game, which is where a fresh " ..
                    "install starts. On hands the two numbers below to " ..
                    "the game's own layout, so they survive the group " ..
                    "changing: a member joining or leaving re-lays the " ..
                    "list out, and the game reads the size from the " ..
                    "same place we wrote it. Size changes the box and " ..
                    "leaves the text alone; scale multiplies both. " ..
                    "They compose - a frame 120 wide at scale 1.5 " ..
                    "takes 180 on screen."),
                get = getGroupSize,
                set = setGroupSize,
            },
            groupWidth = {
                type = "range",
                order = 52,
                width = "full",
                name = ns.Localize("Group Frame Width"),
                desc = ns.Localize("How wide one group member is. " ..
                    "Sizing a group frame is a protected operation: a " ..
                    "change made in combat is queued and applied as " ..
                    "soon as combat ends. Clients without compact " ..
                    "group frames are left alone: the setting then " ..
                    "quietly does nothing rather than erroring."),
                min = 40, max = 160, step = 1,
                disabled = groupSizeOff,
                get = getGroupWidth,
                set = setGroupWidth,
            },
            groupHeight = {
                type = "range",
                order = 53,
                width = "full",
                name = ns.Localize("Group Frame Height"),
                desc = ns.Localize("How tall one group member is. " ..
                    "Queued in combat just like the width, and applied " ..
                    "as soon as combat ends."),
                min = 16, max = 80, step = 1,
                disabled = groupSizeOff,
                get = getGroupHeight,
                set = setGroupHeight,
            },
            groupScale = {
                type = "range",
                order = 54,
                width = "full",
                name = ns.Localize("Group Frame Scale"),
                desc = ns.Localize("One is the native size. Scale " ..
                    "multiplies the whole group frame, text and all, " ..
                    "on top of the width and height above. It is a " ..
                    "protected operation too, so a change made in " ..
                    "combat applies as soon as combat ends."),
                min = 0.5, max = 2, step = 0.05, isPercent = true,
                get = getGroupScale,
                set = setGroupScale,
            },
            groupNote = {
                type = "description",
                order = 50.5,
                width = "full",
                name = ns.Localize("There is no frame to choose on " ..
                    "this tab, and that is the whole difference " ..
                    "between it and the one beside it: the group grid " ..
                    "has no unit of its own, and one size serves every " ..
                    "member. Width and height here are real numbers, " ..
                    "unlike the player and target frames, which are " ..
                    "drawn from artwork and have scale only."),
            },
            },
        },
    },
}

--============================================================================
-- The settings page, declared as data
--============================================================================

-- The shared choice for every frame. An individual frame's own settings (the
-- units section) are not declared here: that is a setting which assembles
-- itself, and it will appear in the schema as a "widget" kind when its turn
-- comes. The loophole is deliberately narrow — the window still does not know
-- what is inside.

if type(ns.Schema) == "table" then
    local Schema = ns.Schema
    local PAGE = "unitframes"

    Schema.Page(PAGE, {
        title = "Unit Frames",
        order = 5,
        section = "unitframes",
    })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "The game's own portrait frames: you, your target, the "
            .. "party. The first entry in every list below is the game's "
            .. "own look, so nothing here is one way.",
    })

    Schema.Add(PAGE, { kind = "header", label = "Health Bar" })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Health Bar Texture",
        path = { "health" },
        apply = "unitframes",
        hint = "The texture the health bar is drawn with. The first entry "
            .. "leaves the game's own.",
        values = BarValues,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Health Bar Color",
        path = { "healthColor" },
        apply = "unitframes",
        hint = "What the health bar's colour means: the game's own rule, "
            .. "the class of whoever it belongs to, or one colour you pick.",
        values = UnitFrames.HealthModeValues,
    })

    Schema.Add(PAGE, {
        kind = "color",
        label = "Health Bar Fixed Color",
        path = { "healthFixed" },
        apply = "unitframes",
        hint = "The one colour used when the health bar is set to a fixed "
            .. "colour above.",
    })

    Schema.Add(PAGE, { kind = "header", label = "Power Bar" })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Power Bar Texture",
        path = { "power" },
        apply = "unitframes",
        hint = "The texture the power bar is drawn with. The first entry "
            .. "leaves the game's own.",
        values = BarValues,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Power Bar Color",
        path = { "powerColor" },
        apply = "unitframes",
        hint = "What the power bar's colour means: the game's own rule by "
            .. "power type, or one colour you pick.",
        values = UnitFrames.PowerModeValues,
    })

    Schema.Add(PAGE, {
        kind = "color",
        label = "Power Bar Fixed Color",
        path = { "powerFixed" },
        apply = "unitframes",
        hint = "The one colour used when the power bar is set to a fixed "
            .. "colour above.",
    })

    Schema.Add(PAGE, { kind = "header", label = "Name and Size" })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Unit Name Color",
        path = { "nameColor" },
        apply = "unitframes",
        hint = "What the unit's name is coloured by: the game's own rule, "
            .. "the unit's class, or one colour you pick.",
        values = NameModeValues,
    })

    Schema.Add(PAGE, {
        kind = "color",
        label = "Unit Name Fixed Color",
        path = { "nameFixed" },
        apply = "unitframes",
        hint = "The one colour used when the name is set to a fixed colour "
            .. "above.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Frame Scale",
        path = { "scale" },
        min = 0.5, max = 2, step = 0.05,
        apply = "unitframes",
        hint = "How big the portrait frames are drawn. One is the size the "
            .. "game gives them.",
    })

    Schema.Add(PAGE, { kind = "header",
        label = "Party and Raid Frames",
        hidden = groupTabGone })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Set the Size of Group Frames",
        path = { "groupSize" },
        hidden = groupTabGone,
        apply = "unitframes",
        hint = "While this is off, not one number is forced on the game: a "
            .. "party member keeps the size the game gave it, and the real "
            .. "native numbers are read before the first change of ours and "
            .. "put back when this goes off again.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Group Frame Width",
        path = { "groupWidth" },
        hidden = groupTabGone,
        disabled = groupSizeOff,
        min = 40, max = 200, step = 1,
        apply = "unitframes",
        hint = "Only used while the switch above is on.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Group Frame Height",
        path = { "groupHeight" },
        hidden = groupTabGone,
        disabled = groupSizeOff,
        min = 20, max = 120, step = 1,
        apply = "unitframes",
        hint = "Only used while the switch above is on.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Group Frame Scale",
        path = { "groupScale" },
        hidden = groupTabGone,
        disabled = groupSizeOff,
        min = 0.5, max = 2, step = 0.05,
        apply = "unitframes",
        hint = "Only used while the switch above is on.",
    })
end

ns.Registry:Register(UnitFrames)
