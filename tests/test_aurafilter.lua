local helpers = require("helpers")

-- The core's shared aura filter: Darken:GetAuraFilter() (contract version 7).
--
-- What is checked is not "how our two modules use it" — their own sets do that
-- (tests/test_nameplates2.lua, tests/test_aurasfilter.lua) — but the surface
-- itself, because it is a contractual one: the author of a module we will
-- never reach with an edit of our own code is entitled to lean on it.
--
-- Four cases are named outright, because each of them is somebody else's
-- module on its first day: it declared a version older than the current one,
-- it compiled a plan out of an empty list, it asked for a decision without
-- compiling a plan at all, and it typed a list in which numbers stand beside names.

helpers.installValidator()

--- The core as the public layer sees it.
-- @return table
local function core()
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Frames.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Combat.lua", ns)
    helpers.loadAddonFile("Core/Api.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/AuraFilter.lua", ns)

    local said = {}
    ns.Registry.report = function(text) said[#said + 1] = text end
    ns.Addon = {
        db = { profile = {}, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }

    return ns, said
end

T.suite("the aura filter: the contract's door")

do
    local ns = core()

    T.eq(type(ns.Api.GetAuraFilter), "function",
        "the core returns the aura filter through a function rather than a field")

    local filter = ns.Api:GetAuraFilter()
    T.eq(type(filter), "table", "the filter is returned as a table")
    T.eq(filter, ns.AuraFilter,
        "the filter returned is the one the core itself uses rather than a similar one beside it")
    T.eq(ns.Api:GetAuraFilter(), filter, "and the very same one on a second question")

    -- The filter's own surface: a snapshot rather than a list of functions. A
    -- name added here by accident is a promise forever, and it is obliged to
    -- require a deliberate decision.
    local surface = {}
    for key, value in pairs(filter) do
        surface[#surface + 1] = key .. ":" .. type(value)
    end
    table.sort(surface)
    T.eq(table.concat(surface, ","),
        "Compile:function,DEFAULT_MODE:string,Decide:function,Entry:function,"
        .. "HIDE:string,IsMode:function,Key:function,Modes:function,"
        .. "NeedsKey:function,PASS:string,SHOW:string,Split:function",
        "the filter's surface: " .. table.concat(surface, ","))

    -- The modes' words are returned as a new array: a shared one would let a
    -- module rewrite the modes for the whole addon, and they go into other people's SavedVariables.
    local modes = filter.Modes()
    T.eq(#modes, 3, "there are three modes")
    T.eq(modes[1], "off", "first stands \"do nothing\"")
    T.eq(filter.DEFAULT_MODE, "off", "and it is the default too")
    modes[1] = "spoiled"
    T.eq(filter.Modes()[1], "off", "spoiling the list did not reach the core")

    for _, word in ipairs(filter.Modes()) do
        T.eq(filter.IsMode(word), true, "the mode is known to the core: " .. word)
    end
    T.eq(filter.IsMode("an invention"), false, "an invented mode is unknown to the core")
    T.eq(filter.IsMode(nil), false, "and so is the absence of a mode")
end

T.suite("the aura filter: a module of an old version asks for the filter")

do
    local ns, said = core()

    -- The surface is one for everybody: a version limits not access but the
    -- ownership of the descriptor's names (Core/Api.lua). A module of the
    -- first version is entitled to ask for the filter and to get it —
    -- otherwise "a module written for version 1 works as it worked" would mean "works until it asks".
    local old = ns.Api:RegisterModule({ name = "oldtimer", api = 1 })
    T.ok(old ~= nil, "a module of version 1 was registered")
    T.eq(ns.Api:GetAuraFilter(), ns.AuraFilter,
        "and the filter returned to it is the very same one")

    -- Asking in advance is possible too, and the answer is now "yes": a module
    -- that needs the filter optionally declares its version and asks.
    T.eq(ns.Api:Supports(7), true, "the seventh version is supported")
    T.eq(ns.Api:Supports(ns.Api.API_VERSION + 1), false,
        "the core does not promise a version beyond the contract's end")

    local seven = ns.Api:RegisterModule({ name = "newcomer", api = 7 })
    T.ok(seven ~= nil, "a module of the seventh version was registered")

    local tooNew, reason = ns.Api:RegisterModule({
        name = "tooNew", api = ns.Api.API_VERSION + 1 })
    T.eq(tooNew, nil, "a module of a version beyond the contract's end was not registered")
    T.ok(type(reason) == "string" and reason:find("update Darken", 1, true),
        "and the refusal says it is the core that has to be updated")

    T.eq(#said, 1, "the core complained exactly once: " .. table.concat(said, " | "))
end

T.suite("the aura filter: the parse of a typed list")

do
    local api = core().Api
    local filter = api:GetAuraFilter()

    -- A number and a name in one field, and they are told apart by their shape.
    local ids, names, count, numbered = filter.Split("12345, Rend\n Кровопускание ")
    T.eq(count, 3, "three records were parsed")
    T.eq(numbered, 1, "one of them a number")
    T.eq(ids[12345], true, "the number became a number")
    T.eq(names["rend"], true, "the Latin was brought to lower case")

    -- string.lower's bounds are no longer here: a name's key is the core's
    -- folding (Darken:GetCasefold, Core/Casefold.lua), and Cyrillic folds on a
    -- par with Latin. This check used to demand the opposite, and demanded it
    -- honestly — the truth changed rather than the check growing weaker.
    --
    T.eq(names["кровопускание"], true, "the Cyrillic was folded into lower case")
    T.eq(names["Кровопускание"], nil, "while as typed it is not in the dictionary")

    -- A name's key is that very function of the core's rather than a copy
    -- beside it: the name is one, and there is not a line of a second folding in the aura filter.
    T.eq(filter.Key, api:GetCasefold().Key,
        "a name's key is the core's folding rather than one of its own")

    -- A repeat creates no second record, rubbish creates no first one.
    local _, _, twice = filter.Split("Rend,,rend,  ,REND,\n 77 ,77")
    T.eq(twice, 2, "repeats and empty pieces do not count: " .. twice)

    local badIds, badNames = filter.Split("3.5, 0, -7")
    T.eq(next(badIds), nil, "a fraction, a zero and a minus did not become numbers")
    T.eq(badNames["3.5"], true, "the typo went into the names, where it will find nothing")

    T.eq((select(3, filter.Split(nil))), 0, "a non-string gives an empty list")
    T.eq((select(3, filter.Split("  , \n "))), 0, "and so do separators alone")

    T.eq(filter.Key("  Rend  "), "rend", "the key was trimmed and folded")
    T.eq(filter.Key("   "), nil, "an empty name gives no key")
    T.eq(filter.Key(42), nil, "nor does a non-string")

    T.eq((filter.Entry(" 77 ")), 77, "a record of digits is a number")
    T.eq((select(2, filter.Entry("Rend"))), "rend", "while the rest is a name")
end

T.suite("the aura filter: a plan out of an empty list and a decision with no plan")

do
    local filter = core().Api:GetAuraFilter()

    -- An empty list. A literal reading of the "only these" mode would give an
    -- empty screen of auras, and a player who erased the line would get not
    -- "as it was" but "nothing". So an empty list switches the mode off entirely.
    local emptyAllow = filter.Compile("", "allow")
    T.eq(emptyAllow.mode, "off", "an empty list switches \"only these\" off")
    T.eq(emptyAllow.count, 0, "not one record was parsed")
    T.eq(filter.Decide(emptyAllow, "rend", 1), filter.PASS,
        "and the list has nothing to say about anything")
    T.eq(filter.NeedsKey(emptyAllow), false, "a name's key is not needed")

    T.eq(filter.Compile("  ,  ", "deny").mode, "off",
        "separators alone give the same empty list")
    T.eq(filter.Compile(nil, nil).mode, "off", "and so does the absence of settings")
    T.eq(filter.Compile("Rend", "an invention").mode, "off",
        "an unfamiliar mode out of SavedVariables means \"do not touch\"")

    -- A plan is returned anew on every call: the display keeps the plan with
    -- itself, and an edit underneath it would mean some auras were selected by the old rule.
    local first = filter.Compile("Rend", "deny")
    local second = filter.Compile("Rend", "deny")
    T.ok(first ~= second, "every plan is a table of its own")
    first.mode = "spoiled"
    T.eq(second.mode, "deny", "spoiling one plan did not reach the other")

    -- Decisions with no plan at all. A filter that did not compile for
    -- whatever reason is obliged to hide nothing of its own accord: the answer is "the list has nothing to say".
    T.eq(filter.Decide(nil, "rend", 1), filter.PASS, "with no plan it is PASS")
    T.eq(filter.Decide("not a table", nil, nil), filter.PASS,
        "and rubbish instead of a plan is PASS too")
    T.eq(filter.NeedsKey(nil), false, "and with no plan no key is needed")
    T.eq(filter.NeedsKey("not a table"), false, "nor by rubbish")
end

T.suite("the aura filter: a list of numbers and names at once")

do
    local filter = core().Api:GetAuraFilter()

    local LIST = "12345, Rend\n777"

    -- The ban: what is named by either of the two forms is obliged to vanish.
    local deny = filter.Compile(LIST, "deny")
    T.eq(deny.count, 3, "three records in the plan")
    T.eq(deny.numbered, 2, "two of them numbers")
    T.eq(filter.NeedsKey(deny), true, "there is a name in the list, so a key is needed")

    T.eq(filter.Decide(deny, nil, 12345), filter.HIDE, "the number is named")
    T.eq(filter.Decide(deny, "rend", nil), filter.HIDE, "the name is named")
    T.eq(filter.Decide(deny, "rend", 999), filter.HIDE,
        "a match of the name is enough")
    T.eq(filter.Decide(deny, "somebody else's", 999), filter.PASS, "what is not named passes")
    T.eq(filter.Decide(deny, nil, nil), filter.PASS,
        "an aura with no name and no number is named by nothing")

    -- "Only these": what is named is shown, the rest is hidden.
    local allow = filter.Compile(LIST, "allow")
    T.eq(filter.Decide(allow, nil, 777), filter.SHOW, "the number is named")
    T.eq(filter.Decide(allow, "rend", nil), filter.SHOW, "and so is the name")
    T.eq(filter.Decide(allow, "somebody else's", 999), filter.HIDE, "the rest is hidden")

    -- A module that does not read numbers asks without a number — and the list
    -- answers it by name alone. That is exactly what the nameplates' engine
    -- had before the shared filter.
    T.eq(filter.Decide(deny, "rend", nil), filter.HIDE, "the name is named without a number too")
    T.eq(filter.Decide(deny, filter.Key("12345"), nil), filter.PASS,
        "a typed number does not pretend to be a name")

    -- A name's key where there are no names in the list at all: a list of
    -- numbers alone does not create a string per aura.
    local idsOnly = filter.Compile("12345,777", "deny")
    T.eq(filter.NeedsKey(idsOnly), false, "there are no names in the list, so no key is needed")
    T.eq(filter.Decide(idsOnly, nil, 777), filter.HIDE, "the number is named all the same")
end

T.suite("the aura filter: a decision's cost does not depend on the list's length")

do
    -- The very property the filter is split in two for, and also the main
    -- thing that is obliged to survive the move into the core. It is checked by
    -- time rather than by reasoning: a filter that walks the list for every
    -- aura would show a thousandfold difference here.
    local filter = core().Api:GetAuraFilter()

    local long = {}
    for i = 1, 1000 do long[i] = "Spell " .. i end

    local one = filter.Compile("Spell 1", "deny")
    local big = filter.Compile(table.concat(long, ","), "deny")
    T.eq(big.count, 1000, "a list of a thousand was parsed whole")

    local ROUNDS = 200000

    --- How many seconds ROUNDS decisions by a plan take.
    -- @param plan table
    -- @return number
    local function measure(plan)
        local started = os.clock()
        for _ = 1, ROUNDS do
            filter.Decide(plan, "spell 500", 4242)
        end
        return os.clock() - started
    end

    local short = measure(one)
    local thousand = measure(big)

    io.write(string.format(
        "  [the core filter's cost] %d decisions: a list of one %.3f ms, "
        .. "of a thousand %.2f ms\n", ROUNDS, short * 1000, thousand * 1000))

    -- The ratio: an allowance for the clock's jitter rather than for an order of magnitude.
    T.ok(thousand <= (short + 0.02) * 4,
        "a list of a thousand costs as much as one of a single entry")
    -- And a ceiling in seconds: the ratio would stay green if both grew dearer.
    T.ok(thousand * 1000 < 50, string.format(
        "%d decisions by a list of a thousand fit into 50 ms: %.2f ms",
        ROUNDS, thousand * 1000))
end

helpers.removeValidator()
