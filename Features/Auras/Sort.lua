local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("auras")

-- The order of the icons, and separating one's own effects from others'.
--
-- Pure rules over a list of aura records. The record is assembled by the
-- reader (Auras.lua) out of what the game gave, and nothing about the game is
-- known here — only the fields. That way what the player sees on screen is
-- tested outside the client: why this icon stands before that one.
--
-- The record's shape both rules rely on:
--   order   number  the index the game gave the aura under; unique in a list
--   expires number  the moment it ends; nil or 0 means an aura with no
--                   duration
--   mine    boolean applied by the player

local Sort = {}
ns.Sort = Sort

--- An aura with no duration.
-- A function of its own, because "no duration" arrives in two different
-- shapes: the game gives now nil, now zero, and differently on different
-- clients.
-- @param aura table
-- @return boolean
local function endless(aura)
    local expires = tonumber(aura and aura.expires)
    return not expires or expires <= 0
end

--- The order of two auras.
--
-- The rule in full: first what is about to end, then what never ends; at an
-- equal duration, in the order the game gave them.
--
-- The last link is mandatory and is not decoration. Without it two auras with
-- one duration (which is ordinary: one cast applies two effects) swap places
-- from call to call, and the icons jump about on screen for no reason at
-- all.
--
-- @param a table
-- @param b table
-- @return boolean
local function before(a, b)
    local endlessA, endlessB = endless(a), endless(b)
    if endlessA ~= endlessB then
        -- What is ending comes first: an icon being watched must not drift
        -- to the tail behind a dozen everlasting blessings.
        return endlessB
    end

    if not endlessA then
        local ea, eb = tonumber(a.expires), tonumber(b.expires)
        if ea ~= eb then return ea < eb end
    end

    return (tonumber(a.order) or 0) < (tonumber(b.order) or 0)
end

Sort.Before = before

--- Order a list of auras in place.
-- @param list table array of records
-- @return table the same list
function Sort.Order(list)
    if type(list) ~= "table" then return list end
    table.sort(list, before)
    return list
end

--- Split a list into one's own effects and others'.
--
-- The tables for the answer are taken from outside and reused: the split
-- happens on every change of auras, that is, in combat, and two fresh tables
-- there would cost the player frames. The tables passed in are cleared in
-- full — otherwise the tail of the previous list would stay on screen.
--
-- @param list table array of records
-- @param own table|nil a table for one's own
-- @param others table|nil a table for others'
-- @return table one's own
-- @return table others'
function Sort.Split(list, own, others)
    own    = type(own) == "table" and own or {}
    others = type(others) == "table" and others or {}

    for i = #own, 1, -1 do own[i] = nil end
    for i = #others, 1, -1 do others[i] = nil end

    if type(list) ~= "table" then return own, others end

    for i = 1, #list do
        local aura = list[i]
        if type(aura) == "table" then
            if aura.mine then
                own[#own + 1] = aura
            else
                others[#others + 1] = aura
            end
        end
    end

    Sort.Order(own)
    Sort.Order(others)

    return own, others
end
