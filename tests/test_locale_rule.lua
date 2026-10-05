local helpers = require("helpers")
local C = require("cyrillic")

-- The base-language rule.
--
-- Spec, §5.4: the base language of the addon is English, and the English
-- string itself serves as the translation key. Russian and Ukrainian are laid
-- on top. The rule implies a prohibition nobody guarded until now: a string
-- the player reads in chat or in a window may not be written in Russian
-- right in the code. Such a string is not merely shown in the wrong
-- language -- it is not translated at all, because the translation is looked
--
-- Why tests/test_locale_tables.lua did not catch this. That check compares
-- two lists: the keys handed to ns.Localize, and the entries of the
-- translation tables. It answers the question "is what we translate
-- translated", and answers it well -- including the ban on a non-English
-- key. But a string that went straight to self:Print past ns.Localize never
-- becomes a key for a moment: it is absent from the first list and from the
-- second, and both halves agree. A completeness check by construction sees
-- only what has already been chosen for translation; it cannot and must not
-- ask whether everything was chosen. That is the second question, and it is here.
--
-- WHAT TELLS A COMMENT FROM A LABEL. This is the main difficulty of the
-- rule: a comment is free text (today English; historically Russian) and is
-- allowed to stay, while a non-English label must disappear. The difference
-- is not guessed from the look of the text but taken from a parser
-- (tests/cyrillic.lua): the file is walked the way Lua walks it, and "--" to
-- end of line and "--[[ ... ]]" are skipped whole. Only what the game counts
-- as a string counts as a string. So a comment of any length in any language
-- is invisible to this check, while a "--" or a quote inside a literal does
--
-- WHAT THE CHECK DOES NOT CATCH.
--
-- 1. Russian text assembled at runtime: from pieces, from string.char, from
--    saved variables, from a game response. It is not in the source, and the
--    parser knows nothing about it.
-- 2. An English string that reached the player past ns.Localize anywhere but
--    :Print. It does not break the language rule (English is the base), but
--    it cannot be translated. The second half of the check catches such
--    strings only in chat -- the labels and descriptions of the settings
--    window are guarded by the completeness check, because the settings tree
-- 3. A key translated wrongly or into the wrong language. That is meaning, not form.
-- 4. The correctness of the English itself.

T.suite("language rule: the parser tells a string from a comment")

-- The parser is checked first and on samples rather than on the addon: the
-- whole language rule rests on it, and a parser that stopped seeing literals
-- looks exactly as green as a clean addon.
do
    local function cyrillicIn(text)
        local found = {}
        for _, entry in ipairs(C.literals(text)) do
            if C.hasCyrillic(entry.text) then found[#found + 1] = entry.text end
        end
        return found
    end

    T.eq(#cyrillicIn('-- русский комментарий\nlocal a = 1\n'), 0,
        "a single-line comment does not count as a string")

    T.eq(#cyrillicIn('--[[ русский\n   комментарий "в кавычках" ]]\nlocal a = 1\n'), 0,
        "a block comment does not count as a string, even with quotes inside")

    T.eq(#cyrillicIn('local a = "русская подпись"\n'), 1,
        "a double-quoted literal is visible")

    T.eq(#cyrillicIn("local a = 'русская подпись'\n"), 1,
        "a single-quoted literal is visible")

    T.eq(#cyrillicIn('local a = [[русская подпись]]\n'), 1,
        "a long literal is visible")

    T.eq(#cyrillicIn('local a = "два -- дефиса и русский текст"\n'), 1,
        "a \"--\" inside a literal does not open a comment")

    T.eq(#cyrillicIn('local a = "кавычка \\" внутри"\n'), 1,
        "an escaped quote does not close the literal")

    -- The order of calls around a literal -- both halves of the rule rest on it.
    do
        local entries = C.literals(
            'self:Print(string.format(ns.Localize("found %d"), n))\n')
        T.eq(#entries, 1, "exactly one literal was found")
        T.eq(table.concat(entries[1].calls, "|"),
            "self:Print|string.format|ns.Localize",
            "the enclosing calls are collected from outermost to innermost")
        T.eq(C.within(entries[1], { "Print" }), true, "the Print call is visible")
        T.eq(C.within(entries[1], { "Localize" }), true, "the Localize call is visible")
    end

    -- The very defect this check was written for.
    do
        local entries = C.literals('self:Print("русская подпись")\n')
        T.eq(#entries, 1, "the literal was found")
        T.eq(C.hasCyrillic(entries[1].text), true, "the Cyrillic was recognised")
        T.eq(C.within(entries[1], { "Print" }), true, "it goes to chat")
        T.eq(C.within(entries[1], { "Localize" }), false, "past the translation")
    end

    T.eq(C.hasCyrillic("plain ascii"), false, "an English string is clean")
    T.eq(C.hasCyrillic("українська"), true, "Ukrainian letters are Cyrillic too")
end

T.suite("language rule: the sources of the package")

-- The file list is asked of the TOC -- both the core TOC and the TOC of
-- every module found on disk. A hand-written list would fall behind
-- silently: a file forgotten in it is not checked at all yet looks checked.
-- A file in no TOC is not loaded by the game, so it shows the player nothing.
local SOURCES = {}
do
    -- There is one TOC because there is one addon: the parts are listed in
    -- it. Formerly the TOC of every part was added here -- back then each
    -- part was a separate addon.
    local tocs = { "Darken.toc" }

    local seen = {}
    for i = 1, #tocs do
        local toc = tocs[i]
        local dir = toc:match("^(.*)/[^/]+$")
        local handle = io.open(toc, "r")
        if not handle then error("could not open " .. toc, 0) end
        for line in handle:lines() do
            local rel = line:match("^%s*([%w_][^%s]*%.lua)%s*$")
            if rel then
                local path = rel:gsub("\\", "/")
                if dir then path = dir .. "/" .. path end
                if not seen[path] then
                    seen[path] = true
                    SOURCES[#SOURCES + 1] = path
                end
            end
        end
        handle:close()
    end
    table.sort(SOURCES)
end

T.ok(#SOURCES >= 60, "the package files were collected from the TOC: " .. #SOURCES)
T.ok(#helpers.moduleFolders() >= 5,
    "the module folders were asked of the disk: " .. #helpers.moduleFolders())

--============================================================================
-- First half: Cyrillic inside a literal
--============================================================================

-- Translation files hold Cyrillic by design: there it IS the translation.
local function isLocaleFile(path)
    -- "Locale/ruRU.lua" for the core and "UmbraUI_Bags/Locale/ruRU.lua" for a module.
    return path:match("^Locale/") ~= nil or path:match("/Locale/") ~= nil
end

-- Calls inside which Cyrillic stays legitimate, and why.
--
-- error(...) is an assertion for whoever writes the code: "the frame group
-- is declared twice", "there is no migration from version N". The player
-- never sees such a string in any healthy state of the addon: it fires on a
-- typo in the source itself, at load time, and it is addressed to the
-- author. Translating it would mean adding keys nobody will ever see to the
-- translation tables, and demanding completeness for them.
--
-- Skin.Report(...) is the styling failure log. By default it is not printed
-- at all (Skin.Debug = false, Skin/Draw.lua) and is enabled by one line by
-- hand; the file itself calls it "read by a developer, not by a player".
local DEV_CALLS = { "error", "assert", "Report" }

-- Named exemptions: file -> string -> why.
--
-- The list is deliberately short and self-cleaning: an exemption no literal
-- matches any more fails the check. Otherwise an exemption would outlive the
-- string it was created for, and would quietly cover the next one.
local EXEMPT = {
    -- Settings migrations are a record of history, not a label. These are the
    -- names of the author's textures before the 2 -> 3 rename (Core/Media.lua
    -- became English): they sit in the saved variables of old profiles and
    -- must keep their former spelling forever, or the migration will stop
    -- recognising an old profile. None of them is ever shown to the player:
    -- the migration turns them into English names before the settings window reads them.
    ["Core/Defaults.lua"] = {
        ["Umbra бирюзовая"] = "texture name before the 2 -> 3 migration",
        ["Umbra жёлтая"]    = "texture name before the 2 -> 3 migration",
        ["Umbra зелёная"]   = "texture name before the 2 -> 3 migration",
        ["Umbra красная"]   = "texture name before the 2 -> 3 migration",
        ["Umbra оранжевая"] = "texture name before the 2 -> 3 migration",
        ["Umbra розовая"]   = "texture name before the 2 -> 3 migration",
        ["Umbra синяя"]     = "texture name before the 2 -> 3 migration",
        ["Umbra сиреневая"] = "texture name before the 2 -> 3 migration",
        ["Umbra тёмная"]    = "texture name before the 2 -> 3 migration",
    },
}

-- Vocabulary files: the Cyrillic in them is what the player types, not what
-- they read. The item-database query parser understands words of three
-- languages ("сумки", "якість", "bank"), and an English base does not cancel
-- that rule: the player types in their own language, not in the addon's.
--
-- The exemption is narrow and is confirmed right here: a vocabulary file has
-- no right to print anything -- not one literal inside :Print. Were a label
-- to appear in it, the exemption would stop covering it.
local VOCABULARY = {
}

local usedExempt, usedVocabulary = {}, {}
local leaked = {}

for i = 1, #SOURCES do
    local path = SOURCES[i]
    if not isLocaleFile(path) then
        local entries = C.literals(C.read(path))
        local vocabulary = VOCABULARY[path]

        if vocabulary then
            usedVocabulary[path] = 0
            for j = 1, #entries do
                if C.hasCyrillic(entries[j].text) then
                    usedVocabulary[path] = usedVocabulary[path] + 1
                end
                -- A vocabulary that started talking has stopped being a vocabulary.
                T.eq(C.within(entries[j], { "Print" }), false,
                    path .. ": a vocabulary file prints nothing, line "
                        .. entries[j].line)
            end
        else
            local byFile = EXEMPT[path]
            for j = 1, #entries do
                local entry = entries[j]
                if C.hasCyrillic(entry.text)
                    and not C.within(entry, DEV_CALLS) then
                    if byFile and byFile[entry.text] then
                        usedExempt[path] = usedExempt[path] or {}
                        usedExempt[path][entry.text] = true
                    else
                        leaked[#leaked + 1] = string.format("%s:%d «%s»",
                            path, entry.line, entry.text:sub(1, 48))
                    end
                end
            end
        end
    end
end

T.eq(#leaked, 0, "Cyrillic reached the player past ns.Localize: "
    .. table.concat(leaked, " | "))

-- An exemption with no string to cover is an exemption that outlived its
-- reason. It fixes nothing and covers the next mistake silently.
do
    local stale = {}
    for path, byFile in pairs(EXEMPT) do
        for text in pairs(byFile) do
            if not (usedExempt[path] and usedExempt[path][text]) then
                stale[#stale + 1] = path .. ": «" .. text:sub(1, 40) .. "»"
            end
        end
    end
    T.eq(#stale, 0, "exemptions with nothing to cover: "
        .. table.concat(stale, " | "))

    local emptyVocabulary = {}
    for path in pairs(VOCABULARY) do
        if (usedVocabulary[path] or 0) == 0 then
            emptyVocabulary[#emptyVocabulary + 1] = path
        end
    end
    T.eq(#emptyVocabulary, 0, "vocabulary files without Cyrillic: "
        .. table.concat(emptyVocabulary, " | "))
end

T.suite("language rule: chat goes through ns.Localize")

--============================================================================
-- Second half: a literal going to chat past the translation
--============================================================================

-- Cyrillic is the shape of the violation, not the violation itself. An
-- English string printed past ns.Localize obeys the language rule but is
-- just as unavailable to translation. So the second half looks not at
-- letters but at the path: a literal inside :Print must be inside ns.Localize.
--
-- Separators and glue are skipped: "  ", ": ", "%s" are not labels and need
-- no translation. The mark of a label is four letters in a row.
local PRINT_CALLS = { "Print" }
local TRANSLATE_CALLS = { "Localize", "LocalizeFor" }

-- UmbraUI_Example is a sample of the contract, not a feature for the player:
-- its command exists to expose the breakage switches to the checks. It has
-- no translation files of its own and deliberately gets none -- the sample
-- ships as exactly two files, and that is part of what it demonstrates. For
-- the same reason it is excluded from the documentation guard (tests/test_docs.lua).
local NOT_A_FEATURE = "^UmbraUI_Example/"

local untranslated = {}
for i = 1, #SOURCES do
    local path = SOURCES[i]
    if not isLocaleFile(path) and not path:match(NOT_A_FEATURE) then
        for _, entry in ipairs(C.literals(C.read(path))) do
            local looksLikeText = entry.text:find("%a%a%a%a")
                or C.hasCyrillic(entry.text)
            if looksLikeText
                and C.within(entry, PRINT_CALLS)
                and not C.within(entry, TRANSLATE_CALLS) then
                untranslated[#untranslated + 1] = string.format("%s:%d «%s»",
                    path, entry.line, entry.text:sub(1, 48))
            end
        end
    end
end

T.eq(#untranslated, 0, "strings to chat past ns.Localize: "
    .. table.concat(untranslated, " | "))

T.suite("language rule: translations of what the core prints")

-- The strings the rule was written for are also checked on the merits: the
-- key is in both tables, an English client sees English, a Russian one
-- Russian, a Ukrainian one Ukrainian. Completeness of all keys is checked by
-- tests/test_locale_tables.lua; named here are the ones that used to reach
-- the player in Russian.
do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Locale/ruRU.lua", ns)
    helpers.loadAddonFile("Locale/ukUA.lua", ns)

    local KEYS = {
        "this build has no demo section",
        "the demo section is on",
        "the demo section is off",
        "usage: /darken scan <part of a frame name>",
        "the settings database is not ready yet",
        "collected %d names over %d patterns",
        "log out - the result will land in Darken.lua (SavedVariables)",
        "found %d for the pattern '%s':",
        "... and %d more - narrow the pattern",
        "this module was switched off",
        "a module name must be a non-empty string",
    }

    ns.SetLocale("enUS")
    for i = 1, #KEYS do
        T.eq(ns.Localize(KEYS[i]), KEYS[i],
            "an English client sees English: " .. KEYS[i])
    end

    for _, locale in ipairs({ "ruRU", "ukUA" }) do
        ns.SetLocale(locale)
        local missing = {}
        for i = 1, #KEYS do
            local value = ns.Localize(KEYS[i])
            if value == KEYS[i] or not C.hasCyrillic(value) then
                missing[#missing + 1] = KEYS[i]
            end
        end
        T.eq(#missing, 0, locale .. ": left untranslated: "
            .. table.concat(missing, " | "))
    end

    -- The words the author uses for these things in Ukrainian: not a check of
    -- the whole translation, but a check that the table is written in his own
    -- vocabulary rather than copied from the Russian.
    ns.SetLocale("ukUA")
    T.eq(ns.Localize("the demo section is off"), "показовий розділ вимкнено",
        "the Ukrainian \"вимкнено\" is in place")
    T.eq(ns.Localize("this module was switched off"), "модуль вимкнено",
        "Ukrainian \"модуль вимкнено\", not the Russian wording")
end
