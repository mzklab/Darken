local helpers = require("helpers")

-- The darkening's default: a high value for a fresh install and the former
-- look for whoever is already playing.
--
-- What the file is written for. This is the only place in the addon where a
-- fresh install changes the game's look by itself, and the cost of a mistake
-- here is visible to the eye: somebody who asked for nothing gets a darkened screen at his next login.
--
-- The trap is exactly the one the version field is absent from the defaults
-- for. On leaving the game AceDB cleans everything equal to a default out of
-- the profile, and the default was zero. Which means "never touched the
-- slider" and "deliberately set zero" look the same in SavedVariables — like
-- nothing — and after the default was raised both would have got the new
-- value. A migration written as "if amount == 0 then..." would never have
-- fired once: there is no such key in the saved data. So it looks at the key's
-- presence and looks where that presence is still visible — into the raw SavedVariables table, before the database is created (ns.RawMigrations).
--
-- The library here is the real one — Libs/AceDB-3.0. A fake would check our
-- notions of it, while the whole case rests on its rules.

--============================================================================
-- The pure half: the migrations themselves, with no game and no library.
--============================================================================

T.suite("the darkening's default: migration 4 -> 5")

local pure = helpers.newNamespace()
helpers.loadAddonFile("Core/Defaults.lua", pure)

T.ok(pure.DB_VERSION >= 5, "the schema's version is no lower than the one that created the step")
T.eq(type(pure.RawMigrations[4]), "function", "the raw step 4 -> 5 is declared")
T.eq(type(pure.Migrations[4]), "function", "and the ordinary step is beside it")

-- Somebody who touched nothing: the darkening section is not in the saved data
-- at all. The former default — zero — is written for him, and that is the
-- answer to "what a silent profile gets": it is left with the look it has
-- rather than getting a new one.
do
    local sv = { profiles = { Default = { version = 4 } } }
    pure.MigrateStoredProfiles(sv, pure.RawMigrations, pure.DB_VERSION)

    T.eq(sv.profiles.Default.darkness.amount, 0,
        "a profile that stayed silent got the former zero written explicitly")

    -- The raw pass does not touch the version: one owner sets it, and the
    -- ordinary migration's steps would otherwise be skipped.
    T.eq(sv.profiles.Default.version, 4, "the raw pass does not raise the version")

    -- A repeated pass is harmless: it runs at every entry into the game until
    -- a profile's turn comes to become the active one.
    pure.MigrateStoredProfiles(sv, pure.RawMigrations, pure.DB_VERSION)
    pure.MigrateStoredProfiles(sv, pure.RawMigrations, pure.DB_VERSION)
    T.eq(sv.profiles.Default.darkness.amount, 0, "and the second pass changes nothing")
end

-- Somebody who chose a value of his own: this step does not touch him.
--
-- The number does change, and it is the next step, 6 -> 7, that changes it:
-- the slider's scale has changed since then, and the former values are
-- converted to it by a multiplication by seven tenths — so that the look stays
-- the same (tests/test_darkscale.lua). A profile of version 4 passes both
-- steps in a row, so what is visible here is their product rather than one of them.
do
    local sv = { profiles = {
        Dark = { version = 4, darkness = { amount = 35 } },
        Full = { version = 4, darkness = { amount = 100, tint = { r = 0.5 } } },
    } }
    pure.MigrateStoredProfiles(sv, pure.RawMigrations, pure.DB_VERSION)

    T.eq(sv.profiles["Dark"].darkness.amount, 25,
        "the chosen value is in place, converted to the current scale")
    T.eq(sv.profiles["Full"].darkness.amount, 70,
        "the scale's former floor landed on its present division")
    T.eq(sv.profiles["Full"].darkness.tint.r, 0.5, "the tint is untouched")
end

-- A fresh profile has no version, and the raw pass skips it: editing a past
-- that does not exist would mean taking the new default away from a newcomer.
do
    local sv = { profiles = { Default = {} } }
    pure.MigrateStoredProfiles(sv, pure.RawMigrations, pure.DB_VERSION)
    T.eq(sv.profiles.Default.darkness, nil, "the raw pass does not touch a fresh profile")
end

-- A profile from the future (the addon rolled back to an older build) is not touched either.
do
    local sv = { profiles = { Default = { version = 99 } } }
    pure.MigrateStoredProfiles(sv, pure.RawMigrations, pure.DB_VERSION)
    T.eq(sv.profiles.Default.darkness, nil, "a profile newer than the target version is untouched")
end

-- Rubbish on the input does not bring the load down: the table arrives from SavedVariables.
do
    T.eq(pure.MigrateStoredProfiles(nil, pure.RawMigrations, 5), nil,
        "with no saved table the pass stays silent")
    local sv = { profiles = "not a table" }
    T.eq(pure.MigrateStoredProfiles(sv, pure.RawMigrations, 5), sv,
        "and with rubbish instead of profiles too")
end

--============================================================================
-- A stand-in client: exactly as much as AceDB asks for at load.
--============================================================================

local saved = {
    CreateFrame = _G.CreateFrame,
    GetRealmName = _G.GetRealmName,
    UnitFactionGroup = _G.UnitFactionGroup,
    UnitName = _G.UnitName,
    UnitClass = _G.UnitClass,
    UnitRace = _G.UnitRace,
    GetLocale = _G.GetLocale,
    GetBuildInfo = _G.GetBuildInfo,
    GetCurrentRegionName = _G.GetCurrentRegionName,
    GetCurrentRegion = _G.GetCurrentRegion,
    strlenutf8 = _G.strlenutf8,
    LibStub = _G.LibStub,
}

local logoutFrame

_G.CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript(key, fn)
        if key == "OnEvent" then
            self.onEvent = fn
            logoutFrame = self
        end
    end
    return frame
end

_G.GetRealmName          = function() return "Test Realm" end
_G.UnitFactionGroup      = function() return "Alliance" end
_G.UnitName              = function() return "Check" end
_G.UnitClass             = function() return "Mage", "MAGE" end
_G.UnitRace              = function() return "Human", "Human" end
_G.GetLocale             = function() return "enUS" end
_G.GetBuildInfo          = function() return "1.15.7", "69977", "date", 11507 end
_G.GetCurrentRegionName  = function() return "EU" end
_G.GetCurrentRegion      = function() return 3 end
_G.strlenutf8            = function(text) return #text end
_G.LibStub               = nil

dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
dofile("Libs/AceDB-3.0/AceDB-3.0.lua")

local AceDB = LibStub("AceDB-3.0")

local ns = helpers.newNamespace()
local FILES = {
    "Core/Skin.lua",
    "Core/Compat.lua",
    "Core/Locale.lua",
    "Core/Registry.lua",
    "Core/Defaults.lua",
    "Modules/Darkness.lua",
}
for i = 1, #FILES do helpers.loadAddonFile(FILES[i], ns) end

--- One entry into the game: exactly the sequence that stands in Core/Init.lua.
-- The order here IS the subject of the check: the raw migrations are obliged to
-- run before AceDB lays the defaults out across the profile.
-- @param sv table the table of saved variables
-- @return table the settings database
local function login(sv)
    AceDB.db_registry = {}
    ns.MigrateStoredProfiles(sv, ns.RawMigrations, ns.DB_VERSION)
    local db = AceDB:New(sv, ns.BuildDefaults(ns.Registry), true)
    ns.MigrateProfile(db.profile, ns.Migrations, ns.DB_VERSION)
    return db
end

--- Leaving the game: the library's own handler rather than a retelling of it.
local function logout()
    logoutFrame.onEvent(logoutFrame, "PLAYER_LOGOUT")
end

--============================================================================
-- A fresh install: the new value, and it survives leaving the game.
--============================================================================

T.suite("the darkening's default: a fresh install")

do
    local sv = {}
    local db = login(sv)

    T.eq(db.profile.darkness.amount, 80,
        "a fresh install is darkened to eighty")

    logout()
    local again = login(sv)
    T.eq(again.profile.darkness.amount, 80, "and after leaving the game too")

    -- Zero is reachable and stays chosen: a default has no right to come back
    -- over the player's choice.
    again.profile.darkness.amount = 0
    logout()
    local third = login(sv)
    T.eq(third.profile.darkness.amount, 0, "a chosen zero came back as a zero")
    T.eq(third.profile.version, ns.DB_VERSION, "the schema's version is in place")
end

--============================================================================
-- Somebody who is already playing: the screen does not darken by itself.
--============================================================================

T.suite("the darkening's default: an update for somebody playing")

-- A profile of version 4 with no darkening section IS both "never touched the
-- slider" and "deliberately set zero" at once: they cannot be told apart in
-- the saved data. Both get a zero, that is, the look they have on their screen now.
do
    local sv = {
        profiles = { Default = { version = 4, unitframes = { health = "Darken Dark" } } },
        profileKeys = {},
    }
    local db = login(sv)

    T.eq(db.profile.darkness.amount, 0,
        "a profile that stayed silent got the former look rather than the new default")
    T.eq(db.profile.unitframes.health, "Darken Dark", "the other settings are untouched")
    T.eq(db.profile.version, ns.DB_VERSION, "the profile was brought to the current version")

    -- The zero lies in the saved data explicitly: it no longer equals the
    -- default, and AceDB cannot clean it out.
    logout()
    T.eq(sv.profiles.Default.darkness.amount, 0, "the zero was written into the saved data")

    local again = login(sv)
    T.eq(again.profile.darkness.amount, 0, "and the second login changed nothing")
end

-- Whoever chose a non-zero value of his own keeps it. The same full circle is
-- checked: the migration, a load, leaving, a load.
do
    local sv = {
        profiles = { Default = { version = 4, darkness = { amount = 35 } } },
        profileKeys = {},
    }
    local db = login(sv)
    T.eq(db.profile.darkness.amount, 25,
        "the chosen value survived the migration, converted to the current scale")

    logout()
    local again = login(sv)
    T.eq(again.profile.darkness.amount, 25, "and survived leaving the game too")
end

-- Somebody who never touched the slider at all. AceDB cleaned his key out on
-- leaving the game (the value equalled the default), and he cannot be told
-- apart in any way from somebody who chose exactly that default for himself:
-- in the saved data both look the same — like nothing. Both get the current
-- default, and that is the author's decision rather than an oversight: what
-- was in his old plugin was to be the default. The full circle with the real library: a login, leaving, a second login.
do
    local sv = {
        profiles = { Default = { version = 6, movers = { locked = false } } },
        profileKeys = {},
    }
    local db = login(sv)

    T.eq(db.profile.darkness.amount, 80,
        "a profile with no key got the current default")
    T.ok(ns.Darkness.Factor(db.profile.darkness.amount)
        < ns.Darkness.EDGE_FACTOR,
        "that is, darker than the scale's former edge")

    logout()
    T.eq(sv.profiles.Default.darkness, nil,
        "and it was cleaned out again: the value equals the default")

    local again = login(sv)
    T.eq(again.profile.darkness.amount, 80, "the second login gives the same thing")
end

-- A profile whose turn has not come yet: another one is active, and nobody
-- raised its version. The raw pass is obliged to reach it too, or by the
-- moment of the switch the raw data will no longer exist.
do
    local sv = {
        profiles = {
            Default = { version = 4 },
            Spare = { version = 4 },
        },
        profileKeys = {},
    }
    login(sv)

    T.eq(sv.profiles["Spare"].darkness.amount, 0,
        "an inactive profile kept the former look too")
    T.eq(sv.profiles["Spare"].version, 4,
        "and nobody forged its version")
end

--============================================================================
-- The stand-ins are removed: the next set must see neither them nor the library.
--============================================================================

AceDB.db_registry = {}
local STUBBED = {
    "CreateFrame", "GetRealmName", "UnitFactionGroup", "UnitName",
    "UnitClass", "UnitRace", "GetLocale", "GetBuildInfo",
    "GetCurrentRegionName", "GetCurrentRegion", "strlenutf8", "LibStub",
}
for i = 1, #STUBBED do _G[STUBBED[i]] = saved[STUBBED[i]] end
