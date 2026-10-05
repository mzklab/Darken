local helpers = require("helpers")

T.suite("Defaults")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Defaults.lua", ns)

T.ok(type(ns.DB_VERSION) == "number", "the schema's version is set as a number")
T.ok(type(ns.BaseDefaults.profile) == "table", "the profile section exists")
-- version must not be a default value: AceDB cleans everything equal to a
-- default out of the profile, the version would never reach SavedVariables,
-- and the migrations would silently fail to run when DB_VERSION was raised.
T.eq(ns.BaseDefaults.profile.version, nil, "version is not declared as a default")

-- Every step from the first version to the current one is obliged to have a
-- migration. Raising DB_VERSION with no migration gives an error already in
-- the game, at the first load of an old profile — that is, at the player's end rather than here.
do
    local gaps = {}
    for v = 1, ns.DB_VERSION - 1 do
        if type(ns.Migrations[v]) ~= "function" then
            gaps[#gaps + 1] = tostring(v)
        end
    end
    T.eq(#gaps, 0, "the chain of migrations has no gaps: " .. table.concat(gaps, ", "))
end

T.suite("the recommended look")

T.ok(type(ns.Recommended) == "table", "the set of the recommended look is defined")
T.ok(type(ns.Recommended.unitframes) == "table", "the set holds the unit frames")

do
    local profile = { unitframes = {
        health = "__native", power = "__native", scale = 1.1,
    } }
    ns.ApplyRecommended(profile)
    T.eq(profile.unitframes.health, "Darken Purple", "the health texture out of the set")
    T.eq(profile.unitframes.power, "Darken Blue", "the power texture out of the set")
    T.eq(profile.unitframes.scale, 1.1, "the set does not touch anything else")
end

-- The set does not create a section the profile does not hold: a key with no
-- subsystem is read by nobody and would stay as rubbish in SavedVariables.
do
    local bare = {}
    ns.ApplyRecommended(bare)
    T.eq(bare.unitframes, nil, "no section is created for a subsystem that is not there")
end

T.suite("migration 1 -> 2: the native look became the default")

-- Whoever never changed the texture saw ours, but it was not in
-- SavedVariables: AceDB cleans everything equal to a default out of the
-- profile. After the default was raised such a profile would have got the
-- native bar unasked — the migration gives it back exactly what it saw.
do
    local seen = { version = 1, unitframes = {
        health = "__native", power = "__native", nameColor = "__native",
    } }
    ns.MigrateProfile(seen, ns.Migrations, ns.DB_VERSION)
    T.eq(seen.version, ns.DB_VERSION, "the profile was brought to the current version")
    T.eq(seen.unitframes.health, "Darken Purple", "the former health bar came back")
    T.eq(seen.unitframes.power, "Darken Blue", "the former power bar came back")
    T.eq(seen.unitframes.nameColor, "class", "the former name colour came back")
end

-- Migration 1 -> 2 does not touch the player's explicit choice: only
-- "__native" falls under its condition. A profile carries its own texture name
-- further on, where migration 2 -> 3 renames it — the choice itself is kept in the process.
do
    local chosen = { version = 1, unitframes = {
        health = "Umbra красная", power = "Umbra зелёная", nameColor = "fixed",
    } }
    ns.MigrateProfile(chosen, ns.Migrations, ns.DB_VERSION)
    T.eq(chosen.unitframes.health, "Darken Red", "the chosen texture was kept")
    T.eq(chosen.unitframes.power, "Darken Green", "and so was the second chosen one")
    T.eq(chosen.unitframes.nameColor, "fixed", "the chosen name mode was kept")
end

-- A fresh install has no version: the migration does not run, and the native
-- look stays native.
do
    local fresh = { unitframes = { health = "__native" } }
    ns.MigrateProfile(fresh, ns.Migrations, ns.DB_VERSION)
    T.eq(fresh.unitframes.health, "__native", "a fresh install is left with the native look")
end

-- A profile with no unit frames section survives the migration.
do
    local noUF = { version = 1 }
    ns.MigrateProfile(noUF, ns.Migrations, ns.DB_VERSION)
    T.eq(noUF.version, ns.DB_VERSION, "a profile with no section was brought to the version")
end

T.suite("migration 1 -> 2: \"__native\" is the default, and the step fires all the same")

-- The trap migration 3 -> 4's comment warns about: a step written as "if the
-- field equals the default" never fires once, because AceDB cleans everything
-- equal to a default out of SavedVariables. Step 1 -> 2 is written exactly
-- that way — "if health equals __native" — and "__native" IS that field's
-- default today (Modules/UnitFrames.lua).
--
-- The trap is nevertheless avoided, and avoided not by accident. The
-- difference lies in the moment. Step 3 -> 4 needed to know "the player chose
-- this", that is, to tell the absence of a key from a value; such knowledge
-- lives only in the raw SavedVariables, and that is why the step looks at the
-- key's presence. Step 1 -> 2 needs the opposite — "the player did not choose
-- this" — and ns.Migrations work over db.profile, that is, already after
-- AceDB:copyDefaults (Core/Init.lua). By that instant the key's absence has
-- turned into today's default, and equality to it is an exact statement of
-- that very "did not choose". And "__native" itself was impossible in schema
-- 1: before d546854 our own texture stood as the default, and the "native" entry did not exist in the select list at all.
--
-- The check holds that whole linkage. Moving step 1 into ns.RawMigrations —
-- to where the key does not yet exist — would make it dead, and the check's
-- second half would go red.
do
    local uf = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", uf)
    helpers.loadAddonFile("Core/Compat.lua", uf)
    helpers.loadAddonFile("Core/Locale.lua", uf)
    helpers.loadAddonFile("Core/Registry.lua", uf)
    helpers.loadAddonFile("Core/Events.lua", uf)
    helpers.loadAddonFile("Core/Combat.lua", uf)
    helpers.loadAddonFile("Modules/UnitFrames.lua", uf)

    local declared = uf.Registry:CollectDefaults("defaults").unitframes
    T.eq(declared.health, "__native",
        "\"__native\" is the declared default of the health field")

    --- What AceDB does before the migrations: lay the defaults out across the profile.
    -- @param profile table the raw SavedVariables table
    -- @param defaults table the section's defaults
    -- @return table the same profile
    local function copyDefaults(profile, defaults)
        profile.unitframes = profile.unitframes or {}
        for key, value in pairs(defaults) do
            if profile.unitframes[key] == nil then
                profile.unitframes[key] = value
            end
        end
        return profile
    end

    -- The raw saved data of somebody playing on schema 1: it says nothing
    -- about the texture, because he never changed it, and the default then was ours.
    local raw = { version = 1 }

    -- First the dead branch: over the raw table the step finds nothing, and
    -- that is exactly the trap in question. There is no key, so there is nothing to compare against.
    local rawOnly = { version = 1 }
    ns.Migrations[1](rawOnly)
    T.eq(rawOnly.unitframes, nil,
        "over the raw saved data the step finds nothing: the key is not there")

    -- And now the path it goes in the game: copyDefaults first, then the
    -- migration. The player is left with the look he had.
    copyDefaults(raw, declared)
    T.eq(raw.unitframes.health, "__native",
        "after copyDefaults the profile's silence became today's default")

    ns.MigrateProfile(raw, ns.Migrations, ns.DB_VERSION)
    T.eq(raw.unitframes.health, "Darken Purple",
        "and step 1 -> 2 gave the player his former bar back")
    T.eq(raw.unitframes.nameColor, "class",
        "and his former name colour")
end

T.suite("MigrateProfile")

-- A profile of the current version passes straight through unchanged.
local current = { version = 1, keep = "as it was" }
local out = ns.MigrateProfile(current, {}, 1)
T.eq(out.version, 1, "the version did not change")
T.eq(out.keep, "as it was", "the data was not lost")

-- The chain of migrations runs in order, from the old version to the target one.
local trace = {}
local migrations = {
    [1] = function(p) trace[#trace + 1] = "1->2"; p.added = "two" end,
    [2] = function(p) trace[#trace + 1] = "2->3"; p.added = p.added .. "+three" end,
}
local old = { version = 1 }
local migrated = ns.MigrateProfile(old, migrations, 3)
T.eq(#trace, 2, "both migrations ran")
T.eq(trace[1], "1->2", "the first one first")
T.eq(trace[2], "2->3", "then the second")
T.eq(migrated.version, 3, "the version was brought to the target one")
T.eq(migrated.added, "two+three", "the changes of both migrations are in place")

-- A profile with no version counts as the very first one.
local legacy = ns.MigrateProfile({}, {}, 1)
T.eq(legacy.version, 1, "a profile with no version gets the current one")

-- The round trip: a fresh profile assembled out of BaseDefaults (which holds
-- no version) went through MigrateProfile — and the version appeared in it. It
-- is precisely that record that survives removeDefaults and reaches SavedVariables.
local fresh = {}
for k, v in pairs(ns.BaseDefaults.profile) do fresh[k] = v end
T.eq(fresh.version, nil, "before the migration there is no version in the profile")
ns.MigrateProfile(fresh, ns.Migrations, ns.DB_VERSION)
T.eq(fresh.version, ns.DB_VERSION, "after the migration the profile is stamped with the version")

-- We do not touch a profile from the future: the user may have rolled the
-- addon back, and "fixing" his settings after the fact is more dangerous than leaving them as they are.
local future = ns.MigrateProfile({ version = 99, x = 1 }, migrations, 3)
T.eq(future.version, 99, "the version from the future was kept")
T.eq(future.x, 1, "the data from the future is untouched")

-- A skipped migration must not break the chain quietly.
T.err(function()
    ns.MigrateProfile({ version = 1 }, { [1] = function() end }, 3)
end, "a gap in the chain of migrations gives an error")
