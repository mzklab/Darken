local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- A nameplate's cast bar: the arithmetic of the bar's travel.
--
-- === The chief decision: the bar is not polled ===
--
-- An ordinary cast bar lives on OnUpdate: every frame the time is asked for,
-- divided, written into the bar. On the player's single frame that is
-- unnoticeable. On thirty nameplates it is thirty handlers per frame, and the
-- specification calls the nameplates' performance more important than
-- anything else in the project.
--
-- So our bar does not compute the time at all. The travel across the screen
-- is done by the engine itself: the fill moves by a scale animation from the
-- current fraction to one over the seconds remaining, and C computes it
-- rather than Lua. Our code wakes on the casting events themselves — start,
-- delay, interruption, end — that is, a handful of times per spell rather
-- than sixty times a second.
--
-- This file is the one thing that still has to be computed: which fraction to
-- start from, which to arrive at, and over how many seconds. A pure function
-- of numbers, testable outside the client.
--
-- === The boundary with the cast bars module ===
--
-- That module owns the player's cast bar: the ticks, the network delay, the
-- not-interruptible mark. Nothing here touches its frames, and the other way
-- round: this bar is a child of our nameplate, it does not exist outside an
-- attached nameplate, and not one setting of that module looks in here. The
-- division is written in its own brief: the cast bars on nameplates belong to
-- the nameplate engine.

local Cast = {}
ns.Cast = Cast

-- A scale of zero will not do for the engine: a texture of zero width is not
-- an empty bar but undefined behaviour. The smallest fraction instead of
-- zero.
local EPSILON = 0.001
Cast.EPSILON = EPSILON

-- The cast bar's height in pixels.
local HEIGHT = { min = 2, max = 20, default = 5 }
Cast.HEIGHT = HEIGHT

--- A cast bar's travel.
--
-- The game gives the start and the end in milliseconds (UnitCastingInfo,
-- UnitChannelInfo) while the current time comes in seconds (GetTime). Mixing
-- the units is the very mistake this function closes once and for all: a
-- division by a thousand in the wrong place gives a bar that travels in a
-- millisecond and looks like a flicker.
--
-- A cast travels left to right: from the fraction already elapsed to one. A
-- channel is the opposite, from the fraction remaining down to zero: the
-- spell is being spent rather than gathered.
--
-- @param startMs any the start in milliseconds
-- @param endMs any the end in milliseconds
-- @param now any the current time in seconds
-- @param channel any a channel rather than a cast
-- @return number|nil the fraction to start from (0..1)
-- @return number|nil the fraction to finish at (0..1)
-- @return number|nil how many seconds to travel for
function Cast.Progress(startMs, endMs, now, channel)
    local from = tonumber(startMs)
    local to   = tonumber(endMs)
    local when = tonumber(now)
    if not from or not to or not when then return nil end
    if from ~= from or to ~= to or when ~= when then return nil end

    local total = (to - from) / 1000
    if total <= 0 then return nil end

    local elapsed = when - from / 1000
    if elapsed < 0 then elapsed = 0 end
    if elapsed > total then elapsed = total end

    local remaining = total - elapsed
    local done = elapsed / total

    if channel then
        -- The fraction remaining is what has not been spent yet.
        local left = remaining / total
        if left < EPSILON then left = EPSILON end
        return left, EPSILON, remaining
    end

    if done < EPSILON then done = EPSILON end
    return done, 1, remaining
end

--- Bring the cast bar's height within its bounds.
-- @param value any
-- @return number
function Cast.Height(value)
    local number = tonumber(value)
    if not number or number ~= number then return HEIGHT.default end
    if number < HEIGHT.min then return HEIGHT.min end
    if number > HEIGHT.max then return HEIGHT.max end
    return number
end
