-- The durability module: a readout of the gear's wear as a separate block on
-- screen.
--
-- The registering file. Everything that decides what to show lies in
-- Rules.lua; everything that draws, in Block.lua. Here there is only the
-- joint with the core: the descriptor, the settings, the event, the command
-- and the mover handle.

local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("durability")

-- The core may be absent entirely: the player switched it off in the addon
-- list. One readable line rather than a Lua error.
--
-- The name in the line is this part's. It used to be the name of the separate
-- addon the part was before it moved inside Darken, and a line naming an
-- addon the player cannot find in their list explains nothing.
if type(_G.Darken) ~= "table"
    or type(_G.Darken.RegisterModule) ~= "function" then
    print("|cffff4040Darken Durability|r: Darken is not loaded, so this part "
        .. "does nothing.")
    return
end

-- The contract version this module is written for. The mover handle appeared
-- in the fourteenth (handle:RegisterElement), and without it the block has
-- nowhere to stand. The sixteenth for two things at once: the module
-- translates the handle's label itself (otherwise no
-- translation-completeness check sees its key), and the core's palette gained
-- an alarm colour, without which the wear readout had nothing to say "bad"
-- with.
local API = 16

-- The module's name and the command's word are written as literals in the
-- descriptor below rather than substituted from here: the project's tools
-- read them from the source rather than from a running addon, and a constant
-- is blank space to them.

-- The game event the readout updates on. There is no timer polling here and
-- must not be: durability changes rarely and always with an event.
local EVENT = "UPDATE_INVENTORY_DURABILITY"

local DEFAULTS = {
    -- A fresh installation changes nothing: the player switches the readout
    -- on.
    enabled    = false,
    alwaysShow = false,
    warnBelow  = 35,
}

--============================================================================
-- Reading the game
--============================================================================

--- The durability readings for every equipment slot.
-- @return table|nil array of { slot, label, current, maximum }; nil when this
--   client has no durability at all
local function readings()
    local ask = _G.GetInventoryItemDurability
    if type(ask) ~= "function" then return nil end

    local slots = ns.Rules.SLOTS
    local out = {}
    for i = 1, #slots do
        local current, maximum = ask(slots[i].slot)
        if current and maximum then
            out[#out + 1] = {
                slot    = slots[i].slot,
                label   = slots[i].label,
                current = current,
                maximum = maximum,
            }
        end
    end

    return out
end

--============================================================================
-- The descriptor
--============================================================================

local module

--- One settings field's accessors.
-- @param key string the field's name in the settings
-- @return function, function get and set
local function field(key)
    local function get()
        local settings = module:GetSettings()
        return settings and settings[key]
    end

    local function set(_, value)
        local settings = module:GetSettings()
        if not settings then return end
        settings[key] = value
        module:Apply()
    end

    return get, set
end

--- Bring the block into line with the settings.
local function refresh(self)
    module = self or module
    local settings = module:GetSettings()
    if not settings then return end

    if not settings.enabled then
        ns.Block.SetShown(false)
        return
    end

    if not ns.Block.Build() then return end

    -- The block's place. The core's mover used to hold it; the mover was
    -- removed from the addon, and the block stands where it stood by default
    -- — under the top edge of the screen.
    local frame = ns.Block.frame
    local root = _G.UIParent
    if type(frame) == "table" and type(frame.SetPoint) == "function"
        and type(root) == "table" then
        if type(frame.ClearAllPoints) == "function" then
            pcall(frame.ClearAllPoints, frame)
        end
        pcall(frame.SetPoint, frame, "TOP", root, "TOP", 0, -180)
    end

    local worst = ns.Rules.Worst(readings())
    local percent = worst and ns.Rules.Percent(worst.current, worst.maximum)
    local state = ns.Rules.State(percent, settings.warnBelow)

    local text = nil
    if percent then
        text = string.format(module:Localize("Durability %d%%"), percent)
    elseif settings.alwaysShow then
        -- There are no readings while the block was asked to be shown: an
        -- empty panel explains nothing, while this line explains everything —
        -- this character is wearing nothing with durability right now.
        text = module:Localize("Durability: nothing to wear out")
    end

    ns.Block.Paint(text, ns.Rules.Tint(state))
    ns.Block.SetShown(ns.Rules.Visible(state, settings.alwaysShow))
end

--- Report the most worn item in chat.
local function report(self)
    module = self or module
    local worst = ns.Rules.Worst(readings())
    local percent = worst and ns.Rules.Percent(worst.current, worst.maximum)

    if not percent then
        module:Print(module:Localize("no equipped item has durability"))
        return
    end

    module:Print(string.format(module:Localize("%s at %d%%"),
        module:Localize(worst.label), percent))
end

local OPTIONS
do
    local enabledGet, enabledSet = field("enabled")
    local alwaysGet, alwaysSet = field("alwaysShow")
    local warnGet, warnSet = field("warnBelow")

    -- The labels are functions rather than strings: the file is read before
    -- registration returns the handle, and there is nothing to translate a
    -- string with at that moment. AceConfig called name and desc while
    -- drawing, that is, much later.
    OPTIONS = {
        type = "group",
        name = function() return module:Localize("Darken Durability") end,
        args = {
            enabled = {
                type  = "toggle",
                order = 1,
                width = "full",
                name  = function()
                    return module:Localize("Show the Durability Block")
                end,
                desc  = function()
                    return module:Localize(
                        "A block on screen with the durability of the worst "
                        .. "piece of equipment you are wearing. Off by "
                        .. "default - a fresh install changes nothing.")
                end,
                get = enabledGet,
                set = enabledSet,
            },
            alwaysShow = {
                type  = "toggle",
                order = 2,
                width = "full",
                name  = function() return module:Localize("Always Show") end,
                desc  = function()
                    return module:Localize(
                        "Keep the block on screen even when nothing is worn "
                        .. "out.")
                end,
                get = alwaysGet,
                set = alwaysSet,
            },
            warnBelow = {
                type  = "range",
                order = 3,
                min   = 5,
                max   = 95,
                step  = 5,
                name  = function() return module:Localize("Warn Below") end,
                desc  = function()
                    return module:Localize(
                        "Below this percent the block is drawn in the warning "
                        .. "color.")
                end,
                get = warnGet,
                set = warnSet,
            },
        },
    }
end

module = _G.Darken:RegisterModule({
    name     = "umbradurability",
    api      = API,
    defaults = DEFAULTS,
    options  = OPTIONS,

    OnEnable = function(self)
        -- The module learns about itself from self. Since contract version
        -- 16 that is no longer necessary — RegisterModule returns the handle
        -- before the core calls the handlers — but it is still correct, and
        -- correct in any version of the contract.
        module = self

        for locale, strings in pairs(ns.Locales or {}) do
            self:RegisterStrings(locale, strings)
        end

        self:RegisterEvent(EVENT, function() refresh(self) end)
        self:RegisterCommand("dura", function() report(self) end)
    end,

    ApplySettings = function(self)
        refresh(self)
    end,

    OnDisable = function()
        -- The core stopped calling us: take everything of ours off the
        -- screen. The block's position stays in the core's profile meanwhile
        -- and goes nowhere.
        ns.Block.SetShown(false)
    end,
})

if not module then return end

--============================================================================
-- The settings page, declared as data
--============================================================================

-- A tab inside the gear page rather than a row of its own in the column.
-- Item level and durability are two rows about one and the same thing: the
-- items being worn. The author said so outright: item level simply in the
-- menu, but he would combine it into one tab with durability.

if type(core.Schema) == "table" then
    local Schema = core.Schema
    local PAGE = "umbradurability"

    Schema.Page("gear", {
        title = "Gear",
        order = 9,
    })

    Schema.Page(PAGE, {
        title = "Durability",
        order = 9.2,
        section = "umbradurability",
        parent = "gear",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show the Durability Block",
        path = { "enabled" },
        apply = "umbradurability",
        hint = "A block on screen with the durability of the worst-worn "
            .. "piece of equipment you are wearing. Off by default - a "
            .. "fresh install changes nothing.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Always Show",
        path = { "alwaysShow" },
        apply = "umbradurability",
        hint = "Keep the block on screen even when nothing is worn out.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Warn Below",
        path = { "warnBelow" },
        min = 5, max = 95, step = 5,
        apply = "umbradurability",
        hint = "Below this percent the block is drawn in the warning "
            .. "colour.",
    })
end
