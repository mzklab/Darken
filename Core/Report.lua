local ADDON, ns = ...

-- The client report: what of everything the compatibility layer declares was
-- found in this client and what was not, and which subsystems therefore did
-- nothing.
--
-- WHY IT EXISTS. Almost every name in Core/Compat.lua is a guess. The
-- existence filter makes a wrong guess safe: there is no error and the addon
-- does not fail. But safety has exactly one consequence — the subsystem
-- silently does nothing, and from outside that is indistinguishable from a
-- breakage. The name directory (Core/Scan.lua) collects itself at login and
-- was step one: it supplies the raw material. Here is step two — an answer
-- rather than raw material.
--
-- THE FILE'S MAIN RULE: the report has no right to err towards the
-- reassuring answer. A group called whole while it is empty is worse than no
-- report at all — the author would stop looking where it is broken. So every
-- default here is pessimistic: a group this file knows nothing about is
-- treated as required in full rather than as "probably fine".
--
-- THREE DIFFERENT EMPTIES. They must be told apart, or the report turns into
-- noise, and noise is read once.
--
-- 1. "Empty on purpose" — the group does not exist in this client at all.
--    That is recorded not by an empty list but by the absence of the key from
--    the compatibility table: vanilla never has a focus cast bar, and vanilla
--    has no "castbar-focus" key. Such a group goes into the `absent` section
--    and is never counted as a problem.
--
-- 2. "Empty by mistake" — the group is declared for this client and not one
--    name was found. That is the wrong guess, and it is the one thing the
--    report was written for.
--
-- 3. "Not there yet" — the game creates the group's frames not at login but
--    when the player opens a window, takes a target or joins a group. Such an
--    empty group means neither "present" nor "absent": it means "there is
--    nothing to judge by". The report answers it with the word `unconfirmed`
--    and asks for the window to be opened and the report run again — and
--    never answers "all is well". An error here would cost exactly the
--    reassuring lie the whole file is written against.
--
-- THE OTHER HALF OF THE ANSWER. Everything above answers "what exists in this
-- client". The blind half is "what we managed to do with it", and usually it
-- is the one that is needed: a group that found twelve names and a subsystem
-- that touched no object in twenty minutes of play — both statements are
-- true, and only the second explains anything. The tally of work done lives
-- in Core/Tally.lua, arrives here as an analysis and is printed in the same
-- lines: the author has one command, not two.
--
-- Everything in this file is pure functions: the globals table and the facts
-- about the client arrive as arguments, and the game is not called from here.
-- So each kind of verdict is tested outside the client
-- (tests/test_report.lua).
local Report = {}
ns.Report = Report

-- The format version of the record in the saved variables. The author reads
-- the report from disk, possibly one not written today; the number says what
-- to read it with.
--
-- 2 — the `stamp` section was added: by what and when this report was
-- assembled. Nothing was removed or renamed, and a reader of version one
-- reads version two as well.
Report.VERSION = 2

--============================================================================
-- Verdicts and kinds of group
--============================================================================

-- A group's verdict. Strings rather than numbers: the report is read by eye
-- from disk.
Report.OK          = "ok"          -- as much was found as this kind needs
Report.PARTIAL     = "partial"     -- part was found where all was expected
Report.MISSING     = "missing"     -- declared for this client, nothing found
Report.UNCONFIRMED = "unconfirmed" -- empty, but nothing to judge by yet
Report.DEGRADED    = "degraded"    -- an empty hook group: a fallback remains
Report.ABSENT      = "absent"      -- not declared for this client at all

-- A group's kind: how many names from its list are enough for it to count as
-- whole. Without that distinction the report would be useless: "found 1 of 2"
-- is normal for a cast bar (the list holds two spellings of one frame) and a
-- loss for a list of unit frames.
Report.REQUIRED     = "required"     -- every name is expected
Report.ALTERNATIVES = "alternatives" -- spellings of one thing; one is enough
Report.SERIES       = "series"       -- the cap on slots is knowingly too high
Report.HOOKS        = "hooks"        -- game functions for hooksecurefunc

-- The label of the subsystem an empty group costs work, the group's kind,
-- and the "does not appear at once" marker.
--
-- The labels are the ones these things already carry in the settings window:
-- "Main Action Bar", "Minimap", "Character Sheet". A second name for the same
-- thing in the report would leave the author guessing what is meant.
--
-- The `later` field is not "it may be absent" but "there is nothing to judge
-- by at this moment", and its text says what to do so that there is. It is
-- English and untranslated: the author reads it from disk, not the player in
-- chat.
local CONSEQUENCE = {
    unitframe = { label = "Unit Frames", kind = Report.REQUIRED },
    ["unitframe-recolor"] = { label = "Unit Frames", kind = Report.HOOKS },
    ["unitframe-auras"] = {
        label = "Auras on Unit Frames", kind = Report.SERIES,
        later = "the game makes these buttons only when the unit has auras: "
            .. "take a target with a buff on it and run the report again",
    },
    ["unitframe-auras-relayout"] = {
        label = "Auras on Unit Frames", kind = Report.HOOKS,
    },

    ["castbar-player"] = { label = "Player Cast Bar", kind = Report.ALTERNATIVES },
    ["castbar-target"] = { label = "Target Cast Bar", kind = Report.ALTERNATIVES },
    ["castbar-focus"]  = { label = "Focus Cast Bar",  kind = Report.ALTERNATIVES },

    nameplate = { label = "Nameplates", kind = Report.REQUIRED },
    ["nameplate-recolor"] = { label = "Nameplates", kind = Report.HOOKS },

    minimap    = { label = "Minimap",            kind = Report.SERIES },
    -- The ring alone, and alternatives because the art is named
    -- differently from one client line to the next. Missing it costs
    -- one setting (a square minimap keeps its round ring) and nothing
    -- else: the map is still cut to shape.
    ["minimap-ring"] = { label = "Minimap", kind = Report.ALTERNATIVES },
    -- The world map's canvas. It is looked up in order NOT to touch it, so
    -- an empty group is no trouble here: in a build where no name was found
    -- the map simply stays in the general pass.
    ["map-canvas"] = { label = "World Map", kind = Report.ALTERNATIVES },
    ["panel-switch"] = { label = "Panel Tabs", kind = Report.ALTERNATIVES },
    ["bag-toggle"] = { label = "Bags", kind = Report.ALTERNATIVES },
    ["bag-frames"] = { label = "Bag Windows",
        kind = Report.ALTERNATIVES },
    ["color-picker"] = { label = "Color Picker",
        kind = Report.ALTERNATIVES },
    objectives = { label = "Objective Tracker",  kind = Report.ALTERNATIVES },
    chat       = { label = "Chat",               kind = Report.SERIES },
    bags       = { label = "Bags and Micro Menu", kind = Report.SERIES },
    tooltip    = { label = "Tooltips",           kind = Report.SERIES },
    character  = {
        label = "Character Sheet", kind = Report.SERIES,
        later = "parts of the character sheet are made when it is first "
            .. "opened: open it once and run the report again",
    },
    questlog = {
        label = "Quest and Dialog Text", kind = Report.SERIES,
        later = "the quest log is made when it is first opened: open it once "
            .. "and run the report again",
    },

    ["bag-window"] = {
        label = "Bag Windows", kind = Report.SERIES,
        later = "bag windows are made when the bags are first opened: open "
            .. "them once and run the report again",
    },
    ["bag-repaint"] = { label = "Bag Windows", kind = Report.HOOKS },

    auras = { label = "Player Aura Grid", kind = Report.ALTERNATIVES },

    ["unit-tap-denied"] = {
        label = "Tapped Mobs Greyed", kind = Report.ALTERNATIVES,
    },
    ["unit-tapped"] = {
        label = "Tapped Mobs Greyed", kind = Report.ALTERNATIVES,
    },
    ["unit-tapped-by-me"] = {
        label = "Tapped Mobs Greyed", kind = Report.ALTERNATIVES,
    },

    ["addon-count"] = {
        label = "Other Addons' Windows", kind = Report.ALTERNATIVES,
    },
    ["addon-info"] = {
        label = "Other Addons' Windows", kind = Report.ALTERNATIVES,
    },

    ["aura-buttons"] = {
        label = "Icon Borders", kind = Report.SERIES,
        later = "the game makes these buttons as auras appear: take a buff "
            .. "and run the report again",
    },
    ["aura-debuff-buttons"] = {
        label = "Icon Borders", kind = Report.SERIES,
        later = "the game makes these buttons as auras appear: take a "
            .. "debuff and run the report again",
    },

    ["equipment-slots"] = {
        label = "Item Level on Equipment", kind = Report.SERIES,
        later = "the equipment buttons come with the character sheet: open "
            .. "it once and run the report again",
    },
    ["equipment-slots-inspect"] = {
        label = "Item Level on Equipment", kind = Report.SERIES,
        later = "the inspect window is a separate load-on-demand part: "
            .. "inspect somebody once and run the report again",
    },
    ["inspect-window"] = {
        label = "Item Level on Equipment", kind = Report.ALTERNATIVES,
        later = "the inspect window is a separate load-on-demand part: "
            .. "inspect somebody once and run the report again",
    },

    ["raidframe-container"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
        later = "group frames are made when you are in a group: join one and "
            .. "run the report again",
    },
    ["raidframe-member"] = {
        label = "Raid Frames", kind = Report.SERIES,
        later = "member frames are made when you are in a group: join one "
            .. "and run the report again",
    },
    ["raidframe-setup"]    = { label = "Raid Frames", kind = Report.ALTERNATIVES },

    -- The group role and an incoming resurrection. An empty group is not
    -- necessarily a wrong name: roles do not exist as a concept on the early
    -- line, and the role icon is simply not drawn there.
    ["unit-role"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
        later = "group roles do not exist on every client: where they do "
            .. "not, the role icon is simply not drawn",
    },
    ["unit-resurrect"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
        later = "incoming resurrection is not told on every client: where it "
            .. "is not, that icon is simply not drawn",
    },

    -- The threat level. An empty group is not necessarily a wrong name: on
    -- the early line the game does not express threat as a number at all, and
    -- there is then nothing to show.
    ["unit-threat"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
        later = "threat is not a number on every client: where it is not, "
            .. "the threat outline is simply not drawn",
    },

    -- The spellbook. Two spellings of one thing; either will do.
    ["spellbook-item-name"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
    },
    ["spellbook-bank"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
    },

    -- Reading a unit's auras. Two spellings of one thing; either will do.
    ["unit-aura"] = { label = "Auras on Unit Frames", kind = Report.ALTERNATIVES },

    -- Overlays on the health bar: incoming heals, a shield, a heal absorb.
    -- An empty group here is not necessarily a wrong name: the early line's
    -- game does not compute such quantities at all, and there is then nothing
    -- to draw. The layer has no way to tell one from the other, so the entry
    -- carries `later`.
    ["heal-incoming"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
        later = "heal prediction does not exist on every client: where it "
            .. "does not, the incoming-heal overlay is simply not drawn",
    },
    ["absorb-shield"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
        later = "damage absorbs do not exist on every client: where they do "
            .. "not, the shield overlay is simply not drawn",
    },
    ["absorb-heal"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
        later = "heal absorbs do not exist on every client: where they do "
            .. "not, the overlay is simply not drawn",
    },

    -- The character's specialization. The group is declared for one client
    -- out of three — the early line has no specializations at all — so on the
    -- others it is not asked about here: an empty group there would mean "the
    -- name was not found", that is, our mistake, whereas the right answer is
    -- "there is no such concept".
    ["player-spec"] = {
        label = "Raid Frames", kind = Report.ALTERNATIVES,
        later = "specializations do not exist on every client: where they do "
            .. "not, click sets are chosen per character and the question "
            .. "about specialization is not asked at all",
    },
    ["raidframe-relayout"] = { label = "Raid Frames", kind = Report.HOOKS },

    -- Container functions: reading the bags and moving things between them.
    -- A group of spellings — the client offers either the table-based or the
    -- global one, and one found is enough for "ok".
    --
    -- Five entries rather than one, and that is not splitting for splitting's
    -- sake: a client that gave the bag's size and not its contents is a
    -- different trouble from a client that gave nothing, and one entry for
    -- all five would say "something was found" in both cases.
    --
    -- None of them carries `later`, and that is a decision rather than an
    -- omission. For the entries above, an empty group can be the truth about
    -- the client: heal prediction and absorbs genuinely do not exist on every
    -- client. Here it is not so — bags exist on every supported client, and an
    -- empty group means exactly one thing: this client reads them by a third
    -- way we do not know about. The verdict has to be a loss: otherwise five
    -- modules would silently stop working at once.
    ["container-slots"]      = { label = "Bag Reading", kind = Report.ALTERNATIVES },
    ["container-item"]       = { label = "Bag Reading", kind = Report.ALTERNATIVES },
    ["container-free-slots"] = { label = "Bag Reading", kind = Report.ALTERNATIVES },
    ["container-item-link"]  = { label = "Bag Reading", kind = Report.ALTERNATIVES },
    ["container-pickup"]     = { label = "Bag Sorting", kind = Report.ALTERNATIVES },

    ["actionbar-main"]                = { label = "Main Action Bar",  kind = Report.ALTERNATIVES },
    ["actionbar-main-buttons"]        = { label = "Main Action Bar",  kind = Report.SERIES },
    ["actionbar-bottomleft"]          = { label = "Bottom Left Bar",  kind = Report.ALTERNATIVES },
    ["actionbar-bottomleft-buttons"]  = { label = "Bottom Left Bar",  kind = Report.SERIES },
    ["actionbar-bottomright"]         = { label = "Bottom Right Bar", kind = Report.ALTERNATIVES },
    ["actionbar-bottomright-buttons"] = { label = "Bottom Right Bar", kind = Report.SERIES },
    ["actionbar-right"]               = { label = "Right Bar",        kind = Report.ALTERNATIVES },
    ["actionbar-right-buttons"]       = { label = "Right Bar",        kind = Report.SERIES },
    ["actionbar-left"]                = { label = "Second Right Bar", kind = Report.ALTERNATIVES },
    ["actionbar-left-buttons"]        = { label = "Second Right Bar", kind = Report.SERIES },
    ["actionbar-pet"]                 = { label = "Pet Bar",          kind = Report.ALTERNATIVES },
    ["actionbar-pet-buttons"]         = { label = "Pet Bar",          kind = Report.SERIES },
    ["actionbar-stance"]              = { label = "Stance Bar",       kind = Report.ALTERNATIVES },
    ["actionbar-stance-buttons"]      = { label = "Stance Bar",       kind = Report.SERIES },
    -- The "leave vehicle" button: a child of the main bar, and whoever hides
    -- the bar hides it along with it. Different spellings of one thing — one
    -- is enough.
    ["actionbar-vehicle"]             = { label = "Leave Vehicle Button", kind = Report.ALTERNATIVES },

    -- The quest button and the zone ability: they come and go on their own
    -- and have nothing to do with the bars. Any of the spellings will do.
    ["actionbar-extra"]               = { label = "Extra Action Button",  kind = Report.ALTERNATIVES },

    ["actionbar-art"]                 = { label = "Action Bar Art",   kind = Report.ALTERNATIVES },
    ["actionbar-relayout"]            = { label = "Action Bar Layout", kind = Report.HOOKS },

    -- Edit mode is asked about not in order to meddle with it but for
    -- exactly the opposite reason: while it is open the position of the bars
    -- and unit frames belongs to it and the addon does nothing. If the client
    -- does not have it, there is nothing to ask.
    ["editmode"]                      = { label = "Edit Mode",        kind = Report.ALTERNATIVES },
}
Report.CONSEQUENCE = CONSEQUENCE

-- What the report says about a group absent from the table above.
--
-- The pessimism here is not caution but the file's own rule. A new group in
-- Core/Compat.lua that was forgotten here has to count as required and land
-- in the list of losses rather than quietly count as healthy. A test will say
-- that it was forgotten here (tests/test_report.lua), but it can only say so
-- to the author and only outside the game; in a live client it is this entry
-- that has to answer.
local UNDESCRIBED = { label = "An Unnamed Group", kind = Report.REQUIRED }

--- The description of what an empty group costs.
-- @param group string
-- @return table {label, kind, later}
function Report.Consequence(group)
    return CONSEQUENCE[group] or UNDESCRIBED
end

--============================================================================
-- The verdict
--============================================================================

--- The verdict on one group.
--
-- The order of the checks here is the rule "never towards the reassuring
-- answer": "nothing to judge by" comes before every other outcome, because it
-- is the one answer that can be replaced neither by "whole" nor by "empty".
--
-- @param kind string the group's kind (Report.REQUIRED and its neighbours)
-- @param later string|nil non-empty if the frames do not appear at once
-- @param declared number how many names are declared
-- @param found number how many were found
-- @return string the verdict
function Report.Judge(kind, later, declared, found)
    declared = tonumber(declared) or 0
    found = tonumber(found) or 0

    -- A group with no declared names is not declared for this client at
    -- all.
    if declared <= 0 then return Report.ABSENT end

    if found <= 0 then
        if later ~= nil and later ~= "" then return Report.UNCONFIRMED end
        -- An empty hook group is not a failure: every subsystem that uses
        -- them has a fallback written down (the next frame, or an event).
        -- Slower, but it works.
        if kind == Report.HOOKS then return Report.DEGRADED end
        return Report.MISSING
    end

    -- Fewer found than declared is a loss only where all were expected. For
    -- a list of spellings of one frame, for a cap on slots and for hooks that
    -- is normal by construction.
    if kind == Report.REQUIRED and found < declared then
        return Report.PARTIAL
    end

    return Report.OK
end

--============================================================================
-- Paths that got halfway
--============================================================================
--
-- A name in a group can be a path, MainActionBar.LeftEndCap for one, and a
-- path that was not found has two different fates which must read
-- differently.
--
-- "Nothing at all" — the first step was not found: the client does not even
-- have the object we were looking inside. That is the ordinary "the name was
-- guessed wrong".
--
-- "The middle is there, the end is not" — the object was found and the field
-- in it was not. That is a different fact, and the only one that says we are
-- close: what to look for is not another frame but another field name in this
-- same frame. Without it the author would re-check the whole spelling, while
-- what needs re-checking is one step.
--
-- The group's verdict does not change because of this: not found is not
-- found, and there is no such thing as an "almost" working setting. What
-- changes is what the report says next.

--- A record about a path that got halfway.
-- @param compat table the compatibility layer
-- @param globals table the globals table
-- @param path string a name or a path
-- @return table|nil a record {path, prefix, parts, reached, stopped, blocked}
local function nearMiss(compat, globals, path)
    if type(compat.LookupSteps) ~= "function" then return nil end

    local object, info = compat.LookupSteps(globals, path)
    if object ~= nil then return nil end

    -- One step is a plain name, and it has no "middle". Zero steps taken
    -- means even the beginning was not found.
    if info.parts < 2 or info.reached < 1 then return nil end

    local parts = compat.PathParts(path)
    local head = {}
    for i = 1, info.reached do head[i] = parts[i] end

    return {
        path    = path,
        prefix  = table.concat(head, "."),
        parts   = info.parts,
        reached = info.reached,
        stopped = info.stopped,
        blocked = info.blocked == true,
    }
end

-- How many missing names to record per group. The cap exists for the
-- readability of the saved file: a series of slots can be missing close to a
-- hundred names, and all of them are the same single fact — "there are fewer
-- slots than the cap".
local MISSING_LIMIT = 50

--============================================================================
-- Assembly
--============================================================================

--- Assemble the report.
--
-- @param flavor string the flavour's name (ns.flavor)
-- @param globals table the client's globals; _G in the game
-- @param facts table|nil facts about the client: build, interface, scale,
--        screen, locale
-- @param compat table|nil the compatibility layer; ns.Compat by default
-- @param counters table|nil the tally counters; ns.Counters by default
-- @param registry table|nil the module registry; ns.Registry by default
-- @param events table|nil the events subsystem; ns.Events by default
-- @return table the report
function Report.Build(flavor, globals, facts, compat, counters, registry, events)
    compat = compat or ns.Compat
    globals = type(globals) == "table" and globals or {}
    facts = type(facts) == "table" and facts or {}

    local out = {
        version   = Report.VERSION,
        -- By what and when this report was assembled. It stands next to the
        -- format version and before everything else: the first thing asked of
        -- a record found on disk is not what is in it but where it came
        -- from.
        stamp     = Report.Stamp(globals),
        flavor    = flavor,
        build     = facts.build,
        interface = facts.interface,
        scale     = facts.scale,
        screen    = facts.screen,
        locale    = facts.locale,
        counts    = {
            ok = 0, partial = 0, missing = 0,
            unconfirmed = 0, degraded = 0, absent = 0,
        },
        groups = {},   -- group -> record
        order  = {},   -- group names alphabetically, for stable reading
        absent = {},   -- groups not declared for this client
        worst  = {},   -- empty by mistake, the large ones first
        watch  = {},   -- guesses that need confirming
        near   = {},   -- paths that got halfway: one step left to find
    }

    -- Paths that got halfway are collected from the whole report at once —
    -- from the groups and from the watch list alike. One path can be recorded
    -- in both places (the main bar's chrome is recorded that way), and naming
    -- it twice would count one guess as two.
    local nearSeen = {}
    local function remember(record, group)
        if record == nil or nearSeen[record.path] then return end
        nearSeen[record.path] = true
        record.group = group
        out.near[#out.near + 1] = record
    end

    local declared = compat.Groups(flavor)
    local here = {}
    for i = 1, #declared do here[declared[i]] = true end

    for i = 1, #declared do
        local group = declared[i]
        local names = compat.GetFrameNames(flavor, group)
        local rule = Report.Consequence(group)

        -- Existence is asked through the layer rather than by indexing the
        -- table directly: a name in a group can be a path, and
        -- globals[path] would answer "no" even where the object exists. The
        -- same traversal also answers "how far did we get".
        local found, missing, cut = {}, {}, 0
        for j = 1, #names do
            if compat.Lookup(globals, names[j]) ~= nil then
                found[#found + 1] = names[j]
            else
                remember(nearMiss(compat, globals, names[j]), group)
                if #missing < MISSING_LIMIT then
                    missing[#missing + 1] = names[j]
                else
                    cut = cut + 1
                end
            end
        end

        local verdict = Report.Judge(rule.kind, rule.later, #names, #found)
        local entry = {
            group       = group,
            label       = rule.label,
            kind        = rule.kind,
            verdict     = verdict,
            declared    = #names,
            found       = #found,
            foundNames  = found,
            missingNames = missing,
            missingMore = cut,
            later       = rule.later,
        }

        out.groups[group] = entry
        out.order[#out.order + 1] = group
        out.counts[verdict] = (out.counts[verdict] or 0) + 1

        if verdict == Report.MISSING then
            out.worst[#out.worst + 1] = entry
        end
    end

    -- Alternatives sharing one label are judged TOGETHER.
    --
    -- Whose kill it is gets asked through three different functions, and each
    -- client has one of them: the modern one calls UnitIsTapDenied, the
    -- classic ones UnitIsTapped and UnitIsTappedByPlayer. Judged separately,
    -- the two that were not found landed in "missing", and the report twice
    -- called something lost that in fact works: all three carry one label.
    --
    -- The author sent exactly this and asked what was broken. Nothing was
    -- broken — the report was noisy.
    do
        local won = {}
        for _, group in ipairs(out.order) do
            local entry = out.groups[group]
            if entry.kind == Report.ALTERNATIVES and entry.found > 0 then
                won[entry.label] = true
            end
        end

        for _, group in ipairs(out.order) do
            local entry = out.groups[group]
            if entry.kind == Report.ALTERNATIVES
                and entry.verdict == Report.MISSING and won[entry.label] then
                -- Not "found" but "a substitute was found": this name is
                -- still absent from the client, and its list of missing names
                -- stays with it. Only the verdict changes — the report no
                -- longer calls this a loss.
                out.counts[entry.verdict] = (out.counts[entry.verdict] or 1) - 1
                entry.verdict = Report.ABSENT
                out.counts[Report.ABSENT] = (out.counts[Report.ABSENT] or 0) + 1

                for i = #out.worst, 1, -1 do
                    if out.worst[i] == entry then table.remove(out.worst, i) end
                end
            end
        end
    end

    -- Groups declared for other clients and not for this one. No key means
    -- the thing does not exist in this client at all, and that is not a
    -- loss.
    local all = compat.AllGroups()
    for i = 1, #all do
        if not here[all[i]] then
            out.absent[#out.absent + 1] = {
                group = all[i],
                label = Report.Consequence(all[i]).label,
            }
            out.counts.absent = out.counts.absent + 1
        end
    end

    -- A large empty group speaks louder than a small one: forty-eight names
    -- that found not one object is about a whole subsystem.
    table.sort(out.worst, function(a, b)
        if a.declared ~= b.declared then return a.declared > b.declared end
        return a.group < b.group
    end)

    local watch = compat.Watchlist()
    out.watchFound = 0
    for i = 1, #watch do
        local exists = compat.Lookup(globals, watch[i].path) ~= nil
        local record = not exists and nearMiss(compat, globals, watch[i].path)
            or nil
        out.watch[i] = {
            path = watch[i].path,
            note = watch[i].note,
            found = exists,
            -- A path that got halfway is marked here too: the list is read
            -- line by line, and "no" next to "but the first step is there"
            -- are two different answers.
            reached = record and record.reached or nil,
            stopped = record and record.stopped or nil,
        }
        if exists then out.watchFound = out.watchFound + 1 end
        remember(record, nil)
    end
    out.watchTotal = #watch

    -- The order comes from a sort: reports are compared between runs.
    table.sort(out.near, function(a, b) return a.path < b.path end)
    out.nearCount = #out.near

    -- The tally of work done is a separate analysis and a separate section
    -- of the record: it is about a different time (what happened during the
    -- session), and mixing it with the groups' verdicts would give a table in
    -- which neither of the two can be read. The tally subsystem may be absent
    -- from a build — then the section is simply not there and the report
    -- stays as it was.
    if type(ns.Tally) == "table" and type(ns.Tally.Build) == "function" then
        out.tally = ns.Tally.Build(counters, registry, events)
    end

    return out
end

--============================================================================
-- Facts about the client
--============================================================================

--- Ask the client for what is worth keeping next to the report.
--
-- The only place in this file that looks at game functions, and it looks
-- through the globals argument: outside the game they do not exist, and the
-- absence of any of them has no right to break anything. A field that did not
-- answer stays nil — the report shows a question mark for it rather than
-- inventing a number.
--
-- @param globals table|nil the globals table; _G in the game
-- @return table {build, interface, scale, screen, locale}
function Report.ClientFacts(globals)
    globals = type(globals) == "table" and globals or {}
    local out = {}

    local build = globals.GetBuildInfo
    if type(build) == "function" then
        local ok, version, number, _, toc = pcall(build)
        if ok then
            out.build = number and (tostring(version) .. " " .. tostring(number))
                or (version and tostring(version) or nil)
            out.interface = toc and tonumber(toc) or nil
        end
    end

    local parent = globals.UIParent
    if type(parent) == "table" and type(parent.GetEffectiveScale) == "function" then
        local ok, scale = pcall(parent.GetEffectiveScale, parent)
        if ok and type(scale) == "number" then
            -- Through string formatting rather than arithmetic: rounding in
            -- this addon lives in one place (Core/Format.lua), and there is
            -- no reason to grow a second body of it for three decimal
            -- places.
            out.scale = tonumber(string.format("%.3f", scale))
        end
    end

    -- The screen resolution is asked of the engine rather than of UIParent:
    -- UIParent's width is already divided by the scale and is not obliged to
    -- match the resolution. The function may be absent — then the second way
    -- is taken.
    local physical = globals.GetPhysicalScreenSize
    if type(physical) == "function" then
        local ok, width, height = pcall(physical)
        if ok and type(width) == "number" and type(height) == "number" then
            out.screen = string.format("%dx%d", width, height)
        end
    end
    if out.screen == nil and type(parent) == "table"
        and type(parent.GetWidth) == "function" then
        local okW, width = pcall(parent.GetWidth, parent)
        local okH, height = pcall(parent.GetHeight, parent)
        if okW and okH and type(width) == "number" and type(height) == "number" then
            out.screen = string.format("%.0fx%.0f", width, height)
        end
    end

    local locale = globals.GetLocale
    if type(locale) == "function" then
        local ok, value = pcall(locale)
        if ok and type(value) == "string" then out.locale = value end
    end

    return out
end

--============================================================================
-- The build stamp
--============================================================================

-- The answer to a question the report had not heard until now: **what built
-- it**.
--
-- THE COST OF NOT HAVING IT. The author logged in and out; the saved
-- variables were rewritten with a fresh file timestamp while the report
-- inside stayed as it was — the game reads an addon's code only at login and
-- on /reload, and edits made while they were playing never reached the
-- report. Nothing said so. It could only be worked out from fields the old
-- build did not write. A file's timestamp proves the game wrote something; it
-- proves nothing at all about what wrote the contents.
--
-- FOUR FACTS AND NOT ONE MORE. The addon's version from the TOC, the
-- contract's version, the settings schema's version and the time. There is no
-- history here and there will not be: the report answers about now, and a
-- list of past builds would also have to be pruned.
--
-- WHICH CLOCK. The game has several, and they mean different things:
--
--   GetTime()      — seconds since the client started. Monotonic and good
--                    within a session, but after logout it means nothing:
--                    1743.8 in a file read three days later compares to
--                    nothing.
--   GetServerTime()— the server's time. A real number, but its time zone is
--                    its own, and it differs by hours from the clock on the
--                    machine where Darken.lua lies.
--   date()         — the wall clock of that very machine.
--
-- The last was taken. The only things a reader can compare the stamp against
-- are the file's modification time on disk and their own "I logged in an hour
-- ago"; both are the local clock. A clock with nothing to compare against is
-- decoration.
--
-- The order in the record, year-month-day hours:minutes:seconds, was chosen
-- because such strings compare as strings: two stamps sort without being
-- parsed.
local WHEN_FORMAT = "%Y-%m-%d %H:%M:%S"

-- What there is nobody to ask. A word, rather than a missing key or nil: a
-- field absent from the record reads as "we forgot to write it", while
-- unknown reads as "we asked and got no answer". A client without `date` must
-- yield this word here rather than an invented number.
Report.UNKNOWN = "unknown"

--- What built the report, and when.
--
-- Two game functions are reached from here (the version from the TOC through
-- Core/Api.lua, the time through the globals argument), and either may be
-- absent: outside the game there are none at all. A field that did not answer
-- gets Report.UNKNOWN.
--
-- @param globals table|nil the globals table; _G in the game
-- @return table {addon, api, settings, when}
function Report.Stamp(globals)
    globals = type(globals) == "table" and globals or {}

    local out = {
        addon    = Report.UNKNOWN,
        api      = Report.UNKNOWN,
        settings = Report.UNKNOWN,
        when     = Report.UNKNOWN,
    }

    -- The addon's version is asked at the same door the modules use
    -- (Api:GetVersion) rather than by reading the TOC again: a second place
    -- where our version is written would diverge from the first
    -- silently.
    local api = ns.Api
    if type(api) == "table" then
        if type(api.GetVersion) == "function" then
            local ok, value = pcall(api.GetVersion, api)
            if ok and type(value) == "string" and value ~= "" then
                out.addon = value
            end
        end
        if type(api.API_VERSION) == "number" then out.api = api.API_VERSION end
    end

    if type(ns.DB_VERSION) == "number" then out.settings = ns.DB_VERSION end

    local clock = globals.date
    if type(clock) == "function" then
        local ok, value = pcall(clock, WHEN_FORMAT)
        if ok and type(value) == "string" and value ~= "" then
            out.when = value
        end
    end

    return out
end

--- Which build produced the report that lay here before, if not this one.
--
-- The back-check the stamp exists for: the addon is the only thing that knows
-- its own version at the very moment it reads somebody else's record. It
-- stays silent if and only if there is nothing to say: there is no previous
-- report, or it was built by the same build. Two unknowns count as the same
-- thing: unknown against unknown is not a divergence but two silences.
--
-- @param previous table|nil the report that lay in the saved variables
-- @param version string|nil the version that built the current report
-- @return string|nil the previous report's version; nil when there is
--         nothing to compare
function Report.Outdated(previous, version)
    if type(previous) ~= "table" then return nil end

    local stamp = type(previous.stamp) == "table" and previous.stamp or nil
    local was = stamp and stamp.addon or nil
    if type(was) ~= "string" or was == "" then was = Report.UNKNOWN end
    if type(version) ~= "string" or version == "" then
        version = Report.UNKNOWN
    end

    if was == version then return nil end
    return was
end

--============================================================================
-- Lines for chat
--============================================================================

-- How many empty groups to name. Chat is no place for a list: the first
-- lines are read there and the rest scrolls away. Everything else lies in the
-- saved variables, where it is read from disk at leisure.
local NAMED_LIMIT = 3

--- A short digest of the report, as lines.
--
-- A pure function: the caller prints, not this. The lines' contents are
-- tested the same way — outside the client.
--
-- @param report table the report from Report.Build
-- @param limit number|nil how many empty groups to name; three by default
-- @param previous table|nil the report that lay in the saved variables
--        before this one; passed so that a different build can be said out
--        loud
-- @return table array of lines
function Report.Lines(report, limit, previous)
    local out = {}
    if type(report) ~= "table" then return out end

    limit = tonumber(limit) or NAMED_LIMIT
    local counts = type(report.counts) == "table" and report.counts or {}

    local function show(value)
        if value == nil or value == "" then return "?" end
        return tostring(value)
    end

    -- The first line says what answered. Not out of politeness: it was
    -- exactly this line that was missing last time, when the answer on disk
    -- had been built by the previous code and looked fresh. The first lines
    -- are the ones read, and the first must say whether this answer is fresh
    -- at all.
    local stamp = type(report.stamp) == "table" and report.stamp or {}
    out[#out + 1] = string.format(ns.Localize(
        "answered by Darken %s, contract %s, settings %s, at %s by this "
            .. "computer's clock"),
        show(stamp.addon), show(stamp.api), show(stamp.settings),
        show(stamp.when))

    -- And immediately the back-check. It exists only here: the addon knows
    -- its own version while the record on disk names its own, and there is
    -- nobody else to compare them. There is no line when the build is the
    -- same: "everything matched" is not news.
    local was = Report.Outdated(previous, stamp.addon)
    if was then
        out[#out + 1] = string.format(ns.Localize(
            "the report stored here until now was made by Darken %s, not by "
                .. "this one - it was out of date. The game reads addon code "
                .. "at login and on /reload, and at no other time."), was)
    end

    out[#out + 1] = string.format(ns.Localize(
        "client %s, build %s, interface %s, UI scale %s, screen %s"),
        show(report.flavor), show(report.build), show(report.interface),
        show(report.scale), show(report.screen))

    -- All five verdicts on declared groups are named, and only then absent.
    -- The sum of the first five numbers equals the number of groups declared
    -- for this client — and a line whose numbers do not add up to what the
    -- report counted stops being read at all. Four out of six used to be
    -- named here, and six empty hook groups landed nowhere.
    out[#out + 1] = string.format(ns.Localize(
        "frame groups: %d confirmed, %d partial, %d empty, %d unconfirmed, "
            .. "%d degraded, %d absent on this client by design"),
        counts.ok or 0, counts.partial or 0, counts.missing or 0,
        counts.unconfirmed or 0, counts.degraded or 0, counts.absent or 0)

    local worst = type(report.worst) == "table" and report.worst or {}
    for i = 1, math.min(#worst, limit) do
        out[#out + 1] = string.format(ns.Localize(
            "%s did nothing: group \"%s\" resolved to nothing (%d names tried)"),
            ns.Localize(worst[i].label), worst[i].group, worst[i].declared)
    end
    if #worst > limit then
        out[#out + 1] = string.format(ns.Localize(
            "and %d more groups resolved to nothing"), #worst - limit)
    end
    if (counts.partial or 0) > 0 then
        out[#out + 1] = string.format(ns.Localize(
            "%d groups found only part of what they name - see the saved "
                .. "variables"), counts.partial)
    end

    if (counts.unconfirmed or 0) > 0 then
        out[#out + 1] = string.format(ns.Localize(
            "%d groups could not be judged: the game makes those frames only "
                .. "after you open the window or take a target. Open them and "
                .. "run the report again."), counts.unconfirmed)
    end

    if (counts.degraded or 0) > 0 then
        out[#out + 1] = string.format(ns.Localize(
            "%d hook groups are empty here: those subsystems fall back to a "
                .. "delayed pass, which is slower but not broken"),
            counts.degraded)
    end

    -- THIS LINE'S RULE. It is printed if and only if no group declared for
    -- this client was left without an answer: none empty, none partial, none
    -- unconfirmed, none degraded. Any other threshold would mean "all is
    -- well" standing above the line "nine groups cannot be checked" —
    -- precisely the reassuring lie the whole file is written against. For the
    -- same reason its place is after the caveats rather than above them: the
    -- first lines are the ones read, and the first must be the one that
    -- troubles.
    if #worst == 0 and (counts.partial or 0) == 0
        and (counts.unconfirmed or 0) == 0 and (counts.degraded or 0) == 0 then
        out[#out + 1] = ns.Localize(
            "every frame group declared for this client resolved to something")
    end

    out[#out + 1] = string.format(ns.Localize(
        "guessed names needing live confirmation: %d of %d exist here"),
        report.watchFound or 0, report.watchTotal or 0)

    -- A path that got halfway is named, and the first one at that: it is the
    -- only line of the report that says not "we did not find it" but "look
    -- here". There is no line at all when there are no such paths: "zero
    -- nearly found" is not news but a line in chat instead of the answer.
    local near = type(report.near) == "table" and report.near or {}
    if #near > 0 then
        out[#out + 1] = string.format(ns.Localize(
            "%d paths got part way: \"%s\" exists here and \"%s\" does not - "
                .. "the object is right, the last step is not"),
            #near, near[1].prefix, near[1].path)
    end

    -- The tally of work done comes last, before the "send the file" line,
    -- and inside it what did not work comes first: the first lines of each
    -- section are the ones read, and the rest scrolls away.
    if type(report.tally) == "table" and type(ns.Tally) == "table"
        and type(ns.Tally.Lines) == "function" then
        local tallyLines = ns.Tally.Lines(report.tally)
        for i = 1, #tallyLines do out[#out + 1] = tallyLines[i] end
    end

    out[#out + 1] = ns.Localize(
        "log out and send Darken.lua (SavedVariables) - the full report "
            .. "is in DarkenDB.global.report")

    return out
end
