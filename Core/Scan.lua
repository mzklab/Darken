local ADDON, ns = ...

-- Reconnaissance: finding frames that exist, by part of their name.
-- It exists so that the compatibility table is filled with confirmed names
-- rather than guesses.
local Scan = {}
ns.Scan = Scan

--- Find global objects whose name contains the pattern.
-- The globals table is passed in as an argument so this is testable outside
-- the game.
-- @param pattern string part of a name; case does not matter
-- @param globals table name -> object
-- @param limit number maximum number of results
-- @return table sorted array of names
function Scan.Find(pattern, globals, limit)
    local out = {}
    if type(pattern) ~= "string" or pattern == "" then return out end
    if type(globals) ~= "table" then return out end

    local needle = pattern:lower()
    for name, value in pairs(globals) do
        if type(name) == "string" and name:lower():find(needle, 1, true) then
            -- Only objects that behave like frames are of interest.
            if type(value) == "table" and type(rawget(value, 0)) == "userdata" then
                out[#out + 1] = name
            end
        end
    end

    table.sort(out)

    if limit and #out > limit then
        for i = #out, limit + 1, -1 do
            out[i] = nil
        end
    end
    return out
end

-- The patterns the name directory is collected by. Kept here rather than in
-- the command: the list is needed by the tests and by the scan alike, and it
-- also defines what has to be run in a live client.
Scan.PATTERNS = {
    "Player", "Target", "Focus", "Party", "Pet",
    "Cast", "Action", "Bar", "Stance", "Shapeshift",
    "Minimap", "Quest", "Chat", "Bag", "Container",
    "NamePlate", "Tooltip", "Character", "Buff", "Debuff",
    "Aura", "Micro", "Merchant", "Bank", "Mail",
}

--- Sort a list and truncate it at the cap.
--
-- The sort comes BEFORE the truncation, and that is half the point of the
-- whole scan. Truncating first returned an arbitrary subset of the matches
-- (pairs order), and an arbitrary subset proves nothing: a name is absent
-- from the list both because it does not exist in the client and because it
-- did not fit. After sorting, a truncated list is the first N
-- alphabetically, and the absence of a name that sorts before the list's last
-- entry again means the name is absent.
--
-- The other half is returning the true count. A truncated list differed from
-- a full one only by counting up to the cap; now the directory states it.
--
-- @param list table array of names
-- @param limit number|nil the cap
-- @return number how many were kept
-- @return number|nil how many there really were, if the list was truncated
local function finish(list, limit)
    table.sort(list)

    local full = #list
    if limit and full > limit then
        for i = full, limit + 1, -1 do list[i] = nil end
        return limit, full
    end
    return full, nil
end

--- Collect names for every pattern in one pass.
--
-- Returns a table with three fields. The globals table is passed in as an
-- argument for testability outside the game, as in Find.
--
--   frames    — pattern -> array of names of frame-like objects;
--   functions — pattern -> array of names of game functions;
--   cut       — pattern -> { frames = N, functions = N } for those patterns
--               whose list hit the cap. N is how many names there really
--               were. No key means the list is complete, and the absence of a
--               name from it means the name is absent from the client.
--
-- WHY FUNCTIONS. The compatibility layer declares more than frames: redrawing
-- the bags, laying out the action bars and laying out the auras are names of
-- game functions. Selecting by "rawget(value, 0) is userdata" did not take
-- them, and six of the addon's groups could never be confirmed or refuted by
-- the directory. The absence of a function name from the directory was
-- indistinguishable from the directory not collecting functions at all.
--
-- THE COST. There is still exactly one pass over the globals table: a client
-- has tens of thousands of globals and there are about twenty patterns, so a
-- separate pass per pattern is the same work multiplied by twenty, during
-- login. Functions add a second selection branch to that pass: a function's
-- name is now lowercased and matched against the patterns too, where
-- previously it was discarded by a single type check. Dropping the
-- truncate-as-you-go means that all matches, not the first two hundred, are
-- in memory before the sort — and those are references to strings that
-- already exist, not copies. All of it costs once per client build at login
-- (Scan.NeedsCollect), and never per frame.
--
-- @param globals table name -> object
-- @param patterns table array of patterns; Scan.PATTERNS by default
-- @param limit number maximum names per pattern and per kind of name
-- @return table the result {frames, functions, cut, limit}
-- @return number how many names were written into the directory
function Scan.Collect(globals, patterns, limit)
    limit = tonumber(limit) or nil

    local frames, functions, cut = {}, {}, {}
    local out = {
        frames    = frames,
        functions = functions,
        cut       = cut,
        limit     = limit,
    }

    if type(globals) ~= "table" then return out, 0 end
    patterns = type(patterns) == "table" and patterns or Scan.PATTERNS

    -- An empty list in the directory is a finding too: it means there are
    -- no such names in the client. A missing key is indistinguishable from
    -- "the pattern was never run".
    local needles = {}
    for i = 1, #patterns do
        local pattern = patterns[i]
        if type(pattern) == "string" and pattern ~= ""
        and frames[pattern] == nil then
            frames[pattern] = {}
            functions[pattern] = {}
            needles[#needles + 1] = { key = pattern, needle = pattern:lower() }
        end
    end

    for name, value in pairs(globals) do
        if type(name) == "string" then
            local kind = type(value)
            local bag
            if kind == "table" and type(rawget(value, 0)) == "userdata" then
                bag = frames
            elseif kind == "function" then
                bag = functions
            end

            if bag ~= nil then
                local lowered = name:lower()
                for i = 1, #needles do
                    if lowered:find(needles[i].needle, 1, true) then
                        local slot = bag[needles[i].key]
                        slot[#slot + 1] = name
                    end
                end
            end
        end
    end

    local total = 0
    for i = 1, #needles do
        local key = needles[i].key
        local keptFrames, fullFrames = finish(frames[key], limit)
        local keptFunctions, fullFunctions = finish(functions[key], limit)
        total = total + keptFrames + keptFunctions

        if fullFrames ~= nil or fullFunctions ~= nil then
            cut[key] = { frames = fullFrames, functions = fullFunctions }
        end
    end

    return out, total
end

--- Whether a pattern's list was truncated.
--
-- One answer to one question, and two parties ask it: whoever reads the
-- directory from disk, and the tests. Without it "two hundred names" and "the
-- first two hundred of six hundred" would be told apart by counting up to the
-- cap by hand — exactly the work that made the previous scan declare fourteen
-- of twenty-five patterns inconclusive.
--
-- @param collected table the result of Scan.Collect, or a stored directory
-- @param pattern string the pattern
-- @param kind string|nil "frames" (the default) or "functions"
-- @return boolean whether the list was truncated
-- @return number|nil how many names there really were
function Scan.WasCut(collected, pattern, kind)
    if type(collected) ~= "table" then return false, nil end
    if type(collected.cut) ~= "table" then return false, nil end

    local entry = collected.cut[pattern]
    if type(entry) ~= "table" then return false, nil end

    local full = tonumber(entry[kind or "frames"])
    if full == nil then return false, nil end
    return true, full
end

--- Whether the directory has to be collected again.
-- What was collected is tied to the client build: while that is the same,
-- there is no point repeating it. A pure function, so the decision is tested
-- without the game.
-- @param stored table the already stored directory, or nil
-- @param build string the current client's build number
-- @return boolean
function Scan.NeedsCollect(stored, build)
    if type(stored) ~= "table" then return true end
    if type(stored.found) ~= "table" then return true end
    -- The client may not report its build. The only honest answer then is
    -- to collect again: a stale directory is worse than doing the work once
    -- more than needed.
    if type(build) ~= "string" or build == "" then return true end
    return stored.build ~= build
end
