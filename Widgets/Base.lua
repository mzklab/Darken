local ADDON, ns = ...

-- Shared construction for every widget in the settings window.
--
-- === Why own widgets instead of skinning foreign ones ===
--
-- The previous window was library widgets repainted from outside: hooked
-- methods, replaced anchors, wrappers around foreign handlers. Each of those
-- is an assumption about library internals that the library never promised,
-- and such assumptions break silently.
--
-- The case that ended the approach: all 38 explanatory paragraphs stopped
-- rendering. Eight rounds of probing ruled out text, font, alpha, colour,
-- draw layer and parent; the actual cause was that the font string had no
-- resolved screen rect at all. A widget we construct cannot hold an opinion
-- we did not give it.
--
-- === Colours come from the palette only ===
--
-- Two background shades written as numbers in two files drift apart
-- silently: nobody notices they differ until the two appear side by side.
-- This file contains no colour literals, only role names from Core/Skin.lua.
--
-- === What this file does not contain ===
--
-- Decisions. Widgets cannot be constructed outside the client, so nothing
-- here is testable without the game. Every decision — which widget a setting
-- gets, in what order, what is disabled — lives in the schema and in the
-- pure functions of Options/Window.lua. This file only draws.

local Widgets = {}
ns.Widgets = Widgets

local Skin = ns.Skin
local M = Skin.Metrics

-- The window's metric scale comes from the core; no numbers are invented
-- here. Inset, gap, row height and field height were chosen once and are
-- checked in tests/test_skin.lua (the scale is a multiple of four).
Widgets.PAD = M.inset
Widgets.GAP = M.gap
Widgets.RAIL = M.rail
Widgets.ROW = M.row
Widgets.FIELD = M.field

-- Width of the control in a settings row: dropdown, edit box and slider row.
--
-- Declared here rather than in whichever file first needed it. Widget files
-- load in TOC order, and Controls.lua reads this before Dropdown.lua would
-- have declared it. The two agreed only because the fallback happened to
-- equal the real value — a coincidence, not an invariant.
--
-- A number rather than a fraction of the window: controls of differing
-- widths on one page read as unrelated settings, equal ones as a column.
Widgets.CONTROL = 230

--- Call a method on an object, tolerating its absence.
--
-- Outside the client most methods do not exist, and inside it some exist
-- only on certain client flavours. A missing method is a negative answer,
-- not a failure: the widget draws with whatever this client provides.
--
-- Five return values are passed through: GetFont returns three and GetPoint
-- five, and a helper returning only the first drops the rest silently.
--
-- @param object table|nil
-- @param name string
-- @return any
function Widgets.Try(object, name, ...)
    if type(object) ~= "table" then return nil end
    local method = object[name]
    if type(method) ~= "function" then return nil end

    local ok, a, b, c, d, e = pcall(method, object, ...)
    if not ok then return nil end
    return a, b, c, d, e
end

local Try = Widgets.Try

--- Create a frame.
-- @param kind string|nil frame type, default "Frame"
-- @param parent table|nil
-- @param template string|nil
-- @return table|nil nil when there is no engine
function Widgets.Frame(kind, parent, template)
    if type(_G.CreateFrame) ~= "function" then return nil end
    local ok, frame = pcall(_G.CreateFrame, kind or "Frame", nil,
        parent or _G.UIParent, template)
    if not ok or type(frame) ~= "table" then return nil end
    return frame
end

--- Give a frame a palette background and border.
--
-- Drawing is delegated to Skin.Backdrop, which already renders our border as
-- four lines instead of the engine backdrop and is used by the durability
-- block, the info panel and the nameplates. A second implementation would
-- diverge from the first at the next palette change.
--
-- @param frame table|nil
-- @param bg any background role name
-- @param edge any border role name; nil for no border
function Widgets.Dress(frame, bg, edge)
    if type(frame) ~= "table" then return end
    if type(Skin.Backdrop) ~= "function" then return end

    Skin.Backdrop(frame, bg, edge)

    -- Re-show what Bare hid. Bare hides the textures rather than destroying
    -- them, so without this the frame would stay transparent forever.
    if frame.umbraBg ~= nil then Try(frame.umbraBg, "Show") end
    if edge ~= nil and type(frame.umbraBorder) == "table" then
        for _, side in pairs(frame.umbraBorder) do Try(side, "Show") end
    end
end

--- Remove a frame's background entirely.
--
-- Used where the parent supplies the background: a page row in the sidebar
-- has none of its own — the column is painted as a whole — and at rest the
-- row must be transparent rather than repeat the column's colour. A repeated
-- colour shows a seam where rows meet.
--
-- @param frame table|nil
function Widgets.Bare(frame)
    if type(frame) ~= "table" then return end

    -- The background is a TEXTURE created by Skin.Backdrop, not an engine
    -- backdrop. SetBackdrop(nil) does not touch it, which is why sidebar
    -- hover highlighting never cleared: it was applied and had nothing to
    -- remove it. Hide the textures instead.
    if frame.umbraBg ~= nil then Try(frame.umbraBg, "Hide") end
    if type(frame.umbraBorder) == "table" then
        for _, side in pairs(frame.umbraBorder) do Try(side, "Hide") end
    end
end

-- Font strings the window has flattened.
--
-- Flattening once is not enough: Modules/Fonts.lua pins the font of every
-- string it owns, and pinning restores the outline and shadow carried by the
-- font object — on profile change, on a font setting change, on entering the
-- world. Window.Repaint re-flattens this set.
--
-- The table is weak-keyed: a font string discarded with its frame must not
-- be held in memory merely because we flattened it.
local FLAT = setmetatable({}, { __mode = "k" })

--- Strip outline and shadow from one font string.
--
-- The outline, not the shadow, was the visible problem: Modules/Fonts.lua
-- applies the player's chosen outline across the whole interface, the
-- settings window included, and a thin outline thickens small text on every
-- side. Outline and shadow both exist for text drawn over the game world,
-- where anything can be behind a letter. In the window the background is
-- flat and dark, so neither separates the letter from it.
--
-- @param text table|nil
local function flat(text)
    local path, size = Try(text, "GetFont")
    if type(path) == "string" and path ~= "" then
        Try(text, "SetFont", path, tonumber(size) or 12, "")

        -- SetFont clears word wrap, which collapses a paragraph into one
        -- ellipsised line. Only strings that asked for wrapping get it back,
        -- recorded by Widgets.Hint as umbraWrap.
        if text.umbraWrap then Try(text, "SetWordWrap", true) end
    end

    Try(text, "SetShadowOffset", 0, 0)
    Try(text, "SetShadowColor", 0, 0, 0, 0)
end

--- Flatten a font string and remember it for later repaints.
-- @param text table|nil
function Widgets.Flatten(text)
    if type(text) ~= "table" then return end

    FLAT[text] = true
    flat(text)
end

--- Re-flatten every font string the window owns.
--
-- Called from Window.Repaint. The pass is cheap — the window holds dozens of
-- strings — and there is no event telling us a font was re-pinned.
function Widgets.Unshadow()
    for text in pairs(FLAT) do flat(text) end
end

--- Create a font string.
--
-- The draw layer is set explicitly to OVERLAY. The library placed its font
-- strings on BACKGROUND, which is harmless for a bare widget because nothing
-- is drawn beneath it. Our page background and block backgrounds occupy that
-- layer, so a paragraph ended up underneath them.
--
-- Flattening happens AFTER Skin.Text: Skin.Text assigns the font, and the
-- font object carries the outline and shadow with it, so flattening earlier
-- would be undone immediately.
--
-- @param parent table owning frame
-- @param role any colour role name; nil means "text"
-- @param template string|nil game font object
-- @return table|nil
function Widgets.Text(parent, role, template)
    local text = Try(parent, "CreateFontString", nil, "OVERLAY",
        template or "GameFontHighlight")
    if type(text) ~= "table" then return nil end

    Try(text, "SetDrawLayer", "OVERLAY")
    Try(text, "SetJustifyH", "LEFT")
    Try(text, "SetJustifyV", "MIDDLE")

    if type(Skin.Text) == "function" then
        Skin.Text(text, role or "text")
    end

    Widgets.Flatten(text)
    return text
end

--- A setting label: one line, left aligned to the rail.
-- @param parent table
-- @param role any
-- @return table|nil
function Widgets.Label(parent, role)
    local text = Widgets.Text(parent, role)
    if text == nil then return nil end

    Try(text, "SetPoint", "TOPLEFT", parent, "TOPLEFT", M.rail, 0)
    Try(text, "SetPoint", "TOPRIGHT", parent, "TOPRIGHT", -M.rail, 0)
    return text
end

--- An explanatory paragraph: several lines across the full width.
--
-- Two horizontal anchors plus word wrap, rather than one anchor and an
-- assigned width. A width written as a number goes stale the first time the
-- window is resized; two anchors follow it.
--
-- The paragraph reports its own height through Widgets.Measure. The layout
-- needs that number, otherwise the next row overlaps its tail.
--
-- @param parent table
-- @return table|nil
function Widgets.Hint(parent)
    local text = Widgets.Text(parent, "textDim", "GameFontHighlightSmall")
    if text == nil then return nil end

    Try(text, "SetPoint", "TOPLEFT", parent, "TOPLEFT", M.rail, 0)
    Try(text, "SetPoint", "TOPRIGHT", parent, "TOPRIGHT", -M.rail, 0)
    Try(text, "SetJustifyV", "TOP")
    Try(text, "SetWordWrap", true)
    text.umbraWrap = true
    Try(text, "SetSpacing", 2)
    return text
end

--- Height the text occupies once laid out.
-- @param text table|nil
-- @return number
function Widgets.Measure(text)
    local high = Try(text, "GetStringHeight")
    return tonumber(high) or 0
end

--- A section heading: label on the left, rule to the right edge.
--
-- The rule divides the page, the way the seam under the window header does;
-- it does not enclose anything. A border around half a page would be a
-- second line where one is enough.
--
-- The accent role is named "lilac" deliberately: Skin.SetAccent recolours
-- that role rather than introducing a new one. The name dates from the first
-- palette and changes only with the palette.
--
-- @param parent table
-- @param role any label role name; nil means the accent
-- @return table|nil heading frame with `text` and `rule` fields
function Widgets.Header(parent, role)
    local frame = Widgets.Frame("Frame", parent)
    if frame == nil then return nil end

    Try(frame, "SetHeight", M.header)

    local text = Widgets.Text(frame, role or "lilac", "GameFontNormalSmall")
    if text then
        Try(text, "SetPoint", "LEFT", frame, "LEFT", M.rail, 0)
    end

    local rule = Try(frame, "CreateTexture", nil, "ARTWORK")
    if type(rule) == "table" then
        Try(rule, "SetColorTexture", Skin.Get("line"))
        Try(rule, "SetHeight", M.hair)
        Try(rule, "SetPoint", "RIGHT", frame, "RIGHT", -M.rail, 0)
        if text then
            Try(rule, "SetPoint", "LEFT", text, "RIGHT", M.gap, 0)
        else
            Try(rule, "SetPoint", "LEFT", frame, "LEFT", M.rail, 0)
        end
    end

    frame.text = text
    frame.rule = rule
    return frame
end

--- A block: a border around a group of settings.
-- @param parent table
-- @return table|nil
function Widgets.Panel(parent)
    local frame = Widgets.Frame("Frame", parent)
    if frame == nil then return nil end
    Widgets.Dress(frame, "panel", "line")
    return frame
end
