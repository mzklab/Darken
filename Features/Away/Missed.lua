-- The tally of what was missed while away, and the line made from it.
--
-- The module's pure part: not one call into the game and not one into the
-- engine. Events that have already happened arrive here — a whisper came, a
-- letter came — and a line leaves, which the screen prints under the card.
-- This can be tested without a client, and it is tested without one.

local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Screen would collide
-- silently.
local ns = core.Feature("away")

local Missed = {}
ns.Missed = Missed

-- What is counted, and in what order it stands in the line. The order is
-- given here as a list rather than by walking a table: a pairs walk in Lua
-- promises no order, and the line would change its look from run to run.
--
-- The keys are not labels. Each kind's label is taken from the translation at
-- the point of printing, because it has three number forms in Russian and two
-- in English, and deciding that here, away from the language, would be
-- wrong.
--
-- Invitations are not in the list, and that is not an omission. A group
-- invitation, a dungeon offer, a summon and a duel request are in the list of
-- interruptions: the screen goes out on them for the rest of the absence.
-- Counting them would mean a counter nobody can ever see — there is nothing
-- left to show it with.
Missed.KINDS = { "whisper", "mail" }

local KNOWN = {}
for i = 1, #Missed.KINDS do KNOWN[Missed.KINDS[i]] = true end

--- An empty tally: every kind at zero.
--
-- A function rather than a template table: a template would be returned by
-- reference, and two screens in a row would share one tally.
-- @return table
function Missed.New()
    local out = {}
    for i = 1, #Missed.KINDS do out[Missed.KINDS[i]] = 0 end
    return out
end

--- Add one event.
--
-- An unknown kind is silently discarded rather than given a key of its own:
-- otherwise a typo at a call site would create a new kind that is never
-- printed (it is not in KINDS) and is never noticed.
-- @param tally table the tally
-- @param kind string the kind
-- @param count number|nil how many; one by default
-- @return table the same tally
function Missed.Add(tally, kind, count)
    if type(tally) ~= "table" then return tally end
    if not KNOWN[kind] then return tally end

    local many = tonumber(count) or 1
    if many ~= many or many <= 0 then return tally end

    tally[kind] = (tonumber(tally[kind]) or 0) + many
    return tally
end

--- Whether there is anything to show.
-- @param tally table|nil
-- @return boolean
function Missed.Any(tally)
    if type(tally) ~= "table" then return false end
    for i = 1, #Missed.KINDS do
        if (tonumber(tally[Missed.KINDS[i]]) or 0) > 0 then return true end
    end
    return false
end

--- The kinds with a non-zero count, in KINDS order.
--
-- A list of pairs is returned rather than a string: only whoever knows the
-- language can inflect a label by number, and that is the point of printing
-- rather than this place.
-- @param tally table|nil
-- @return table array of { kind = string, count = number }
function Missed.Parts(tally)
    local out = {}
    if type(tally) ~= "table" then return out end

    for i = 1, #Missed.KINDS do
        local kind = Missed.KINDS[i]
        local count = tonumber(tally[kind]) or 0
        if count > 0 then
            out[#out + 1] = { kind = kind, count = count }
        end
    end
    return out
end

--- Assemble the line from pieces already translated.
--
-- The separator is a middle dot with spaces, the info panel's: two lines of
-- one addon separated differently read as the lines of two different addons.
-- @param pieces table array of strings
-- @return string|nil nil when there is nothing to show
function Missed.Join(pieces)
    if type(pieces) ~= "table" or #pieces == 0 then return nil end
    return table.concat(pieces, " \194\183 ")
end
