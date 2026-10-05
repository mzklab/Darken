local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- A nameplate's dimensions, from the settings.
--
-- Pure arithmetic and the only place it is done. Moved here not for elegance:
-- the values come from SavedVariables, where anything ends up over the years —
-- somebody's edit of the file, a setting from a future version, plain
-- rubbish. A width of "abc" or a height of -40 inside the game code would
-- mean a Lua error on every creature that appears, that is, in combat; here
-- they mean a return to the default, and that is tested outside the
-- client.

local Geometry = {}
ns.Geometry = Geometry

-- The bounds of what makes sense, and the defaults. The slider on the
-- settings page uses these same numbers: two lists of bounds would diverge
-- silently, and the player would get a slider part of whose travel changes
-- nothing.
local BOUNDS = {
    width  = { min = 40,  max = 300, default = 110 },
    height = { min = 4,   max = 40,  default = 10  },
    scale  = { min = 0.5, max = 2,   default = 1   },
}
Geometry.BOUNDS = BOUNDS

--- Bring one number within its setting's bounds.
-- A non-number gives the default: a value no slider could produce did not
-- come from the player. A number beyond a bound is clamped to it: there is no
-- reason to lose the player's instruction over one unit too many.
-- @param key string the setting's name
-- @param value any the value from the profile
-- @return number
function Geometry.Clamp(key, value)
    local spec = BOUNDS[key]
    if not spec then return 0 end

    local number = tonumber(value)
    if not number or number ~= number then return spec.default end

    if number < spec.min then return spec.min end
    if number > spec.max then return spec.max end
    return number
end

--- A nameplate's dimensions, by the settings.
-- @param settings table|nil the module's settings section
-- @return number the width
-- @return number the health bar's height
-- @return number the scale
function Geometry.Plate(settings)
    settings = type(settings) == "table" and settings or {}
    return Geometry.Clamp("width",  settings.width),
           Geometry.Clamp("height", settings.height),
           Geometry.Clamp("scale",  settings.scale)
end

--- The layout inside a nameplate.
--
-- The name stands above the bar, the level at its right edge inside. The
-- name's height is computed from the bar's height rather than set by a
-- setting of its own: two independent heights give the player the chance to
-- assemble a nameplate the name does not fit into, and then to hunt for where
-- they did it.
--
-- The gap comes from the styling's spacing scale (the contract,
-- skin.Metrics) rather than being written as a number: one and the same
-- distance on screen must be set by one and the same value.
--
-- @param width number the bar's width
-- @param height number the bar's height
-- @param gap number the gap from the spacing scale
-- @return number the full height of the space taken
-- @return number the height of the name's line
-- @return number the name's offset upwards from the bar
function Geometry.Layout(width, height, gap)
    width  = tonumber(width)  or BOUNDS.width.default
    height = tonumber(height) or BOUNDS.height.default
    gap    = tonumber(gap)    or 2
    if gap < 0 then gap = 0 end

    -- The name's line is never shorter than eight pixels: below that it
    -- cannot be read, while a bar four pixels high is a legitimate
    -- setting.
    local nameHeight = height
    if nameHeight < 8 then nameHeight = 8 end

    return height + gap + nameHeight, nameHeight, gap
end

--- A bar's fill fraction.
-- A function of its own, because a maximum of zero is ordinary: the game
-- gives zero health for a corpse and for a unit it knows nothing about yet. A
-- division by zero would give a NaN, and the bar would stay as it was for the
-- previous unit.
-- @param current any
-- @param maximum any
-- @return number a fraction from 0 to 1
function Geometry.Fill(current, maximum)
    local value = tonumber(current)
    local total = tonumber(maximum)
    if not value or not total or total <= 0 then return 0 end
    if value <= 0 then return 0 end
    if value >= total then return 1 end
    return value / total
end
