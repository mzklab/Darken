local helpers = require("helpers")

T.suite("Scan.Find")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Scan.lua", ns)
local Scan = ns.Scan

-- A frame in the client is a table with userdata under the key 0.
-- We fake that in order to check the selection without the game.
local function fakeFrame()
    local t = {}
    rawset(t, 0, newproxy and newproxy(false) or nil)
    return t
end

local globals = {
    PlayerFrame      = fakeFrame(),
    PlayerFrameHP    = fakeFrame(),
    TargetFrame      = fakeFrame(),
    PlayerSettings   = { 0 },        -- not a frame: key 0 is not userdata
    PLAYER_CONSTANT  = "a string",   -- not a table at all
}

local found = Scan.Find("player", globals, 60)
T.eq(#found, 2, "only the frames holding the pattern were found")
T.eq(found[1], "PlayerFrame", "the result is sorted: the first")
T.eq(found[2], "PlayerFrameHP", "the result is sorted: the second")

T.eq(#Scan.Find("PLAYER", globals, 60), 2, "the pattern's case does not matter")
T.eq(#Scan.Find("", globals, 60), 0, "an empty pattern gives nothing")
T.eq(#Scan.Find(nil, globals, 60), 0, "a nil instead of a pattern")
T.eq(#Scan.Find("frame", globals, 1), 1, "the limit on results is observed")

T.suite("Scan.Collect")

T.ok(#Scan.PATTERNS > 0, "the list of patterns is not empty")

local collected, total = Scan.Collect(globals, { "player", "target", "none" }, 60)
T.eq(total, 3, "the names were counted over every pattern")
T.eq(#collected.frames["player"], 2, "the player pattern was gathered")
T.eq(#collected.frames["target"], 1, "the target pattern was gathered")
T.ok(collected.frames["none"] ~= nil, "a pattern with no matches is recorded all the same")
T.eq(#collected.frames["none"], 0, "and recorded as an empty list")

-- The empty lists are needed precisely because "there are no such names in
-- the client" is an answer, while a missing key is indistinguishable from "the pattern was never run".
local _, zero = Scan.Collect(nil, { "player" }, 60)
T.eq(zero, 0, "with no dictionary of globals nothing was gathered")

local byDefault = Scan.Collect(globals, nil, 60)
T.ok(byDefault.frames["Player"] ~= nil, "with no list of patterns Scan.PATTERNS is taken")

T.suite("Scan.Collect: the game's functions")

-- The compatibility layer declares more than frames: the bags' redrawing, the
-- bars' layout and the auras' layout are names of the game's functions. While
-- the selection took only objects with userdata under key 0, the directory
-- could neither confirm nor refute six of the addon's groups ever, and "the
-- name was guessed wrong" was indistinguishable from "the probe does not gather functions at all".
do
    local mixed = {
        ContainerFrame1              = fakeFrame(),
        ContainerFrame_GenerateFrame = function() end,
        ContainerFrame_OnShow        = function() end,
        CONTAINER_LIMIT              = 5,
    }

    local out = Scan.Collect(mixed, { "Container" }, 60)
    T.eq(#out.frames["Container"], 1, "the frame got into its own list")
    T.eq(out.frames["Container"][1], "ContainerFrame1", "and it is a frame specifically")

    T.eq(#out.functions["Container"], 2, "both functions were gathered")
    T.eq(out.functions["Container"][1], "ContainerFrame_GenerateFrame",
        "the functions are sorted: the first")
    T.eq(out.functions["Container"][2], "ContainerFrame_OnShow",
        "the functions are sorted: the second")

    -- A number, being neither a table nor a function, gets nowhere: the
    -- directory is about the existence of the names the addon declares, and it
    -- declares only frames and functions.
    local _, count = Scan.Collect(mixed, { "Container" }, 60)
    T.eq(count, 3, "both the frames and the functions were counted, and only they")

    -- A pattern with not a single match is recorded as empty in both lists:
    -- otherwise "there are no functions of that name" would be indistinguishable from "it was never asked".
    local empty = Scan.Collect(mixed, { "Nameplate" }, 60)
    T.ok(empty.frames["Nameplate"] ~= nil, "the empty list of frames was recorded")
    T.ok(empty.functions["Nameplate"] ~= nil, "the empty list of functions was recorded")
end

T.suite("Scan.Collect: a cut is visible and comes after the sorting")

-- THE FILE'S MAIN CHECK. The ceiling used to cut the list on the fly, in
-- pairs order, and sorted the remainder. Which means that for a pattern that
-- hit the ceiling an arbitrary part of the matches was returned, while a
-- name's absence from such a part proved nothing — and a cut list looked
-- exactly like a full one. The probe over a live client lost fourteen patterns
-- out of twenty-five on that.
--
-- Hence two checks, and both are obliged to fail separately: the list is cut
-- alphabetically (rather than however it happened), and the directory itself says that it is cut.
do
    local many = {}
    local expected = {}
    for i = 1, 300 do
        -- Names with leading zeroes: the alphabetical order matches the
        -- numeric one, and what is expected can be named outright.
        local name = string.format("BarWidget%03d", i)
        many[name] = fakeFrame()
        if i <= 10 then expected[i] = name end
    end

    local out, kept = Scan.Collect(many, { "BarWidget" }, 10)
    local list = out.frames["BarWidget"]

    T.eq(#list, 10, "the ceiling is observed")
    T.eq(kept, 10, "what was recorded was counted rather than what was found")

    -- Three hundred names in an arbitrary pairs order: such a cut cannot match
    -- the alphabetical first ten by chance. One that returned a cut before the
    -- sorting will fail this on the very first run.
    local same = true
    for i = 1, 10 do
        if list[i] ~= expected[i] then same = false end
    end
    T.ok(same, "the alphabetical first ten were kept rather than the first that came along")

    local wasCut, full = Scan.WasCut(out, "BarWidget")
    T.eq(wasCut, true, "the directory says the list is cut")
    T.eq(full, 300, "and names the real number of names")
    T.eq(out.limit, 10, "the ceiling is recorded beside the cut")
end

-- A full list is not marked as cut by anything: the pattern's key is not in
-- cut at all. It is for that distinction that all of this is written — a
-- name's absence from an UNCUT list proves the name's absence from the client.
do
    local out = Scan.Collect(globals, { "player", "target" }, 60)
    T.eq(next(out.cut), nil, "full lists are not marked as cut")
    T.eq(Scan.WasCut(out, "player"), false, "and answer \"not cut\" by name")
    T.eq(Scan.WasCut(out, "no such pattern"), false,
        "an unfamiliar pattern does not count as cut")
    T.eq(Scan.WasCut(nil, "player"), false, "nor does an empty directory")
end

-- The functions are cut by a ceiling of their own and marked by a field of
-- their own: a pattern may have a full list of frames and a cut list of functions at once.
do
    local mixed = {}
    for i = 1, 30 do
        mixed[string.format("ActionSlot%02d_Update", i)] = function() end
    end
    mixed.ActionBarOne = fakeFrame()

    local out = Scan.Collect(mixed, { "Action" }, 5)
    T.eq(#out.functions["Action"], 5, "the functions were cut by the ceiling")
    T.eq(out.functions["Action"][1], "ActionSlot01_Update",
        "and cut after the sorting")
    T.eq(#out.frames["Action"], 1, "the frames of the same pattern are untouched")

    local cutFunctions, fullFunctions = Scan.WasCut(out, "Action", "functions")
    T.eq(cutFunctions, true, "the functions' cut is marked")
    T.eq(fullFunctions, 30, "with the real number of functions")
    T.eq(Scan.WasCut(out, "Action", "frames"), false,
        "while the list of frames of the same pattern is full")
end

-- With no ceiling nothing is cut, and cut stays empty.
do
    local out, count = Scan.Collect(globals, { "frame" }, nil)
    T.eq(#out.frames["frame"], 3, "with no ceiling every match is returned")
    T.eq(count, 3, "and all of them were counted")
    T.eq(next(out.cut), nil, "there was nothing to cut")
end

T.suite("Scan.NeedsCollect")

T.ok(Scan.NeedsCollect(nil, "60100"), "there is no directory, so gather")
T.ok(Scan.NeedsCollect({}, "60100"), "a directory with no names, so gather")
T.ok(Scan.NeedsCollect({ build = "60000", found = {} }, "60100"),
     "the client's build changed, so gather afresh")
T.ok(not Scan.NeedsCollect({ build = "60100", found = {} }, "60100"),
     "the same build, so do not gather again")

-- The client may not return the build. A stale directory silently is worse
-- than one extra pass once per login.
T.ok(Scan.NeedsCollect({ build = "60100", found = {} }, nil),
     "the build is unknown, so gather")
T.ok(Scan.NeedsCollect({ build = "60100", found = {} }, ""),
     "an empty build, so gather")
