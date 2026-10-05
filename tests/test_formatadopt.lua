local helpers = require("helpers")

-- Adoption of the core number formatting: no copies are left anywhere.
--
-- The fifth consolidation of the project is finished. The core hands out one
-- number formatting (Darken:GetFormat(), contract version 12,
-- Core/Format.lua), and everyone who wrote a large number or computed a percentage calls it.
--
-- There were four places, not two:
--
--   Modules/Texts.lua      -- Texts.Abbreviate and Texts.Percent;
--   Features/InfoPanel/Format.lua -- Format.Short and Format.Ratio.
--
-- The panel abbreviation (Format.Short) was not named in the analysis at
-- all: the two named functions computed percentages, while the third copy --
-- the hidden one -- wrote large numbers. It was found the same way
-- everything in this suite is found: by scanning the sources for the marks
-- of the rule (thresholds, format strings, the rounding expression), not by reading a list.
--
-- Three things are checked here, and their order is not accidental:
--
--   1. IDENTITY of the functions, not agreement of their answers. Copies
--      give identical answers too -- right up to the day one of the two is edited.
--   2. NO COPIES ARE LEFT: the marks of the rule are searched for across all
--      subsystem and module files and are not found; separately it is checked
--      that they ARE in the core -- a scan that finds nothing anywhere is
--      green even when it has forgotten how to search.
--   3. THE BOUNDARIES, as strings rather than intermediate numbers: zero,
--      the neighbours of a thousand and a million, round thousands, one
--      decimal place, and both negative cases the two old functions handled differently.

T.suite("number formatting adoption: no copies are left")

--============================================================================
-- Namespaces: the core, the bar subsystem, the panel module
--============================================================================

-- The Darken global for the duration of this file. The outward door is
-- opened by the real Core/Api.lua below (which creates the global); here we
-- only remember what stood before us: the next file of the suite must not see our core.
local _, restoreDoor = helpers.installFormat()

local core = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", core)
helpers.loadAddonFile("Core/Registry.lua", core)
helpers.loadAddonFile("Core/Locale.lua", core)
helpers.loadAddonFile("Core/Events.lua", core)
helpers.loadAddonFile("Core/Combat.lua", core)
helpers.loadAddonFile("Core/Skin.lua", core)
helpers.loadAddonFile("Core/Frames.lua", core)
helpers.loadAddonFile("Core/Api.lua", core)
helpers.loadAddonFile("Core/Format.lua", core)

-- The font subsystem calls LibSharedMedia while the file is read, and the
-- unit frames are needed by the texts for the deferral queue. There is no library outside the game.
local savedLibStub = LibStub
LibStub = function() return nil end
helpers.loadAddonFile("Modules/Fonts.lua", core)
helpers.loadAddonFile("Modules/UnitFrames.lua", core)
helpers.loadAddonFile("Modules/Texts.lua", core)
LibStub = savedLibStub

local panel = helpers.newNamespace()
helpers.loadAddonFile("Features/InfoPanel/Format.lua", panel)

local Texts = core.Texts
local Cells = panel.Format

--============================================================================
-- 1. Identity: one function, not four identical ones
--============================================================================

do
    local door = core.Api:GetFormat()

    T.eq(door, core.Format, "the door hands out the same table as the core file")

    -- The bar labels. This is the same addon, so the table is taken directly
    -- (ns.Format) rather than through the global -- but the function must be the very same one.
    T.eq(Texts.Abbreviate, core.Format.Abbreviate,
        "the bar abbreviation is the core function, not a copy")
    T.eq(Texts.Percent, core.Format.Percent,
        "the bar percentage is the core function, not a copy")
    T.eq(Texts.Abbreviate, door.Abbreviate,
        "and the very one the outward door hands out")
    T.eq(Texts.Percent, door.Percent, "the same for the percentage")

    -- The info panel is a separate addon, and it reaches the core only
    -- through the door. Its own name (Format.Numbers) exists precisely so
    -- that identity can be checked rather than inferred from matching answers.
    T.eq(type(Cells.Numbers), "table", "the panel named the core formatting outwardly")
    T.eq(Cells.Numbers, core.Format,
        "the panel holds the very table the core door handed out")
    T.eq(Cells.Numbers, door,
        "and that is exactly what Darken:GetFormat() returns")
    T.eq(Cells.Numbers.Abbreviate, core.Format.Abbreviate,
        "the panel abbreviation is the core function")
    T.eq(Cells.Numbers.Percent, core.Format.Percent,
        "the panel percentage is the core function")

    -- Short and Ratio, however, cannot and must not be identities: beyond the
    -- core rule the panel has two decisions of its own about its own cell
    -- (input filtering and clamping to zero). What is checked is that these
    -- are wrappers and not second bodies -- by the scan below and the behaviour below.
    T.ok(Cells.Short ~= core.Format.Abbreviate,
        "Short does not pass itself off as the core function: it has its own decision about input")
    T.ok(Cells.Ratio ~= core.Format.Percent,
        "Ratio likewise: clamping to zero is the panel's decision")
end

--============================================================================
-- 2. No copies are left: a source scan for the marks of the rule
--============================================================================
--
-- The file lists are taken from the TOCs -- the core one and every module
-- one -- rather than written here: a file created tomorrow must come under the scan by itself.

do
    --- The core subsystem and settings files listed in Darken.toc.
    -- @return table an array of paths
    local function coreOwnFiles()
        local handle = io.open("Darken.toc", "r")
        if not handle then error("could not open Darken.toc", 2) end

        local out = {}
        for line in handle:lines() do
            local rel = line:match("^%s*((Modules[\\/][%w_]+%.lua))%s*$")
                or line:match("^%s*((Config[\\/][%w_]+%.lua))%s*$")
                or line:match("^%s*((Skin[\\/][%w_]+%.lua))%s*$")
            if rel then out[#out + 1] = (rel:gsub("\\", "/")) end
        end
        handle:close()

        if #out == 0 then
            error("Darken.toc lists not a single subsystem file", 2)
        end
        return out
    end

    --- The whole text of a file.
    -- @param path string
    -- @return string
    local function textOf(path)
        local handle = io.open(path, "r")
        if not handle then error("could not open " .. path, 2) end
        local text = handle:read("*a")
        handle:close()
        return text
    end

    local scanned = {}
    local files = coreOwnFiles()
    for i = 1, #files do
        scanned[#scanned + 1] = { path = files[i], text = textOf(files[i]) }
    end

    local folders = helpers.moduleFolders()
    T.ok(#folders >= 5, "the module folders were found: " .. #folders)
    for i = 1, #folders do
        local sources = helpers.moduleSources(folders[i])
        for j = 1, #sources do
            scanned[#scanned + 1] =
                { path = sources[j], text = textOf(sources[j]) }
        end
    end

    T.ok(#scanned >= 40, "sources under the scan: " .. #scanned)

    -- The marks of the rule. Each is something without which a second
    -- formatting cannot be made: a threshold, a unit, a format string, the division by a hundred itself.
    local MARKS = {
        "999500",       -- the million threshold corrected for rounding
        "1000000",      -- the million divisor
        "MILLION",      -- the name the divisor stood under
        "THOUSAND",     -- and the name of the thousand threshold
        "%.1fk",        -- the thousands format string
        "%.1fm",        -- and the millions one
        "* 100",        -- a fraction turned into percent
    }

    for m = 1, #MARKS do
        local mark = MARKS[m]
        local found = {}
        for i = 1, #scanned do
            if scanned[i].text:find(mark, 1, true) then
                found[#found + 1] = scanned[i].path
            end
        end
        T.eq(#found, 0, "the number-formatting mark \"" .. mark
            .. "\" does not occur outside the core: " .. table.concat(found, " | "))
    end

    -- A scan that finds nothing anywhere is green even when it has forgotten
    -- how to search. So the same marks are searched for where they belong, and must be found.
    local coreText = textOf("Core/Format.lua")
    local present = 0
    for m = 1, #MARKS do
        if coreText:find(MARKS[m], 1, true) then present = present + 1 end
    end
    T.eq(present, #MARKS,
        "in Core/Format.lua every mark is in place -- the scan can search")

    -- Symmetric rounding. Formerly this said "the panel kept exactly one of
    -- them": the body lived in the module, because a plain "round to an
    -- integer" was not on the contract surface. Version 13 named it
    -- (Darken:GetFormat().Round), and the last body moved into the core --
    -- the panel has no rounding of its own at all, and that shows in the count.
    --
    -- The count is deliberately case-insensitive: a copy created anew would
    -- be called Round no less often than round.
    local panelText = textOf("Features/InfoPanel/Format.lua")
    local own = 0
    for _ in panelText:gmatch("local%s+function%s+[Rr]ound") do own = own + 1 end
    for _ in panelText:gmatch("local%s+[Rr]ound%s*=") do own = own + 1 end
    T.eq(own, 0, "not a single rounding of its own is left in the panel")
    T.ok(panelText:find("fmt.Round(fps)", 1, true) ~= nil,
        "the frame rate is rounded by the core")

    -- The other side of the same: both panel functions call the core by name.
    T.ok(panelText:find("fmt.Abbreviate(value)", 1, true) ~= nil,
        "Short calls the core abbreviation")
    T.ok(panelText:find("fmt.Percent(current, maximum)", 1, true) ~= nil,
        "Ratio calls the core percentage")
end

--============================================================================
-- 3. The boundaries: the strings the player will see are compared
--============================================================================
--
-- "Nothing changes" is checked where such an edit actually breaks: at the
-- thresholds, on round thousands, on one decimal place and at zero.

do
    -- Pairs of "value -- what is written". The values are taken at the edges,
    -- not in the middles: thresholds break one unit away from themselves.
    local CASES = {
        { 0,       "0" },
        { 1,       "1" },
        { 42,      "42" },
        { 999,     "999" },       -- the last number below the threshold
        { 1000,    "1.0k" },      -- exactly the threshold
        { 1001,    "1.0k" },
        { 1500,    "1.5k" },      -- one decimal place
        { 2000,    "2.0k" },      -- a round thousand is written with the zero, not as "2k"
        { 9999,    "10.0k" },
        { 10000,   "10.0k" },
        { 12437,   "12.4k" },     -- the very number from the analysis
        { 15000,   "15.0k" },
        { 999499,  "999.5k" },    -- the last number below the million threshold
        { 999500,  "1.0m" },      -- exactly the threshold, and it is not a million
        { 999999,  "1.0m" },      -- "1000.0k" is never written
        { 1000000, "1.0m" },      -- exactly a million
        { 2500000, "2.5m" },
        { -1500,   "-1.5k" },     -- the sign in front, not lost
        { -999999, "-1.0m" },
    }

    for i = 1, #CASES do
        local value, want = CASES[i][1], CASES[i][2]
        T.eq(Texts.Abbreviate(value), want,
            "the bar writes " .. tostring(value) .. " as \"" .. want .. "\"")
        T.eq(Cells.Short(value), want,
            "and the panel cell uses the same letters")
    end

    -- "1000.0k" is written for no value in the band around the threshold:
    -- that is the very failure the million threshold is not a million for.
    local wrong = 0
    for value = 999000, 1000000 do
        if Texts.Abbreviate(value):find("1000.0k", 1, true) then
            wrong = wrong + 1
        end
    end
    T.eq(wrong, 0, "\"1000.0k\" is written for no value near the threshold")

    -- The whole bar label -- what the player reads, not an intermediate
    -- number. Three formats, with abbreviation on and off.
    T.eq(Texts.FormatValue(12437, 25000, "value", true), "12.4k/25.0k",
        "the \"number\" format with abbreviation")
    T.eq(Texts.FormatValue(12437, 25000, "value", false), "12437/25000",
        "and without abbreviation")
    T.eq(Texts.FormatValue(12437, 25000, "percent", false), "50%",
        "the \"percent\" format")
    T.eq(Texts.FormatValue(12437, 25000, "both", true), "12.4k/25.0k 50%",
        "the \"number and percent\" format")
    T.eq(Texts.FormatValue(0, 0, "percent", false), "0%",
        "a zero maximum gives zero percent, not a division by zero")
    T.eq(Texts.FormatValue(0, 100, "value", true), "0/100",
        "zero is written as zero, not as a dash")

    -- The whole panel cell.
    T.eq(Cells.Percent(12437, 25000), "50%", "cell: a half")
    T.eq(Cells.Percent(1, 0), Cells.NONE, "cell: nothing to divide by -- a dash")
    T.eq(Cells.Experience(12437, 25000, nil, "current"), "12.4k/25.0k",
        "the experience cell: the same letters as on the bar")
    T.eq(Cells.Experience(12437, 25000, nil, "percent"), "50%",
        "the experience cell as a percentage")
    T.eq(Cells.Experience(12437, 25000, nil, "remaining"), "12.6k",
        "the experience cell as a remainder")
    T.eq(Cells.Reputation("Argent Dawn", "Friendly", 2100, 6000, "current"),
        "Argent Dawn: 2.1k/6.0k", "the reputation cell")

    -- The frame rate did not drift with the rounding: it has its own and it
    -- stayed exactly the same.
    T.eq(Cells.Fps(59.6), "60 fps", "frames are rounded, not truncated")
    T.eq(Cells.Fps(59.4), "59 fps", "and downwards too")
end

--============================================================================
-- 4. Input: what each side counts as a number
--============================================================================
--
-- One of the two old functions accepted the string "50", the other rejected
-- it strictly. The move has no right to loosen or tighten what reaches the
-- game, so input filtering stayed the decision of each side and is checked
-- directly.

do
    -- The bar used tonumber and still does: the value comes from the game,
    -- and a numeric string from there is the same number.
    T.eq(Texts.Abbreviate("1500"), "1.5k", "bar: a numeric string is a number")
    T.eq(Texts.Percent("50", "200"), 25, "and in the percentage too")
    T.eq(Texts.Abbreviate(nil), nil, "bar: nothing to abbreviate -- nil")
    T.eq(Texts.Abbreviate("garbage"), nil, "garbage is nil too")
    T.eq(Texts.Percent(nil, nil), 0, "bar: a non-number counts as zero")
    T.eq(Texts.Number("1500", true), "1.5k", "label: a string reaches the number")
    T.eq(Texts.Number(nil, true), "0", "while nothing to write means zero")

    -- The label without abbreviation: the same path the core takes below a
    -- thousand, and it is checked on the values where truncation differs from
    -- rounding and a sign differs from its absence. Formerly a second body of
    -- the rule stood here and no check called it: both live call sites passed
    -- abbreviate = true and went into the core without looking here.
    T.eq(Texts.Number(12437, false), "12437", "without abbreviation, every digit")
    T.eq(Texts.Number(999.9, false), "999", "the fraction is truncated towards zero")
    T.eq(Texts.Number(-999.9, false), "-999", "and with a minus it truncates the same way")
    T.eq(Texts.Number(-0.5, false), "-0", "the sign lives outside \"%d\" and is not lost")
    T.eq(Texts.Number(0, false), "0", "zero stays zero")
    T.eq(Texts.Number("1500", false), "1500", "a numeric string is a number")
    T.eq(Texts.Number(nil, false), "0", "nothing to write means zero")

    -- And this is one body, not two matching ones. What is compared is not
    -- the answer but the rule: below a thousand the abbreviation writes
    -- exactly the same, and these two answers cannot diverge because there is nobody to write them apart.
    local apart = {}
    local SAMPLES = { 0, 1, -1, 0.5, -0.5, 12.9, -12.9, 999, 999.9, -999.9 }
    for i = 1, #SAMPLES do
        local n = SAMPLES[i]
        if Texts.Number(n, false) ~= Texts.Abbreviate(n) then
            apart[#apart + 1] = tostring(n)
        end
    end
    T.eq(#apart, 0, "below a thousand both switches give one answer: "
        .. table.concat(apart, " | "))

    -- The panel rejected and still rejects everything that is not a number:
    -- the cell value comes from a foreign metric, and a string from there means a foreign mistake.
    T.eq(Cells.Short("1500"), Cells.NONE, "panel: a numeric string gives a dash")
    T.eq(Cells.Short(nil), Cells.NONE, "no number means a dash")
    T.eq(Cells.Short(0 / 0), Cells.NONE, "NaN gives a dash")
    T.eq(Cells.Short(math.huge), Cells.NONE, "infinity gives a dash")
    T.eq(Cells.Ratio("50", 100), nil, "panel: a string does not count as a number")
    T.eq(Cells.Ratio(nil, 100), nil, "a non-number gives nil")
    T.eq(Cells.Ratio(50, 0), nil, "a zero maximum gives nil, not zero")
    T.eq(Cells.Ratio(50, -1), nil, "a negative maximum gives nil too")

    -- The difference in answering "there is nothing to count from" also
    -- stayed each side's own: zero on a bar is a value, a dash in a cell is missing data.
    T.eq(Texts.Percent(50, 0), 0, "bar: a zero maximum gives zero")
    T.eq(Cells.Ratio(50, 0), nil, "panel: the same case gives nil")
end

--============================================================================
-- 5. Negatives: the clamping stayed with the panel, and only with it
--============================================================================

do
    -- The core does not clamp: a negative percentage means somebody computed
    -- the wrong thing, and replacing it with zero means hiding their mistake.
    T.eq(Texts.Percent(-1, 8), -13, "bar: the minus is visible, truncated towards zero")
    T.eq(Texts.Percent(-1, 8), -Texts.Percent(1, 8),
        "and Percent(-x) equals minus Percent(x)")
    T.eq(Texts.FormatValue(-1, 8, "percent", false), "-13%",
        "and on screen it is a minus as well")

    -- The panel clamps, and that is written at the place of the decision, not in the number formatting.
    T.eq(Cells.Ratio(-1, 8), 0, "panel: a negative percentage is clamped to zero")
    T.eq(Cells.Ratio(-1, 1000000), 0, "and an arbitrarily small minus gives zero")
    T.eq(Cells.Percent(-1, 8), "0%", "in the cell that is \"0%\"")

    -- The abbreviation, however, returns a negative number with its minus on
    -- both sides: the clamping belongs to the cell percentage, not to the whole file.
    T.eq(Cells.Short(-1500), "-1.5k", "cell: the minus on the abbreviation stayed")
    T.eq(Texts.Abbreviate(-1500), "-1.5k", "and on the bar too")
end

restoreDoor()
