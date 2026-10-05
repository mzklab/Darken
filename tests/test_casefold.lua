local helpers = require("helpers")

-- Core case handling: Darken:GetCasefold() (folding is contract version 9,
-- upper case is version 10).
--
-- What is checked is not "how our three subsystems use it" -- their own
-- suites do that (tests/test_bagsmodule.lua, tests/test_itemdb.lua,
-- tests/test_aurafilter.lua) -- but the mapping table itself, because a
-- mistake in it is doubly silent. A fold that did not happen the player sees
-- as "I do not have that"; a fold that went to the wrong place they see as
-- a foreign item in the answer, and they stop trusting the search box. The
-- second is worse than the first, so the letter pairs that have no right to
-- fold together are named here one by one.

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

local ns = core()
local casefold = ns.Api:GetCasefold()
local fold = casefold.Fold

T.suite("case folding: the contract door")

do
    T.eq(type(casefold), "table", "the core hands the folding out")

    -- The same table the core uses itself, not a lookalike beside it: a
    -- second mapping table would silently drift from the first.
    T.eq(casefold, ns.Casefold, "the very table was handed out, not a copy")

    -- A snapshot of the surface: a name added by accident will demand a
    -- deliberate decision. The outward contract may be neither narrowed nor widened unnoticed.
    local surface = {}
    for key, value in pairs(casefold) do
        surface[#surface + 1] = key .. ":" .. type(value)
    end
    table.sort(surface)
    T.eq(table.concat(surface, ","),
        "Fold:function,Key:function,Upper:function",
        "the case surface: " .. table.concat(surface, ","))

    -- The version limits ownership of descriptor names, not access to the
    -- surface: a module declaring version one is entitled to ask and to
    -- receive. Otherwise "a module built for version 1 works as it worked"
    -- would mean "works until it asks".
    -- The version number is not written here: upper case was handed out by
    -- the tenth, and holding that as a comparison with the current
    -- API_VERSION would mean editing the case check whenever the contract grows elsewhere.
    T.ok(ns.Api.API_VERSION >= 10, "upper case was handed out by version ten")
    T.eq(ns.Api:Supports(9), true, "the ninth, which handed out folding, is supported")
    T.eq(ns.Api:Supports(10), true, "the tenth as well")
    T.eq(ns.Api.API_MIN_VERSION, 1, "while the lower bound stayed at one")

    local old = ns.Api:RegisterModule({
        name = "oldtimer", api = 1,
        OnEnable = function() end,
    })
    T.ok(old ~= nil, "a version 1 module registers")
    T.eq(ns.Api:GetCasefold(), casefold,
        "and gets the same case handling as everyone else")

    -- Upper case is for display, folding is for comparison, and both sides
    -- walk the same alphabet table. Upper case deliberately has no door of
    -- its own: two doors would promise two different kinds of knowledge.
    T.eq(casefold.Upper("профілі"), "ПРОФІЛІ",
        "upper case is handed out through the same door")
    T.eq(casefold.Fold(casefold.Upper("профілі")), "профілі",
        "and these are the two sides of one pair")
end

T.suite("case folding: Latin")

do
    T.eq(fold("BREAD"), "bread", "upper-case Latin folds")
    T.eq(fold("bread"), "bread", "lower case stays itself")
    T.eq(fold("Tough Hunk of Bread"), "tough hunk of bread",
        "and both ways inside a string")

    -- Latin with diacritics: the German, French, Spanish, Italian and
    -- Portuguese clients. string.lower did not know their letters at all --
    -- it knows one byte.
    T.eq(fold("ÄÖÜ"), "äöü", "German umlauts")
    T.eq(fold("ÉÈÊÇ"), "éèêç", "French marks")
    T.eq(fold("ÑÁÍÓÚ"), "ñáíóú", "Spanish ones")
    T.eq(fold("ÃÕÀÌÒÙ"), "ãõàìòù", "Portuguese and Italian ones")
    T.eq(fold("Ärger"), fold("ärger"), "and both ways")
end

T.suite("case folding: Cyrillic")

do
    -- The very case all of this was made for: the Russian client.
    T.eq(fold("ХЛЕБ"), "хлеб", "upper-case Cyrillic folds")
    T.eq(fold("Хлеб"), "хлеб", "and capitalised too")
    T.eq(fold("хлеб"), "хлеб", "lower case stays itself")
    T.eq(fold("Хлеб"), fold("хлеб"), "both ways give one and the same")
    T.eq(fold("АБВГДЕЖЗИЙКЛМНОП"), "абвгдежзийклмноп", "the first range, А-П")
    T.eq(fold("РСТУФХЦЧШЩЪЫЬЭЮЯ"), "рстуфхцчшщъыьэюя", "the second, Р-Я")
    T.eq(fold("Ёж"), "ёж", "Ё lies outside both ranges and still folds")

    -- Ukrainian letters absent from the Russian alphabet. The author writes
    -- in Ukrainian, and "Ігор" must be findable when typed as "ігор".
    T.eq(fold("ІЇЄҐ"), "ії" .. "єґ", "all four at once")
    T.eq(fold("І"), "і", "І folds")
    T.eq(fold("Ї"), "ї", "Ї folds")
    T.eq(fold("Є"), "є", "Є folds")
    T.eq(fold("Ґ"), "ґ", "Ґ folds even though it lies outside the range")
    T.eq(fold("Ігор Ґанок"), "ігор ґанок", "and in a live string")
end

T.suite("case folding: pairs that have no right to fold together")

do
    -- The worst folding can do is merge two different letters. Then the
    -- search answers with things nobody asked about, and the player stops
    -- trusting it. Every pair here is named because it is easy to get wrong.

    -- Latin A and Cyrillic А look identical and are in fact different. The
    -- string "Аркан" in Cyrillic need not be found by a Latin "A".
    T.ok(fold("A") ~= fold("А"), "Latin A and Cyrillic А are not the same")
    T.ok(fold("c") ~= fold("с"), "Latin c and Cyrillic с are not the same")
    T.ok(fold("Pop") ~= fold("Рор"), "and whole lookalike words do not match")

    -- Е and Ё are different letters of the Russian alphabet, and "все" need
    -- not find "всё". The "add 0x20" arithmetic does not merge them, and that is pinned down.
    T.ok(fold("Е") ~= fold("Ё"), "Е and Ё are different letters")
    T.ok(fold("е") ~= fold("ё"), "and in lower case too")

    -- И (Russian) and І (Ukrainian) look nearly identical and sit in
    -- different places of the table.
    T.ok(fold("И") ~= fold("І"), "И and І are different letters")
    T.ok(fold("и") ~= fold("і"), "and in lower case too")

    -- The classic trap of the Latin range: × (the multiplication sign,
    -- U+00D7) sits between Ö and Ø, and "add 0x20" would turn it into ÷
    -- (U+00F7). Neither is a letter, and neither may become the other.
    T.eq(fold("×"), "×", "the multiplication sign stays itself")
    T.eq(fold("÷"), "÷", "the division sign too")
    T.ok(fold("×") ~= fold("÷"), "and they do not turn into each other")

    -- The Turkish İ (U+0130) and ı (U+0131). The game has no Turkish client,
    -- and "correct" Turkish folding would fold Latin I into ı -- that is, it
    -- would break search on ten clients out of eleven for the sake of a
    -- non-existent one. Neither letter folds with anything.
    T.eq(fold("İ"), "İ", "İ stays itself")
    T.eq(fold("ı"), "ı", "ı stays itself")
    T.ok(fold("İ") ~= fold("i"), "İ does not match Latin i")
    T.ok(fold("I") ~= fold("ı"), "and Latin I does not match ı")
    T.eq(fold("I"), "i", "while Latin I folds as it does everywhere")

    -- ß is lower case already. Folding it into "ss" is not allowed: that
    -- changes the string length and makes "Straße" and "Strasse" one word, which the game does not do.
    T.eq(fold("ß"), "ß", "ß stays itself")
    T.ok(fold("ß") ~= fold("SS"), "and it does not become \"ss\"")
end

T.suite("case folding: mixtures, repetition and emptiness")

do
    -- An item name on the Russian client is routinely mixed with Latin and
    -- digits: "Свиток Защиты II", "Эликсир (Rank 2)".
    T.eq(fold("Свиток Защиты II"), "свиток защиты ii",
        "a mixture of Cyrillic and Latin folds completely")
    T.eq(fold("Ärger UND Ärger"), "ärger und ärger",
        "a mixture of Latin with and without diacritics")
    T.eq(fold("ХЛЕБ 42 Bread ÄÖ"), "хлеб 42 bread äö",
        "digits and spaces pass through untouched")

    -- Folding twice is the same as folding once. A string gets folded in
    -- different places, and the second time must not spoil the first.
    local once = fold("Хлеб ÄÖ Bread")
    T.eq(fold(once), once, "folding again changes nothing")
    T.eq(fold("хлеб"), "хлеб", "already folded Cyrillic stays itself")
    T.eq(fold("äöü"), "äöü", "already folded Latin with marks too")

    T.eq(fold(""), "", "an empty string folds into an empty one")
    T.eq(fold(" "), " ", "a space stays a space")
    T.eq(fold(nil), nil, "not a string -- nothing to fold")
    T.eq(fold(42), nil, "a number likewise")
    T.eq(fold({}), nil, "and a table")

    -- The comparison key: the same folding plus trimming the edges. Empty and
    -- whitespace give nil, that is "nothing to compare": an empty string as a
    -- query would match everything at once.
    T.eq(casefold.Key("  Хлеб  "), "хлеб", "the key trims the edges and folds")
    T.eq(casefold.Key("   "), nil, "spaces mean \"nothing to compare\"")
    T.eq(casefold.Key(""), nil, "an empty string likewise")
    T.eq(casefold.Key(nil), nil, "and the absence of a string")
    T.eq(casefold.Key(42), nil, "and a non-string")
end

T.suite("case folding: the three cases it exists for")

do
    -- An item name (the bags module). A player on the Russian client types
    -- their word in lower case, because that is how people type.
    local item = "Хлеб"
    T.ok(fold(item):find(casefold.Key("хлеб"), 1, true) ~= nil,
        "an item name is found when typed in a different case")

    -- The typed query (the item database). Folded once, compared many times
    -- -- and the folded form is not equal to the typed one, that is the
    -- player gets their own spelling back in the box, not ours.
    local typed = "ХлЕб"
    T.eq(casefold.Key(typed), "хлеб", "the typed query is reduced to a key")
    T.ok(casefold.Key(typed) ~= typed, "while the typed text stays as typed")
    T.eq(typed, "ХлЕб", "folding does not rewrite the string in place")

    -- A spell name (the shared aura filter). The name key is the very core
    -- function, not a copy beside it.
    local filter = ns.Api:GetAuraFilter()
    T.eq(filter.Key, casefold.Key, "the aura name key is the core folding")
    T.eq(filter.Key(" Кровопускание "), "кровопускание",
        "a spell name is reduced to a key")
    T.eq(filter.Key("КРОВОПУСКАНИЕ"), filter.Key("кровопускание"),
        "and matches what was typed in any case")

    -- Folding is for comparison, and nothing else. Neither an item name nor a
    -- spell name is ever stored folded: what the game handed out is what is kept.
    local plan = filter.Compile("Кровопускание", "deny")
    T.eq(plan.names["кровопускание"], true, "a folded key went into the dictionary")
    T.eq(filter.Decide(plan, filter.Key("кровопускание"), nil), filter.HIDE,
        "and a decision is made by it")
end

T.suite("case folding: the cost")

do
    -- Folding sits on the search path -- 1800 names per keystroke -- and on
    -- the aura path, where it is called in combat. So folded forms are
    -- remembered: the second time the same string costs a dictionary lookup.
    --
    -- A ratio is checked rather than milliseconds: a threshold in seconds on
    -- someone else's machine would mean a red line where everything is fine.
    local names = {}
    for i = 1, 1800 do names[i] = "Хлеб Номер " .. i end

    -- The fold result is counted rather than discarded: a call whose result
    -- nobody needs the compiler may skip entirely, and the measurement would
    -- show zero regardless of what it costs.
    local letters = 0

    -- There are many passes: one keystroke costs less than the clock can
    -- measure, and a single pass would show zero regardless of the cost.
    local ROUNDS = 500

    local function pass()
        local started = os.clock()
        for _ = 1, ROUNDS do
            for i = 1, 1800 do letters = letters + #fold(names[i]) end
        end
        return (os.clock() - started) / ROUNDS
    end

    local first = pass()         -- the first pass fills the memory
    local second = pass()
    for _ = 1, 3 do second = math.min(second, pass()) end

    io.write(string.format(
        "  [folding cost] 1800 names: remembered %.3f ms\n", second * 1000))

    T.ok(letters > 0, "the folding really was called: " .. letters)
    T.ok(second <= first + 0.001,
        "folding again is not more expensive than the first time")
    T.ok(second * 1000 < 20, string.format(
        "1800 folded names fit into 20 ms: %.3f ms", second * 1000))

    -- The memory is bounded, and crossing the bound breaks nothing: the
    -- dictionary is created anew while the answers stay the same. This is
    -- checked with a number of strings well above the bound.
    for i = 1, 20000 do fold("Строка Номер " .. i) end
    T.eq(fold("Хлеб"), "хлеб", "after the memory reset the answer is the same")
    T.eq(fold("ÄÖÜ"), "äöü", "and the same for Latin with diacritics")
    T.eq(fold("×"), "×", "and the pair that does not fold did not fold")
end

helpers.removeValidator()
