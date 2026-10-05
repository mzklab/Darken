local ADDON, ns = ...

-- Localisation of the addon's interface.
--
-- The base language is English, and the translation key is the English string
-- itself (see the spec, section 5.4). The main property follows from that: on
-- an English client no translation table is read at all — the key is already
-- the label. A locale is layered on top: its table overrides the keys it
-- contains, the rest stay English.
--
-- A Russian key would break that path: a player on an English client would
-- see Russian text with no way to change it.
--
-- Adding a language is one file in Locale/ and one line in four TOCs. Not a
-- single ns.Localize call site changes.

-- Registered translation tables: locale name -> table.
ns.Locales = {}

-- The empty table for English and for an unknown locale. Shared so as not to
-- breed garbage, and immutable by convention: ns.L is only read.
local EMPTY = {}

--- Register a translation table.
-- Called from the Locale/<locale>.lua files while the addon loads.
-- Registering the same locale again extends what is already there rather than
-- replacing it, so a language can be split across several files.
-- @param name string locale name as GetLocale() spells it, e.g. "ruRU"
-- @param translations table key (the English string) -> translation
function ns.RegisterLocale(name, translations)
    if type(name) ~= "string" or name == "" then return end
    if type(translations) ~= "table" then return end

    local existing = ns.Locales[name]
    if existing == nil then
        ns.Locales[name] = translations
    else
        for key, value in pairs(translations) do
            existing[key] = value
        end
    end

    -- A locale may be registered after the language was chosen: the choice
    -- then has to be recomputed, or ns.L would stay empty until the next
    -- SetLocale.
    if ns.locale == name then
        ns.L = ns.Locales[name]
    end
end

--- The client's language.
-- The only place in the addon that calls GetLocale(). Wrapped so that tests
-- can set the language, and so that the absence of the game API (running
-- outside the game) does not break loading.
-- @return string|nil the locale name, or nil if there is nobody to ask
function ns.ClientLocale()
    if type(GetLocale) ~= "function" then return nil end

    local ok, value = pcall(GetLocale)
    if not ok or type(value) ~= "string" or value == "" then return nil end

    return value
end

--- Choose the interface language.
-- An unknown locale is not an error: the addon stays English. That is the
-- fallback for whose sake English was chosen as the base language.
-- @param name string|nil the locale name
-- @return table the chosen translation table (empty for English)
function ns.SetLocale(name)
    ns.locale = type(name) == "string" and name or nil
    ns.L = (ns.locale and ns.Locales[ns.locale]) or EMPTY
    return ns.L
end

--- Translate a key.
-- The rule: a missing translation must not yield an empty string or nil — the
-- key is the English label, so an untranslated place stays readable and looks
-- like what it is rather than like a broken interface.
-- The exception is nil and "": there is nothing to translate, and both yield
-- "".
-- @param key string|nil the English key string
-- @return string the translation, the key itself when untranslated, "" for
--     nil and ""
function ns.Localize(key)
    if key == nil or key == "" then
        return ""
    end

    local translated = ns.L[key]
    if type(translated) == "string" and translated ~= "" then
        return translated
    end

    return key
end

-- The language is chosen while this file loads, before the modules assemble
-- their settings pages (some of them build labels at file scope). The
-- translation tables load next, in TOC order, and are picked up through
-- RegisterLocale.
ns.SetLocale(ns.ClientLocale())

-- Strings of the addon's parts and of third-party modules.
--
-- Why they are here. The core's dictionary does not belong to a module and is
-- not exposed — that is right. But the contract said nothing at all about
-- translating a module's own strings, and the first real module brought a
-- copy of this whole file: its own RegisterLocale, SetLocale and Localize. A
-- copy is a second language-selection rule that will diverge from ours
-- silently, and a second way to name the client's language where there must
-- be one.
--
-- So the model is exposed rather than the dictionary: a module declares its
-- own strings, while language selection and the "the key is the English
-- label" fallback stay with the core. Module tables are kept per name and
-- copied at declaration time: a module receives neither anybody else's
-- dictionary nor its own back — this door cannot write into the shared
-- table.
ns.ModuleStrings = {}

--- Declare a module's strings.
-- Declaring the same locale again extends what is already there rather than
-- replacing it: a module's language can be split across several files, as the
-- core's can.
-- Only a non-empty string counts as a translation — anything else is skipped
-- silently, because without it the key remains a readable English label.
-- @param name string the module's name
-- @param locale string locale name as GetLocale() spells it, e.g. "ruRU"
-- @param translations table key (the English string) -> translation
-- @return boolean whether the strings were accepted
function ns.RegisterModuleStrings(name, locale, translations)
    if type(name) ~= "string" or name == "" then return false end
    if type(locale) ~= "string" or locale == "" then return false end
    if type(translations) ~= "table" then return false end

    local byModule = ns.ModuleStrings[name]
    if byModule == nil then
        byModule = {}
        ns.ModuleStrings[name] = byModule
    end

    local table_ = byModule[locale]
    if table_ == nil then
        table_ = {}
        byModule[locale] = table_
    end

    for key, value in pairs(translations) do
        if type(key) == "string" and type(value) == "string" and value ~= "" then
            table_[key] = value
        end
    end

    return true
end

--- Translate a module's key.
-- The rule is the core's, and that is the point: an untranslated key stays
-- itself, that is, an English label, rather than becoming blank space. The
-- language is the core's too: two definitions of the client's language would
-- diverge, and a module would speak a different language from the settings
-- window.
-- @param name string the module's name
-- @param key string|nil the English key string
-- @return string
function ns.LocalizeFor(name, key)
    if key == nil or key == "" then return "" end
    if type(key) ~= "string" then return "" end

    local byModule = type(name) == "string" and ns.ModuleStrings[name] or nil
    local table_ = byModule and ns.locale and byModule[ns.locale]
    local translated = table_ and table_[key]
    if type(translated) == "string" and translated ~= "" then
        return translated
    end

    return key
end
