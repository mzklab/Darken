local ADDON, ns = ...

local Skin = ns.Skin

-- Border sides. One enumeration for the whole addon: four names spread
-- across files would sooner or later diverge in their order too.
local SIDES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
Skin.SIDES = SIDES

--- Remove the textures Blizzard or Ace drew themselves.
-- Without this our fill lands on top of somebody else's border and the result
-- is a mess. The calls go through Skin.Try: clearing a texture is a foreign
-- API whose signature differs between clients, and one region must not abort
-- the styling of the whole frame. SetAtlas(nil) follows SetTexture(nil):
-- in modern builds some textures are set from an atlas, and they have to be
-- cleared the same way they were assigned.
function Skin.StripTextures(frame)
    if not frame then return end

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture" then
                Skin.Try(region, "SetTexture", nil)
                Skin.Try(region, "SetAtlas", nil)
            end
        end
    end

    if frame.SetBackdrop then
        Skin.Try(frame, "SetBackdrop", nil)
    end
end

-- The four button state textures. The names match the method names:
-- GetNormalTexture, SetNormalTexture and so on.
local BUTTON_STATES = { "Normal", "Pushed", "Disabled", "Highlight" }

--- Suppress a button's native state textures.
--
-- Why Skin.StripTextures is not enough: state textures belong to the button
-- rather than to the frame's layers, and the engine decides itself which one
-- to show on press, hover and disable. In modern builds they come from an
-- atlas (the red "UI-Panel-Button-Up"), so one pass over the regions misses
-- them.
--
-- Why alpha rather than clearing alone: a texture can only be cleared by
-- Set*Texture(nil), and on some clients that raises — and did raise. It was
-- this very line that aborted the styling of the close button, the keybinding
-- button and the whole dropdown, leaving the first two red and the third
-- invisible. Alpha is assigned to the texture object directly, survives state
-- changes (the engine shows and hides the textures but never touches their
-- alpha) and works even where clearing did not.
--
-- @param button table the button frame
function Skin.ClearButtonTextures(button)
    if not button then return end

    for i = 1, #BUTTON_STATES do
        local state = BUTTON_STATES[i]

        local getter = button["Get" .. state .. "Texture"]
        if type(getter) == "function" then
            local okGet, texture = pcall(getter, button)
            if okGet and texture then
                Skin.Try(texture, "SetAlpha", 0)
                Skin.Try(texture, "SetTexture", nil)
                Skin.Try(texture, "SetAtlas", nil)
            end
        end

        Skin.Try(button, "Set" .. state .. "Texture", nil)
    end
end

--- A fill and a one-pixel border.
--
-- The default layer is the lowest one: an ordinary frame only needs to sit
-- under everything drawn on it. A button is different. Its native state
-- textures live above the background and are suppressed by alpha, and any
-- pass over foreign frames can restore that alpha; at that moment a fill
-- lying beneath them stops meaning anything and the button is natively red
-- again. So the caller may name the layer the fill goes on and sit above the
-- foreign textures rather than below them. Restored alpha then changes
-- nothing: our colour is on top regardless.
--
-- The layer is assigned on every call rather than only at creation: widgets
-- come out of the pool with a fill created on the default layer at some
-- point, and that one has to be raised too.
--
-- @param frame table the frame
-- @param bgName string palette name of the fill colour
-- @param borderName string|nil palette name of the border colour; nil for none
-- @param layer string|nil draw layer; the lowest one by default
-- @param sublevel number|nil sublevel; the border goes one above it
function Skin.Backdrop(frame, bgName, borderName, layer, sublevel)
    if not frame or not frame.CreateTexture then return end

    local bgLayer = layer or "BACKGROUND"
    local bgLevel = sublevel or 0

    if not frame.umbraBg then
        frame.umbraBg = frame:CreateTexture(nil, bgLayer)
        frame.umbraBg:SetAllPoints(frame)
    end
    Skin.Try(frame.umbraBg, "SetDrawLayer", bgLayer, bgLevel)
    frame.umbraBg:SetColorTexture(Skin.Get(bgName))

    if not borderName then return end

    if not frame.umbraBorder then
        frame.umbraBorder = {}
        for _, side in ipairs(SIDES) do
            frame.umbraBorder[side] = frame:CreateTexture(nil,
                layer and bgLayer or "BORDER")
        end
    end
    for _, side in ipairs(SIDES) do
        Skin.Try(frame.umbraBorder[side], "SetDrawLayer",
            layer and bgLayer or "BORDER", layer and (bgLevel + 1) or 0)
    end

    local b = frame.umbraBorder
    local r, g, bl, a = Skin.Get(borderName)

    b.TOP:ClearAllPoints()
    b.TOP:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    b.TOP:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    b.TOP:SetHeight(1)

    b.BOTTOM:ClearAllPoints()
    b.BOTTOM:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    b.BOTTOM:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    b.BOTTOM:SetHeight(1)

    b.LEFT:ClearAllPoints()
    b.LEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    b.LEFT:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    b.LEFT:SetWidth(1)

    b.RIGHT:ClearAllPoints()
    b.RIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    b.RIGHT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    b.RIGHT:SetWidth(1)

    for _, side in ipairs(SIDES) do
        b[side]:SetColorTexture(r, g, bl, a)
    end
end

--- Pin a font string's font.
--
-- The settings window does not change with the font the player chose for the
-- game: it is a tool, not a subject of configuration. The exception is held
-- by a pin (Modules/Fonts.lua), and that pin had to be reapplied every time
-- a font object was assigned to a label: when a widget came out of the pool,
-- when a paragraph was drawn, when the cursor entered a button or a tree row.
-- There turned out to be more such places than were found one by one.
--
-- So the pin is applied where styling already touches every label of the
-- window on every repaint — next to the colour. Colour and font are assigned
-- in one motion, and missing one without missing the other is no longer
-- possible.
--
-- Whether a frame is "our window" is decided not here but behind the door
-- (Fonts.PinText): the same call colours the labels of the bags window and
-- the item database, and those are what the addon draws instead of the game's
-- interface, so they do obey the font settings.
--
-- The fonts subsystem may be absent from a build, and the styling layer may
-- not count on it: its absence is an ordinary "nothing to do with" answer
-- rather than an error.
--
-- @param fontString table|nil the font string
-- @param path string|nil an explicit face; nil keeps the object's own
-- @param size number|nil an explicit size
-- @param flags any explicit outline flags
-- @return boolean whether it was pinned
function Skin.HoldFont(fontString, path, size, flags)
    local fonts = ns.Fonts
    if type(fonts) ~= "table" then
        -- Without the subsystem a plain assignment is left: styling that
        -- carries its own face must apply it in any case.
        if path and fontString and fontString.SetFont then
            return pcall(fontString.SetFont, fontString, path, size, flags)
                and true or false
        end
        return false
    end

    if path then
        if type(fonts.KeepFont) ~= "function" then return false end
        local ok, held = pcall(fonts.KeepFont, fontString, path, size, flags)
        return (ok and held) and true or false
    end

    if type(fonts.PinText) ~= "function" then return false end
    local ok, pinned = pcall(fonts.PinText, fontString)
    return (ok and pinned) and true or false
end

--- Text colour from the palette.
function Skin.Text(fontString, colorName)
    if not fontString or not fontString.SetTextColor then return end
    Skin.HoldFont(fontString)
    fontString:SetTextColor(Skin.Get(colorName))
end

--- Recolour a border already built by Skin.Backdrop.
-- @param frame table a frame carrying the umbraBorder field
-- @param colorName string palette name of the colour
function Skin.BorderColor(frame, colorName)
    local border = frame and frame.umbraBorder
    if not border then return end

    local r, g, b, a = Skin.Get(colorName)
    for i = 1, #SIDES do
        border[SIDES[i]]:SetColorTexture(r, g, b, a)
    end
end

--- A one-pixel border around an arbitrary region.
-- Skin.Backdrop can only border a whole frame, while a border is also needed
-- around a single region: a checkbox square, a colour swatch, a dropdown. The
-- texture set is remembered, so a repeat call reuses and recolours it — no
-- separate colour function is needed. The top and bottom strips overhang by a
-- pixel on each side, or the corners would be left with holes.
--
-- === Where the set is remembered ===
--
-- In one of two ways, and choosing between them is choosing whose frame it
-- is.
--
--   A field name (string) — on a frame we created ourselves: our widgets in
--     the settings window, a mover handle. An extra field on our own frame
--     harms nothing.
--   Side memory (ns.Skin.Memory) — on a game frame: a bag slot, an action
--     button. Writing a field into a game object's table marks the object
--     itself, the mark spreads further, and the player sees it in somebody
--     else's file.
--
-- The two are told apart by the argument's type, and that is not brevity for
-- its own sake: there is no third way, and the choice between two must be
-- visible in the call itself.
--
-- @param frame table the frame that owns the textures
-- @param key string|table field name, or the side memory table
-- @param target table the region to border
-- @param colorName string palette name of the colour
function Skin.Outline(frame, key, target, colorName)
    if not frame or not target then return end

    local aside = type(key) == "table" and key or nil

    local set = aside and aside[frame] or (not aside and frame[key]) or nil
    if not set then
        set = {}
        for i = 1, #SIDES do
            set[SIDES[i]] = frame:CreateTexture(nil, "OVERLAY")
        end
        if aside then aside[frame] = set else frame[key] = set end
    end

    set.TOP:ClearAllPoints()
    set.TOP:SetPoint("BOTTOMLEFT", target, "TOPLEFT", -1, 0)
    set.TOP:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", 1, 0)
    set.TOP:SetHeight(1)

    set.BOTTOM:ClearAllPoints()
    set.BOTTOM:SetPoint("TOPLEFT", target, "BOTTOMLEFT", -1, 0)
    set.BOTTOM:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 1, 0)
    set.BOTTOM:SetHeight(1)

    set.LEFT:ClearAllPoints()
    set.LEFT:SetPoint("TOPRIGHT", target, "TOPLEFT", 0, 0)
    set.LEFT:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", 0, 0)
    set.LEFT:SetWidth(1)

    set.RIGHT:ClearAllPoints()
    set.RIGHT:SetPoint("TOPLEFT", target, "TOPRIGHT", 0, 0)
    set.RIGHT:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", 0, 0)
    set.RIGHT:SetWidth(1)

    local r, g, b, a = Skin.Get(colorName)
    for i = 1, #SIDES do
        set[SIDES[i]]:SetColorTexture(r, g, b, a)
    end
end

--- Strip the native textures exactly once.
-- A second StripTextures call would clear our own fill: umbraBg lives among
-- the same frame regions. The flag is shared by every styling file: a frame
-- that passed through one of them is not stripped again by the next.
function Skin.StripOnce(frame)
    if not frame or frame.umbraStripped then return end
    Skin.StripTextures(frame)
    frame.umbraStripped = true
end

--- Assert that a widget has every field the styling works with.
-- A missing field means a different AceGUI revision. Working around it with a
-- condition would be the worse decision: the result would be a half-styled
-- widget with no trace in the log, which is the most expensive kind of defect
-- to find. So this raises instead; the caller's pcall catches it and prints
-- it along with the widget type, so the settings window does not fall apart.
-- @param widget table
-- @param ... string names of the required fields
function Skin.Require(widget, ...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if widget[name] == nil then
            error(string.format(
                "missing field '%s': this AceGUI revision is not the one the styling expects",
                name), 0)
        end
    end
end

--- Call an object's method if it exists, surviving a mismatched signature.
-- Some engine methods do not exist on every supported client, and where they
-- do they take different arguments. Unguarded, such a call would abort the
-- handler halfway: part of the widget would stay unstyled, and permanently so
-- — there is no second attempt.
-- @param object table the object carrying the method
-- @param name string method name
-- @return boolean whether the method ran without error
function Skin.Try(object, name, ...)
    local method = object and object[name]
    if type(method) ~= "function" then return false end
    return (pcall(method, object, ...))
end

-- How many styling failures to remember. The list is deliberately short: it
-- exists to answer "what broke", not to accumulate for a whole session.
local FAILURE_LIMIT = 32

--- Styling failures, oldest first.
-- Read by a developer (/dump Darken... or a debugger), not by the player.
Skin.Failures = {}

--- Whether failures are printed to chat.
--
-- Off, and that is a fix rather than caution. Skin.Report sat inside the
-- re-entrancy loop of the width handler (see Skin.Wrap) and printed a line on
-- every pass: the author saw it a hundred and sixty-four times in a row.
-- Diagnostics reachable in a shipped addon end up in the player's chat sooner
-- or later — if not through this loop, then through the next one.
--
-- Turned on deliberately and from one place: ns.Skin.Debug = true.
Skin.Debug = false

--- Record a styling failure.
--
-- One place for the whole addon: both widget construction and the method
-- wrappers report a failure the same way.
--
-- There is still no silence here — a half-styled widget with no trace remains
-- the worst outcome. A trace always exists: the failure goes into
-- Skin.Failures. It reaches chat only while Skin.Debug is on, because chat is
-- the player's space, not the addon's log.
--
-- @param what string what was being styled
-- @param err any the error text
function Skin.Report(what, err)
    local text = string.format(
        "failed to style %s: %s", tostring(what), tostring(err))

    local log = Skin.Failures
    log[#log + 1] = text
    if #log > FAILURE_LIMIT then table.remove(log, 1) end

    if not Skin.Debug then return end
    if not ns.Addon or type(ns.Addon.Print) ~= "function" then return end
    ns.Addon:Print(text)
end

-- The methods the library re-enters on a frame size event.
--
-- This is the cause of the "C stack overflow" the author hit a hundred and
-- sixty-four times in a row when opening the settings.
--
-- FrameResize (AceGUI-3.0.lua, the OnSizeChanged script of every widget)
-- calls OnWidthSet and OnHeightSet on any size change — including a change of
-- the height alone. And everybody assigns a height in response to a width:
-- the library's Label (reflowing its paragraph), the library's CheckBox (the
-- height for its description) and our own styling (the rail and the gap). So
-- the width handler raises the event itself and re-enters itself; our answer
-- and the library's differ (we measure the paragraph narrowed by two rails,
-- it measures the full width), and the two kept overwriting each other's
-- height until the stack ran out. pcall is powerless here: it catches an
-- error, not a loop.
--
-- The fix is neither a depth limit nor a counter with a threshold. The fix is
-- that the re-entrant pass has nothing to do: the width did not change inside
-- the width handler — nobody assigns it there, neither the library nor we —
-- so a second pass would compute exactly the same thing. It is therefore
-- cancelled outright, original included.
--
-- The technique is not ours: it is exactly how the library guards its own
-- paragraph reflow (the `resizing` field in AceGUIWidget-Label.lua — "set the
-- flag to stop constant size updates"). Here it is simply extended to the
-- methods we wrapped.
local REENTRANT = {
    OnWidthSet  = "umbraInWidth",
    OnHeightSet = "umbraInHeight",
}

--- Wrap a widget method once.
-- The original goes into a field with the umbra prefix, which doubles as the
-- guard against wrapping twice. The constructor copies the methods into the
-- widget itself, so the replacement does not affect other widgets of the same
-- type and survives OnRelease and OnAcquire: their code does not touch the
-- methods.
-- The call's arguments are passed to the handler too: some methods (a
-- dropdown's AddItem) are interesting precisely for what was passed to them.
-- @param widget table
-- @param name string method name
-- @param after function called after the original: (widget, arguments...)
function Skin.Wrap(widget, name, after)
    local saved = "umbra" .. name
    if widget[saved] or type(widget[name]) ~= "function" then return end

    -- Name of the guard field for the sizing methods; the other methods
    -- have none, and the wrapper behaves as before.
    local busy = REENTRANT[name]

    widget[saved] = widget[name]
    widget[name] = function(self, ...)
        if busy then
            if self[busy] then return end
            self[busy] = true
        end

        -- The original is guarded not in order to swallow the error — it is
        -- re-raised below — but in order to clear the guard field. A widget
        -- stuck with the field raised would stop responding to size changes
        -- altogether.
        local okOrig, errOrig = pcall(self[saved], self, ...)

        -- The same guard as at widget creation: a styling error on one
        -- element must not abort rebuilding the window. Without it a failure
        -- inside `after` would also interrupt the library's own method call —
        -- building a whole list, for instance, at its first row.
        local ok, err
        if okOrig then
            ok, err = pcall(after, self, ...)
        end

        if busy then self[busy] = nil end

        if not okOrig then error(errOrig, 0) end
        if not ok then
            Skin.Report(string.format("widget '%s' after %s",
                tostring(self.type), name), err)
        end
    end
end

--- Assign a widget's height so that the library's layout sees it.
--
-- This is the cause of two defects that made the window look broken: the
-- preset buttons stood flush against each other, and a block's heading ended
-- up written over the first line of the paragraph below it.
--
-- The AceGUI layout does not ask a frame for its height. Both "List" and
-- "Flow" read the frame.height field and fall back to frame:GetHeight() only
-- when it is absent (lines 649 and 699 in
-- Libs/AceGUI-3.0/AceGUI-3.0.lua). That field is set by the library itself —
-- WidgetBase.SetHeight writes both the frame height and the field beside it —
-- and it is set on almost every widget in the window: a button assigns itself
-- twenty-four in OnAcquire, a heading eighteen.
--
-- Hence both complaints. The styling added its gap through a direct
-- frame:SetHeight, the field stayed at the library's value, and the layout
-- placed the next element by the old, smaller number. On a button the
-- addition simply vanished — the buttons stood flush. On a heading it was
-- worse: its label is anchored to the vertical middle of its frame, the frame
-- grew taller, and the layout still allotted it the old line — so the label
-- dropped below its allotted line, straight onto whatever stood beneath.
--
-- So the height is assigned the same way the library assigns it: through the
-- widget's method where there is one, and through the field beside the frame
-- height where there is not. We do not introduce a layout of our own: the
-- number stays what it was, it is simply visible now.
--
-- @param widget table AceGUI widget
-- @param height number the height
function Skin.Height(widget, height)
    local frame = widget and widget.frame
    if not frame or type(height) ~= "number" then return end

    -- A height already in place is not assigned twice. This is not about
    -- saving a call: assigning a size raises OnSizeChanged, through which the
    -- library re-enters the width handler (see Skin.Wrap). A "nothing
    -- changed" event is one loop for nothing, and the engine does not raise
    -- it; neither do we.
    local okNow, now = pcall(frame.GetHeight, frame)
    if okNow and type(now) == "number"
        and math.abs(now - height) < 0.5
        and type(frame.height) == "number"
        and math.abs(frame.height - height) < 0.5 then
        return
    end

    if type(widget.SetHeight) == "function" then
        pcall(widget.SetHeight, widget, height)
    elseif type(frame.SetHeight) == "function" then
        pcall(frame.SetHeight, frame, height)
    end

    -- The widget's method writes the field itself, but that cannot be
    -- relied on: library revisions differ, and the price of a miss is that
    -- same overlap. Assigning the field again costs nothing.
    frame.height = height
end

--- Pad an element out to the common gap.
--
-- Why. AceGUI places layout rows three pixels apart — the number is baked
-- into the library, and it must not be touched for the sake of one window.
-- Three pixels between a checkbox twenty-four tall and a slider forty-four
-- tall read differently: below the checkbox's label there is nothing, while
-- the slider runs a number field down to its bottom edge. Hence "the elements
-- float": the gap is equal in pixels and unequal to the eye.
--
-- What it does. Adds enough to the widget's height for the distance to the
-- next one to become Skin.Metrics.gap. Widget contents are pushed to the top
-- of their frame, so the addition goes entirely to the bottom and becomes the
-- gap.
--
-- A repeat call doubles nothing: the padded height is remembered, and a
-- height equal to the remembered one is not stretched again. So it can be
-- called from anywhere, any number of times.
--
-- The height is assigned through Skin.Height rather than a direct
-- frame:SetHeight, and that is not a detail: the AceGUI layout reads the
-- frame.height field rather than the frame's actual height (see Skin.Height).
--
-- @param widget table AceGUI widget
-- @param gap number|nil the desired gap; Skin.Metrics.gap by default
function Skin.Stretch(widget, gap)
    local frame = widget and widget.frame
    if not frame or type(frame.GetHeight) ~= "function" then return end
    if type(frame.SetHeight) ~= "function" then return end

    local ok, height = pcall(frame.GetHeight, frame)
    if not ok or type(height) ~= "number" or height <= 0 then return end

    -- A height we set ourselves is not padded again: otherwise every call
    -- would add as much once more.
    local mine = widget.umbraRhythm
    if mine and math.abs(height - mine) < 0.5 then return end

    widget.umbraRhythm = height + Skin.Slack(gap)
    Skin.Height(widget, widget.umbraRhythm)
end

--- Restore the gap after every method that assigns a height.
--
-- The library assigns the height, and does so more than once: OnAcquire on
-- every handout from the pool, SetLabel and SetDescription on every repaint of
-- the window. A one-off correction would survive only the first draw.
--
-- A method already wrapped by the styling for another reason must not be
-- passed here: Skin.Wrap installs one wrapper per method, and a second one
-- silently fails to install. In such cases call Skin.Stretch directly from
-- the handler already attached to that method.
--
-- @param widget table AceGUI widget
-- @param gap number|nil the desired gap
-- @param ... string method names
function Skin.Rhythm(widget, gap, ...)
    local function stretch(self)
        Skin.Stretch(self, gap)
    end

    for i = 1, select("#", ...) do
        Skin.Wrap(widget, (select(i, ...)), stretch)
    end

    stretch(widget)
end
