local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- A nameplate's aura filter: what belongs to this module and nothing more.
--
-- === What left this file, and where it went ===
--
-- Parsing the list the player typed, the name key, the mode words and the
-- list's verdict now live in the core (Darken:GetAuraFilter, contract version
-- 7, docs/module-api.md). They were written here and, separately, in the
-- compact auras — identically, down to the string.lower limit. Two copies of
-- one rule diverge silently: a change in one leaves the other as it was, and
-- one and the same typed list starts meaning different things in two windows.
-- No copy was left here: below there is neither a string parser, nor a map,
-- nor the mode words.
--
-- === What stayed here, and why ===
--
-- What the neighbour does not have and the core must not:
--
--   the cap on the number of icons (LIMIT) and an icon's size (SIZE) — an
--       icon on a nameplate is a frame, there are thirty nameplates' worth of
--       frames on screen, and the upper bound here is not a matter of taste;
--   the switches by aura kind (helpful/harmful) and the switch for the icons
--       themselves (enabled) — in the compact auras the aura's kind is
--       expressed by two separate blocks, and such a switch does not exist
--       there at all;
--   the precedence of "only mine" — here it covers auras of any kind while
--       for the neighbour only buffs, and that is not a detail but a
--       different meaning of the setting.
--
-- A shared function with a flag per caller would not be one rule but two
-- copies in one table.
--
-- === The cost ===
--
-- The split in two is preserved in full: Compile parses the settings into a
-- plan and is called when the settings change, while Allows decides about one
-- aura and allocates neither tables, nor strings, nor loops. The ceiling is
-- guarded by tests/test_nameplates2.lua ("the filter's cost does not depend
-- on the number of nameplates").

-- The core's shared filter. Asked for once: the same table is returned every
-- time, and fetching it per aura would mean paying for one and the same
-- thing.
--
-- A core older than version 7 does not have this door. Then ns.Filter is not
-- created at all, and NamePlates.lua says one readable line to the player and
-- leaves: a silent Lua error in a file's body is the worst of answers.
local core = type(Darken) == "table"
    and type(Darken.GetAuraFilter) == "function"
    and Darken:GetAuraFilter() or nil
if type(core) ~= "table" then return end

local Filter = {}
ns.Filter = Filter

-- The greatest number of icons to show. The upper bound is not a matter of
-- taste: an icon is a frame, the engine does not release frames at all, and
-- "let us show all forty" means forty frames per nameplate until the end of
-- the session.
local LIMIT = { min = 1, max = 8, default = 4 }
Filter.LIMIT = LIMIT

-- An icon's size in pixels.
local SIZE = { min = 8, max = 32, default = 16 }
Filter.SIZE = SIZE

-- The name key and the question "is one needed at all" are the core's, and
-- taken from the core by name rather than written out beside it. The name key
-- folds Cyrillic case as it folds Latin: the core's Core/Casefold.lua stands
-- behind it, so a lower-case spelling finds a capitalised one. What does not
-- fold and why is stated there.
Filter.Key      = core.Key
Filter.NeedsKey = core.NeedsKey

local HIDE, SHOW = core.HIDE, core.SHOW

--- Compile the filter's plan from the module's settings.
--
-- The only place where tables are allocated and strings parsed. The core
-- parses the list and the mode, and the module adds its own fields to the
-- plan it was given — it is an ordinary table, and a new one per call: the
-- plan backs what is on screen, and editing it underneath would mean half the
-- nameplates were recomputed by the old rule and half by the new one.
--
-- @param settings table|nil the module's settings section
-- @return table the plan
function Filter.Compile(settings)
    settings = type(settings) == "table" and settings or {}

    local plan = core.Compile(settings.auraList, settings.auraMode)

    local limit = tonumber(settings.auraLimit) or LIMIT.default
    if limit ~= limit or limit < LIMIT.min then limit = LIMIT.min end
    if limit > LIMIT.max then limit = LIMIT.max end

    plan.enabled  = settings.auras and true or false
    plan.onlyMine = settings.auraOnlyMine and true or false
    plan.helpful  = settings.auraHelpful and true or false
    plan.harmful  = settings.auraHarmful and true or false
    plan.limit    = math.floor(limit)

    return plan
end

--- Whether to let one aura through.
--
-- A hot path: called for every aura of every creature on screen. Not one
-- table, not one string, not one loop — and not one read of the settings:
-- everything the decision needs is already in the plan.
--
-- The order of the rules is set by their cost and by their meaning. First what
-- cuts away whole ranks (switched off, the wrong kind of aura), then the list
-- — the core computes its verdict — then "only mine".
--
-- The list outranks the other rules in one direction only: "show only these"
-- is the player's instruction by name, and "only mine" does not override it.
-- The opposite — a prohibition — outranks everything: what was named as
-- forbidden must disappear, whatever it is.
--
-- The module does not read spell ids and therefore does not ask for them: on
-- a nameplate it matches a name, as it always has.
--
-- @param plan table|nil the plan from Compile
-- @param key string|nil the spell's name key (Filter.Key)
-- @param mine any whether the aura was applied by the player
-- @param harmful any whether the aura is harmful
-- @return boolean
function Filter.Allows(plan, key, mine, harmful)
    if type(plan) ~= "table" or not plan.enabled then return false end

    if harmful then
        if not plan.harmful then return false end
    else
        if not plan.helpful then return false end
    end

    local verdict = core.Decide(plan, key, nil)
    if verdict == HIDE then return false end
    -- What was named is shown regardless of "only mine": the player who
    -- typed the spell into the list has already said they want to see it, and
    -- a second rule on top of that would read as a refusal.
    if verdict == SHOW then return true end

    if plan.onlyMine and not mine then return false end

    return true
end

--- How many icons are allowed to be shown.
-- @param plan table|nil
-- @return number
function Filter.Limit(plan)
    if type(plan) ~= "table" then return 0 end
    if not plan.enabled then return 0 end
    return plan.limit or LIMIT.default
end
