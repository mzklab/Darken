local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("itemlevel")

-- The pure rules for showing an item's level.
--
-- There is not one touch of the game here: all this file can do is decide
-- which number to show, in what colour, at what size and in which corner of
-- the icon. The game's values arrive as arguments because they are precisely
-- what breaks: the level arrives now as a number, now as nil, now as a zero
-- (an item the client knows nothing about yet), the quality is sometimes
-- negative, and the setting comes out of SavedVariables, into which anything
-- at all finds its way over the years.
--
-- The answer to "does an item's level mean anything on this client" comes from
-- here too: it is decided by the presence of game objects rather than by the
-- build number.

local Level = {}
ns.Level = Level

-- The marks of a client on which an item's level is a meaningful number.
--
-- The list holds candidates, exactly as the list of frame names in the core's
-- compatibility layer does: an object's existence is checked rather than the
-- client's version. The build number lies twice — it changes on one and the
-- same client and coincides across different lines — and "the level is not
-- shown on 2.5.4" would be a rule that breaks on 2.5.5.
--
-- Why these three. Each appears only where an item's level really governs a
-- character's power: the detailed level with upgrades taken into account, the
-- average level of the equipment, and the character window's information
-- table. On vanilla and TBC an item does have a level, but it decides nothing,
-- and not one of these objects exists on the client.
local PROBES = {
    "GetDetailedItemLevelInfo",
    "GetAverageItemLevel",
    "C_PaperDollInfo",
}
Level.PROBES = PROBES

--- Whether an item's level means anything on this client.
-- @param env table the client's table of globals (in the game, _G)
-- @return boolean
function Level.Meaningful(env)
    if type(env) ~= "table" then return false end

    for i = 1, #PROBES do
        local object = env[PROBES[i]]
        local kind = type(object)
        if kind == "function" or kind == "table" then return true end
    end

    return false
end

--- The item's id out of its link.
--
-- The link is the only thing the game returns about an item at once and
-- always; the id out of it is needed in order to recognise that item in the
-- information-ready event. Parsed as a string rather than by a game function:
-- the game's own exists on some clients only, while the link's shape — the
-- word "item" followed by the id — is the same on all of them.
-- @param link any
-- @return number|nil
function Level.ItemID(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

--- Which number to show.
--
-- The detailed level (upgrades included) outranks the plain one: it is the one
-- the game shows in the tooltip, and diverging from the tooltip means making
-- the player trust one of two numbers at random.
--
-- A zero is not a level but "I do not know yet": the client returns a zero
-- both for an item whose information has not been loaded and for an item with
-- no level at all. Both cases mean "do not show a number", and the caller
-- tells them apart by whether the readiness event arrived.
--
-- @param detailed any the detailed level
-- @param basic any the level out of the general information
-- @return number|nil
function Level.Choose(detailed, basic)
    local value = tonumber(detailed)
    if not value or value ~= value or value <= 0 then
        value = tonumber(basic)
    end
    if not value or value ~= value or value <= 0 then return nil end

    return math.floor(value)
end

--- The number as a string.
-- An empty string rather than nil: it goes into SetText, and a nil there would
-- mean different things on different clients.
-- @param level any
-- @return string
function Level.Format(level)
    local value = tonumber(level)
    if not value or value ~= value or value <= 0 then return "" end
    return string.format("%d", math.floor(value))
end

--- What to do with one place on screen.
--
-- The whole order of the decision is collected into one pure function, and
-- that was done for a single case — an item whose information has not arrived
-- yet. Where that case is handled in place, it is handled by halves: the
-- number did not appear, the slot was cleared, and nobody will remember it
-- again. Here it has a name of its own — "wait" — and an item id of its own,
-- by which the place will be found when the information comes.
--
-- @param link any the item's link, or nil when the place is empty
-- @param detailed any the detailed level from the game
-- @param basic any the level out of the general information
-- @return string "show", "wait" or "clear"
-- @return number|nil the level for "show", the item's id for "wait"
function Level.Decide(link, detailed, basic)
    if type(link) ~= "string" or link == "" then return "clear", nil end

    local level = Level.Choose(detailed, basic)
    if level then return "show", level end

    -- There is no level but there is a link: the item exists while its
    -- information is still on its way.
    local item = Level.ItemID(link)
    if not item then return "clear", nil end

    return "wait", item
end

-- The number's fallback colour: white. Not "none": a string without a colour
-- would keep the colour from the previous item, and that is the nastiest kind
-- of error — a plausible one.
local WHITE = { r = 1, g = 1, b = 1 }

--- The number's colour.
--
-- Through one table rather than four arguments: the colour is asked for on
-- every bag slot, and the table here is one and reused.
--
-- @param info table|nil { byQuality, quality, colors, fallback }
-- @return number, number, number
function Level.Color(info)
    if type(info) ~= "table" then return WHITE.r, WHITE.g, WHITE.b end

    local fallback = type(info.fallback) == "table" and info.fallback or WHITE

    if not info.byQuality then
        return tonumber(fallback.r) or WHITE.r,
               tonumber(fallback.g) or WHITE.g,
               tonumber(fallback.b) or WHITE.b
    end

    local quality = tonumber(info.quality)
    local colors = type(info.colors) == "table" and info.colors or nil
    local color = quality and colors and colors[quality] or nil

    if type(color) == "table" then
        local r = tonumber(color.r) or tonumber(color[1])
        local g = tonumber(color.g) or tonumber(color[2])
        local b = tonumber(color.b) or tonumber(color[3])
        if r and g and b then return r, g, b end
    end

    return tonumber(fallback.r) or WHITE.r,
           tonumber(fallback.g) or WHITE.g,
           tonumber(fallback.b) or WHITE.b
end

-- The icon's corners. The array sets the order of the rows in the settings
-- list, the table parses the value: two lists of corners would diverge
-- silently, and part of the choice in the list would change nothing.
local POSITIONS = {
    { key = "topleft",     point = "TOPLEFT",     x =  1, y = -1,
      label = "Top Left" },
    { key = "topright",    point = "TOPRIGHT",    x = -1, y = -1,
      label = "Top Right" },
    { key = "bottomleft",  point = "BOTTOMLEFT",  x =  1, y =  1,
      label = "Bottom Left" },
    { key = "bottomright", point = "BOTTOMRIGHT", x = -1, y =  1,
      label = "Bottom Right" },
    { key = "center",      point = "CENTER",      x =  0, y =  0,
      label = "Center" },
}
Level.POSITIONS = POSITIONS

-- The default position. The top left corner: the bottom right is taken by the
-- stack count, and two numbers in one corner would overlap.
local DEFAULT_POSITION = "topleft"
Level.DEFAULT_POSITION = DEFAULT_POSITION

local BY_KEY = {}
for i = 1, #POSITIONS do BY_KEY[POSITIONS[i].key] = POSITIONS[i] end

--- The number's anchor on the icon.
--
-- The inset comes from the core skin's scale of insets (Metrics.edge) rather
-- than being written as a number: one and the same distance on screen is set
-- by one value. The inset's sign belongs to the corner rather than to the
-- caller.
--
-- The two when there is no inset is the answer to "there is no skin at all"
-- rather than a second record of the quantity: it adds up with nothing and
-- stands in for a missing answer. A one used to stand here — the same quantity
-- the hair metric returned at the time, and that coincidence was accidental.
--
-- @param position any the setting's value
-- @param inset any the inset from the skin's scale
-- @return string the anchor point
-- @return number the horizontal offset
-- @return number the vertical offset
function Level.Anchor(position, inset)
    local spec = BY_KEY[position] or BY_KEY[DEFAULT_POSITION]

    local gap = tonumber(inset)
    if not gap or gap ~= gap or gap < 0 then gap = 2 end

    return spec.point, spec.x * gap, spec.y * gap
end

-- The bounds of the number's size. The same numbers stand in the settings
-- section's slider: two lists of bounds would give a slider part of whose
-- travel changes nothing.
local BOUNDS = {
    size = { min = 6, max = 24, default = 11 },
}
Level.BOUNDS = BOUNDS

--- The number's size from the setting.
-- Not a number means the default: such a value cannot be produced with the
-- slider, so it did not come from the player. A number beyond a bound is
-- clamped to it.
-- @param value any
-- @return number
function Level.ClampSize(value)
    local spec = BOUNDS.size

    local number = tonumber(value)
    if not number or number ~= number then return spec.default end

    if number < spec.min then return spec.min end
    if number > spec.max then return spec.max end
    return number
end

--- Parsing a slot button's item attribute: the bag and the slot as two
--- numbers.
--
-- Needed in order to show the number on somebody else's bag window (the bags
-- module): its button does not store the item's place of its own, while the
-- attribute it uses the item by does — and that can be read.
--
-- @param value any
-- @return number|nil the bag
-- @return number|nil the slot
function Level.ParseItemAttribute(value)
    if type(value) ~= "string" then return nil, nil end

    local container, slot = value:match("^%s*(%-?%d+)%s+(%-?%d+)%s*$")
    if not container then return nil, nil end

    return tonumber(container), tonumber(slot)
end
