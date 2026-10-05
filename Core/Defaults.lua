local ADDON, ns = ...

-- The settings schema's version. It goes up whenever the shape of the stored
-- data changes, and a migration is added along with it.
ns.DB_VERSION = 14

-- The base settings in AceDB's format. Modules add their own sections
-- through Registry:CollectDefaults(); only what is shared lives here.
-- WARNING: there must be no `version` field here, and it cannot be brought
-- back. AceDB copies the values from defaults into the profile
-- (copyDefaults), and on PLAYER_LOGOUT it cleans out of the profile
-- everything equal to its default (removeDefaults). So a `version` declared
-- as a default would never reach SavedVariables: on every load it would again
-- equal the current ns.DB_VERSION, ns.MigrateProfile would see from ==
-- target and quietly do nothing. After DB_VERSION went up, old profiles would
-- be read as new ones — a silent corruption of the settings. Only
-- MigrateProfile sets the version, by a raw write into the profile, and it
-- survives removeDefaults precisely because there is no such key in
-- defaults.
ns.BaseDefaults = {
    profile = {
        -- Paint the settings windows of other Ace3 addons. The library is
        -- shared by every addon on Ace3, so the switch changed the look not
        -- only of Darken's own window but of other addons' settings windows
        -- using the same copy of AceGUI-3.0.
        --
        -- NOTE: nothing reads this setting today. The hook that painted
        -- AceGUI widgets went with the old settings window, while the toggle
        -- is still shown in the settings (Options/Pages.lua) — a switch that
        -- does nothing. Either the skinning comes back or the row goes.
        skinAce = true,

        -- The accent colour: the one colour a dark theme says "look here"
        -- with.
        --
        -- The default is steel rather than lilac, and that change is the
        -- author's decision rather than the code's taste. The lilac is
        -- derived from the addon's own textures and was first; on a large
        -- settings window it turned out loud — the heading, the checkbox, the
        -- slider and the selected row all shouted in one colour, and the eye
        -- had nothing to catch on. Steel is quieter, and in a dark theme that
        -- is a virtue rather than pallor.
        --
        -- The lilac has not gone anywhere: it is first in the list of sets
        -- and comes back with one choice on the General page.
        accent = "steel",

        -- Show the demonstration settings page.
        -- Off: the page existed to check the widgets' styling and the player
        -- does not need it — not one of its settings does anything.
        --
        -- NOTE: the page itself went with the old settings window. The
        -- command /darken demo now answers that this build has no demo
        -- section, and nothing reads this field.
        showDemo = false,
    },
}

-- The author's look: what the addon would set as defaults if it had the
-- right to. The defaults are the game's native look (see
-- Modules/UnitFrames.lua), while this set is applied in one action on the
-- General page — that is, by the player's choice rather than by fait
-- accompli.
--
-- Today it is one of three presets (Core/Presets.lua): classic, modern and
-- this one. The table stayed here and the presets take it from here: the
-- author's set is older than they are, it survived three versions of the
-- settings schema, migration 1 -> 2 refers to it, and moving it for the sake
-- of tidiness would cost history.
--
-- The texture names match the keys in the LibSharedMedia registry
-- (Core/Media.lua): renaming a texture there must pass through here too.
-- The colour stands next to the texture here not for completeness: the
-- addon's textures are a gradient the engine multiplies by the bar's colour,
-- and without a chosen colour they are tinted by whatever the game set
-- (health is green for it). So the author's look without the colour is not
-- half of the author's look but a different look.
ns.Recommended = {
    unitframes = {
        health      = "Darken Purple",
        healthColor = "class",
        power       = "Darken Blue",
        powerColor  = "power",
    },
}

-- The settings fields that hold texture names. The list is explicit: the
-- sets' other fields are colour modes, switches and numbers, and checking
-- those against the LibSharedMedia registry is meaningless. The tests need it
-- (tests/test_media.lua, tests/test_presets.lua) so that a typo in a texture
-- name does not survive to the client: an unknown name does not raise but
-- silently leaves the native bar.
ns.PRESET_TEXTURE_FIELDS = {
    unitframes = { "health", "power" },
    nameplates = { "health" },
}

--- Merge values into an existing settings table.
--
-- The function descends exactly through the keys named in the source: a
-- setting absent from it is not changed at any level. That is the preset's
-- promise — it touches only its own.
--
-- A nested table from the source is not stored by reference but rewritten key
-- by key: a preset's table is one for the whole session, and putting it into
-- a profile would hand the player a shared object to edit — an edit to one
-- profile would change them all.
--
-- A key under which the profile holds something other than a table while the
-- source offers a table is created as an empty table: that is what a setting
-- not yet in the profile looks like (AceDB cleans out values equal to the
-- default).
--
-- @param target table the settings table
-- @param values table the values
local function merge(target, values)
    for key, value in pairs(values) do
        if type(value) == "table" then
            local nested = target[key]
            if type(nested) ~= "table" then
                nested = {}
                target[key] = nested
            end
            merge(nested, value)
        else
            target[key] = value
        end
    end
end

--- Apply a set of values to a profile.
-- A pure function: it edits the table it was given and knows nothing about
-- the game or the module registry. It does not create a section the profile
-- lacks: a setting without its subsystem is read by nobody anyway, while a
-- stray key would outlive the module's removal and stay in SavedVariables as
-- litter. Inside a section the rule is different — see merge above.
-- @param profile table the settings profile
-- @param values table the set of values: section -> settings
-- @return table the same profile
function ns.ApplySettingValues(profile, values)
    if type(profile) ~= "table" or type(values) ~= "table" then return profile end

    for section, sectionValues in pairs(values) do
        local target = profile[section]
        if type(target) == "table" and type(sectionValues) == "table" then
            merge(target, sectionValues)
        end
    end

    return profile
end

--- Apply the author's look to a profile.
-- A thin wrapper over the common path: the author's set is a set of values
-- like any preset and is applied by the same code.
-- @param profile table the settings profile
-- @param recommended table|nil the set of values; ns.Recommended by default
-- @return table the same profile
function ns.ApplyRecommended(profile, recommended)
    local source = type(recommended) == "table" and recommended or ns.Recommended
    return ns.ApplySettingValues(profile, source)
end

-- Migrations: [version] = a function bringing a profile of that version to
-- the next one.
--
-- 1 -> 2: the game's native look became the default for the bar textures and
-- the name colour. Raising a default does not by itself touch anybody's
-- profile, but that is not enough here. On logout AceDB cleans out of the
-- profile everything equal to its default (removeDefaults), so somebody who
-- never changed the texture does not have it in SavedVariables at all: on the
-- next load they would get the new default — the native bar — and conclude
-- the addon was broken. The migration gives such profiles back exactly what
-- they saw, by writing the former values explicitly. Whoever chose a texture
-- themselves keeps it, and the migration does not reach them: only the value
-- __native meets the condition, and no such value existed in the version 1
-- schema.
--
-- The strings here are written literally and deliberately: a migration is a
-- record of history. If the native-look marker is ever renamed, this function
-- has to stay with the old spelling, or it will stop recognising old
-- profiles.
--
-- 2 -> 3: the addon's nine textures were renamed from Russian names to
-- English ones (Core/Media.lua). The addon's base language is English, and a
-- texture's name goes into the shared LibSharedMedia registry and is seen by
-- players on any client language. But that same name lies in SavedVariables
-- as a setting's value: without a migration the saved choice would stop being
-- found and the bar would silently return to the native one.
--
-- The translation table is a record of history too and is written literally:
-- the old names in it must stay in their former spelling forever, or the
-- migration will stop recognising old profiles.
local RENAMED_TEXTURES_2_TO_3 = {
    -- The keys are the Russian names from the time the addon was called
    -- something else. They must not be renamed along with the addon: a key
    -- recognises WHAT WAS SAVED, and other people's saved files hold exactly
    -- this spelling.
    ["Umbra бирюзовая"] = "Darken Cyan",
    ["Umbra жёлтая"]    = "Darken Yellow",
    ["Umbra зелёная"]   = "Darken Green",
    ["Umbra красная"]   = "Darken Red",
    ["Umbra оранжевая"] = "Darken Orange",
    ["Umbra розовая"]   = "Darken Pink",
    ["Umbra синяя"]     = "Darken Blue",
    ["Umbra сиреневая"] = "Darken Purple",
    ["Umbra тёмная"]    = "Darken Dark",
}

-- The profile settings holding a bar texture's name. The list is explicit:
-- blindly fixing everything that looks like a string is not allowed.
local TEXTURE_FIELDS_2_TO_3 = {
    { section = "unitframes", key = "health" },
    { section = "unitframes", key = "power"  },
}

--- Rename saved texture names.
-- Only what the addon itself once wrote is touched: a value absent from the
-- translation table is left as it is. That rule covers the native-look
-- marker __native, names from other addons' texture sets, and unfamiliar
-- rubbish alike — fixing somebody else's value is more dangerous than
-- leaving it. A second pass is harmless: the new names are not keys of the
-- table.
-- @param profile table the settings profile
local function RenameTextures(profile)
    for i = 1, #TEXTURE_FIELDS_2_TO_3 do
        local field = TEXTURE_FIELDS_2_TO_3[i]
        local section = profile[field.section]
        if type(section) == "table" then
            local renamed = RENAMED_TEXTURES_2_TO_3[section[field.key]]
            if renamed then section[field.key] = renamed end
        end
    end
end
ns.RenameTextures = RenameTextures

-- The profile fields holding a bar texture's name. There are more of them
-- here than in the 2 -> 3 rename: since then the nameplates and individual
-- units have learned to choose a texture too.
local TEXTURE_FIELDS_11_TO_12 = {
    { section = "unitframes", key = "health" },
    { section = "unitframes", key = "power"  },
    { section = "nameplates", key = "health" },
}

--- Rewrite the addon-name prefix in saved values.
--
-- There are two prefixes and they differ: for textures it is the old addon
-- name plus a space, for the info panel's cells the old addon name with its
-- UI suffix plus a space. That is how it came about historically, and the
-- rename has to know both — otherwise half the values stay unrecognised and
-- the player sees settings half reset.
--
-- @param profile table the settings profile
-- @return number how many values were rewritten
local function RenameAddonNames(profile)
    if type(profile) ~= "table" then return 0 end

    local changed = 0

    local function swap(value, old, new)
        if type(value) ~= "string" then return nil end
        if value:sub(1, #old) ~= old then return nil end
        return new .. value:sub(#old + 1)
    end

    for i = 1, #TEXTURE_FIELDS_11_TO_12 do
        local field = TEXTURE_FIELDS_11_TO_12[i]
        local section = profile[field.section]
        if type(section) == "table" then
            local said = swap(section[field.key], "Umbra ", "Darken ")
            if said then
                section[field.key] = said
                changed = changed + 1
            end
        end
    end

    -- An individual unit's textures lie one level deeper still.
    local units = type(profile.unitframes) == "table"
        and profile.unitframes.units or nil
    if type(units) == "table" then
        for _, own in pairs(units) do
            if type(own) == "table" then
                for _, key in ipairs({ "health", "power" }) do
                    local said = swap(own[key], "Umbra ", "Darken ")
                    if said then
                        own[key] = said
                        changed = changed + 1
                    end
                end
            end
        end
    end

    -- The order of the info panel's cells.
    local info = profile["umbrainfo"]
    local order = type(info) == "table" and info.order or nil
    if type(order) == "table" then
        for i = 1, #order do
            local said = swap(order[i], "UmbraUI ", "Darken ")
            if said then
                order[i] = said
                changed = changed + 1
            end
        end
    end

    return changed
end
ns.RenameAddonNames = RenameAddonNames

-- 3 -> 4: the channel ticks and the latency tail moved out of the cast bar
-- subsystem into the Advanced Cast Bars module. Neither exists in the addon
-- any more — the cast bar was removed entirely — but the migration stays: it
-- repairs the saved files of whoever installed that build.
--
-- Why they moved: the specification gives the core a bar's appearance and a
-- module the elements laid on top of it which do not change that appearance.
-- The ticks and the tail are the latter, and while they lived in both places
-- the player could switch the ticks on twice and see them twice.
--
-- What the migration does: it moves the saved values of three fields into the
-- module's section and removes them from the core's, where nobody will read
-- them again.
--
-- Why the move looks at a key's presence rather than at its value. On logout
-- AceDB cleans out of the profile everything equal to its default, and the
-- defaults were ticks = false, latency = false and tickInterval = 1. So those
-- fields are in SavedVariables for exactly those who changed them, and those
-- are the ones to move. A migration written as "if ticks == false then..."
-- would never have fired once: no such key occurs in a saved file.
--
-- The module's section is created only when there is something to move.
-- Otherwise the profile would be left with an empty section for an addon the
-- player may never install.
--
-- The section names and the names of the three fields are written literally:
-- a migration is a record of history, and renaming any of them must leave
-- this function in its former spelling, or it will stop recognising old
-- profiles.
local MOVED_FIELDS_3_TO_4 = { "ticks", "tickInterval", "latency" }
local MOVED_UNITS_3_TO_4  = { "player", "target", "focus" }

--- Move the ticks and the latency tail into the module's section.
-- @param profile table the settings profile
local function MoveCastBarMarks(profile)
    local castbar = profile["castbar"]
    if type(castbar) ~= "table" then return end

    local moved

    for i = 1, #MOVED_UNITS_3_TO_4 do
        local unitKey = MOVED_UNITS_3_TO_4[i]
        local unit = castbar[unitKey]
        if type(unit) == "table" then
            for f = 1, #MOVED_FIELDS_3_TO_4 do
                local field = MOVED_FIELDS_3_TO_4[f]
                local value = unit[field]
                if value ~= nil then
                    if moved == nil then
                        moved = profile["umbracastbars"]
                        if type(moved) ~= "table" then
                            moved = {}
                            profile["umbracastbars"] = moved
                        end
                    end

                    local target = moved[unitKey]
                    if type(target) ~= "table" then
                        target = {}
                        moved[unitKey] = target
                    end

                    target[field] = value
                    unit[field] = nil
                end
            end
        end
    end
end
ns.MoveCastBarMarks = MoveCastBarMarks

-- 4 -> 5: the dimming default became 70 instead of zero.
--
-- Why the default was raised at all. The addon's general rule — a fresh
-- installation changes nothing — is overruled by the author here, and only
-- here: a dark interface that looks like an untouched game after being
-- installed does not do what it is installed for. For everything else the
-- rule holds.
--
-- What follows for those already playing. On logout AceDB cleans out of the
-- profile everything equal to its default, and the default was zero. So
-- somebody who never touched the slider and somebody who deliberately set
-- zero have equally nothing in SavedVariables — and after the default was
-- raised both would get a dimmed screen without asking for it. That is the
-- same defect the missing `version` default guards against, only this time
-- visible to the eye.
--
-- The decision: the new default goes to a fresh installation, while somebody
-- already playing keeps the look they have. An update is not an installation,
-- and changing a person's screen behind their back is not allowed even for
-- the better. Whoever chose a non-zero value of their own is touched by no
-- branch: their value lies in the saved file and stays there as it is.
--
-- So the migration writes the old default explicitly: a version 4 profile's
-- silence meant zero, and now the profile says zero out loud. From there that
-- zero lives as an ordinary setting, and the slider takes it to seventy in
-- one drag — and back.
--
-- Why the step is in two stages. An ordinary migration works on db.profile —
-- that is, after AceDB has already put the defaults into the profile
-- (copyDefaults). At that moment `amount` equals seventy for everybody
-- alike, and "never touched it" cannot be told from "set it to seventy": the
-- key is there for both. The only place where a missing key is still visible
-- is the raw SavedVariables table, before the database is created. That is
-- where ns.RawMigrations works from (called from Core/Init.lua).
--
-- The section and field names are written literally: a migration is a record
-- of history, and renaming the subsystem or the setting must leave this
-- function in its former spelling, or it will stop recognising old profiles.
--
-- A second pass is harmless: a value once written is present afterwards and
-- the second pass does not touch it. That is needed not for tidiness — only
-- the active profile has its version raised (ns.MigrateProfile), while the
-- raw pass walks every saved profile on every login until each one's turn
-- comes.
local DARKNESS_BEFORE_5 = 0

--- Keep the former look for somebody who never switched dimming on.
-- @param profile table the settings profile, raw or already with defaults
local function KeepDarknessAsWas(profile)
    if type(profile) ~= "table" then return end

    local darkness = profile["darkness"]
    if type(darkness) ~= "table" then
        darkness = {}
        profile["darkness"] = darkness
    end

    if darkness["amount"] == nil then
        darkness["amount"] = DARKNESS_BEFORE_5
    end
end
ns.KeepDarknessAsWas = KeepDarknessAsWas

-- The mover overlay's lock before schema version 6. The default was locked,
-- and for somebody who locked it deliberately AceDB cleaned the key out on
-- logout: the value equalled the default. After the default moved to
-- unlocked, such a profile would open the overlay unlocked, and the first
-- movement of the mouse would shift an element they had placed — precisely
-- the harm the lock exists against.
--
-- The same two-stage technique as the dimming, and for the same reason: a
-- missing key is visible only in the raw SavedVariables table, before
-- copyDefaults. The section and field names are written literally — a
-- migration is a record of history, and renaming the subsystem must leave
-- this spelling as it is, or old profiles will stop being recognised.
--
-- A second pass is harmless: a value once written is there afterwards and
-- the second pass does not touch it.
local MOVER_LOCK_BEFORE_6 = true

--- Keep the lock closed for somebody who closed it.
-- @param profile table the settings profile, raw or already with defaults
local function KeepMoverLockAsWas(profile)
    if type(profile) ~= "table" then return end

    local movers = profile["movers"]
    if type(movers) ~= "table" then
        movers = {}
        profile["movers"] = movers
    end

    if movers["locked"] == nil then
        movers["locked"] = MOVER_LOCK_BEFORE_6
    end
end
ns.KeepMoverLockAsWas = KeepMoverLockAsWas

-- 6 -> 7: the dimming slider's scale changed.
--
-- What changed. The scale's former end (a hundred, factor 0.30) now stands at
-- seventy, and thirty more steps were added beyond it down to factor 0.20 —
-- darker than anything the addon could do. The details of the scale itself
-- are in Modules/Darkness.
--
-- What follows. A number lying in a saved file meant a look on the former
-- scale and means a different look on the present one: a hundred was the
-- bottom and has become the bottom minus another third of the travel. So the
-- number has to change in a way that keeps the look the same — and that is
-- exactly a multiplication by seven tenths: the new scale's first seventy
-- steps repeat the former hundred. A hundred becomes seventy, forty becomes
-- twenty-eight, zero stays zero.
--
-- Rounding. The slider moves in whole steps, so 35 becomes 25 rather than
-- 24.5. The price is half a step, that is, 0.005 of the factor: on the
-- chrome's half-tones that is hundredths of brightness, which are not
-- visible. Dropping it half a step down, or storing a fraction in an integer
-- setting, are both worse.
--
-- Silence must not be converted, and cannot be. A profile without the key
-- stood at the former default — seventy — while the present default is
-- forty-nine, and Darkness.Factor gives one and the same 0.51 for both. A
-- silent profile gets the new default and sees its former screen; were we to
-- touch it here, it would see somebody else's.
--
-- Why the step is raw. The same reason as its neighbours above, and this time
-- a harsher one. After copyDefaults everybody has a number in the profile,
-- and for whoever was silent it equals the default. Telling them from
-- somebody who chose exactly that default themselves is impossible;
-- recomputing both would shift the first one's screen. A key's presence is
-- visible only in the raw SavedVariables table.
--
-- Why a marker is needed. The previous two steps wrote a value only in place
-- of a missing key and were therefore harmless on a repeat. This step
-- multiplies, while the raw pass walks every saved profile on every login
-- until that profile's turn to become active comes: a second pass would
-- multiply again. So the recomputed value is marked by the former one written
-- beside it, and the marker doubles as the answer to "has this profile been
-- converted". The marker key is not in the defaults — so AceDB will not clean
-- it out, and the marker survives logout as it must.
--
-- The section and field names and the seven tenths are written literally
-- here: a migration is a record of history. Whether the scale's break moves
-- or the subsystem is renamed, this function has to stay as it is, or it will
-- stop recognising the profiles it was written for.
local DARKNESS_SCALE_TO_7 = 0.7
local DARKNESS_MARK_7 = "amountBefore7"

--- Convert the chosen dimming to the present scale.
-- @param profile table the settings profile, raw or already with defaults
local function RescaleDarknessTo7(profile)
    if type(profile) ~= "table" then return end

    local darkness = profile["darkness"]
    if type(darkness) ~= "table" then return end

    -- The profile is already converted: there is nothing to multiply
    -- again.
    if darkness[DARKNESS_MARK_7] ~= nil then return end

    -- No key means the profile stood at the former default, and the present
    -- default gives it the same look. No marker either: there was nothing to
    -- convert, and a repeat pass will see exactly the same silence.
    local amount = tonumber(darkness["amount"])
    if amount == nil then return end

    if amount < 0 then amount = 0 end
    if amount > 100 then amount = 100 end

    darkness[DARKNESS_MARK_7] = amount
    darkness["amount"] = math.floor(amount * DARKNESS_SCALE_TO_7 + 0.5)
end
ns.RescaleDarknessTo7 = RescaleDarknessTo7

-- The bag slots' border before schema version 8.
--
-- The setting was part of the dark bags: with the window's native look (the
-- default) the border was not drawn at all, and the border's own default of
-- true meant "on, once there is something to be on". The dark look went
-- (Modules/Bags.lua), the border became a setting in its own right, and that
-- same true would now mean "put a border on everybody's slots" — including
-- those who never recoloured their bags. So the default moved to false.
--
-- Moving a default is not free: the former "never touched it" and the new
-- "never touched it" mean different things, and the difference can be seen
-- only where a missing key is still visible — in the raw SavedVariables
-- table, before copyDefaults. The same two-stage technique as the dimming and
-- the mover lock, and for the same reason.
--
-- The rule: the border was visible to exactly those who chose the dark look
-- and did not switch it off themselves. The style key stood for everybody
-- after copyDefaults, while in the raw table it is there only for those who
-- chose a non-default — that is, for exactly them.
--
-- The section and field names are written literally: a migration is a record
-- of history, and renaming the subsystem must leave this spelling as it is,
-- or old profiles will stop being recognised.
--
-- A second pass is harmless: the style key stays in the profile as it is (a
-- dead key nobody reads any more), and the second pass writes the same value
-- to the same place.
--
-- @param profile table the settings profile, raw or already with defaults
local function KeepBagBordersAsWas(profile)
    if type(profile) ~= "table" then return end

    local bags = profile["bags"]
    if type(bags) ~= "table" then return end

    -- The window's native look: this profile never saw the border, and the
    -- new default gives it exactly the same. There is nothing to write.
    if bags["style"] ~= "dark" then return end

    if bags["slotBorder"] ~= false then bags["slotBorder"] = true end
end
ns.KeepBagBordersAsWas = KeepBagBordersAsWas

--- Remove the global font size from the profile: an offset stands in its
--- place now.
--
-- What it was. The global size field meant a size in points assigned to
-- every font object of the game at once. The setting expressed only one
-- thought — "let it be exactly this everywhere" — and no other request could
-- be expressed with it at all. The addon's author set 10 and saw the chat,
-- the tooltips and the quest log all at one height and noticeably smaller
-- than the game's; a heading stopped differing from a small label.
--
-- What it became. The global adjust field is a shift from each element's
-- native size, and zero means "as in the game". The request "as in the game,
-- only larger" is expressed by it directly, while the difference between a
-- heading and a label is preserved by itself.
--
-- Why the former value is not carried over. There is nothing to carry it
-- with: 10 as a size and 10 as an offset are different numbers with different
-- meanings, and the second would mean "add ten points to everything", a
-- trouble twice as bad as the first. Nor is there anything to take a
-- difference from instead: each object's native size is its own while the
-- setting was one. The honest answer is "the new setting does not know this
-- request": the key is removed, the offset stays zero, and the player gets
-- the game's native sizes to choose from afresh.
--
-- The section and field names are written literally: a migration is a record
-- of history, and renaming the subsystem must leave this spelling as it is,
-- or old profiles will stop being recognised.
--
-- A second pass is harmless: the key is already gone and there is nothing to
-- remove.
--
-- @param profile table the settings profile
local function DropGlobalFontSize(profile)
    if type(profile) ~= "table" then return end

    local fonts = profile["fonts"]
    if type(fonts) ~= "table" then return end

    local global = fonts["global"]
    if type(global) ~= "table" then return end

    global["size"] = nil
end
ns.DropGlobalFontSize = DropGlobalFontSize

--- Give the dimming a place for per-window exceptions.
--
-- The key is named literally: a migration is a record of history, and
-- renaming the subsystem must leave this spelling as it is, or old profiles
-- will stop being recognised.
--
-- A second pass is harmless: a non-empty table is left as it is.
--
-- @param profile table the settings profile
local function AddWindowExceptions(profile)
    if type(profile) ~= "table" then return end

    local darkness = profile["darkness"]
    if type(darkness) ~= "table" then return end

    if darkness["excludeWindow"] == nil then
        darkness["excludeWindow"] = {}
    end
end
ns.AddWindowExceptions = AddWindowExceptions

-- The dimming's exceptions before schema version 10.
--
-- An area used to have two states: dimmed by the general amount, or not
-- dimmed at all, and the second was recorded as a tick in the exceptions
-- list. Now an area has a mode, and the former tick is one of its values:
-- native, leave it as it is. The setting did not disappear and did not move,
-- it became more specific — and is carried over one to one, with no losses
-- and no guesswork.
--
-- Only what was ticked is carried over. The exceptions list also wrote
-- explicit falses into the profile (AceDB cleans out a value equal to the
-- default, and an explicit false read better by eye), and they mean exactly
-- what silence means: the area is dimmed like everything else. No mode is
-- written for such an area at all — it keeps the default, "follow the general
-- amount".
--
-- This migration does not touch the slider under any condition. Its default
-- went up from forty-nine to sixty-four, and the difference goes only to
-- somebody who never touched the slider: they have no key in the saved file
-- and the new default arrives by itself. A chosen value lies there as a key
-- and stays itself — so this step needs no raw stage.
--
-- The section and field names and the mode's value are written literally
-- here: a migration is a record of history, and renaming the subsystem must
-- leave this function in its former spelling, or it will stop recognising old
-- profiles.
--
-- A second pass is harmless: the second time it rewrites the same modes with
-- the same values, and after the first pass there are no exceptions left.
--
-- @param profile table the settings profile
local function ExcludeToModes(profile)
    if type(profile) ~= "table" then return end

    local darkness = profile["darkness"]
    if type(darkness) ~= "table" then return end

    local exclude = darkness["exclude"]
    if type(exclude) ~= "table" then return end

    local modes = darkness["mode"]
    if type(modes) ~= "table" then
        modes = {}
        darkness["mode"] = modes
    end

    for group, kept in pairs(exclude) do
        if kept == true and modes[group] == nil then
            modes[group] = "native"
        end
    end

    darkness["exclude"] = nil
end
ns.ExcludeToModes = ExcludeToModes

ns.Migrations = {
    [1] = function(profile)
        local unitframes = profile.unitframes
        if type(unitframes) ~= "table" then return end

        if unitframes.health == "__native" then
            unitframes.health = "Umbra сиреневая"
        end
        if unitframes.power == "__native" then
            unitframes.power = "Umbra синяя"
        end
        if unitframes.nameColor == "__native" then
            unitframes.nameColor = "class"
        end
    end,

    [2] = function(profile)
        RenameTextures(profile)
    end,

    [3] = function(profile)
        MoveCastBarMarks(profile)
    end,

    -- The second stage of step 4 -> 5. The first, the only one that can see
    -- a missing key, ran in ns.RawMigrations before the database was created;
    -- here the key is already in place and the call changes nothing. The
    -- stage was kept not for the table's tidiness: a profile that reached
    -- here without AceDB's defaults — other code, a test, a hand edit — gets
    -- the old default written rather than the new one silently.
    [4] = function(profile)
        KeepDarknessAsWas(profile)
    end,

    -- The second stage of step 5 -> 6, after the pattern of its neighbour
    -- above: the first ran in ns.RawMigrations before the database was
    -- created, and this one is for a profile that arrived without AceDB's
    -- defaults.
    [5] = function(profile)
        KeepMoverLockAsWas(profile)
    end,

    -- Step 6 -> 7 is deliberately empty here, and it is the only stage
    -- without a counterpart the other way round in ns.RawMigrations: all the
    -- work was done before the database was created, and it cannot be done
    -- here.
    --
    -- For the two neighbours above, the second stage is for a profile that
    -- arrived without AceDB's defaults: they write a value in place of a
    -- missing key, and there is nothing to get wrong there. Rescaling is a
    -- different matter. After copyDefaults a profile that was silent holds
    -- the default, and that is indistinguishable from the same number chosen
    -- deliberately; rescaling would dim the screen of somebody who asked for
    -- nothing — precisely the harm the raw step is written against. Not
    -- rescaling leaves other code with a number on the former scale, which is
    -- visible to the eye and corrected in one drag. Of the two evils the
    -- second was chosen.
    --
    -- This costs the addon's own profiles nothing: the raw pass walks every
    -- saved profile on every login, so an unconverted profile never reaches
    -- MigrateProfile here — neither at login nor on a profile switch
    -- (Core/Init.lua, Addon:OnProfileUpdate).
    [6] = function() end,

    -- The second stage of step 7 -> 8, after stages 4 and 5: the first ran
    -- in ns.RawMigrations before the database was created, and this one is
    -- for a profile that arrived without AceDB's defaults. There is nothing
    -- to get wrong here: the style key either equals dark or it does not, and
    -- after copyDefaults it means exactly what it meant in the raw table.
    [7] = function(profile)
        KeepBagBordersAsWas(profile)
    end,

    -- Step 8 -> 9: the dimming gained per-window exceptions.
    --
    -- There is work here for exactly one missing place. An older profile
    -- knows only the per-group exceptions, and the question "which individual
    -- windows are not to be dimmed" was never put to it. The answer to an
    -- unasked question is "none", that is, an empty table, and it is written
    -- in place of a missing key: somebody who already managed to tick
    -- something (other code, a hand edit) keeps their choice untouched.
    --
    -- This step needs no raw stage. There is no point telling "no key" from
    -- "the key equals the default" here: the default is an empty table, and
    -- both cases mean the same thing — not one window is excluded.
    --
    -- The catalogue of windows seen needs no migration at all: it lies not in
    -- the profile but in the database's global section, and its absence means
    -- exactly what it should — nothing has been seen yet.
    [8] = function(profile)
        AddWindowExceptions(profile)
    end,

    -- Step 9 -> 10: every dimming area gained a mode, and the former
    -- exceptions list became one of its values. All the work is in
    -- ExcludeToModes above, along with the reason this step needs no raw
    -- stage.
    [9] = function(profile)
        ExcludeToModes(profile)
    end,

    -- Step 10 -> 11: the global font size was replaced by an offset from the
    -- native one. All the work is in DropGlobalFontSize above, along with the
    -- reason the former value is carried nowhere.
    --
    -- This step needs no raw stage: there is no point telling "no key" from
    -- "the key equals the default". Removing a key that is not there and
    -- removing a key equal to zero are the same action with the same
    -- outcome.
    [10] = function(profile)
        DropGlobalFontSize(profile)
    end,

    -- 13 -> 14: a preset the player pressed left the quest-text area set to
    -- "as in the game", and the dialogue window stayed a light patch in a
    -- dark interface.
    --
    -- That is our own writing again rather than their choice. While we could
    -- not lighten text on parchment, the only answer was "do not dim this
    -- sheet at all", and the preset buttons wrote "as in the game" for that
    -- area — in all three presets at once. The addon learned to lighten the
    -- text, the answer went stale, and the entry stayed in the profile: the
    -- author sent a light parchment with the words "why was the gray out not
    -- applied here".
    --
    -- Only the native value is removed and only for this area: an empty place
    -- means the default, and this area's default is now the right one. A
    -- player who chose "as in the game" by hand will choose it again with one
    -- click — whereas leaving them a light window silently is not an
    -- option.
    [13] = function(profile)
        local darkness = profile.darkness
        local modes = type(darkness) == "table" and darkness.mode or nil
        if type(modes) == "table" and modes.questlog == "native" then
            modes.questlog = nil
        end
    end,

    -- 12 -> 13: a preset the player pressed moved the quest-text area to
    -- "follow the general amount", and the text in the quest and dialogue
    -- windows disappeared.
    --
    -- That is our mistake rather than their choice: the preset button set
    -- "follow" for every area in turn, including the one place where the text
    -- is printed dark on light. So the value is removed — not replaced by
    -- another but removed: an empty place means the default, and this area's
    -- default is the right one.
    --
    -- Only the follow value is removed and only it. A player who chose darker
    -- or lighter for this area by hand chose it themselves, and we have no
    -- right to touch their choice.
    [12] = function(profile)
        local darkness = profile.darkness
        local modes = type(darkness) == "table" and darkness.mode or nil
        if type(modes) == "table" and modes.questlog == "follow" then
            modes.questlog = nil
        end
    end,

    -- 11 -> 12: the addon changed its name, and saved values that held that
    -- name stopped meaning anything.
    --
    -- There are two kinds of them, and the player saw both at once. The bar
    -- texture names carried the old addon's name — no such textures exist any
    -- more, and the bar silently returned to its native look. The info
    -- panel's cell names carried it too — no such cells exist either, and the
    -- panel, switched on in the settings, showed nothing.
    --
    -- Only the PREFIX is renamed, and only where the addon itself wrote those
    -- values. A foreign name from somebody else's texture set is not touched:
    -- fixing a foreign value is more dangerous than leaving it as it is.
    [11] = function(profile)
        RenameAddonNames(profile)
    end,
}

-- Migrations that need the profile before AceDB puts the defaults into it:
-- [version] = function(profile).
--
-- A separate table rather than a flag inside the common one, because what
-- differs is not the step but the moment: these functions work on the raw
-- SavedVariables table, where a missing key still means "the player did not
-- choose this". After copyDefaults that fact does not exist at all.
--
-- A step may be absent here entirely: a raw profile is needed by a minority
-- of migrations, and a skipped version is not an error here, unlike in
-- ns.Migrations.
ns.RawMigrations = {
    [4] = KeepDarknessAsWas,
    [5] = KeepMoverLockAsWas,
    [6] = RescaleDarknessTo7,
    [7] = KeepBagBordersAsWas,
}

--- Run the raw migrations across every saved profile.
--
-- It works on the whole SavedVariables table rather than on one profile, and
-- that is not convenience. A profile's version is raised by
-- ns.MigrateProfile, which sees only the active profile: the others keep
-- their old version for as long as it takes, and by the time the player
-- switches to such a profile the raw data is gone — the database is created
-- and the defaults are spread. So the raw pass walks every profile at once
-- and on every login.
--
-- Nobody raises a version here, deliberately: one owner sets it —
-- ns.MigrateProfile — or the ordinary migration stages would be skipped.
-- Hence the requirement on raw steps: a second pass must be harmless. A step
-- that writes in place of a missing key gets that for free; a step that
-- computes from a former value gets it only through a marker in the profile
-- itself (RescaleDarknessTo7 above).
--
-- A profile without a version counts as fresh and is skipped: raw steps
-- correct the past, and a fresh profile has none — it is entitled to the new
-- defaults.
--
-- A pure function: it knows nothing about the game or about AceDB.
--
-- @param sv table|nil the addon's SavedVariables table
-- @param migrations table the table of [version] = function
-- @param target number the target schema version
-- @return table|nil the same table
function ns.MigrateStoredProfiles(sv, migrations, target)
    if type(sv) ~= "table" or type(migrations) ~= "table" then return sv end
    if type(target) ~= "number" then return sv end

    local profiles = sv.profiles
    if type(profiles) ~= "table" then return sv end

    for _, profile in pairs(profiles) do
        if type(profile) == "table" and type(profile.version) == "number" then
            for v = profile.version, target - 1 do
                local step = migrations[v]
                if type(step) == "function" then step(profile) end
            end
        end
    end

    return sv
end

--- Bring a profile to the target schema version.
-- A profile without a version field counts as fresh and simply receives the
-- target version. A profile with a version above the target is left
-- unchanged: that happens when the addon is rolled back to an older build,
-- and corrupting the settings in that case is not allowed.
-- @param profile table the settings profile
-- @param migrations table the table of [version] = function
-- @param target number the target version
-- @return table the same profile
function ns.MigrateProfile(profile, migrations, target)
    local from = profile.version

    if type(from) ~= "number" then
        profile.version = target
        return profile
    end

    if from >= target then
        return profile
    end

    for v = from, target - 1 do
        local step = migrations[v]
        if type(step) ~= "function" then
            error(string.format(
                "no settings migration from version %d to %d", v, v + 1), 2)
        end
        step(profile)
    end

    profile.version = target
    return profile
end

-- Names modules may not claim: they already mean something in the profile. A
-- module with such a name would overwrite a housekeeping field, and the
-- settings would disappear silently.
ns.RESERVED_KEYS = {
    version = true,
}

-- Names the core itself placed in the ROOT of the old settings tree. They
-- are not in the profile, so the table above does not catch them, while a
-- collision here was quiet and unpleasant: a module section named general
-- would land on top of the General section, while a module named profiles
-- would itself be overwritten by the profiles section arriving next. The
-- player would see a section gone and never learn why.
--
-- The root held more than sections. The window's header lived there too: the
-- rule under the title, the search box, its clear button and the note about
-- nothing being found — AceConfigDialog drew the root group's settings above
-- the left column. A module named search would overwrite the search box
-- itself, and silently.
--
-- NOTE: this list is history now and is no longer verified against anything.
-- The new window has no AceConfig root — a page is identified by its schema
-- id — and the test that kept this list in step with the root
-- (tests/test_reserved.lua) went with the old window. The ban itself still
-- works and still costs nothing: it only forbids these words as module
-- names. The list once fell three names behind the root, and an edit to its
-- own neighbour did not notice them.
ns.RESERVED_SECTIONS = {
    general     = true,
    profiles    = true,
    demo        = true,
    headerRule  = true,
    modules     = true,
    search      = true,
    searchClear = true,
    searchNote  = true,
}

-- Names the core claims in the database's GLOBAL section (db.global). The
-- two tables above guard the profile, while a module's defaults land not only
-- there: its globals key goes into the global section under the module's own
-- name (ns.InjectModuleDefaults). The core keeps its own things there — the
-- frame-name directory and the client report — and a ban looking only at the
-- profile did not close those keys at all.
--
-- The price of the omission is the profile's, and silent on both sides: a
-- module named report registers successfully, AceDB spreads its defaults into
-- db.global.report, and the first /darken report replaces its entire
-- account-wide store with a diagnostic dump. The module reads version,
-- flavor, groups and tally out of there and never learns why.
--
-- NOTE: this list used to be checked against what the core actually writes
-- into that section (the test read Core/Init.lua) in both directions — a key
-- missing from here failed the run, and so did a name claimed for nothing.
-- That test went with the old window; today the list is kept by hand.
ns.RESERVED_GLOBALS = {
    scan      = true,
    report    = true,
    darkprobe = true,
}

--- Check whether a name is free for a module.
-- @param name string the module's name
-- @param reserved table the table of claimed names (may be nil)
-- @return boolean whether the name is free
-- @return string|nil the error text if it is claimed
function ns.CheckModuleName(name, reserved)
    if type(name) ~= "string" or name == "" then
        return false, ns.Localize("a module name must be a non-empty string")
    end
    if type(reserved) == "table" and reserved[name] then
        return false, string.format(ns.Localize(
            "the name '%s' is reserved for a housekeeping field of the "
                .. "profile"), name)
    end
    return true
end

--- Whether a name is claimed by the core.
-- Three bans in one place: the profile's housekeeping fields (version), the
-- core's own settings (skinAce, showDemo) and the core's keys in the
-- database's global section (scan, report). A module with such a name would
-- overwrite somebody else's data silently — a core setting would disappear
-- and the core would look at fault.
--
-- One check for both paths: our own subsystems pass it in Core/Init.lua while
-- the database is assembled, third-party modules in Core/Api.lua at
-- registration. Two copies of the rule would diverge at the very first new
-- base key.
-- @param name any
-- @return boolean
function ns.ModuleNameTaken(name)
    if type(name) ~= "string" or name == "" then return false end

    if type(ns.RESERVED_KEYS) == "table" and ns.RESERVED_KEYS[name] then
        return true
    end

    if type(ns.RESERVED_SECTIONS) == "table" and ns.RESERVED_SECTIONS[name] then
        return true
    end

    if type(ns.RESERVED_GLOBALS) == "table" and ns.RESERVED_GLOBALS[name] then
        return true
    end

    local base = ns.BaseDefaults and ns.BaseDefaults.profile
    if type(base) == "table" and base[name] ~= nil then
        return true
    end

    return false
end

-- The names of the core's own subsystems, and the prefix reserved for the
-- core.
--
-- A name-collision policy, and one that was chosen rather than that merely
-- came about. The core used to simply claim a name first: its own subsystems
-- register before the game reads other addons, and a third-party module with
-- the same name was refused with "the name is already registered". For a
-- third-party module already written and working that is the worst outcome:
-- it stops working after a core update without having broken any rule. That
-- is exactly what we did by claiming the name bags.
--
-- The decision has two halves.
--
-- 1. The list of the core's subsystem names is closed. It is enumerated here
--    in full and grows no further: a module written today cannot be broken by
--    tomorrow's core update. A new subsystem with a name not on the list used
--    to fail the test run at once rather than six months later on somebody
--    else's client — NOTE: that test (tests/test_reserved.lua) went with the
--    old settings window, and the list is kept by hand today.
--
-- 2. The core_ prefix is reserved for the core. Every future core subsystem
--    takes a name with it, while a module's name carrying that prefix is
--    refused. That way the core has room to grow, and the growth takes
--    nothing from anybody.
--
-- Why the claimed names were not renamed to core_* straight away: a
-- subsystem's name is a key in the SavedVariables profile, and renaming nine
-- keys would cost every player a settings migration for the sake of names
-- that are claimed anyway. The price of the choice is stated plainly: the
-- existing names are unavailable to a third-party module forever, and the
-- refusal says so in words rather than keeping quiet.
ns.CORE_PREFIX = "core_"

ns.CORE_SUBSYSTEMS = {
    darkness   = true,
    fonts      = true,
    unitframes = true,
    nameplates = true,
    texts      = true,
    bags       = true,
    icons      = true,
    launcher   = true,
}

--- Whether a name belongs to the core, from a third-party module's point of
--- view.
--
-- Separate from ns.ModuleNameTaken deliberately. Our own subsystems pass that
-- check too (Core/Init.lua, while the database is assembled), and they are
-- precisely the ones entitled to claim a name like darkness: it is their own.
-- The ban on the subsystem names and on the core's prefix applies only on the
-- public registration path, that is, in Core/Api.lua.
-- @param name any
-- @return boolean
function ns.CoreOwnsName(name)
    if type(name) ~= "string" or name == "" then return false end

    if ns.ModuleNameTaken(name) then return true end
    if ns.CORE_SUBSYSTEMS[name] then return true end

    return name:sub(1, #ns.CORE_PREFIX) == ns.CORE_PREFIX
end

--- Assemble the defaults table for AceDB.
--
-- Moved here out of Core/Init.lua, and not for tidiness. This table decides
-- every setting's fate at logout: AceDB cleans out of the profile everything
-- equal to a default declared here, and puts the default back at load. A
-- setting whose section is not here is not cleaned out at all; a setting
-- whose section is here must come back out of SavedVariables exactly as the
-- player left it. That has to be checked outside the client, and only what is
-- assembled by a pure function can be checked — hence the move: in
-- Core/Init.lua the assembly was locked inside OnInitialize, which does not
-- run without the game.
--
-- There are two sections: profile switches along with the profile, global
-- lives for the whole account. There is deliberately no char section — see
-- Core/Api.lua.
--
-- An impostor name disables the module rather than breaking the load: a
-- third-party module with an unfortunate name has no right to leave the
-- player without a core.
--
-- @param registry table the module registry (ns.Registry or a stand-in)
-- @return table { profile = ..., global = ... }
function ns.BuildDefaults(registry)
    local defaults = { profile = {}, global = {} }

    for key, value in pairs(ns.BaseDefaults.profile) do
        defaults.profile[key] = value
    end

    if type(registry) ~= "table"
        or type(registry.CollectDefaults) ~= "function" then
        return defaults
    end

    local function collect(section, field)
        for name, moduleDefaults in pairs(registry:CollectDefaults(field)) do
            local nameOk, nameErr = ns.CheckModuleName(name, ns.RESERVED_KEYS)
            if ns.ModuleNameTaken(name) then
                nameOk, nameErr = false, string.format(ns.Localize(
                    "the module name '%s' is taken by a core setting"), name)
            end

            if nameOk then
                section[name] = moduleDefaults
            elseif type(registry.Disable) == "function" then
                registry:Disable(name, nameErr)
            end
        end
    end

    collect(defaults.profile, "defaults")
    collect(defaults.global,  "globals")

    return defaults
end
