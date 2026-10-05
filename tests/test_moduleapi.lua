local helpers = require("helpers")

helpers.installValidator()

-- The third version of the public contract: combat, strings, events, frame
-- names and the policy on reserved names.
--
-- The core could do all of this before -- and did not hand it out, so every
-- module wrote its own. What is checked here is not the happy path but the
-- promises: a failing event handler may not take the core down with it, work
-- deferred in combat must run once and in its own order, a module's
-- vocabulary is invisible to its neighbour, and a refusal over a reserved

--- The core as the public layer sees it.
-- @return table the namespace, table the list of what was said to the player
local function core()
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Frames.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Combat.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/Api.lua", ns)

    local said = {}
    ns.Registry.report = function(text) said[#said + 1] = text end
    ns.Addon = {
        db = { profile = {}, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }

    return ns, said
end

--- A descriptor with the mandatory fields filled in.
local function descriptor(over)
    local d = { name = "example", api = 1 }
    for key, value in pairs(over or {}) do d[key] = value end
    return d
end

T.suite("contract: game events")

do
    local ns, said = core()
    local one = ns.Api:RegisterModule(descriptor({ name = "one" }))
    local two = ns.Api:RegisterModule(descriptor({ name = "two" }))

    local heard = {}
    T.eq(one:RegisterEvent("BAG_UPDATE_DELAYED", function(event, bag)
        heard[#heard + 1] = "one:" .. tostring(event) .. ":" .. tostring(bag)
    end), true, "the subscription was accepted")

    T.eq(two:RegisterEvent("BAG_UPDATE_DELAYED", function()
        heard[#heard + 1] = "two"
    end), true, "a second module listens to the same event")

    T.eq(ns.Events.Dispatch("BAG_UPDATE_DELAYED", 3), 2,
        "the event reached both")
    T.eq(heard[1], "one:BAG_UPDATE_DELAYED:3",
        "the handler received the event name and its arguments")

    -- One handler per (event, module) pair: subscribing from ApplySettings is
    -- legitimate, while a second copy of the handler would mean double work
    -- on every profile switch.
    one:RegisterEvent("BAG_UPDATE_DELAYED", function()
        heard[#heard + 1] = "one-again"
    end)
    heard = {}
    ns.Events.Dispatch("BAG_UPDATE_DELAYED")
    T.eq(#heard, 2, "a repeated subscription replaced the former one instead of adding a second")

    T.eq(one:UnregisterEvent("BAG_UPDATE_DELAYED"), true, "the subscription was removed")
    heard = {}
    T.eq(ns.Events.Dispatch("BAG_UPDATE_DELAYED"), 1, "one listener remained")

    T.eq(one:RegisterEvent("", function() end), false, "an empty event name is rejected")
    T.eq(one:RegisterEvent("PLAYER_LOGIN", 5), false, "a non-function is rejected")
    T.eq(#said, 0, "nobody was disabled: " .. table.concat(said, " | "))
end

do
    -- A failing handler. This is the main promise of a subscription: a module
    -- that raises an error in its handler is disabled itself and takes
    -- neither the core nor its neighbour with it.
    local ns, said = core()
    local rude  = ns.Api:RegisterModule(descriptor({ name = "rude" }))
    local quiet = ns.Api:RegisterModule(descriptor({ name = "quiet" }))

    local quietHeard = 0
    rude:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        error("the handler broke")
    end)
    quiet:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        quietHeard = quietHeard + 1
    end)

    T.eq(ns.Events.Dispatch("PLAYER_REGEN_DISABLED"), 1,
        "one handler out of two ran")
    T.eq(quietHeard, 1, "the neighbour received its event")
    T.eq(ns.Registry:IsFailed("rude"), true, "the failing module is disabled")
    T.eq(#said, 1, "and it was said once")
    T.ok(said[1]:find("rude", 1, true) ~= nil, "the message names the culprit")
    T.ok(said[1]:find("PLAYER_REGEN_DISABLED", 1, true) ~= nil,
        "and names the event: " .. said[1])

    -- A disabled module stops listening: the subscription is removed by the
    -- core, not by the module author's memory.
    T.eq(ns.Events.Count("PLAYER_REGEN_DISABLED"), 1,
        "the subscription of the disabled module was removed")

    quietHeard = 0
    ns.Events.Dispatch("PLAYER_REGEN_DISABLED")
    T.eq(quietHeard, 1, "the neighbour keeps listening")
end

T.suite("contract: work deferred to the end of combat")

do
    local ns, said = core()
    local module = ns.Api:RegisterModule(descriptor({ name = "deferring" }))

    local combat = false
    local saved = _G.InCombatLockdown
    _G.InCombatLockdown = function() return combat end

    local protected   = { IsProtected = function() return true end }
    local unprotected = { IsProtected = function() return false end }

    local done = {}

    -- No combat: the work runs at once, even on a protected object.
    T.eq(module:Secure(protected, "scale", function() done[#done + 1] = "a" end),
        true, "out of combat the work runs at once")
    T.eq(#done, 1, "and it runs exactly once")

    combat = true

    -- Combat, but the object is not protected: there is nothing to defer,
    -- otherwise the addon would go sluggish for no reason.
    T.eq(module:Secure(unprotected, "plain", function() done[#done + 1] = "b" end),
        true, "an unprotected object may be touched in combat")
    T.eq(#done, 2, "the work on it was done at once")

    -- Combat plus a protected object: only that is deferred.
    T.eq(module:Secure(protected, "scale", function() done[#done + 1] = "c" end),
        false, "protected work in combat is deferred")
    T.eq(ns.Combat.PendingFor("deferring"), 1, "one item is queued")
    T.eq(#done, 2, "and it has not run yet")

    -- A repeated write under the same key displaces the former one while
    -- keeping its place: ten slider moves give one application, not the whole history.
    module:Secure(protected, "scale", function() done[#done + 1] = "d" end)
    module:Secure(protected, "position", function() done[#done + 1] = "e" end)
    T.eq(ns.Combat.PendingFor("deferring"), 2, "there are still two keys")

    T.eq(module:InCombat(), true, "the module sees combat")

    combat = false
    T.eq(ns.Events.Dispatch("PLAYER_REGEN_ENABLED"), 1,
        "leaving combat drains the queue")
    T.eq(table.concat(done, ""), "abde",
        "the last action of every key ran, in the order of first write")
    T.eq(ns.Combat.PendingFor("deferring"), 0, "the queue is empty")
    T.eq(#said, 0, "nobody is disabled")

    -- Garbage on the input neither breaks the module nor pretends to succeed.
    local okCall, reason = module:Secure(protected, "", function() end)
    T.eq(okCall, false, "an empty key is rejected")
    T.ok(type(reason) == "string" and reason ~= "", "and the refusal is stated in words")

    _G.InCombatLockdown = saved
end

do
    -- A deferred action that fails. Nobody calls it from outside: the queue
    -- is drained on an event, that is outside the protection of anyone's call.
    local ns, said = core()
    local module = ns.Api:RegisterModule(descriptor({ name = "late" }))
    local neighbour = ns.Api:RegisterModule(descriptor({ name = "neighbour" }))

    local saved = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    local protected = { IsProtected = function() return true end }

    module:Secure(protected, "boom", function() error("a late breakage") end)
    local neighbourDone = false
    neighbour:Secure(protected, "fine", function() neighbourDone = true end)

    _G.InCombatLockdown = saved

    T.eq(ns.Combat.DrainAll(), 1, "one action out of two went through")
    T.eq(neighbourDone, true, "the neighbour did its own")
    T.eq(ns.Registry:IsFailed("late"), true, "the one that failed on leaving combat is disabled")
    T.eq(ns.Registry:IsFailed("neighbour"), false, "the neighbour works")
    T.eq(#said, 1, "there is one message: " .. table.concat(said, " | "))
end

T.suite("contract: a disabled module does not come back")

do
    -- The core disables a failing module and removes its subscriptions. The
    -- door back was left open, though: its own timer, its own OnUpdate or a
    -- hook on a foreign frame -- the module code keeps running after being
    -- disabled, the document says so outright -- and one handle:RegisterEvent
    -- line put the subscription back. There was nobody left to remove it a
    -- second time: Disable stays silent for an already disabled name. The
    -- core receiver woke up on every such event until the interface was
    -- reloaded -- exactly the cost the unsubscribe was written for.
    local ns, said = core()
    local dead = ns.Api:RegisterModule(descriptor({ name = "brokenone" }))
    local live = ns.Api:RegisterModule(descriptor({ name = "goodone" }))

    dead:RegisterEvent("BAG_UPDATE_DELAYED", function() error("broke") end)
    live:RegisterEvent("BAG_UPDATE_DELAYED", function() end)

    T.eq(ns.Events.Count("BAG_UPDATE_DELAYED"), 2, "two are listening")
    ns.Events.Dispatch("BAG_UPDATE_DELAYED")
    T.eq(ns.Registry:IsFailed("brokenone"), true, "the failing one is disabled")
    T.eq(ns.Events.Count("BAG_UPDATE_DELAYED"), 1, "its subscription was removed")

    -- Here is the breakage itself: a disabled module asks to subscribe again.
    local heard = 0
    T.eq(dead:RegisterEvent("BAG_UPDATE_DELAYED", function() heard = heard + 1 end),
        false, "a disabled module is refused a subscription")
    T.eq(ns.Events.Count("BAG_UPDATE_DELAYED"), 1,
        "and the subscription did not come back: only the live neighbour listens")

    -- Subscribing to an event nobody else listens to would bring the event
    -- back to the core receiver itself -- that is, to the player's frames.
    T.eq(dead:RegisterEvent("PLAYER_REGEN_DISABLED", function() heard = heard + 1 end),
        false, "and to a new event as well")
    T.eq(ns.Events.Count("PLAYER_REGEN_DISABLED"), 0, "no listeners appeared")
    T.eq(ns.Events.asked["PLAYER_REGEN_DISABLED"], nil,
        "and the game was not asked for that event")

    ns.Events.Dispatch("BAG_UPDATE_DELAYED")
    T.eq(heard, 0, "the handler of a disabled module is not called")

    -- The live neighbour is not affected: the refusal is targeted.
    T.eq(live:RegisterEvent("PLAYER_REGEN_DISABLED", function() end), true,
        "a live module subscribes as before")

    T.eq(#said, 1, "there is still one message: " .. table.concat(said, " | "))
end

do
    -- The same for the deferral queue: a disabled module kept its own alive
    -- and could keep putting work into it.
    local ns, said = core()
    local dead = ns.Api:RegisterModule(descriptor({ name = "queuer" }))

    local saved = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    local protected = { IsProtected = function() return true end }

    local ran = 0
    dead:Secure(protected, "attr", function() ran = ran + 1 end)
    T.eq(ns.Combat.PendingFor("queuer"), 1, "the work is deferred")

    ns.Registry:Disable("queuer", "a check")
    T.eq(ns.Registry:IsFailed("queuer"), true, "the module is disabled")
    T.eq(ns.Combat.PendingFor("queuer"), 0,
        "the queue of a disabled module is removed along with its subscriptions")

    -- And new work does not go into it.
    local okCall, reason = dead:Secure(protected, "attr", function() ran = ran + 1 end)
    T.eq(okCall, false, "a disabled module has nothing to defer")
    T.ok(type(reason) == "string" and reason ~= "",
        "and the refusal is stated in words: " .. tostring(reason))
    T.eq(ns.Combat.PendingFor("queuer"), 0, "the queue did not come back to life")

    _G.InCombatLockdown = saved

    T.eq(ns.Combat.DrainAll(), 0, "there is nothing to run on leaving combat")
    T.eq(ran, 0, "not a single action of the disabled module ran")
end

T.suite("contract: module strings")

do
    local ns = core()
    local module = ns.Api:RegisterModule(descriptor({ name = "speaker" }))
    local other  = ns.Api:RegisterModule(descriptor({ name = "listener" }))

    local strings = { ["Bags"] = "Сумки", ["Nothing matches"] = "Ничего не найдено" }
    T.eq(module:RegisterStrings("ruRU", strings), true, "the strings were accepted")
    T.eq(module:RegisterStrings("ruRU", nil), false, "a non-table is rejected")
    T.eq(module:RegisterStrings("", strings), false, "an empty locale is rejected")

    -- The core picks the language: a second detection of the client language
    -- would diverge from ours, and a module would speak a different language
    ns.SetLocale("deDE")
    T.eq(module:Localize("Bags"), "Bags", "an unknown locale leaves English in place")

    ns.SetLocale("ruRU")
    T.eq(module:Localize("Bags"), "Сумки", "a known locale translates")
    T.eq(module:Localize("no such key"), "no such key",
        "an untranslated key stays itself")
    T.eq(module:Localize(nil), "", "nothing to translate -- an empty string")
    T.eq(module:Localize(""), "", "and the same for an empty key")

    -- The vocabulary is locked to the module name: another module's strings are out of reach.
    T.eq(other:Localize("Bags"), "Bags", "a neighbour does not see the other translation")

    -- The table is copied: it stays with the module, and the core has its own.
    strings["Bags"] = "a substitution"
    T.eq(module:Localize("Bags"), "Сумки", "editing your own table does not touch the core")

    ns.SetLocale(nil)
end

T.suite("contract: game frame names")

do
    local ns = core()
    local module = ns.Api:RegisterModule(descriptor({ name = "decorator" }))
    T.ok(module ~= nil, "the module is registered")

    -- Before the core has determined the client the list is empty, and that
    -- is not an error: an exception would be raised from the file body of a foreign addon.
    T.eq(#ns.Api:GetFrameNames("unitframe"), 0, "before the core starts there are no names")

    ns.flavor = "mists"

    local savedPlayer, savedTarget = _G.PlayerFrame, _G.TargetFrame
    _G.PlayerFrame = { "the player frame" }

    local names = ns.Api:GetFrameNames("unitframe")
    T.eq(#names, 1, "only an existing name was handed out")
    T.eq(names[1], "PlayerFrame", "and that is the one")

    -- A new array is handed out: a shared table would let a module rewrite
    -- the frame list for the whole addon.
    names[1] = "a substitution"
    T.eq(ns.Api:GetFrameNames("unitframe")[1], "PlayerFrame",
        "editing the answer does not touch the shared table")

    _G.TargetFrame = { "the target frame" }
    T.eq(#ns.Api:GetFrameNames("unitframe"), 2,
        "a frame that appeared appears in the answer too")

    T.eq(#ns.Api:GetFrameNames("no such group"), 0, "an unknown group is empty")
    T.eq(#ns.Api:GetFrameNames(nil), 0, "with no group, empty")
    -- A group that does not exist on this client at all. It is checked with
    -- an existing frame on purpose: formerly mists stood here, where
    -- castbar-focus exists in Core/Compat.lua while _G.FocusFrameSpellBar
    -- does not exist outside the game -- and the zero came from the existence
    -- filter, that is from the same thing checked three lines above. The
    -- difference shows only this way: one and the same live frame is handed
    local savedFocus = _G.FocusFrameSpellBar
    _G.FocusFrameSpellBar = { "the focus cast bar" }

    T.eq(#ns.Api:GetFrameNames("castbar-focus"), 1,
        "on a client with focus the group hands out its frame")

    ns.flavor = "vanilla"
    T.eq(#ns.Api:GetFrameNames("castbar-focus"), 0,
        "on a client without focus there is no group, and an existing frame does not help")
    T.eq(#ns.Api:GetFrameNames("unitframe"), 2,
        "while known groups on this client answer as before")

    _G.FocusFrameSpellBar = savedFocus
    _G.PlayerFrame, _G.TargetFrame = savedPlayer, savedTarget
end

T.suite("contract: name collisions")

do
    local ns, said = core()

    --- A refusal with a reason.
    local function rejects(name, needle, why)
        local handle, reason = ns.Api:RegisterModule(descriptor({ name = name }))
        T.eq(handle, nil, why .. ": there is no registration")
        T.ok(type(reason) == "string" and reason:find(needle, 1, true) ~= nil,
            why .. ": the reason should contain \"" .. needle .. "\", got: "
            .. tostring(reason))
        T.ok(reason and reason:find(name, 1, true) ~= nil,
            why .. ": the reason names the name itself")
    end

    -- The name of a core subsystem. The list is closed (Core/Defaults.lua): a
    -- module written today will not break with tomorrow's core update. But
    -- the names already taken are taken forever, and the refusal must say so
    -- in words -- silence here is the very breakage all of this is about.
    rejects("bags", "belongs to Darken itself", "a core subsystem name")
    rejects("darkness", "belongs to Darken itself", "and one more")

    -- The core prefix: future subsystems grow behind it, and it is closed to
    -- a module. That way the core has room to grow without taking anything from anyone.
    rejects("core_anything", "core_", "the core prefix")
    rejects("core_", "core_", "the prefix alone with no name")

    -- Neighbouring names are free: the ban is about the prefix, not about a letter.
    local ok = ns.Api:RegisterModule(descriptor({ name = "corestuff" }))
    T.ok(ok ~= nil, "a name without an underscore is free")
    local umbra = ns.Api:RegisterModule(descriptor({ name = "umbrabags" }))
    T.ok(umbra ~= nil, "a name after your own addon is free")

    T.eq(#said, 4, "one message to the player per refusal")
end

do
    -- A version the core does not have. The module does not load, the player
    -- reads what to do, and no yellow Lua error appears.
    local ns = core()
    local handle, reason = ns.Api:RegisterModule(
        descriptor({ name = "future", api = ns.Api.API_VERSION + 1 }))
    T.eq(handle, nil, "a module from the future is not registered")
    T.ok(type(reason) == "string" and reason:find("update Darken", 1, true),
        "and it says what to update: " .. tostring(reason))

    local old, oldReason = ns.Api:RegisterModule(
        descriptor({ name = "ancient", api = 0 }))
    T.eq(old, nil, "a version below the first is not accepted")
    T.ok(type(oldReason) == "string", "and the refusal has a reason")
end

helpers.removeValidator()
