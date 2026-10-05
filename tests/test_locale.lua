local helpers = require("helpers")

-- The addon's base language is English, and the English string itself serves
-- as the translation key (the spec, §5.4). The main consequence is what is
-- checked here: the English interface comes out without a single line of
-- translation, while a locale overrides only what it holds.

T.suite("Localisation")

-- The client's language is a game API. It is hidden behind ns.ClientLocale so
-- that it can be set from here: without the substitution the set would check
-- the language of the machine it was run on.
local savedGetLocale = GetLocale

--- Load Core/Locale.lua with a given client language.
-- @param locale string|nil what GetLocale() will return; nil means the global is not there at all
-- @return table the namespace
local function load(locale)
    if locale == nil then
        GetLocale = nil
    else
        GetLocale = function() return locale end
    end

    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Locale.lua", ns)
    return ns
end

do
    local ns = load("enUS")
    T.ok(type(ns.Localize) == "function", "the translation function exists")
    T.ok(type(ns.L) == "table", "the translation table always exists")
    T.ok(type(ns.Locales) == "table", "the registry of locales exists")
end

T.suite("An English client: no translation is needed")

do
    local ns = load("enUS")
    -- Not one table is registered, and that is the norm: the key IS the
    -- finished English label.
    T.eq(ns.Localize("Interface Font"), "Interface Font", "the key is returned as it is")
    T.eq(ns.Localize("Apply the Author's Look"), "Apply the Author's Look",
         "a long label is returned as it is")
    T.eq(ns.Localize(nil), "", "a nil gives an empty string")
    T.eq(ns.Localize(""), "", "an empty key gives an empty string")
end

do
    -- An English client with Russian registered: the table is not chosen, and
    -- the Russian text must not seep through.
    local ns = load("enUS")
    ns.RegisterLocale("ruRU", { ["Fonts"] = "Шрифты" })
    T.eq(ns.Localize("Fonts"), "Fonts", "another locale does not replace the English")
end

T.suite("A Russian client: the translation is substituted")

do
    local ns = load("ruRU")
    ns.RegisterLocale("ruRU", { ["Fonts"] = "Шрифты" })
    T.eq(ns.locale, "ruRU", "the client's language was chosen")
    T.eq(ns.Localize("Fonts"), "Шрифты", "the translation was found")
    -- A key the table does not hold stays English and is therefore noticeable.
    T.eq(ns.Localize("Outline"), "Outline", "an untranslated key stays English")
end

do
    -- The load order: Core/Locale.lua chooses the language before the
    -- Locale/*.lua files manage to register. The registration is obliged to
    -- recompute the choice, or ns.L would stay empty until the end of the session.
    local ns = load("ruRU")
    T.eq(ns.Localize("Fonts"), "Fonts", "before the registration, English")
    ns.RegisterLocale("ruRU", { ["Fonts"] = "Шрифты" })
    T.eq(ns.Localize("Fonts"), "Шрифты", "after the registration, Russian")
end

do
    -- A language may be laid out across several files: the second
    -- registration adds to the first rather than overwriting it.
    local ns = load("ruRU")
    ns.RegisterLocale("ruRU", { ["Fonts"] = "Шрифты" })
    ns.RegisterLocale("ruRU", { ["Outline"] = "Контур" })
    T.eq(ns.Localize("Fonts"), "Шрифты", "the first record is alive")
    T.eq(ns.Localize("Outline"), "Контур", "the second record was added")
end

T.suite("An unfamiliar client: the English fallback")

do
    -- The locale is created but empty — that is what a language whose
    -- translation has only been started looks like. The fallback is obliged to
    -- lead into English rather than into a neighbouring locale.
    local ns = load("ukUA")
    ns.RegisterLocale("ruRU", { ["Fonts"] = "Шрифты" })
    ns.RegisterLocale("ukUA", {})
    T.eq(ns.locale, "ukUA", "the client's language was chosen")
    T.eq(ns.Localize("Fonts"), "Fonts", "an empty locale gives English rather than Russian")
end

do
    local ns = load("koKR")
    ns.RegisterLocale("ruRU", { ["Fonts"] = "Шрифты" })
    T.eq(ns.Localize("Fonts"), "Fonts", "a locale with no table gives English")
end

do
    -- Outside the game there is no GetLocale global. That is no reason to fall
    -- over at load: the whole set of checks rests on it.
    local ns = load(nil)
    T.eq(ns.ClientLocale(), nil, "without the game API the language is unknown")
    T.eq(ns.Localize("Fonts"), "Fonts", "and the interface stays English")
end

T.suite("ns.SetLocale")

do
    local ns = load("enUS")
    ns.RegisterLocale("ruRU", { ["Fonts"] = "Шрифты" })

    T.eq(ns.Localize("Fonts"), "Fonts", "before the change of language, English")
    ns.SetLocale("ruRU")
    T.eq(ns.Localize("Fonts"), "Шрифты", "after the change of language, Russian")
    ns.SetLocale(nil)
    T.eq(ns.Localize("Fonts"), "Fonts", "clearing the language restores English")
    T.eq(ns.locale, nil, "the language's name was cleared")
end

do
    -- Rubbish on the input must not break the addon's load: an unfamiliar
    -- name is handled the same way as the absence of a name.
    local ns = load("enUS")
    T.eq(type(ns.SetLocale(42)), "table", "a non-string language gives a table rather than an error")
    T.eq(ns.Localize("Fonts"), "Fonts", "and the interface stays English")

    ns.RegisterLocale(nil, { ["Fonts"] = "Ф" })
    ns.RegisterLocale("ruRU", "not a table")
    T.eq(ns.Locales.ruRU, nil, "a rubbish registration does not create a locale")
end

do
    -- An empty string in a translation table is not a translation but a gap:
    -- an empty label would look like a failure of the addon.
    local ns = load("ruRU")
    ns.RegisterLocale("ruRU", { ["Fonts"] = "" })
    T.eq(ns.Localize("Fonts"), "Fonts", "an empty translation is not shown")
end

GetLocale = savedGetLocale
