local ADDON, ns = ...

-- A single-line text field.
--
-- === Text inset ===
--
-- INSET is applied once, at construction. The old window had to patch the
-- library's edit box because it set a zero left inset, so the first
-- character touched the border; the patch also had to re-apply the inset
-- whenever foreign code overwrote it. Owning the widget removes both.
--
-- === Focus state ===
--
-- The border brightens on focus, not only on hover, because focus answers
-- "where does typing go" and must stay visible after the pointer moves away.
-- Precedence is disabled > focused > hovered, decided by Skin.FieldState and
-- tested there.

local Widgets = ns.Widgets
local Skin = ns.Skin
local M = Skin.Metrics

-- Fields share one width with dropdowns and slider rows: they stack in a
-- single column, and unequal right edges read as unrelated controls.
local FIELD = Widgets.CONTROL

local Try = Widgets.Try

-- Text inset from the border. Same value as the checkbox-to-label gap: one
-- inset for the whole window.
local INSET = M.gap

--- Repaint the field for its current state.
-- @param frame table the border frame, not the edit box
local function restyle(frame)
    if type(frame) ~= "table" then return end
    local state = Skin.FieldState(frame.umbraOff, frame.umbraFocus,
        frame.umbraOver)
    Widgets.Wear(frame, state, "select")

    if frame.box then
        Skin.Text(frame.box, frame.umbraOff and "textFaint" or "text")
    end
end

--- Build a text field.
--
-- @param parent table
-- @param text any label; nil or "" makes the field span the row
-- @param onCommit function|nil called with the text on Enter
-- @return table|nil
function Widgets.EditBox(parent, text, onCommit)
    local frame = Widgets.Frame("Frame", parent)
    if frame == nil then return nil end

    -- One row: label left, field right, matching dropdown and slider.
    Try(frame, "SetHeight", M.row)

    local label = Widgets.Text(frame, "text")
    if label then
        Try(label, "SetPoint", "LEFT", frame, "LEFT", M.rail, 0)
        Try(label, "SetText", text)
    end
    frame.label = label

    local field = Widgets.Frame("Frame", frame)
    if field == nil then return frame end

    -- Unlabelled fields span the row. The search box is the only one: it is
    -- not a setting in a column and has no label to align with.
    local alone = text == nil or text == ""

    Try(field, "SetHeight", M.row - M.edge * 2)
    if alone then
        Try(field, "SetPoint", "LEFT", frame, "LEFT", M.rail, 0)
        Try(field, "SetPoint", "RIGHT", frame, "RIGHT", -M.rail, 0)
    else
        Try(field, "SetWidth", FIELD)
        Try(field, "SetPoint", "RIGHT", frame, "RIGHT", -M.rail, 0)

        if label then
            -- Bound the label on the right at the field edge. Without it a
            -- long label runs under the field and overlaps its value;
            -- "Font Size Adjustment" did exactly that.
            Try(label, "SetPoint", "RIGHT", field, "LEFT", -M.gap, 0)
            Try(label, "SetWordWrap", false)
        end
    end
    frame.field = field

    local box = Widgets.Frame("EditBox", field)
    if box == nil then return frame end

    Try(box, "SetAllPoints", field)
    Try(box, "SetAutoFocus", false)
    Try(box, "SetFontObject", "GameFontHighlight")
    Try(box, "SetTextInsets", INSET, INSET, 3, 3)
    field.box = box
    frame.box = box

    -- SetCursorColor is missing on some clients. Where present the caret is
    -- tinted; where absent the focus border is the only cue, which is why it
    -- is not optional.
    Try(box, "SetCursorColor", Skin.Get("lilac"))
    Try(box, "SetHighlightColor", Skin.Get("lilacDeep", 0.6))

    Try(box, "SetScript", "OnEnter", function()
        field.umbraOver = true
        restyle(field)
    end)
    Try(box, "SetScript", "OnLeave", function()
        field.umbraOver = nil
        restyle(field)
    end)
    Try(box, "SetScript", "OnEditFocusGained", function()
        field.umbraFocus = true
        restyle(field)
    end)
    Try(box, "SetScript", "OnEditFocusLost", function()
        field.umbraFocus = nil
        restyle(field)
    end)

    Try(box, "SetScript", "OnEscapePressed", function(self)
        Try(self, "ClearFocus")
    end)
    Try(box, "SetScript", "OnEnterPressed", function(self)
        Try(self, "ClearFocus")
        if type(onCommit) == "function" then
            pcall(onCommit, Try(self, "GetText") or "")
        end
    end)

    --- Set the text without firing onCommit.
    -- @param said any
    frame.umbraSet = function(self, said)
        Try(self.box, "SetText", said or "")
    end

    restyle(field)
    return frame
end
