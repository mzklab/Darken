local helpers = require("helpers")

T.suite("migration 2 -> 3: the textures' names became English")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Defaults.lua", ns)

-- The names are written out here literally rather than taken from the
-- migration table: a test that reads the same table as the code checks only
-- that table against itself. The old spelling is a record of history, and
-- diverging from it is not allowed: having diverged, the migration will stop recognising old profiles.
local RENAMED = {
    { old = "Umbra бирюзовая", new = "Darken Cyan"   },
    { old = "Umbra жёлтая",    new = "Darken Yellow" },
    { old = "Umbra зелёная",   new = "Darken Green"  },
    { old = "Umbra красная",   new = "Darken Red"    },
    { old = "Umbra оранжевая", new = "Darken Orange" },
    { old = "Umbra розовая",   new = "Darken Pink"   },
    { old = "Umbra синяя",     new = "Darken Blue"   },
    { old = "Umbra сиреневая", new = "Darken Purple" },
    { old = "Umbra тёмная",    new = "Darken Dark"   },
}

T.eq(#RENAMED, 9, "all nine of the addon's textures were renamed")

-- Every old name is obliged to get its new one — both on the health bar and
-- on the power bar: both settings store a texture's name.
for i = 1, #RENAMED do
    local pair = RENAMED[i]
    local profile = { version = 2, unitframes = {
        health = pair.old, power = pair.old, nameColor = "class", scale = 1.2,
    } }
    ns.MigrateProfile(profile, ns.Migrations, ns.DB_VERSION)
    T.eq(profile.unitframes.health, pair.new,
        "\"" .. pair.old .. "\" -> \"" .. pair.new .. "\" on the health")
    T.eq(profile.unitframes.power, pair.new,
        "\"" .. pair.old .. "\" -> \"" .. pair.new .. "\" on the power")
    T.eq(profile.unitframes.scale, 1.2, "the migration does not touch anything else")
    T.eq(profile.unitframes.nameColor, "class", "nor the name's colour")
end

T.suite("migration 2 -> 3: somebody else's is not fixed")

-- The native-look marker does not stand for a texture's name and is not
-- subject to renaming: the player asked for the bar not to be replaced at all.
do
    local native = { version = 2, unitframes = {
        health = "__native", power = "__native",
    } }
    ns.MigrateProfile(native, ns.Migrations, ns.DB_VERSION)
    T.eq(native.unitframes.health, "__native", "the native look stayed native")
    T.eq(native.unitframes.power, "__native", "and on the second bar too")
end

-- A name out of somebody else's texture set and a merely unfamiliar value
-- pass straight through: the addon did not write them and is not entitled to fix them.
do
    local foreign = { version = 2, unitframes = {
        health = "Blizzard Raid Bar", power = "Darken Unknown",
    } }
    ns.MigrateProfile(foreign, ns.Migrations, ns.DB_VERSION)
    T.eq(foreign.unitframes.health, "Blizzard Raid Bar",
        "a name out of somebody else's set was not touched")
    T.eq(foreign.unitframes.power, "Darken Unknown",
        "an unfamiliar value was not touched")
end

-- A profile with no unit frames section survives the migration and creates no section.
do
    local bare = { version = 2 }
    ns.MigrateProfile(bare, ns.Migrations, ns.DB_VERSION)
    T.eq(bare.version, ns.DB_VERSION, "the profile was brought to the current version")
    T.eq(bare.unitframes, nil, "no section was created for a subsystem that is not there")
end

T.suite("migration 2 -> 3: a repeated pass is harmless")

-- The new names are not keys of the translation table, so a second pass over
-- an already renamed profile changes nothing. The function itself is what is
-- checked: MigrateProfile would not call the step a second time anyway — the
-- version is already the target one — while carrying a profile between builds can arrange such a repeat.
do
    local profile = { unitframes = { health = "Umbra сиреневая", power = "Umbra синяя" } }
    ns.RenameTextures(profile)
    T.eq(profile.unitframes.health, "Darken Purple", "the first pass renamed it")
    ns.RenameTextures(profile)
    T.eq(profile.unitframes.health, "Darken Purple", "the second pass changed nothing")
    ns.RenameTextures(profile)
    T.eq(profile.unitframes.power, "Darken Blue", "nor did the third")
end

-- MigrateProfile does not run the step again on a profile already converted.
do
    local done = { version = 3, unitframes = { health = "Darken Purple" } }
    ns.MigrateProfile(done, ns.Migrations, ns.DB_VERSION)
    T.eq(done.version, ns.DB_VERSION, "the version is in place")
    T.eq(done.unitframes.health, "Darken Purple", "the value was not touched")
end

T.suite("migration 2 -> 3: the new names match the registry")

-- The migration moves a profile onto names that may be absent from the
-- addon's set: a typo here gives neither an error nor an empty bar — the
-- choice simply will not be found, and the bar will silently become the native one.
helpers.loadAddonFile("Core/Media.lua", ns)

do
    local textures = ns.Media.Textures()
    local missing = {}
    for i = 1, #RENAMED do
        if textures[RENAMED[i].new] == nil then
            missing[#missing + 1] = RENAMED[i].new
        end
    end
    T.eq(#missing, 0,
        "every new name is in the set: " .. table.concat(missing, "; "))

    -- And the other way round: no name is left in the set that the migration does not know.
    local known = {}
    for i = 1, #RENAMED do known[RENAMED[i].new] = true end
    local orphans = {}
    for name in pairs(textures) do
        if not known[name] then orphans[#orphans + 1] = name end
    end
    T.eq(#orphans, 0,
        "the migration knows every texture of the set: " .. table.concat(orphans, "; "))
end
