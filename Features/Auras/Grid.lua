local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("auras")

-- The game's standard grid of buffs and debuffs: how to take it away and how
-- to give it back.
--
-- This is the module's most dangerous place, and its danger is one: taking a
-- foreign frame away is easy, while giving it back is possible only if what
-- was taken and in what state was recorded beforehand. So there is not one
-- action here without a record.
--
-- === Why not Hide() and not UnregisterAllEvents() ===
--
-- Hide() does not work by itself: the game shows the grid itself on every
-- change of auras, and a hidden frame will be back on screen in a moment. The
-- usual answer to that is UnregisterAllEvents(), and it is irreversible: the
-- engine does not let one enumerate back what a frame was subscribed to. A
-- module that "switches off" that way does not give the player their
-- interface back until a reload — while the specification demands a return
-- without one.
--
-- So the frame moves to a hidden holder: SetParent onto a frame that is never
-- shown. The game goes on showing the grid and updating it as if nothing
-- happened, but a child of a hidden parent is not visible on screen. The
-- return is the same SetParent back, to the recorded parent, and a Show() if
-- the frame was shown. The subscriptions are not touched at all, because
-- there is no reason to touch them.
--
-- === About combat ===
--
-- The player's aura grid is not protected by the engine, and the move to the
-- holder goes through in combat as it does outside it. That must not be
-- decided by a frame's name — protectedness is inherited from the parent and
-- changes between builds — so the call goes through the core (the contract,
-- handle:Secure), which asks the object itself. On an unprotected frame that
-- means "do it right now".

local Grid = {}
ns.Grid = Grid

--- The grid names a frame actually stands behind on this client, and those
--- frames.
--
-- The module has no list of foreign names of its own: the names arrive as an
-- argument, taken from the core — Darken:GetFrameNames("auras"). The
-- compatibility layer is declared the only place that knows Blizzard's frame
-- names, and a second list beside it would diverge from the client at the
-- very first patch, and diverge silently: the grid would simply stop being
-- moved away, with nobody to say so.
--
-- THE FRAMES COME FROM THERE TOO, AS THE DOOR'S SECOND ANSWER (contract 18),
-- rather than being looked up by name in _G. A name in a group can be a path
-- into a foreign frame, and _G[path] is nil: a module that took a name from
-- the layer and went into the globals with it would get emptiness and
-- silently move nothing away — precisely the failure the layer is written
-- against.
--
-- The selection is still made once more, and it is not redundant: the core
-- returns names that something stands behind, while the grid needs a frame
-- specifically. An empty list of candidates (a client where these windows do
-- not exist at all) gives an empty answer — the module then simply moves
-- nothing away.
--
-- @param candidates table|nil the names from the core
-- @param objects table|nil the objects from the core, one per name
-- @return table array of names
-- @return table array of frames, one per name, in the same order
function Grid.Names(candidates, objects)
    local names, frames = {}, {}
    if type(candidates) ~= "table" then return names, frames end
    if type(objects) ~= "table" then return names, frames end

    for i = 1, #candidates do
        local frame = objects[i]
        if type(frame) == "table" then
            names[#names + 1] = candidates[i]
            frames[#frames + 1] = frame
        end
    end

    return names, frames
end

--- An empty ledger of what was taken.
-- @return table
function Grid.NewState()
    return { records = {}, count = 0 }
end

--- Take one frame of the grid under the hidden holder.
--
-- The record is created before the move and holds everything needed for the
-- return: the former parent and whether the frame was shown. Calling again on
-- the same frame rewrites nothing — otherwise the second record would
-- remember the holder as "the former parent", and the return would give the
-- frame back to nowhere.
--
-- @param state table
-- @param frame table|nil a game frame
-- @param holder table|nil the hidden holder
-- @return boolean whether it was taken now
function Grid.Take(state, frame, holder)
    if type(state) ~= "table" or type(frame) ~= "table" then return false end
    if state.records[frame] ~= nil then return false end

    local parent
    if type(frame.GetParent) == "function" then
        local ok, value = pcall(frame.GetParent, frame)
        if ok then parent = value end
    end

    local shown = true
    if type(frame.IsShown) == "function" then
        local ok, value = pcall(frame.IsShown, frame)
        if ok then shown = value and true or false end
    end

    state.records[frame] = { parent = parent, shown = shown }
    state.count = state.count + 1

    if holder ~= nil and type(frame.SetParent) == "function" then
        pcall(frame.SetParent, frame, holder)
    end
    if type(frame.Hide) == "function" then pcall(frame.Hide, frame) end

    return true
end

--- Whether a frame is held by us.
-- @param state table
-- @param frame table|nil
-- @return table|nil the record
function Grid.Held(state, frame)
    if type(state) ~= "table" or type(frame) ~= "table" then return nil end
    return state.records[frame]
end

--- Put everything taken back where it belongs.
--
-- The return goes by the records rather than by the list of names: a name may
-- have disappeared from the client, while the frame we took has gone nowhere
-- and has to come back. It is shown exactly when it was shown at the moment
-- we took it: a grid the player hid themselves has to stay hidden.
--
-- @param state table
-- @return number how many frames were given back
function Grid.Restore(state)
    if type(state) ~= "table" then return 0 end

    local returned = 0
    for frame, record in pairs(state.records) do
        if record.parent ~= nil and type(frame.SetParent) == "function" then
            pcall(frame.SetParent, frame, record.parent)
        end
        if record.shown then
            if type(frame.Show) == "function" then pcall(frame.Show, frame) end
        end
        state.records[frame] = nil
        returned = returned + 1
    end

    state.count = 0
    return returned
end
