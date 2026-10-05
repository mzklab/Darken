local helpers = require("helpers")

-- The build stamp in the report: what it was built with and when.
--
-- Why the check exists. The author entered the game and left; the saved
-- variables file was rewritten with a fresh timestamp while the report inside
-- stayed as it was — the game reads an addon's code only at login and on
-- /reload. Nothing said so, and it could only be worked out by the fields the
-- former build did not write. The file's timestamp proves the game wrote
-- something; what the contents were written by it does not prove.
--
-- Hence the composition of the checks. Each answers one question: is it said
-- what the report was built with; is a time invented where there is no clock;
-- and — most importantly — does the addon say aloud that the answer that lay on the disk was not built by it.

T.suite("The build stamp: four facts and not one invented")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Locale/ruRU.lua", ns)
helpers.loadAddonFile("Locale/ukUA.lua", ns)
helpers.loadAddonFile("Core/Report.lua", ns)

local Report = ns.Report

ns.SetLocale("enUS")

-- A client in which there is nobody to ask. Not one nil and not one number
-- out of thin air: a field absent from the record reads off the disk as "they
-- forgot to write it", while an invented number is worse than one absent entirely.
do
    local stamp = Report.Stamp({})
    T.eq(stamp.addon, Report.UNKNOWN, "the addon's version is unknown, said in a word")
    T.eq(stamp.api, Report.UNKNOWN, "and so is the contract's version")
    T.eq(stamp.settings, Report.UNKNOWN, "and so is the settings schema's version")
    T.eq(stamp.when, Report.UNKNOWN, "and so is the time")

    T.eq(Report.Stamp(nil).when, Report.UNKNOWN, "and with no dictionary at all")
end

-- A client where everything was asked. The addon's version goes through the
-- same door as the modules' (Api:GetVersion) rather than by a second read of the TOC.
do
    ns.Api = { GetVersion = function() return "0.9.0" end, API_VERSION = 19 }
    ns.DB_VERSION = 9

    local stamp = Report.Stamp({
        date = function(format) return "2026-09-26 19:41:02" end,
    })
    T.eq(stamp.addon, "0.9.0", "the addon's version out of the TOC")
    T.eq(stamp.api, 19, "the contract's version as a number")
    T.eq(stamp.settings, 9, "the settings schema's version as a number")
    T.eq(stamp.when, "2026-09-26 19:41:02", "the time by the local clock")
end

-- The time is written year first: two stamps are compared as strings, with no
-- parsing. What is checked is the pattern handed to the clock rather than our
-- opinion of it.
do
    local asked
    Report.Stamp({ date = function(format) asked = format; return "x" end })
    T.eq(asked, "%Y-%m-%d %H:%M:%S", "the year, the month, the day, then the clock")
end

T.suite("The build stamp: there may be no clock")

-- A client whose clock exists and falls over, and a client that has none at
-- all. Neither has the right either to bring the report down or to get a number.
do
    local broken = Report.Stamp({ date = function() error("no") end })
    T.eq(broken.when, Report.UNKNOWN, "a clock that fell over stays silent rather than bringing things down")
    T.eq(broken.addon, "0.9.0", "and does not spoil the rest of the stamp")

    local wrongType = Report.Stamp({ date = 5 })
    T.eq(wrongType.when, Report.UNKNOWN, "not a function is unknown too")

    local empty = Report.Stamp({ date = function() return "" end })
    T.eq(empty.when, Report.UNKNOWN, "an empty string is not an answer")

    local number = Report.Stamp({ date = function() return 1790000000 end })
    T.eq(number.when, Report.UNKNOWN, "a number instead of a string is not recorded")
end

T.suite("The build stamp: it lies in the record")

do
    local report = Report.Build("vanilla", {
        date = function() return "2026-09-26 19:41:02" end,
    }, {})

    T.eq(type(report.stamp), "table", "the stamp's section is in the record")
    T.eq(report.stamp.addon, "0.9.0", "and names the build")
    T.eq(report.stamp.when, "2026-09-26 19:41:02", "and the time")

    -- The record's shape changed, and the format's number is obliged to say
    -- so: the report is read off the disk and not only by eye.
    T.ok(Report.VERSION >= 2, "the format's version was raised: " .. Report.VERSION)
    T.eq(report.version, Report.VERSION, "and recorded")
end

T.suite("The build stamp: the reverse check")

-- What all of this is written for: the report that lay on the disk was built
-- by a build other than the one running now.
do
    T.eq(Report.Outdated(nil, "0.9.0"), nil, "there is no previous one, so we stay silent")
    T.eq(Report.Outdated("not a table", "0.9.0"), nil, "rubbish, and we stay silent too")
    T.eq(Report.Outdated({ stamp = { addon = "0.9.0" } }, "0.9.0"), nil,
        "the same build is no news")

    T.eq(Report.Outdated({ stamp = { addon = "0.8.0" } }, "0.9.0"), "0.8.0",
        "a different build is named")

    -- A report of the former shape has no stamp at all. That is not "the same
    -- build": it is "the build is unknown", and staying silent here would mean reassuring.
    T.eq(Report.Outdated({ counts = {} }, "0.9.0"), Report.UNKNOWN,
        "a record with no stamp is an unknown build rather than our own")

    -- Two unknowns are not a discrepancy but two silences.
    T.eq(Report.Outdated({ counts = {} }, nil), nil,
        "unknown against unknown leaves nothing to say")
end

T.suite("The build stamp: the lines for the chat")

do
    local globals = { date = function() return "2026-09-26 19:41:02" end }
    local report = Report.Build("vanilla", globals, {})

    -- The first line says what answered. It is precisely that one that was missing last time.
    local first = Report.Lines(report)[1]
    T.ok(first:find("0.9.0", 1, true) ~= nil, "the build is named: " .. first)
    T.ok(first:find("19", 1, true) ~= nil, "the contract is named")
    T.ok(first:find("2026-09-26 19:41:02", 1, true) ~= nil, "and the time")

    -- With no previous report there is no line about it: a fresh install
    -- changes nothing.
    local fresh = table.concat(Report.Lines(report), "\n")
    T.eq(fresh:find("out of date", 1, true), nil,
        "there is no previous one, so there is no line")

    -- A report built by one build and read with another one running.
    local previous = { stamp = { addon = "0.8.0" } }
    local lines = Report.Lines(report, nil, previous)
    local text = table.concat(lines, "\n")
    T.ok(text:find("0.8.0", 1, true) ~= nil, "the former build is named")
    T.ok(text:find("out of date", 1, true) ~= nil, "and named as out of date")
    T.ok(text:find("/reload", 1, true) ~= nil,
        "and it is said what picks the new code up")
    T.eq(lines[2]:find("out of date", 1, true) ~= nil, true,
        "the line stands right after the stamp: the first lines are what gets read")

    -- The same build, and there is no line.
    local same = table.concat(
        Report.Lines(report, nil, { stamp = { addon = "0.9.0" } }), "\n")
    T.eq(same:find("out of date", 1, true), nil,
        "the build is the same, so there is nothing to alarm with")

    -- A client with no clock is left with a report rather than without one.
    local blind = Report.Build("vanilla", {}, {})
    local blindText = table.concat(Report.Lines(blind), "\n")
    T.ok(blindText:find(Report.UNKNOWN, 1, true) ~= nil,
        "the time is unknown, and so it is said")
    T.ok(blindText:find("DarkenDB.global.report", 1, true) ~= nil,
        "and the rest of the report is in place")
end

-- Both shipped locales print both lines, and print them with their own
-- numbers: a format string that lost its %s would leave the author without an
-- answer in the same place he lost it.
do
    for _, locale in ipairs({ "ruRU", "ukUA" }) do
        ns.SetLocale(locale)

        local report = Report.Build("vanilla", {
            date = function() return "2026-09-26 19:41:02" end,
        }, {})
        local text = table.concat(
            Report.Lines(report, nil, { stamp = { addon = "0.8.0" } }), "\n")

        T.ok(text:find("0.9.0", 1, true) ~= nil,
            locale .. ": the current build is named")
        T.ok(text:find("0.8.0", 1, true) ~= nil,
            locale .. ": the former build is named")
        T.ok(text:find("/reload", 1, true) ~= nil,
            locale .. ": /reload is mentioned")
    end

    ns.SetLocale("enUS")
end
