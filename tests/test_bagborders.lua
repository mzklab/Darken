local helpers = require("helpers")

-- The bag slots' border after "dark bags" went away.
--
-- The setting used to be part of the window's look: at the native look (the
-- default) the border was not drawn at all, and its own default — true —
-- meant "on, when there is something to switch on". The look went away, the
-- border became a setting in itself, and that same true would now mean "draw
-- a border round everybody's slots", including those who never had their
-- bags repainted. So the default moved to false, and migration 7 -> 8 writes
-- the border explicitly for those who did see it.
--
-- The step is a raw one, before copyDefaults, and that is not a choice
-- between two conveniences. After AceDB lays the defaults out, the "style"
-- key stands for everybody and "chose dark bags" is indistinguishable from
-- "never touched it". The key's absence is visible only in the raw SavedVariables table — and that is where the step works.

T.suite("the slots' border: the default and the storage path")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Skin/Draw.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Defaults.lua", ns)
helpers.loadAddonFile("Modules/Bags.lua", ns)

-- Not equality to eight: the eighth version is the one the border step was
-- created in, and the next edit of the storage shape will raise it again.
-- What has to be checked here is that the step exists and that the version
-- caught it, not that nobody stored anything after this task.
T.ok(ns.DB_VERSION >= 8, "the settings schema's version was raised")
T.ok(type(ns.Migrations[7]) == "function", "step 7 -> 8 is in place")
T.eq(ns.Bags.defaults.slotBorder, false, "a fresh install draws no border round a slot")
T.eq(ns.Bags.defaults.style, nil, "there is no bag look in the defaults any more")

-- The storage path is the one it was: bags.slotBorder. Moving the key would
-- have required a second migration, while a migration by value would not have
-- worked at all — AceDB cleans a value equal to the default out of the profile on leaving the game.
do
    ns.Addon = { db = { profile = { bags = { slotBorder = false } } } }
    local toggle = ns.Bags.options.args.slotBorder

    T.eq(toggle.get(), false, "the switch reads bags.slotBorder")
    toggle.set(nil, true)
    T.eq(ns.Addon.db.profile.bags.slotBorder, true, "and writes to the same place")
    T.eq(toggle.get(), true, "and reads it back")
    ns.Addon = nil
end

T.suite("the slots' border: migration 7 -> 8 by the key's presence")

local keep = ns.KeepBagBordersAsWas
T.eq(type(keep), "function", "the migration step is exposed")
T.eq(ns.RawMigrations[7], keep, "and stands as the seventh version's raw step")
T.eq(type(ns.Migrations[7]), "function", "the ordinary step 7 -> 8 is in place")

-- Somebody who never touched the bags at all: there is no section in the raw
-- profile, he never saw a border, and the new default gives him exactly the same.
do
    local profile = { version = 7 }
    keep(profile)
    T.eq(profile.bags, nil, "nothing was added to an untouched profile")
end

-- The window's native look: there is no "style" key in the raw profile,
-- because it equals the default. That player never saw a border once.
do
    local profile = { version = 7, bags = {} }
    keep(profile)
    T.eq(profile.bags.slotBorder, nil, "at the native look the border is not switched on")
end

-- Dark bags: the key is there, the player never switched the border off — so he saw it.
do
    local profile = { version = 7, bags = { style = "dark" } }
    keep(profile)
    T.eq(profile.bags.slotBorder, true, "the border was written for whoever chose dark bags")

    -- A second pass is harmless: the raw step goes over every saved profile
    -- at every entry into the game, until a profile's turn comes.
    keep(profile)
    T.eq(profile.bags.slotBorder, true, "a repeated pass writes the same thing")
end

-- Dark bags with the border switched off: the "slotBorder" key lies in the
-- profile as false, and that is exactly what the player chose.
do
    local profile = { version = 7, bags = { style = "dark", slotBorder = false } }
    keep(profile)
    T.eq(profile.bags.slotBorder, false, "a border switched off stayed switched off")
end

-- Rubbish instead of a profile does not bring the entry into the game down.
do
    T.ok(pcall(keep, nil), "a nil is not an error")
    T.ok(pcall(keep, { bags = "a string" }), "nor is an alien value of the section")
end

T.suite("the slots' border: the raw pass over every saved profile")

do
    local sv = {
        profiles = {
            ["Player - Realm"] = { version = 7, bags = { style = "dark" } },
            ["Second"]      = { version = 7, bags = {} },
            ["Fresh"]       = {},
            ["New"]         = { version = 8, bags = {} },
        },
    }
    ns.MigrateStoredProfiles(sv, ns.RawMigrations, ns.DB_VERSION)

    T.eq(sv.profiles["Player - Realm"].bags.slotBorder, true,
        "the border was written for dark bags")
    T.eq(sv.profiles["Second"].bags.slotBorder, nil,
        "and not for the native look")
    T.eq(sv.profiles["Fresh"].bags, nil,
        "a profile with no version counts as fresh and is skipped")
    T.eq(sv.profiles["New"].bags.slotBorder, nil,
        "the raw pass does not touch a profile of the current version")
end

-- And the ordinary ladder brings a profile to the current version with no
-- gaps: MigrateProfile does not forgive a step that is missing.
do
    local profile = { version = 7, bags = { style = "dark" } }
    ns.MigrateProfile(profile, ns.Migrations, ns.DB_VERSION)
    T.eq(profile.version, ns.DB_VERSION, "the version was raised to the current one")
    T.eq(profile.bags.slotBorder, true, "and the border was written by the second step")
end
