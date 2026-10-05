local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- Rules for a single unit: a look of its own for a creature the player named.
--
-- === What a rule is ===
--
-- A rule is a list of creatures plus what sets their nameplate apart from the
-- rest. The list is typed as the list of spells in the aura filter is:
-- separated by commas or one per line, and an entry may be either a name or a
-- creature id. The core parses it (Darken:GetAuraFilter().Split), not us: the
-- question "a name or an id" is already answered there, and a second parser
-- beside the first would diverge from it silently — exactly the way the aura
-- filter and the case folding had already diverged.
--
-- Why not a name alone. The name is what the player knows and can type, and
-- without it a rule could not be created at all: the player never sees a
-- creature's id anywhere. But a name belongs to the client's language and is
-- not unique: an English word finds no creature at all on a Russian client,
-- while a common title finds a dozen and a half different creatures. An id
-- depends neither on the language nor on coincidences. So both are accepted,
-- what the player typed is stored, and whatever matched is compared.
--
-- === What a rule changes ===
--
-- Two things, and both are about the look:
--
--   the health bar's colour — what rules are asked for in the first place: a
--       named creature has to stand out among twenty like it;
--   the size — a multiplier over the nameplate's common scale, because
--       "stands out" is read not only by colour, and on thirty nameplates
--       first of all by size.
--
-- What a rule deliberately does not change:
--
--   the name's colour separately from the bar's. One display function
--       (Plate.SetColor) writes the bar's colour and the name's colour from
--       one triple of numbers, and splitting them would mean a second owner of
--       the colour — the very defect the precedence declared in Colors.Bar
--       forbids;
--   the width and the height. The width stands in the arithmetic of
--       shortening names (Names.Fit) and in the layout (Geometry.Layout), and
--       a width of its own per unit would mean recomputing the layout for
--       every creature that appeared instead of once per edit of a setting.
--       The scale carries no such price: it is one call into the engine, and
--       not one number of ours depends on it;
--   the cast bar, the aura icons and the quest icon. Those are not the look
--       but the contents of the display, and each of them is already switched
--       on by a switch of its own for the whole screen. A switch per rule
--       would multiply the settings section by the number of rules, while the
--       answer to "what for" is not stated for any of the three.
--
-- === The cost ===
--
-- The work is laid out by cost the same way the aura filter is, and for the
-- same reason: there may be three dozen rules, as many nameplates on screen,
-- and walking the list for every creature on every repaint is precisely the
-- way addons bring the frame rate down in a raid.
--
--   Compile — parsing the list of rules into two maps. Called when the
--       settings have changed: entering the game, changing the profile,
--       editing a field. The only place where tables are allocated and strings
--       parsed.
--
--   For — the decision about one unit. No tables, no strings, no loops: one or
--       two lookups in a finished map and, at worst, one comparison. The cost
--       depends neither on the number of rules nor on the number of
--       nameplates.
--
-- A fresh install: there are no rules, Any answers "no", and the hot path
-- performs not one extra action at all — neither case folding nor reading a
-- GUID.
--
-- === Precedence between rules ===
--
-- Two rules may name one creature: one by name and the other by id, or both by
-- name. The dispute is settled by the rule's position in the player's list —
-- the earlier one outranks. The argument is the same as for the bag rules: a
-- precedence that cannot be seen by eye in the list the player will be able
-- neither to predict nor to correct.
--
-- Half the dispute is closed at compile time already: a map is taken by the
-- first rule to name the entry, and the second simply does not reach it. What
-- is left is a dispute between the maps — a name against an id — and one
-- comparison of rank settles it.

-- The core's shared filter: parsing the list (Split) is its work, not ours.
-- Case folding is the core's as well and is taken through its own door
-- (Darken:GetCasefold, contract version 9): there is not even one line of a
-- copy here that could diverge.
local aura = type(Darken) == "table"
    and type(Darken.GetAuraFilter) == "function"
    and Darken:GetAuraFilter() or nil
local casefold = type(Darken) == "table"
    and type(Darken.GetCasefold) == "function"
    and Darken:GetCasefold() or nil
if type(aura) ~= "table" or type(casefold) ~= "table" then return end

local Rules = {}
ns.Rules = Rules

-- The size multiplier. The bounds are not a matter of taste: a nameplate four
-- times smaller than the rest cannot be read, while one four times larger
-- covers its neighbours — that is, hides exactly what the rule was created
-- for.
local SCALE = { min = 0.5, max = 2, default = 1 }
Rules.SCALE = SCALE

-- The greatest number of rules, and how long a rule's name may be. The limits
-- are needed because the list goes into SavedVariables and is shown as a
-- choice list: a thousand rules there mean a settings window that cannot be
-- opened.
Rules.MAX = 30
Rules.MAX_NAME = 40

-- The comparison key is the core's function rather than a wrapper around it:
-- the name here is a second name for one and the same function. Cyrillic, the
-- Ukrainian Ґ and accented Latin all fold; what does not fold and why is
-- stated in Core/Casefold.lua.
Rules.Key = casefold.Key

-- The kinds of GUID whose sixth field is a creature id. A player deliberately
-- does not belong here: their GUID is of another kind and has no creature id
-- at all.
local NPC_KINDS = { Creature = true, Vehicle = true, Pet = true }

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

--- One colour channel out of the saved variables.
-- @param value any
-- @return number|nil
local function channel(value)
    local number = tonumber(value)
    if not number or number ~= number then return nil end
    if number < 0 then return 0 end
    if number > 1 then return 1 end
    return number
end

--- A creature's id out of its GUID.
--
-- A pure function: the GUID arrives as a string and is parsed here rather than
-- in the display. The GUID's kind stands as its first field, and it is checked
-- directly: a player has no creature id, and taking their sixth field for one
-- would mean painting a random player by a rule written about a boar.
--
-- @param guid any
-- @return number|nil
function Rules.NpcId(guid)
    if type(guid) ~= "string" then return nil end

    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == nil or not NPC_KINDS[kind] then return nil end

    return tonumber(id)
end

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
-- rule without a name cannot be picked from the list. The list of creatures is
-- required: a rule aimed at nobody would stand there as a row that does
-- nothing. A name is not repeated: two identical headings in one choice list
-- cannot be told apart.
--
-- @param list table array of rules (edited in place)
-- @param name any the rule's name
-- @param text any the list of creature names and ids
-- @return table|nil the rule that was created
-- @return string|nil the refusal code
function Rules.Add(list, name, text)
    if type(list) ~= "table" then return nil, "noname" end

    local clean = trim(name)
    if clean == nil then return nil, "noname" end
    if #clean > Rules.MAX_NAME then return nil, "long" end

    local _, _, count = aura.Split(text)
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

--- Rewrite a rule's list of creatures.
-- @param list table
-- @param name any
-- @param text any
-- @return boolean
-- @return string|nil the refusal code
function Rules.SetText(list, name, text)
    local index, rule = Rules.Find(list, name)
    if index == nil then return false, "gone" end

    local _, _, count = aura.Split(text)
    if count == 0 then return false, "notext" end

    rule.text = trim(text)
    return true, nil
end

--- Set or remove a rule's colour.
-- A nil instead of a channel means "do not change the colour": a rule is
-- entitled to change the size alone, and then the bar is painted by the
-- ordinary precedence.
-- @param list table
-- @param name any
-- @param r any
-- @param g any
-- @param b any
-- @return boolean
function Rules.SetColor(list, name, r, g, b)
    local index, rule = Rules.Find(list, name)
    if index == nil then return false end

    local cr, cg, cb = channel(r), channel(g), channel(b)
    if cr == nil or cg == nil or cb == nil then
        rule.color = nil
        return true
    end

    rule.color = { cr, cg, cb }
    return true
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

--- Compile the rules for comparison.
--
-- The only place where tables are allocated and strings parsed. Everything the
-- decision uses afterwards lies in two maps: creature name -> rule and
-- creature id -> rule.
--
-- A rule that changes nothing (neither the colour nor the size) does not reach
-- the plan: there is nothing to compare against it, while it costs as much as
-- one that does something. A corrupt entry in the saved variables — people
-- edit them by hand — is skipped the same way.
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
        hasIds   = false,
    }
    if type(list) ~= "table" then return plan end

    for i = 1, #list do
        local entry = list[i]
        if type(entry) == "table" then
            local ids, names, count = aura.Split(entry.text)
            if count > 0 then
                local rule = { rank = i, scale = Rules.Scale(entry.scale) }

                rule.name = trim(entry.name) or ""

                local color = entry.color
                if type(color) == "table" then
                    local r = channel(color[1] ~= nil and color[1] or color.r)
                    local g = channel(color[2] ~= nil and color[2] or color.g)
                    local b = channel(color[3] ~= nil and color[3] or color.b)
                    if r and g and b then rule.r, rule.g, rule.b = r, g, b end
                end

                if rule.r ~= nil or rule.scale ~= SCALE.default then
                    local claimed = false

                    for id in pairs(ids) do
                        if plan.byId[id] == nil then
                            plan.byId[id] = rule
                            plan.hasIds = true
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

                    if claimed then plan.count = plan.count + 1 end
                end
            end
        end
    end

    return plan
end

--- Whether there is any rule in effect at all.
--
-- Asked first in the hot path, and at the defaults it answers no: a fresh
-- install must pay neither for case folding nor for reading a GUID.
-- @param plan table|nil
-- @return boolean
function Rules.Any(plan)
    return type(plan) == "table" and plan.count > 0
end

--- Whether the decision needs the name key.
-- Asked before the key is created: while there is not one name among the
-- rules, there is nothing to fold every creature's name against.
-- @param plan table|nil
-- @return boolean
function Rules.NeedsKey(plan)
    return type(plan) == "table" and plan.hasNames and true or false
end

--- Whether the decision needs the creature id.
-- For the same reason: reading a GUID and parsing it is work, and there is no
-- point doing it for a map that holds not one id.
-- @param plan table|nil
-- @return boolean
function Rules.NeedsId(plan)
    return type(plan) == "table" and plan.hasIds and true or false
end

--- Which rule this unit got.
--
-- A hot path: called for every creature that appears and on every repaint. Not
-- one table, not one string, not one loop — two lookups in a finished map and
-- one comparison, and that only when both of them matched.
--
-- @param plan table|nil the plan from Compile
-- @param key string|nil the creature's name key (Rules.Key)
-- @param id number|nil the creature's id (Rules.NpcId)
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

--- A nameplate's scale with the rule taken into account.
--
-- A multiplier rather than a number of its own: the nameplate's common scale
-- is the player's setting, and a rule that replaced it entirely would untie
-- the named creature from the slider the player had just been moving.
--
-- @param rule table|nil the rule from the plan
-- @param base any the common scale from the settings
-- @return number
function Rules.Apply(rule, base)
    local value = tonumber(base)
    if not value or value ~= value or value <= 0 then value = 1 end

    if type(rule) == "table" then
        local factor = tonumber(rule.scale)
        if factor and factor == factor and factor > 0 then
            value = value * factor
        end
    end

    return value
end
