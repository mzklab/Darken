local helpers = require("helpers")

-- The looks (presets).
--
-- Two subjects the file is written for, and both about the promise made to
-- the player in the button's description.
--
-- The first: a preset names only settings that exist. A setting that does not
-- exist silently goes nowhere — more precisely, it goes into the profile as
-- rubbish while the look does not change. In the client that looks like "the
-- button half works", and it has to be worked out by eye.
--
-- The second: a preset changes exactly what it enumerated and nothing more.
-- That is not a question of tidiness: if it wrote a whole section, the font or
-- the darkening the player chose would vanish at a press of a button that said
-- nothing about them.

local savedLibStub = LibStub
local fakeMedia = {
    List    = function() return {} end,
    IsValid = function() return false end,
    Fetch   = function() return nil end,
}
LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return fakeMedia end
    return nil
end

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Events.lua", ns)
helpers.loadAddonFile("Core/Combat.lua", ns)
helpers.loadAddonFile("Core/Media.lua", ns)
helpers.loadAddonFile("Core/Defaults.lua", ns)
helpers.loadAddonFile("Core/Presets.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)
helpers.loadAddonFile("Modules/Fonts.lua", ns)
helpers.loadAddonFile("Modules/UnitFrames.lua", ns)
helpers.loadAddonFile("Modules/NamePlates.lua", ns)

LibStub = savedLibStub

T.suite("the looks: the contents")

T.ok(type(ns.PRESETS) == "table", "the table of looks is defined")
T.ok(#ns.PRESETS >= 3, "there are no fewer than three looks: " .. #ns.PRESETS)

do
    local seen = {}
    local dupes = {}
    for i = 1, #ns.PRESETS do
        local preset = ns.PRESETS[i]
        T.ok(type(preset.key) == "string" and preset.key ~= "",
            "look " .. i .. " has a key")
        T.ok(type(preset.label) == "string" and preset.label ~= "",
            "the look \"" .. tostring(preset.key) .. "\" has a label")
        T.ok(type(preset.desc) == "string" and preset.desc ~= "",
            "the look \"" .. tostring(preset.key) .. "\" has a description")
        T.ok(type(preset.values) == "table",
            "the look \"" .. tostring(preset.key) .. "\" has values")
        if seen[preset.key] then dupes[#dupes + 1] = preset.key end
        seen[preset.key] = true
    end
    T.eq(#dupes, 0, "the looks' keys do not repeat: "
        .. table.concat(dupes, ", "))
end

-- Our own look takes its sections from the same set the profile's migration
-- refers to: not copies of the sections but the very same tables. The set
-- itself, meanwhile, does not belong to it — the preset has a darkening of its
-- own while the migration must not have one: it would reset a slider for the
-- player it was never asked about.
do
    local author = ns.GetPreset("author")
    T.ok(author ~= nil, "our own look is in place")

    for section, values in pairs(ns.Recommended) do
        T.eq(author.values[section], values,
            "the set's section is taken by reference rather than as a copy: " .. tostring(section))
    end

    T.eq(ns.Recommended.darkness, nil,
        "and no darkening was added to the shared set")
    T.eq(type(author.values.darkness), "table",
        "while the preset has one of its own")
end

T.ok(ns.GetPreset("classic") ~= nil, "the classic look is in place")
T.ok(ns.GetPreset("modern") ~= nil, "the modern look is in place")
T.eq(ns.GetPreset("no such thing"), nil, "an unfamiliar key gives no look")

T.suite("the looks: the native-look markers are written down correctly")

-- A preset is loaded before the modules and writes the markers literally. A
-- divergence from a subsystem would mean a preset that silently fails to
-- restore the native look: a string no list knows would end up in the profile.
do
    local native, inherit = 0, 0
    local function walk(values)
        for _, value in pairs(values) do
            if type(value) == "table" then walk(value)
            elseif value == ns.UnitFrames.NATIVE then native = native + 1
            elseif value == ns.Fonts.INHERIT then inherit = inherit + 1
            end
        end
    end
    for i = 1, #ns.PRESETS do walk(ns.PRESETS[i].values) end

    T.ok(native > 0, "the native-look marker occurs in the looks: " .. native)
    T.ok(inherit > 0, "the \"as in the game\" marker occurs in the looks: " .. inherit)
end

T.suite("the looks: only settings that exist are named")

-- The defaults of every subsystem, gathered the same way the core gathers
-- them: section -> table of defaults.
local defaults = ns.Registry:CollectDefaults("defaults")

do
    local unknown = {}

    --- Whether a path exists in the defaults.
    local function exists(node, path, from)
        local current = node
        for i = from, #path do
            if type(current) ~= "table" then return false end
            current = current[path[i]]
            if current == nil then return false end
        end
        return true
    end

    local function walk(section, node, values, prefix)
        for key, value in pairs(values) do
            local path = prefix .. "." .. tostring(key)
            -- A setting's value is sometimes false (a switch), so
            -- "and ... or nil" is unusable here: a false would turn into a
            -- nil, and a setting that exists would be declared non-existent.
            local target
            if type(node) == "table" then target = node[key] end

            if target == nil then
                unknown[#unknown + 1] = path
            elseif type(value) == "table" then
                walk(section, target, value, path)
            end
        end
    end

    for i = 1, #ns.PRESETS do
        local preset = ns.PRESETS[i]
        for section, values in pairs(preset.values) do
            local node = defaults[section]
            if type(node) ~= "table" then
                unknown[#unknown + 1] = preset.key .. ": " .. section
            else
                walk(section, node, values, preset.key .. ": " .. section)
            end
        end
    end

    T.eq(#unknown, 0, "every setting of the looks exists: "
        .. table.concat(unknown, " | "))
    T.ok(exists(defaults, { "unitframes", "health" }, 1),
        "the path check itself works")
end

T.suite("the looks: the textures' names are real")

-- A typo in a texture's name does not fail: an unknown name silently leaves
-- the native bar, and "apply the look" does half of what it promised.
do
    local textures = ns.Media.Textures()
    local bad = {}
    for i = 1, #ns.PRESETS do
        local preset = ns.PRESETS[i]
        for section, fields in pairs(ns.PRESET_TEXTURE_FIELDS) do
            local values = preset.values[section]
            for j = 1, #fields do
                local name = values and values[fields[j]]
                if type(name) == "string" and name ~= ns.UnitFrames.NATIVE
                    and textures[name] == nil then
                    bad[#bad + 1] = preset.key .. ": " .. name
                end
            end
        end
    end
    T.eq(#bad, 0, "the textures' names are in the addon's set: "
        .. table.concat(bad, " | "))
end

T.suite("the looks: exactly what is enumerated changes")

--- A fresh profile out of the subsystems' defaults.
-- A copy rather than the shared tables: applying a look edits the profile, and
-- spoiling the defaults would spoil the next check.
local function freshProfile()
    local function copy(source)
        local out = {}
        for key, value in pairs(source) do
            if type(value) == "table" then out[key] = copy(value)
            else out[key] = value end
        end
        return out
    end
    return copy(defaults)
end

--- Gather all a table's leaves into a flat dictionary of "path -> value".
local function flatten(node, prefix, out)
    out = out or {}
    for key, value in pairs(node) do
        local path = (prefix == "" and tostring(key))
            or (prefix .. "." .. tostring(key))
        if type(value) == "table" then
            flatten(value, path, out)
        else
            out[path] = value
        end
    end
    return out
end

for i = 1, #ns.PRESETS do
    local preset = ns.PRESETS[i]

    local profile = freshProfile()
    local before = flatten(profile, "")

    ns.ApplyPreset(profile, preset)

    local after = flatten(profile, "")

    -- What the look promised to change.
    local promised = {}
    local changes = ns.PresetChanges(preset)
    for j = 1, #changes do promised[changes[j].path] = changes[j].value end

    -- Not one setting beyond what was promised.
    local extra = {}
    for path, value in pairs(after) do
        if before[path] ~= value and promised[path] == nil then
            extra[#extra + 1] = path
        end
    end
    T.eq(#extra, 0, preset.key .. ": nothing extra was touched: "
        .. table.concat(extra, " | "))

    -- Not one setting vanished.
    local lost = {}
    for path in pairs(before) do
        if after[path] == nil then lost[#lost + 1] = path end
    end
    T.eq(#lost, 0, preset.key .. ": nothing went missing: "
        .. table.concat(lost, " | "))

    -- Everything promised is in place.
    local wrong = {}
    for path, value in pairs(promised) do
        if after[path] ~= value then
            wrong[#wrong + 1] = string.format("%s (%s instead of %s)", path,
                tostring(after[path]), tostring(value))
        end
    end
    T.eq(#wrong, 0, preset.key .. ": what was promised was applied: "
        .. table.concat(wrong, " | "))

    T.ok(#changes > 0, preset.key .. ": the look changes something: " .. #changes)
end

T.suite("the looks: the application")

-- A look can be named by its key: that is how the button in the "General" section calls it.
do
    local profile = freshProfile()
    T.eq(ns.ApplyPreset(profile, "modern"), true, "the look was applied by its key")
    T.eq(profile.unitframes.healthColor, "class", "the value out of the look went on")

    T.eq(ns.ApplyPreset(profile, "no such thing"), false,
        "an unfamiliar key is not applied")
    T.eq(ns.ApplyPreset(nil, "modern"), false, "with no profile there is nothing to apply to")
end

-- A look does not create a section the profile does not hold: a key with no
-- subsystem is read by nobody anyway, while in SavedVariables it would stay forever.
do
    local bare = { unitframes = { health = "__native" } }
    ns.ApplyPreset(bare, "classic")
    T.eq(bare.fonts, nil, "no section is created for a subsystem that is not there")
    T.eq(bare.nameplates, nil, "nor a second one")
    T.eq(bare.unitframes.health, "__native", "a section that exists was applied")
end

-- A look's nested table is not put into the profile by reference: otherwise an
-- edit of one profile would change both the look itself and every profile after it.
do
    local profile = freshProfile()
    ns.ApplyPreset(profile, "modern")
    local preset = ns.GetPreset("modern")

    T.ok(profile.unitframes ~= preset.values.unitframes,
        "the nested table was copied rather than shared")

    profile.fonts.global.outline = "spoiled"
    T.eq(preset.values.fonts.global.outline, "OUTLINE",
        "the look was not spoiled by an edit of the profile")
end

T.suite("the looks: the list of changes")

-- The list is assembled out of the same table the look applies and cannot
-- diverge from it. That is the whole point: the button's description is
-- obliged to name exactly what the button changes.
do
    local preset = ns.GetPreset("classic")
    local changes = ns.PresetChanges(preset)

    local sorted = true
    for i = 2, #changes do
        if changes[i - 1].path >= changes[i].path then sorted = false end
    end
    T.ok(sorted, "the list is sorted by the setting's path")

    local found = false
    for i = 1, #changes do
        if changes[i].path == "unitframes.health" then found = true end
    end
    T.ok(found, "a nested setting is named by its full path")

    local summary = ns.PresetSummary(preset)
    local lines = 0
    for _ in summary:gmatch("[^\n]+") do lines = lines + 1 end
    T.eq(lines, #changes, "there are as many lines in the list as there are changes")

    T.ok(summary:find("unitframes.health", 1, true) ~= nil,
        "the list names the settings by their names in the profile")
end

T.eq(#ns.PresetChanges(nil), 0, "an empty look has no list")
T.eq(ns.PresetSummary(nil), "", "nor a line")

-- Three markers are translated into words, the rest is shown as it is.
-- A texture's name meanwhile is never translated: it is a key of the
-- LibSharedMedia registry and a value in SavedVariables.
ns.SetLocale("enUS")
T.eq(ns.PresetValueText("__native"), "Game's Own", "the native look in words")
T.eq(ns.PresetValueText("__inherit"), "Game's Own", "\"as in the game\" the same way")
T.eq(ns.PresetValueText(true), "On", "switched on, in a word")
T.eq(ns.PresetValueText(false), "Off", "switched off, in a word")
T.eq(ns.PresetValueText(12), "12", "a number as it is")
T.eq(ns.PresetValueText("Darken Dark"), "Darken Dark", "a texture's name is not translated")

