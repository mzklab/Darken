local ADDON, ns = ...

-- The grid of slots in the game's own bag window: an outline around every
-- slot.
--
-- Why one setting is all that is left here. The subsystem used to offer "dark
-- bags": it put the window's native artwork out, laid its own fill with a
-- border underneath and repainted the labels. There was a point to that while
-- the dimming reached an enumerated list of frames. Today the dimming walks
-- the interface and reaches every window of the game, the bag windows
-- included — and "dark bags" became a second way of saying the same thing,
-- only louder: one dimming was laid over the common one.
--
-- The author saw it as a row of its own in the column of sections and said
-- that it was a pointless setting: if the dimming is on, it applies to
-- everything, so why is there a menu entry for this. They were right: the
-- choice is gone, and the row in the column is gone with it.
--
-- What is left is what the dimming cannot do and cannot be made to do: a line
-- where there is none. The dimming multiplies the colour of artwork that
-- already exists, while a grid of slots has to be drawn. So the outline lives
-- on — and lives on the dimming's page, beside the slider that makes a window
-- dark (Config/Options.lua, ns.INLINE_SECTIONS).
--
-- How this group of frames differs from the dimming subsystem's bags group.
-- There it is the bag buttons on the main bar and the micro menu, that is,
-- what is always visible. Here it is the windows with the items themselves
-- (the bag-window group), which the game opens when those buttons are
-- clicked. One texture has no two owners: the groups do not overlap, and that
-- has been checked by eye against Core/Compat.lua.
--
-- Reversibility. The subsystem deliberately does not use Skin.StripTextures: a
-- texture that was stripped does not come back, while a setting that is
-- switched off has to return the native look without a reload of the interface
-- — that is what the addon's general rule about native defaults demands. The
-- outline is a texture of our own, and switching it off hides it rather than
-- deleting it: a texture cannot be released in this API anyway, and showing it
-- again is cheaper than creating it afresh.
--
-- The default is the game's native look: a fresh install does not outline the
-- slots.

local Bags = {
    name = "bags",
}
ns.Bags = Bags

-- The tally of what was done (Core/Tally.lua). The reference is taken once
-- while the file is read: the handler on top of the game's function fires as
-- often as the game calls its own function, and it must not cost more than one
-- addition of integers.
local counters = ns.Counters or {}
ns.Counters = counters

-- Hooks installed and hooks fired. The first, were it zero, would mean that
-- not one guessed name of a game function was found; the second, with the
-- first non-zero, would mean the name was found and came to nothing.
counters.hooked_bags = counters.hooked_bags or 0
counters.fired_bags  = counters.fired_bags  or 0

-- The names of the game's functions whose hooks have already been
-- counted.
local counted = {}

-- Where a slot's outline texture set is kept for a slot button (see
-- Skin.Outline).
local SLOT_BORDER = ns.Skin.Memory()

-- A slot's outline is kept in side memory rather than in a field on the slot
-- itself: a bag slot is a game object, and a field on it would mark it (see the
-- explanation at ns.Skin.Outline).

--- The outline we built on this slot, or nil.
--
-- Exposed for the same reason Darkness.Remembered is: the question "have you
-- touched this object" used to be put to a field on the object itself, the
-- field is gone, and the question remains.
--
-- @param button table|nil the bag slot
-- @return table|nil the outline's sides
function Bags.Border(button)
    if type(button) ~= "table" then return nil end
    return SLOT_BORDER[button]
end

-- The outline's colour. The same one the addon draws all its lines with: a
-- slot's outline and the border of any of our windows stand side by side on
-- screen, and two different shades would read as a mistake.
local BORDER_COLOR = "line"

-- The default is the game's native look: a fresh install does not outline the
-- slots.
--
-- This used to be true, and the outline was part of "dark bags": with the
-- window in its native look it was not drawn at all, so a fresh install did
-- not show it. That look is gone, and so that nothing changed for those who
-- are already playing, the default moved to false while the outline was
-- written explicitly for those who had chosen the dark bags — migration 7 -> 8
-- in Core/Defaults.lua.
Bags.defaults = {
    slotBorder = false,
}

--- The subsystem's settings from the profile.
-- @return table|nil
local function Settings()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    if not profile then return nil end
    return profile[Bags.name]
end

--- The list of a group's names that exist.
-- Wrapped in pcall: outside the game ns.flavor is not set and Resolve is
-- bound to raise — but the subsystem must then simply do nothing.
-- @param group string
-- @return table array of names
local function resolve(group)
    local ok, names = pcall(ns.Compat.Resolve, group)
    if ok and type(names) == "table" then return names end
    return {}
end

--- Show or hide a set of our textures.
-- @param set table|nil a texture, or a table of textures
-- @param show boolean
local function display(set, show)
    if type(set) ~= "table" then return end

    if type(set.Show) == "function" and type(set.Hide) == "function" then
        if show then pcall(set.Show, set) else pcall(set.Hide, set) end
        return
    end

    for _, texture in pairs(set) do
        display(texture, show)
    end
end

--- Outline the slot buttons of one window.
-- @param frameName string the bag window's name
-- @param border boolean whether to draw the outline
local function paintSlots(frameName, border)
    local candidates = ns.Compat.BagSlotNames(frameName)
    local names = ns.Compat.FilterExisting(candidates, _G)

    for i = 1, #names do
        local button = _G[names[i]]
        if type(button) == "table" then
            if border then
                ns.Skin.Outline(button, SLOT_BORDER, button, BORDER_COLOR)
                display(SLOT_BORDER[button], true)
            else
                display(SLOT_BORDER[button], false)
            end
        end
    end
end

--- Outline the slots of one bag window.
-- The outline is created when first needed and after that lives on the slot
-- button itself: switching it off hides it, switching it on shows it again.
-- @param frameName string the window's name
-- @param border boolean whether to draw the slots' outline
-- @return boolean whether the window was found
function Bags.Paint(frameName, border)
    local frame = _G[frameName]
    if type(frame) ~= "table" then return false end

    paintSlots(frameName, border == true)

    return true
end

--- Apply the settings.
-- The only path of application: entering the game, changing the profile,
-- editing a setting and the game repainting a bag itself all lead here.
function Bags:ApplySettings()
    local settings = Settings()
    if not settings then return end

    local names = resolve("bag-window")
    for i = 1, #names do
        Bags.Paint(names[i], settings.slotBorder == true)
    end
end

--- Enabling the subsystem.
--
-- Here and only here are the handlers on top of the game's functions
-- installed. The game repaints a bag window itself — when it opens, when an
-- item is received, when a bag is changed — and our styling would be
-- overwritten after that. The handler is installed after the game's function
-- rather than instead of it: both the engine itself and other addons call the
-- repaint.
function Bags:OnEnable()
    if type(hooksecurefunc) == "function" then
        local names = resolve("bag-repaint")
        for i = 1, #names do
            if type(_G[names[i]]) == "function" then
                if pcall(hooksecurefunc, names[i], function()
                    counters.fired_bags = counters.fired_bags + 1
                    Bags:ApplySettings()
                end) then
                    if not counted[names[i]] then
                        counted[names[i]] = true
                        counters.hooked_bags = counters.hooked_bags + 1
                    end
                end
            end
        end
    end

    -- The subscription goes through the core's door (ns.Events) rather than
    -- through AceEvent. The reason was measured rather than guessed: AceEvent
    -- stores one handler per "event + object" pair, and the object is one and
    -- the same for every subsystem of the core — ns.Addon. Five subsystems
    -- asked for PLAYER_ENTERING_WORLD and four for PLAYER_REGEN_ENABLED, and
    -- exactly the last one registered survived in each pair; the other
    -- subscriptions vanished silently. The core's door stores a subscription
    -- under the subsystem's name, so they cannot collide.
    --
    -- The door can be absent only where it was not loaded (the tests of a
    -- single subsystem); in the game it is always there.
    local me = ns.Registry:NameOf(Bags)
    if type(ns.Events) ~= "table" or me == nil then return end

    -- A bag's contents change more often than anything else on screen, and
    -- every change repaints the slots. There is one event: the rest is brought
    -- by the handler on top of the game's functions above.
    ns.Events.Subscribe("BAG_UPDATE_DELAYED", me, function()
        Bags:ApplySettings()
    end)
end

-- The subsystem's section. It no longer stands as a row in the column of
-- sections: its one remaining setting arrives as an inline block on the
-- dimming's page (Config/Options.lua, ns.INLINE_SECTIONS). The section
-- nevertheless stays a section — the same table under the same subsystem name
-- — because it is the settings tree that assigns a section its place, not the
-- module.
Bags.options = {
    type = "group",
    name = ns.Localize("Game Bags"),
    args = {
        slotBorder = {
            type = "toggle",
            order = 1,
            width = "full",
            name = ns.Localize("Bag Slot Borders"),
            desc = ns.Localize("Draws a one pixel border around every slot "
                .. "in the game's own bag windows, so that the grid reads "
                .. "as a grid. This is the one thing dimming cannot do for "
                .. "the bags by itself: dimming multiplies the artwork that "
                .. "is already there, and a line that is not there cannot "
                .. "be multiplied. Off to start with, and switching it off "
                .. "takes the line away at once, with no interface reload."),
            get = function()
                local settings = Settings()
                return settings ~= nil and settings.slotBorder == true
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.slotBorder = value and true or false
                Bags:ApplySettings()
            end,
        },
    },
}

--============================================================================
-- The settings page, declared as data
--============================================================================

-- One setting, and it does not create a page of its own: a row in the column
-- for a single checkbox is a row that is opened once and never again. So the
-- checkbox is nested into the dimming's page: the bags darken along with
-- everything else, and the outline of their slots is part of the same
-- conversation.

if type(ns.Schema) == "table" then
    ns.Schema.Add("darkness", {
        kind = "toggle",
        label = "Outline Bag Slots",
        apply = "bags",
        hint = "Draw a thin line around every bag slot. The game draws the "
            .. "slots themselves; this only adds the outline.",
        get = function()
            local db = ns.Addon and ns.Addon.db
            local profile = db and db.profile
            local part = profile and profile[Bags.name]
            return part and part.slotBorder or false
        end,
        set = function(value)
            local db = ns.Addon and ns.Addon.db
            local profile = db and db.profile
            local part = profile and profile[Bags.name]
            if type(part) ~= "table" then return end
            part.slotBorder = value and true or false
        end,
    })
end

ns.Registry:Register(Bags)
