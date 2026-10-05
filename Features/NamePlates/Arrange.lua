local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- The positions of a nameplate's parts: the pure rule of "what stands
-- where".
--
-- The parts are the name, the level, the cast bar, the aura icons, the quest
-- icon and the nameplate itself. Each has a place (the side it stands on) and
-- two offsets in points. Here there is only arithmetic: not one frame, not one
-- string for the player. The display writes the positions (Plate.Place), one
-- function from here decides them (Arrange.Spec), and there is no second place
-- in the module that moves the parts — exactly the same one-owner rule the
-- colour (Colors.Bar) and the scale (Plate.SetScale) live by.
--
-- === Why a place rather than free dragging ===
--
-- A nameplate does not stand on the screen: there are dozens of them, they
-- appear and leave, and "right here" does not exist for them at all. A part's
-- place exists relative to the health bar and in no other way, and a bar has
-- four sides. Dragging would draw the same answer more expensively and less
-- precisely.
--
-- === What an offset means when nameplates are of different sizes ===
--
-- Nothing beyond what has been said already: an offset is points in the
-- nameplate's own units, and a rule for a single unit changes the scale of the
-- frame itself (Plate.SetScale). So a nameplate a rule enlarged is enlarged
-- entirely, positions included: the parts neither drift apart nor ride over
-- each other. Multiplying the offset by the rule's factor would be a second
-- record of the same multiplication — and the first, the engine's, would
-- remain anyway.
--
-- === When this is computed ===
--
-- Once per edit of the settings (Arrange.Compile), like the aura filter's plan
-- and the compiled rules. After that the finished plan travels with the
-- events, and Spec is called only during a placement — that is, on a
-- nameplate's attachment and on an edit of a setting, but never on an update
-- of health, of auras or of a cast.

local Arrange = {}
ns.Arrange = Arrange

-- The parts in the order the settings section offers them for choosing. The
-- nameplate itself comes last: it is the only one with no side.
local PARTS = { "name", "level", "cast", "auras", "quest", "plate" }
Arrange.PARTS = PARTS

local KNOWN = {}
for i = 1, #PARTS do KNOWN[PARTS[i]] = true end

-- The places of each part. The first in the list is the default, and that
-- default was not chosen afresh but copied from how the nameplate looked
-- before the positions existed: a fresh install is obliged to change nothing
-- on screen.
--
-- A part has as many places as it has meaningful ones, and not one more.
-- "Above the bar" and "under the nameplate" for the name are two things the
-- player genuinely asks for; eight compass points for a label is a list with
-- nothing to choose from.
local PLACES = {
    name  = { "top", "over", "bottom" },
    level = { "top", "over", "bottom" },
    cast  = { "bottom", "top" },
    auras = { "top", "bottom" },
    quest = { "left", "right" },
    -- The nameplate itself stands where the game put it, and only the
    -- offsets move it. It has no side: it does not stand beside itself.
    plate = { "center" },
}
Arrange.PLACES = PLACES

-- The offset's bounds. The same numbers stand in the settings section's
-- slider: two lists of bounds would diverge silently, and part of the slider
-- would stop changing anything.
--
-- A hundred and fifty points in each direction is noticeably more than the
-- tallest nameplate and noticeably less than the screen: an offset has to be
-- able to take a part beyond its own nameplate (that is what it is asked for)
-- and does not have to be able to take it to the other end of the screen,
-- where it would stop having anything to do with its creature.
local OFFSET = { min = -150, max = 150, default = 0 }
Arrange.OFFSET = OFFSET

--- A part's default place.
-- @param part string|nil
-- @return string|nil
function Arrange.Default(part)
    local list = PLACES[part]
    return list and list[1] or nil
end

--- Whether this part has such a place at all.
-- @param part string|nil
-- @param place any
-- @return boolean
function Arrange.Has(part, place)
    local list = PLACES[part]
    if not list then return false end

    for i = 1, #list do
        if list[i] == place then return true end
    end
    return false
end

--- Bring a place to a meaningful one.
-- An unfamiliar place means the default rather than a Lua error: the value
-- comes from SavedVariables, into which anything at all finds its way over the
-- years, and a part left without an anchor would disappear from the screen for
-- good.
-- @param part string|nil
-- @param place any
-- @return string|nil
function Arrange.Place(part, place)
    if not KNOWN[part] then return nil end
    if Arrange.Has(part, place) then return place end
    return Arrange.Default(part)
end

--- Bring an offset within its bounds.
-- Not a number means zero: a value that cannot be produced with the slider did
-- not come from the player. A number beyond a bound is clamped to it.
-- @param value any
-- @return number
function Arrange.Offset(value)
    local number = tonumber(value)
    if not number or number ~= number then return OFFSET.default end
    if number < OFFSET.min then return OFFSET.min end
    if number > OFFSET.max then return OFFSET.max end
    return number
end

--- Compile the positions from the settings into a finished plan.
--
-- Called once per edit of the settings and nowhere else: parsing the saved
-- variables for every creature that appears is precisely the cost whose
-- absence the engine is written for.
--
-- The plan is always complete: every part has a place and both offsets, even
-- when the saved variables say not one word about it. So the display never has
-- to know about the defaults at all.
--
-- @param settings table|nil the module's settings section
-- @return table
function Arrange.Compile(settings)
    local store = nil
    if type(settings) == "table" and type(settings.arrange) == "table" then
        store = settings.arrange
    end

    local plan = {}
    for i = 1, #PARTS do
        local part = PARTS[i]
        local saved = store and store[part]
        if type(saved) ~= "table" then saved = nil end

        plan[part] = {
            place = Arrange.Place(part, saved and saved.place),
            x = Arrange.Offset(saved and saved.x),
            y = Arrange.Offset(saved and saved.y),
        }
    end

    return plan
end

--- Whether a part stands somewhere other than it would on a fresh install.
-- The settings display needs it rather than the placement: a "reset" button
-- with nothing to reset tells the player an untruth about what they have
-- done.
-- @param plan table|nil
-- @param part string|nil
-- @return boolean
function Arrange.Moved(plan, part)
    local entry = type(plan) == "table" and plan[part] or nil
    if type(entry) ~= "table" then return false end

    return entry.place ~= Arrange.Default(part)
        or entry.x ~= OFFSET.default
        or entry.y ~= OFFSET.default
end

-- The anchors. Each row is our part's point, the point of what it is anchored
-- to, and two offsets in points, computed from the nameplate's measurements.
--
-- Every part's default is copied from the former display letter for letter,
-- and that is tested directly: the suite compares Spec's answer under an empty
-- plan against the numbers that stood in Plate.Layout and Plate.LayoutExtras
-- before the positions existed.
--
-- The rel field says what to anchor to: "frame" is our whole nameplate, "bar"
-- is the health bar inside it, "plate" is the game's own nameplate. The bar is
-- needed by one place, "over the bar": a label on the bar has to travel with
-- the bar rather than with the box in which a row for the name is also set
-- aside above the bar.
local ANCHORS = {
    name = {
        -- The name's row stands above the health bar, at the bar's height
        -- plus the gap. Written with the same points and the same numbers it
        -- stood with in the display before the positions existed — not "the
        -- same to look at" but by the same corner: the suite compares the
        -- anchor by the point's name rather than by coordinates.
        top = function(geom)
            return "frame", "BOTTOMLEFT", "BOTTOMLEFT", 0, geom.height + geom.gap
        end,
        over = function(geom)
            return "bar", "LEFT", "LEFT", geom.edge, 0
        end,
        bottom = function(geom)
            return "frame", "TOPLEFT", "BOTTOMLEFT", 0, -geom.gap
        end,
    },
    level = {
        top = function(geom)
            return "frame", "BOTTOMRIGHT", "BOTTOMRIGHT", -geom.edge,
                geom.height + geom.gap
        end,
        over = function(geom)
            return "bar", "RIGHT", "RIGHT", -geom.edge, 0
        end,
        bottom = function(geom)
            return "frame", "TOPRIGHT", "BOTTOMRIGHT", -geom.edge, -geom.gap
        end,
    },
    cast = {
        bottom = function(geom)
            return "frame", "TOPLEFT", "BOTTOMLEFT", 0, -geom.gap
        end,
        top = function(geom)
            return "frame", "BOTTOMLEFT", "TOPLEFT", 0, geom.gap
        end,
    },
    auras = {
        -- The icons go in a row to the right from the nameplate's edge: the
        -- step is an icon's side plus the gap. An icon's index arrives in Spec
        -- separately and does not reach the plan: the plan is one for every
        -- nameplate, while the index is each one's own.
        top = function(geom, index)
            return "frame", "BOTTOMLEFT", "TOPLEFT",
                (index - 1) * geom.step, geom.gap
        end,
        bottom = function(geom, index)
            return "frame", "TOPLEFT", "BOTTOMLEFT",
                (index - 1) * geom.step, -geom.gap
        end,
    },
    quest = {
        left = function(geom)
            return "frame", "RIGHT", "LEFT", -geom.gap, 0
        end,
        right = function(geom)
            return "frame", "LEFT", "RIGHT", geom.gap, 0
        end,
    },
    plate = {
        center = function() return "plate", "CENTER", "CENTER", 0, 0 end,
    },
    -- The health bar. The player cannot move it — it is the thing the other
    -- parts' sides are measured from — but it too goes through the same door:
    -- a second way of anchoring a nameplate's part would be that very second
    -- owner of the positions.
    bar = {
        ground = function() return "frame", "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 end,
    },
}

--- Where one part stands.
--
-- The only place in the whole module where a position is decided. A pure
-- function: it allocates not one table, knows nothing of frames, and gives its
-- answer as five values.
--
-- @param plan table|nil the plan from Arrange.Compile; nil means the defaults
-- @param part string the part's name
-- @param geom table the measurements: width, height, gap, edge, step
-- @param index number|nil the aura icon's index
-- @return string|nil what to anchor to: "frame", "bar" or "plate"
-- @return string|nil our part's point
-- @return string|nil the point of what we anchor to
-- @return number the horizontal offset
-- @return number the vertical offset
function Arrange.Spec(plan, part, geom, index)
    local anchors = ANCHORS[part]
    if anchors == nil then return nil end

    local entry = type(plan) == "table" and plan[part] or nil
    local place
    if type(entry) == "table" then
        place = Arrange.Place(part, entry.place)
    end
    if place == nil then
        -- The bar and an unfamiliar saved value arrive here the same way:
        -- the part's first place is taken, and for the bar that is its only
        -- one.
        place = Arrange.Default(part)
        if place == nil then
            for name in pairs(anchors) do place = place or name end
        end
    end

    local rule = anchors[place]
    if rule == nil then return nil end

    local rel, point, relPoint, x, y = rule(geom, tonumber(index) or 1)

    if type(entry) == "table" then
        x = x + entry.x
        y = y + entry.y
    end

    return rel, point, relPoint, x, y
end

-- === Editing the positions by the player ===================================
--
-- The same two things as with the rules: the record lives in the module's
-- settings, and it is changed from here. The settings display does not write
-- into the saved variables itself — otherwise an edit would have to be tested
-- together with the window.

--- A part's record in the settings, created when needed.
-- @param settings table|nil
-- @param part string|nil
-- @return table|nil
function Arrange.Entry(settings, part)
    if type(settings) ~= "table" or not KNOWN[part] then return nil end

    local store = settings.arrange
    if type(store) ~= "table" then
        store = {}
        settings.arrange = store
    end

    local entry = store[part]
    if type(entry) ~= "table" then
        entry = {}
        store[part] = entry
    end

    return entry
end

--- Put a part in a place.
-- @param settings table|nil
-- @param part string|nil
-- @param place any
-- @return boolean whether it was written
function Arrange.SetPlace(settings, part, place)
    if not Arrange.Has(part, place) then return false end

    local entry = Arrange.Entry(settings, part)
    if entry == nil then return false end

    entry.place = place
    return true
end

--- Offset a part horizontally or vertically.
-- @param settings table|nil
-- @param part string|nil
-- @param axis string "x" or "y"
-- @param value any
-- @return boolean whether it was written
function Arrange.SetOffset(settings, part, axis, value)
    if axis ~= "x" and axis ~= "y" then return false end

    local entry = Arrange.Entry(settings, part)
    if entry == nil then return false end

    entry[axis] = Arrange.Offset(value)
    return true
end

--- Reset one part to its default.
-- The record is erased entirely rather than overwritten with the defaults: a
-- record saying "the same place, zero offsets" is the same trace of an edit,
-- only invisible, and the comparison "has this part been touched" would stop
-- working.
-- @param settings table|nil
-- @param part string|nil
-- @return boolean whether there was anything to reset
function Arrange.Reset(settings, part)
    if type(settings) ~= "table" or not KNOWN[part] then return false end

    local store = settings.arrange
    if type(store) ~= "table" or store[part] == nil then return false end

    store[part] = nil
    return true
end

--- Reset the positions entirely.
-- @param settings table|nil
-- @return boolean whether there was anything to reset
function Arrange.ResetAll(settings)
    if type(settings) ~= "table" then return false end

    local store = settings.arrange
    if type(store) ~= "table" or next(store) == nil then return false end

    settings.arrange = {}
    return true
end
