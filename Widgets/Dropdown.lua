local ADDON, ns = ...

-- A dropdown: a closed field holding the value, and an open list of rows.
--
-- === Why the arrow is drawn from bars ===
--
-- The addon carries no arrow artwork of its own, and the game's is a sunken
-- button in a frame, which has no place in a flat skin. Four bars of
-- narrowing width, taken from the palette, look the same on every client and
-- do not depend on which file the game happens to have put under that name
-- in a particular build.
--
-- === Why the list is our own frame rather than the game's menu ===
--
-- The game's menu brings its whole skin with it and closes by its own rules.
-- Our frame closes by ours: a click outside, Escape, picking a row, closing
-- the window.

local Widgets = ns.Widgets
local Skin = ns.Skin
local M = Skin.Metrics

-- Width of the field. A number rather than a share of the window: fields of
-- differing widths on one page read as differing settings, equal ones as a
-- column.
local FIELD = Widgets.CONTROL

local Try = Widgets.Try

-- The arrow: four bars, two pixels each.
local ARROW_ROWS = 4
local ARROW_STEP = 2
local ARROW_WIDE = ARROW_ROWS * ARROW_STEP
local ARROW_INSET = M.gap

-- Where the middle of the arrow sits and where the value's name stops. Both
-- are worked out from one column: they used to be written out ready-made in
-- two places, and the link between them existed only in somebody's head —
-- move one, and the name either runs into the arrow or stops short of it.
local ARROW_CENTER = -(ARROW_INSET + ARROW_WIDE / 2)
local VALUE_RIGHT = -(ARROW_INSET + ARROW_WIDE + M.rail)

-- How many rows to show before the list starts scrolling.
local LIST_ROWS = 12

--- Draw a downward arrow out of bars.
-- @param frame table the frame to draw in
-- @return table array of textures
-- The preview strip: how wide it is, and how much shorter than the row.
--
-- Wide enough that a gradient reads as a gradient rather than as a colour, and
-- narrow enough that the longest texture name still fits beside it.
local PREVIEW_WIDE = 90
local PREVIEW_INSET = 10

local function arrow(frame)
    local rows = {}
    for i = 1, ARROW_ROWS do
        local line = Try(frame, "CreateTexture", nil, "OVERLAY")
        if type(line) ~= "table" then break end

        local wide = (ARROW_ROWS - i + 1) * ARROW_STEP
        Try(line, "SetSize", wide, 1)
        Try(line, "SetPoint", "CENTER", frame, "RIGHT", ARROW_CENTER,
            (ARROW_ROWS / 2 - i + 0.5))
        Try(line, "SetColorTexture", Skin.Get("textDim"))
        rows[#rows + 1] = line
    end
    return rows
end

--- Repaint the arrow.
-- @param rows table|nil
-- @param role any
local function tintArrow(rows, role)
    if type(rows) ~= "table" then return end
    for i = 1, #rows do
        Try(rows[i], "SetColorTexture", Skin.Get(role))
    end
end

--============================================================================
-- The list
--============================================================================

--- Close the open list, if there is one.
function Widgets.CloseList()
    local open = Widgets.openList
    if type(open) ~= "table" then return end
    Try(open, "Hide")
    Widgets.openList = nil
end

--- Build the list of rows under the field.
--
-- The list lives on UIParent rather than inside the field: inside, the
-- page's scrolling would clip it exactly when the field sits at its bottom
-- edge.
--
-- @param field table the field
-- @return table|nil
local function buildList(field)
    if field.list then return field.list end

    local list = Widgets.Frame("Frame", _G.UIParent)
    if list == nil then return nil end

    Try(list, "Hide")
    Try(list, "SetFrameStrata", "FULLSCREEN_DIALOG")
    Widgets.Dress(list, "ink", "line")

    list.rows = {}
    field.list = list
    return list
end

--- Hand back the list row with this number, making it if need be.
-- @param list table
-- @param index number
-- @return table|nil
local function rowAt(list, index)
    if list.rows[index] then return list.rows[index] end

    local row = Widgets.Frame("Button", list)
    if row == nil then return nil end

    Try(row, "SetHeight", M.row)
    Try(row, "SetPoint", "LEFT", list, "LEFT", M.rail, 0)
    Try(row, "SetPoint", "RIGHT", list, "RIGHT", -M.rail, 0)
    if index == 1 then
        Try(row, "SetPoint", "TOP", list, "TOP", 0, -M.rail)
    else
        Try(row, "SetPoint", "TOP", list.rows[index - 1], "BOTTOM", 0, 0)
    end

    -- The strip that shows what a choice looks like.
    --
    -- A list of bar textures named "Darken Purple" against "Darken Pink" asks
    -- the player to choose a picture by its word, which is the one thing a
    -- word cannot do. The strip is the picture itself, drawn at the right of
    -- the row where it does not crowd the name.
    --
    -- Created with the row rather than when a preview first appears: a row is
    -- reused for whatever list opens next, and a texture made halfway through
    -- would arrive after the row had already been laid out.
    local show = Try(row, "CreateTexture", nil, "ARTWORK")
    if show then
        Try(show, "SetPoint", "RIGHT", row, "RIGHT", -M.gap, 0)
        Try(show, "SetWidth", PREVIEW_WIDE)
        Try(show, "SetHeight", M.row - PREVIEW_INSET)
        Try(show, "Hide")
    end
    row.show = show

    local text = Widgets.Text(row, "text")
    if text then
        Try(text, "SetPoint", "LEFT", row, "LEFT", M.gap, 0)
        Try(text, "SetPoint", "RIGHT", row, "RIGHT", -M.gap, 0)
    end
    row.text = text

    list.rows[index] = row
    return row
end

--============================================================================
-- The field
--============================================================================

--- A dropdown.
--
-- @param parent table
-- @param text any the label
-- @param onPick function|nil called with the key of the chosen row
-- @return table|nil
function Widgets.Dropdown(parent, text, onPick)
    local frame = Widgets.Frame("Frame", parent)
    if frame == nil then return nil end

    -- One row, not two: the label on the left, the field on the right.
    --
    -- A label ABOVE the field takes twice the height and gives nothing for
    -- it: on a page of twenty settings that is forty rows instead of twenty,
    -- and the lower ones have to be scrolled to. On the left the label also
    -- lines up with the checkbox labels, so the page reads as one column
    -- rather than a staircase.
    Try(frame, "SetHeight", M.row)

    local label = Widgets.Text(frame, "text")
    if label then
        Try(label, "SetPoint", "LEFT", frame, "LEFT", M.rail, 0)
        Try(label, "SetText", text)
    end
    frame.label = label

    local field = Widgets.Frame("Button", frame)
    if field == nil then return frame end

    Try(field, "SetSize", FIELD, M.row - M.edge * 2)
    Try(field, "SetPoint", "RIGHT", frame, "RIGHT", -M.rail, 0)
    frame.field = field

    if label then
        -- The label is bounded on the RIGHT by the edge of the field.
        -- Without that a long label runs under the field and is read on top
        -- of its value: "Font Size Adjustment" ran over the slider in
        -- exactly that way.
        Try(label, "SetPoint", "RIGHT", field, "LEFT", -M.gap, 0)
        Try(label, "SetWordWrap", false)
    end

    local value = Widgets.Text(field, "text")
    if value then
        Try(value, "SetPoint", "LEFT", field, "LEFT", M.gap, 0)
        Try(value, "SetPoint", "RIGHT", field, "RIGHT", VALUE_RIGHT, 0)
    end
    field.value = value

    field.arrow = arrow(field)

    Widgets.Respond(field, "select", function(self, state, kind)
        Widgets.Wear(self, state, kind)
        tintArrow(self.arrow, state == "disabled" and "textFaint" or "textDim")
    end)

    --- Set the rows: an array of { key, text }.
    -- @param items table
    frame.umbraItems = function(self, items)
        self.items = type(items) == "table" and items or {}
    end

    --- Show the chosen value without calling the handler.
    -- @param key any
    frame.umbraSet = function(self, key)
        self.key = key
        local said = nil
        for _, item in ipairs(self.items or {}) do
            if item.key == key then said = item.text end
        end
        if self.field and self.field.value then
            Try(self.field.value, "SetText", said or "")
        end
    end

    Try(field, "SetScript", "OnClick", function(self)
        if self.umbraOff then return end

        -- A second click on an open field closes it: the field is the same
        -- kind of toggle as everything else in the window.
        if Widgets.openList ~= nil and Widgets.openList == frame.list then
            Widgets.CloseList()
            return
        end

        Widgets.CloseList()

        local list = buildList(frame)
        if list == nil then return end

        local items = frame.items or {}
        local shown = math.min(#items, LIST_ROWS)

        for i = 1, shown do
            local row = rowAt(list, i)
            if row then
                local item = items[i]
                Try(row.text, "SetText", item.text)

                -- The name gives way to the strip, and takes the room back
                -- when there is none: a list where only some entries have a
                -- picture must not indent the others for nothing.
                if row.show then
                    local path = type(item.preview) == "string"
                        and item.preview or nil
                    if path ~= nil and Try(row.show, "SetTexture", path) then
                        Try(row.show, "Show")
                        Try(row.text, "SetPoint", "RIGHT", row, "RIGHT",
                            -(M.gap * 2 + PREVIEW_WIDE), 0)
                    else
                        Try(row.show, "Hide")
                        Try(row.text, "SetPoint", "RIGHT", row, "RIGHT",
                            -M.gap, 0)
                    end
                end

                Try(row, "Show")

                Widgets.Respond(row, "select", function(me, state)
                    -- A list row is painted with a FILL, not as a button.
                    --
                    -- A button brings a border with it, and ten rows with
                    -- borders read as ten buttons rather than one list. The
                    -- list is already outlined as a whole; a second border
                    -- inside it has no business being there.
                    local want = state
                    if item.key == frame.key then
                        -- The chosen row stays filled with no pointer on
                        -- it: otherwise, opening the list, the player cannot
                        -- see what is chosen now.
                        want = "selected"
                    elseif state ~= "hover" then
                        want = nil
                    end

                    local name, alpha = nil, nil
                    if want ~= nil and type(Skin.RowColors) == "function" then
                        name, alpha = Skin.RowColors(want)
                    end

                    if name == nil then
                        Widgets.Bare(me)
                    elseif type(Skin.Backdrop) == "function" then
                        Skin.Backdrop(me, name, nil)
                        if me.umbraBg then
                            Try(me.umbraBg, "SetColorTexture",
                                Skin.Get(name, alpha))
                            Try(me.umbraBg, "Show")
                        end
                    end
                end)

                Try(row, "SetScript", "OnClick", function()
                    Widgets.CloseList()
                    frame:umbraSet(item.key)
                    if type(onPick) == "function" then pcall(onPick, item.key) end
                end)
            end
        end

        for i = shown + 1, #list.rows do Try(list.rows[i], "Hide") end

        Try(list, "ClearAllPoints")
        Try(list, "SetPoint", "TOPLEFT", self, "BOTTOMLEFT", 0, -M.rail)
        Try(list, "SetPoint", "TOPRIGHT", self, "BOTTOMRIGHT", 0, -M.rail)
        Try(list, "SetHeight", shown * M.row + M.rail * 2)
        Try(list, "Show")

        Widgets.openList = list
    end)

    frame:umbraItems({})
    return frame
end
