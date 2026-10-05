local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("auras")

-- The layout of the grid of icons, and the text of the remaining time.
--
-- Pure arithmetic and the only place where it is done. It was moved here not
-- for beauty's sake: the numbers come from SavedVariables, into which anything
-- at all finds its way over the years — somebody's edit of the file, a setting
-- from a future version, plain rubbish. An icon size of "abc" or a
-- per-row count of -3 inside game code would mean a Lua error on every change
-- of auras, that is, in combat; here they mean a return to the default, and
-- that is tested outside the client.
--
-- Here also lives the rule the whole module was written for: turning the
-- remaining time into a label. It returns not only the label but also the
-- moment until which that label will not change. Without the second value
-- every icon would have to be updated on every frame — precisely what addons
-- burn frames on.

local Layout = {}
ns.Layout = Layout

-- The bounds of what makes sense, and the defaults. The settings section's
-- sliders use these same numbers: two lists of bounds would diverge silently,
-- and the player would get a slider part of whose travel changes nothing.
local BOUNDS = {
    size    = { min = 12, max = 64, default = 30 },
    perRow  = { min = 1,  max = 24, default = 12 },
    spacing = { min = 0,  max = 24, default = 4  },

    -- The grid's numeric position. It no longer has sliders: the core's
    -- mover places the grid, by the same handles the player places everything
    -- else on screen with. The bounds stayed here for one thing — migrating an
    -- old profile onto the mover (Layout.MoverPoint): a player who placed the
    -- grid with sliders has these very numbers in their profile, and they have
    -- to be read by the same clamping that wrote them.
    offsetX = { min = -1200, max = 1200, default = -200 },
    offsetY = { min = -1200, max = 1200, default = -20  },
}
Layout.BOUNDS = BOUNDS

-- The directions the grid grows in. The first word is where the rows go, the
-- second is where a row grows. The list is closed: the value goes into the
-- profile, and an unfamiliar name has to mean the default rather than an empty
-- layout.
--
-- The anchor point for each direction is here too. It is not derived from the
-- name at the call site: one direction has to give one corner, and two
-- derivations would diverge at the very first edit.
local DIRECTIONS = {
    downleft  = { x = -1, y = -1, point = "TOPRIGHT"    },
    downright = { x =  1, y = -1, point = "TOPLEFT"     },
    upleft    = { x = -1, y =  1, point = "BOTTOMRIGHT" },
    upright   = { x =  1, y =  1, point = "BOTTOMLEFT"  },
}
Layout.DIRECTIONS = DIRECTIONS

local DEFAULT_DIRECTION = "downleft"
Layout.DEFAULT_DIRECTION = DEFAULT_DIRECTION

--- Bring one number within its setting's bounds.
-- Not a number means the default: a value that cannot be produced with the
-- slider did not come from the player. A number beyond a bound is clamped to
-- it: there is no reason to lose the player's instruction over one unit too
-- many.
-- @param key string the setting's name
-- @param value any the value from the profile
-- @return number
function Layout.Clamp(key, value)
    local spec = BOUNDS[key]
    if not spec then return 0 end

    local number = tonumber(value)
    if not number or number ~= number then return spec.default end

    if number < spec.min then return spec.min end
    if number > spec.max then return spec.max end
    return number
end

--- The direction of growth from the setting.
-- @param value any the value from the profile
-- @return string a direction name from DIRECTIONS
function Layout.Direction(value)
    if type(value) == "string" and DIRECTIONS[value] then return value end
    return DEFAULT_DIRECTION
end

--- Every numeric layout setting at once.
-- @param settings table|nil the module's settings section
-- @return number the icon's size
-- @return number icons per row
-- @return number the gap
-- @return string the direction
function Layout.Grid(settings)
    settings = type(settings) == "table" and settings or {}

    -- The per-row count is rounded down: half an icon in a row does not
    -- exist, and a fraction in the profile would mean a row whose length
    -- cannot be stated.
    local perRow = math.floor(Layout.Clamp("perRow", settings.perRow))
    if perRow < BOUNDS.perRow.min then perRow = BOUNDS.perRow.min end

    return Layout.Clamp("size", settings.size),
           perRow,
           Layout.Clamp("spacing", settings.spacing),
           Layout.Direction(settings.direction)
end

--- A block's anchor point for a direction of growth.
-- @param direction any
-- @return string the frame's corner
function Layout.Anchor(direction)
    return DIRECTIONS[Layout.Direction(direction)].point
end

--============================================================================
-- The grid's origin: the thing the mover moves
--============================================================================

-- The core's mover places the grid, and what it moves is one small frame — the
-- origin, to whose corner both blocks are anchored. The blocks themselves are
-- not handed to the mover, and that is no detail: their size changes with
-- every buff that appears and ends, while the mover holds a frame by its
-- centre against the screen's centre. A block handed to the mover directly
-- would spread from its own centre in both directions on every change of auras
-- — that is, precisely what the grid has no right to do: the icons have to
-- stand where the player remembers them.
--
-- So the origin's size is constant and depends on no setting at all. It exists
-- exactly so that there is something to grab with the mouse on the mover's
-- overlay and so that the label on the handle fits.
--
-- The default is the very one the sliders held before the mover: the screen's
-- top right corner, two hundred pixels left and twenty down. A fresh install
-- does not move by one pixel because of the switch to the mover, and that is a
-- condition of the work.
local ORIGIN = {
    w     = 120,
    h     = 24,
    point = DIRECTIONS[DEFAULT_DIRECTION].point,
    x     = BOUNDS.offsetX.default,
    y     = BOUNDS.offsetY.default,
}
Layout.ORIGIN = ORIGIN

--- A rectangle's corner offset from its centre, horizontally.
-- @param point string the corner
-- @param width number the width
-- @return number
local function cornerX(point, width)
    if point:find("LEFT", 1, true) then return -width / 2 end
    if point:find("RIGHT", 1, true) then return width / 2 end
    return 0
end

--- A rectangle's corner offset from its centre, vertically.
-- @param point string the corner
-- @param height number the height
-- @return number
local function cornerY(point, height)
    if point:find("TOP", 1, true) then return height / 2 end
    if point:find("BOTTOM", 1, true) then return -height / 2 end
    return 0
end

--- Convert the grid's old numeric position into the mover's position.
--
-- A pure function and the only place where this conversion is done. It is
-- needed once in a player's life — at the first launch of the build in which
-- the mover places the grid — and getting it wrong is not allowed: there will
-- be no second time, and the grid will have travelled.
--
-- Here is what it is computed from. The old position is a block corner's
-- offset from the same corner of the screen. The mover stores the offset of
-- the moved frame's **centre** from the **centre** of the screen, because that
-- is the only point that stays itself when the resolution changes. So one has
-- to add to the old offset where the screen's corner lies relative to its
-- centre, and subtract where the same corner of the origin lies relative to
-- its centre.
--
-- The screen's size arrives from outside: it is known only in the game, while
-- the decision about the conversion has to be testable without it.
--
-- @param point any the block's anchor corner (Layout.Anchor)
-- @param offsetX any the old horizontal offset
-- @param offsetY any the old vertical offset
-- @param screenW any the screen's width in UIParent units
-- @param screenH any the screen's height
-- @param width any the origin's width
-- @param height any the origin's height
-- @return number the centre's offset to the right of the screen's centre
-- @return number the centre's offset above the screen's centre
function Layout.MoverPoint(point, offsetX, offsetY, screenW, screenH,
                           width, height)
    if type(point) ~= "string" or point == "" then point = ORIGIN.point end

    local dx = tonumber(offsetX) or 0
    local dy = tonumber(offsetY) or 0
    local sw = tonumber(screenW) or 0
    local sh = tonumber(screenH) or 0
    local ow = tonumber(width)  or ORIGIN.w
    local oh = tonumber(height) or ORIGIN.h

    return cornerX(point, sw) + dx - cornerX(point, ow),
           cornerY(point, sh) + dy - cornerY(point, oh)
end

--- Whether the saved data holds the old shape — the one where the grid was
--- placed by numbers.
--
-- The **presence of the keys** is asked about rather than their value, and
-- that is the decisive detail. On leaving the game AceDB strips out of the
-- saved variables everything equal to the declared default: a player who left
-- the grid at its defaults left the game without these keys, and "the value
-- differs from the default" gives no answer. But "the key exists at all" does:
-- the new shape neither declares nor writes these keys, so they can come from
-- nowhere but an old profile.
--
-- Such data has no shape number either: before the mover the module did not
-- number its shape. So the number is assigned here, and assigned once — the
-- core (handle:Migrate) treats unnumbered data as fresh and simply gives it
-- the target number.
--
-- @param data any the module's saved data
-- @return boolean
function Layout.Legacy(data)
    if type(data) ~= "table" then return false end
    if data.version ~= nil then return false end
    return data.offsetX ~= nil or data.offsetY ~= nil
end

--- One icon's place in the grid.
--
-- The count starts from the block's anchor point (Layout.Anchor), so the
-- offsets are always "from the corner inwards": the first icon stands exactly
-- in the corner, and the direction of growth sets the signs.
--
-- @param index number the icon's number, from one
-- @param perRow number icons per row
-- @param size number the icon's size
-- @param spacing number the gap
-- @param direction any the direction of growth
-- @return number the horizontal offset
-- @return number the vertical offset
function Layout.Place(index, perRow, size, spacing, direction)
    local n = tonumber(index)
    if not n or n < 1 then n = 1 end
    n = math.floor(n)

    local columns = math.floor(tonumber(perRow) or BOUNDS.perRow.default)
    if columns < 1 then columns = 1 end

    local cell = tonumber(size) or BOUNDS.size.default
    local gap  = tonumber(spacing) or BOUNDS.spacing.default
    if gap < 0 then gap = 0 end

    local step   = cell + gap
    local column = (n - 1) % columns
    local row    = math.floor((n - 1) / columns)

    local way = DIRECTIONS[Layout.Direction(direction)]
    return way.x * column * step, way.y * row * step
end

--- An icon's shift towards the centre of its cell.
--
-- The grid's cell is one for everybody and is computed from the common icon
-- size: an icon's place (Layout.Place), a block's size (Layout.Block) and the
-- inset for the next block (Layout.Advance) know nothing about rules for a
-- single aura and must not. Otherwise the set of auras, which changes
-- constantly in combat, would move the whole grid every time a rule applied —
-- that is, precisely what the grid has no right to do: the icons have to stand
-- where the player remembers them.
--
-- So an icon of a different size stays in its cell and takes its centre. The
-- count starts from the anchor corner (Layout.Anchor), and so the direction of
-- growth sets the shift's sign: a smaller icon moves inwards into the cell, a
-- larger one spills out of it equally on both sides.
--
-- @param cell any the cell's size, that is, the common icon size
-- @param actual any this icon's size
-- @param direction any the direction of growth
-- @return number the horizontal shift
-- @return number the vertical shift
function Layout.Inset(cell, actual, direction)
    local box = tonumber(cell)
    if not box or box ~= box then box = BOUNDS.size.default end

    local own = tonumber(actual)
    if not own or own ~= own then own = box end

    local half = (box - own) / 2
    if half == 0 then return 0, 0 end

    local way = DIRECTIONS[Layout.Direction(direction)]
    return way.x * half, way.y * half
end

--- The number the grid's second block starts at.
--
-- Other people's effects start on a new row rather than continuing the row of
-- one's own: otherwise the "separation" is visible only by the order, that is,
-- not visible at all. Zero effects of one's own do not eat a row — the block
-- of other people's then starts at the first place.
--
-- @param count number how many icons are in the first block
-- @param perRow number icons per row
-- @return number the number of the second block's first icon, from one
function Layout.Offset(count, perRow)
    local n = math.floor(tonumber(count) or 0)
    if n < 1 then return 1 end

    local columns = math.floor(tonumber(perRow) or BOUNDS.perRow.default)
    if columns < 1 then columns = 1 end

    return math.ceil(n / columns) * columns + 1
end

--- The size of the space the grid takes up.
-- The holder frame needs it: without a size of its own it does not catch the
-- mouse and is of no use to a future mover.
-- @param count number the number of icons
-- @param perRow number icons per row
-- @param size number the icon's size
-- @param spacing number the gap
-- @return number the width
-- @return number the height
function Layout.Block(count, perRow, size, spacing)
    local n = math.floor(tonumber(count) or 0)
    if n < 0 then n = 0 end

    local columns = math.floor(tonumber(perRow) or BOUNDS.perRow.default)
    if columns < 1 then columns = 1 end

    local cell = tonumber(size) or BOUNDS.size.default
    local gap  = tonumber(spacing) or BOUNDS.spacing.default
    if gap < 0 then gap = 0 end

    if n == 0 then return cell, cell end

    local wide = n < columns and n or columns
    local rows = math.ceil(n / columns)

    return wide * cell + (wide - 1) * gap,
           rows * cell + (rows - 1) * gap
end

--- How far to move on for the grid's next block.
--
-- An empty block takes no space at all. Without this rule a filter that
-- removed every buff would leave a hole one icon tall on screen, and the
-- player would read it as "something is there but did not draw". Only a block
-- itself gives the space for a block.
--
-- The gap is taken double: between two blocks it has to be more noticeable
-- than between two rows inside a block, or the two blocks read as one.
--
-- @param count number how many icons are in the block
-- @param height number the block's height (Layout.Block)
-- @param spacing number the gap
-- @return number
function Layout.Advance(count, height, spacing)
    local n = math.floor(tonumber(count) or 0)
    if n < 1 then return 0 end

    local tall = tonumber(height) or 0
    local gap  = tonumber(spacing) or BOUNDS.spacing.default
    if gap < 0 then gap = 0 end

    return tall + gap * 2
end

-- The units of the time label, from the largest to the smallest. Each has a
-- threshold of its own, and it is not one: 60m instead of 1h reads worse, and
-- 3600s does not read at all.
local HOUR   = 3600
local MINUTE = 60

--- The label of the remaining time, and the moment until which it will not
--- change.
--
-- The second value is the whole point of this function. The label 17 holds
-- exactly until the instant 16 seconds are left; until then there is no reason
-- to touch the icon. The caller collects such moments and wakes for the
-- nearest one rather than walking every icon on every frame.
--
-- @param remaining any how many seconds are left
-- @return string the label; empty when there is nothing to show
-- @return number|nil seconds until the label changes; nil means it will never
--     change
function Layout.Remaining(remaining)
    local left = tonumber(remaining)
    if not left or left ~= left then return "", nil end
    if left <= 0 then return "", nil end

    local unit, suffix
    if left >= HOUR then
        unit, suffix = HOUR, "h"
    elseif left >= MINUTE then
        unit, suffix = MINUTE, "m"
    else
        unit, suffix = 1, ""
    end

    -- Rounded up: while even a fraction of a second is left, the next whole
    -- number is shown. A label of 0 on an aura that is still alive is more
    -- confusing than one unit too many.
    local value = math.ceil(left / unit)

    -- The label will change when the remainder falls to (value-1) units. For
    -- 5.4 seconds that is 0.4 seconds rather than "in a second": otherwise the
    -- labels drift from the real time by half a unit and accumulate error.
    local delay = left - (value - 1) * unit
    if delay <= 0 then delay = unit end

    return tostring(value) .. suffix, delay
end

--- The label for the number of stacks.
-- One stack is not a label: a 1 on every icon takes up room and says nothing.
-- @param count any
-- @return string
function Layout.Stacks(count)
    local n = tonumber(count)
    if not n or n ~= n or n < 2 then return "" end
    return tostring(math.floor(n))
end
