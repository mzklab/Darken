local helpers = require("helpers")

-- The settings window's own widgets: the trim.
--
-- A widget cannot be checked whole without a client: no frame is created
-- outside the game, and everything drawn is checked by eye. What can be
-- checked, though, is the thing the window is being rewritten for — that a
--
-- widget has NO opinion and does not fall over. Two properties, and both
--
-- derived from the former window's defects:
--   1. A label lies on the top layer. The library put its own on BACKGROUND,
--      and for a bare widget that is a matter of indifference — nothing is
--      drawn beneath it. Beneath ours something is: the page's background and
--      a block's background lie on that same layer, and all thirty-eight
--      explanatory paragraphs ended up UNDER them. The author saw empty bands while six numbers in a row said the text was fine.
--
--   2. With no engine nothing falls over. The widgets are created when the
--      window is opened, and the window is opened on a client where half the methods are missing too.

T.suite("the widgets: the trim")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Casefold.lua", ns)
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Skin/Draw.lua", ns)
helpers.loadAddonFile("Widgets/Base.lua", ns)
helpers.loadAddonFile("Widgets/Controls.lua", ns)
helpers.loadAddonFile("Widgets/Dropdown.lua", ns)
helpers.loadAddonFile("Widgets/EditBox.lua", ns)
helpers.loadAddonFile("Widgets/Scroll.lua", ns)

local W = ns.Widgets

T.eq(type(W), "table", "the trim was read")

--============================================================================
-- The scale is taken from the core
--============================================================================

-- The widgets have no numbers of their own: the inset, the gap and a row's
-- height were chosen once in Core/Skin.lua and are checked there. A second set
-- of the same numbers would diverge from the first silently — on one edit out of ten.
do
    T.eq(W.PAD, ns.Skin.Metrics.inset, "the inset comes from the core's scale")
    T.eq(W.GAP, ns.Skin.Metrics.gap, "the gap from the same place")
    T.eq(W.RAIL, ns.Skin.Metrics.rail, "the rail from the same place")
    T.eq(W.ROW, ns.Skin.Metrics.row, "a row's height from the same place")
end

--============================================================================
-- The protected call
--============================================================================

T.suite("the widgets: the protected call returns every value")

do
    local object = {
        GetFont = function() return "path", 12, "OUTLINE" end,
        Angry = function() error("no") end,
    }

    -- Three values rather than one. GetFont returns the path, the size and the
    -- outline, and a helper that returns only the first silently loses the
    -- size: on exactly that the growth of the lines was not applied in the
    -- away screen, and it was a check that caught it rather than the client.
    local path, size, flags = W.Try(object, "GetFont")
    T.eq(path, "path", "the path came back")
    T.eq(size, 12, "and the size")
    T.eq(flags, "OUTLINE", "and the outline")

    T.eq(W.Try(object, "Angry"), nil, "a call that fell over gives an empty answer")
    T.eq(W.Try(object, "NoSuchThing"), nil, "a missing method gives an empty answer")
    T.eq(W.Try(nil, "GetFont"), nil, "an empty object gives an empty answer")
    T.eq(W.Try("a string", "GetFont"), nil, "a non-object gives an empty answer")
end

--============================================================================
-- With no engine
--============================================================================

T.suite("the widgets: with no engine nothing falls over")

do
    local saved = _G.CreateFrame
    _G.CreateFrame = nil

    T.eq(W.Frame("Frame"), nil, "no frame is created")
    T.eq(W.Header(nil), nil, "no header is created")
    T.eq(W.Panel(nil), nil, "no block is created")
    T.eq(W.Text(nil), nil, "no label is created")
    T.eq(W.Label(nil), nil, "no caption is created")
    T.eq(W.Hint(nil), nil, "no paragraph is created")
    T.eq(W.Measure(nil), 0, "measuring nothing gives zero")

    W.Dress(nil, "panel", "line")
    T.ok(true, "trimming an empty frame passes silently")

    _G.CreateFrame = saved
end

--============================================================================
-- The labels on the fake engine
--============================================================================

T.suite("the widgets: a label lies on the top layer")

do
    local noop = function() end

    local function fake(kind)
        local object = { kind = kind, points = {}, children = {} }
        object.SetDrawLayer = function(self, layer) self.layer = layer end
        object.GetDrawLayer = function(self) return self.layer or "BACKGROUND" end
        object.SetPoint = function(self, point, _, _, x, y)
            self.points[#self.points + 1] = { point, x, y }
        end
        object.GetNumPoints = function(self) return #self.points end
        object.SetText = function(self, value) self.text = value end
        object.GetStringHeight = function() return 42 end
        object.SetTextColor = function(self, r, g, b) self.color = { r, g, b } end
        object.SetVertexColor = function(self, r, g, b) self.color = { r, g, b } end
        object.CreateFontString = function(self)
            local made = fake("FontString")
            self.children[#self.children + 1] = made
            return made
        end
        object.CreateTexture = function(self)
            local made = fake("Texture")
            self.children[#self.children + 1] = made
            return made
        end
        object.SetColorTexture = function(self, r, g, b, a)
            self.fill = { r, g, b, a }
        end
        -- Only methods answer an empty call: in the engine they begin with a
        -- capital. A field that does not exist is obliged to stay empty.
        setmetatable(object, { __index = function(_, key)
            if type(key) == "string" and key:match("^%u") then return noop end
        end })
        return object
    end

    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }
    _G.UIParent = fake("Frame")
    _G.CreateFrame = function(kind) return fake(kind) end

    local page = fake("Frame")

    -- The main property: a label is NOT at the bottom. The former window lost
    -- all thirty-eight paragraphs on that.
    local text = W.Text(page)
    T.eq(text.layer, "OVERLAY", "the label was raised off the bottom")

    local hint = W.Hint(page)
    T.eq(hint.layer, "OVERLAY", "and so was the explanatory paragraph")

    -- A paragraph is held by two anchors rather than by one plus an assigned
    -- width: a width as a number goes stale at the window's first resize,
    -- while anchors follow it by themselves.
    T.eq(hint:GetNumPoints(), 2, "the paragraph is anchored on two sides")
    T.eq(W.Measure(hint), 42, "and says how much room it took")

    local label = W.Label(page)
    T.eq(label:GetNumPoints(), 2, "the caption is anchored on two sides too")

    -- A header: the label on the left, the rule to the right edge.
    local header = W.Header(page)
    T.ok(header ~= nil, "the header was created")
    T.ok(header.text ~= nil, "the header has a label")
    T.ok(header.rule ~= nil, "and a rule")
    T.eq(header.text.layer, "OVERLAY", "the header's label is on the top layer")

    local panel = W.Panel(page)
    T.ok(panel ~= nil, "the block was created")
    T.ok(panel.umbraBg ~= nil, "and got a background from the core's styling")

    _G.CreateFrame, _G.UIParent = saved.CreateFrame, saved.UIParent
end

--============================================================================
-- A control's state
--============================================================================

T.suite("the widgets: the seniority of the states")

-- A pure rule and therefore checkable. A widget asks it at every movement of
-- the mouse, and it decides one thing: which of four words to name.
--
-- The order here is not a matter of taste. The prohibition is strongest of
-- all: a disabled button has no right to brighten under the mouse, or it
-- promises a press that will not happen. A press is stronger than a hover: one
-- presses without moving the cursor away, and if the hover overrides the press the click looks like nothing.
do
    T.eq(W.State(false, false, false), "normal", "nothing is happening")
    T.eq(W.State(false, false, true), "hover", "the cursor is hovering")
    T.eq(W.State(false, true, true), "pushed", "a press is stronger than a hover")
    T.eq(W.State(false, true, false), "pushed",
        "a press is visible even when the cursor was moved away")
    T.eq(W.State(true, true, true), "disabled",
        "the prohibition is stronger than both a press and a hover")
    T.eq(W.State(true, false, false), "disabled", "and in itself")

    -- Rubbish on the input is an ordinary answer rather than an error: the
    -- marks arrive from the engine as a frame's fields, and a nil happens there.
    T.eq(W.State(nil, nil, nil), "normal", "empty marks mean rest")
end

T.suite("the widgets: the controls with no engine")

do
    local saved = _G.CreateFrame
    _G.CreateFrame = nil

    T.eq(W.Button(nil, "Yes"), nil, "no button is created")
    T.eq(W.CheckBox(nil, "Yes"), nil, "no checkbox is created")
    T.eq(W.Slider(nil, "Strength", 0, 100, 1), nil, "no slider is created")

    W.Disable(nil, true)
    W.Wear(nil, "normal")
    W.Respond(nil)
    T.ok(true, "disabling, painting and responding on nothing pass silently")

    _G.CreateFrame = saved
end

--============================================================================
-- The scrolling: the widgets' only arithmetic
--============================================================================

T.suite("the widgets: how much scrolling is available")

-- A mistake here does not fail. It simply does not let one reach the page's
-- bottom, and that can be noticed only on a long page and only if looked for.
do
    T.eq(W.Reach(1000, 400), 600, "contents taller than the viewport give the difference")
    T.eq(W.Reach(300, 400), 0, "contents shorter than the viewport leave nothing to scroll")
    T.eq(W.Reach(400, 400), 0, "level with it leaves nothing either")

    -- The numbers arrive from the engine, and anything at all happens there.
    T.eq(W.Reach(nil, 400), 0, "an empty height gives zero")
    T.eq(W.Reach(1000, nil), 1000, "an empty viewport gives the whole height")
    T.eq(W.Reach(0 / 0, 400), 0, "a NaN gives zero rather than endless scrolling")
end

T.suite("the widgets: the scrolling is clamped to the bounds")

do
    T.eq(W.Clamp(100, 600), 100, "inside the bounds it stays as it is")
    T.eq(W.Clamp(-50, 600), 0, "one cannot go above the top")
    T.eq(W.Clamp(900, 600), 600, "nor below the bottom")
    T.eq(W.Clamp(100, 0), 0, "nothing to scroll gives zero")
    T.eq(W.Clamp(0 / 0, 600), 0, "a NaN gives zero")
end

T.suite("the widgets: the share scrolled")

-- The bar travels by it. A division by zero here is the most likely failure: a
-- page shorter than the viewport happens for half the sections.
do
    T.eq(W.Share(0, 600), 0, "at the beginning it is zero")
    T.eq(W.Share(600, 600), 1, "at the end it is one")
    T.eq(W.Share(300, 600), 0.5, "in the middle it is a half")
    T.eq(W.Share(100, 0), 0, "nothing to scroll gives zero rather than a division by zero")
    T.eq(W.Share(900, 600), 1, "beyond the bound it is one all the same")
end

T.suite("the widgets: a select and an edit box with no engine")

do
    local saved = _G.CreateFrame
    _G.CreateFrame = nil

    T.eq(W.Dropdown(nil, "Colour"), nil, "no select is created")
    T.eq(W.EditBox(nil, "Name"), nil, "no edit box is created")
    T.eq(W.Scroll(nil), nil, "no scroll frame is created")

    W.CloseList()
    T.ok(true, "closing a select that does not exist passes silently")

    _G.CreateFrame = saved
end
