local ADDON, ns = ...

-- Widget showcase: one instance of each widget kind in its own window.
--
-- Widgets cannot be constructed outside the client, so their appearance is
-- only verifiable by eye. This window made that possible before the settings
-- window was built on top of them.
--
-- It is a development tool: no translations, no settings, no saved position.
-- Reached with /dark widgets.

local Widgets = ns.Widgets
local Skin = ns.Skin
local M = Skin.Metrics

local Try = Widgets.Try

local FRAME_NAME = "DarkenWidgetDemo"

-- Window width, and the number of rows it is sized for.
local WIDE, ROWS = 420, 16

local demo

--- Anchor a widget as the next row, top to bottom.
--
-- Each row hangs off the previous one. Sufficient for a showcase; the
-- settings window computes its own layout in Options/Window.lua.
--
-- @param frame table the widget
-- @param after table|nil previous widget, or nil for the first
-- @param page table the containing frame
-- @param gap number|nil
-- @return table the widget, for chaining
local function stack(frame, after, page, gap)
    if type(frame) ~= "table" then return after end

    Try(frame, "ClearAllPoints")
    if after then
        Try(frame, "SetPoint", "TOPLEFT", after, "BOTTOMLEFT", 0,
            -(gap or M.gap))
        Try(frame, "SetPoint", "TOPRIGHT", after, "BOTTOMRIGHT", 0,
            -(gap or M.gap))
    else
        Try(frame, "SetPoint", "TOPLEFT", page, "TOPLEFT", M.inset,
            -M.inset)
        Try(frame, "SetPoint", "TOPRIGHT", page, "TOPRIGHT", -M.inset,
            -M.inset)
    end
    return frame
end

--- Build the showcase window.
-- @return table|nil
local function build()
    if demo then return demo end

    local frame = Widgets.Frame("Frame", _G.UIParent)
    if frame == nil then return nil end

    Try(frame, "SetSize", WIDE, M.row * ROWS + M.inset * 2)
    Try(frame, "SetPoint", "CENTER", _G.UIParent, "CENTER", 0, 0)
    Try(frame, "SetFrameStrata", "DIALOG")
    Try(frame, "SetMovable", true)
    Try(frame, "EnableMouse", true)
    Try(frame, "RegisterForDrag", "LeftButton")
    Try(frame, "SetScript", "OnDragStart", function(self)
        Try(self, "StartMoving")
    end)
    Try(frame, "SetScript", "OnDragStop", function(self)
        Try(self, "StopMovingOrSizing")
    end)
    Widgets.Dress(frame, "ink", "line")

    local last

    last = stack(Widgets.Header(frame), nil, frame)
    if last and last.text then Try(last.text, "SetText", "WIDGETS") end

    local hint = Widgets.Frame("Frame", frame)
    if hint then
        Try(hint, "SetHeight", M.row * 2)
        local text = Widgets.Hint(hint)
        if text then
            Try(text, "SetText", "Every widget below is drawn by Darken "
                .. "itself. Nothing here is a game widget repainted from "
                .. "the outside.")
        end
        last = stack(hint, last, frame)
    end

    local check = Widgets.CheckBox(frame, "A checkbox", nil)
    last = stack(check, last, frame)

    local slider = Widgets.Slider(frame, "A slider", 0, 100, 1, nil)
    if slider then slider:umbraSet(64) end
    last = stack(slider, last, frame)

    local drop = Widgets.Dropdown(frame, "A dropdown", nil)
    if drop then
        drop:umbraItems({
            { key = "one", text = "First choice" },
            { key = "two", text = "Second choice" },
            { key = "three", text = "Third choice" },
        })
        drop:umbraSet("two")
    end
    last = stack(drop, last, frame)

    local edit = Widgets.EditBox(frame, "An edit box", nil)
    if edit then edit:umbraSet("type here") end
    last = stack(edit, last, frame)

    local row = Widgets.Frame("Frame", frame)
    if row then
        Try(row, "SetHeight", M.row)
        local button = Widgets.Button(row, "A button", function()
            Widgets.Hide()
        end)
        if button then
            Try(button, "ClearAllPoints")
            Try(button, "SetPoint", "LEFT", row, "LEFT", M.rail, 0)
        end

        local off = Widgets.Button(row, "Disabled", nil)
        if off then
            Try(off, "ClearAllPoints")
            Try(off, "SetPoint", "LEFT", button or row, "RIGHT", M.gap, 0)
            Widgets.Disable(off, true)
        end

        last = stack(row, last, frame, M.group)
    end

    demo = frame
    return frame
end

--- Show the window.
function Widgets.Show()
    local frame = build()
    if frame then Try(frame, "Show") end
end

--- Hide the window.
function Widgets.Hide()
    if demo then Try(demo, "Hide") end
end

--- Toggle the window.
-- @return boolean whether it is shown now
function Widgets.Toggle()
    local frame = build()
    if frame == nil then return false end

    local shown = Try(frame, "IsShown") and true or false
    if shown then Try(frame, "Hide") else Try(frame, "Show") end
    return not shown
end
