local helpers = require("helpers")

-- Whether a setting survives leaving the game.
--
-- Why this set exists. Settings are lost silently: the player moves a slider,
-- sees the change on the screen, leaves — and comes back to the former value.
-- No error, no yellow line, no trace in the chat. There is only one way to
-- notice it — to check every setting separately, and nobody does that until
-- they lose one of their own.
--
-- So what is checked here is neither one setting nor "the mechanism in
-- general". Here the WHOLE declared set of defaults is taken
-- (ns.BuildDefaults, Core/Defaults.lua) and every field of it is run through
-- the full circle: write a value other than the default -> leave the game ->
-- a new load out of what landed in SavedVariables -> read it back.
-- A setting added tomorrow gets into the check by itself, without an edit of
-- this file: the walk goes over the table of defaults rather than over a list of names.
--
-- The library here is the real one — Libs/AceDB-3.0. A fake would check our
-- notions of it, while the settings were lost on its rules precisely:
-- removeDefaults on PLAYER_LOGOUT cleans out of the profile everything equal
-- to a declared default, while copyDefaults at load puts the default back. A
-- value the player chose himself is obliged to pass between those two
-- millstones whole.

T.suite("the settings survive leaving the game")

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

-- The frame AceDB hangs PLAYER_LOGOUT on. We keep it separately: leaving the
-- game is reproduced by calling that very handler rather than by our own copy
-- of its body — a copy would diverge from the library at its first update.
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

--============================================================================
-- The addon: the core and every subsystem out of Modules/, in TOC order.
--============================================================================

local ns = helpers.newNamespace()
local FILES = {
    "Core/Compat.lua",
    "Core/Skin.lua",
    "Core/Registry.lua",
    "Core/Defaults.lua",
    "Core/Presets.lua",
    "Core/Locale.lua",
    "Core/Frames.lua",
    "Core/Events.lua",
    "Core/Combat.lua",
    "Core/Media.lua",
    "Core/Format.lua",
    "Modules/Darkness.lua",
    "Modules/Fonts.lua",
    "Modules/UnitFrames.lua",
    "Modules/NamePlates.lua",
    "Modules/Texts.lua",
    "Modules/Bags.lua",
}
for i = 1, #FILES do
    helpers.loadAddonFile(FILES[i], ns)
end

local defaults = ns.BuildDefaults(ns.Registry)

T.ok(type(defaults.profile) == "table", "the defaults build returns the profile section")
T.ok(type(defaults.global) == "table", "and the global section")
T.ok(defaults.profile.darkness ~= nil, "a subsystem's section got into the defaults")
T.eq(defaults.profile.version, nil, "version is not declared as a default")

--============================================================================
-- The walk over the defaults: every field is one setting.
--============================================================================

-- A value deliberately different from the default and of the same type. The
-- type is kept deliberately: replacing a number with a string would check the store rather than the setting.
-- @param value any the default
-- @return any|nil a nil means "such a field is not checked"
local function unlike(value)
    if type(value) == "number"  then return value + 7 end
    if type(value) == "boolean" then return not value end
    if type(value) == "string"  then return value .. "-check" end
    return nil
end

--- Walk the defaults in depth, yielding every value field.
-- @param source table the table of defaults
-- @param path string the path accumulated from above
-- @param sink function (path, key, defaults, value)
local function walk(source, path, sink)
    for key, value in pairs(source) do
        local here = path == "" and tostring(key)
            or (path .. "." .. tostring(key))
        if type(value) == "table" then
            walk(value, here, sink)
        else
            sink(here, key, source, value)
        end
    end
end

--- Reach a table by a path, creating the missing links.
-- @param root table
-- @param path string a path of the form "a.b.c"
-- @return table|nil the table the last link lies in
-- @return string the last link's key
local function reach(root, path)
    local parts = {}
    for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end

    local node = root
    for i = 1, #parts - 1 do
        local nested = node[parts[i]]
        if type(nested) ~= "table" then
            nested = {}
            node[parts[i]] = nested
        end
        node = nested
    end
    return node, parts[#parts]
end

--- Read a value by a path without creating anything.
-- @param root table
-- @param path string
-- @return any
local function peek(root, path)
    local node = root
    for part in path:gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

--============================================================================
-- The first circle: what the player chose comes back the same.
--============================================================================

do
    local sv = {}

    -- The first session: the player changes every setting he has.
    local db = AceDB:New(sv, defaults, true)
    ns.MigrateProfile(db.profile, ns.Migrations, ns.DB_VERSION)

    local chosen = {}
    walk(defaults.profile, "", function(path, _, _, value)
        local want = unlike(value)
        if want == nil then return end
        local node, key = reach(db.profile, path)
        node[key] = want
        chosen[path] = want
    end)

    local globals = {}
    walk(defaults.global, "", function(path, _, _, value)
        local want = unlike(value)
        if want == nil then return end
        local node, key = reach(db.global, path)
        node[key] = want
        globals[path] = want
    end)

    local counted = 0
    for _ in pairs(chosen) do counted = counted + 1 end
    T.ok(counted > 20, string.format(
        "the whole set of settings got into the check (%d were found)", counted))

    -- Leaving the game: that very handler of the library rather than a retelling of it.
    T.ok(logoutFrame ~= nil, "AceDB hung a handler for leaving the game")
    logoutFrame.onEvent(logoutFrame, "PLAYER_LOGOUT")

    -- The second session: a new database over what landed in SavedVariables.
    AceDB.db_registry = {}
    local fresh = AceDB:New(sv, ns.BuildDefaults(ns.Registry), true)
    ns.MigrateProfile(fresh.profile, ns.Migrations, ns.DB_VERSION)

    local lost = {}
    for path, want in pairs(chosen) do
        if peek(fresh.profile, path) ~= want then
            lost[#lost + 1] = path
        end
    end
    table.sort(lost)
    T.eq(#lost, 0, "the profile: not one setting was lost — "
        .. table.concat(lost, ", "))

    local lostGlobal = {}
    for path, want in pairs(globals) do
        if peek(fresh.global, path) ~= want then
            lostGlobal[#lostGlobal + 1] = path
        end
    end
    table.sort(lostGlobal)
    T.eq(#lostGlobal, 0, "the shared section: not one setting was lost — "
        .. table.concat(lostGlobal, ", "))

    -- The schema's version is obliged to survive into SavedVariables: the
    -- whole chain of migrations rests on it. It is absent from the defaults for precisely that reason.
    T.eq(sv.profiles.Default.version, ns.DB_VERSION,
        "the schema's version survived into the saved data")
    T.eq(fresh.profile.version, ns.DB_VERSION,
        "and was read back the same")
end

--============================================================================
-- The second circle: a fresh install changes nothing.
--============================================================================

do
    local sv = {}
    local db = AceDB:New(sv, ns.BuildDefaults(ns.Registry), true)
    ns.MigrateProfile(db.profile, ns.Migrations, ns.DB_VERSION)

    -- The player touched nothing.
    logoutFrame.onEvent(logoutFrame, "PLAYER_LOGOUT")

    AceDB.db_registry = {}
    local fresh = AceDB:New(sv, ns.BuildDefaults(ns.Registry), true)

    local wrong = {}
    walk(defaults.profile, "", function(path, _, _, value)
        if peek(fresh.profile, path) ~= value then
            wrong[#wrong + 1] = path
        end
    end)
    table.sort(wrong)
    T.eq(#wrong, 0, "a fresh install reads every default as its own — "
        .. table.concat(wrong, ", "))
end

--============================================================================
-- The third circle: a default chosen by hand stays chosen.
--============================================================================

-- A value equal to the default AceDB cleans out of the saved data — and that
-- holds exactly as long as the default does not change. Then the player's
-- choice silently becomes the new default, and that is the very defect the
-- version field is absent from ns.BaseDefaults for. What is checked here is a
-- more modest promise but the one the player looks at: having chosen the
-- default, he gets it back rather than something else.
do
    local sv = {}
    local db = AceDB:New(sv, ns.BuildDefaults(ns.Registry), true)
    ns.MigrateProfile(db.profile, ns.Migrations, ns.DB_VERSION)

    walk(defaults.profile, "", function(path, _, _, value)
        local node, key = reach(db.profile, path)
        node[key] = value
    end)

    logoutFrame.onEvent(logoutFrame, "PLAYER_LOGOUT")

    AceDB.db_registry = {}
    local fresh = AceDB:New(sv, ns.BuildDefaults(ns.Registry), true)

    local wrong = {}
    walk(defaults.profile, "", function(path, _, _, value)
        if peek(fresh.profile, path) ~= value then
            wrong[#wrong + 1] = path
        end
    end)
    table.sort(wrong)
    T.eq(#wrong, 0, "a chosen default comes back as itself — "
        .. table.concat(wrong, ", "))
end

--============================================================================
-- The fourth circle: a module out of a separate folder arrives later and
-- redeclares the defaults to a live database (ns.InjectModuleDefaults,
-- Core/Init.lua). On that AceDB cleans the defaults out of the profile and
-- puts them back — what the player chose is obliged to survive that too.
--============================================================================

do
    local sv = {}
    local live = ns.BuildDefaults(ns.Registry)
    local db = AceDB:New(sv, live, true)
    ns.MigrateProfile(db.profile, ns.Migrations, ns.DB_VERSION)

    local chosen = {}
    walk(live.profile, "", function(path, _, _, value)
        local want = unlike(value)
        if want == nil then return end
        local node, key = reach(db.profile, path)
        node[key] = want
        chosen[path] = want
    end)

    -- Exactly what ns.InjectModuleDefaults does: add a section to that same
    -- table of defaults and redeclare it to the database.
    live.profile.umbraexample = { enabled = false, size = 12 }
    live.global.umbraexample  = { seen = 0 }
    db:RegisterDefaults(live)

    local lost = {}
    for path, want in pairs(chosen) do
        if peek(db.profile, path) ~= want then lost[#lost + 1] = path end
    end
    table.sort(lost)
    T.eq(#lost, 0, "a module's arrival does not erase what was chosen — "
        .. table.concat(lost, ", "))

    logoutFrame.onEvent(logoutFrame, "PLAYER_LOGOUT")

    AceDB.db_registry = {}
    local after = ns.BuildDefaults(ns.Registry)
    after.profile.umbraexample = { enabled = false, size = 12 }
    after.global.umbraexample  = { seen = 0 }
    local fresh = AceDB:New(sv, after, true)

    lost = {}
    for path, want in pairs(chosen) do
        if peek(fresh.profile, path) ~= want then lost[#lost + 1] = path end
    end
    table.sort(lost)
    T.eq(#lost, 0, "nor does leaving the game after its arrival — "
        .. table.concat(lost, ", "))
end

--============================================================================
-- The stand-ins are removed: the next set must see neither them nor the library.
--============================================================================

-- The list of names is explicit: a nil in the table of saved values is the
-- absence of a key, and a walk through pairs would not return everything, leaving a stand-in for the next set.
AceDB.db_registry = {}
local STUBBED = {
    "CreateFrame", "GetRealmName", "UnitFactionGroup", "UnitName",
    "UnitClass", "UnitRace", "GetLocale", "GetBuildInfo",
    "GetCurrentRegionName", "GetCurrentRegion", "strlenutf8", "LibStub",
}
for i = 1, #STUBBED do _G[STUBBED[i]] = saved[STUBBED[i]] end
