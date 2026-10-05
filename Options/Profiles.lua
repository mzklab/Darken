local ADDON, ns = ...

-- Profiles: a page of our own over the same store.
--
-- === What changes and what does not ===
--
-- The store does not change by a single byte: it is still AceDB, the same
-- profiles in the same saved-variables file. Only the window that manages
-- them changes — AceDBOptions used to draw it, bringing its own styling and
-- its own wording along.
--
-- === Why "Profile Name" rather than "Rename To" ===
--
-- The author said it plainly about the old window: "Rename To" reads badly;
-- better to just set a name, then press rename. A field labelled "Rename To"
-- is half a sentence that the button finishes; a field labelled "Profile
-- Name" reads on its own, and the button beside it says what to do with it.
--
-- === What is pure here ===
--
-- The rules: whether this profile may be deleted, whether a name may be
-- used, what the list becomes afterwards. They are tested because a mistake
-- in them costs the player a profile — and a profile is all of their settings
-- at once.

local Profiles = {}
ns.Profiles = Profiles

--============================================================================
-- Pure decisions
--============================================================================

--- Normalise a name for comparison and storage.
-- @param said any
-- @return string
function Profiles.Trim(said)
    if type(said) ~= "string" then return "" end
    return said:match("^%s*(.-)%s*$") or ""
end

--- Whether this profile may be deleted.
--
-- The one currently in use may not be: deleting it leaves the addon with no
-- settings at all and nothing to restore them from. AceDB does not forbid
-- this, so it is forbidden here.
--
-- @param names table|nil list of names
-- @param current any name of the current profile
-- @param name any name of the profile to delete
-- @return boolean, string|nil whether it may; the reason if not
function Profiles.CanDelete(names, current, name)
    local want = Profiles.Trim(name)
    if want == "" then return false, "no name" end
    if want == Profiles.Trim(current) then return false, "current" end

    for _, said in ipairs(type(names) == "table" and names or {}) do
        if said == want then return true, nil end
    end
    return false, "unknown"
end

--- Whether a profile may be given this name.
--
-- An empty name and a taken name are two different refusals, named
-- differently: "name taken" is something the player can fix, while "nothing
-- entered" would be incomprehensible if reported as "taken".
--
-- @param names table|nil list of names
-- @param name any
-- @return boolean, string|nil
function Profiles.CanName(names, name)
    local want = Profiles.Trim(name)
    if want == "" then return false, "no name" end

    for _, said in ipairs(type(names) == "table" and names or {}) do
        if said == want then return false, "taken" end
    end
    return true, nil
end

--- Profile names in alphabetical order.
--
-- The order is deliberate: AceDB returns them in table-iteration order, that
-- is, in any order, and a list that is "different sometimes" forces the eye
-- to search where it could simply look.
--
-- @param db table|nil
-- @return table array of names
function Profiles.Names(db)
    if type(db) ~= "table" or type(db.GetProfiles) ~= "function" then
        return {}
    end

    local ok, list = pcall(db.GetProfiles, db)
    if not ok or type(list) ~= "table" then return {} end

    local out = {}
    for i = 1, #list do out[i] = list[i] end
    table.sort(out)
    return out
end

--- Name of the current profile.
-- @param db table|nil
-- @return string
function Profiles.Current(db)
    if type(db) ~= "table" or type(db.GetCurrentProfile) ~= "function" then
        return ""
    end
    local ok, said = pcall(db.GetCurrentProfile, db)
    return (ok and type(said) == "string") and said or ""
end

--============================================================================
-- Actions
--============================================================================

--- The addon's store.
-- @return table|nil
local function store()
    local addon = ns.Addon
    local db = addon and addon.db
    return type(db) == "table" and db or nil
end

--- Switch to a profile.
-- @param name any
-- @return boolean
function Profiles.Use(name)
    local db = store()
    local want = Profiles.Trim(name)
    if db == nil or want == "" then return false end
    if want == Profiles.Current(db) then return false end

    return pcall(db.SetProfile, db, want) and true or false
end

--- Create a profile with this name and switch to it.
--
-- AceDB creates a profile by switching: SetProfile with an unknown name
-- builds it from the defaults. It has no separate "create", and there is
-- nothing here to invent one from.
--
-- @param name any
-- @return boolean, string|nil
function Profiles.New(name)
    local db = store()
    if db == nil then return false, "no store" end

    local ok, why = Profiles.CanName(Profiles.Names(db), name)
    if not ok then return false, why end

    return pcall(db.SetProfile, db, Profiles.Trim(name)) and true or false
end

--- Copy another profile's settings into the current one.
-- @param name any the profile to copy from
-- @return boolean
function Profiles.CopyFrom(name)
    local db = store()
    local want = Profiles.Trim(name)
    if db == nil or want == "" then return false end
    if want == Profiles.Current(db) then return false end

    return pcall(db.CopyProfile, db, want) and true or false
end

--- Delete a profile.
-- @param name any
-- @return boolean, string|nil
function Profiles.Delete(name)
    local db = store()
    if db == nil then return false, "no store" end

    local ok, why = Profiles.CanDelete(Profiles.Names(db),
        Profiles.Current(db), name)
    if not ok then return false, why end

    return pcall(db.DeleteProfile, db, Profiles.Trim(name)) and true or false
end

--- Rename the current profile.
--
-- The store cannot rename at all, so a rename is assembled from three of its
-- actions: switch to the new name, copy the old profile into it, delete the
-- old one. The order matters — copy before deleting, or there is nothing left
-- to copy from.
--
-- @param name any the new name
-- @return boolean, string|nil
function Profiles.Rename(name)
    local db = store()
    if db == nil then return false, "no store" end

    local ok, why = Profiles.CanName(Profiles.Names(db), name)
    if not ok then return false, why end

    local from = Profiles.Current(db)
    if from == "" then return false, "no current" end

    if not pcall(db.SetProfile, db, Profiles.Trim(name)) then
        return false, "switch failed"
    end
    if not pcall(db.CopyProfile, db, from) then
        return false, "copy failed"
    end

    -- Deleting the old profile comes last, and its failure does not undo
    -- the rename: the player is already in a profile with the new name and
    -- their own settings. They can delete the leftover themselves, whereas
    -- rolling back would return them to where they were leaving.
    pcall(db.DeleteProfile, db, from)
    return true, nil
end

--- Reset the current profile to the defaults.
-- @return boolean
function Profiles.Reset()
    local db = store()
    if db == nil or type(db.ResetProfile) ~= "function" then return false end
    return pcall(db.ResetProfile, db) and true or false
end

--============================================================================
-- Page
--============================================================================

-- The column's second group: profiles are the only part of the window that
-- is not about the game but about the settings themselves. The page is
-- therefore rendered more quietly than the rest (the `aside` field) and comes
-- last.

if type(ns.Schema) == "table" then
    local Schema = ns.Schema
    local PAGE = "profiles"

    -- The typed name lives here rather than in the profile: it is window
    -- state, not a choice that must survive logout.
    local typed = ""

    Schema.Page(PAGE, {
        title = "Profiles",
        order = 100,
        aside = true,
    })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "A profile is every setting in this window at once. Which "
            .. "profile a character uses is that character's own choice; "
            .. "the profiles themselves are shared across the account.",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Current Profile",
        apply = "none",
        hint = "Switch this character to another profile. Everything in "
            .. "this window follows at once.",
        values = function()
            local db = ns.Addon and ns.Addon.db
            local out = {}
            for _, name in ipairs(Profiles.Names(db)) do
                out[#out + 1] = { key = name, text = name }
            end
            return out
        end,
        get = function()
            return Profiles.Current(ns.Addon and ns.Addon.db)
        end,
        set = function(value)
            if Profiles.Use(value) and type(ns.Registry) == "table" then
                pcall(ns.Registry.ApplyAll, ns.Registry)
            end
        end,
    })

    -- The field is labelled "Profile Name" rather than "Rename To": a label
    -- of the latter kind is half a sentence finished by the button and reads
    -- only together with it. There are two buttons beside it, and both say
    -- what to do with what was typed.
    Schema.Add(PAGE, {
        kind = "text",
        label = "Profile Name",
        apply = "none",
        hint = "Type a name here, then press one of the buttons below.",
        get = function() return typed end,
        set = function(value) typed = Profiles.Trim(value) end,
    })

    Schema.Add(PAGE, {
        kind = "action",
        label = "New Profile",
        apply = "none",
        hint = "Start a profile with that name, at the addon's defaults, "
            .. "and switch this character to it.",
        run = function()
            if Profiles.New(typed) then
                typed = ""
                if type(ns.Registry) == "table" then
                    pcall(ns.Registry.ApplyAll, ns.Registry)
                end
            end
        end,
    })

    Schema.Add(PAGE, {
        kind = "action",
        label = "Rename",
        apply = "none",
        hint = "Give the profile you are in that name. Its settings come "
            .. "with it.",
        run = function()
            if Profiles.Rename(typed) then typed = "" end
        end,
    })

    Schema.Add(PAGE, { kind = "header", label = "Other Profiles" })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Copy Settings From",
        apply = "none",
        hint = "Take every setting from another profile into the one you "
            .. "are in. The other profile is left alone.",
        values = function()
            local db = ns.Addon and ns.Addon.db
            local current = Profiles.Current(db)
            local out = {}
            for _, name in ipairs(Profiles.Names(db)) do
                if name ~= current then
                    out[#out + 1] = { key = name, text = name }
                end
            end
            return out
        end,
        get = function() return nil end,
        set = function(value)
            if Profiles.CopyFrom(value) and type(ns.Registry) == "table" then
                pcall(ns.Registry.ApplyAll, ns.Registry)
            end
        end,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Delete Profile",
        apply = "none",
        hint = "Remove a profile you are not using. The one you are in "
            .. "cannot be deleted: deleting it would leave the addon with "
            .. "no settings at all.",
        values = function()
            local db = ns.Addon and ns.Addon.db
            local current = Profiles.Current(db)
            local out = {}
            for _, name in ipairs(Profiles.Names(db)) do
                if name ~= current then
                    out[#out + 1] = { key = name, text = name }
                end
            end
            return out
        end,
        get = function() return nil end,
        set = function(value) Profiles.Delete(value) end,
    })

    Schema.Add(PAGE, {
        kind = "action",
        label = "Reset This Profile",
        apply = "none",
        hint = "Put every setting in the profile you are in back to the "
            .. "addon's defaults. Other profiles are left alone.",
        run = function()
            if Profiles.Reset() and type(ns.Registry) == "table" then
                pcall(ns.Registry.ApplyAll, ns.Registry)
            end
        end,
    })
end
