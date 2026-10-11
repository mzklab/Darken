local ADDON, ns = ...

-- The tally of work done: what the subsystems managed to do this session.
--
-- WHY IT EXISTS. The client report (Core/Report.lua) answers "what exists in
-- this client". That is half of it. The other half is "what we managed to do
-- with it", and usually that is the half that is needed: "the nameplate group
-- found twelve names" and "the nameplate engine attached to none of them in
-- twenty minutes of combat" are both true, and only the second explains
-- anything.
--
-- The mover was never exercised in a client. Whether it placed a single
-- position is, today, impossible to find out. The dimming pass walks the whole
-- interface; how many objects it dimmed and how many it skipped as content is
-- the difference between "it works" and "it found nothing".
--
-- THE RULE FOR ADDING A COUNTER. A counter is added if and only if there is an
-- answer to "which number, were it zero, would prove this subsystem did
-- nothing?". Twenty numbers nobody reads are worse than five that answer the
-- question.
--
-- THE RULE OF COST. Counting must be free. These counters sit on paths
-- measured in microseconds: an aura repaint is 0.03 ms, a nameplate pass
-- 0.05 ms. So incrementing a counter is exactly one integer addition through
-- an already-taken local reference: no function call, no table, no string. Any
-- wrapper around that ("Tally.Add(key)") would show up in the whole-cost
-- measurement, which has ceilings of its own (tests/test_wholecost.lua).
--
-- THREE DIFFERENT ZEROES. The same distinction Core/Report.lua lives by, and
-- for the same reason: a counter nobody increments is precisely the
-- reassuring lie the report was written against.
--
--   nil — the counter is unclaimed. The subsystem that keeps it is not in
--         this build at all (the module is not installed). Never a problem.
--   0   — the counter is claimed and never touched: the subsystem is there
--         and did nothing. This is the answer the file was written for.
--   >0  — it did that much.
--
-- A counter is claimed by the subsystem that keeps it, while its file is
-- read, with one line: "counters.key = counters.key or 0". So "unclaimed"
-- means precisely the absence of the subsystem rather than forgetfulness.
--
-- Everything in this file is pure functions over a table of numbers: the game
-- is not called from here, and every verdict is tested outside the client
-- (tests/test_tally.lua).

-- The table of numbers itself. Everyone increments it, and everything else
-- here describes it. Created "if not already there" for the same reason the
-- subsystems create it that way: a test file loads a subsystem without the
-- core, and the table then appears from the first subsystem loaded.
local Counters = ns.Counters or {}
ns.Counters = Counters

local Tally = {}
ns.Tally = Tally

-- Version of the record's format in the saved variables: the author reads it
-- from disk, possibly with a different addon from the one that wrote it.
Tally.VERSION = 1

--============================================================================
-- A counter's kind, and its verdict
--============================================================================

-- A counter's kind: what its zero means.
Tally.NEEDED  = "needed"  -- zero means "nothing was done" - a failure
Tally.NORMAL  = "normal"  -- zero means nothing: there may have been no work
Tally.FAILURE = "failure" -- counts refusals: the news is non-zero, not zero

-- A counter's verdict. Strings rather than numbers: the report is read by
-- eye from disk.
Tally.UNCLAIMED = "unclaimed" -- unclaimed: this subsystem is not in the build
Tally.DONE      = "done"      -- this much was done
Tally.IDLE      = "idle"      -- claimed and never touched - this is the failure
Tally.EMPTY     = "empty"     -- zero, but zero was to be expected
Tally.QUIET     = "quiet"     -- there were no refusals
Tally.FAILING   = "failing"   -- there were refusals, and this many

--- The verdict on one counter.
--
-- The order of the checks is the rule "never towards the reassuring answer":
-- a claimed zero counter of the required kind is called a failure rather than
-- quiet, and a "done / of what was deferred" pair is judged by its partner
-- before it is judged by its own kind.
--
-- @param kind string the counter's kind (Tally.NEEDED and its neighbours)
-- @param value number|nil the counter's value; nil means unclaimed
-- @param pair number|nil the partner's value; nil means there is no partner
-- @return string the verdict
function Tally.Verdict(kind, value, pair)
    if value == nil then return Tally.UNCLAIMED end
    value = tonumber(value) or 0

    if kind == Tally.FAILURE then
        if value > 0 then return Tally.FAILING end
        return Tally.QUIET
    end

    if value > 0 then return Tally.DONE end

    -- Zero while the partner is working is a failure, whatever the kind.
    -- This is the very case partners exist for: the hook was installed and
    -- never ran; the work was deferred and never carried out.
    pair = tonumber(pair)
    if pair ~= nil and pair > 0 then return Tally.IDLE end

    if kind == Tally.NEEDED then return Tally.IDLE end
    return Tally.EMPTY
end

--- Whether a verdict counts as a failure.
-- One answer to one question, asked by two parties: the chat line and the
-- analysis.
-- @param verdict string
-- @return boolean
function Tally.IsTrouble(verdict)
    return verdict == Tally.IDLE or verdict == Tally.FAILING
end

--============================================================================
-- The counter dictionary
--============================================================================

-- What exactly is counted, and what a zero means for each.
--
-- The order here is reading order rather than alphabetical: first what the
-- subsystems did, then deferred work, then silent refusals. The order must be
-- fixed: two runs of the report are compared by eye.
--
-- The label is translated — it is read in chat. The meaning (means) is not:
-- one sentence in English, read by the author from disk next to the number.
-- The `later` field in Core/Report.lua is arranged the same way.
local COUNTERS = {
    {
        key = "dimmed", label = "Objects Dimmed", kind = Tally.NEEDED,
        means = "textures the dimming pass wrote a colour into",
    },
    {
        key = "content", label = "Objects Left As Content", kind = Tally.NORMAL,
        means = "regions the dimming pass looked at and left alone because "
            .. "they are content, not chrome",
    },
    -- Raising dark text out of a darkened page had no count, and the
    -- question it answers cannot be answered any other way: "the raising
    -- never ran" and "it ran and judged the text light enough to leave" look
    -- identical on screen and are fixed in different places.
    -- Required rather than ordinary, and that is the point of it.
    --
    -- An ordinary counter at zero is not printed: there may simply have been
    -- no work, and twenty zeroes would bury the line. Here zero IS the
    -- finding - a darkened page whose text was never raised is unreadable -
    -- and the first time it was needed it could not be read, because nothing
    -- is what the line shows for it. A measurement whose answer is invisible
    -- in its most interesting case is not a measurement.
    {
        key = "lifted", label = "Labels Raised", kind = Tally.NEEDED,
        pair = "lightText",
        means = "dark labels raised out of a darkened page - zero beside a "
            .. "non-zero count of labels left alone means the rule judged "
            .. "them all light enough, and the threshold is the thing to look "
            .. "at rather than the walk; zero beside zero means the raising "
            .. "never reached the page at all",
    },
    {
        key = "lightText", label = "Labels Left Light", kind = Tally.NORMAL,
        means = "labels the raising looked at and left, because their own "
            .. "colour is bright enough to read on a dark page - a yellow "
            .. "name, a green quest title, a white reward line",
    },
    -- Three operations shared one count, and the sharing cost three wrong
    -- diagnoses in a row: a number made of minimap buttons was read as proof
    -- that action buttons had been outlined. A count answers a question only
    -- if one thing increments it.
    {
        key = "cropped", label = "Icon Edges Trimmed", kind = Tally.NORMAL,
        subsystem = "Icon Borders",
        means = "icons whose own dull edge was trimmed away - zero with the "
            .. "setting on means the icon of a button was not found on this "
            .. "client, and then the outline is missing for the same reason",
    },
    {
        key = "tinted", label = "Icons Dimmed", kind = Tally.NORMAL,
        subsystem = "Icon Borders",
        means = "spell icons given the dimming's own shade - zero while the "
            .. "setting is on means the pass never reached them, and zero "
            .. "while it is off means nothing at all, which is why the "
            .. "setting is worth checking before the code is",
    },
    {
        key = "hooked_icons", label = "Game Functions Hooked",
        kind = Tally.NORMAL, subsystem = "Icon Borders",
        means = "the game's own repaint of a button, hooked so our shade "
            .. "goes back in the same call - a zero beside dimmed icons "
            .. "means the shade is written and then lost, which is exactly "
            .. "what the probe showed before this hook existed",
    },
    {
        key = "rounded", label = "Minimap Buttons Rounded", kind = Tally.NORMAL,
        subsystem = "Icon Borders",
        means = "buttons other addons put around the minimap that were cut "
            .. "into circles",
    },
    {
        key = "framed", label = "Icons Framed", kind = Tally.NORMAL,
        subsystem = "Icon Borders",
        means = "action buttons this addon drew its own line around - zero "
            .. "with the setting on means not one button name of this "
            .. "client was found, which is a broken guess and not a choice",
    },
    -- The watcher of other people's repaintings had no count at all, and its
    -- absence cost an evening: "Hooks That Ran (Dimming)" was read as its
    -- firings when it counts openings of windows, and on that reading the
    -- watcher was declared innocent. A subsystem nobody counts cannot be
    -- cleared or convicted.
    {
        key = "repainted", label = "Repaints Heard", kind = Tally.NORMAL,
        subsystem = "Interface Darkness",
        means = "times the game repainted a picture after us and the watcher "
            .. "heard it - a zero while the screen is plainly being redrawn "
            .. "means the watcher is deaf on this client, and everything the "
            .. "game repaints keeps its own colours no matter what we wrote",
    },
    {
        key = "retextured", label = "Bars Retextured", kind = Tally.NORMAL,
        means = "status bars given one of the addon's own textures",
    },
    -- Two counts rather than one, and that is not duplication. Nameplates
    -- are styled by a core subsystem (Modules/NamePlates.lua) and redrawn by
    -- the part's engine (Features/NamePlates); they take turns, but not
    -- always: the engine is off in a fresh installation, and the core works
    -- then. One number for both would mean one's zero hides behind the
    -- other's work — exactly what the whole tally exists to prevent.
    {
        key = "plates_seen", label = "Nameplates The Game Showed",
        subsystem = "Nameplates", kind = Tally.NORMAL,
        means = "nameplates the game put on screen while this session ran - "
            .. "zero here with zero attached means there was nothing to "
            .. "attach to, which is a different matter from attaching and "
            .. "failing",
    },
    {
        key = "plates", label = "Nameplates Attached", kind = Tally.NEEDED,
        means = "nameplates the core's own nameplate subsystem styled - "
            .. "the module engine has its own key",
    },
    {
        key = "plates_engine", label = "Nameplates Taken By The Engine",
        kind = Tally.NEEDED,
        means = "nameplates the addon's own nameplate engine attached its "
            .. "own frames to - unclaimed means the engine did not run this "
            .. "session, which is the player's choice and not a failure",
    },
    {
        key = "auras", label = "Auras Ruled On", kind = Tally.NORMAL,
        means = "auras the spell list decided about by name",
    },
    -- Hooks: a pair of numbers per subsystem that has any.
    --
    -- The pair used to be shared by all, and that is exactly why it answered
    -- nobody's question. The dimming hooks fire continuously, so the shared
    -- "fired" is always above zero; a subsystem whose hook was installed and
    -- never fired — the one case the pair exists for — was hidden behind that
    -- number entirely. The rule for adding a counter, written at the top of
    -- this file, asks "what would prove THIS subsystem did nothing"; a shared
    -- pair had no such answer.
    --
    -- The label is the same for every pair, and the subsystem is named by the
    -- `subsystem` field: both words are already translated (settings labels),
    -- and a second name for the same thing would leave the author guessing
    -- what is meant.
    {
        key = "hooked_bags", label = "Game Functions Hooked",
        subsystem = "Game Bags", kind = Tally.NEEDED,
        means = "game functions this subsystem hooked by a guessed name",
    },
    {
        key = "fired_bags", label = "Hooks That Ran",
        subsystem = "Game Bags", kind = Tally.NORMAL, pair = "hooked_bags",
        means = "times one of this subsystem's hooks actually ran - zero "
            .. "against a non-zero hook count is a name that resolved and "
            .. "then did nothing",
    },
    {
        key = "hooked_darkness", label = "Game Functions Hooked",
        subsystem = "Dimming", kind = Tally.NEEDED,
        means = "game functions this subsystem hooked by a guessed name",
    },
    {
        key = "fired_darkness", label = "Hooks That Ran",
        subsystem = "Dimming", kind = Tally.NORMAL, pair = "hooked_darkness",
        means = "times one of this subsystem's hooks actually ran - zero "
            .. "against a non-zero hook count is a name that resolved and "
            .. "then did nothing",
    },
    {
        key = "hooked_nameplates", label = "Game Functions Hooked",
        subsystem = "Nameplates", kind = Tally.NEEDED,
        means = "game functions this subsystem hooked by a guessed name",
    },
    {
        key = "fired_nameplates", label = "Hooks That Ran",
        subsystem = "Nameplates", kind = Tally.NORMAL, pair = "hooked_nameplates",
        means = "times one of this subsystem's hooks actually ran - zero "
            .. "against a non-zero hook count is a name that resolved and "
            .. "then did nothing",
    },
    {
        key = "hooked_texts", label = "Game Functions Hooked",
        subsystem = "Bar Text", kind = Tally.NEEDED,
        means = "game functions this subsystem hooked by a guessed name",
    },
    {
        key = "absent_texts", label = "Names This Client Does Not Have",
        subsystem = "Bar Text", kind = Tally.NORMAL,
        means = "names of game functions this subsystem looked for and did "
            .. "not find - zero hooks WITH names missing means the client "
            .. "renamed them, which is a different problem from zero hooks "
            .. "with every name present",
    },
    {
        key = "fired_texts", label = "Hooks That Ran",
        subsystem = "Bar Text", kind = Tally.NORMAL, pair = "hooked_texts",
        means = "times one of this subsystem's hooks actually ran - zero "
            .. "against a non-zero hook count is a name that resolved and "
            .. "then did nothing",
    },
    {
        key = "hooked_unitframes", label = "Game Functions Hooked",
        subsystem = "Unit Frames", kind = Tally.NEEDED,
        means = "game functions this subsystem hooked by a guessed name",
    },
    {
        key = "fired_unitframes", label = "Hooks That Ran",
        subsystem = "Unit Frames", kind = Tally.NORMAL, pair = "hooked_unitframes",
        means = "times one of this subsystem's hooks actually ran - zero "
            .. "against a non-zero hook count is a name that resolved and "
            .. "then did nothing",
    },
    {
        key = "deferred", label = "Work Deferred In Combat",
        kind = Tally.NORMAL,
        means = "operations put aside because the game was in combat",
    },
    {
        key = "drained", label = "Deferred Work Carried Out",
        kind = Tally.NORMAL, pair = "deferred",
        means = "deferred operations carried out after the fight ended - "
            .. "zero against deferred work is work that was put aside and "
            .. "never done",
    },
    {
        key = "forbidden", label = "Objects The Game Keeps To Itself",
        subsystem = "Interface Darkness", kind = Tally.NORMAL,
        means = "objects the game marks as not the addon's to touch - "
            .. "reaching one at all would mark this addon's code and cost "
            .. "the game its own cooldowns and cast times, so the sweep "
            .. "walks past them; a number here is the guard working, not a "
            .. "failure",
    },
    {
        key = "protected_darkness",
        label = "Protected Frames The Sweep Left Alone",
        subsystem = "Interface Darkness", kind = Tally.NORMAL,
        means = "frames the engine watches over - action bars and their "
            .. "buttons, the raid frame holder, the bar a vehicle puts on "
            .. "screen. Touching one makes the engine count the frame as "
            .. "changed by an addon, and the frame's own code then runs "
            .. "marked: the player sees it as a broken cooldown in a game "
            .. "file. Their look belongs to the subsystem that owns them, "
            .. "which paints them itself; a number here is the guard "
            .. "working, not a failure",
    },
    -- Secret values reach more than one subsystem, so there is more than one
    -- counter for them. A shared key would mean a refusal on the cast bar and
    -- a refusal in the dimming pass add up into one number, and that number
    -- could not say what failed to draw. The label is the same for both and
    -- the subsystem is named by the `subsystem` field — the same scheme as
    -- the hooked_/fired_ pairs above.
    {
        key = "blocked_darkness", label = "Secret Values The Engine Refused",
        subsystem = "Interface Darkness", kind = Tally.FAILURE,
        means = "colours the game handed over as secret - the addon may "
            .. "hold such a value but not work with it while its own code "
            .. "is running, so the object keeps its native look",
    },
}
Tally.COUNTERS = COUNTERS

-- Key -> dictionary entry. Built once while the file is read.
local BY_KEY = {}
for i = 1, #COUNTERS do BY_KEY[COUNTERS[i].key] = COUNTERS[i] end

--- A counter's description.
-- @param key string
-- @return table|nil {key, label, subsystem, kind, means, pair}
function Tally.Describe(key)
    return BY_KEY[key]
end

--- What a counter is called in chat.
--
-- The label is translated and so is the subsystem's name, while the brackets
-- are not: they contain no word at all, and adding a translation entry for
-- brackets would add an entry indistinguishable from a typo. Both translated
-- pieces come from existing settings labels — the same thing must be called
-- the same way.
--
-- @param entry table an entry from Tally.Build or from the dictionary
-- @return string
function Tally.Title(entry)
    if type(entry) ~= "table" then return "" end

    local label = ns.Localize(entry.label)
    if entry.subsystem == nil then return label end
    return string.format("%s (%s)", label, ns.Localize(entry.subsystem))
end

--- The counter keys, in reading order.
-- A new array is returned: the dictionary is ours, and there is nothing to
-- rewrite it from outside with.
-- @return table array of keys
function Tally.Order()
    local out = {}
    for i = 1, #COUNTERS do out[i] = COUNTERS[i].key end
    return out
end

--============================================================================
-- Modules: how many are in service and how many stepped out
--============================================================================

--- How many modules are working and how many are switched off.
--
-- Not a counter: the registry knows this without us, and a second count
-- beside it would diverge silently. Asked at report time.
--
-- @param registry table|nil the registry; ns.Registry by default
-- @return table {live, down, downNames}
function Tally.Modules(registry)
    registry = registry or ns.Registry

    local out = { live = 0, down = 0, downNames = {} }
    if type(registry) ~= "table" or type(registry.Each) ~= "function" then
        return out
    end

    for _, name in registry:Each() do
        if registry:IsFailed(name) then
            out.down = out.down + 1
            out.downNames[#out.downNames + 1] = name
        else
            out.live = out.live + 1
        end
    end
    table.sort(out.downNames)

    return out
end

--============================================================================
-- Hooks: what the engine refused
--============================================================================

--- Which event registrations the engine refused to accept.
--
-- Not a counter, and for the same reason Tally.Modules is not one: this is a
-- list of names rather than a number, and a number instead of the list would
-- answer nobody's question. "One subscription was refused" says nothing;
-- "NAME_PLATE_UNIT_ADDED was refused" says everything.
--
-- Why it is here at all. Registering an event goes through pcall (the engine
-- raises on an unknown name), and until now a refusal was recorded nowhere. A
-- subsystem whose event the engine did not accept does nothing and looks
-- exactly like a subsystem whose event was accepted and never delivered. That
-- is precisely the silent failure both Core/Report.lua and this file were
-- written against.
--
-- Asked at report time, like the registry's contents.
--
-- @param events table|nil the events subsystem; ns.Events by default
-- @return table {accepted, refusedCount, refused = {{event, tries}}}
function Tally.Events(events)
    if events == nil then events = ns.Events end

    local out = { accepted = 0, refusedCount = 0, refused = {} }
    if type(events) ~= "table" then return out end

    if type(events.Accepted) == "function" then
        out.accepted = tonumber(events.Accepted()) or 0
    end

    if type(events.Refused) == "function" then
        local refused = events.Refused()
        if type(refused) == "table" then
            out.refused = refused
            out.refusedCount = #refused
        end
    end

    return out
end

--============================================================================
-- Assembly
--============================================================================

--- Assemble the analysis of the tally.
--
-- @param counters table|nil the table of numbers; ns.Counters by default
-- @param registry table|nil the module registry; ns.Registry by default
-- @param events table|nil the events subsystem; ns.Events by default
-- @return table the analysis
function Tally.Build(counters, registry, events)
    counters = type(counters) == "table" and counters or Counters

    local out = {
        version   = Tally.VERSION,
        counters  = {},  -- key -> entry
        order     = {},  -- keys in reading order
        idle      = {},  -- claimed and never touched: this is the answer
        failing   = {},  -- silent refusals that were not zero
        unclaimed = {},  -- unclaimed: these subsystems are not in the build
        extra     = {},  -- numbers that are not in the dictionary
        modules   = Tally.Modules(registry),
        events    = Tally.Events(events),
    }

    for i = 1, #COUNTERS do
        local rule = COUNTERS[i]

        -- The value goes through tonumber: the table is shared, and a
        -- module may put anything into it through the contract. A report that
        -- raised on somebody else's row would say nothing at all.
        local raw = counters[rule.key]
        local value = raw ~= nil and tonumber(raw) or nil
        local pair = rule.pair and tonumber(counters[rule.pair]) or nil

        local verdict = Tally.Verdict(rule.kind, value, pair)
        local entry = {
            key       = rule.key,
            label     = rule.label,
            subsystem = rule.subsystem,
            kind      = rule.kind,
            means     = rule.means,
            pair      = rule.pair,
            value     = value,
            verdict   = verdict,
        }

        out.counters[rule.key] = entry
        out.order[#out.order + 1] = rule.key

        if verdict == Tally.IDLE then
            out.idle[#out.idle + 1] = entry
        elseif verdict == Tally.FAILING then
            out.failing[#out.failing + 1] = entry
        elseif verdict == Tally.UNCLAIMED then
            out.unclaimed[#out.unclaimed + 1] = rule.key
        end
    end

    -- A number absent from the dictionary is not silently lost. Only a
    -- module could have put it there through the contract, and "a key the
    -- report knows nothing about" has to reach the saved file rather than
    -- vanish: what vanished can be neither read nor fixed.
    for key, value in pairs(counters) do
        if BY_KEY[key] == nil then
            local number = tonumber(value)
            if number ~= nil then out.extra[key] = number end
        end
    end

    return out
end

--============================================================================
-- Lines for chat
--============================================================================

--- A short digest of the tally, as lines.
--
-- A pure function: the caller prints, not this.
--
-- There are few lines and their order is the reverse of the expected one:
-- what failed comes first. The first lines are the ones read while the rest
-- scrolls away, and "the nameplate subsystem did nothing" has to stand before
-- "eight hundred objects dimmed".
--
-- @param tally table the analysis from Tally.Build
-- @return table array of lines
function Tally.Lines(tally)
    local out = {}
    if type(tally) ~= "table" then return out end

    -- A subscription the engine refused comes before everything else, and
    -- that is not an order of importance but an order of explanation: it
    -- names the cause of somebody else's zero. The subsystem whose event was
    -- not accepted appears a line below among "did nothing", and without this
    -- line its zero would read as "the game sent nothing" — that is, as the
    -- game's fault rather than as a refused registration.
    --
    -- Printed only when there were refusals: "zero refusals" is not news but
    -- a line in chat read instead of the answer.
    local events = type(tally.events) == "table" and tally.events or {}
    local refused = type(events.refused) == "table" and events.refused or {}
    if #refused > 0 then
        local names = {}
        for i = 1, #refused do names[i] = refused[i].event end
        out[#out + 1] = string.format(ns.Localize(
            "the game refused to register these events: %s - whatever waits "
                .. "on them did nothing and could not say why"),
            table.concat(names, ", "))
    end

    -- The file's main line. By name and in full: the list is short by
    -- construction, and shortening it to a number would hide the answer.
    local idle = type(tally.idle) == "table" and tally.idle or {}
    if #idle > 0 then
        local names = {}
        for i = 1, #idle do names[i] = Tally.Title(idle[i]) end
        out[#out + 1] = string.format(ns.Localize(
            "did nothing this session: %s"), table.concat(names, ", "))
    end

    -- Silent refusals. One line, and only when there were any: "zero
    -- refusals" is not news but a line in chat read instead of the answer.
    local failing = type(tally.failing) == "table" and tally.failing or {}
    if #failing > 0 then
        local pieces = {}
        for i = 1, #failing do
            pieces[i] = string.format("%s %d",
                Tally.Title(failing[i]), failing[i].value)
        end
        out[#out + 1] = string.format(ns.Localize(
            "the game quietly refused: %s"), table.concat(pieces, ", "))
    end

    -- What was done, on one line: label-and-number pairs separated by
    -- commas. Zero and unclaimed do not go here: zero was covered above, and
    -- about unclaimed there is nothing to say.
    local done = {}
    local order = type(tally.order) == "table" and tally.order or {}
    for i = 1, #order do
        local entry = tally.counters and tally.counters[order[i]]
        if entry and entry.verdict == Tally.DONE then
            done[#done + 1] = string.format("%s %d",
                Tally.Title(entry), entry.value)
        end
    end
    if #done > 0 then
        out[#out + 1] = string.format(ns.Localize("this session: %s"),
            table.concat(done, ", "))
    else
        out[#out + 1] = ns.Localize(
            "this session the addon did not do a single counted thing")
    end

    local modules = type(tally.modules) == "table" and tally.modules or {}
    out[#out + 1] = string.format(ns.Localize(
        "modules: %d in service, %d switched off"),
        modules.live or 0, modules.down or 0)

    return out
end
