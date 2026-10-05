local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("infopanel")

-- Clicking and hovering a cell: what belongs to the readout by the standard
-- and what the panel adds of its own.
--
-- There is not one call into the game here. In come a registry object and the
-- settings; out comes an intent: which handlers the readout has, what to show
-- in the tooltip, and which rows the menu is built from. Panel.lua draws that,
-- this file decides it, and so the decision is entirely testable outside the
-- client.
--
-- === Whose click is whose ===
--
-- LibDataBroker describes four mouse handlers on a readout: OnClick, OnEnter,
-- OnLeave and OnTooltipShow. They belong to whoever created the readout, and
-- the panel has no right to substitute them: an addon whose click opens its
-- own window must open it from our bar too.
--
-- Hence:
--
-- * the left button belongs entirely to the standard. There is an OnClick — it
--   is called; there is none — nothing happens;
-- * the right button opens the panel's menu, and opens it for every cell
--   without exception;
-- * the readout's own action does not vanish from the menu: when it has an
--   OnClick, it stands as the menu's first row. Having taken the right button
--   away from the readout, we are obliged to give it back in one click rather
--   than keep it.
--
-- The rule is written so that it cannot tell our readouts from other people's:
-- the menu is built from the cell's name and from what the object answers
-- about itself. Neither our name prefix nor any access to the table of our own
-- readouts appears in this file at all, and a test watches this very text in
-- the source. An "is this ours" branch would make a foreign readout a
-- second-class citizen, and the whole module is written against precisely
-- that.

local Cells = {}
ns.Cells = Cells

-- The standard's handler names. As strings in one place: a typo in any of
-- them would silently give a dead mouse.
local ONCLICK = "OnClick"
local ONENTER = "OnEnter"
local ONLEAVE = "OnLeave"
local ONTOOLTIP = "OnTooltipShow"
local TOOLTIPTEXT = "tooltiptext"

--- Read a field of a registry object.
--
-- Through pcall, because the object is somebody else's: in the real library a
-- metatable stands behind the field, so reading it runs foreign code, which is
-- entitled to raise.
-- @param object table|nil
-- @param key string
-- @return any
local function attribute(object, key)
    if type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if not ok then return nil end
    return value
end

--- The readout's handler under this name, if it has one.
-- @param object table|nil
-- @param key string
-- @return function|nil
function Cells.Handler(object, key)
    local value = attribute(object, key)
    if type(value) == "function" then return value end
    return nil
end

--- What the readout can do by itself.
-- @param object table|nil
-- @return table { click, enter, leave, tooltip }
function Cells.Offers(object)
    local text = attribute(object, TOOLTIPTEXT)
    return {
        click = Cells.Handler(object, ONCLICK) ~= nil,
        enter = Cells.Handler(object, ONENTER) ~= nil,
        leave = Cells.Handler(object, ONLEAVE) ~= nil,
        tooltip = Cells.Handler(object, ONTOOLTIP) ~= nil
            or (type(text) == "string" and text ~= ""),
    }
end

--- What to show on hover.
--
-- The order is the standard's, from the most particular to the most general: a
-- readout that draws its own tooltip draws it itself; after it, the one that
-- asks to fill somebody else's tooltip; after that, ready-made text; and only
-- when there is nothing at all does the panel show what it already has — the
-- label and the value.
--
-- An intent is returned rather than a drawn tooltip: drawing is the display's
-- business, while the choice of branch is tested here.
-- @param object table|nil
-- @param label string|nil
-- @param text string|nil
-- @return table { kind = "own"|"fill"|"text"|"cell", fn = ..., text = ... }
function Cells.Tooltip(object, label, text)
    local own = Cells.Handler(object, ONENTER)
    if own then return { kind = "own", fn = own } end

    local fill = Cells.Handler(object, ONTOOLTIP)
    if fill then return { kind = "fill", fn = fill } end

    local ready = attribute(object, TOOLTIPTEXT)
    if type(ready) == "string" and ready ~= "" then
        return { kind = "text", text = ready }
    end

    return { kind = "cell", label = label, text = text }
end

--- Call the readout's own click handler.
-- @param object table|nil
-- @param frame any the cell's frame — the standard passes it as the first
--     argument
-- @param button string|nil the mouse button's name
-- @return boolean whether there was anybody to call
function Cells.Click(object, frame, button)
    local fn = Cells.Handler(object, ONCLICK)
    if not fn then return false end

    -- A foreign handler under a guard: a foreign click that raises has no
    -- right to bring the panel down, let alone to disable our module.
    pcall(fn, frame, button)
    return true
end

--- Call the readout's own mouse-leave handler.
-- @param object table|nil
-- @param frame any
-- @return boolean
function Cells.Leave(object, frame)
    local fn = Cells.Handler(object, ONLEAVE)
    if not fn then return false end
    pcall(fn, frame)
    return true
end

--- A cell's menu.
--
-- Everything the panel can do to one cell without sending the player off to
-- the settings: hide it, move it, send it to the other bar. Plus, when it
-- exists, the readout's own action as the first row.
--
-- The contents are computed from the name and the settings and have no other
-- input: for two readouts with the same place in the row and the same bar the
-- menu matches letter for letter, whoever created them.
--
-- @param name string the cell's name in the registry
-- @param settings table|nil the module's settings
-- @param arranged table|nil the full order of cells (ns.Layout.Arrange)
-- @param offers table|nil the answer from Cells.Offers
-- @return table array of menu rows
function Cells.Menu(name, settings, arranged, offers)
    local out = {}
    if type(name) ~= "string" or name == "" then return out end

    settings = type(settings) == "table" and settings or {}
    arranged = type(arranged) == "table" and arranged or {}

    local at
    for i = 1, #arranged do
        if arranged[i] == name then at = i break end
    end

    if type(offers) == "table" and offers.click then
        out[#out + 1] = {
            kind = "own",
            label = ns.Localize("What This Metric Does Itself"),
            enabled = true,
        }
    end

    out[#out + 1] = {
        kind = "hide",
        label = ns.Localize("Hide This Cell"),
        enabled = true,
    }

    -- There is nowhere to move it — the row is still in place, but greyed.
    -- A row that disappears shifts its neighbours, and the player clicks
    -- something other than what they saw a moment ago.
    out[#out + 1] = {
        kind = "move",
        delta = -1,
        label = ns.Localize("Move Earlier"),
        enabled = at ~= nil and at > 1,
    }
    out[#out + 1] = {
        kind = "move",
        delta = 1,
        label = ns.Localize("Move Later"),
        enabled = at ~= nil and at < #arranged,
    }

    local side = type(settings.sides) == "table" and settings.sides[name] or nil
    if not (ns.Layout and ns.Layout.SIDES[side]) then
        side = settings.defaultSide
        if not (ns.Layout and ns.Layout.SIDES[side]) then side = "top" end
    end

    out[#out + 1] = {
        kind = "side",
        side = "top",
        label = ns.Localize("Move to the Top Bar"),
        enabled = settings.top == true and side ~= "top",
    }
    out[#out + 1] = {
        kind = "side",
        side = "bottom",
        label = ns.Localize("Move to the Bottom Bar"),
        enabled = settings.bottom == true and side ~= "bottom",
    }

    return out
end

--- Carry out the chosen menu row.
--
-- Only the settings change: the repaint is called by whoever called this. The
-- "the readout's own action" row does not reach here — Cells.Click performs
-- it, because it is not the panel that performs it.
-- @param entry table|nil a menu row
-- @param name string the cell's name
-- @param settings table|nil the settings
-- @param names table|nil the names from the registry
-- @return boolean whether anything changed
function Cells.Apply(entry, name, settings, names)
    if type(entry) ~= "table" or type(settings) ~= "table" then return false end
    if type(name) ~= "string" or name == "" then return false end
    if entry.enabled == false then return false end

    if entry.kind == "hide" then
        settings.hidden = type(settings.hidden) == "table" and settings.hidden or {}
        settings.hidden[name] = true
        return true
    end

    if entry.kind == "move" then
        if not ns.Layout then return false end
        settings.order = ns.Layout.Move(names, settings.order, name, entry.delta)
        return true
    end

    if entry.kind == "side" then
        if not (ns.Layout and ns.Layout.SIDES[entry.side]) then return false end
        settings.sides = type(settings.sides) == "table" and settings.sides or {}
        settings.sides[name] = entry.side
        return true
    end

    return false
end
