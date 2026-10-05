local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("infopanel")

-- Formatting the info panel's values.
--
-- There is not one call into the game here and not one event subscription.
-- Everything in this file is pure functions: numbers in, and out comes the
-- string the player reads in a cell. That is why the file is separated from
-- the rest of the module: this is exactly where the mistakes live (gold
-- assembled from the wrong remainder; an afternoon hour shown as an early
-- morning one; a percentage computed out of zero), and exactly where they are
-- caught outside the client.
--
-- The rule for the whole file: a value comes from the game or from
-- SavedVariables, which means anything at all can come. Not one function here
-- raises on nil, on a string or on NaN — a dash is returned instead. An empty
-- cell in the panel looks like a failure; a dash looks like missing data.

-- Writing a number is the core's business (Darken:GetFormat(), contract
-- version 13, docs/module-api.md). Asked for once, while the file is read: the
-- same table is returned every time, and fetching it for every repaint of a
-- cell would mean paying for one and the same thing. This is not the skin and
-- not the media — those are asked for in place, because they change with the
-- player's settings; the rule for writing a number never changes.
--
-- A core older than version 13 does not have this door at all: abbreviation
-- and percentages appeared in the twelfth, rounding in the thirteenth. Then
-- ns.Format is not created at all, and InfoPanel.lua says one readable line to
-- the player and leaves: a silent Lua error in a file's body is the worst of
-- answers.
--
-- All three names are asked for rather than one standing for all: a version 12
-- core returns a table without Round, and a panel that took it would raise not
-- here but on the first drawing of the frame rate — that is, a second after
-- entering the world and without one word about the cause.
local fmt = type(Darken) == "table"
    and type(Darken.GetFormat) == "function"
    and Darken:GetFormat() or nil
if type(fmt) ~= "table" or type(fmt.Abbreviate) ~= "function"
    or type(fmt.Percent) ~= "function" or type(fmt.Round) ~= "function" then
    return
end

local Format = {}
ns.Format = Format

-- The core's number writing exposed under its own name: the test compares it
-- with the core's by the identity of the table and the functions rather than
-- by their answers matching. A copy accidentally created afresh would become
-- visible at once rather than at the first number that diverged.
Format.Numbers = fmt

-- What is shown in place of a value that does not exist. One for the whole
-- module: two different placeholders in neighbouring cells would read as two
-- different states.
local NONE = "--"
Format.NONE = NONE

--- Whether this really is a number.
-- As a function of its own, because it has to be checked in every function of
-- the file: NaN equals itself only in the definition, not in Lua.
-- @param value any
-- @return boolean
local function isNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end
Format.IsNumber = isNumber

--- The abbreviated spelling of a large number: 1234 becomes 1.2k.
-- Experience and reputation numbers do not fit whole into a cell fifty pixels
-- wide, and the panel lives by being read at a glance.
--
-- The thresholds, the format strings and the suffix are no longer here: the
-- core computes all of that (Darken:GetFormat().Abbreviate). Three numbers
-- used to stand here as a copy reconciled by hand — and a copy reconciled by
-- hand is a divergence deferred.
--
-- What stayed ours, and stayed deliberately: what input the panel counts as a
-- number. The core accepts a numeric string (to it "50" is fifty); the panel
-- never does: a value reaches a cell from a foreign readout of the
-- LibDataBroker standard, and a string from there means not a number but
-- somebody else's mistake. The filter stands here, before the core is called,
-- so the move could not weaken it: what was a dash stayed a dash.
-- @param value number|nil
-- @return string
function Format.Short(value)
    if not isNumber(value) then return NONE end
    return fmt.Abbreviate(value) or NONE
end

--- The player's money, in coins.
-- The letters come from the client (GOLD_AMOUNT_SYMBOL and its neighbours)
-- rather than being written here as strings: on a non-English client the
-- letters are different, and a pair of our own would diverge from the game
-- silently.
--
-- Leading zero denominations are not shown, trailing ones are: 12g 0s 5c reads
-- as a sum, while 12g 5c reads as a parsing error.
-- @param copper number|nil the amount in copper
-- @param symbols table|nil { gold = "g", silver = "s", copper = "c" }
-- @return string
function Format.Money(copper, symbols)
    if not isNumber(copper) then return NONE end

    local gold = type(symbols) == "table" and symbols.gold or "g"
    local silver = type(symbols) == "table" and symbols.silver or "s"
    local penny = type(symbols) == "table" and symbols.copper or "c"

    local sign = copper < 0 and "-" or ""
    local total = math.floor(math.abs(copper))

    local g = math.floor(total / 10000)
    local s = math.floor((total % 10000) / 100)
    local c = total % 100

    if g > 0 then
        return string.format("%s%d%s %d%s %d%s", sign, g, gold, s, silver, c, penny)
    elseif s > 0 then
        return string.format("%s%d%s %d%s", sign, s, silver, c, penny)
    end

    return string.format("%s%d%s", sign, c, penny)
end

--- A share, as a percentage.
--
-- The core computes it (Darken:GetFormat().Percent). Two decisions stayed
-- here, and both are the panel's decisions about its own cell rather than part
-- of the arithmetic:
--
--   the input filter — the same as Format.Short's: only a number counts as a
--   number, and "nothing to compute from" is a dash rather than a zero. On an
--   empty maximum the core answers zero, and for a label on a bar that is
--   right: zero per cent is a value there. In a cell a zero would mean
--   "durability 0%", that is, a lie instead of missing data;
--
--   the clamp to zero — it was here, and the core deliberately did not take
--   it. Ratio never returns a negative number outwards. That is written at the
--   place of the decision rather than inside the formatting, which is why it
--   can be seen.
--
-- @param current number|nil
-- @param maximum number|nil
-- @return number|nil whole percent; nil when there is nothing to compute
--     from
function Format.Ratio(current, maximum)
    if not isNumber(current) or not isNumber(maximum) then return nil end
    if maximum <= 0 then return nil end

    local percent = fmt.Percent(current, maximum)
    if percent < 0 then percent = 0 end
    return percent
end

--- The percentage as a string.
-- @param current number|nil
-- @param maximum number|nil
-- @return string
function Format.Percent(current, maximum)
    local percent = Format.Ratio(current, maximum)
    if percent == nil then return NONE end
    return percent .. "%"
end

--- The equipment's durability: the lowest of the worn items.
-- The lowest specifically rather than the average: the player needs to know
-- when the first item will break, and an average over ten items hides one
-- broken one.
-- @param slots table|nil array of { current = number, maximum = number }
-- @return number|nil the percentage; nil when nothing has durability
function Format.Durability(slots)
    if type(slots) ~= "table" then return nil end

    local lowest
    for i = 1, #slots do
        local slot = slots[i]
        if type(slot) == "table" then
            local percent = Format.Ratio(slot.current, slot.maximum)
            if percent ~= nil and (lowest == nil or percent < lowest) then
                lowest = percent
            end
        end
    end

    return lowest
end

--- The free room in the bags.
-- @param free number|nil
-- @param total number|nil
-- @return string
function Format.Bags(free, total)
    if not isNumber(free) then return NONE end
    if not isNumber(total) or total <= 0 then
        return tostring(math.floor(free))
    end
    return string.format("%d/%d", math.floor(free), math.floor(total))
end

--- The connection's latency.
-- Two numbers rather than one: the game returns the latency to one's own realm
-- and to the world server separately, and the difference between them is half
-- the readout's meaning.
-- @param home number|nil
-- @param world number|nil
-- @return string
function Format.Latency(home, world)
    local h = isNumber(home) and math.floor(home) or nil
    local w = isNumber(world) and math.floor(world) or nil

    if h and w and h ~= w then return string.format("%d/%d ms", h, w) end
    if h then return string.format("%d ms", h) end
    if w then return string.format("%d ms", w) end
    return NONE
end

--- The frame rate.
--
-- The panel's only fractional quantity: the game returns 59.6 while 60 fps is
-- written into the cell. The rounding is the core's
-- (Darken:GetFormat().Round, contract version 13). A body of our own used to
-- lie here — the last copy of the number-writing rule to survive the
-- reconciliation of version 12 — and it matched the core's line for line. The
-- input filter stays ours, as in Short and Ratio: on rubbish the core answers
-- zero, and a 0 fps in the cell would read as a game that had stopped, so a
-- dash stands here.
-- @param fps number|nil
-- @return string
function Format.Fps(fps)
    if not isNumber(fps) then return NONE end
    return string.format("%d fps", fmt.Round(fps))
end

--- The clock.
-- @param hour number|nil 0..23
-- @param minute number|nil 0..59
-- @param second number|nil 0..59
-- @param twelve boolean|nil the twelve-hour form
-- @param seconds boolean|nil whether to show the seconds
-- @return string
function Format.Clock(hour, minute, second, twelve, seconds)
    if not isNumber(hour) or not isNumber(minute) then return NONE end

    local h = math.floor(hour) % 24
    local m = math.floor(minute) % 60
    local s = isNumber(second) and math.floor(second) % 60 or 0

    local suffix = ""
    if twelve then
        -- Midnight and noon are the two cases people get wrong: hour 0 is
        -- 12 AM and hour 12 is 12 PM, neither of them a zero.
        suffix = h < 12 and " AM" or " PM"
        h = h % 12
        if h == 0 then h = 12 end
    end

    if seconds then
        return string.format("%02d:%02d:%02d%s", h, m, s, suffix)
    end
    return string.format("%02d:%02d%s", h, m, suffix)
end

-- The ways of showing experience. The keys go into SavedVariables, so they
-- are words rather than numbers: a number in a saved profile cannot be read by
-- eye and does not survive the list being rearranged.
local XP_MODES = { current = true, percent = true, remaining = true }
Format.XP_MODES = XP_MODES

--- Experience.
-- @param current number|nil
-- @param maximum number|nil
-- @param rested number|nil the rested reserve, when there is one
-- @param mode string|nil current, percent or remaining
-- @return string
function Format.Experience(current, maximum, rested, mode)
    if not isNumber(current) or not isNumber(maximum) or maximum <= 0 then
        return NONE
    end

    if not XP_MODES[mode] then mode = "current" end

    local text
    if mode == "percent" then
        text = Format.Percent(current, maximum)
    elseif mode == "remaining" then
        text = Format.Short(maximum - current)
    else
        text = Format.Short(current) .. "/" .. Format.Short(maximum)
    end

    -- The rested reserve is appended to all three forms: it is a separate
    -- quantity rather than another way of showing the same one.
    if isNumber(rested) and rested > 0 then
        text = text .. " +" .. Format.Percent(rested, maximum)
    end

    return text
end

--- Reputation with the watched faction.
-- @param name string|nil the faction's name
-- @param standing string|nil the standing's name, such as Friendly
-- @param value number|nil how much has been earned in the current standing
-- @param maximum number|nil how much has to be earned
-- @param mode string|nil percent or current
-- @return string
function Format.Reputation(name, standing, value, maximum, mode)
    if type(name) ~= "string" or name == "" then return NONE end

    local amount
    if mode == "percent" then
        amount = Format.Percent(value, maximum)
    else
        local percent = Format.Ratio(value, maximum)
        if percent == nil then
            amount = nil
        else
            amount = Format.Short(value) .. "/" .. Format.Short(maximum)
        end
    end

    if amount == nil or amount == NONE then
        if type(standing) == "string" and standing ~= "" then
            return name .. ": " .. standing
        end
        return name
    end

    return name .. ": " .. amount
end

--- A cell's whole caption, such as Gold: 12g 3s.
-- One function for every cell, and our readouts pass through it exactly as
-- other people's do. An empty label means the cell shows the value alone.
-- @param label string|nil
-- @param text string|nil
-- @return string
function Format.Cell(label, text)
    local value = type(text) == "string" and text ~= "" and text or nil
    local title = type(label) == "string" and label ~= "" and label or nil

    if title and value then return title .. ": " .. value end
    if value then return value end
    if title then return title end
    return NONE
end
