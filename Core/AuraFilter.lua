local ADDON, ns = ...

-- The shared aura filter: parsing the spell list the player typed, and
-- deciding about one aura. The core exposes this through
-- Darken:GetAuraFilter() (contract version 7, docs/module-api.md).
--
-- === Why this lives in the core ===
--
-- Two parts arrived at the same filter separately: the nameplate engine
-- (Features/NamePlates) and the compact auras (Features/Auras). It was not
-- only the intent that matched — the mode words matched, the splitting of the
-- list on commas and newlines, the reduction of a name to a key, and the
-- explicitly documented limit of string.lower. Two copies of one rule diverge
-- silently: a change in one leaves the other as it was, and the player gets
-- two filters that read the same string differently. A module has no right to
-- look into another's folder, so the shared part was put where both may
-- look — into the core.
--
-- The string.lower limit is no longer here. Two more subsystems hit it
-- separately — the bags' search and the item database's query language — and
-- case folding moved one level deeper, into ns.Casefold (Core/Casefold.lua):
-- for the same reason and by the same means the filter itself moved here. The
-- name key below is that core function, not a wrapper around it.
--
-- === Why the filter is split in two ===
--
-- There are many decisions: thirty nameplates with five auras each is a
-- hundred and fifty decisions per recalculation, and an update of the
-- player's auras is up to eighty — arriving constantly in combat. A filter
-- that parses the settings string, splits it on commas and allocates a table
-- on every decision is exactly how addons drop the frame rate in a raid. And
-- the answer is the same every time: the settings string does not change
-- between two auras.
--
-- So the work is laid out by cost:
--
--   Compile — parses the settings into a plan. Called exactly when the
--       settings changed: login, a profile switch, an edit to the field. The
--       only place where tables and strings are allocated.
--
--   Decide — the decision about one aura. No tables, no strings, no loops:
--       one or two comparisons and one or two lookups in a finished map. The
--       cost depends neither on the list's length nor on the number of auras
--       on screen.
--
-- That property is not a promise but a measured quantity: both modules guard
-- the ceilings (tests/test_nameplates2.lua, tests/test_aurasfilter.lua) and so
-- does the contract itself (tests/test_aurafilter.lua).
--
-- === What is here and what is not ===
--
-- Here is what matched word for word in both modules: the mode words, the
-- list parsing, the name key and the list's verdict. Nothing that differed
-- between them is here: the cap on the number of icons and the per-kind
-- switches belong to the nameplate engine, and the "only mine" scope to the
-- compact auras. A shared function with a flag per caller is not one rule but
-- two copies in one table, and they are harder to tell apart than two files.
--
-- The list's verdict is a word rather than a yes/no: a list can say three
-- different things — "hide", "show regardless" and "I have nothing to say".
-- Reduced to two, each module would have to restate the precedence, while the
-- precedence of everything else is honestly different between them.
--
-- The plan is an ordinary table, and a module adds its own fields to it.
-- Compile returns a new table on every call: the plan backs what is on
-- screen, and editing it underneath would mean half the auras were filtered
-- by the old rule and half by the new one.

local AuraFilter = {}
ns.AuraFilter = AuraFilter

-- The tally of work done (Core/Tally.lua). The reference is taken once while
-- the file is read: the decision about one aura is the addon's hottest path,
-- and nothing but integer addition may happen on it.
local counters = ns.Counters or {}
ns.Counters = counters

counters.auras = counters.auras or 0

-- What to do with the spell list. The values reach the modules'
-- SavedVariables, so they are words rather than numbers: a mode's index,
-- shifted when a new one is appended, would silently change the player's
-- setting.
--
-- The declaration order is fixed: a module builds its dropdown from it, and
-- "do nothing" has to come first.
local MODES = { "off", "deny", "allow" }

local MODE_SET = {}
for i = 1, #MODES do MODE_SET[MODES[i]] = true end

-- The default: "do nothing". A filter that hid something needed is
-- discovered in a raid and discovered expensively, so a fresh installation
-- hides nothing.
local DEFAULT_MODE = "off"
AuraFilter.DEFAULT_MODE = DEFAULT_MODE

-- The words of the list's verdict. Part of the contract on the same footing
-- as the mode words: adding is allowed, renaming is not.
local SHOW, HIDE, PASS = "show", "hide", "pass"
AuraFilter.SHOW = SHOW
AuraFilter.HIDE = HIDE
AuraFilter.PASS = PASS

--- The mode words, in declaration order.
-- A new array every time: a shared one would let a module rewrite the modes
-- for the whole addon, and the modes reach other people's SavedVariables.
-- @return table array of words
function AuraFilter.Modes()
    local out = {}
    for i = 1, #MODES do out[i] = MODES[i] end
    return out
end

--- Whether the core knows this mode word.
-- @param mode any
-- @return boolean
function AuraFilter.IsMode(mode)
    return MODE_SET[mode] == true
end

--- The key of a spell's name, for looking it up in the list.
--
-- This is the core's case folding (ns.Casefold.Key, Core/Casefold.lua) and it
-- is that function itself rather than a wrapper around it: the name here is a
-- second name for one function, and there is no copy that could diverge, not
-- even by a line. There used to be a string.lower here, which in Lua 5.1
-- folds byte by byte and knows only ASCII: "Кровопускание" was found with a
-- capital letter and not with a small one. The bags module and the item
-- database each documented the same limit separately; it is now lifted in all
-- three places at once, because there is one place.
--
-- Cyrillic, the Ukrainian Ґ and Latin letters with diacritics fold — the
-- letters of the clients the game shipped in. What does not fold and why is
-- stated in Core/Casefold.lua and in docs/module-api.md: the author of a
-- third-party module will hit this too, not only ours.
-- @param name any
-- @return string|nil
AuraFilter.Key = ns.Casefold.Key

--- Parse one entry of the list.
--
-- An entry is either a spell id or a spell name, and they are told apart by
-- their shape rather than by a separate setting: asking the player to declare
-- "a number follows" is one more question where the answer is visible.
--
-- An id is a positive integer. A fraction and a zero are never spell ids, and
-- "3.5" here means a typo rather than id 3: such an entry goes to the names,
-- where it simply matches nothing, instead of silently becoming somebody
-- else's spell.
--
-- A module that does not read aura ids simply does not pass them to the
-- decision: a typed id matches nothing, which is the same as it was before
-- the shared filter.
-- @param piece any a piece of the typed string
-- @return number|nil the spell id
-- @return string|nil the name key
function AuraFilter.Entry(piece)
    local key = AuraFilter.Key(piece)
    if key == nil then return nil, nil end

    if key:match("^%d+$") then
        local id = tonumber(key)
        if id and id > 0 then return math.floor(id), nil end
    end

    return nil, key
end

--- Parse the spell list the player typed.
--
-- The separator is a comma or a newline: the player may type the list as a
-- column, and explaining to them that a column is one name with newlines
-- inside would be honest and useless.
--
-- A repeat is not counted twice and does not create a second entry: a list
-- naming the same thing three times means exactly what a list naming it once
-- means.
--
-- @param text any
-- @return table map of id -> true
-- @return table map of name key -> true
-- @return number how many distinct entries were parsed
-- @return number how many of them were ids
function AuraFilter.Split(text)
    local ids, names = {}, {}
    local count, numbered = 0, 0
    if type(text) ~= "string" then return ids, names, count, numbered end

    for piece in text:gmatch("[^,\r\n]+") do
        local id, key = AuraFilter.Entry(piece)
        if id ~= nil then
            if not ids[id] then
                ids[id] = true
                count = count + 1
                numbered = numbered + 1
            end
        elseif key ~= nil then
            if not names[key] then
                names[key] = true
                count = count + 1
            end
        end
    end

    return ids, names, count, numbered
end

--- Compile the list into a filtering plan.
--
-- The list and the mode arrive separately rather than as a settings section:
-- the modules' field names are their own (auraList/auraMode versus
-- filterList/filterMode), and demanding identical ones would mean renaming
-- the player's setting for the core's convenience.
--
-- A module adds its own fields to the plan it is given — it is an ordinary
-- table.
--
-- @param list any the list string the player typed
-- @param mode any the mode word from the settings
-- @return table the plan
function AuraFilter.Compile(list, mode)
    if not MODE_SET[mode] then mode = DEFAULT_MODE end

    local ids, names, count, numbered = AuraFilter.Split(list)

    -- A mode that needs a list, with an empty list, would mean "show
    -- nothing" (allow) or "show everything" (deny) — the second is harmless,
    -- the first looks broken and hides the player's whole aura display. An
    -- empty list switches the mode off entirely: whoever cleared the field
    -- wants the previous appearance back, not to be left without auras.
    if count == 0 then mode = DEFAULT_MODE end

    -- Whether there is anything to compare a name against at all. While
    -- there are no names in the list there is no point building a name key —
    -- and a name key is a new string per aura per update.
    local hasNames = (mode ~= DEFAULT_MODE) and next(names) ~= nil

    return {
        mode     = mode,
        ids      = ids,
        names    = names,
        count    = count,
        numbered = numbered,
        hasNames = hasNames and true or false,
    }
end

--- Whether the decision needs a name key.
--
-- Asked before the key is built: a key is a new string, and allocating one per
-- aura for a map that holds no names at all is paying for nothing. With a
-- module's defaults the answer is always no.
-- @param plan table|nil
-- @return boolean
function AuraFilter.NeedsKey(plan)
    return type(plan) == "table" and plan.hasNames and true or false
end

--- Whether the spell is named in the list.
-- @param plan table the plan
-- @param key string|nil the name key
-- @param id number|nil the spell id
-- @return boolean
local function listed(plan, key, id)
    if id ~= nil and plan.ids[id] then return true end
    if key ~= nil and plan.names[key] then return true end
    return false
end

--- What the list says about one aura.
--
-- A hot path: called for every aura of every update. Not one table, not one
-- string, not one loop — and not one read of the settings: everything the
-- decision needs is already in the plan.
--
-- The answer is one of three words, and there are three because a list can
-- say three different things:
--
--   HIDE — what was named as forbidden must disappear, whatever it is;
--   SHOW — what was named in "only these" mode is shown by name: whoever
--          typed the spell has already said they want to see it, and the
--          module's other rules on top of that would read as a refusal;
--   PASS — the list has nothing to say; the module decides from here.
--
-- Without a plan: PASS. A filter that failed to compile for any reason
-- whatsoever must hide nothing of its own accord. What "nothing to say" means
-- is each module's own business, not ours.
--
-- @param plan table|nil the plan from Compile
-- @param key string|nil the spell's name key (Key), or nil
-- @param id number|nil the spell id, or nil
-- @return string SHOW, HIDE or PASS
function AuraFilter.Decide(plan, key, id)
    if type(plan) ~= "table" then return PASS end

    -- The tally stands only on the branches where the list said something.
    -- On PASS — which is almost every aura almost always — not a single
    -- operation was added: the counter answers "did the list filter anything
    -- at all", and auras the list has nothing to say about do not change that
    -- answer.
    local mode = plan.mode
    if mode == "deny" then
        if listed(plan, key, id) then
            counters.auras = counters.auras + 1
            return HIDE
        end
    elseif mode == "allow" then
        counters.auras = counters.auras + 1
        if listed(plan, key, id) then return SHOW end
        return HIDE
    end

    return PASS
end
