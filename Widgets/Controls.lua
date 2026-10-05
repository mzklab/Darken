local ADDON, ns = ...

-- Interactive controls: button, checkbox, slider.
--
-- === Where state colours come from ===
--
-- Not from here. Skin.ButtonColors decides the colour of a control at rest,
-- hovered, pressed and disabled. Those colours predate this file and were
-- chosen for the skinned library widgets, deliberately: the move to our own
-- widgets should change nothing the player can see except that paragraphs
-- stopped disappearing.
--
-- Field state precedence is also the core's (Skin.FieldState), a pure
-- function with its own tests: disabled beats focused, focused beats
-- hovered. A second copy of that order here would diverge at the first fix.
--
-- === What this file does not decide ===
--
-- Anything. A widget does not know which setting it shows or what a click
-- means; it is handed a callback. The decisions live in the schema.

local Widgets = ns.Widgets
local Skin = ns.Skin
local M = Skin.Metrics

-- Widths of the slider row's parts: the number box and each stepper button.
local NUMBER = 40
local STEPPER = 16

-- Shown in the number box when the value is at its minimum and the row
-- declared `zero`: an em dash meaning "nothing of its own, inherited".
-- A zero font size for a category means "follow the global tab", not a font
-- of zero height, and a bare 0 does not say that.
--
-- A mark rather than a word: the box is NUMBER pixels wide, and a word is
-- shown tail-first — "Same as Global" rendered as "bal".
local MARK = string.char(226, 128, 148)

-- The slider row is wider than Widgets.CONTROL and grows leftwards.
--
-- A dropdown holds one label and fits any width. The slider row holds four
-- parts in the same space — two steppers, the track and the number box — and
-- at CONTROL width the track was under 80 pixels for 100 steps, which the
-- mouse cannot resolve.
--
-- Right edges still line up: all three control kinds are anchored to the
-- right of the row, so the extra width is taken from the label, which is
-- shorter than its space almost everywhere.
--
-- TRACK is the remainder rather than a literal: a literal drifts from the
-- sum of the parts silently and the row overlaps itself.
local WHOLE = Widgets.CONTROL + 80
local TRACK = WHOLE - NUMBER - STEPPER * 2 - Skin.Metrics.rail * 3

-- Exposed for tests/test_window.lua, which checks the row is no narrower
-- than a dropdown and that the track keeps half the row.
Widgets.SLIDER = { whole = WHOLE, track = TRACK, stepper = STEPPER,
    number = NUMBER }

local Try = Widgets.Try

-- Side of the checkbox square. Smaller than the row height on purpose: a
-- full-height square reads as a button rather than a checkbox.
local CHECK = 13

-- Slider track height, and the thumb's dimensions.
local TROUGH = 5
local THUMB_WIDE, THUMB_HIGH = 4, 12

--- Paint background and border for a state name.
--
-- One place for all three controls: button, checkbox and track differ in
-- shape, not in palette, and three copies of this call would drift apart by
-- one colour.
--
-- @param frame table
-- @param state string state name
-- @param kind string|nil palette kind: "normal", "select", "primary"
local function wear(frame, state, kind)
    if type(frame) ~= "table" then return end
    local fill, edge = Skin.ButtonColors(state, kind)
    Widgets.Dress(frame, fill, edge)
end
Widgets.Wear = wear

--- Resolve a state name from mouse and disabled flags.
--
-- Pure, therefore testable. Called on every mouse movement; it decides one
-- thing: which of the four state names applies.
--
-- @param disabled any
-- @param down any mouse button held
-- @param over any pointer inside
-- @return string
function Widgets.State(disabled, down, over)
    if disabled then return "disabled" end
    if down then return "pushed" end
    if over then return "hover" end
    return "normal"
end

--- Attach mouse response to a control.
--
-- One set of scripts for every control. The response answers "did that
-- register"; without it a control reads as broken.
--
-- OnMouseUp arrives even when the pointer left the control while held: the
-- engine delivers it to whoever received the press. Without handling it the
-- control would stay in the pressed state permanently.
--
-- @param frame table
-- @param kind string|nil palette kind
-- @param paint function|nil painter; defaults to wear
local function respond(frame, kind, paint)
    if type(frame) ~= "table" then return end
    paint = paint or wear

    local function show(self)
        paint(self, Widgets.State(self.umbraOff, self.umbraDown,
            self.umbraOver), kind)
    end
    frame.umbraShow = show

    Try(frame, "SetScript", "OnEnter", function(self)
        self.umbraOver = true
        show(self)
    end)
    Try(frame, "SetScript", "OnLeave", function(self)
        self.umbraOver = nil
        show(self)
    end)
    Try(frame, "SetScript", "OnMouseDown", function(self)
        self.umbraDown = true
        show(self)
    end)
    Try(frame, "SetScript", "OnMouseUp", function(self)
        self.umbraDown = nil
        show(self)
    end)

    show(frame)
end
Widgets.Respond = respond

--- Disable or enable a control.
-- @param frame table|nil
-- @param off any
function Widgets.Disable(frame, off)
    if type(frame) ~= "table" then return end
    frame.umbraOff = off and true or nil

    if off then Try(frame, "Disable") else Try(frame, "Enable") end
    if type(frame.umbraShow) == "function" then frame.umbraShow(frame) end

    if frame.label then
        Skin.Text(frame.label, off and "textFaint" or "text")
    end
end

--============================================================================
-- Button
--============================================================================

--- A button with a centred label.
--
-- Width follows the label unless one is given: "Restore the Game's Fonts"
-- and "Yes" at one width means either a clipped word or empty space.
--
-- @param parent table
-- @param text any label
-- @param onClick function|nil
-- @param width number|nil
-- @param kind string|nil palette kind
-- @return table|nil
function Widgets.Button(parent, text, onClick, width, kind)
    local button = Widgets.Frame("Button", parent)
    if button == nil then return nil end

    Try(button, "SetHeight", M.row)

    local label = Widgets.Text(button, "text")
    if label then
        Try(label, "SetPoint", "CENTER", button, "CENTER", 0, 0)
        Try(label, "SetJustifyH", "CENTER")
        Try(label, "SetText", text)
    end
    button.label = label

    if tonumber(width) then
        Try(button, "SetWidth", tonumber(width))
    else
        local own = tonumber(Try(label, "GetStringWidth")) or 0
        Try(button, "SetWidth", (own > 0 and own or 60) + M.inset * 2)
    end

    respond(button, kind)

    Try(button, "SetScript", "OnClick", function(self)
        if self.umbraOff then return end
        if type(onClick) == "function" then pcall(onClick, self) end
    end)

    return button
end

--============================================================================
-- Checkbox
--============================================================================

--- A checkbox with its label on the right.
--
-- The square sits on the same rail as dropdown labels and slider tracks.
-- Off that rail it breaks the column and the page reads as a staircase; this
-- was a defect of the previous window and was fixed there too.
--
-- @param parent table
-- @param text any label
-- @param onChange function|nil called with the new value
-- @return table|nil
function Widgets.CheckBox(parent, text, onChange)
    local button = Widgets.Frame("Button", parent)
    if button == nil then return nil end

    Try(button, "SetHeight", M.row)

    local box = Widgets.Frame("Frame", button)
    if box then
        Try(box, "SetSize", CHECK, CHECK)
        Try(box, "SetPoint", "LEFT", button, "LEFT", M.rail, 0)
    end
    button.box = box

    -- The tick is a fill inside the square, not a game texture: the game's
    -- texture would bring the client's gold border into a dark window.
    local mark = Try(box, "CreateTexture", nil, "OVERLAY")
    if type(mark) == "table" then
        Try(mark, "SetPoint", "TOPLEFT", box, "TOPLEFT", 3, -3)
        Try(mark, "SetPoint", "BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
        Try(mark, "SetColorTexture", Skin.Get("lilac"))
        Try(mark, "Hide")
    end
    button.mark = mark

    local label = Widgets.Text(button, "text")
    if label then
        Try(label, "SetPoint", "LEFT", box or button, "RIGHT", M.gap, 0)
        Try(label, "SetPoint", "RIGHT", button, "RIGHT", -M.rail, 0)
        Try(label, "SetText", text)
    end
    button.label = label

    -- The square is painted, not the whole button: highlighting the entire
    -- row would claim the full page width is clickable.
    respond(button, "select", function(self, state, kind)
        wear(self.box, state, kind)

        -- The square always keeps a border, whatever state is returned.
        -- Without one an unchecked box is a dark square on a dark
        -- background: invisible, and the row reads as a label with no
        -- setting attached.
        if type(Skin.Backdrop) == "function" then
            local fill = Skin.ButtonColors(state, kind)
            Skin.Backdrop(self.box, fill or "ink", "line")
        end
    end)

    --- Set the tick without firing onChange.
    -- @param on any
    button.umbraSet = function(self, on)
        self.umbraValue = on and true or false
        if self.mark then
            if self.umbraValue then Try(self.mark, "Show")
            else Try(self.mark, "Hide") end
        end
    end

    Try(button, "SetScript", "OnClick", function(self)
        if self.umbraOff then return end
        self:umbraSet(not self.umbraValue)
        if type(onChange) == "function" then
            pcall(onChange, self.umbraValue)
        end
    end)

    button:umbraSet(false)
    return button
end

--============================================================================
-- Slider
--============================================================================

--- A slider row: label, steppers, track and a number box.
--
-- The track and fill are drawn here; the thumb must be the texture assigned
-- through SetThumbTexture, because the engine moves that one. A texture of
-- ours in its place would stay still.
--
-- @param parent table
-- @param text any label
-- @param low number
-- @param high number
-- @param step number
-- @param onChange function|nil called with the new value
-- @return table|nil
function Widgets.Slider(parent, text, low, high, step, onChange)
    local frame = Widgets.Frame("Frame", parent)
    if frame == nil then return nil end

    -- One row: label left, slider and number right, matching the dropdown
    -- and the edit box. A label above the slider costs twice the height and
    -- gains nothing.
    Try(frame, "SetHeight", M.row)

    local label = Widgets.Text(frame, "text")
    if label then
        Try(label, "SetPoint", "LEFT", frame, "LEFT", M.rail, 0)
        Try(label, "SetText", text)
    end
    frame.label = label

    local slider = Widgets.Frame("Slider", frame)
    if slider == nil then return frame end

    Try(slider, "SetOrientation", "HORIZONTAL")
    Try(slider, "SetHeight", M.row)
    Try(slider, "SetWidth", TRACK)

    -- Bound the label on the right at the "less" stepper. Without it a long
    -- label runs under the slider and is read over the track.
    if label then
        Try(label, "SetPoint", "RIGHT", slider, "LEFT",
            -(STEPPER + M.rail + M.gap), 0)
        Try(label, "SetWordWrap", false)
    end
    Try(slider, "SetMinMaxValues", tonumber(low) or 0, tonumber(high) or 100)
    Try(slider, "SetValueStep", tonumber(step) or 1)
    Try(slider, "SetObeyStepOnDrag", true)
    frame.slider = slider

    local trough = Try(slider, "CreateTexture", nil, "BACKGROUND")
    if type(trough) == "table" then
        Try(trough, "SetHeight", TROUGH)
        Try(trough, "SetPoint", "LEFT", slider, "LEFT", 0, 0)
        Try(trough, "SetPoint", "RIGHT", slider, "RIGHT", 0, 0)
        Try(trough, "SetColorTexture", Skin.Get("line"))
    end
    slider.trough = trough

    -- Create the thumb if the engine supplied none.
    --
    -- A Slider created without a game template has no thumb texture:
    -- GetThumbTexture returns nil. With no thumb the engine has nothing to
    -- move and the fill has nothing to anchor to, since it ends at the
    -- thumb's centre. The symptom was an empty track with no trace of the
    -- value, whatever was written into the slider.
    local thumb = Try(slider, "GetThumbTexture")
    if type(thumb) ~= "table" then
        local own = Try(slider, "CreateTexture", nil, "ARTWORK")
        if type(own) == "table" then
            Try(own, "SetColorTexture", Skin.Get("text"))
            Try(own, "SetSize", THUMB_WIDE, THUMB_HIGH)
            Try(slider, "SetThumbTexture", own)
            thumb = Try(slider, "GetThumbTexture") or own
        end
    end
    if type(thumb) == "table" then
        Try(thumb, "SetColorTexture", Skin.Get("text"))
        Try(thumb, "SetSize", THUMB_WIDE, THUMB_HIGH)
    end
    slider.thumb = thumb

    -- The fill runs from the left of the track to the thumb's centre.
    -- Anchoring to the thumb removes the need to track the value: the engine
    -- moves the thumb and the fill's right edge follows.
    local fill = Try(slider, "CreateTexture", nil, "BORDER")
    if type(fill) == "table" and type(trough) == "table" then
        Try(fill, "SetPoint", "TOPLEFT", trough, "TOPLEFT", 0, 0)
        Try(fill, "SetPoint", "BOTTOMLEFT", trough, "BOTTOMLEFT", 0, 0)
        if type(thumb) == "table" then
            Try(fill, "SetPoint", "RIGHT", thumb, "CENTER", 0, 0)
        end
        Try(fill, "SetColorTexture", Skin.Get("lilac"))
    end
    slider.fill = fill

    --- Snap a value to the bounds and the step.
    --
    -- Typed input arrives in any form: letters, fractions, numbers out of
    -- range. The slider cannot produce those but the number box can, and a
    -- value stored outside the bounds is one the slider can no longer
    -- reach.
    -- @param got any
    -- @return number
    local function fit(got)
        local want = tonumber(got)
        local lo = tonumber(low) or 0
        local hi = tonumber(high) or 100

        if want == nil or want ~= want then want = lo end
        if want < lo then want = lo end
        if want > hi then want = hi end

        local by = tonumber(step)
        if by ~= nil and by > 0 then
            want = lo + math.floor((want - lo) / by + 0.5) * by
            if want > hi then want = hi end
        end
        return want
    end
    --- Move by one step.
    -- @param sign number -1 or 1
    local function nudge(sign)
        local by = tonumber(step)
        if by == nil or by <= 0 then by = 1 end
        local now = tonumber(Try(slider, "GetValue")) or 0
        Try(slider, "SetValue", fit(now + sign * by))
    end

    -- Steppers flank the track because the mouse cannot resolve a single
    -- step: a track of a few hundred pixels across a hundred steps gives
    -- only a pixel or two per step.
    local less = Widgets.Button(frame, "\226\128\147", function() nudge(-1) end,
        STEPPER)
    if less then
        Try(less, "ClearAllPoints")
        Try(less, "SetPoint", "RIGHT", slider, "LEFT", -M.rail, 0)
        Try(less, "SetHeight", M.row - M.edge * 2)
    end
    frame.less = less

    local more = Widgets.Button(frame, "+", function() nudge(1) end,
        STEPPER)
    if more then
        Try(more, "ClearAllPoints")
        Try(more, "SetHeight", M.row - M.edge * 2)
    end
    frame.more = more

    -- An edit box rather than a label: the number is both shown and typed.
    -- A slider suits searching by eye and not knowing the answer; typing 64
    -- is faster than aiming at it.
    --
    -- The row is assembled RIGHT TO LEFT: box at the edge, "more" to its
    -- left, then the track. Anchoring the track to the edge independently
    -- made the parts sum wider than the row, and "more" overlapped the box,
    -- rendering as "+75" in one piece.
    local box = Widgets.Frame("EditBox", frame)
    if box then
        Try(box, "SetSize", NUMBER, M.row - M.edge * 2)
        Try(box, "SetPoint", "RIGHT", frame, "RIGHT", -M.rail, 0)
        if more then
            Try(more, "SetPoint", "RIGHT", box, "LEFT", -M.rail, 0)
        end
        Try(slider, "SetPoint", "RIGHT", more or box, "LEFT", -M.rail, 0)
        Try(box, "SetAutoFocus", false)

        -- Not numeric-only: the box may hold MARK instead of a number
        -- where the minimum means "inherited". Typed input is still read as
        -- a number, and anything unparseable snaps to the minimum.
        Try(box, "SetNumeric", false)
        Try(box, "SetJustifyH", "CENTER")
        Try(box, "SetFontObject", "GameFontHighlightSmall")
        Try(box, "SetTextInsets", M.rail, M.rail, 0, 0)
        Widgets.Dress(box, "ink", "line")

        Try(box, "SetScript", "OnEnterPressed", function(self)
            Try(slider, "SetValue", fit(Try(self, "GetText")))
            Try(self, "ClearFocus")
        end)
        -- Losing focus commits: someone who types a number and clicks away
        -- believes they have set it.
        Try(box, "SetScript", "OnEditFocusLost", function(self)
            Try(slider, "SetValue", fit(Try(self, "GetText")))
        end)
        Try(box, "SetScript", "OnEscapePressed", function(self)
            Try(self, "SetText",
                tostring(tonumber(Try(slider, "GetValue")) or 0))
            Try(self, "ClearFocus")
        end)
    end
    frame.box = box
    frame.value = box

    --- Set the value without firing onChange.
    -- @param got number
    --- Render a value for the number box.
    --
    -- A minimum sometimes means "inherited" rather than a quantity: a
    -- category font size of zero means "follow the global tab", not a font
    -- of zero height. A bare 0 does not convey that.
    --
    -- @param got any
    -- @return string
    local function worded(got)
        local value = fit(got)
        if frame.umbraZero and value == (tonumber(low) or 0) then
            -- A mark, not a word. The box is NUMBER pixels wide and
            -- "Same as Global" does not fit: the box shows the tail, which
            -- rendered as "bal". The explanation belongs in the hint.
            return MARK
        end
        return tostring(value)
    end
    frame.umbraWorded = worded

    frame.umbraSet = function(self, got)
        self.umbraQuiet = true
        -- Re-apply the bounds before writing. The engine clamps to the
        -- current range, and a slider whose range was never set treats it as
        -- 0..1, so any value of ours becomes an extreme.
        Try(self.slider, "SetMinMaxValues", tonumber(low) or 0,
            tonumber(high) or 100)
        Try(self.slider, "SetValue", fit(got))
        self.umbraQuiet = nil
        if self.box then
            Try(self.box, "SetText", worded(got))
            -- Cursor to the start: the box shows the part of the string
            -- the cursor is in, and left at the end it shows the tail.
            Try(self.box, "SetCursorPosition", 0)
        end
    end

    Try(slider, "SetScript", "OnValueChanged", function(self, got)
        local shown = fit(got)
        if frame.box then
            Try(frame.box, "SetText", worded(got))
            Try(frame.box, "SetCursorPosition", 0)
        end
        if frame.umbraQuiet then return end
        if type(onChange) == "function" then pcall(onChange, shown) end
    end)

    return frame
end
