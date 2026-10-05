-- The durability module's pure part.
--
-- There is not one call into the game here: the readings arrive as a table,
-- and the answers are a number, a state word and a colour name. The boundary
-- is drawn that way on purpose — the project's specification (section 8) does
-- not accept logic hidden inside an event handler, and there is no other way
-- to test it outside the client.

local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("durability")

local Rules = {}
ns.Rules = Rules

-- The equipment slots that can have durability.
--
-- A slot's number is not somebody else's frame name but the character's
-- permanent slot index: the game itself understands it, and the module has no
-- second such list anywhere. The labels are English, because an English
-- string is the translation key.
Rules.SLOTS = {
    { slot =  1, label = "Head" },
    { slot =  3, label = "Shoulder" },
    { slot =  5, label = "Chest" },
    { slot =  6, label = "Waist" },
    { slot =  7, label = "Legs" },
    { slot =  8, label = "Feet" },
    { slot =  9, label = "Wrist" },
    { slot = 10, label = "Hands" },
    { slot = 16, label = "Main Hand" },
    { slot = 17, label = "Off Hand" },
    { slot = 18, label = "Ranged" },
}

--- A slot's English label, by its number.
-- @param slot number
-- @return string|nil nil when the number is not in the list
function Rules.LabelFor(slot)
    for i = 1, #Rules.SLOTS do
        if Rules.SLOTS[i].slot == slot then return Rules.SLOTS[i].label end
    end
    return nil
end

--- The worst reading of a set.
--
-- The comparison is by multiplication rather than by division: two divisions
-- per step give different answers on equal fractions because of rounding
-- error, and "the worst slot" starts jumping between two items worn equally.
-- @param readings table array of { slot, label, current, maximum }
-- @return table|nil the worst reading
-- @return number how many readings were usable at all
function Rules.Worst(readings)
    if type(readings) ~= "table" then return nil, 0 end

    local worst, counted = nil, 0
    for i = 1, #readings do
        local entry = readings[i]
        local current = type(entry) == "table" and entry.current or nil
        local maximum = type(entry) == "table" and entry.maximum or nil

        if type(current) == "number" and type(maximum) == "number"
            and maximum > 0 then
            counted = counted + 1
            if worst == nil
                or current * worst.maximum < worst.current * maximum then
                worst = entry
            end
        end
    end

    return worst, counted
end

--- The wear percentage, by the core's rule.
--
-- The module has no rounding of its own and must not: writing a number is one
-- thing in this addon (contract version 12), and a second copy beside it
-- would diverge from the first on the day one of the two is edited. A zero
-- maximum is separated from zero per cent before the call — an empty slot and
-- a slot with a broken item are different answers, while the contract answers
-- both with zero.
-- @param current number
-- @param maximum number
-- @return number|nil the percentage; nil when there is no reading
function Rules.Percent(current, maximum)
    if type(current) ~= "number" or type(maximum) ~= "number"
        or maximum <= 0 then
        return nil
    end

    local core = _G.Darken
    if type(core) ~= "table" or type(core.GetFormat) ~= "function" then
        return nil
    end

    return core:GetFormat().Percent(current, maximum)
end

--- The readout's state in one word.
-- @param percent number|nil
-- @param warnBelow number|nil the alarm threshold
-- @return string|nil "broken", "warn", "fine"; nil when there is no
--         reading
function Rules.State(percent, warnBelow)
    if type(percent) ~= "number" then return nil end
    if percent <= 0 then return "broken" end
    if type(warnBelow) == "number" and percent < warnBelow then return "warn" end
    return "fine"
end

-- A palette colour name from the core for each state.
--
-- A module has no right to invent a colour from numbers: a colour is asked of
-- the core or not asked at all. A quiet readout is muted, while the alarming
-- and the broken ones are painted with the palette's alarm colour (warn,
-- contract version 16) — precisely the case it exists for: a number reporting
-- a state the player has to act on.
--
-- Broken differs from alarming not by colour but by the number itself: "0%"
-- reads without a hint, while a second alarming shade would be a second way
-- of saying one and the same thing. The block must not be kept alarming all
-- the time — an alarm that is always lit stops being an alarm — and that is
-- why the block usually does not show the quiet state at all
-- (Rules.Visible).
local TINTS = {
    broken = "warn",
    warn   = "warn",
    fine   = "textDim",
}

--- The palette colour name for a state.
-- @param state string|nil
-- @return string|nil
function Rules.Tint(state)
    return TINTS[state]
end

--- Whether to show the block.
-- @param state string|nil
-- @param alwaysShow boolean|nil
-- @return boolean
function Rules.Visible(state, alwaysShow)
    -- "Always show" outranks the absence of readings.
    --
    -- Empty readings used to override that setting, and it looked like this:
    -- the player ticks the box, nothing appears on screen, and there is
    -- nothing to understand why from — no block, no line, no reason. The
    -- author wrote exactly that: I set Always Show and never saw any line
    -- appear anywhere.
    --
    -- Now the block appears and says in words that there are no readings
    -- (Features/Durability/Durability.lua). An empty block is more honest
    -- than an empty screen: it stands where it belongs, and it can be seen
    -- where to move it.
    if alwaysShow then return true end
    if state == nil then return false end
    return state ~= "fine"
end
