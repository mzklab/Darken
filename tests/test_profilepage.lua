local helpers = require("helpers")

-- Our own profiles page: the rules and the actions over the store.
--
-- What is checked here is not the styling but what costs the player dearly. A
-- mistake in a profile rule costs him not a setting but EVERY setting at
-- once: a profile is the whole window entire.
--
-- The store is a stand-in but with the same calls AceDB governs them by. It
-- has no renaming at all, and renaming is assembled out of three of its
-- actions — and that is exactly what is checked here.

local ns = helpers.newNamespace()
helpers.loadAddonFile("Options/Schema.lua", ns)
helpers.loadAddonFile("Options/Profiles.lua", ns)

local Profiles = ns.Profiles

--- A stand-in store with the same calls as AceDB's.
local function newStore(current, names)
    local db = { current = current, kept = {}, log = {} }
    for _, name in ipairs(names) do db.kept[name] = true end

    function db:GetProfiles()
        local out = {}
        for name in pairs(self.kept) do out[#out + 1] = name end
        return out
    end
    function db:GetCurrentProfile() return self.current end
    function db:SetProfile(name)
        self.kept[name] = true
        self.current = name
        self.log[#self.log + 1] = "set:" .. name
    end
    function db:CopyProfile(name)
        self.log[#self.log + 1] = "copy:" .. name
    end
    function db:DeleteProfile(name)
        self.kept[name] = nil
        self.log[#self.log + 1] = "delete:" .. name
    end
    function db:ResetProfile()
        self.log[#self.log + 1] = "reset"
    end
    return db
end

T.suite("the profiles page: a name is brought to a comparable shape")

do
    T.eq(Profiles.Trim("  Mzk  "), "Mzk", "the edges were removed")
    T.eq(Profiles.Trim("   "), "", "whitespace alone is an empty name")
    T.eq(Profiles.Trim(nil), "", "empty is empty")
    T.eq(Profiles.Trim(42), "", "not a string is empty")
end

T.suite("the profiles page: what can be deleted")

-- The one you are sitting in must not be deleted: a current profile deleted
-- leaves the addon with no settings at all and nothing to restore them with.
-- AceDB does not forbid that — we do.
do
    local names = { "Default", "Raid", "Alt" }

    T.eq(Profiles.CanDelete(names, "Default", "Raid"), true,
        "another profile is deleted")

    local ok, why = Profiles.CanDelete(names, "Default", "Default")
    T.eq(ok, false, "the current one is not deleted")
    T.eq(why, "current", "and the reason is named")

    local okTwo, whyTwo = Profiles.CanDelete(names, "Default", "NoSuchThing")
    T.eq(okTwo, false, "one that does not exist is not deleted")
    T.eq(whyTwo, "unknown", "and that is a different reason")

    T.eq(Profiles.CanDelete(names, "Default", "  Raid  "), true,
        "a name's edges change nothing")
end

T.suite("the profiles page: what name may be given")

-- Empty and taken are two different refusals, and they are named differently:
-- "taken" the player will correct, while "nothing was entered" he will not understand if told "taken".
do
    local names = { "Default", "Raid" }

    T.eq(Profiles.CanName(names, "New"), true, "a free name is taken")

    local ok, why = Profiles.CanName(names, "Raid")
    T.eq(ok, false, "a taken one is not")
    T.eq(why, "taken", "and the reason is named")

    local okTwo, whyTwo = Profiles.CanName(names, "   ")
    T.eq(okTwo, false, "an empty one is not taken")
    T.eq(whyTwo, "no name", "and that is a different reason")
end

T.suite("the profiles page: the list in alphabetical order")

-- AceDB returns the names in the order the pairs are walked, that is, in any
-- order. A list that is "sometimes different" makes one hunt with the eyes where one could simply look.
do
    local db = newStore("Default", { "Raid", "Alt", "Default" })
    local names = Profiles.Names(db)

    T.eq(#names, 3, "all three are in place")
    T.eq(names[1], "Alt", "first comes the alphabetical first")
    T.eq(names[3], "Raid", "and the last comes last")

    T.eq(#Profiles.Names(nil), 0, "with no store it is empty")
    T.eq(Profiles.Current(nil), "", "and there is no current one")
end

T.suite("the profiles page: renaming is assembled out of three actions")

-- The store cannot rename at all. The order matters: copy BEFORE deleting, or
-- there will be nowhere to copy from.
do
    local db = newStore("Default", { "Default", "Raid" })
    ns.Addon = { db = db }

    T.eq(Profiles.Rename("Combat"), true, "it was renamed")
    T.eq(db.current, "Combat", "and we are sitting in the profile with the new name")

    T.eq(db.log[1], "set:Combat", "first we moved into the new one")
    T.eq(db.log[2], "copy:Default", "then we copied the former one into it")
    T.eq(db.log[3], "delete:Default", "and only then deleted the former one")
    T.eq(db.kept["Default"], nil, "the former name is gone")

    -- A taken name does not reach the store at all.
    local other = newStore("Default", { "Default", "Raid" })
    ns.Addon = { db = other }
    local ok, why = Profiles.Rename("Raid")
    T.eq(ok, false, "we do not rename into a taken name")
    T.eq(why, "taken", "and the reason is named")
    T.eq(#other.log, 0, "and we do not touch the store at all")
end

T.suite("the profiles page: switching, creating, copying, resetting")

do
    local db = newStore("Default", { "Default", "Raid" })
    ns.Addon = { db = db }

    T.eq(Profiles.Use("Raid"), true, "we switched")
    T.eq(db.current, "Raid", "and the store knows about it")
    T.eq(Profiles.Use("Raid"), false, "into the very same one, no")

    -- AceDB has no separate "create": a profile is created by switching.
    T.eq(Profiles.New("New"), true, "a new profile was created")
    T.eq(db.current, "New", "and we are in it")
    T.eq(select(2, Profiles.New("New")), "taken", "a second time it is taken")

    T.eq(Profiles.CopyFrom("Raid"), true, "we copied from another one")
    T.eq(Profiles.CopyFrom("New"), false, "from itself, no")

    T.eq(Profiles.Reset(), true, "we reset it")
    T.eq(db.log[#db.log], "reset", "and the store was called")
end

T.suite("the profiles page: with no store nothing falls over")

do
    ns.Addon = nil

    T.eq(Profiles.Use("Raid"), false, "switching, no")
    T.eq(Profiles.New("Raid"), false, "creating, no")
    T.eq(Profiles.CopyFrom("Raid"), false, "copying, no")
    T.eq(Profiles.Delete("Raid"), false, "deleting, no")
    T.eq(Profiles.Rename("Raid"), false, "renaming, no")
    T.eq(Profiles.Reset(), false, "resetting, no")
end
