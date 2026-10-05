local helpers = require("helpers")

T.suite("ParseCommand")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Command.lua", ns)

-- Rubbish on the input must not demand checks from the caller.
local cmd, rest = ns.ParseCommand(nil)
T.eq(cmd, "", "nil: no subcommand")
T.eq(rest, "", "nil: no remainder")

cmd, rest = ns.ParseCommand("")
T.eq(cmd, "", "an empty string: no subcommand")
T.eq(rest, "", "an empty string: no remainder")

cmd, rest = ns.ParseCommand("   ")
T.eq(cmd, "", "whitespace only: no subcommand")
T.eq(rest, "", "whitespace only: no remainder")

cmd, rest = ns.ParseCommand("scan")
T.eq(cmd, "scan", "one subcommand")
T.eq(rest, "", "no remainder")

cmd, rest = ns.ParseCommand("scan Player")
T.eq(cmd, "scan", "a subcommand with an argument")
T.eq(rest, "Player", "the argument was separated")

cmd, rest = ns.ParseCommand("scan    Player")
T.eq(cmd, "scan", "extra whitespace inside: the subcommand")
T.eq(rest, "Player", "extra whitespace inside was collapsed")

cmd, rest = ns.ParseCommand("   scan Player   ")
T.eq(cmd, "scan", "whitespace at the edges: the subcommand")
T.eq(rest, "Player", "whitespace at the edges was dropped")

-- An argument of several words stays one piece: a search pattern may hold a
-- space, and the caller should not have to glue it back together.
cmd, rest = ns.ParseCommand("scan Party Member")
T.eq(cmd, "scan", "a multi-word argument: the subcommand")
T.eq(rest, "Party Member", "the multi-word argument was kept whole")

T.suite("the parts' words: a switched-off part answers in words")

-- Silence here is the worst of answers: the player typed a word, nothing
-- happened, and he has nothing to understand why with. A part is switched off
-- in two ways — by its own failure and by the core's decision — and to the player they are the same.
do
    -- A core of our own: the registry needs the real one rather than a fake —
    -- it is what decides whether a part is switched off.
    local core = helpers.newNamespace()
    helpers.loadAddonFile("Core/Locale.lua", core)
    helpers.loadAddonFile("Core/Registry.lua", core)
    helpers.loadAddonFile("Core/Command.lua", core)

    local said = {}
    core.Registry.report = function() end
    core.Addon = { Print = function(_, text) said[#said + 1] = text end }

    local ran = 0
    core.Registry:Register({ name = "umbratalk" })
    core.RegisterModuleCommand("umbratalk", "talk", function() ran = ran + 1 end)

    T.eq(core.RunModuleCommand("talk", ""), true, "the word was carried out")
    T.eq(ran, 1, "and the part heard it")
    T.eq(#said, 0, "silently, as a working part should")

    core.Registry:Disable("umbratalk", "a check")
    T.eq(core.RunModuleCommand("talk", ""), true, "the word is still ours")
    T.eq(ran, 1, "but it did not reach the part")
    T.eq(#said, 1, "while it was said aloud: " .. table.concat(said, " | "))
end
