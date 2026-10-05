local helpers = require("helpers")

-- Numbers, the label inset from the edge and one rule per texture name --
-- contract version 12.
--
-- The defect this suite was written for. The player reads numbers more often
-- than anything else on screen, yet the contract did not hand out the number
-- formatting rules at all: GetSkin handed out colour and inset, GetMedia
-- texture and font, GetCasefold case. So the abbreviation of a large number
-- was written twice -- by the bar labels and by the info panel cells -- and
-- diverged: "12.4k" against "12k", "1.0m" against "1000.0k". The world
-- family analysis could only reconcile that with a copy: a module in a
-- separate folder has no other way.
--
-- So what is checked here is not "the functions exist" but properties of the surface:
--
--   * the door leads to the very core function rather than to a lookalike
--     beside it -- and that is checked by identity rather than by comparing
--     answers: copies give identical answers until someone edits them;
--   * not a single copy of the rule is left in the core -- the thresholds
--     are searched for across every core file listed in the TOC;
--   * the rounding is symmetric about zero, that is the same magnitude with
--     the other sign is computed the same way;
--   * one rule resolves a texture name, and its answer is the same even
--     when LibSharedMedia is not installed.

--- The core as the public layer sees it.
local function core()
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Skin/Draw.lua", ns)
    helpers.loadAddonFile("Core/Frames.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Combat.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/Format.lua", ns)
    helpers.loadAddonFile("Core/Media.lua", ns)
    helpers.loadAddonFile("Core/Api.lua", ns)

    local said = {}
    ns.Registry.report = function(text) said[#said + 1] = text end
    ns.Addon = {
        db = { profile = {}, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }

    return ns, said
end

--- Read a whole file.
local function read(path)
    local file = io.open(path, "r")
    if not file then error("could not open " .. path, 2) end
    local text = file:read("*a")
    file:close()
    return text
end

--- The core files listed in Darken.toc.
-- The list is taken from the same file the game loads them by: rewritten
-- into the check it would fall behind silently, and a file created tomorrow
-- would not come under the copy search at all.
-- @return table an array of paths with forward slashes
local function coreFiles()
    local list = {}
    for line in read("Darken.toc"):gmatch("[^\r\n]+") do
        local path = line:match("^%s*(Core[\\/][%w_]+%.lua)%s*$")
        if path then list[#list + 1] = (path:gsub("\\", "/")) end
    end
    if #list == 0 then
        error("Darken.toc lists not a single core file", 2)
    end
    return list
end

T.suite("the numbers are visible from the contract")

do
    local ns = core()
    local fmt = ns.Api:GetFormat()

    T.eq(type(fmt), "table", "the door is open")

    -- A snapshot of the surface: a name added by accident will demand a
    -- deliberate decision. Every one here is a promise forever.
    local surface = {}
    for key, value in pairs(fmt) do
        surface[#surface + 1] = key .. ":" .. type(value)
    end
    table.sort(surface)
    T.eq(table.concat(surface, ","),
        "Abbreviate:function,Percent:function,Round:function",
        "the number surface: " .. table.concat(surface, ","))

    T.ok(ns.Api.API_VERSION >= 12, "the numbers were handed out by version twelve")
    T.eq(ns.Api:Supports(12), true, "version twelve is supported")
    T.eq(ns.Api.API_MIN_VERSION, 1, "while the lower bound stayed at one")
end

T.suite("the door leads to the core rule, not to a copy of it")

-- The main property of the whole suite, and it is checked by identity.
-- Comparing answers will not do here: a copy answers the same right up to
-- the day one of the two is edited -- and the world family analysis showed
-- that this is exactly how they get edited.
do
    local ns = core()

    T.eq(ns.Api:GetFormat(), ns.Format,
        "what goes outward is the same table the core uses")
    T.eq(ns.Api:GetFormat().Abbreviate, ns.Format.Abbreviate,
        "the abbreviation is the same function")
    T.eq(ns.Api:GetFormat().Percent, ns.Format.Percent,
        "the percentage is the same function")
    T.eq(ns.Api:GetFormat(), ns.Api:GetFormat(), "the door is one and the same")
end

T.suite("no copies of the rule are left in the core")

-- The thresholds are exactly what diverged. They are searched for across
-- every core file from the TOC: a magnitude written in a second place will
-- diverge from the first silently, and nothing but the player's eyes will notice.
do
    local owner = "Core/Format.lua"
    local MARKS = { "999500", "%.1fk", "%.1fm" }

    for _, path in ipairs(coreFiles()) do
        if path ~= owner then
            local text = read(path)
            for i = 1, #MARKS do
                T.eq(text:find(MARKS[i], 1, true), nil,
                    "the abbreviation threshold is written only in " .. owner
                    .. ", yet was found in " .. path .. ": " .. MARKS[i])
            end
        end
    end

    -- And the owner does hold them after all: a check that finds nothing
    -- anywhere is green even when it has forgotten how to search.
    local mine = read(owner)
    for i = 1, #MARKS do
        T.ok(mine:find(MARKS[i], 1, true) ~= nil,
            "the rule lives in " .. owner .. ": " .. MARKS[i])
    end
end

T.suite("abbreviating a large number")

-- The rule of the health bar label was taken letter for letter: that is the
-- one the player sees every fight. The boundaries are checked from both
-- sides -- that is where rounding mistakes live.
do
    local abbr = core().Api:GetFormat().Abbreviate

    local CASES = {
        { 0,        "0"      },
        { 1,        "1"      },
        { 9,        "9"      },
        { 999,      "999"    },
        -- Below a thousand the fraction is truncated towards zero rather than
        -- rounded: that is how the bar label wrote it. There are no live
        -- fractional magnitudes here, and this case is reachable only by a direct call.
        { 999.9,    "999"    },
        { 0.9,      "0"      },
        { 1000,     "1.0k"   },
        { 1001,     "1.0k"   },
        { 1100,     "1.1k"   },
        { 9999,     "10.0k"  },
        -- Exactly the case the two rules diverged on: the info panel cell
        -- wrote "10k", the bar "10.0k".
        { 10000,    "10.0k"  },
        { 12437,    "12.4k"  },
        { 15000,    "15.0k"  },
        { 999499,   "999.5k" },
        { 999500,   "1.0m"   },
        -- And the second: the panel wrote "1000.0k" -- the same number as
        -- "1.0m", three characters longer and in units it no longer has.
        { 999999,   "1.0m"   },
        { 1000000,  "1.0m"   },
        { 1049999,  "1.0m"   },
        { 1234567,  "1.2m"   },
        { 12345678, "12.3m"  },
    }

    for i = 1, #CASES do
        local value, want = CASES[i][1], CASES[i][2]
        T.eq(abbr(value), want, "abbreviation " .. value .. " -> " .. want)
    end

    -- The sign is a factor, not a separate rule. The symmetry is checked on
    -- all the same magnitudes at once: a rule written for one side diverges
    -- from the other on the very first edit.
    for i = 1, #CASES do
        local value = CASES[i][1]
        if value > 0 then
            T.eq(abbr(-value), "-" .. CASES[i][2],
                "the minus is moved to the front: " .. value)
        end
    end
    T.eq(abbr(-0), "0", "minus zero is simply zero")

    -- The spelling "1000.0k" never occurs for any value: that is why the
    -- million threshold is corrected for rounding. The whole band around the
    -- threshold is checked in a row rather than one chosen number, and the
    -- report carries the first offence -- otherwise one mistake would cost a thousand red lines.
    do
        local bad = nil
        for value = 999000, 1000000 do
            local text = abbr(value)
            if text:find("^1000%.") then
                bad = value .. " -> " .. text
                break
            end
        end
        T.eq(bad, nil, "nowhere does the fraction reach the next unit")
    end

    -- A magnitude has one unit: no "k" inside an "m", no two letters.
    do
        local bad = nil
        for i = 1, #CASES do
            local text = abbr(CASES[i][1])
            local units = 0
            for _ in text:gmatch("[km]") do units = units + 1 end
            if units > 1 then bad = text break end
        end
        T.eq(bad, nil, "a magnitude has one unit")
    end

    -- Garbage in gives nil out: "nothing to abbreviate" and "zero" are
    -- different answers, and substituting one for the other is not allowed.
    T.eq(abbr(nil), nil, "nil is not abbreviated")
    T.eq(abbr("letters"), nil, "a string that is not a number is not abbreviated")
    T.eq(abbr({}), nil, "a table is not abbreviated")
    T.eq(abbr(true), nil, "true is not abbreviated")
    T.eq(abbr(0 / 0), nil, "NaN is not abbreviated")
    T.eq(abbr(math.huge), nil, "infinity is not abbreviated")
    T.eq(abbr(-math.huge), nil, "nor is minus infinity")
    T.eq(abbr("12437"), "12.4k", "a number as a string counts as a number")
end

T.suite("a share as a percentage")

do
    local percent = core().Api:GetFormat().Percent

    T.eq(percent(0, 100), 0, "zero out of a hundred is zero")
    T.eq(percent(50, 100), 50, "a half")
    T.eq(percent(100, 100), 100, "the whole")
    T.eq(percent(150, 100), 150, "more than the maximum is more than a hundred")
    T.eq(percent(1, 3), 33, "a third rounds down")
    T.eq(percent(2, 3), 67, "two thirds round up")
    T.eq(percent(1, 200), 1, "an exact half percent moves away from zero")
    T.eq(percent(3, 200), 2, "one and a half percent goes to two")
    T.eq(percent(5, 200), 3, "two and a half goes to three")

    -- A zero maximum gives zero percent rather than a division by zero or
    -- nil: a bar with a zero maximum happens on a unit out of sight and on a
    -- class with no resource, that is all the time.
    T.eq(percent(50, 0), 0, "a zero maximum gives zero percent")
    T.eq(percent(50, -10), 0, "a negative maximum gives zero too")
    T.eq(percent(nil, nil), 0, "the absence of both magnitudes gives zero")
    T.eq(percent("letters", "letters"), 0, "garbage gives zero")
    T.eq(percent(50, 0 / 0), 0, "NaN in the maximum gives zero")
    T.eq(percent(0 / 0, 100), 0, "NaN in the value gives zero")
    T.eq(percent(50, math.huge), 0, "an infinite maximum gives zero")
    T.eq(percent("50", "100"), 50, "numbers as strings count as numbers")

    -- The very divergence the rounding was consolidated for. The bar label
    -- computed math.floor(v + 0.5): on negatives a half moves towards zero
    -- while on positives it moves away from zero, and Percent(-c, m) stops
    -- being minus Percent(c, m). The panel handled the sign explicitly; that is what was taken.
    T.eq(percent(-1, 200), -1, "minus an exact half moves away from zero")
    T.eq(percent(-5, 200), -3, "minus two and a half goes to minus three")
    T.eq(percent(-1, 3), -33, "minus a third")
    T.eq(percent(-2, 3), -67, "minus two thirds")

    for _, pair in ipairs({ { 1, 200 }, { 3, 200 }, { 5, 200 }, { 1, 3 },
                            { 2, 3 }, { 50, 100 }, { 7, 9 }, { 123, 456 } }) do
        local c, m = pair[1], pair[2]
        T.eq(percent(-c, m), -percent(c, m),
            "the sign is a factor: " .. c .. "/" .. m)
    end

    -- The result is not clamped to zero. The clamping belonged to the info
    -- panel, and that is its decision about its own cell rather than part of
    -- the rounding: a negative percentage means somebody computed the wrong
    -- thing, and replacing it with zero means hiding their mistake behind a plausible answer.
    T.eq(percent(-50, 100), -50, "a negative share is shown as it is")

    -- The answer is always an integer: the label writes it through %d.
    for _, pair in ipairs({ { 1, 3 }, { 2, 7 }, { 123456, 999999 },
                            { -1, 3 }, { 0, 5 } }) do
        local value = percent(pair[1], pair[2])
        T.eq(value, math.floor(value), "the percentage is an integer: " .. value)
    end
end

T.suite("an old-version module calls the numbers and gets the same ones")

-- The version limits ownership of descriptor names, not access to the
-- surface.
do
    local ns, said = core()
    local fmt = ns.Api:GetFormat()

    for version = ns.Api.API_MIN_VERSION, ns.Api.API_VERSION do
        local handle = ns.Api:RegisterModule({
            name = "numbers" .. version,
            api  = version,
        })
        T.ok(handle ~= nil, "a version " .. version .. " module is registered")

        local theirs = ns.Api:GetFormat()
        T.eq(theirs, fmt, "version " .. version .. ": one door for everyone")
        T.eq(theirs.Abbreviate(12437), "12.4k",
            "version " .. version .. ": the same answer")
        T.eq(theirs.Percent(1, 3), 33,
            "version " .. version .. ": and the same percentage")
    end

    local old = ns.Api:RegisterModule({ name = "cautious", api = 2 })
    T.ok(old ~= nil, "a version 2 module registers")
    T.eq(ns.Api:Supports(12), true, "and is entitled to ask about the twelfth")

    T.eq(#said, 0, "the core did not complain: " .. table.concat(said, " | "))

    local future, reason = ns.Api:RegisterModule({
        name = "tooNew", api = ns.Api.API_VERSION + 1 })
    T.eq(future, nil, "a module of a future version does not register")
    T.ok(type(reason) == "string" and reason:find("update Darken", 1, true),
        "and the refusal says it is the core that needs updating")
end

T.suite("Metrics.edge: the label inset from the edge")

-- The second gap of the same analysis. Between hair and rail the scale was
-- empty, and that place was taken by four literals in three subsystems. What
-- is checked is the place of the magnitude in the series, not the number itself.
do
    local ns = core()
    local M = ns.Skin.Metrics

    T.eq(type(M.edge), "number", "the scale has edge")
    T.ok(M.edge > 0, "and it is a positive number")
    T.ok(M.edge > M.hair, "the label is pushed further than the border thickness")
    T.ok(M.edge < M.rail, "and closer than the left rail")

    -- The magnitude is handed out through the same door as the whole scale, and as a copy.
    local metrics = ns.Api:GetSkin().Metrics()
    T.eq(metrics.edge, M.edge, "a module gets the same inset")

    metrics.edge = -999
    T.ok(ns.Skin.Metrics.edge ~= -999, "the scale is still handed out as a copy")
end

T.suite("one rule resolves a texture name")

-- The third gap of the analysis, and the only one of the three that changes
-- the outcome on screen. There were two answers: ns.Media.BarPath (our nine
-- as files, then the registry) for the contract, and ns.Skin.MediaTexture
-- (the registry only) for the core subsystems. The difference shows exactly
-- when LibSharedMedia is not installed: an author texture chosen by the
-- player would appear on the engine nameplates and would not appear on the
-- unit frames, the cast bar and the preview in the list. Today the library
-- lies in Libs/ and is always loaded, that is the rule rested on the packaging rather than on a declaration.
do
    local ns = core()

    -- The fake library knows one foreign name and not one of ours: that is
    -- how it shows where the answer came from.
    local lib = {
        IsValid = function(_, kind, name)
            return kind == "statusbar" and name == "Foreign bar"
        end,
        Fetch = function(_, kind, name)
            if kind == "statusbar" and name == "Foreign bar" then
                return "Interface\\Foreign\\bar.tga"
            end
            return nil
        end,
    }

    local ours = ns.Media.Entries()[1].name

    -- The names are wrapped one by one: a nil in the list is as valid an
    -- input as the rest, while in a plain array it would cut the walk short silently.
    local NAMES = { { ours }, { "Darken Purple" }, { "Foreign bar" },
                    { "Close" }, { "__native" }, { "" }, { nil }, { 42 },
                    { {} } }

    -- One rule means the same answer on any input, not "works much the
    -- same": the two resolvers are compared against each other, without any
    -- path named by us.
    for _, box in ipairs({ { lib }, { nil } }) do
        local pass = box[1]
        local with = pass and " (with the library)" or " (without the library)"
        for i = 1, #NAMES do
            local name = NAMES[i][1]
            T.eq(ns.Skin.MediaTexture(pass, name), ns.Media.BarPath(pass, name),
                "both resolvers answer the same: " .. tostring(name) .. with)
        end
    end

    -- And the same shows from a third side -- from the contract a module
    -- uses.
    local media = ns.Api:GetMedia()
    T.eq(media.BarTexture(ours), ns.Skin.MediaTexture(nil, ours),
        "the contract and the core resolve our name identically")

    -- Here is the outcome that used to be invisible: without the library our
    -- nine are found anyway -- they lie as files inside the addon.
    local path = ns.Skin.MediaTexture(nil, ours)
    T.ok(type(path) == "string" and path ~= "",
        "without the library our texture is found: " .. tostring(path))
    T.ok(path:find("Darken", 1, true) ~= nil,
        "and it is found as a file inside the addon")

    -- Without the library there is nobody to ask about a foreign name, and
    -- inventing an answer is not allowed: a silent substitution by a foreign texture is worse than a refusal.
    T.eq(ns.Skin.MediaTexture(nil, "Foreign bar"), nil,
        "a foreign name without the library gives nil")
    T.eq(ns.Skin.MediaTexture(lib, "Foreign bar"), "Interface\\Foreign\\bar.tga",
        "while with the library it gives its path")

    -- The "is this a texture or not" filter has not weakened: a word from the
    -- list does not get a bar. That is what MediaTexture was born for.
    T.eq(ns.Skin.MediaTexture(lib, "Close"), nil,
        "a word from the list does not count as a texture")
    T.eq(ns.Skin.MediaTexture(lib, ""), nil, "an empty name gives nil")
    T.eq(ns.Skin.MediaTexture(lib, 42), nil, "a non-string name gives nil")
    T.eq(ns.Skin.MediaTexture(lib, nil), nil, "the absence of a name gives nil")
    T.eq(ns.Skin.MediaTexture({}, ours), ns.Media.BarPath({}, ours),
        "an object with no methods does not stop our texture being found")

    -- The rule has no second body left: the statusbar registry is asked from
    -- one file in the core.
    local owner = "Core/Media.lua"
    for _, file in ipairs(coreFiles()) do
        if file ~= owner then
            local text = read(file)
            T.eq(text:find("\"statusbar\"", 1, true), nil,
                "the statusbar registry is asked only in " .. owner
                .. ", yet it was asked in " .. file)
        end
    end
    T.ok(read(owner):find("\"statusbar\"", 1, true) ~= nil,
        "and in " .. owner .. " it really is asked")
end
