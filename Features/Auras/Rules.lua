local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("auras")

-- Rules for a single aura: a look of its own for a spell the player named,
-- and a sound when it ends.
--
-- === What a rule is ===
--
-- A rule is a list of spells plus what sets their icon apart from the rest.
-- The list is typed exactly as the filter list is: separated by commas or one
-- per line, and an entry may be either a spell's id or its name. The core
-- parses it (Darken:GetAuraFilter().Split) — the same parser that handles the
-- filter list and the list of creatures in the nameplate rules. There is no
-- second parser for one and the same string anywhere in the addon, and
-- creating one here would mean creating a door behind which one spell name
-- means different things in two fields of one window.
--
-- Why both an id and a name are accepted: the name is what the player knows
-- and can type, but it belongs to the client's language and is not unique;
-- the id depends neither on the language nor on coincidences. What the player
-- typed is stored, and whatever matched is compared.
--
-- === What a rule changes ===
--
-- Three things, and each answers its own question of the player's.
--
--   the size — a multiplier over the common icon size. "It stands out" on a
--       grid of forty icons is read first of all by size;
--   the border's colour — a colour name from the skin's palette
--       (skin.Colors). This is the second half of the same question: the icon
--       has to differ also when there is no room on screen and nowhere to
--       enlarge it;
--   the sound on ending — the only thing that happens on a transition rather
--       than on a state. It is described separately, below.
--
-- What a rule deliberately does not change:
--
--   its own place in the grid. The module lays the grid out (Layout.Place),
--       and a place in it is an ordinal rather than a property of the spell:
--       the set of auras changes constantly in combat, and "the third cell"
--       belongs to a different aura a second later. A rule that pulled an
--       icon out of its cell would leave a hole in its place and ride over
--       some other icon, because it knows nothing about the rest. The request
--       "put this aura over there" is truly answered by a grid block of its
--       own with a place of its own, and that is a separate thing, written
--       down in the queue of work;
--   whether to show the aura at all. That is a question of filtering, and
--       Filter.Allows already answers it. A second place able to hide an aura
--       would give the player two places to ask "why do I not see it";
--   the order of the icons. The order is a rule over the whole list
--       (Sort.lua) rather than a property of one aura, and a rank of its own
--       per rule would mean a sorting that cannot be explained by looking at
--       the list;
--   the size of the labels separately from the icon's size. It is computed
--       from the icon's size anyway (Icon.Dress): two independent quantities
--       let one assemble an icon whose timer cannot be read.
--
-- === The cost ===
--
-- The work is laid out by cost the same way the filtering is, and for the same
-- reason: there may be a dozen rules, up to eighty auras on the player, and
-- aura updates arrive constantly in combat.
--
--   Compile — parsing the list of rules into two maps. Called only from
--       ApplySettings: entering the game, changing the profile, editing a
--       field. The only place where tables are allocated and strings parsed.
--
--   For — the decision about one aura. No tables, no strings, no loops: one
--       or two lookups in a finished map and, at worst, one comparison.
--
-- A fresh install: there are no rules, Any answers "no" at the very first
-- question, and the hot path does not perform one action for the rules' sake.
--
-- === Precedence between rules ===
--
-- Two rules may name one aura: one by name, the other by id. The dispute is
-- settled by the rule's position in the player's list — the earlier one
-- outranks, as in the bag and nameplate rules. Half the dispute is closed at
-- compile time already: a map is taken by the first rule to name the entry.
-- What is left is a dispute between the maps, and one comparison of rank
-- settles it.
--
-- === The sound on ending ===
--
-- This is the only thing in the module that happens on a transition.
-- Everything else is state: there is an aura, there is an icon; no aura, no
-- icon, and there is nothing to get wrong. A sound gets it wrong loudly: one
-- that played on a change of zone or on an edit of a setting is worse than one
-- that never played at all.
--
-- So "the aura ended" means exactly one thing here: **it was in the previous
-- set that was read and it is not in the current one, and both sets were read
-- one after the other under one and the same settings**. Everything that
-- breaks that chain disarms it (Rules.Disarm), and the first set after that is
-- only remembered:
--
--   an edit of any setting (ApplySettings) — the filter may have stopped
--       letting the aura through, and its disappearance from the set means an
--       edit rather than an ending;
--   entering the world and reloading the interface — the set of auras arrives
--       afresh, and the first reading after entering has nothing to be
--       compared with;
--   the module itself being switched on and off.
--
-- What is remembered is neither the icon nor the place in the grid but the
-- aura itself — its spell id, or, in its absence, the name key (Rules.Token).
-- So the pool of icons takes no part in this at all: an icon does not care
-- which aura it showed last time, and reuse cannot play a sound. An aura being
-- refreshed (a new duration, a new stack) does not change its id and does not
-- count as an ending.
--
-- How many sounds: no more than one per repaint. Three auras that ended at
-- once are the same piece of news three times, while three sounds at once add
-- up to a noise in which none of them can be made out.

-- The module already took the core's shared filter in Filter.lua, and it is
-- taken from there rather than through a second door: Filter.Split and
-- Filter.Key are the core's own functions (Darken:GetAuraFilter, contract 7)
-- rather than wrappers over them. There is not one line of a parser of our own
-- or of case folding of our own here.
if type(ns.Filter) ~= "table" then return end

local Rules = {}
ns.Rules = Rules

-- Parsing the list and the name key are the core's, taken by name. A second
-- name for one function rather than a copy: the test compares them by
-- identity.
Rules.Split = ns.Filter.Split
Rules.Key   = ns.Filter.Key

-- The size multiplier. The bounds are not a matter of taste: an icon half
-- the size of its neighbours cannot be read, while one twice the size spills
-- out of its cell by half the gap on every side — beyond that it would cover
-- its neighbours, that is, hide precisely what the rule was created for.
local SCALE = { min = 0.5, max = 2, default = 1 }
Rules.SCALE = SCALE

-- An icon smaller than eight pixels does not exist: neither the picture nor
-- the timer can be read on one (Icon.Dress keeps the same floor for the
-- font).
local MIN_SIZE = 8
Rules.MIN_SIZE = MIN_SIZE

-- The greatest number of rules, and how long a rule's name may be. The
-- limits are needed because the list goes into SavedVariables and is shown as
-- a choice list: a thousand rules there mean a settings window that cannot be
-- opened.
Rules.MAX = 30
Rules.MAX_NAME = 40

--- Trim the whitespace at both ends.
-- An empty string is not a name: somebody who typed one space named nothing.
-- @param value any
-- @return string|nil
local function trim(value)
    if type(value) ~= "string" then return nil end
    local clean = value:match("^%s*(.-)%s*$")
    if clean == "" then return nil end
    return clean
end

--- Bring the size multiplier within its bounds.
-- Not a number means the default: a value that cannot be produced with the
-- slider came not from the player but from somebody's edit of the saved
-- variables file.
-- @param value any
-- @return number
function Rules.Scale(value)
    local number = tonumber(value)
    if not number or number ~= number then return SCALE.default end
    if number < SCALE.min then return SCALE.min end
    if number > SCALE.max then return SCALE.max end
    return number
end

--- An icon's size with the rule taken into account.
--
-- A multiplier rather than a number of its own: the common icon size is the
-- player's setting, and a rule that replaced it entirely would untie the named
-- aura from the slider the player had just been moving.
--
-- A whole number: half a pixel on an icon means a blurred one-pixel border.
--
-- @param rule table|nil the rule from the plan
-- @param base any the common icon size from the settings
-- @return number
function Rules.Size(rule, base)
    local cell = tonumber(base)
    if not cell or cell ~= cell or cell <= 0 then
        cell = ns.Layout.BOUNDS.size.default
    end

    local factor = SCALE.default
    if type(rule) == "table" then factor = Rules.Scale(rule.scale) end

    local size = math.floor(cell * factor + 0.5)
    if size < MIN_SIZE then size = MIN_SIZE end
    return size
end

--- The border colour's name with the rule taken into account.
--
-- A name from the palette rather than a triple of numbers, and that is not a
-- simplification. Colours in this addon belong to the skin and are taken from
-- it through the contract (skin.Color, skin.Outline): a colour of our own
-- beside the palette is a colour that will not change together with it, that
-- is, precisely what is forbidden to the rest of the module. The list of names
-- shown to the player is the one the skin itself returns, so a name that
-- appears in the palette will turn up in the rules by itself.
--
-- @param rule table|nil
-- @param fallback string the colour name of an ordinary border
-- @return string the colour's name
function Rules.Color(rule, fallback)
    if type(rule) == "table" and type(rule.color) == "string"
        and rule.color ~= "" then
        return rule.color
    end
    return fallback
end

--- What an aura is called in the memory of endings.
--
-- The spell's id, or, in its absence, the name key. Neither the icon nor the
-- place in the grid: both of those outlive their aura (an icon goes back to
-- the pool and falls to another one), while the spell's id belongs to it
-- specifically.
--
-- @param id any the spell's id
-- @param key any the name key (Rules.Key)
-- @return number|string|nil
function Rules.Token(id, key)
    local number = tonumber(id)
    if number and number == number and number > 0 then return number end
    if type(key) == "string" and key ~= "" then return key end
    return nil
end

--============================================================================
-- The list of rules: editing by the player
--============================================================================

--- The list of rules from the module's settings.
--
-- What lies in the saved variables is returned, without a copy: edits are made
-- in place, and a copy would mean an edit lost when the game is left. A missing
-- key gives an empty list rather than a refusal: that is how a fresh install
-- reads.
--
-- @param settings table|nil
-- @return table array of rules
function Rules.List(settings)
    if type(settings) ~= "table" then return {} end
    if type(settings.rules) ~= "table" then return {} end
    return settings.rules
end

--- Find a rule by its name.
-- Compared by the folded key: a capitalised spelling and a lower-case one are
-- one rule.
-- @param list table|nil
-- @param name any
-- @return number|nil the position in the list
-- @return table|nil the rule itself
function Rules.Find(list, name)
    local key = Rules.Key(name)
    if key == nil or type(list) ~= "table" then return nil, nil end

    for i = 1, #list do
        local rule = list[i]
        if type(rule) == "table" and Rules.Key(rule.name) == key then
            return i, rule
        end
    end

    return nil, nil
end

--- Create a rule.
--
-- A refusal is returned as a code rather than a phrase: the place that shows
-- it translates it, not the place that decides it. The name is required — a
-- rule without a name cannot be picked from the list. The list of spells is
-- required: a rule aimed at nobody would stand there as a row that does
-- nothing.
--
-- @param list table array of rules (edited in place)
-- @param name any the rule's name
-- @param text any the list of spell names and ids
-- @return table|nil the rule that was created
-- @return string|nil the refusal code
function Rules.Add(list, name, text)
    if type(list) ~= "table" then return nil, "noname" end

    local clean = trim(name)
    if clean == nil then return nil, "noname" end
    if #clean > Rules.MAX_NAME then return nil, "long" end

    local _, _, count = Rules.Split(text)
    if count == 0 then return nil, "notext" end

    if Rules.Find(list, clean) ~= nil then return nil, "taken" end
    if #list >= Rules.MAX then return nil, "full" end

    local rule = { name = clean, text = trim(text), scale = SCALE.default }
    list[#list + 1] = rule
    return rule, nil
end

--- Rename a rule.
-- @param list table
-- @param name any the current name
-- @param wanted any the new name
-- @return boolean
-- @return string|nil the refusal code
function Rules.Rename(list, name, wanted)
    local index, rule = Rules.Find(list, name)
    if index == nil then return false, "gone" end

    local clean = trim(wanted)
    if clean == nil then return false, "noname" end
    if #clean > Rules.MAX_NAME then return false, "long" end

    local other = Rules.Find(list, clean)
    if other ~= nil and other ~= index then return false, "taken" end

    rule.name = clean
    return true, nil
end

--- Rewrite a rule's list of spells.
-- @param list table
-- @param name any
-- @param text any
-- @return boolean
-- @return string|nil the refusal code
function Rules.SetText(list, name, text)
    local index, rule = Rules.Find(list, name)
    if index == nil then return false, "gone" end

    local _, _, count = Rules.Split(text)
    if count == 0 then return false, "notext" end

    rule.text = trim(text)
    return true, nil
end

--- Set the size multiplier.
-- @param list table
-- @param name any
-- @param value any
-- @return boolean
function Rules.SetScale(list, name, value)
    local index, rule = Rules.Find(list, name)
    if index == nil then return false end

    rule.scale = Rules.Scale(value)
    return true
end

--- Set or remove the border's colour.
-- An empty name means "do not change the colour": a rule is entitled to change
-- the size alone, and then the border is painted in the skin's ordinary
-- colour.
-- @param list table
-- @param name any
-- @param color any a colour name from the palette
-- @return boolean
function Rules.SetColor(list, name, color)
    local index, rule = Rules.Find(list, name)
    if index == nil then return false end

    local clean = trim(color)
    rule.color = clean
    return true
end

--- Switch the sound on ending on or off.
-- @param list table
-- @param name any
-- @param value any
-- @return boolean
function Rules.SetSound(list, name, value)
    local index, rule = Rules.Find(list, name)
    if index == nil then return false end

    rule.sound = value and true or nil
    return true
end

--- Forget a rule.
-- @param list table
-- @param name any
-- @return boolean
function Rules.Remove(list, name)
    local index = Rules.Find(list, name)
    if index == nil then return false end

    table.remove(list, index)
    return true
end

--- Move a rule up or down in precedence.
-- Exactly one step: the list is read by eye, and a rule that travelled three
-- rows from where the player was looking is not a rearrangement but a loss.
-- @param list table
-- @param name any
-- @param delta number -1 up, 1 down
-- @return boolean
function Rules.Move(list, name, delta)
    local index = Rules.Find(list, name)
    if index == nil then return false end

    local step = tonumber(delta)
    if step ~= 1 and step ~= -1 then return false end

    local target = index + step
    if target < 1 or target > #list then return false end

    list[index], list[target] = list[target], list[index]
    return true
end

--============================================================================
-- Compiling and deciding
--============================================================================

--- Compile the rules for comparison.
--
-- The only place where tables are allocated and strings parsed. Everything the
-- decision uses afterwards lies in two maps: spell id -> rule and name key ->
-- rule.
--
-- A rule that changes nothing (neither the size, nor the colour, nor the
-- sound) does not reach the plan: there is nothing to compare against it,
-- while it costs as much as one that does something. A corrupt entry in the
-- saved variables — people edit them by hand — is skipped the same way.
--
-- A map is taken by the first rule to name the entry: the list is read top to
-- bottom, and the earlier one outranks. The rule's position stays with it
-- (rank), because the dispute between the maps is settled in the hot path.
--
-- @param list table|nil the array of rules from the saved variables
-- @return table the plan
function Rules.Compile(list)
    local plan = {
        byName   = {},
        byId     = {},
        count    = 0,
        hasNames = false,
        hasSound = false,
    }
    if type(list) ~= "table" then return plan end

    for i = 1, #list do
        local entry = list[i]
        if type(entry) == "table" then
            local ids, names, count = Rules.Split(entry.text)
            if count > 0 then
                local rule = {
                    rank  = i,
                    name  = trim(entry.name) or "",
                    scale = Rules.Scale(entry.scale),
                    color = trim(entry.color),
                    sound = entry.sound and true or false,
                }

                if rule.scale ~= SCALE.default or rule.color ~= nil
                    or rule.sound then
                    local claimed = false

                    for id in pairs(ids) do
                        if plan.byId[id] == nil then
                            plan.byId[id] = rule
                            claimed = true
                        end
                    end

                    for key in pairs(names) do
                        if plan.byName[key] == nil then
                            plan.byName[key] = rule
                            plan.hasNames = true
                            claimed = true
                        end
                    end

                    if claimed then
                        plan.count = plan.count + 1
                        if rule.sound then plan.hasSound = true end
                    end
                end
            end
        end
    end

    return plan
end

--- Whether there is any rule in effect at all.
--
-- Asked first in the hot path, and at the defaults it answers no: a fresh
-- install must not pay for the rules with a single lookup.
-- @param plan table|nil
-- @return boolean
function Rules.Any(plan)
    return type(plan) == "table" and plan.count > 0
end

--- Whether the decision needs the name key.
-- Asked before the key is created: while there is not one name among the
-- rules, there is nothing to fold every aura's name against. A key is a new
-- string per aura per update.
-- @param plan table|nil
-- @return boolean
function Rules.NeedsKey(plan)
    return type(plan) == "table" and plan.hasNames and true or false
end

--- Whether there is any rule with a sound.
-- While there is none, the memory of endings is not created at all.
-- @param plan table|nil
-- @return boolean
function Rules.HasSound(plan)
    return type(plan) == "table" and plan.hasSound and true or false
end

--- Which rule this aura got.
--
-- A hot path: called for every aura that passed the filter. Not one table, not
-- one string, not one loop — two lookups in a finished map and one comparison,
-- and that only when both of them matched.
--
-- @param plan table|nil the plan from Compile
-- @param key string|nil the name key (Rules.Key)
-- @param id number|nil the spell's id
-- @return table|nil the rule
function Rules.For(plan, key, id)
    if type(plan) ~= "table" then return nil end

    local byId = id ~= nil and plan.byId[id] or nil
    local byName = key ~= nil and plan.byName[key] or nil

    if byId == nil then return byName end
    if byName == nil then return byId end

    -- The two maps named different rules: the one that stands earlier in the
    -- player's list outranks.
    if byName.rank < byId.rank then return byName end
    return byId
end

--============================================================================
-- The memory of endings
--============================================================================

--- Create an empty memory of endings.
--
-- Two tables and an armed flag. The tables are reused and swapped: auras
-- change during a fight, and a fresh table per update would cost the player
-- frames.
-- @return table
function Rules.NewWatch()
    return { seen = {}, fresh = {}, armed = false }
end

--- Forget everything seen and disarm.
--
-- Called everywhere the chain from the previous set to the current one breaks:
-- an edit of the settings, entering the world, the module being switched on
-- and off. The first set after that is only remembered, and there will be no
-- sound on it.
-- @param watch table|nil
function Rules.Disarm(watch)
    if type(watch) ~= "table" then return end
    for token in pairs(watch.seen) do watch.seen[token] = nil end
    for token in pairs(watch.fresh) do watch.fresh[token] = nil end
    watch.armed = false
end

--- Mark an aura as present in the current set.
-- @param watch table|nil
-- @param token any the aura's name in the memory (Rules.Token)
function Rules.Watch(watch, token)
    if type(watch) ~= "table" or token == nil then return end
    watch.fresh[token] = true
end

--- Close the set and say how many auras ended.
--
-- One that was in the previous set and is not in the current one has ended.
-- While the memory is not armed the answer is zero for any set: there is
-- nothing to compare against.
--
-- The sets are swapped rather than copied: these are two tables for the whole
-- module.
--
-- @param watch table|nil
-- @return number how many auras ended
function Rules.Settle(watch)
    if type(watch) ~= "table" then return 0 end

    local ended = 0
    if watch.armed then
        for token in pairs(watch.seen) do
            if not watch.fresh[token] then ended = ended + 1 end
        end
    end

    local old = watch.seen
    watch.seen = watch.fresh
    watch.fresh = old
    for token in pairs(old) do old[token] = nil end

    watch.armed = true
    return ended
end

--============================================================================
-- The sound
--============================================================================

-- The door outwards. The module does not replace it — the tests do:
-- otherwise the sound would be tested only in the client, that is, nowhere.
--
-- The addon has no sound file of its own, and there is no reason to add one
-- for a single rule: the game gives its own. There are two paths, and the one
-- that exists on this client is chosen — by the object's existence rather than
-- by the build number. The Master channel is needed because a warning sound
-- has to be audible also when the player has turned the spell sounds down.
local hooks = {
    Play = function()
        if type(PlaySound) ~= "function" then return false end

        if type(SOUNDKIT) == "table" and SOUNDKIT.RAID_WARNING then
            if pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") then
                return true
            end
            return (pcall(PlaySound, SOUNDKIT.RAID_WARNING))
        end

        -- Old clients know the name rather than the id.
        return (pcall(PlaySound, "RaidWarning"))
    end,
}
Rules.hooks = hooks

--- Replace the door outwards.
-- @param replacements table|nil name -> function
function Rules.Setup(replacements)
    if type(replacements) ~= "table" then return end
    for name, fn in pairs(replacements) do
        if hooks[name] ~= nil and type(fn) == "function" then
            hooks[name] = fn
        end
    end
end

--- Play the ending sound.
--
-- No more than one per repaint — it is called with the number of auras that
-- ended rather than once per aura: three sounds at once add up to a noise in
-- which not one piece of news can be made out.
--
-- @param ended any how many auras ended
-- @return boolean whether it played
function Rules.Play(ended)
    local count = tonumber(ended)
    if not count or count < 1 then return false end
    return hooks.Play() and true or false
end
