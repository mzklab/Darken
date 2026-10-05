local ADDON, ns = ...

-- Page scrolling and its bar.
--
-- === Why the bar is ours, not the game's ===
--
-- The game's scroll bar is two arrow buttons and a slider in a stone frame.
-- None of it fits a flat dark window, and repainting foreign widgets is the
-- approach the old settings window was built on and this one replaced.
--
-- === What this file does not decide ===
--
-- The height of the contents. The caller declares it through umbraExtend;
-- this file only shows a window onto them and positions the bar. Computing
-- the height here would require knowing what the page contains.

local Widgets = ns.Widgets
local Skin = ns.Skin
local M = Skin.Metrics

local Try = Widgets.Try

-- Scroll bar width. Deliberately narrow: the bar reports position, it is not
-- a control. Scrolling is done with the wheel.
local BAR = 4

--- How far the contents can be scrolled.
--
-- Pure: two numbers in, one out, so it is testable outside the client. A
-- mistake here does not raise an error; it silently prevents reaching the
-- bottom of the page, which is only visible on a long page.
--
-- @param content any height of the contents
-- @param window any height of the visible window
-- @return number scrollable distance, never negative
function Widgets.Reach(content, window)
    local tall = tonumber(content) or 0
    local seen = tonumber(window) or 0
    local left = tall - seen
    if left ~= left or left < 0 then return 0 end
    return left
end

--- Clamp a scroll offset into range.
-- @param got any
-- @param reach any
-- @return number
function Widgets.Clamp(got, reach)
    local at = tonumber(got) or 0
    local top = tonumber(reach) or 0
    if at ~= at or at < 0 then return 0 end
    if at > top then return top end
    return at
end

--- Scroll position as a fraction from 0 to 1.
-- @param at any
-- @param reach any
-- @return number
function Widgets.Share(at, reach)
    local top = tonumber(reach) or 0
    if top <= 0 then return 0 end
    return Widgets.Clamp(at, top) / top
end

--- Build a scrollable area.
--
-- Returns the scroll frame with a `content` field: the frame page rows are
-- parented to. The caller sets the content height through umbraExtend.
--
-- @param parent table
-- @return table|nil
function Widgets.Scroll(parent)
    local frame = Widgets.Frame("ScrollFrame", parent)
    if frame == nil then return nil end

    local content = Widgets.Frame("Frame", frame)
    if content == nil then return frame end

    Try(frame, "SetScrollChild", content)
    Try(content, "SetHeight", 1)
    frame.content = content

    --- Match the content width to the scroll frame width.
    --
    -- A scroll child must be given an explicit width; the engine does not
    -- derive one. Without this the content stays 1 pixel wide and every row
    -- anchored to both its edges collapses to zero width: checkbox labels,
    -- paragraphs and dropdowns are not drawn at all. Headings survive
    -- because they are anchored by one edge and size to their text, which is
    -- why the symptom reads as "headings present, settings missing".
    frame.umbraFit = function(self)
        local wide = tonumber(Try(self, "GetWidth")) or 0
        if wide > 0 then Try(self.content, "SetWidth", wide) end
    end

    -- The scroll frame width follows from its anchors, which the engine
    -- resolves after this function returns. Refit on every size change
    -- rather than once at build time.
    Try(frame, "SetScript", "OnSizeChanged", function(self)
        self:umbraFit()
    end)
    frame:umbraFit()

    -- The bar overlays the content at the right edge. Placing it outside
    -- would cost the page BAR pixels of width permanently, including when
    -- there is nothing to scroll.
    local bar = Widgets.Frame("Frame", frame)
    if bar then
        Try(bar, "SetWidth", BAR)
        Try(bar, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        Try(bar, "SetPoint", "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        Try(bar, "Hide")

        local thumb = Try(bar, "CreateTexture", nil, "OVERLAY")
        if type(thumb) == "table" then
            Try(thumb, "SetColorTexture", Skin.Get("lilacDeep"))
            Try(thumb, "SetPoint", "LEFT", bar, "LEFT", 0, 0)
            Try(thumb, "SetPoint", "RIGHT", bar, "RIGHT", 0, 0)
        end
        bar.thumb = thumb
    end
    frame.bar = bar

    --- Declare the height of the contents.
    -- @param tall any
    frame.umbraExtend = function(self, tall)
        local high = tonumber(tall) or 0
        self:umbraFit()
        Try(self.content, "SetHeight", high)

        local window = tonumber(Try(self, "GetHeight")) or 0
        local reach = Widgets.Reach(high, window)
        self.umbraReach = reach

        if self.bar then
            if reach > 0 then Try(self.bar, "Show")
            else Try(self.bar, "Hide") end

            if self.bar.thumb and window > 0 and high > 0 then
                local share = window / high
                if share > 1 then share = 1 end
                Try(self.bar.thumb, "SetHeight", window * share)
            end
        end

        self:umbraTo(Try(self, "GetVerticalScroll") or 0)
    end

    --- Scroll to an offset, clamped into range.
    -- @param at any
    frame.umbraTo = function(self, at)
        local reach = tonumber(self.umbraReach) or 0
        local put = Widgets.Clamp(at, reach)
        Try(self, "SetVerticalScroll", put)

        local bar, thumb = self.bar, self.bar and self.bar.thumb
        if bar and thumb then
            local window = tonumber(Try(self, "GetHeight")) or 0
            local tall = tonumber(Try(thumb, "GetHeight")) or 0
            local room = window - tall
            if room < 0 then room = 0 end
            Try(thumb, "ClearAllPoints")
            Try(thumb, "SetPoint", "LEFT", bar, "LEFT", 0, 0)
            Try(thumb, "SetPoint", "RIGHT", bar, "RIGHT", 0, 0)
            Try(thumb, "SetPoint", "TOP", bar, "TOP", 0,
                -(room * Widgets.Share(put, reach)))
        end
    end

    Try(frame, "EnableMouseWheel", true)
    Try(frame, "SetScript", "OnMouseWheel", function(self, delta)
        local step = M.row * 3
        self:umbraTo((Try(self, "GetVerticalScroll") or 0)
            - (tonumber(delta) or 0) * step)
    end)

    return frame
end
