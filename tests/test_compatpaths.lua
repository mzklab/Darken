local helpers = require("helpers")

-- Paths: the name of what lies inside somebody else's object.
--
-- WHY THIS EXISTS. The compatibility layer could name only globals. What has
-- no global name — a field inside a frame — it could not name, and a setting
-- that needs such a field silently did nothing. That is exactly what happened
-- with the main bar's gryphons: in 1.60.1 there is not one of the three
-- declared names, and there is no replacement among the globals and cannot be.
--
-- WHAT IS CHECKED HERE. Not "the path works" but what is most dangerous not to
-- get from a path: existence is asked about at **every** step, somebody else's
-- object does not break while being walked, and "we got to the middle" is
-- distinguishable from "there is nothing". The latter is the only answer that
-- says "look here", and losing it would mean returning to silence through another door.
--
-- What is not here: the correctness of the paths themselves. Whether
-- MainActionBar.LeftEndCap exists in a live client no check outside the client will say — that is what the report is for.

T.suite("Paths: the parse of a spelling")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", ns)
local Compat = ns.Compat

T.eq(#Compat.PathParts("MainActionBar"), 1, "a plain name is a path of one step")
T.eq(#Compat.PathParts("MainActionBar.LeftEndCap"), 2, "two steps")
T.eq(Compat.PathParts("MainActionBar.EndCaps.LeftEndCap")[3], "LeftEndCap",
    "the third step was parsed")

-- The parse is deliberately strict: a lax one would merge a typo with an
-- intention, and "A..B" would silently mean "A.B" — that is, a path the author never wrote.
T.eq(#Compat.PathParts("A..B"), 0, "a double dot is not a path but a typo")
T.eq(#Compat.PathParts(".A"), 0, "a dot at the beginning is a typo")
T.eq(#Compat.PathParts("A."), 0, "a dot at the end is a typo")
T.eq(#Compat.PathParts(""), 0, "an empty string is not a path")
T.eq(#Compat.PathParts(nil), 0, "nor is a nil")

T.suite("Paths: existence is checked at every step")

do
    -- A stand-in client. The dictionary arrives as an argument, so the whole
    -- walk is checked outside the game.
    local caps = { LeftEndCap = { kind = "texture" } }
    local globals = {
        MainActionBar = { EndCaps = caps },
        PlainGlobal   = 7,
        SomeFunction  = function() return 1 end,
        -- The file handle is real userdata rather than a fake made of a table:
        -- it is on userdata that ordinary indexing breaks.
        Handle        = io.stdout,
        Angry = setmetatable({}, {
            __index = function() error("somebody else's metatable threw", 0) end,
        }),
    }

    -- 1. A path that resolves.
    local object, info = Compat.LookupSteps(globals,
        "MainActionBar.EndCaps.LeftEndCap")
    T.eq(object, caps.LeftEndCap, "a path that resolved returns the object itself")
    T.eq(info.reached, 3, "all three steps were walked")
    T.eq(info.parts, 3, "and there were three steps")
    T.eq(info.stopped, nil, "there was nothing to stop at")

    -- 2. The first step is missing. That is the ordinary "the name was guessed wrong".
    object, info = Compat.LookupSteps(globals, "NoSuchBar.LeftEndCap")
    T.eq(object, nil, "no beginning means no object")
    T.eq(info.reached, 0, "not a step was walked")
    T.eq(info.stopped, "NoSuchBar", "and it is said what we stopped at")

    -- 3. The middle is missing. The first step is there, the second is not —
    -- that is a "no" too, but it has to be said differently: what has to be looked for is not another bar.
    object, info = Compat.LookupSteps(globals, "MainActionBar.Art.LeftEndCap")
    T.eq(object, nil, "no middle means no object")
    T.eq(info.reached, 1, "one step out of three was walked")
    T.eq(info.stopped, "Art", "we stopped in the middle")
    T.eq(info.blocked, false, "and we stopped because the step is missing rather than "
        .. "because there is nowhere to enter")

    -- 4. The last step is missing. That very "we are close".
    object, info = Compat.LookupSteps(globals, "MainActionBar.RightEndCap")
    T.eq(object, nil, "no end means no object")
    T.eq(info.reached, 1, "but the beginning is there")
    T.eq(info.parts, 2, "out of two steps")
    T.eq(info.stopped, "RightEndCap", "and it is the last step that is named")

    -- 5. A path through userdata. Reading a field is harmless; assuming a
    -- table where there is userdata is not: ordinary indexing throws here.
    object, info = Compat.LookupSteps(globals, "Handle.write")
    T.eq(object, nil, "there is no way through userdata")
    T.eq(info.reached, 1, "the userdata itself exists meanwhile")
    T.eq(info.blocked, true, "and that is recorded separately: there is nowhere to enter")
    T.eq(type(globals.Handle), "userdata", "the stand-in userdata is a real one")

    -- The same case for a number and a function: not "empty" but "there is nowhere further".
    object, info = Compat.LookupSteps(globals, "PlainGlobal.Anything")
    T.eq(info.reached, 1, "the number exists")
    T.eq(info.blocked, true, "while there is no way inside a number")
    object, info = Compat.LookupSteps(globals, "SomeFunction.Anything")
    T.eq(info.blocked, true, "nor inside a function")

    -- Somebody else's metatable is entitled to throw. Walking somebody else's
    -- object has no right to bring the addon down.
    object, info = Compat.LookupSteps(globals, "Angry.Anything")
    T.eq(object, nil, "a metatable that threw is a \"no\" rather than a failure")
    T.eq(info.blocked, true, "and is recorded as \"entering did not work\"")

    -- 6. A path resolved into something other than expected. The layer promises
    -- existence and only it: the object's kind is asked by the caller, of the object itself.
    object, info = Compat.LookupSteps(globals, "PlainGlobal")
    T.eq(object, 7, "a number may lie at a path")
    T.eq(info.reached, 1, "and that is a fully resolved path")
    T.eq(type(Compat.Lookup(globals, "SomeFunction")), "function",
        "and a function is as valid an answer as a frame")

    -- A plain name is the same path, only of one step.
    T.eq(Compat.Lookup(globals, "MainActionBar"), globals.MainActionBar,
        "a plain name resolves by the same walk")
    T.eq(Compat.Lookup(globals, "NoSuchThing"), nil, "while something that does not exist does not")
    T.eq(Compat.Lookup(nil, "MainActionBar"), nil, "with no dictionary there is no answer")
end

T.suite("Paths: the existence filter and a group")

do
    local caps = {}
    local globals = {
        MainMenuBarLeftEndCap = { texture = true },
        MainActionBar = { LeftEndCap = caps },
    }

    -- A path and a plain name lie in one group with no reservations: both pass
    -- through one filter.
    local names, objects = Compat.FilterExisting({
        "MainMenuBarLeftEndCap",
        "MainMenuBarRightEndCap",
        "MainActionBar.LeftEndCap",
        "MainActionBar.RightEndCap",
        "NoSuchBar.LeftEndCap",
    }, globals)

    T.eq(#names, 2, "only what exists was left")
    T.eq(names[1], "MainMenuBarLeftEndCap", "the plain name got through")
    T.eq(names[2], "MainActionBar.LeftEndCap", "and the path got through, the order kept")
    T.eq(objects[1], globals.MainMenuBarLeftEndCap, "the object is returned beside the name")
    T.eq(objects[2], caps, "and for a path the one lying inside is returned")
    T.eq(#objects, #names, "the arrays are of one length")

    -- Why the objects are returned from here rather than obtained by the
    -- caller: for a path a lookup in the dictionary does not work at all.
    T.eq(globals["MainActionBar.LeftEndCap"], nil,
        "the dictionary does not answer for a path — hence the second array")

    -- The framing group is declared with both names and paths for all three clients.
    local FLAVORS = { "vanilla", "tbc", "mists" }
    for i = 1, #FLAVORS do
        local group = Compat.GetFrameNames(FLAVORS[i], "actionbar-art")
        local paths = 0
        for j = 1, #group do
            if #Compat.PathParts(group[j]) > 1 then paths = paths + 1 end
        end
        T.ok(paths >= 4, FLAVORS[i] .. ": the framing is named with paths too: " .. paths)
        T.eq(#Compat.FilterExisting(group, {}), 0,
            FLAVORS[i] .. ": on a client with no framing nothing is left")
    end

    -- The path declared by a group is the very one written down in the watch
    -- list: two places say one and the same thing about one guess.
    local declared = {}
    local group = Compat.GetFrameNames("vanilla", "actionbar-art")
    for i = 1, #group do declared[group[i]] = true end
    T.ok(declared["MainActionBar.LeftEndCap"],
        "the path out of the watch list is declared by a group too")
end

T.suite("Paths: Resolve returns the objects, and they are a copy")

do
    -- Resolve is the layer's only place that reads _G, so the stand-in client
    -- here is a real one: the names are put into _G and removed afterwards.
    -- A clean table: the group has eight spellings, and any of them left in the
    -- globals by a neighbouring set of checks would arrive here as a third
    -- candidate. A stand-in client is obliged to be a stand-in entirely.
    local ART = {
        "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
        "MainMenuBarArtFrame", "MainActionBar",
    }
    local savedArt = {}
    for i = 1, #ART do
        savedArt[i] = _G[ART[i]]
        _G[ART[i]] = nil
    end

    local cap = { name = "cap" }
    _G.MainActionBar = { LeftEndCap = cap }
    ns.flavor = "vanilla"

    local names, objects = Compat.Resolve("actionbar-art")
    T.eq(#names, 1, "in the stand-in client exactly one candidate resolved")
    T.eq(names[1], "MainActionBar.LeftEndCap", "and it is a path rather than a name")
    T.eq(objects[1], cap, "the object arrived as the second array")

    names[1] = "spoiled"
    objects[1] = nil
    local again = Compat.Resolve("actionbar-art")
    T.eq(again[1], "MainActionBar.LeftEndCap",
        "the answer is a copy: spoiling it spoils nothing for anybody")

    ns.flavor = nil
    for i = 1, #ART do _G[ART[i]] = savedArt[i] end
end

T.suite("The report: the middle is there, the end is not")

do
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Locale/ruRU.lua", ns)
    helpers.loadAddonFile("Locale/ukUA.lua", ns)
    helpers.loadAddonFile("Core/Report.lua", ns)
    local Report = ns.Report

    -- A client in which the main bar exists while the framing field in it does
    -- not. That is the author's case: what has to be looked for is not another
    -- bar but another field name in this same one.
    local globals = { MainActionBar = { Fancy = {} } }
    local report = Report.Build("vanilla", globals, {})

    local art = report.groups["actionbar-art"]
    T.eq(art.verdict, Report.MISSING,
        "the verdict on the group is not softened: not found means not found")

    local near = {}
    for i = 1, #report.near do near[report.near[i].path] = report.near[i] end

    T.ok(near["MainActionBar.LeftEndCap"] ~= nil,
        "a path that got to the middle is named")
    T.eq(near["MainActionBar.LeftEndCap"].prefix, "MainActionBar",
        "and it is said what exactly exists in the client")
    T.eq(near["MainActionBar.LeftEndCap"].stopped, "LeftEndCap",
        "and which step was not found")
    T.eq(near["MainMenuBarLeftEndCap"], nil,
        "a plain name does not get into that list: it has no middle")
    T.eq(near["MainMenuBarArtFrame.LeftEndCap"], nil,
        "and a path with no beginning is not an \"almost\" either")

    -- One and the same path is declared both by a group and by the watch list.
    -- Counting one guess as two would mean lying with a number.
    local seen = 0
    for i = 1, #report.near do
        if report.near[i].path == "MainActionBar.LeftEndCap" then
            seen = seen + 1
        end
    end
    T.eq(seen, 1, "the path is named once although it is written down in two places")

    -- The watch list says the same line by line.
    local watch = {}
    for i = 1, #report.watch do watch[report.watch[i].path] = report.watch[i] end
    T.eq(watch["MainActionBar.LeftEndCap"].found, false, "the path was not found")
    T.eq(watch["MainActionBar.LeftEndCap"].reached, 1,
        "but the first step was walked, and that is recorded beside it")
    T.eq(watch["C_NamePlate"].reached, nil,
        "a plain name has no \"how far we got\"")

    -- The order is stable: the report is compared between runs.
    local ordered = true
    for i = 2, #report.near do
        if report.near[i - 1].path > report.near[i].path then ordered = false end
    end
    T.ok(ordered, "the paths are sorted alphabetically")

    -- The line for the chat. It is the only one in the whole report that says
    -- not "we did not find it" but "look here".
    local lines = Report.Lines(report)
    local first = report.near[1].path
    local said = nil
    for i = 1, #lines do
        if lines[i]:find(first, 1, true) then said = lines[i] end
    end
    T.ok(said ~= nil, "the report names the almost-found path aloud: " .. first)
    T.ok(said ~= nil and said:find(report.near[1].prefix, 1, true) ~= nil,
        "and names the object that does exist in the client: " .. tostring(said))

    -- A client in which the bar itself is missing too: there is no "almost", and no line.
    local blind = Report.Build("vanilla", {}, {})
    T.eq(#blind.near, 0, "no beginning means no \"almost\" either")
    local quiet = Report.Lines(blind)
    for i = 1, #quiet do
        T.ok(not quiet[i]:find("got part way"),
            "there is no line about an \"almost\" at all when there was no almost")
    end

    -- And the other way round: a path that resolved does not count as "almost found".
    local whole = Report.Build("vanilla",
        { MainActionBar = { LeftEndCap = {} } }, {})
    T.eq(whole.groups["actionbar-art"].verdict, Report.OK,
        "a resolved path is an ordinary \"ok\" for a group of spellings")
    T.eq(whole.groups["actionbar-art"].found, 1, "and exactly one was found")
    for i = 1, #whole.near do
        T.ok(whole.near[i].path ~= "MainActionBar.LeftEndCap",
            "what was found does not get into the \"almost\"")
    end
end
