local helpers = require("helpers")

-- Three behavioural discrepancies named by the analysis of the world family,
-- and what was done about them.
--
--
--   1. The size of the stack digit on a nameplate's aura was not tied to the
--      icon's size: on a small icon the digit stuck out past the edge, on a
--      large one it was lost. The compact auras had the tie, and it is that one which is taken here.
--   2. The cast bar had no setting for the label's position while the health
--      and power bars did. One and the same quantity — "where the text stands
--      on a bar" — was a setting in one place and not in the other.
--   3. Texts.Percent and Format.Ratio round differently on negatives. That is
--      not reconciled here: the number's rule is moving into the core, and the
--      choice of rounding belongs to it. What is written down is exactly what
--      each of the two does today — so that after the move it is visible what
--      changed and for whom.
--
-- The first two checks compare two subsystems against each other rather than
-- against a number we chose: where two draw one and the same thing, their rule is a single one.

helpers.installValidator()

--============================================================================
-- 1. The stack digit grows along with the icon — and identically for both
--============================================================================

do
    T.suite("the world fixes: the stack digit by the icon's size")

    local aurasNs = helpers.newNamespace()
    do
        local _, restore = helpers.installAuraFilter()
        helpers.loadModule("Features/Auras", aurasNs, { withRegistration = false })
        restore()
    end

    local platesNs = helpers.newNamespace()
    do
        local _, restore = helpers.installAuraFilter()
        helpers.loadModule("Features/NamePlates", platesNs,
            { withRegistration = false })
        restore()
    end

    local Icon  = aurasNs.Icon
    local Plate = platesNs.Plate

    T.ok(type(Icon.FontHeight) == "function",
        "the compact auras compute the digit's height by a name")
    T.ok(type(Plate.AuraFontHeight) == "function",
        "and so does the nameplates' engine")

    -- Both sides the player can choose: the compact auras have a setting of
    -- their own for an icon's size, the nameplates have their own. The bounds
    -- are taken from the subsystems themselves rather than rewritten here.
    local COMPACT = aurasNs.Layout.BOUNDS.size
    local PLATES  = platesNs.Filter.SIZE

    local from = math.min(COMPACT.min, PLATES.min)
    local to   = math.max(COMPACT.max, PLATES.max)

    local diverged = 0
    for side = from, to do
        if Icon.FontHeight(side) ~= Plate.AuraFontHeight(side) then
            diverged = diverged + 1
        end
    end
    T.eq(diverged, 0,
        "on every side of the icon both heights matched (" .. from .. ".." .. to .. ")")

    -- The smallest icon the player can choose is the very outcome the fix was
    -- made for. The digit on it is obliged to be no taller than the icon
    -- itself: anything taller sticks out past the edge and lies over a neighbour.
    T.ok(Plate.AuraFontHeight(PLATES.min) <= PLATES.min,
        "on the nameplate's smallest icon the digit is no taller than the icon")
    T.ok(Icon.FontHeight(COMPACT.min) <= COMPACT.min,
        "and on the smallest compact icon too")
    T.eq(Plate.AuraFontHeight(PLATES.min), Icon.FontHeight(PLATES.min),
        "and the height is one and the same for both")

    -- The height grows along with the icon and never decreases.
    local grew, dropped = 0, 0
    for side = from + 1, to do
        local before, after = Plate.AuraFontHeight(side - 1),
            Plate.AuraFontHeight(side)
        if after > before then grew = grew + 1 end
        if after < before then dropped = dropped + 1 end
    end
    T.eq(dropped, 0, "the digit's height does not decrease at a single step")
    T.ok(grew > 0, "and on a large icon it is greater than on a small one")

    -- Rubbish on the input is not an error but the smallest size: an icon's
    -- side arrives from the saved data and survives a change of version.
    T.eq(Plate.AuraFontHeight(nil), Plate.AuraFontHeight(0),
        "with no icon side the lower bound is taken")
end

--============================================================================
-- 1b. And it really does reach the label itself
--============================================================================
--
-- A rule computed correctly and put nowhere is exactly the defect being
-- fixed: the height was computed for the compact auras and was not computed
-- on the nameplate. So the real layout of the icons is run here on a stand-in
-- engine, and the label itself is asked.

do
    T.suite("the world fixes: the height reaches the nameplate's label")

    local platesNs = helpers.newNamespace()
    do
        local _, restore = helpers.installAuraFilter()
        helpers.loadModule("Features/NamePlates", platesNs,
            { withRegistration = false })
        restore()
    end
    local Plate = platesNs.Plate
    local SIZE  = platesNs.Filter.SIZE

    --- A stand-in font string: it remembers the path, the size and the outline.
    local function fontString()
        local text = { path = "a font", size = 0, flags = "" }
        function text:SetText() end
        function text:SetJustifyH() end
        function text:SetPoint() end
        function text:GetFont() return self.path, self.size, self.flags end
        function text:SetFont(path, size, flags)
            self.path, self.size, self.flags = path, size, flags
        end
        return text
    end

    --- A stand-in frame: the little the icons' layout needs.
    local function frameObject(kind)
        local frame = { kind = kind, width = 0, height = 0, shown = false }
        function frame:Hide() self.shown = false end
        function frame:Show() self.shown = true end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:GetWidth() return self.width end
        function frame:SetPoint() end
        function frame:ClearAllPoints() end
        function frame:SetAllPoints() end
        function frame:CreateTexture()
            return { SetAllPoints = function() end,
                SetTexCoord = function() end, SetTexture = function() end }
        end
        function frame:CreateFontString() return fontString() end
        function frame:SetMinMaxValues() end
        function frame:SetValue() end
        function frame:SetStatusBarTexture() end
        function frame:SetScript() end
        function frame:SetDrawEdge() end
        function frame:SetHideCountdownNumbers() end
        function frame:SetCooldown() end
        function frame:Clear() end
        return frame
    end

    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }
    _G.CreateFrame = function(kind) return frameObject(kind) end
    _G.UIParent = frameObject("Frame")

    local skin = {
        Backdrop = function() return true end,
        Outline  = function() return true end,
        Color    = function() return 0.7, 0.5, 0.7 end,
    }

    -- The smallest icon the player can choose.
    local frame = Plate.Build(skin)
    Plate.LayoutExtras(frame, skin, 110, 10, 2, nil, SIZE.min, 2)

    local count = frame.auras[1].count
    T.eq(count.size, Plate.AuraFontHeight(SIZE.min),
        "on the smallest icon the digit was set by the icon's rule")
    T.ok(count.size <= SIZE.min, "and is no taller than the icon itself")

    -- The category's font is set after the layout and brings a height of its
    -- own. The digit is obliged to return to the icon's height: otherwise the
    -- font setting would break it for exactly the person who touched it.
    local media = {
        ApplyFont = function(_, object)
            if type(object) == "table" and object.SetFont then
                object:SetFont("another font", 24, "OUTLINE")
            end
            return true
        end,
    }
    Plate.ApplyExtraFonts(frame, media)

    T.eq(count.path, "another font", "the typeface stayed the core's")
    T.eq(count.flags, "OUTLINE", "and so did its outline")
    T.eq(count.size, Plate.AuraFontHeight(SIZE.min),
        "while the height returned to the icon's size")

    -- The largest icon: the same layout, a different height.
    Plate.LayoutExtras(frame, skin, 110, 10, 2, nil, SIZE.max, 2)
    Plate.ApplyExtraFonts(frame, media)
    T.eq(count.size, Plate.AuraFontHeight(SIZE.max),
        "on the largest icon the digit grew along with it")
    T.ok(Plate.AuraFontHeight(SIZE.max) > Plate.AuraFontHeight(SIZE.min),
        "and it is greater than on the small one")

    _G.CreateFrame = saved.CreateFrame
    _G.UIParent = saved.UIParent
end

--============================================================================
-- 2. The label's position on the cast bar
--============================================================================

--============================================================================
-- 3. One rounding of the percentage for both
--============================================================================
--
-- Two roundings and three discrepancies between them used to be written down
-- here — "as it is today" — awaiting the core's rule. The rule landed
-- (Core/Format.lua, contract 12), both subsystems took it up, and the section
-- was rewritten onto what came of it: one function computes, and all the panel
-- has left of its own are the decisions about its own cell.
--
-- What shifted because of the move: the rounding of a negative percentage on
-- the bar. It was math.floor(v + 0.5) — a half went towards zero (-12.5 into
-- -12); it became symmetrical (-12.5 into -13). There are no negative
-- percentages on a bar, so nothing shifted on the screen; the line below records exactly that.

do
    T.suite("the world fixes: one rounding of the percentage for both")

    local savedLibStub = LibStub
    LibStub = function() return nil end

    local core = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", core)
    helpers.loadAddonFile("Core/Compat.lua", core)
    helpers.loadAddonFile("Core/Locale.lua", core)
    helpers.loadAddonFile("Core/Registry.lua", core)
    helpers.loadAddonFile("Core/Events.lua", core)
    helpers.loadAddonFile("Core/Combat.lua", core)
    helpers.loadAddonFile("Modules/Fonts.lua", core)
    helpers.loadAddonFile("Modules/UnitFrames.lua", core)
    helpers.loadAddonFile("Core/Format.lua", core)
    helpers.loadAddonFile("Modules/Texts.lua", core)
    LibStub = savedLibStub

    local panel = helpers.newNamespace()
    local _, restoreDoor = helpers.installFormat()
    helpers.loadAddonFile("Features/InfoPanel/Format.lua", panel)
    restoreDoor()

    local bars  = core.Texts.Percent
    local cells = panel.Format.Ratio

    -- On live quantities there is no difference at all, and that is the first
    -- thing to fix down: an edit of the rounding has no right to shift a single number on the screen.
    local LIVE = {
        { 0, 100 }, { 1, 100 }, { 50, 100 }, { 99, 100 }, { 100, 100 },
        { 1, 3 }, { 2, 3 }, { 1, 8 }, { 3, 8 }, { 5, 8 }, { 7, 8 },
        { 1, 200 }, { 1, 1000 }, { 12437, 25000 }, { 1, 2 },
    }
    local diverged = 0
    for i = 1, #LIVE do
        local c, m = LIVE[i][1], LIVE[i][2]
        if bars(c, m) ~= cells(c, m) then diverged = diverged + 1 end
    end
    T.eq(diverged, 0, "on non-negative quantities both compute identically")

    -- A half on non-negatives goes up for both: 1 out of 8 is 12.5 %, and both
    -- write 13.
    T.eq(bars(1, 8), 13, "the bar: half a percent goes up")
    T.eq(cells(1, 8), 13, "the panel: up as well")

    -- And here is what each does on negatives.
    --
    -- The bar computes with the core's rounding: the sign is handled
    -- explicitly, a half always goes AWAY from zero, and the property "the
    -- negative of the same quantity gives the negative of the same answer"
    -- holds. math.floor(v + 0.5) used to stand here, for which -12.5 gave -12, and the equality broke on exactly the half.
    T.eq(bars(-1, 8), -13,
        "the bar: -12.5 % rounds to -13 (the half goes away from zero)")
    T.eq(bars(1, 8), 13, "while +12.5 % rounds to 13, by the same half away from zero")
    T.eq(bars(-1, 8), -bars(1, 8),
        "that is, for the bar Percent(-x) equals minus Percent(x)")

    -- Away from the half the answer is the one it was before the move: -12.3 %
    -- is -12, -12.7 % is -13. Exactly the half shifted, and only it.
    T.eq(bars(-123, 1000), -12, "the bar: -12.3 % is -12")
    T.eq(bars(-127, 1000), -13, "the bar: -12.7 % is -13")

    -- The bar returns a negative answer as it is: the minus is visible. The
    -- core does no clamping to zero, and that behaviour of its did not change.
    T.ok(bars(-1, 8) < 0, "the bar: a negative percentage stays negative")

    -- The panel computes with that same core rounding and then clamps the
    -- result to zero — by its own decision about its own cell, written at the
    -- place of the decision. The panel does not return a negative number
    -- outwards at all: -12.5 % is computed as -13 and handed out as a zero, exactly as before the move.
    T.eq(cells(-1, 8), 0, "the panel: a negative percentage is clamped to zero")
    T.eq(cells(-127, 1000), 0, "and -12.7 % is a zero too")
    T.eq(cells(-1, 1000000), 0, "and an arbitrarily small minus is a zero too")

    local clamped = 0
    for i = 1, #LIVE do
        local c, m = LIVE[i][1], LIVE[i][2]
        if c > 0 and cells(-c, m) == 0 then clamped = clamped + 1 end
    end
    T.eq(clamped, #LIVE - 1,
        "the panel returns a zero on every negative quantity")

    -- Different answers to "there is nothing to compute from" are not a
    -- rounding but lie in those same two functions, and after the move into the
    -- core the choice will have to be made here too.
    T.eq(bars(50, 0), 0, "the bar: a zero maximum gives zero per cent")
    T.eq(cells(50, 0), nil, "the panel: a zero maximum gives a nil")
    T.eq(bars(nil, nil), 0, "the bar: a non-number counts as a zero")
    T.eq(cells(nil, 100), nil, "the panel: a non-number gives a nil")
    T.eq(cells("50", 100), nil, "the panel: a string does not count as a number")
    T.eq(bars("50", 100), 50, "the bar: a string does count as a number")
end

helpers.removeValidator()
