local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("auras")

-- Filtering auras: what to show and what to hide. Here is what belongs to
-- this module, and nothing more.
--
-- === What left this file, and where it went ===
--
-- Parsing the list the player typed (an id or a name), the name key, the mode
-- words and the list's verdict now live in the core (Darken:GetAuraFilter,
-- contract version 7, docs/module-api.md). They were written here and,
-- separately, in the nameplates engine — identically, down to the string.lower
-- limit. Two copies of one rule diverge silently: a change in one leaves the
-- other as it was, and one and the same typed list starts meaning different
-- things in two windows. No copy was left here: below there is neither a
-- string parser, nor a map, nor the mode words.
--
-- === What stayed here, and why ===
--
-- What is ours and the neighbour does not have:
--
--   the aura's id. The module reads it from the game (the modern per-index
--       aura call returns spellId as a field, the classic UnitAura as its
--       tenth value) and passes it to the decision beside the name. The core
--       can parse a typed id — only whoever reads it can ask about it, and
--       the nameplates engine does not read ids at all;
--   the scope of "only mine". Here it covers buffs alone: on the player
--       debuffs are applied by anybody but themselves, and "show only my
--       debuffs" would mean an empty debuff block always — a setting that
--       looks like a filter and works like a switch. For the neighbour the
--       same setting honestly covers auras of any kind, and reducing the two
--       to one flag would mean a shared rule that is true for neither;
--   the aura's kind as an axis of filtering. Two switches — "hide all buffs"
--       and "hide all debuffs". Switches specifically, and they are named as
--       switches: "hide all buffs" has to leave the buff block empty, and it
--       is empty not because the setting broke but because that is what was
--       asked for. That is what sets them apart from the "only my debuffs"
--       that is not here: there the setting promised a filter and silently
--       meant emptiness, here it says emptiness out loud and promises nothing
--       beyond it.
--
--       They cannot be merged with "only mine" into one axis of kind: "only
--       mine" narrows a block while these two put it out, and one setting of
--       three values (all / only mine / none) would deprive debuffs of a
--       middle value they do not have.
--
-- === The file's main rule ===
--
-- A filter that hid what was needed is discovered by the player in a raid, and
-- discovered dearly. So every default means "show everything", and any
-- uncertainty is resolved the same way: no plan — show; an unfamiliar mode out
-- of the profile — show; an empty list — show. Anything can be hidden only by
-- what the player typed themselves.
--
-- === The cost ===
--
-- The split in two is preserved in full: Compile parses the settings into a
-- plan and is called only from ApplySettings, while Allows decides about one
-- aura and allocates neither tables, nor strings, nor loops. Both ceilings are
-- guarded by tests/test_aurasfilter.lua ("the decision's cost does not depend
-- on the list's length").

-- The core's shared filter. Asked for once: the same table is returned every
-- time, and fetching it per aura would mean paying for one and the same
-- thing.
--
-- A core older than version 7 does not have this door. Then ns.Filter is not
-- created at all, and Auras.lua says one readable line to the player and
-- leaves: a silent Lua error in a file's body is the worst of answers.
local core = type(Darken) == "table"
    and type(Darken.GetAuraFilter) == "function"
    and Darken:GetAuraFilter() or nil
if type(core) ~= "table" then return end

local Filter = {}
ns.Filter = Filter

-- The mode words are the core's. The set is assembled from the core's list
-- rather than written out beside it: having diverged, two sets would give the
-- player a mode the core does not know and would silently switch their filter
-- off.
local MODES = {}
for _, word in ipairs(core.Modes()) do MODES[word] = true end
Filter.MODES = MODES

Filter.DEFAULT_MODE = core.DEFAULT_MODE

-- Parsing the list, the name key and the question "is one needed at all" are
-- the core's, and taken from the core by name rather than written out beside
-- it. The name key folds Cyrillic case as it folds Latin: the core's
-- Core/Casefold.lua stands behind it, so a lower-case spelling finds a
-- capitalised one. What does not fold and why is stated there.
Filter.Split    = core.Split
Filter.Key      = core.Key
Filter.NeedsKey = core.NeedsKey

local HIDE, SHOW = core.HIDE, core.SHOW

--- Compile the filter's plan from the module's settings.
--
-- The only place where tables are allocated and strings parsed. The core
-- parses the list and the mode, and the module adds its own fields to the plan
-- it was given — it is an ordinary table, and a new one per call: the plan
-- backs what is on screen, and editing it underneath would mean some icons
-- were filtered by the old rule and some by the new one.
--
-- @param settings table|nil the module's settings section
-- @return table the plan
function Filter.Compile(settings)
    settings = type(settings) == "table" and settings or {}

    local plan = core.Compile(settings.filterList, settings.filterMode)

    -- "Only mine" covers buffs alone, and that is not a simplification. See
    -- the header.
    plan.onlyMine = settings.onlyMine and true or false

    -- The aura's kind as an axis: two switches, one per block. The default
    -- for both is "do not hide": a fresh install hides nothing.
    plan.hideBuffs   = settings.hideBuffs and true or false
    plan.hideDebuffs = settings.hideDebuffs and true or false

    return plan
end

--- Whether a block of this kind will stay empty for any aura at all.
--
-- Asked not on the hot path but by the settings section: the player is
-- entitled to ask for an empty block, but they must learn about it from the
-- setting rather than from an empty screen in combat. The answer is here
-- because the precedence of the rules is written here: a second place
-- computing the same thing would diverge from Allows silently.
--
-- "Always empty" means it literally: there is no aura Allows would let into
-- this block. A list in the "show only these" mode lifts the emptiness — it
-- outranks the switch — while in the "nothing" and "hide the named" modes it
-- adds nothing to the block.
--
-- @param plan table|nil the plan from Compile
-- @param harmful any whether the question is about the debuff block
-- @return boolean
function Filter.Blank(plan, harmful)
    if type(plan) ~= "table" then return false end

    -- What was named outranks the switch: while such a list is typed, the
    -- block can show at least what was named.
    if plan.mode == "allow" then return false end

    if harmful then return plan.hideDebuffs and true or false end
    return plan.hideBuffs and true or false
end

--- Whether to show one aura.
--
-- A hot path: called for every aura of the player's on every update. Not one
-- table, not one string, not one loop — and not one read of the settings:
-- everything the decision needs is already in the plan.
--
-- Without a plan the answer is "show": a filter that failed to compile for
-- whatever reason is obliged to hide nothing. The opposite default is an empty
-- aura display in the middle of a fight.
--
-- The precedence of the rules is stated here once and in full:
--
--   1. "Hide these" outranks everything: what was named as forbidden must
--      disappear, whatever it is.
--   2. "Show only these" is an instruction by name, and it outranks all of our
--      rules at once: whoever typed the spell into the list has already said
--      they want to see it, and any rule on top of that would read as a
--      refusal. Hence also the fact that "hide all buffs" does not put out a
--      buff named in this mode: the list outranks the switch.
--   3. "Hide all buffs" and "hide all debuffs" — each by its own aura kind.
--   4. "Only mine" covers buffs and does not cover debuffs — and where buffs
--      are hidden entirely there is nothing left to narrow, so the setting is
--      not asked about at all.
--
-- The first two points are the list's verdict, and the core computes it: it is
-- one for both modules. The third and the fourth are ours, and they stayed
-- here.
--
-- The neighbour's order is the reverse: there the aura's kind outranks the
-- list. That is not a divergence through oversight — for the neighbour the
-- switches say "show", their default is yes, and they answer the question
-- "what kinds of icon exist here at all", while here they say "hide", the
-- default is no, and they answer the question "what to remove from what is
-- already visible". What was named outranks the second and does not outrank
-- the first.
--
-- @param plan table|nil the plan from Compile
-- @param key string|nil the spell's name key (Filter.Key), or nil
-- @param id number|nil the spell's id, or nil
-- @param mine any whether the aura was applied by the player
-- @param harmful any whether this is a debuff
-- @return boolean
function Filter.Allows(plan, key, id, mine, harmful)
    if type(plan) ~= "table" then return true end

    local verdict = core.Decide(plan, key, id)
    if verdict == HIDE then return false end
    if verdict == SHOW then return true end

    if harmful then
        if plan.hideDebuffs then return false end
    else
        if plan.hideBuffs then return false end
        if plan.onlyMine and not mine then return false end
    end

    return true
end
