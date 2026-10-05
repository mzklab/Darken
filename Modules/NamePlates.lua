local ADDON, ns = ...

-- Skinning the game's own nameplates: our textures on the health bar, the
-- colour by class and by reaction, our font on the name, the dimming of the
-- chrome.
--
-- This is skinning rather than a nameplate engine. The subsystem creates no
-- nameplates of its own and does not deal with placement, aura icons, threat
-- thresholds and the rest: the engine is written down as a separate module in
-- the queue of work and will be written separately. Here is the same work the
-- unit frames subsystem already does on the game's own frames for the player
-- and the target.
--
-- Where the colour comes from. From here, nowhere: ns.UnitFrames.BarColor
-- makes the decision "what colour is this bar", and there is no second copy of
-- that rule here. The modes are the same ("by class", "by reaction", "custom
-- colour", the game's native look), the settings' names are the same (health,
-- healthColor, healthFixed, nameColor, nameFixed), and that is why
-- ns.UnitFrames.ApplyBar, ApplyFrameColors and ApplyName suit this place
-- without one edit. One and the same thing on screen has to be decided by one
-- and the same code.
--
-- When to skin. A nameplate does not always exist: the game creates one when a
-- creature appears on screen and takes it back when it leaves. So there is no
-- list of nameplates, and skinning "once at load" would have skinned nothing.
-- The only correct moment is the NAME_PLATE_UNIT_ADDED event: the game sends
-- it exactly when the nameplate is attached to a unit and the unit is already
-- known, and before the player sees it. Before that moment there is no
-- nameplate; after it, the screen would have to be polled by a timer.
--
-- What is not here and will not be. No OnUpdate, no timer, no pass over every
-- nameplate each frame. There can be dozens of them on screen, and each of
-- them updates constantly; everything done per frame costs ten times more here
-- than anywhere else in the addon. The work is done twice: once when a
-- nameplate appears and once after the game has repainted the bar itself (a
-- hook on its functions through hooksecurefunc). Neither of those paths
-- allocates a table.
--
-- A foreign owner. If a real nameplate addon is installed — Plater,
-- Platynator, Threat Plates and the rest — the subsystem stands aside and says
-- so once. Two owners of one bar give flickering and errors: one paints, the
-- other repaints, and the one whose name the player remembers first looks at
-- fault.

local NamePlates = {
    name = "nameplates",
}
ns.NamePlates = NamePlates

-- The tally of what was done (Core/Tally.lua). The reference is taken once
-- while the file is read: the handler on top of the game's function fires as
-- often as the game calls its own function, and it must not cost more than one
-- addition of integers.
local counters = ns.Counters or {}
ns.Counters = counters

-- Hooks installed and hooks fired. The first, were it zero, would mean that
-- not one guessed name of a game function was found; the second, with the
-- first non-zero, would mean the name was found and came to nothing.
counters.hooked_nameplates = counters.hooked_nameplates or 0
counters.fired_nameplates  = counters.fired_nameplates  or 0

-- The names of the game's functions whose hooks have already been
-- counted.
local counted = {}

-- The nameplates THIS subsystem skinned. A zero with the subsystem alive is
-- the very answer the whole tally was devised for: the names were found, the
-- event arrived, and nothing changed on screen.
--
-- The key belongs to the subsystem entirely. The separate engine module counts
-- its own under its own key (plates_engine): while the number was shared, one
-- party's zero hid behind the other's work, and on a fresh install the engine
-- is off — so its zero read as the core's work.
--
-- The claim is released when the subsystem stands aside (OnDisable below) and
-- made again when it comes back (ApplySettings): a subsystem that stood aside
-- does nothing by agreement, and "claimed and never touched" would be untrue
-- of it.
counters.plates = counters.plates or 0

-- How many nameplates the game showed us.
--
-- Needed because "zero skinned" means two different things and they look
-- alike: the subsystem did not work — or there were no nameplates on screen at
-- all. The author's report showed a zero, and there was no telling from it
-- which of the two it was.
--
-- Counted on the event, before any work: the event arrived, so the game showed
-- a nameplate, and what happens next is our business.
counters.plates_seen = counters.plates_seen or 0

-- The marker for "the game's native look". Taken from the unit frames
-- subsystem rather than written out as a string: the value goes into
-- SavedVariables, and two copies would diverge silently.
local NATIVE = ns.UnitFrames and ns.UnitFrames.NATIVE or "__native"

-- The dimming group's key. The same one written down in
-- Modules/Darkness.lua and in Core/Compat.lua: the list of exceptions in the
-- dimming settings works by it.
local GROUP = "nameplate"

-- The font category the name on a nameplate belongs to. A creature's name is
-- a unit's name, and giving it a category of its own would mean splitting two
-- identical texts on screen across two settings.
local FONT_CATEGORY = "unitname"

-- The fields the engine keeps a unit frame in inside a nameplate.
-- Candidates: different builds name the field differently, and whatever is
-- absent is skipped.
local PLATE_FIELDS = { "UnitFrame", "unitFrame" }

-- The name's font string. The same field the unit frames use.
local NAME_FIELDS = { "name" }

-- The marker for "we skinned this frame". It lives in side memory rather
-- than in a field on the unit frame itself: the frame is a game object.
--
-- It exists not for reversibility but for cost. The hook on the repainting
-- functions catches every frame of the game, raid frames included: they are
-- built from the same compact frame. A check against this marker is one
-- comparison, while parsing the unit's name (does it begin with "nameplate")
-- would cost a string search on every repaint of every bar on screen.
local STYLED = ns.Skin.Memory()

-- The marker for "we dimmed this frame". The dimming walks a frame's regions
-- and its children's, and there is no point making that walk with the slider
-- off: without the marker one would have to either walk always or leave the
-- nameplates that had managed to darken dimmed forever.
local DIMMED = ns.Skin.Memory()

-- The brightness factor for the bars is one, that is, do not dim. The same
-- rule and for the same reason as in the unit frames (BAR_FACTOR in
-- Modules/UnitFrames.lua): a bar's fill shows a quantity rather than
-- decorating the interface. The dimming here falls to the nameplate's
-- chrome.
local BAR_FACTOR = 1

-- The addons that skin nameplates themselves.
--
-- Both the addon's name and its global table are checked. The name because an
-- addon may be loaded and not have created anything yet; the table because an
-- addon may sit in a folder under a different name while its engine works all
-- the same. One match is enough.
--
-- The list holds candidates, as everything in this addon does: an unfamiliar
-- name costs nothing, while a missed one costs the player a flickering bar.
local FOREIGN = {
    { addon = "Plater",                  global = "Plater"        },
    { addon = "Platynator",              global = "Platynator"    },
    { addon = "TidyPlates",              global = "TidyPlates"    },
    { addon = "TidyPlates_ThreatPlates", global = "ThreatPlates"  },
    { addon = "TidyPlatesContinued",     global = "TidyPlatesCont" },
    { addon = "NeatPlates",              global = "NeatPlates"    },
    { addon = "Kui_Nameplates",          global = "KuiNameplates" },
    { addon = "nPlates",                 global = "nPlates"       },
}

--- Who in this game owns the nameplates besides us.
--
-- A pure function: the list of loaded addons arrives as a function, the
-- globals as a table. So the rule is tested outside the client, while which
-- spelling of the game's API to use is chosen once at the call site.
--
-- The call of the foreign function is guarded: it arrives from outside, and
-- its raising must not take the subsystem's enabling with it. If it raised, we
-- treat the addon as absent: the worst that follows is that we skin nameplates
-- where we should not, and the player disables the subsystem themselves.
--
-- @param loaded function|nil (name) -> boolean
-- @param globals table|nil a map of name -> object
-- @return string|nil the foreign addon's name
function NamePlates.ForeignOwner(loaded, globals)
    for i = 1, #FOREIGN do
        local entry = FOREIGN[i]

        if type(loaded) == "function" then
            local ok, isLoaded = pcall(loaded, entry.addon)
            if ok and isLoaded then return entry.addon end
        end

        if type(globals) == "table" and globals[entry.global] ~= nil then
            return entry.addon
        end
    end

    return nil
end

--- The unit frame inside a nameplate.
-- A pure function of a table. No field at all means the frame is the nameplate
-- itself: some builds keep the bars directly on it, and a refusal in that case
-- would mean a silently non-working subsystem.
-- @param plate table|nil
-- @return table|nil
function NamePlates.UnitFrameOf(plate)
    if type(plate) ~= "table" then return nil end

    for i = 1, #PLATE_FIELDS do
        local frame = plate[PLATE_FIELDS[i]]
        if type(frame) == "table" then return frame end
    end

    return plate
end

--- The subsystem's settings from the profile.
-- @return table|nil
local function Settings()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    if not profile then return nil end
    return profile[NamePlates.name]
end

-- The textures library. Asked of LibStub once per session: skinning happens
-- for every creature that appears, and fetching the library each time would
-- mean paying for one and the same thing.
local media, mediaAsked

--- @return table|nil
local function Media()
    if mediaAsked then return media end
    mediaAsked = true

    if not LibStub then return nil end
    local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok and type(lib) == "table" then media = lib end
    return media
end

--- The game's nameplate API, if it exists on this client.
-- Asked of the compatibility layer rather than of a version number: the table
-- may be absent, and then there is nothing to skin.
-- @return table|nil
local function Api()
    local names = ns.Compat.Resolve(GROUP)
    for i = 1, #names do
        local object = _G[names[i]]
        if type(object) == "table"
            and type(object.GetNamePlateForUnit) == "function" then
            return object
        end
    end
    return nil
end

--- Whether the subsystem works on this client.
-- An answer of no means there is no point showing the settings section:
-- scrolling lists that affect nothing is worse than not seeing them at all.
-- @return boolean
function NamePlates.Available()
    if NamePlates.standDown then return false end
    if ns.flavor == nil then return false end
    return Api() ~= nil
end

--- Skin one unit frame.
--
-- Everything that happens here is done by the unit frames subsystem: the
-- textures, the bars' colours, the name's colour. The settings' names coincide
-- deliberately — that is how "the same skinning" comes to mean one and the
-- same thing.
--
-- Not one table is allocated: both the textures and the colours read the
-- settings' fields directly, while the unit frames subsystem asks the game for
-- the unit's information itself.
--
-- @param frame table|nil the nameplate's unit frame
-- @param settings table the subsystem's settings
-- @return boolean whether it was skinned
local function style(frame, settings)
    local UF = ns.UnitFrames
    if type(frame) ~= "table" or type(settings) ~= "table" then return false end
    if type(UF) ~= "table" then return false end

    UF.ApplyFrameTextures(frame, settings, Media())
    UF.ApplyFrameColors(frame, settings, BAR_FACTOR)
    UF.ApplyName(frame, settings)

    -- The name's font belongs to the fonts subsystem, and it is that
    -- subsystem that sets it: the rule for choosing it, the memory of the
    -- original value and the list of fonts all live there. From here comes
    -- only the object, which did not yet exist at the moment of the common
    -- pass.
    local fonts = ns.Fonts
    if type(fonts) == "table" and type(fonts.ApplyCategory) == "function" then
        local label = UF.Pick(frame, NAME_FIELDS, "SetFont")
        if label then fonts.ApplyCategory(FONT_CATEGORY, label) end
    end

    -- The dimming of the chrome. The walk over the regions is made only when
    -- a dimming has really been set, or when we have already dimmed this
    -- nameplate and now have to give it its brightness back: ones restore the
    -- remembered colour, while skipping would leave it dark forever.
    local dark = ns.Darkness
    if type(dark) == "table" and type(dark.MultipliersFor) == "function" then
        local dr, dg, db = dark.MultipliersFor(GROUP)
        if dr ~= 1 or dg ~= 1 or db ~= 1 or DIMMED[frame] then
            dark.ApplyToFrame(frame, dr, dg, db)
            DIMMED[frame] = (dr ~= 1 or dg ~= 1 or db ~= 1) or nil
        end
    end

    STYLED[frame] = true
    counters.plates = counters.plates + 1
    return true
end

--- Skin a unit's nameplate.
-- The only entrance from the event. By the event's definition there is no unit
-- without a nameplate at that moment, but the check costs less than an error
-- in combat.
-- @param unit string|nil
-- @return boolean
function NamePlates.StyleUnit(unit)
    if NamePlates.standDown then return false end
    if type(unit) ~= "string" or unit == "" then return false end

    local settings = Settings()
    if not settings then return false end

    local api = Api()
    if not api then return false end

    local ok, plate = pcall(api.GetNamePlateForUnit, unit)
    if not ok then return false end

    return style(NamePlates.UnitFrameOf(plate), settings)
end

--- Every nameplate that is on screen right now.
-- The game creates the table itself, and this function is called only on a
-- change of the settings — not when a creature appears.
-- @return table array of nameplates
local function CurrentPlates()
    local api = Api()
    if not api or type(api.GetNamePlates) ~= "function" then return {} end

    local ok, plates = pcall(api.GetNamePlates)
    if not ok or type(plates) ~= "table" then return {} end
    return plates
end

-- Re-entry guard: our colour is assigned inside the handler of the game's
-- function, and another addon hooked onto the same function may call it
-- again.
local repainting = false

--- Repaint one nameplate after the game has repainted it.
--
-- The hook on the game's functions leads here (the nameplate-recolor group).
-- The frame arrives as an argument — the very one the game has just repainted
-- — so the work is done on one frame rather than on every one on screen.
--
-- Foreign frames are filtered out by one comparison: raid frames are built
-- from the same button as nameplates, and repainting them here would be plain
-- harm.
--
-- @param frame table|nil the unit frame
-- @return boolean
function NamePlates.Repaint(frame)
    if repainting or NamePlates.standDown then return false end
    if type(frame) ~= "table" or not STYLED[frame] then return false end

    local settings = Settings()
    if not settings then return false end

    repainting = true
    local ok = pcall(function()
        ns.UnitFrames.ApplyFrameColors(frame, settings, BAR_FACTOR)
        ns.UnitFrames.ApplyName(frame, settings)
    end)
    repainting = false

    return ok
end

-- The default settings. Everything stands at the game's native look — the
-- same rule as everywhere in the addon: a fresh install replaces not one
-- texture and not one colour, and the native look stays not only the initial
-- one but also a choice.
local textR, textG, textB = ns.Skin.Get("text")

NamePlates.defaults = {
    health      = NATIVE,
    healthColor = NATIVE,
    healthFixed = { r = textR, g = textG, b = textB },
    nameColor   = NATIVE,
    nameFixed   = { r = textR, g = textG, b = textB },
}

--- Apply the settings.
--
-- The only path of application. It passes over the nameplates that are on
-- screen right now: the rest will be skinned at the moment they appear,
-- because there is nothing to skin what does not exist with.
--
-- Called on entering the game, on changing the profile and on editing a
-- setting — that is, a handful of times per session rather than per frame.
function NamePlates:ApplySettings()
    if NamePlates.standDown then return end

    -- The subsystem's return to itself passes through here (Registry:Resume
    -- calls ApplySettings), and the tally's claim comes back along with it.
    counters.plates = counters.plates or 0

    local settings = Settings()
    if not settings then return end

    local plates = CurrentPlates()
    for i = 1, #plates do
        style(NamePlates.UnitFrameOf(plates[i]), settings)
    end
end

--- Disabling the subsystem.
--
-- Needed for one thing: a subsystem a module stood aside stops being the owner
-- of its tally. A claimed zero means "the subsystem is here and did nothing" —
-- that is a failure, and the report names it out loud; a subsystem that stood
-- aside did nothing by agreement, and the same line about it would be a false
-- alarm for everybody who installed the nameplate engine. The report passes
-- over an unclaimed key silently, and that is the truth about it.
--
-- Standing aside only: a subsystem switched off by a failure or by the player
-- answers for its own zero itself.
function NamePlates:OnDisable()
    if NamePlates.standDown then counters.plates = nil end
end

--- Enabling the subsystem.
--
-- Here and only here are the subscriptions created. The settings are not
-- applied: right after OnEnable the registry calls ApplyAll.
function NamePlates:OnEnable()
    -- The subscription goes through the core's door (ns.Events) rather than
    -- through AceEvent. The reason was measured rather than guessed: AceEvent
    -- stores one handler per "event + object" pair, and the object is one and
    -- the same for every subsystem of the core — ns.Addon — so the
    -- subsystems' subscriptions overwrote each other silently. The core's door
    -- stores a subscription under the subsystem's name.
    --
    -- The door can be absent only where it was not loaded (the tests of a
    -- single subsystem); in the game it is always there.
    local me = ns.Registry:NameOf(NamePlates)
    if type(ns.Events) ~= "table" or me == nil then return end

    -- A foreign owner. The addon's name is asked of whichever API exists on
    -- this client: in new builds the function moved into the C_AddOns
    -- table.
    local isLoaded = IsAddOnLoaded
    if type(isLoaded) ~= "function" and type(C_AddOns) == "table" then
        isLoaded = C_AddOns.IsAddOnLoaded
    end

    local owner = NamePlates.ForeignOwner(isLoaded, _G)
    if owner then
        NamePlates.standDown = true

        -- Disabling through the registry rather than by a flag of our own:
        -- it tells the player once, removes the settings section from the
        -- tree and stops calling us. Three things that would otherwise have
        -- to be done separately, each of them as a second owner of a rule
        -- that already exists.
        ns.Registry:Disable(ns.Registry:NameOf(NamePlates) or NamePlates.name,
            string.format(ns.Localize(
                "Nameplates are handled by \"%s\", so Darken leaves them "
                .. "alone: two addons painting one bar give flicker and "
                .. "errors. The nameplate section is hidden."),
                tostring(owner)))
        return
    end

    if not NamePlates.Available() then return end

    -- The only moment when a nameplate exists and its unit is known.
    ns.Events.Subscribe("NAME_PLATE_UNIT_ADDED", me,
        function(_, unit)
            counters.plates_seen = counters.plates_seen + 1
            NamePlates.StyleUnit(unit)
        end)

    -- The hook on the game's functions that paint the bar and the name
    -- themselves. Through hooksecurefunc — after their work rather than
    -- instead of it. The names are taken from the compatibility layer:
    -- whatever does not exist on the client never reaches us.
    if type(hooksecurefunc) == "function" then
        local painters = ns.Compat.Resolve("nameplate-recolor")
        for i = 1, #painters do
            if type(_G[painters[i]]) == "function" then
                if pcall(hooksecurefunc, painters[i], function(frame)
                    counters.fired_nameplates = counters.fired_nameplates + 1
                    NamePlates.Repaint(frame)
                end) then
                    if not counted[painters[i]] then
                        counted[painters[i]] = true
                        counters.hooked_nameplates = counters.hooked_nameplates + 1
                    end
                end
            end
        end
    end

    -- The names on nameplates are targets of the fonts subsystem's unit
    -- names category. The list is assembled at the moment of application: by
    -- the time the file loads not one nameplate exists.
    local fonts = ns.Fonts
    if type(fonts) == "table" and type(fonts.AddTargets) == "function" then
        fonts.AddTargets(FONT_CATEGORY, function()
            local out = {}
            if NamePlates.standDown then return out end

            local plates = CurrentPlates()
            for i = 1, #plates do
                local frame = NamePlates.UnitFrameOf(plates[i])
                local label = ns.UnitFrames.Pick(frame, NAME_FIELDS, "SetFont")
                if label then out[#out + 1] = label end
            end
            return out
        end)
    end
end

--- The get/set handlers for a plain settings field.
-- @param field string
-- @return function, function
local function handlers(field)
    return function()
        local settings = Settings()
        return settings and settings[field]
    end,
    function(_, value)
        local settings = Settings()
        if not settings then return end
        settings[field] = value
        NamePlates:ApplySettings()
    end
end

--- The get/set handlers for a colour field.
-- @param field string
-- @return function, function
local function colorHandlers(field)
    return function()
        local settings = Settings()
        local color = settings and settings[field]
        if type(color) ~= "table" then return 1, 1, 1 end
        return color.r or 1, color.g or 1, color.b or 1
    end,
    function(_, r, g, b)
        local settings = Settings()
        if not settings then return end
        settings[field] = { r = r, g = g, b = b }
        NamePlates:ApplySettings()
    end
end

local getHealth,      setHealth      = handlers("health")
local getHealthColor, setHealthColor = handlers("healthColor")
local getNameColor,   setNameColor   = handlers("nameColor")
local getHealthFixed, setHealthFixed = colorHandlers("healthFixed")
local getNameFixed,   setNameFixed   = colorHandlers("nameFixed")

--- Whether to hide the whole section.
-- There is no client without nameplates, but there is a client without the API
-- one reaches them through, and there is a foreign addon as the owner.
-- @return boolean
local function hidden()
    return not NamePlates.Available()
end

-- The lists of textures and of colour modes are the very same functions the
-- unit frames use. A second list of the same values beside the first would
-- diverge from it at the very first new texture.
NamePlates.options = {
    type = "group",
    name = ns.Localize("Nameplates"),
    hidden = hidden,
    args = {
        about = {
            type = "description",
            order = 1,
            width = "full",
            name = ns.Localize("The addon's look on the game's own " ..
                "nameplates: bar texture, bar color, name color, font and " ..
                "dimming. This is not a nameplate engine - placement, " ..
                "auras and threat thresholds stay with the game. If a real " ..
                "nameplate addon is loaded, this section disappears and " ..
                "Darken does not touch nameplates at all."),
        },

        healthHeader = {
            type = "header",
            order = 10,
            name = ns.Localize("Health Bar"),
        },
        health = {
            type = "select",
            order = 11,
            width = "full",
            name = ns.Localize("Health Bar Texture"),
            desc = ns.Localize("The first entry is the game's own texture: " ..
                "the addon leaves it alone until asked, and going back to " ..
                "it restores exactly the look you had before, at once and " ..
                "without an interface reload. The addon's own textures are " ..
                "a gradient from white to a color. The engine multiplies " ..
                "them by the bar color, so the white end gives the pure " ..
                "color and the pastel end its muted shade. Which color " ..
                "that is, is chosen right below."),
            values = ns.UnitFrames.BarValues,
            sorting = ns.UnitFrames.BarSorting,
            get = getHealth,
            set = setHealth,
        },
        healthColor = {
            type = "select",
            order = 12,
            width = "full",
            name = ns.Localize("Health Bar Color"),
            desc = ns.Localize("The color the texture is tinted by. " ..
                "\"By Class\" applies to players only: creatures have no " ..
                "class, so their bar is colored by reaction to you. The " ..
                "first entry leaves the color to the game, and switching " ..
                "back to it restores the native color at once."),
            values = ns.UnitFrames.HealthModeValues,
            sorting = ns.UnitFrames.HealthModeSorting,
            get = getHealthColor,
            set = setHealthColor,
        },
        healthFixed = {
            type = "color",
            order = 13,
            -- The default colour sits beside the setting as a reference to
            -- the defaults table itself rather than as a retyped number:
            -- otherwise "restore the default" and "what a new player has"
            -- would diverge at the first edit of either. The colour swatch's
            -- skinning reads it (Skin.DefaultColor).
            arg = { default = NamePlates.defaults.healthFixed },
            width = "full",
            name = ns.Localize("Custom Health Bar Color"),
            desc = ns.Localize("Used in \"Custom Color\" mode, and also " ..
                "when neither the class nor the reaction of a unit is " ..
                "known."),
            hasAlpha = false,
            get = getHealthFixed,
            set = setHealthFixed,
        },

        nameHeader = {
            type = "header",
            order = 20,
            name = ns.Localize("Unit Name"),
        },
        nameColor = {
            type = "select",
            order = 21,
            width = "full",
            name = ns.Localize("Name Color"),
            desc = ns.Localize("\"Game's Own Name Color\" leaves the name " ..
                "to the game; switching back to it restores the native " ..
                "color at once. \"By Class\" applies to players only: " ..
                "creatures have no class, so their name is colored by " ..
                "reaction to you. When that is unknown too, the color " ..
                "chosen below is used."),
            values = ns.UnitFrames.NameModeValues,
            sorting = ns.UnitFrames.NameModeSorting,
            get = getNameColor,
            set = setNameColor,
        },
        nameFixed = {
            type = "color",
            order = 22,
            -- The default colour sits beside the setting as a reference to
            -- the defaults table itself rather than as a retyped number:
            -- otherwise "restore the default" and "what a new player has"
            -- would diverge at the first edit of either. The colour swatch's
            -- skinning reads it (Skin.DefaultColor).
            arg = { default = NamePlates.defaults.nameFixed },
            width = "full",
            name = ns.Localize("Custom Name Color"),
            desc = ns.Localize("Used in \"Custom Color\" mode, and also " ..
                "when neither the class nor the reaction of a unit is " ..
                "known."),
            hasAlpha = false,
            get = getNameFixed,
            set = setNameFixed,
        },

        fontNote = {
            type = "description",
            order = 30,
            width = "full",
            name = ns.Localize("Font and dimming for nameplates are set " ..
                "elsewhere and on purpose: the name uses the \"Unit Names\" " ..
                "font category, and dimming follows the Interface Darkness slider, " ..
                "where \"Nameplates\" can be excluded like any other group."),
        },
    },
}

--============================================================================
-- The settings page, declared as data
--============================================================================

-- The lists of values are taken from the unit frames rather than created
-- anew. A bar's texture and the rule for its colour are one and the same
-- question wherever the bar stands, and two lists about one thing would
-- diverge when a texture was added.

if type(ns.Schema) == "table" then
    local Schema = ns.Schema
    local PAGE = "nameplates"

    Schema.Page(PAGE, {
        title = "Nameplates",
        order = 6,
        section = "nameplates",
    })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "The bars the game draws over heads. The first entry in "
            .. "every list is the game's own look.",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Health Bar Texture",
        path = { "health" },
        apply = "nameplates",
        hint = "The texture the health bar is drawn with. The first entry "
            .. "leaves the game's own.",
        values = function()
            local from = ns.UnitFrames and ns.UnitFrames.BarValues
            if type(from) == "function" then return from() end
            return {}
        end,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Health Bar Color",
        path = { "healthColor" },
        apply = "nameplates",
        hint = "What the health bar's colour means: the game's own rule, "
            .. "the class of whoever it belongs to, or one colour you pick.",
        values = function()
            local from = ns.UnitFrames and ns.UnitFrames.HealthModeValues
            if type(from) == "function" then return from() end
            return {}
        end,
    })

    Schema.Add(PAGE, {
        kind = "color",
        label = "Health Bar Fixed Color",
        path = { "healthFixed" },
        apply = "nameplates",
        hint = "The one colour used when the health bar is set to a fixed "
            .. "colour above.",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Unit Name Color",
        path = { "nameColor" },
        apply = "nameplates",
        hint = "What the unit's name is coloured by: the game's own rule, "
            .. "the unit's class, or one colour you pick.",
        values = function()
            local from = ns.UnitFrames and ns.UnitFrames.NameModeValues
            if type(from) == "function" then return from() end
            return {}
        end,
    })

    Schema.Add(PAGE, {
        kind = "color",
        label = "Unit Name Fixed Color",
        path = { "nameFixed" },
        apply = "nameplates",
        hint = "The one colour used when the name is set to a fixed colour "
            .. "above.",
    })
end

ns.Registry:Register(NamePlates)
