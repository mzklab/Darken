local helpers = require("helpers")
local localekeys = require("localekeys")

-- The completeness of the translations.
--
-- The English string from the call site serves as the translation key, which
-- means a typo in a key breaks nothing visible to the eye: the label simply
-- stays English. The only guard against that is comparing the list of keys
-- occurring in the code against the list of keys in the locale's table.
-- So the keys here are read out of the sources rather than rewritten by hand:
-- a rewritten list would diverge from the code at the very first edit.
--
-- Both shipped locales are checked identically: the rule "the translation is
-- complete" does not depend on the language, and a different set of checks
-- would mean one of the tables lives by rules of its own.

T.suite("The completeness of the translations")

-- The files ns.Localize occurs in.
--
-- The list is not rewritten by hand, and that is the main thing here. It used
-- to be a list of lines with a note saying "a new file is added here";
-- Core/Combat.lua did not get into it, and a key out of it went into the
-- delivery untranslated with a green set of checks. A line forgotten in a list
-- quenches a check entirely and quenches it silently — and a check that is
-- trusted and cannot fire is worse than a missing one.
--
-- So the list is assembled out of the delivery: the TOC enumerates every file
-- of the addon (otherwise the game will not read them), and a file holding at
-- least one ns.Localize gets here by itself. There is nowhere left to forget a
-- new file of the core: a file that is not in the TOC does not load in the game either.
local SOURCES = {}
do
    local toc = io.open("Darken.toc", "r")
    if not toc then error("Darken.toc did not open", 0) end

    for line in toc:lines() do
        -- A file's line in the TOC: "Folder\File.lua", with any number of
        -- segments and either slash — the game accepts both.
        local path = line:match("^([%w_][%w_%.%-\\/]*%.lua)%s*$")
        if path then
            path = path:gsub("\\", "/")
            local handle = io.open(path, "r")
            local text = handle and handle:read("*a") or ""
            if handle then handle:close() end

            -- Only the files where the translation is really called are taken:
            -- a file with no labels is of no use to the parse, and its absence
            -- hides nothing.
            -- The parts' files (the Features folder) are not taken here, and
            -- that is not a hole in the guard. Every part has a dictionary of
            -- its own — its own Locale/ruRU.lua — and the core does not hold
            -- it: a part's dictionary is handed to the core by its descriptor
            -- (handle:RegisterStrings) rather than rewritten into the shared
            -- one. A part's dictionary's completeness is checked by
            -- tests/test_optionwords.lua, one folder at a time, and demanding
            -- its lines of the core's dictionary would mean demanding one translation in two places.
            local mine = path:sub(1, #"Features/") ~= "Features/"
            -- Two marks rather than one. Only the files with a call of the
            -- translation used to be taken; the schema files do not call it —
            -- their labels lie in the label and hint fields and are translated
            -- by the window at the drawing — and they did not get into the parse at all.
            if mine and (text:find("ns%.Localize%(")
                or text:find("Schema%.Add%(")) then
                SOURCES[#SOURCES + 1] = path
            end
        end
    end
    toc:close()
end

-- The gathering itself is under check too: a broken parse of the TOC would
-- leave the list empty, and the translations' completeness would be checked against nothing.
T.ok(#SOURCES >= 18, "the files with labels were gathered out of the delivery: " .. #SOURCES)

-- The keys that need no translation. The addon's name is the same in any
-- language; translating it would mean renaming the addon.
local NO_TRANSLATION = {
    ["Darken"] = true,
}

-- The keys that arrive in ns.Localize as a variable rather than a literal: the
-- labels out of the GROUPS, CATEGORIES, OUTLINE_LABELS and NAME_MODES tables,
-- the "the value is not set" lines and the notes glued onto descriptions.
-- The list is short and changes rarely, but it has to exist: without it a hole
-- in those labels' translation would slip past the check.
local INDIRECT = {
    -- Config/Options.lua: ns.TAB_GROUPS — the labels of the column's
    -- containers and tabs. They arrive as a variable (spec.label), and without
    -- these lines a hole in their translation would slip past the check.
    "Gear", "Look", "Rules", "Item Level", "Durability",
    -- Modules/Darkness.lua: GROUPS
    "Unit Frames", "Action Bar Art", "Minimap", "Bags and Micro Menu",
    "Chat", "Objective Tracker", "Tooltips", "Character Sheet",
    "Buffs and Debuffs", "Other Addons' Windows",
    "Quest and Dialog Text",
    "Other Windows",
    -- Modules/Fonts.lua: CATEGORIES
    "Unit Names", "Bar Values", "Hotkeys and Counts", "Floating Combat Text",
    "Addon Window Text",
    -- Modules/Fonts.lua: OUTLINE_LABELS
    "No Outline", "Thin Outline", "Thick Outline", "Outline Without Antialiasing",
    -- Modules/Fonts.lua: the "the value is not set" lines
    "Game's Own Font", "Game's Own Outline", "Same as Global",
    -- Modules/UnitFrames.lua: NATIVE_BAR_LABEL, NAME_MODES, HEALTH_MODES
    -- and POWER_MODES
    "Game's Own Texture", "Game's Own Name Color", "By Class", "By Reaction",
    "Custom Color", "Game's Own Bar Color", "By Power Type",
    -- Modules/CastBar.lua: UNITS, TEXT_FORMATS and COLOR_MODES
    "Player Cast Bar", "Target Cast Bar", "Focus Cast Bar",
    "Game's Own Cast Text", "Spell Name", "Time Left",
    "Spell Name and Time Left",
    "Game's Own Cast Color", "Custom Cast Colors",
    -- Modules/Texts.lua: FORMATS and POSITIONS
    "Game's Own Bar Text", "Number", "Percent", "Number and Percent",
    "Game's Own Position", "Left Edge", "Center", "Right Edge",
    -- Modules/Fonts.lua: GLYPH_WARNING_KEY, the note on the font select's descriptions
    "Note: a font without glyphs for your client language shows text as "
        .. "empty boxes. LibSharedMedia cannot check glyphs, so such a font "
        .. "sits in the list next to the rest. If text disappears after you "
        .. "pick one, put the previous font back - no interface reload needed.",
    -- Modules/Fonts.lua: LOGOUT_NOTE_KEY, the note on the description of the
    -- world labels' font.
    "Note: the numbers floating over units are drawn by the world text "
        .. "engine, which reads the font file once, at login. A new font "
        .. "therefore shows up only after a full logout to character select - "
        .. "an interface reload is not enough. Size, outline, gravity and "
        .. "duration apply at once.",
    -- Modules/Fonts.lua: OWN_WINDOW_KEY, the note on the global tab about the
    -- addon's own window being outside the font settings' reach.
    "Darken's own settings window stays out of all of this on purpose: "
        .. "it is the tool you are changing the font with, and a window that "
        .. "resizes under your hands while you drag the slider is hard to "
        .. "steer and hard to get back. Everything else follows what you set "
        .. "here - the game's interface, and the windows Darken puts in "
        .. "its place, the bags window and the nameplates among them.",
    -- Modules/Fonts.lua: WINDOW_TEXT_KEY, the note on the tab of the windows'
    -- own text about the "subject of the setting / tool" boundary.
    "This covers the windows Darken draws in place of the game's own - "
        .. "the bags window and the item database among them. The settings "
        .. "window you are reading this in is not one of them: it is the "
        .. "tool, not the thing being set, and a window that reshapes itself "
        .. "while you adjust it is hard to steer. A window of a module picks "
        .. "this up when the module asks the core for it, so an older module "
        .. "may still be on the game's own font.",
    -- Modules/ActionBars.lua: BARS and BUTTON_STYLES.
    "Main Action Bar", "Bottom Left Bar", "Bottom Right Bar", "Right Bar",
    "Second Right Bar", "Pet Bar", "Stance Bar",
    "Game's Own Button Look", "Dark Buttons",
    -- Core/Presets.lua: the looks' labels and descriptions. They arrive in
    -- ns.Localize as a table's field rather than as a literal: the looks' file
    -- itself is loaded before the subsystems and stores English keys, while
    -- they are translated at the place of display (Config/Options.lua).
    "Classic Look", "Modern Look", "The Author's Look",
    "Our settings arranged to read as the game did in 1.x: bars and "
        .. "fonts left to the game, and dimming off - the interface back to "
        .. "the game's own brightness. It is not a restoration of the old "
        .. "window art - that is a separate, much larger piece of work. Each "
        .. "of the three looks says what the dimming slider should be, this "
        .. "one included: a look you press is the whole look, not the "
        .. "difference from what you had.",
    "Our settings arranged to read as the game does today: bars colored "
        .. "by class and power type, thin outline on text, and the dimming a "
        .. "fresh install comes with.",
    "The addon's own unit frame look: the health bar tinted by class "
        .. "color, the power bar by power type, and the dimming a fresh "
        .. "install comes with. Fonts and name color stay yours.",
    -- Modules/Darkness.lua: GROUPS, the nameplates' group. The key is shared
    -- with the nameplates' settings section.
    "Nameplates",
    -- Modules/UnitFrames.lua: UNITS — the frames' labels in the "these
    -- settings are for" list. They arrive in ns.Localize as a table's field:
    -- the list is assembled out of the same enumeration the application
    -- decides whose settings act on a frame by. Only "Party" is here: the
    -- other six labels are already translated as keys of other places, and a
    -- second spelling of the same word would make a translator guess what was meant.
    "Party",
    -- Modules/Darkness.lua: MODES — the labels of the areas' modes. They
    -- arrive in ns.Localize as a table's field: the dropdown is assembled out
    -- of the same enumeration the darkening is computed by.
    "Overall Strength", "Game's Own Look", "Dimmed", "Dark",
    "More Dark", "Darker", "Even Darker", "Black", "Class Color",
    -- Config/Demo.lua: INERT_KEY, the note on the samples' descriptions
    "This setting does nothing: the section exists to check appearance.",
    -- Config/Demo.lua: DISABLED_KEY, the description of the disabled twin. It
    -- arrives in ns.Localize as a variable for the same reason as INERT_KEY:
    -- the line is one for the whole section while there are many descriptions it gets into.
    "Disabled twin of the control above: this is what the disabled state "
        .. "looks like.",
    -- Core/Report.lua: CONSEQUENCE — the subsystems' labels in the report
    -- about the client. They arrive in ns.Localize as a table's field. Only
    -- the ones not above are here: the rest the report takes from the already
    -- translated labels of the settings window, because one and the same thing is obliged to be called the same.
    "Auras on Unit Frames", "Bag Windows", "Player Aura Grid",
    "Item Level on Equipment", "Raid Frames", "Action Bar Layout",
    "An Unnamed Group",
    -- Core/Tally.lua: COUNTERS — the labels of the counters of what was done.
    -- They arrive in ns.Localize as a table's field for the same reason as the labels above.
    "Objects Dimmed", "Objects Left As Content", "Bars Retextured",
    "Nameplates Attached", "Nameplates Taken By The Engine",
    "Auras Ruled On", "Positions Applied",
    "Containers Recorded", "Game Functions Hooked", "Hooks That Ran",
    "Work Deferred In Combat", "Deferred Work Carried Out",
    "Colours The Engine Refused", "Protected Actions Refused",
}

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Locale/ruRU.lua", ns)
helpers.loadAddonFile("Locale/ukUA.lua", ns)

-- We gather the keys out of the code.
local wanted, seen = {}, {}
local function want(key)
    if not seen[key] then
        seen[key] = true
        wanted[#wanted + 1] = key
    end
end

for i = 1, #SOURCES do
    local keys = localekeys.literal(localekeys.read(SOURCES[i]))
    for j = 1, #keys do want(keys[j]) end
end
for i = 1, #INDIRECT do want(INDIRECT[i]) end

T.ok(#wanted > 60, "the keys were read out of the sources: " .. #wanted)

-- A key is obliged to be English: a non-English key breaks the fallback, and
-- an English client would see a foreign label.
local nonAscii = {}
for i = 1, #wanted do
    if wanted[i]:find("[\128-\255]") then
        nonAscii[#nonAscii + 1] = wanted[i]
    end
end
T.eq(#nonAscii, 0, "every key is English: " .. table.concat(nonAscii, " | "))

--- Check one locale table's completeness.
-- @param locale string the locale's name
local function checkLocale(locale)
    local translations = ns.Locales[locale]
    T.ok(type(translations) == "table", locale .. ": the table is registered")
    if type(translations) ~= "table" then return end

    -- Every key is translated. A gap means a label left English — precisely
    -- the loss the rebuild must not cost.
    local missing = {}
    for i = 1, #wanted do
        local key = wanted[i]
        if not NO_TRANSLATION[key] and type(translations[key]) ~= "string" then
            missing[#missing + 1] = key
        end
    end
    T.eq(#missing, 0, locale .. ": left untranslated: "
        .. table.concat(missing, " | "))

    -- The reverse check: a record no call site leads to is a dead translation.
    -- Usually it is a typo in a key, and it looks like an English label in the
    -- game, that is, silent.
    local orphan = {}
    for key in pairs(translations) do
        if not seen[key] then orphan[#orphan + 1] = key end
    end
    T.eq(#orphan, 0, locale .. ": translations with no call site: "
        .. table.concat(orphan, " | "))

    -- A translation must not match its key: a match means the record was
    -- forgotten and left untranslated while it looks finished.
    local untranslated = {}
    for key, value in pairs(translations) do
        if value == key then untranslated[#untranslated + 1] = key end
    end
    T.eq(#untranslated, 0, locale .. ": records with no translation: "
        .. table.concat(untranslated, " | "))
end

checkLocale("ruRU")

T.suite("Locale/ukUA.lua translates everything the player sees")

checkLocale("ukUA")

-- The two tables are obliged to cover one and the same set of keys: a
-- divergence means a new label was translated into one language and forgotten in the other.
do
    local ru, uk = ns.Locales.ruRU, ns.Locales.ukUA
    local onlyRu, onlyUk = {}, {}
    for key in pairs(ru) do
        if uk[key] == nil then onlyRu[#onlyRu + 1] = key end
    end
    for key in pairs(uk) do
        if ru[key] == nil then onlyUk[#onlyUk + 1] = key end
    end
    T.eq(#onlyRu, 0, "present in Russian only: " .. table.concat(onlyRu, " | "))
    T.eq(#onlyUk, 0, "present in Ukrainian only: " .. table.concat(onlyUk, " | "))
end

-- The Ukrainian must not turn out to be a copy of the Russian: a matching line
-- would mean the Russian text was carried over instead of being translated.
do
    local ru, uk = ns.Locales.ruRU, ns.Locales.ukUA
    local same = {}
    for key, value in pairs(uk) do
        -- One-word labels may legitimately coincide ("Шрифт", "Контур"), so
        -- only long lines are compared.
        if #value > 40 and ru[key] == value then same[#same + 1] = key end
    end
    T.eq(#same, 0, "the Ukrainian repeats the Russian word for word: "
        .. table.concat(same, " | "))
end

T.suite("The client's language chooses the table")

ns.SetLocale("ukUA")
T.eq(ns.Localize("Fonts"), "Шрифти", "a Ukrainian client sees Ukrainian")

ns.SetLocale("ruRU")
T.eq(ns.Localize("Fonts"), "Шрифты", "a Russian client sees Russian")

ns.SetLocale("enUS")
T.eq(ns.Localize("Fonts"), "Fonts", "an English client sees English")

ns.SetLocale("koKR")
T.eq(ns.Localize("Fonts"), "Fonts", "a client with no table sees English")
