local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("itemlevel")

-- The ledger of items whose details the game has not sent yet.
--
-- This is the module's most important place, and here is why. The game does
-- not give an item's details at once: for an unfamiliar item the client asks
-- the server, and the very first question about its level returns zero. Stop
-- there and the number simply does not appear — and does not appear not for
-- every item but for those the player has not seen yet this session. From
-- outside that looks random: one player has the numbers, another has half of
-- them, and it depends on what they opened earlier. There is nothing to
-- investigate in such a bug report.
--
-- So there is no notion of "an empty cell" here: an item whose level is not
-- known yet is a deferred repaint. It is held against the item's id and will
-- be drawn when the event announcing details for that very id arrives.
--
-- The file is pure: not one call into the game. The records are whatever the
-- caller can repaint itself with; the ledger knows only their keys.

local Pending = {}
ns.Pending = Pending

-- The cap on the number of deferred repaints.
--
-- A bound rather than a hope: the bank, the mail and somebody else's
-- equipment give hundreds of unfamiliar items in a row, and the readiness
-- event for some of them may never arrive — the server stays silent about an
-- item that no longer exists. Without a bound the ledger would grow all
-- session. On overflow the new record is refused rather than an old one
-- discarded: an old one is already being waited for by somebody, while the
-- next pass will draw the new one.
local LIMIT = 500
Pending.LIMIT = LIMIT

--- A fresh ledger.
-- @return table
function Pending.New()
    return { byItem = {}, byKey = {}, count = 0 }
end

--- How many repaints are deferred right now.
-- @param state table
-- @return number
function Pending.Count(state)
    if type(state) ~= "table" then return 0 end
    return state.count or 0
end

--- The record under a key, if one is deferred.
-- @param state table
-- @param key any
-- @return table|nil
function Pending.Held(state, key)
    if type(state) ~= "table" or key == nil then return nil end
    local record = state.byKey[key]
    return record and record.target or nil
end

--- Remove the deferred repaint under a key.
-- @param state table
-- @param key any
-- @return boolean whether there was one
function Pending.Forget(state, key)
    if type(state) ~= "table" or key == nil then return false end

    local record = state.byKey[key]
    if not record then return false end

    state.byKey[key] = nil

    local bucket = state.byItem[record.item]
    if bucket then
        bucket[key] = nil
        if next(bucket) == nil then state.byItem[record.item] = nil end
    end

    state.count = state.count - 1
    return true
end

--- Defer one place's repaint until an item's details are ready.
--
-- The key is a place on screen (a bag slot, an equipment slot) rather than an
-- item: the item in one slot changes, and a second record about that same
-- slot would mean the old one repaints it with contents no longer there. So
-- calling again under the same key replaces the record, including moving it
-- under a different item id.
--
-- @param state table
-- @param itemID any the id of the item whose details are awaited
-- @param key any the key of the place on screen
-- @param target any what to repaint
-- @return boolean whether it was accepted
function Pending.Remember(state, itemID, key, target)
    if type(state) ~= "table" then return false end
    if key == nil or target == nil then return false end

    local item = tonumber(itemID)
    if not item or item ~= item then return false end

    local existing = state.byKey[key]
    if existing then
        -- Under the same id it is merely an updated target; under a
        -- different one, a move.
        if existing.item == item then
            existing.target = target
            state.byItem[item][key] = target
            return true
        end
        Pending.Forget(state, key)
    end

    if state.count >= LIMIT then return false end

    local bucket = state.byItem[item]
    if not bucket then
        bucket = {}
        state.byItem[item] = bucket
    end

    bucket[key] = target
    state.byKey[key] = { item = item, target = target }
    state.count = state.count + 1
    return true
end

--- Take everything that was waiting for this item's details.
--
-- Take rather than read: a record handed over for repainting must not be left
-- in the ledger — the repaint will either show a number or defer itself
-- afresh, and in the second case it puts itself back. Otherwise one item that
-- never arrived would stay in the ledger forever.
--
-- @param state table
-- @param itemID any
-- @return table array of targets
function Pending.Take(state, itemID)
    local out = {}
    if type(state) ~= "table" then return out end

    local item = tonumber(itemID)
    if not item then return out end

    local bucket = state.byItem[item]
    if not bucket then return out end

    -- The keys are collected separately: the table is cleared in the same
    -- pass, and changing a table during a pairs walk over it is a Lua
    -- error.
    local keys = {}
    for key in pairs(bucket) do keys[#keys + 1] = key end

    for i = 1, #keys do
        out[#out + 1] = bucket[keys[i]]
        Pending.Forget(state, keys[i])
    end

    return out
end

--- Forget everything. Switching the module off, a profile change, leaving
--- the world.
-- @param state table
-- @return number how many records there were
function Pending.Wipe(state)
    if type(state) ~= "table" then return 0 end

    local had = state.count or 0
    state.byItem, state.byKey, state.count = {}, {}, 0
    return had
end
