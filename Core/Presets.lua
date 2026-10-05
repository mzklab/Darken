local ADDON, ns = ...

-- Look presets: a set of values for our own settings, applied in one action.
--
-- A preset is a table of "section -> settings" and nothing more. It has no
-- storage of its own, no application path of its own and no memory of the
-- previous look: it writes ordinary settings the ordinary way
-- (ns.ApplySettingValues, Core/Defaults.lua), after which application follows
-- the one path there is — ns.Registry:ApplyAll. A second settings mechanism
-- beside the first would diverge from it at the very first change, and the
-- player would see a setting that "reads one way and works another".
--
-- The main property follows from that. A preset does not switch the addon
-- into a mode of its own and is not remembered: it puts values into the
-- profile once. Everything it wrote stays ordinary settings — visible in the
-- window, changeable one at a time, and each of them has the game's native
-- look as its first choice. There is no one-way street here and no separate
-- "undo" button either: returning to a whole previous set is what profiles
-- are for (the Profiles page), and returning one setting is that setting.
--
-- What a preset touches is what its table names. A setting absent from the
-- table is untouched at any depth of nesting: a player who chose their own
-- font or dimming keeps them after the Classic look, if the preset does not
-- speak about them.

-- The markers for "the game's native look" and "not set". The strings are
-- written here literally rather than taken from the subsystems: this file
-- loads before Modules/, and a reference to ns.UnitFrames.NATIVE would be
-- nil. A test checks that they match (tests/test_presets.lua) — a divergence
-- would mean a preset that silently fails to restore the native look.
local NATIVE  = "__native"
local INHERIT = "__inherit"

--- A preset's dimming section: the amount, and every area set to "follow".
--
-- Why EVERY preset has one, not only the classic look.
--
-- Dimming used to be touched by one preset out of three: the classic one put
-- the slider at zero, while the modern and the author's looks did not touch
-- it at all — "the player sets the level of darkness themselves". That
-- sounded reasonable, and on screen it looked like this: the author pressed
-- all three buttons in a row and wrote "they all just reset the state, there
-- is no difference between them".
--
-- And they are right. The first press of the classic look switched dimming
-- off, and neither of the other two could bring it back: they are about bars
-- and fonts. The interface stayed light whatever was pressed, and the three
-- buttons differed by settings invisible on a light screen.
--
-- So a preset describes a look IN FULL rather than the difference from what
-- was there. That is what the word "look" means: press it and get what was
-- promised, regardless of what stood before. The slider has not gone
-- anywhere: the player moves it afterwards as much as they like.
--
-- The areas are listed by name rather than as an empty table: the values are
-- merged in (ns.ApplySettingValues), and an empty table would erase nothing.
-- The list mirrors GROUPS in Modules/Darkness.lua, and a test guards against
-- divergence (tests/test_darkareas.lua).
--
-- @param amount number the dimming amount
-- @return table the darkness section for a preset
local function Darkening(amount)
    return {
        amount = amount,
        mode = {
            unitframe        = "follow",
            nameplate        = "follow",
            ["actionbar-art"] = "follow",
            minimap          = "follow",
            auras            = "follow",
            bags             = "follow",
            chat             = "follow",
            objectives       = "follow",
            tooltip          = "follow",
            character        = "follow",
            questlog         = "follow",
            window           = "follow",
            addons           = "follow",
        },
    }
end

--- The classic look.
--
-- These are our own settings arranged so that the interface reads as old,
-- rather than a restoration of the 1.x interface: that is a separate item in
-- the work queue ("a full restoration of the classic interface") and costs an
-- order of magnitude more.
--
-- Hence the contents. The gryphons stay — the game draws them itself, and
-- they were there in 1.x. Bars and fonts are handed back to the game: our
-- gradient and our outline read as modern, and no choice of colour makes them
-- "classic". There is no dimming — a dark interface is a device of recent
-- years. The action bar is one row of twelve buttons at the native size with
-- tight spacing: that is how it stood in 1.x, as one piece rather than three
-- drifted-apart groups.
--
-- The zero in dimming became work rather than confirmation once the default
-- was raised (Modules/Darkness.lua): it used to match the default and changed
-- nothing for most players, and now it switches dimming off. The value is
-- deliberately untouched — a preset describes the look it leads to rather
-- than a shift from what stands now, and the classic look without dimming
-- stayed the same look.
--
-- The change of the slider's scale (migration 6 -> 7) does not touch this
-- zero from any side: zero on any scale means the game's native look and
-- stays zero. No preset names any other dimming number.
local CLASSIC = {
    unitframes = {
        health      = NATIVE,
        healthColor = NATIVE,
        power       = NATIVE,
        powerColor  = NATIVE,
        nameColor   = NATIVE,
    },
    nameplates = {
        health      = NATIVE,
        healthColor = NATIVE,
        nameColor   = NATIVE,
    },
    fonts = {
        -- No preset touches the font size: zero in that setting means "as
        -- in the game", and in the list of changes it would read as a size of
        -- zero. A setting that cannot be put into words does not belong in
        -- the list — all the more so when the preset never meant to change
        -- it.
        global = { font = INHERIT, outline = INHERIT },
    },
    -- Dimming is reset both by the slider and by the areas' modes, and the
    -- second is not there for tidiness. The slider governs only those areas
    -- whose mode is "follow"; an area the player moved to "More Dark" would
    -- stay dark, and the classic look would promise native brightness while
    -- delivering half of it. A preset that promises something other than what
    -- it does is the same trouble that got dimming removed from the modern
    -- look.
    --
    -- The modes are listed by name rather than as an empty table: a preset
    -- merges its values in (ns.ApplySettingValues), and an empty table would
    -- erase nothing. The list mirrors GROUPS in Modules/Darkness.lua, and a
    -- test guards against divergence (tests/test_darkareas.lua).
    darkness = Darkening(0),
}

--- The modern look.
--
-- How the game looks today: no gryphons, dark buttons, bars coloured by class
-- and by power type, text with a thin outline, the chrome muted. The numbers
-- here are not copied from another client and could not be — they are our own
-- settings; what was copied is the direction, not the values.
--
-- Dimming is not in the set, and the reason is stated in the table itself, in
-- the place where it once stood.
local MODERN = {
    unitframes = {
        health      = "Darken Dark",
        healthColor = "class",
        power       = "Darken Dark",
        powerColor  = "power",
        nameColor   = "class",
    },
    nameplates = {
        health      = "Darken Dark",
        healthColor = "class",
        nameColor   = "class",
    },
    fonts = {
        global = { font = INHERIT, outline = "OUTLINE" },
    },
    -- Dimming is the same as in a fresh installation. It used not to be here
    -- at all, and the reason was stated as "the player sets the level of
    -- darkness themselves". The reason is right, the conclusion drawn from it
    -- was wrong — see Darkening.
    darkness = Darkening(64),
}

-- The author's look: the core's recommended set plus dimming.
--
-- The values are taken from ns.Recommended (Core/Defaults.lua) rather than
-- copied here: the set is older than the presets, a profile migration refers
-- to it, and two copies would diverge at the first change. Adding dimming
-- into it directly is ruled out for the same reason — the profile migration
-- would reset a slider for the player that nobody asked it to touch.
--
-- So there is a table of its own here, assembled from references to the set's
-- sections: a change in Core/Defaults.lua is visible here too, while dimming
-- lives only in the preset.
local AUTHOR = { darkness = Darkening(64) }
for section, values in pairs(ns.Recommended) do
    AUTHOR[section] = values
end

-- The presets in display order. An array rather than a map: the order of the
-- buttons is set here, and the classic look comes first — it changes the
-- least and is closest to what the player already sees.
--
-- The author's look takes its values from ns.Recommended (Core/Defaults.lua)
-- rather than copying them here: the set is older than the presets, a profile
-- migration refers to it, and two copies would diverge at the first change.
--
-- The labels are English translation keys, and they are translated where they
-- are displayed rather than here: this file loads before the modules add
-- their own labels, and storing a finished string would freeze the language
-- as of the moment the file was read.
ns.PRESETS = {
    {
        key    = "classic",
        label  = "Classic Look",
        desc   = "Our settings arranged to read as the game did in 1.x: " ..
                 "bars and fonts left to the game, and dimming off - the " ..
                 "interface back to the game's own brightness. It is not a " ..
                 "restoration of the old window art - that is a separate, " ..
                 "much larger piece of work. Each of the three looks says " ..
                 "what the dimming slider should be, this one included: a " ..
                 "look you press is the whole look, not the difference " ..
                 "from what you had.",
        values = CLASSIC,
    },
    {
        key    = "modern",
        label  = "Modern Look",
        desc   = "Our settings arranged to read as the game does today: " ..
                 "bars colored by class and power type, thin outline on " ..
                 "text, and the dimming a fresh install comes with.",
        values = MODERN,
    },
    {
        key    = "author",
        label  = "The Author's Look",
        desc   = "The addon's own unit frame look: the health bar tinted " ..
                 "by class color, the power bar by power type, and the " ..
                 "dimming a fresh install comes with. Fonts and name color " ..
                 "stay yours.",
        values = AUTHOR,
    },
}

--- A preset, by its key.
-- @param key any
-- @return table|nil
function ns.GetPreset(key)
    if type(key) ~= "string" then return nil end
    for i = 1, #ns.PRESETS do
        if ns.PRESETS[i].key == key then return ns.PRESETS[i] end
    end
    return nil
end

--- A setting's value as the player reads it.
--
-- The addon's three markers — the game's native look, "as above" and a
-- switch — in words; everything else as it is. A texture's name is never
-- translated: it is a key in the LibSharedMedia registry and a value in
-- SavedVariables (see Core/Media.lua).
--
-- @param value any
-- @return string
function ns.PresetValueText(value)
    if value == NATIVE or value == INHERIT then
        return ns.Localize("Game's Own")
    end
    if value == true  then return ns.Localize("On")  end
    if value == false then return ns.Localize("Off") end
    return tostring(value)
end

--- The list of settings a preset changes.
--
-- Returns "path -> value" pairs in alphabetical order of the path. The path
-- is written the way the setting lies in the profile ("unitframes.health"),
-- and that is not laziness: a button's description must name exactly what the
-- button changes, and a name assembled from the table cannot diverge from it
-- — unlike one rewritten by hand.
--
-- A pure function: it reads nothing from the profile or from the game.
--
-- @param preset table|nil the preset
-- @return table array of { path = string, value = any }
function ns.PresetChanges(preset)
    local out = {}
    if type(preset) ~= "table" or type(preset.values) ~= "table" then
        return out
    end

    local function walk(prefix, values)
        for key, value in pairs(values) do
            local path = prefix .. "." .. tostring(key)
            if type(value) == "table" then
                walk(path, value)
            else
                out[#out + 1] = { path = path, value = value }
            end
        end
    end

    for section, values in pairs(preset.values) do
        if type(values) == "table" then walk(tostring(section), values) end
    end

    table.sort(out, function(a, b) return a.path < b.path end)
    return out
end

--- A preset's changes, one line per setting.
-- @param preset table|nil
-- @return string
function ns.PresetSummary(preset)
    local changes = ns.PresetChanges(preset)
    local lines = {}
    for i = 1, #changes do
        lines[i] = string.format("%s = %s", changes[i].path,
            ns.PresetValueText(changes[i].value))
    end
    return table.concat(lines, "\n")
end

--============================================================================
-- The question asked before applying
--============================================================================

-- The settings areas under human names.
--
-- Why this became necessary. The question before applying used to name a
-- number — "replaces 19 settings, listed in the tooltip". A number tells the
-- player nothing, and the tooltip hangs on a button in the settings window:
-- in a modal dialog it is not on screen at all, and the player was sent to
-- look where they cannot. Deciding "apply or not" has to be possible without
-- leaving the dialog, so the question names not a count but the places on
-- screen that will change.
--
-- The translation keys are the ones the settings window's own entries carry:
-- the same place on screen must be called the same thing in the question and
-- in the settings. They are translated while the text is assembled rather
-- than here: this file loads before the locale tables.
--
-- "Entries" rather than "top-level sections": the list names what the preset
-- changes rather than where it lies in the settings. Whether that coincides
-- with how the column is arranged today is the column's question, not the
-- player's.
--
-- The darkness key is named by its page's label, "Interface Darkness",
-- rather than by the slider inside it: a preset moves both the slider and the
-- tint, that is, changes the whole page.
local AREA_LABELS = {
    unitframes = "Unit Frames",
    nameplates = "Nameplates",
    fonts      = "Fonts",
    darkness   = "Interface Darkness",
}

-- The order the areas are listed in. Set here rather than by sorting: the
-- player reads the list top to bottom, and the order must be the same for
-- every preset, or two questions in a row look like they are about different
-- things.
local AREA_ORDER = {
    "unitframes", "nameplates", "fonts", "darkness",
}

--- The areas a preset touches, in words.
--
-- A pure function. An area that found no name here enters the list under its
-- own key rather than disappearing: a preset that grew a new area must name
-- it to the player somehow — silence here would mean a question that lies
-- about its own consequences.
--
-- @param preset table|nil
-- @return table array of strings
function ns.PresetAreas(preset)
    local out = {}
    if type(preset) ~= "table" or type(preset.values) ~= "table" then
        return out
    end

    local named = {}
    for i = 1, #AREA_ORDER do
        local key = AREA_ORDER[i]
        if type(preset.values[key]) == "table" then
            named[key] = true
            out[#out + 1] = ns.Localize(AREA_LABELS[key])
        end
    end

    local rest = {}
    for key, value in pairs(preset.values) do
        if type(value) == "table" and not named[key] then
            rest[#rest + 1] = tostring(key)
        end
    end
    table.sort(rest)
    for i = 1, #rest do out[#out + 1] = rest[i] end

    return out
end

--- The text of the question asked before a preset is applied.
--
-- Three short paragraphs, and nothing more belongs in a modal dialog: a
-- dialog that has to be re-read is worse than one that said less.
--
-- The first names the preset. The second says what will change and that
-- everything else stays as it is: that is the answer to the player's only
-- question, "will I lose my setting". The third names the way back: a copy of
-- the profile made before the experiment is the real insurance, and a preset
-- offers no other (see the note at the top of this file).
--
-- The third paragraph begins with "cancel", and that is not politeness. The
-- dialog is modal: while it is on screen the Profiles page is unreachable and
-- the advice to copy the profile cannot be followed. Advice that is correct
-- and impossible to follow at the very moment it is given is worse than
-- silence — so it names the one action it becomes possible from: cancelling
-- this question.
--
-- A pure function: it reads nothing from the profile or from the game.
--
-- @param preset table|nil the preset, or its key
-- @return string an empty string when there is nothing to name
function ns.PresetConfirmText(preset)
    if type(preset) == "string" then preset = ns.GetPreset(preset) end
    if type(preset) ~= "table" then return "" end

    local areas = ns.PresetAreas(preset)
    if #areas == 0 then return "" end

    -- The list is comma-separated with no conjunction: a conjunction would
    -- need a translation entry of its own, and in a language with a different
    -- word order it would land in the wrong place. A comma reads the same
    -- everywhere.
    return string.format(ns.Localize("Apply \"%s\"?"),
               ns.Localize(preset.label))
        .. "\n\n"
        .. string.format(ns.Localize("It changes %s. Every other setting " ..
               "stays as it is."), table.concat(areas, ", "))
        .. "\n\n"
        .. ns.Localize("To keep your current look, cancel and copy the " ..
               "profile first in the Profiles section.")
end

--- Apply a preset to a profile.
-- The application path is the one a setting changed by hand takes: the values
-- go into the profile and then the registry is called. A preset has no
-- application of its own.
-- @param profile table the settings profile
-- @param preset table|nil the preset, or its key
-- @return boolean whether it was applied
function ns.ApplyPreset(profile, preset)
    if type(preset) == "string" then preset = ns.GetPreset(preset) end
    if type(profile) ~= "table" or type(preset) ~= "table" then return false end
    if type(preset.values) ~= "table" then return false end

    ns.ApplySettingValues(profile, preset.values)
    return true
end
