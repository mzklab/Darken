local helpers = require("helpers")

-- The icons' borders: a line where there is none, and the trimming of the native edge.
--
-- Why the subsystem exists at all. The darkening can multiply the colour of
-- what the game drew and nothing more: a button's native edge is drawn inside
-- its own picture, darkens along with it, and a row of buttons turns into dark
-- patches with no borders. The author sent in a screenshot of the bottom row
-- asking what was going on with the shadows there.

T.suite("the icons: the trimming of the edge is reversible")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Modules/Icons.lua", ns)

local Icons = ns.Icons
T.ok(Icons ~= nil, "the subsystem was read")

--- A stand-in icon texture with coordinates of its own.
local function newIcon(left, right, top, bottom)
    local icon = { coords = { left or 0, right or 1, top or 0, bottom or 1 } }
    function icon:GetTexCoord()
        return self.coords[1], self.coords[2], self.coords[3], self.coords[4]
    end
    function icon:SetTexCoord(l, r, t, b)
        self.coords = { l, r, t, b }
    end
    return icon
end

do
    local icon = newIcon(0, 1, 0, 1)

    T.eq(Icons.Crop(icon, true), true, "the edge was trimmed")
    T.ok(icon.coords[1] > 0, "the left edge moved inwards")
    T.ok(icon.coords[2] < 1, "and so did the right")
    T.ok(math.abs(icon.coords[1] - (1 - icon.coords[2])) < 1e-9,
        "the trimming is the same on both sides")

    -- The restoration sets exactly what stood there rather than what we consider usual.
    T.eq(Icons.Crop(icon, false), true, "the edge was restored")
    T.eq(icon.coords[1], 0, "the left edge is in place")
    T.eq(icon.coords[2], 1, "and so is the right")

    -- An icon whose coordinates were not the default ones: its own are
    -- restored rather than a zero and a one.
    local trimmed = newIcon(0.2, 0.8, 0.2, 0.8)
    Icons.Crop(trimmed, true)
    Icons.Crop(trimmed, false)
    T.eq(trimmed.coords[1], 0.2, "somebody else's trimming was restored as its own")
    T.eq(trimmed.coords[2], 0.8, "by both edges")

    -- A second restoration in a row touches nothing: there is nothing remembered any more.
    T.eq(Icons.Crop(trimmed, false), false, "there is nothing left to restore")

    -- A non-texture brings nothing down.
    T.eq(Icons.Crop(nil, true), false, "there is no empty icon")
    T.eq(Icons.Crop({}, true), false, "nor an object with no coordinates")
end

T.suite("the icons: the icon is asked of the button")

-- A field rather than a frame's name: a field is part of a button's build,
-- and it is asked of the button itself. The same device as the contents in the darkening subsystem.
do
    local icon = newIcon()
    T.eq(Icons.IconOf({ icon = icon }), icon, "the icon field")
    T.eq(Icons.IconOf({ Icon = icon }), icon, "the Icon field")
    T.eq(Icons.IconOf({ IconTexture = icon }), icon, "the IconTexture field")
    T.eq(Icons.IconOf({ icon = {} }), nil,
        "a field with no coordinates does not count as an icon")
    T.eq(Icons.IconOf(nil), nil, "there is no empty button")
end

T.suite("the icons: a fresh install touches nothing")

do
    T.eq(Icons.defaults.border, false, "there are no borders")
    T.eq(Icons.defaults.crop, false, "the edge is untouched")

    -- The section is there, and both its settings are read without the database.
    local args = Icons.options and Icons.options.args or {}
    T.eq(type(args.border), "table", "the border setting is in place")
    T.eq(type(args.crop), "table", "and so is the trimming one")
    T.eq(args.border.get(), false, "with no database the border is off")
    T.eq(args.crop.get(), false, "and so is the trimming")

    -- A write with no database brings nothing down.
    args.border.set(nil, true)
    args.crop.set(nil, true)
    T.ok(true, "the write with no database passed silently")
end

T.suite("the icons: the backing beneath a bar")

-- The backing is laid beneath the bar and wider than it: it gives the row an
-- edge where the game draws none. Our texture on somebody else's frame lives
-- in the side memory — showing it again is cheaper than creating it afresh.
do
    local made = {}

    local bar = {}
    function bar:CreateTexture()
        local texture = { shown = true, points = {} }
        function texture:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function texture:SetColorTexture(...) self.color = { ... } end
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        made[#made + 1] = texture
        return texture
    end

    T.eq(Icons.Shade(bar, true), true, "the backing was laid down")
    T.eq(#made, 1, "and exactly one texture was created")
    T.eq(#made[1].points, 2, "it is stretched by two corners")
    T.ok(made[1].color ~= nil, "and painted")

    -- The texture is not created a second time: it is already there.
    T.eq(Icons.Shade(bar, true), true, "the backing is in place")
    T.eq(#made, 1, "no second texture appeared")

    -- Switching it off hides it rather than deleting it.
    T.eq(Icons.Shade(bar, false), false, "the backing was removed")
    T.eq(made[1].shown, false, "the texture is hidden")
    T.eq(#made, 1, "and not lost")

    -- Switching it on shows that very one.
    Icons.Shade(bar, true)
    T.eq(made[1].shown, true, "the same texture is shown")

    -- There is no bar at all — an ordinary answer rather than a failure.
    T.eq(Icons.Shade(nil, true), false, "with no bar there is nowhere to lay it")
    T.eq(Icons.Shade({}, true), false, "nor onto a frame with no textures")
end

T.suite("the icons: round buttons on the minimap")

-- Only other addons' buttons are touched, and on them exactly one thing: a
-- mask on the icon's picture. A mask is removed by the same call with an empty
-- path, so switching it off restores the button's look with no reload.
do
    local function newButton(name)
        local icon = { masks = {} }
        function icon:SetTexCoord() end
        function icon:SetMask(path) self.masks[#self.masks + 1] = path end

        local button = { icon = icon }
        function button:GetName() return name end
        return button, icon
    end

    local mine, icon = newButton("SomeAddonMinimapButton")

    T.eq(Icons.Round(mine, true), true, "the button was rounded")
    T.ok(#icon.masks == 1 and icon.masks[1] ~= "", "the mask was placed")

    T.eq(Icons.Round(mine, false), false, "and taken back off")
    T.eq(icon.masks[#icon.masks], "", "by an empty path, that is, cleanly")

    -- Somebody else's mask is not removed: the switch is not entitled to break
    -- a button we never touched. An unconditional SetMask("") used to stand
    -- here — and an addon that puts its own mask on its own button lost it to
    -- a single switch of ours.
    local stranger, strangerIcon = newButton("OtherAddonMinimapButton")
    strangerIcon:SetMask("Interface\\SomeAddon\\TheirOwnMask")
    T.eq(Icons.Round(stranger, false), false, "there is nothing to round")
    T.eq(strangerIcon.masks[#strangerIcon.masks],
        "Interface\\SomeAddon\\TheirOwnMask",
        "somebody else's mask stayed in place")

    -- A button with no mask in this client is an ordinary answer rather than a failure.
    local old = { icon = { SetTexCoord = function() end } }
    T.eq(Icons.Round(old, true), false, "with no SetMask there is nothing to round with")

    -- And so is a button with no icon.
    T.eq(Icons.Round({}, true), false, "with no icon either")
end
