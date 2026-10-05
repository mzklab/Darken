local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- The ledger of what is attached, and the decision to stand aside. Both are
-- pure rules, and both were lifted out here because getting them wrong costs
-- most.
--
-- Why the ledger exists at all. The game reuses nameplates: the very frame
-- that carried a merchant's name a moment ago falls to a hostile boar a second
-- later. There is no list of nameplates — there is a pair of events, "appeared
-- for a unit" and "went away", and everything the module hung on a frame it
-- has to remove itself. A forgotten field means not rubbish in memory but
-- somebody else's name on somebody else's bar, and the player will notice it,
-- not the author.
--
-- So the ledger is built as two maps at once — by unit and by frame — and is
-- tested outside the client: a detachment has to clear both, and attaching a
-- frame that is still recorded for somebody else has to detach the previous
-- one first.

local Engine = {}
ns.Engine = Engine

-- The addons that draw nameplates themselves.
--
-- The same list and the same rule as in the core's skinning, and the copy here
-- is unavoidable: the module lives as a separate addon and does not see the
-- core's insides. Both the addon's name and its global table are checked: an
-- addon may be loaded and have created nothing yet, and it may sit in a folder
-- under a different name. One match is enough.
--
-- The list holds candidates: an unfamiliar name costs nothing, while a missed
-- one costs the player a flickering bar and two engines on one frame.
local FOREIGN = {
    { addon = "Plater",                  global = "Plater"         },
    { addon = "Platynator",              global = "Platynator"     },
    { addon = "TidyPlates",              global = "TidyPlates"     },
    { addon = "TidyPlates_ThreatPlates", global = "ThreatPlates"   },
    { addon = "TidyPlatesContinued",     global = "TidyPlatesCont" },
    { addon = "NeatPlates",              global = "NeatPlates"     },
    { addon = "Kui_Nameplates",          global = "KuiNameplates"  },
    { addon = "nPlates",                 global = "nPlates"        },
}
Engine.FOREIGN = FOREIGN

--- Who in this game draws nameplates besides us.
--
-- A pure function: the list of loaded addons arrives as a function, the
-- globals as a table. Which spelling of the game's API to use is chosen once
-- at the call site.
--
-- The call of the foreign function is guarded: it arrives from outside, and
-- its raising must not take the module's enabling with it. If it raised, we
-- treat the addon as absent: the worst that follows is that we draw our
-- nameplates where we should not, and the player switches the module off
-- themselves.
--
-- @param loaded function|nil (name) -> boolean
-- @param globals table|nil a map of name -> object
-- @return string|nil the foreign addon's name
function Engine.ForeignOwner(loaded, globals)
    for i = 1, #FOREIGN do
        local entry = FOREIGN[i]

        if type(loaded) == "function" then
            local ok, isLoaded = pcall(loaded, entry.addon)
            if ok and isLoaded then return entry.addon end
        end

        if type(globals) == "table" and globals[entry.global] ~= nil then
            return entry.addon
        end
    end

    return nil
end

--- The decision: are we to draw nameplates.
--
-- Three outcomes, and each has a word of its own, because the player needs to
-- know not "yes or no" but why.
--
-- "foreign" — another engine is installed in the game. We stand aside, not it:
-- the foreign addon does not know about us and cannot yield, while two engines
-- on one frame give flickering and errors.
--
-- "off" — the module is switched off in the settings. That is a fresh
-- install's default: a module that is installed but not enabled changes
-- nothing on screen, and the core's skinning of the standard nameplates goes
-- on working.
--
-- "draw" — we draw. Then the core's skinning yields, not us: it is the
-- fallback path for those who have no engine, while the engine is installed
-- deliberately, as a folder of its own.
--
-- @param enabled any the value of the "enabled" setting
-- @param owner string|nil the foreign engine's name
-- @return string "foreign" | "off" | "draw"
-- @return string|nil the foreign engine's name for the "foreign" outcome
function Engine.Decide(enabled, owner)
    if type(owner) == "string" and owner ~= "" then
        return "foreign", owner
    end
    if not enabled then return "off" end
    return "draw"
end

--- An empty ledger.
-- Two maps rather than one: the lookup by unit happens on every change of
-- health, the lookup by frame on every attachment. One map would make the
-- second path a linear search, and that path runs in combat for every creature
-- that appears.
-- @return table
function Engine.NewState()
    return { byUnit = {}, byPlate = {}, count = 0 }
end

--- The attachment record for a unit.
-- @param state table
-- @param unit string|nil
-- @return table|nil
function Engine.Held(state, unit)
    if type(state) ~= "table" or type(unit) ~= "string" then return nil end
    return state.byUnit[unit]
end

--- Detach a unit.
--
-- Both maps and the record itself are cleared: the record is handed to the
-- caller so that it can return the frame to the pool and restore the native
-- nameplate, but as far as the ledger is concerned it is gone. A repeated
-- detachment keeps quiet — the "went away" event also arrives for a unit we
-- never took (the module may have been switched on in the middle of a
-- fight).
--
-- @param state table
-- @param unit string|nil
-- @return table|nil the record, if there was one
function Engine.Detach(state, unit)
    if type(state) ~= "table" or type(unit) ~= "string" then return nil end

    local record = state.byUnit[unit]
    if record == nil then return nil end

    state.byUnit[unit] = nil
    if record.plate ~= nil then state.byPlate[record.plate] = nil end
    state.count = state.count - 1

    return record
end

--- Attach a unit to a game nameplate.
--
-- This is where the main hole of reuse is closed. The game hands the same
-- frame to a new unit, and the "went away" event for the previous one may not
-- arrive at all — on a change of zone, on leaving combat, on a reload of the
-- interface. So an attachment begins with a detachment: of the unit this frame
-- was recorded for, and of the frame this unit was recorded for. Without those
-- two lines the previous creature's name is left on the bar, and the engine is
-- the one that looks at fault.
--
-- The record's table may be passed in ready, and the display does exactly
-- that: it lies on our own frame and outlives its returns to the pool. An
-- attachment happens in combat for every creature that appears, and allocating
-- a table there is the very cost a nameplates engine has no right to demand.
--
-- @param state table
-- @param unit string|nil
-- @param plate table|nil the game's frame
-- @param frame table|nil our frame
-- @param record table|nil a record table to reuse
-- @return table|nil the attachment's record
-- @return table|nil the record that had to be detached (it needs clearing)
function Engine.Attach(state, unit, plate, frame, record)
    if type(state) ~= "table" then return nil end
    if type(unit) ~= "string" or unit == "" then return nil end
    if plate == nil then return nil end

    -- This unit is already recorded for us: a fresh record replaces the old
    -- one, and the caller is obliged to clear the old one — its frame shows a
    -- past state.
    local previous = Engine.Detach(state, unit)

    -- This game frame was recorded for another unit. That happens, and it is
    -- precisely the case this whole function is written for.
    local stale = state.byPlate[plate]
    if stale ~= nil then
        local dropped = Engine.Detach(state, stale.unit)
        previous = previous or dropped
    end

    record = type(record) == "table" and record or {}
    record.unit  = unit
    record.plate = plate
    record.frame = frame

    state.byUnit[unit]  = record
    state.byPlate[plate] = record
    state.count = state.count + 1

    return record, previous
end

--- Detach everything.
-- Called on a change of zone and when the module is switched off. The records
-- are returned as an array: the caller has to walk them and give every frame
-- back, and clearing the ledger one unit at a time while doing so is not
-- allowed — the map would change underneath the walk.
-- @param state table
-- @return table array of records
function Engine.DetachAll(state)
    local out = {}
    if type(state) ~= "table" then return out end

    for _, record in pairs(state.byUnit) do
        out[#out + 1] = record
    end

    state.byUnit  = {}
    state.byPlate = {}
    state.count   = 0

    return out
end

--- Wipe a record clean.
--
-- This is the promise "a frame returned to the pool carries nothing of the
-- previous unit", written down executably. The fields are enumerated by a walk
-- rather than by a list: the record lives on our frame and outlives its
-- returns, so every field the display adds tomorrow has to be removed already
-- today. A list of fields would diverge from the display silently, and would
-- diverge in exactly the direction that costs most.
-- @param record table|nil
-- @return table|nil the same record, empty
function Engine.Wipe(record)
    if type(record) ~= "table" then return nil end
    for key in pairs(record) do record[key] = nil end
    return record
end

--- Whether the ledger is clean for this unit and this frame.
-- It exists for the tests and for one thought: "nothing was left" is a claim
-- that has to be testable rather than a promise in a comment.
-- @param state table
-- @param unit string|nil
-- @param plate table|nil
-- @return boolean
function Engine.Clean(state, unit, plate)
    if type(state) ~= "table" then return false end
    if unit ~= nil and state.byUnit[unit] ~= nil then return false end
    if plate ~= nil and state.byPlate[plate] ~= nil then return false end
    return true
end
