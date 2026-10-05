local helpers = require("helpers")

-- The client report.
--
-- What is checked here is not "the report was assembled" but the one
-- property it was written for: **it does not err on the reassuring side**. A
-- group called whole while it is empty is worse than having no report at all
-- -- the author will stop looking where it is broken, and will stop silently.
--
-- Hence the composition of the checks. Every verdict outcome is examined
-- separately, and each has the converse question attached: what this outcome
-- is **not**. Plus the cross-cutting rule checked on all groups at once: the
-- "ok" verdict is never issued for any zero of found names.
--
-- What is not here and cannot be: the correctness of the names themselves.
-- No check outside the client will say whether CastingBarFrame exists in the
-- live game -- that is what the report run inside it is for.

T.suite("report: the verdict on one group")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Locale/ruRU.lua", ns)
helpers.loadAddonFile("Locale/ukUA.lua", ns)
helpers.loadAddonFile("Core/Report.lua", ns)

local Compat, Report = ns.Compat, ns.Report

-- A group declared for a client and finding nothing is a wrong guess, and
-- that is the only thing the report was written for.
T.eq(Report.Judge(Report.REQUIRED, nil, 7, 0), Report.MISSING,
    "seven declared, nothing found -- the guess is wrong")
T.eq(Report.Judge(Report.ALTERNATIVES, nil, 2, 0), Report.MISSING,
    "two spellings of one thing and neither in the client -- a loss as well")
T.eq(Report.Judge(Report.SERIES, nil, 48, 0), Report.MISSING,
    "a cap of slots yielding not a single slot is a loss")

-- "Has not appeared yet" must come before every other outcome: it is the
-- only answer that can be replaced neither by "whole" nor by "empty".
T.eq(Report.Judge(Report.SERIES, "open the window", 48, 0), Report.UNCONFIRMED,
    "empty, but the window was never opened -- there is nothing to judge by")
T.eq(Report.Judge(Report.REQUIRED, "open the window", 4, 0), Report.UNCONFIRMED,
    "a required group with deferred appearance is not condemned either")
T.ok(Report.Judge(Report.REQUIRED, "open the window", 4, 0) ~= Report.OK,
    "and it is not called \"whole\" either")
T.ok(Report.Judge(Report.REQUIRED, "open the window", 4, 0) ~= Report.MISSING,
    "nor \"empty by mistake\": those are different answers")

-- An empty hook group is not a failure: every subsystem that uses them has
-- a fallback path written down.
T.eq(Report.Judge(Report.HOOKS, nil, 5, 0), Report.DEGRADED,
    "not a single function to hook -- the fallback path remains")
T.ok(Report.Judge(Report.HOOKS, nil, 5, 0) ~= Report.OK,
    "but such a group does not count as \"whole\"")

-- A partial match is a loss only where everything was expected.
T.eq(Report.Judge(Report.REQUIRED, nil, 7, 4), Report.PARTIAL,
    "four out of seven required ones is a loss")
T.eq(Report.Judge(Report.ALTERNATIVES, nil, 2, 1), Report.OK,
    "one of two spellings is normal by construction")
T.eq(Report.Judge(Report.SERIES, nil, 48, 6), Report.OK,
    "six slots out of a cap of forty-eight is normal by construction")
T.eq(Report.Judge(Report.HOOKS, nil, 5, 2), Report.OK,
    "two functions out of five -- there is something to hook")
T.eq(Report.Judge(Report.REQUIRED, nil, 7, 7), Report.OK,
    "everything is in place")

-- Zero declared is not an empty group but a group not declared for this
-- client at all.
T.eq(Report.Judge(Report.REQUIRED, nil, 0, 0), Report.ABSENT,
    "there was nothing to look for -- the group does not exist here")

-- Garbage on the input has no right to give a reassuring answer.
T.ok(Report.Judge(nil, nil, 3, 0) ~= Report.OK, "with no group kind it is not \"whole\"")
T.eq(Report.Judge(nil, nil, 3, nil), Report.MISSING,
    "a non-numeric \"found\" reads as zero rather than as \"all is well\"")

T.suite("report: an unknown group counts as required")

-- A new group in Core/Compat.lua that was forgotten in Core/Report.lua must
-- land in the losses rather than quietly count as healthy.
do
    local rule = Report.Consequence("no-group-with-this-name")
    T.eq(rule.kind, Report.REQUIRED, "the default is pessimistic")
    T.eq(rule.later, nil, "and it is given no reprieve")
    T.eq(Report.Judge(rule.kind, rule.later, 3, 0), Report.MISSING,
        "an unknown empty group is a loss")
end

-- And the omission itself is caught here, outside the client: every group of
-- every flavour must be described. The list is asked of the compatibility
-- layer rather than copied here: a copy would fall behind exactly when
-- Core/Report.lua.
do
    local undescribed = {}
    local all = Compat.AllGroups()
    for i = 1, #all do
        if Report.CONSEQUENCE[all[i]] == nil then
            undescribed[#undescribed + 1] = all[i]
        end
    end
    T.eq(#undescribed, 0, "groups with no described consequence: "
        .. table.concat(undescribed, " | "))
    T.ok(#all >= 40, "groups in the compatibility layer: " .. #all)
end

T.suite("Compat.AllGroups and Compat.Lookup")

-- The union of the groups is the very place where "deliberately empty"
-- differs from "empty by mistake". There is no focus cast bar in vanilla at
-- all, and that is recorded by the absence of a key.
do
    local here = {}
    local list = Compat.Groups("vanilla")
    for i = 1, #list do here[list[i]] = true end

    T.eq(here["castbar-focus"], nil, "vanilla declares no focus cast bar")

    local all = {}
    local everything = Compat.AllGroups()
    for i = 1, #everything do all[everything[i]] = true end
    T.eq(all["castbar-focus"], true, "but it is declared for other clients")

    -- The order is stable: the report is compared between runs.
    local sorted = true
    for i = 2, #everything do
        if everything[i - 1] > everything[i] then sorted = false end
    end
    T.ok(sorted, "the union is sorted")
end

do
    local globals = {
        GetPetHappiness = function() end,
        C_PetInfo = { GetPetFoodTypes = function() end },
    }
    T.ok(Compat.Lookup(globals, "GetPetHappiness") ~= nil, "a plain global")
    T.ok(Compat.Lookup(globals, "C_PetInfo.GetPetFoodTypes") ~= nil,
        "a function inside a table is found by a dotted path")
    T.eq(Compat.Lookup(globals, "C_PetInfo.GetPetHappiness"), nil,
        "what is not in the table is not found")
    T.eq(Compat.Lookup(globals, "GetPetHappiness.Anything"), nil,
        "a path through a function leads nowhere")
    T.eq(Compat.Lookup(globals, ""), nil, "an empty path")
    T.eq(Compat.Lookup(nil, "GetPetHappiness"), nil, "with no table")
end

T.suite("report: the list of guesses awaiting confirmation")

-- The list must name what the author asked to confirm by name: the raid
-- frame size table, the pet happiness functions and the aura layout
-- functions.
do
    local watch = Compat.Watchlist()
    T.ok(#watch >= 10, "the list is non-empty: " .. #watch)

    local byPath = {}
    for i = 1, #watch do
        byPath[watch[i].path] = watch[i]
        T.ok(type(watch[i].note) == "string" and watch[i].note ~= "",
            watch[i].path .. ": the note is written")
    end

    T.ok(byPath["DefaultCompactUnitFrameSetupOptions"] ~= nil,
        "the raid frame size table is named")
    T.ok(byPath["TargetFrame_UpdateAuras"] ~= nil,
        "the target aura layout is named")
    T.ok(byPath["CompactUnitFrame_UpdateAuras"] ~= nil,
        "the compact frame aura layout is named")

    -- The list is returned as a copy: it goes outward, into the report.
    watch[1].path = "spoiled"
    T.ok(Compat.Watchlist()[1].path ~= "spoiled", "a copy was handed out")
end

-- The pet function names used to lie in the feeding module as a second list
-- of the same names and were compared here with the core list. There is no
-- second list any more: the module names the layer groups, and the names
-- live in the groups. The same divergence is checked, only from the other
-- side: the group and the list must name the same paths. Diverging, they
-- would give a report answering about a name the module never asks for -- silence from the other side.

T.suite("report: assembly on a fake client")

-- A client with nothing in it. Every declared group must turn out to be
-- either a loss or "nothing to judge by" -- and none can turn out whole.
--
do
    local report = Report.Build("vanilla", {}, {})

    T.eq(report.counts.ok, 0, "in an empty client there is not a single whole group")
    T.ok(report.counts.missing > 0, "the losses are named: " .. report.counts.missing)
    T.ok(report.counts.unconfirmed > 0,
        "and so is \"nothing to judge by\": " .. report.counts.unconfirmed)
    T.ok(report.counts.absent > 0, "and the groups not meant for this client: "
        .. report.counts.absent)

    -- The focus cast bar in vanilla is that "deliberately empty": it never
    -- lands in the losses under any conditions.
    T.eq(report.groups["castbar-focus"], nil,
        "an undeclared group does not enter the group report")
    local absent = {}
    for i = 1, #report.absent do absent[report.absent[i].group] = true end
    T.eq(absent["castbar-focus"], true,
        "it lies in the \"does not exist for this client\" section")

    -- Unit frame auras: the game creates their icons only when the unit has
    -- auras. Such a group being empty on a fresh login is not a verdict.
    local auras = report.groups["unitframe-auras"]
    T.eq(auras.verdict, Report.UNCONFIRMED,
        "unit frame auras with no target are not condemned")
    T.ok(auras.later ~= nil, "and it says what to do so there is something to judge by")

    -- The game creates the unit frames at login, and emptiness here is our mistake.
    T.eq(report.groups["unitframe"].verdict, Report.MISSING,
        "the unit frames must exist on a fresh login")

    -- The sum of the verdicts matches the number of groups.
    local total = 0
    for _, count in pairs(report.counts) do total = total + count end
    T.eq(total, #report.order + report.counts.absent,
        "every group is counted exactly once")

    T.eq(report.watchFound, 0, "in an empty client not a single guess was confirmed")
    T.eq(report.watchTotal, #Compat.Watchlist(), "the list was walked in full")
end

-- A client that has some things. Here the main cross-cutting rule is
-- checked: "ok" is never issued for any zero of found names.
do
    local globals = {}
    local names = Compat.GetFrameNames("vanilla", "unitframe")
    for i = 1, #names do globals[names[i]] = { i } end
    globals.CastingBarFrame = {}
    globals.DefaultCompactUnitFrameSetupOptions = { width = 72 }
    globals.C_NamePlate = { GetNamePlateForUnit = function() end }

    local report = Report.Build("vanilla", globals, {
        build = "1.15.7 61457", interface = 11507,
        scale = 0.711, screen = "2560x1440", locale = "ruRU",
    })

    T.eq(report.groups["unitframe"].verdict, Report.OK,
        "every unit frame name is in place")
    T.eq(report.groups["unitframe"].found, #names, "and all of them are counted")

    local cast = report.groups["castbar-player"]
    T.eq(cast.verdict, Report.OK, "one spelling out of two is normal")
    T.eq(cast.found, 1, "one was found")
    T.eq(#cast.missingNames, 1, "the second is recorded as missing")

    T.eq(report.watchFound, 2, "two guesses were confirmed")

    -- The cross-cutting rule.
    local reassuring = {}
    for i = 1, #report.order do
        local entry = report.groups[report.order[i]]
        if entry.verdict == Report.OK and entry.found == 0 then
            reassuring[#reassuring + 1] = entry.group
        end
    end
    T.eq(#reassuring, 0, "a group that found nothing was called whole: "
        .. table.concat(reassuring, " | "))

    -- The client facts reach the report as they are.
    T.eq(report.interface, 11507, "the interface number is recorded")
    T.eq(report.screen, "2560x1440", "the resolution is recorded")
    T.eq(report.version, Report.VERSION, "the format version is recorded")

    -- A large empty group comes before a small one.
    T.ok(#report.worst >= 2, "there are several empty groups: " .. #report.worst)
    T.ok(report.worst[1].declared >= report.worst[2].declared,
        "the large loss is named first")
end

T.suite("report: the client facts")

-- Not a single game function exists outside the game, and the absence of any
-- of them may neither break anything nor invent a number.
do
    local facts = Report.ClientFacts({})
    T.eq(facts.build, nil, "there is nobody to ask for the build")
    T.eq(facts.interface, nil, "nor for the interface number")
    T.eq(facts.scale, nil, "nor for the scale")
    T.eq(facts.screen, nil, "nor for the resolution")

    T.eq(Report.ClientFacts(nil).build, nil, "and with no table at all")
end

do
    local parent = {
        GetEffectiveScale = function() return 0.7111111 end,
        GetWidth = function() return 1280 end,
        GetHeight = function() return 720 end,
    }
    local facts = Report.ClientFacts({
        GetBuildInfo = function() return "1.15.7", "61457", "date", 11507 end,
        UIParent = parent,
        GetLocale = function() return "ukUA" end,
    })
    T.eq(facts.build, "1.15.7 61457", "the version and the build together")
    T.eq(facts.interface, 11507, "the interface number as a number")
    T.eq(facts.scale, 0.711, "the scale is rounded to thousandths")
    T.eq(facts.screen, "1280x720", "without GetPhysicalScreenSize UIParent is used")
    T.eq(facts.locale, "ukUA", "the client language")

    -- A failing game function does not break the report.
    local broken = Report.ClientFacts({
        GetBuildInfo = function() error("no") end,
        GetLocale = function() error("no") end,
    })
    T.eq(broken.build, nil, "a failing GetBuildInfo stays silent rather than breaking")
    T.eq(broken.locale, nil, "and so does GetLocale")
end

T.suite("report: the chat lines")

ns.SetLocale("enUS")

do
    local report = Report.Build("vanilla", {}, { interface = 11507 })
    local lines = Report.Lines(report)

    T.ok(#lines >= 5, "there are few lines, but there are some: " .. #lines)
    T.ok(#lines <= 12, "and they are not dumped into chat by the hundred: " .. #lines)

    local text = table.concat(lines, "\n")
    T.ok(text:find("11507", 1, true) ~= nil, "the interface number is named")
    T.ok(text:find("vanilla", 1, true) ~= nil, "the flavour is named")
    T.ok(text:find("DarkenDB.global.report", 1, true) ~= nil,
        "it says where the full report lies")
    T.ok(text:find("run the report again", 1, true) ~= nil,
        "it mentions the groups there is nothing to judge by")

    -- Nothing goes unnamed: if there are more empty groups than the limit,
    -- the remainder is reported as a number.
    T.ok(text:find("and %d+ more groups") ~= nil,
        "the remainder of empty groups is named as a number")

    -- Exactly as many are named as are allowed.
    local named = 0
    for _ in text:gmatch("did nothing") do named = named + 1 end
    T.eq(named, 3, "three worst ones are named individually")

    T.eq(#Report.Lines(nil), 0, "with no report there are no lines")
end

-- A client where everything is in place must say so outright: otherwise the
-- author will look for a missing line and will not find it.
do
    local globals = {}
    local groups = Compat.Groups("vanilla")
    for i = 1, #groups do
        local names = Compat.GetFrameNames("vanilla", groups[i])
        for j = 1, #names do globals[names[j]] = {} end
    end

    local report = Report.Build("vanilla", globals, {})
    T.eq(report.counts.missing, 0, "there are no losses")
    T.eq(report.counts.unconfirmed, 0, "and no unjudged ones")

    local text = table.concat(Report.Lines(report), "\n")
    T.ok(text:find("resolved to something", 1, true) ~= nil,
        "it says that everything was found")
    T.eq(text:find("did nothing", 1, true), nil, "and nobody was blamed")
end

-- The subsystem labels are translated: the line is read by the player in chat.
do
    ns.SetLocale("ruRU")
    local report = Report.Build("vanilla", {}, {})
    local text = table.concat(Report.Lines(report), "\n")
    local C = require("cyrillic")
    T.eq(C.hasCyrillic(text), true, "the Russian client sees Russian lines")
    ns.SetLocale("enUS")
end

--============================================================================
-- The reassuring line: the only way to see it is for it to be true
--============================================================================
--
-- What this section is for. The line "every declared group found at least
-- something" is the only statement of the report that can be read as "there
-- is nowhere left to look". So it has exactly one rule: it is printed if and
-- only if no declared group was left without an answer -- neither empty, nor
-- partial, nor unjudged, nor degraded.
--
-- The former check asked about this line on a client where **every**
-- declared name exists, that is in the one state in which the line is true.
-- Here the states are gone through one by one.

T.suite("report: the reassuring line and the numbers that add up")

do
    -- A client where everything was found except the hook groups and the
    -- groups the game creates later. There are no losses at all
    -- (counts.missing == 0), and the former condition would print "everything was found" over fifteen empty groups.
    local globals = {}
    local groups = Compat.Groups("vanilla")
    for i = 1, #groups do
        local rule = Report.Consequence(groups[i])
        local skip = rule.kind == Report.HOOKS
            or (rule.later ~= nil and rule.later ~= "")
        if not skip then
            local names = Compat.GetFrameNames("vanilla", groups[i])
            for j = 1, #names do globals[names[j]] = {} end
        end
    end

    local report = Report.Build("vanilla", globals, {})
    T.eq(report.counts.missing, 0, "there are no empty-by-mistake ones")
    T.ok(report.counts.unconfirmed > 0,
        "but there are unjudged ones: " .. report.counts.unconfirmed)
    T.ok(report.counts.degraded > 0,
        "and degraded ones: " .. report.counts.degraded)

    local text = table.concat(Report.Lines(report), "\n")
    T.eq(text:find("resolved to something", 1, true), nil,
        "there is no reassuring line: fifteen groups answered with nothing")
end

do
    -- The same question from the other side: one partial group cancels the
    -- line too, and so does one degraded one.
    local function textFor(counts)
        return table.concat(Report.Lines({
            counts = counts, worst = {}, order = {}, groups = {},
        }), "\n")
    end

    T.ok(textFor({ ok = 10 }):find("resolved to something", 1, true) ~= nil,
        "all clean -- the line is printed")
    T.eq(textFor({ ok = 10, unconfirmed = 1 })
        :find("resolved to something", 1, true), nil,
        "one unjudged one cancels the line")
    T.eq(textFor({ ok = 10, degraded = 1 })
        :find("resolved to something", 1, true), nil,
        "one degraded one cancels the line")
    T.eq(textFor({ ok = 10, partial = 1 })
        :find("resolved to something", 1, true), nil,
        "one partial one cancels the line")
end

do
    -- And the order: the reassurance stands after the caveats, not above
    -- them. People read the first lines, and "all is well" above "nine groups
    -- cannot be checked" is exactly the lie this file was written against.
    local lines = Report.Lines({
        counts = { ok = 10 }, worst = {}, order = {}, groups = {},
    })
    local calm, guessed
    for i = 1, #lines do
        if lines[i]:find("resolved to something", 1, true) then calm = i end
        if lines[i]:find("guessed names", 1, true) then guessed = i end
    end
    T.ok(calm ~= nil, "the line was found")
    T.ok(calm ~= nil and guessed ~= nil and calm == guessed - 1,
        "and it stands last among the group lines -- where the caveats "
        .. "are printed, not above them")
end

do
    -- The numbers must add up: the sum of the verdicts named in the line
    -- equals the number of groups declared for this client. Otherwise the
    -- author adds them up, gets less, and stops trusting the line entirely.
    local report = Report.Build("vanilla", {}, {})

    -- The line is found by content rather than by index: the index changes
    -- with any line inserted above, and the verdict-count check would go red
    -- on the build stamp, which has nothing to do with the numbers.
    local line
    for _, text in ipairs(Report.Lines(report)) do
        if text:find("frame groups:", 1, true) then line = text end
    end
    T.ok(line ~= nil, "the line about the group verdicts was found")

    local numbers = {}
    for n in line:gmatch("%d+") do numbers[#numbers + 1] = tonumber(n) end
    T.eq(#numbers, 6, "the line holds six numbers: five verdicts and absent")

    local declared = #Compat.Groups("vanilla")
    local sum = 0
    for i = 1, 5 do sum = sum + numbers[i] end
    T.eq(sum, declared,
        "the verdicts add up to the number of declared groups: " .. declared)
    T.eq(numbers[6], report.counts.absent, "the last number is absent")
end


T.suite("report: variants of one thing under one label are judged together")

-- "Whose kill is this" is asked by three different functions, and every
-- client has one of them: the modern one calls UnitIsTapDenied, the classic
-- one UnitIsTapped and UnitIsTappedByPlayer. Judged apart, the two not found
-- land in "missing", and the report twice calls missing something that
-- works: all three share one label.
--
-- The author sent exactly that and asked what was broken. Nothing was broken
-- -- the report was noisy.
do
    local globals = { UnitIsTapDenied = function() return false end }

    local built = Report.Build("vanilla", globals, {})

    local denied = built.groups["unit-tap-denied"]
    local tapped = built.groups["unit-tapped"]
    local byMe   = built.groups["unit-tapped-by-me"]

    T.ok(denied ~= nil, "the variant the client has is in the report")
    T.ok(tapped ~= nil and byMe ~= nil, "and so are the ones it does not have")

    if denied and tapped and byMe then
        T.eq(denied.verdict, ns.Report.OK, "the found variant is fine")
        T.ok(tapped.verdict ~= ns.Report.MISSING,
            "the one not found is not called a loss: there is a replacement")
        T.ok(byMe.verdict ~= ns.Report.MISSING, "and neither is the second")

        -- The list of names not found stays with them: the name still does
        -- not exist in the client, and there is no reason to hide that. Only the verdict changes.
        T.ok(#tapped.missingNames > 0, "the name not found is named as before")

        -- And they are not in the "worst": what lands there is what needs fixing.
        for _, bad in ipairs(built.worst) do
            T.ok(bad.label ~= denied.label,
                "nothing from this label landed in the worst")
        end
    end
end
