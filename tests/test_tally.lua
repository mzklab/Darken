local helpers = require("helpers")
local wholecost = require("wholecost")

-- The tally of work done.
--
-- What is checked here is not "the counter exists" but the one property it
-- was written for: **a zero must mean something**. A counter that is always
-- zero because nobody increments it is exactly the reassuring lie the client
-- report was written against. A counter indistinguishable from a missing
-- subsystem is the same lie from the other side.
--
-- Hence the composition of the file:
--
--   1. The verdict on a counter -- every outcome separately, each with the
--      converse question attached: what this outcome is **not**.
--   2. The dictionary, for consistency: a partner points at an existing key,
--      the labels are not repeated, every counter has one sentence of
--      meaning.
--   3. The cross-cutting rule of the analysis: a claimed zero of a required
--      kind never looks like "all is well".
--   4. **The live paths.** Every counter is driven above zero by the very
--      code that runs in the game rather than by writing a number into a
--      table. A check that adds one itself proves only addition.
--   5. A cross-check against the package: every dictionary key must be
--      incremented somewhere in the shipped files. That is the place where "a
--      counter nobody touches" goes red rather than green.
--
-- What is not here and cannot be: the correctness of the numbers themselves
-- in a live client. Thirty nameplates of a fake client are thirty
-- attachments, and how many the player will have only the player can say.

--============================================================================
-- 1. The verdict on one counter
--============================================================================

T.suite("tally: the verdict on one counter")

local pure = helpers.newNamespace()
helpers.loadAddonFile("Core/Locale.lua", pure)
helpers.loadAddonFile("Core/Tally.lua", pure)

local Tally = pure.Tally

-- An unclaimed counter is not a zero. It means "the subsystem that keeps it
-- is not in this build", and that never counts as a problem.
T.eq(Tally.Verdict(Tally.NEEDED, nil, nil), Tally.UNCLAIMED,
    "nobody claimed the counter -- the subsystem is not in the build")
T.ok(Tally.Verdict(Tally.NEEDED, nil, nil) ~= Tally.IDLE,
    "and that is not called a failure")
T.eq(Tally.IsTrouble(Tally.UNCLAIMED), false,
    "an unclaimed counter does not count as a problem")

-- A claimed zero of a required kind IS the answer the whole tally exists for.
T.eq(Tally.Verdict(Tally.NEEDED, 0, nil), Tally.IDLE,
    "claimed and never touched -- the subsystem did nothing")
T.eq(Tally.IsTrouble(Tally.IDLE), true, "and that is a problem")
T.ok(Tally.Verdict(Tally.NEEDED, 0, nil) ~= Tally.EMPTY,
    "\"empty and rightly so\" is a different answer")

-- A claimed zero of an ordinary kind means nothing: there may have been no work.
T.eq(Tally.Verdict(Tally.NORMAL, 0, nil), Tally.EMPTY,
    "a zero where a zero was to be expected")
T.eq(Tally.IsTrouble(Tally.EMPTY), false, "and it does not count as a problem")

T.eq(Tally.Verdict(Tally.NORMAL, 7, nil), Tally.DONE, "seven were done")
T.eq(Tally.Verdict(Tally.NEEDED, 1, nil), Tally.DONE, "at least something was done")

-- A failure counter: here the news is not a zero but a non-zero.
T.eq(Tally.Verdict(Tally.FAILURE, 0, nil), Tally.QUIET,
    "there were no failures -- that is good, not empty")
T.eq(Tally.IsTrouble(Tally.QUIET), false, "and it does not count as a problem")
T.eq(Tally.Verdict(Tally.FAILURE, 3, nil), Tally.FAILING, "three failures")
T.eq(Tally.IsTrouble(Tally.FAILING), true, "and this one is a problem")

-- The partner. A zero beside a working partner is a failure whatever the
-- kind: that is exactly "the name was found but nothing came of it" and "deferred and never run".
T.eq(Tally.Verdict(Tally.NORMAL, 0, 12), Tally.IDLE,
    "twelve hooks installed, zero fired -- that is a failure")
T.eq(Tally.Verdict(Tally.NORMAL, 0, 0), Tally.EMPTY,
    "a zero beside a zero partner means nothing")
T.eq(Tally.Verdict(Tally.NORMAL, 4, 12), Tally.DONE,
    "what fired counts as fired even with a partner")

--============================================================================
-- 2. The dictionary
--============================================================================

T.suite("tally: the dictionary is consistent")

do
    local seenKey, seenLabel = {}, {}
    local keys = {}
    for i = 1, #Tally.COUNTERS do
        local rule = Tally.COUNTERS[i]
        keys[rule.key] = true

        T.ok(type(rule.key) == "string" and rule.key ~= "",
            "the counter has a key")
        T.eq(seenKey[rule.key], nil, "the key is not repeated: " .. rule.key)
        seenKey[rule.key] = true

        T.ok(type(rule.label) == "string" and rule.label ~= "",
            "the counter has a label: " .. rule.key)

        -- The name in chat is not repeated. The hook counters share a label
        -- and are told apart by the subsystem -- so what is compared is what
        -- the player reads in full rather than half of it.
        local title = Tally.Title(rule)
        T.eq(seenLabel[title], nil, "the name in chat is not repeated: " .. title)
        seenLabel[title] = true

        -- One sentence of meaning. A counter that cannot be explained to the
        -- author in one phrase should not have been created at all.
        T.ok(type(rule.means) == "string" and #rule.means > 20,
            "the counter has a meaning in one sentence: " .. rule.key)

        T.ok(rule.kind == Tally.NEEDED or rule.kind == Tally.NORMAL
            or rule.kind == Tally.FAILURE,
            "the kind of the counter is named: " .. rule.key)
    end

    for i = 1, #Tally.COUNTERS do
        local rule = Tally.COUNTERS[i]
        if rule.pair ~= nil then
            T.eq(keys[rule.pair], true,
                "the partner points at an existing key: " .. rule.key)
            T.ok(rule.pair ~= rule.key, "and not at itself: " .. rule.key)
        end
    end

    -- The reading order is stable: two runs of the report are compared by eye.
    local order = Tally.Order()
    T.eq(#order, #Tally.COUNTERS, "the order names every counter")
    T.eq(order[1], Tally.COUNTERS[1].key, "and starts with the first")

    -- A new array is handed out: the dictionary is ours, there is nothing to rewrite it from outside.
    order[1] = "erased"
    T.eq(Tally.Order()[1], Tally.COUNTERS[1].key,
        "the order is handed out as a copy, not as the shared table")
end

--============================================================================
-- 3. The analysis
--============================================================================

T.suite("tally: the analysis does not err on the reassuring side")

do
    local report = Tally.Build({ dimmed = 0, plates = 5 }, nil)

    T.eq(report.counters.dimmed.verdict, Tally.IDLE,
        "a claimed zero of the darkening is a failure")
    T.eq(report.counters.plates.verdict, Tally.DONE, "five nameplates is work done")

    -- The sections of the analysis: every outcome lands in exactly its own.
    local idleKeys = {}
    for i = 1, #report.idle do idleKeys[report.idle[i].key] = true end
    T.eq(idleKeys.dimmed, true, "the darkening is named in the idle list")
    T.eq(idleKeys.plates, nil, "while the one that did its work is not")

    local unclaimed = {}
    for i = 1, #report.unclaimed do unclaimed[report.unclaimed[i]] = true end
    T.eq(unclaimed.dimmed, nil, "and it is not mixed with a claimed zero")

    -- The cross-cutting rule: no claimed zero of a required kind looks like
    -- work done.
    for i = 1, #report.order do
        local entry = report.counters[report.order[i]]
        if entry.value == 0 and entry.kind == Tally.NEEDED then
            T.ok(entry.verdict ~= Tally.DONE,
                "a zero required counter is not called done: "
                .. entry.key)
        end
    end
end

do
    -- A key the dictionary does not know can only be put there by a module.
    -- It is not lost: a vanished number can neither be read nor fixed.
    local report = Tally.Build({ plates = 1, somethingNew = 4 })
    T.eq(report.extra.somethingNew, 4, "the foreign key landed in a separate section")
    T.eq(report.extra.plates, nil, "while a known one did not")

    -- The table is shared, and through the contract a module can put anything
    -- into it. A report that failed on a foreign row would say nothing at all.
    local ok, broken = pcall(Tally.Build, { plates = "not a number" })
    T.eq(ok, true, "a foreign row in the table of numbers does not break the analysis")
    T.eq(broken.counters.plates.value, nil, "and it does not pretend to be a number")
end

do
    -- The modules are counted at the registry rather than by a second counter
    -- beside it: a second one would diverge from the first silently.
    local registry = {
        Each = function()
            local list = { "alpha", "beta", "gamma" }
            local i = 0
            return function()
                i = i + 1
                if list[i] then return {}, list[i] end
            end
        end,
        IsFailed = function(_, name) return name == "beta" end,
    }

    local report = Tally.Build({}, registry)
    T.eq(report.modules.live, 2, "two modules are in service")
    T.eq(report.modules.down, 1, "one is disabled")
    T.eq(report.modules.downNames[1], "beta", "and it is named individually")
end

--============================================================================
-- 4. The lines
--============================================================================

T.suite("tally: the lines speak first about what did not work")

do
    local lines = Tally.Lines(Tally.Build({
        dimmed = 0, plates = 12, blocked_darkness = 3,
    }))

    T.ok(#lines >= 3, "lines assembled: " .. #lines)

    -- The main rule of the order: idleness comes before work done. People
    -- read the first lines, the rest scrolls away.
    T.ok(lines[1]:find("Objects Dimmed", 1, true) ~= nil,
        "the first line names what did nothing: " .. lines[1])

    local all = table.concat(lines, "\\n")
    T.ok(all:find("Nameplates Attached 12", 1, true) ~= nil,
        "what was done is named as a number: " .. all)
    T.ok(all:find(
        "Secret Values The Engine Refused (Interface Darkness) 3",
        1, true) ~= nil,
        "the silent failures are named separately, and the subsystem is named: " .. all)
    T.ok(all:find("Containers Recorded", 1, true) == nil,
        "while an unclaimed counter does not go to chat at all")
end

do
    -- An addon that did nothing at all must say so out loud. An empty "this
    -- session" section would read as "a line was forgotten".
    local lines = Tally.Lines(Tally.Build({}))
    local all = table.concat(lines, "\\n")
    T.ok(all:find("did not do a single counted thing", 1, true) ~= nil,
        "an empty session is stated in words: " .. all)
end

--============================================================================
-- 5. The live paths: every counter is driven above zero by real code
--============================================================================

T.suite("tally: the darkening counts what it actually did")

do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Tally.lua", ns)
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Modules/Darkness.lua", ns)

    local counters = ns.Counters
    local Darkness = ns.Darkness

    local function texture(opts)
        local t = {
            r = 0.5, g = 0.5, b = 0.5, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function() return opts.file end,
            GetName = function() return opts.name end,
        }
        function t:GetVertexColor() return self.r, self.g, self.b, self.a end
        function t:SetVertexColor(cr, cg, cb, ca)
            self.r, self.g, self.b = cr, cg, cb
            if ca ~= nil then self.a = ca end
        end
        return t
    end

    -- Trim and content mixed together -- that is how they lie in a game
    local chrome = {
        texture({ file = "Interface\\DialogFrame\\UI-DialogBox-Border" }),
        texture({ file = "Interface\\DialogFrame\\UI-DialogBox-Corner" }),
    }
    -- window. The portrait and the icon are content, and they are recognised
    -- by name: a file id on its own says nothing, in current builds the trim
    -- is named by one too.
    local content = {
        texture({ file = 132863, name = "GameWindowPortrait" }),
        texture({ file = 132864, name = "GameWindowIcon" }),
    }

    local regions = {}
    for i = 1, #chrome do regions[#regions + 1] = chrome[i] end
    for i = 1, #content do regions[#regions + 1] = content[i] end

    local window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "GameWindow" end,
        GetRegions = function() return unpack(regions) end,
        GetChildren = function() return end,
    }

    local savedParent = _G.UIParent
    _G.UIParent = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "UIParent" end,
        GetRegions = function() return end,
        GetChildren = function() return window end,
    }

    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = {
        darkness = { amount = 40, exclude = {}, tint = {} } } } }

    T.eq(counters.dimmed, 0, "before the application the darkening did nothing")
    T.eq(counters.content, 0, "and saw no content")

    Darkness:ApplySettings()

    T.eq(counters.dimmed, #chrome,
        "exactly as many trim textures were darkened as there were: "
        .. counters.dimmed)
    T.eq(counters.content, #content,
        "and exactly as many were left as content: " .. counters.content)

    -- Two halves of one question. A pass that skipped everything and a pass
    -- that found nothing look the same -- this pair tells them apart.
    T.ok(counters.dimmed > 0 and counters.content > 0,
        "both halves of \"darkened against skipped\" are non-zero")

    -- A silent engine refusal: a colour an addon may not compute with.
    local secret = setmetatable({}, { __add = function()
        error("cannot be computed with") end })
    local blind = texture({ file = "Interface\\Anything" })
    blind.r = secret
    T.eq(counters.blocked_darkness, 0, "there have been no refusals yet")
    Darkness.Tint(blind, 0.5)
    T.eq(counters.blocked_darkness, 1, "the engine refusal was counted rather than swallowed")

    _G.UIParent = savedParent
end

T.suite("tally: bars, auras, deferred work and motion")

do
    local savedLibStub = LibStub
    LibStub = function(name)
        if name == "LibSharedMedia-3.0" then
            return { List = function() return {} end,
                IsValid = function() return false end,
                Fetch = function() return nil end }
        end
        return nil
    end

    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Tally.lua", ns)
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Combat.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/AuraFilter.lua", ns)
    helpers.loadAddonFile("Modules/UnitFrames.lua", ns)

    LibStub = savedLibStub

    local counters = ns.Counters

    local C = string.char(92)

    -- A bar. Replacing the texture is the only way the "bar texture" setting
    -- reaches the screen.
    do
        -- The bar remembers the assigned file and hands it back the way the
        -- engine does: only then is a "the same one a second time" replacement distinguishable.
        local bar = {
            GetStatusBarColor = function() return 1, 1, 1, 1 end,
            SetStatusBarColor = function() end,
        }
        bar.file = "Interface" .. C .. "Native" .. C .. "Bar"
        bar.SetStatusBarTexture = function(self, path) self.file = path end
        bar.GetStatusBarTexture = function(self)
            local owner = self
            return { GetTexture = function() return owner.file end }
        end
        T.eq(counters.retextured, 0, "no bars have been touched yet")
        T.eq(ns.UnitFrames.SetBarTexture(bar, "Interface\\Ours\\Bar"), true,
            "the texture was replaced")
        T.eq(counters.retextured, 1, "and the replacement was counted")

        -- The same texture a second time is not work, and does not count as work.
        ns.UnitFrames.SetBarTexture(bar, "Interface\\Ours\\Bar")
        T.eq(counters.retextured, 1,
            "replacing the same texture again does not touch the counter")
    end

    -- Auras. What is counted is what the list actually filtered; an aura the
    -- list has nothing to say about does not change the answer.
    do
        local plan = ns.AuraFilter.Compile("Rend", "deny")
        T.eq(counters.auras, 0, "the list has decided nothing yet")

        T.eq(ns.AuraFilter.Decide(plan, ns.AuraFilter.Key("Rend"), nil),
            ns.AuraFilter.HIDE, "what is named as denied gets hidden")
        T.eq(counters.auras, 1, "and the decision was counted")

        ns.AuraFilter.Decide(plan, ns.AuraFilter.Key("Blessing"), nil)
        T.eq(counters.auras, 1,
            "an aura the list has nothing to say about does not touch the counter")
    end

    -- Work deferred to the end of combat, and the end of combat.
    do
        local savedLock = _G.InCombatLockdown
        _G.InCombatLockdown = function() return true end

        ns.Registry:Register({ name = "tallytest" })

        local protected = { IsProtected = function() return true end }
        local ran = false

        T.eq(counters.deferred, 0, "nothing has been deferred yet")
        T.eq(ns.Combat.Secure("tallytest", protected, "move", function()
            ran = true
        end), false, "work on something protected in combat is deferred")
        T.eq(ran, false, "and is not done right now")
        T.eq(counters.deferred, 1, "the deferral was counted")

        T.eq(counters.drained, 0, "nothing from the queue has run yet")
        _G.InCombatLockdown = function() return false end
        ns.Combat.DrainAll()
        T.eq(ran, true, "on leaving combat the work was done")
        T.eq(counters.drained, 1, "and the run was counted")

        _G.InCombatLockdown = savedLock
    end

end
T.suite("tally: a fully booted addon counts its own work")

do
    -- The whole combat scene: the core, eight modules, thirty nameplates, the
    -- real nameplate engine from a separate folder. Here the counters are
    -- incremented by the very code that runs for the player.
    local scene = wholecost.scene({})
    T.eq(scene.boot.coreLoaded, true, "the scene came up: "
        .. tostring(scene.boot.coreError))

    local counters = scene.ns.Counters
    T.ok(type(counters) == "table", "the counter table was created")

    -- The main number of the file. The nameplate engine is a module, and
    -- without the contract (handle:Counters, version 17) this number would be unreachable.
    --
    -- The engine has a number of its own. On this scene the engine is on, so
    -- the core nameplate subsystem is stood down and its key is withdrawn:
    -- "stood down" and "here and did nothing" are different answers, and formerly there was nothing to tell them apart.
    T.ok((counters.plates_engine or 0) >= wholecost.PLATES,
        string.format("the engine attached to every nameplate: %d with %d on "
            .. "screen", counters.plates_engine or 0, wholecost.PLATES))
    T.eq(counters.plates, nil,
        "while the counter of the stood-down core subsystem is claimed by nobody")

    -- Hooks on game functions. Zero installed would mean that not a single
    -- guessed name was found; zero fired with a non-zero installed would mean
    -- that the name was found but nothing came of it.
    -- They are counted per subsystem: one shared number would hide a
    -- subsystem whose hook never fired behind the hooks of its neighbour.
    T.ok((counters.hooked_darkness or 0) > 0,
        "the darkening hooks are installed: "
        .. tostring(counters.hooked_darkness))
    T.ok((counters.hooked_unitframes or 0) > 0,
        "and the unit frame hooks too: "
        .. tostring(counters.hooked_unitframes))

    wholecost.busyFrame(scene)
    -- And the fired ones are counted per subsystem as well. On the fake scene
    -- exactly one hook fires -- the one of the bar labels -- and that is
    -- exactly what the shared number hid: the other six subsystems looked
    -- like they were working at its expense.
    local ran = {}
    for _, name in ipairs({ "bags", "darkness",
        "nameplates", "texts", "unitframes" }) do
        if (counters["fired_" .. name] or 0) > 0 then ran[#ran + 1] = name end
    end
    T.eq(table.concat(ran, ", "), "texts",
        "the bar label hook fired, and only it")

    local tally = scene.ns.Tally.Build(counters, scene.ns.Registry)
    T.eq(tally.counters.fired_unitframes.verdict, scene.ns.Tally.IDLE,
        "while the unit frame hook is called idle rather than done")

    T.ok((counters.dimmed or 0) > 0,
        "the darkening walked the fake interface: "
        .. tostring(counters.dimmed))

    -- The report assembles on a live scene and does not fail on anything.
    local report = scene.ns.Report.Build(scene.flavor, _G, {})
    T.ok(type(report.tally) == "table", "the tally went into the client report")
    T.eq(report.tally.counters.plates_engine.verdict, scene.ns.Tally.DONE,
        "and in the report the nameplates count as work done")
    T.eq(report.tally.counters.plates.verdict, scene.ns.Tally.UNCLAIMED,
        "while the stood-down core subsystem stays silent rather than counting as idle")

    local lines = scene.ns.Report.Lines(report)
    T.ok(#lines > 0, "the report lines assembled: " .. #lines)

    local all = table.concat(lines, "\\n")
    T.ok(all:find("this session", 1, true) ~= nil,
        "and they hold a section about what was done this session")

    scene.restore()
end

--============================================================================
-- 7. A cross-check against the package: a counter nobody increments
--============================================================================

T.suite("tally: somebody increments every counter")

do
    -- What this section is for. A counter that is always zero because nobody
    -- touches it looks in the report exactly like a subsystem that did
    -- nothing -- that is, it lies to the author in exactly the direction this
    -- whole mechanism was written against. That can only be caught here: in a
    -- live client the two pictures are identical.
    --
    -- The file list is asked of the package rather than copied here: the TOC
    -- lists everything the game reads, and the module folders everything the
    -- separate addons read. A copied list would fall behind silently.
    local sources = {}

    local toc = io.open("Darken.toc", "r")
    T.ok(toc ~= nil, "Darken.toc was opened")
    for line in toc:lines() do
        local path = line:match("^([%w_][%w_%.%-\\/]*%.lua)%s*$")
        if path then sources[#sources + 1] = (path:gsub("\\", "/")) end
    end
    toc:close()

    local folders = helpers.moduleFolders()
    for i = 1, #folders do
        local files = helpers.moduleSources(folders[i])
        for j = 1, #files do sources[#sources + 1] = files[j] end
    end

    local text = {}
    for i = 1, #sources do
        local handle = io.open(sources[i], "r")
        if handle then
            text[#text + 1] = handle:read("*a")
            handle:close()
        end
    end
    local whole = table.concat(text, "\n")
    T.ok(#whole > 100000, "the package was read: " .. #whole .. " bytes")

    for i = 1, #Tally.COUNTERS do
        local key = Tally.COUNTERS[i].key

        -- The increment. There is one form for the whole addon, chosen for
        -- cost: one integer addition through an already taken local
        -- reference. Alignment spaces in the source do not bother the pattern.
        local bump = "counters%." .. key .. "%s*=%s*counters%." .. key
            .. "%s*%+%s*1"
        T.ok(whole:find(bump) ~= nil,
            "somebody increments the counter: " .. key)

        -- The claim. Without it the idleness of a subsystem would look like
        -- its absence, and that is a different answer.
        local claim = "counters%." .. key .. "%s*=%s*counters%." .. key
            .. "%s*or%s*0"
        T.ok(whole:find(claim) ~= nil,
            "and somebody claims it while the file is read: " .. key)
    end
end

--============================================================================
-- 8. Every key has exactly one owner
--============================================================================

T.suite("tally: every key has exactly one owner")

do
    -- What this section is for. Section seven asks whether **anybody**
    -- increments a key. Seven subsystems writing into one pair of numbers
    -- satisfy it seven times in a row -- and that is exactly why it missed
    -- the case the pair was created for: the darkening hooks fire
    -- continuously, so fired is always above zero, and a subsystem whose hook
    -- never fired is invisible.
    --
    -- There is one rule here: a key is claimed by one file. Then its zero
    -- speaks about one subsystem rather than about seven at once.
    local sources = {}

    local toc = io.open("Darken.toc", "r")
    for line in toc:lines() do
        local path = line:match("^([%w_][%w_%.%-\\/]*%.lua)%s*$")
        if path then sources[#sources + 1] = (path:gsub("\\", "/")) end
    end
    toc:close()

    local folders = helpers.moduleFolders()
    for i = 1, #folders do
        local files = helpers.moduleSources(folders[i])
        for j = 1, #files do sources[#sources + 1] = files[j] end
    end

    -- The comments are discarded: Core/Api.lua shows a sample of claiming a
    -- counter in the contract description, and a sample is not an owner.
    local code = {}
    for i = 1, #sources do
        local handle = io.open(sources[i], "r")
        if handle then
            local lines = {}
            for line in handle:lines() do
                if not line:match("^%s*%-%-") then lines[#lines + 1] = line end
            end
            handle:close()
            code[sources[i]] = table.concat(lines, "\n")
        end
    end

    -- There are no exemptions, and formerly there was one: the plates key was
    -- shared by the core nameplate subsystem and the Features/NamePlates
    -- module, on the grounds that the module replaces the subsystem entirely
    -- (handle:Replaces) and therefore exactly one of the two is ever live.
    -- The grounds were wrong: the replacement is declared only from start(),
    -- that is only with the engine on, and the engine is off on a fresh
    -- install. Both owners are live at once for everyone who installed the
    -- module and did not enable it -- that is for everyone right after
    -- installing. Now the engine has its own key (plates_engine), and there
    -- is no room for an exemption here: the section asks exactly what it was written for, and it has no permitted "two" answers left.
    local shared, checked = {}, 0
    for i = 1, #Tally.COUNTERS do
        local key = Tally.COUNTERS[i].key
        local claim = "counters%." .. key .. "%s*=%s*counters%." .. key
            .. "%s*or%s*0"

        local owners = {}
        for path, body in pairs(code) do
            -- Core/Tally.lua claims no keys: it describes them.
            if path ~= "Core/Tally.lua" and body:find(claim) then
                owners[#owners + 1] = path
            end
        end
        table.sort(owners)
        checked = checked + 1

        if #owners ~= 1 then
            shared[#shared + 1] = key .. " -> " .. table.concat(owners, ", ")
        end
    end

    T.ok(checked >= 14, "the dictionary keys were gone through: " .. checked)
    table.sort(shared)
    T.eq(#shared, 0, "there are no keys with several owners: "
        .. table.concat(shared, " | "))
end

--============================================================================
-- 9. Hooks: a zero in one subsystem is visible over the work of its neighbour
--============================================================================

T.suite("tally: a hook that did not fire in one subsystem")

do
    -- Seven subsystems, seven pairs, and none shares a number with its neighbour.
    local SUBSYSTEMS = {
        "bags", "darkness",
        "nameplates", "texts", "unitframes",
    }
    for i = 1, #SUBSYSTEMS do
        local name = SUBSYSTEMS[i]
        local hooked = Tally.Describe("hooked_" .. name)
        local fired = Tally.Describe("fired_" .. name)

        T.ok(hooked ~= nil, "there is a counter of installed hooks: " .. name)
        T.ok(fired ~= nil, "and of fired ones: " .. name)
        T.eq(fired and fired.pair, "hooked_" .. name,
            "the partner points at its own subsystem: " .. name)
        T.ok(hooked ~= nil and hooked.subsystem ~= nil,
            "the subsystem is named: " .. name)
    end

    -- There is no shared pair any more: its zero meant nothing.
    T.eq(Tally.Describe("hooked"), nil, "no shared hooked is left")
    T.eq(Tally.Describe("fired"), nil, "nor a shared fired")
end


do
    -- Re-enabling a subsystem (Registry:Retry calls OnEnable again) does not
    -- increment the hook count: what is counted is the hooked game functions
    -- rather than the installations. All seven sources are asked at once.
    local OWNERS = {
        "Modules/Bags.lua", "Modules/Darkness.lua",
        "Modules/UnitFrames.lua",
    }
    local without = {}
    for i = 1, #OWNERS do
        local handle = io.open(OWNERS[i], "r")
        local body = handle and handle:read("*a") or ""
        if handle then handle:close() end
        if not body:find("counted%[") then without[#without + 1] = OWNERS[i] end
    end
    T.eq(#without, 0, "every subsystem remembers which names are already counted: "
        .. table.concat(without, " | "))
end
