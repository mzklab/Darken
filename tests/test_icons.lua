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

T.suite("the minimap is cut to the shape that was asked for")

-- The window has carried a "Square Minimap" tick for a long time and nothing
-- behind it: the key it wrote drove the rounding of other addons' buttons, and
-- the shape of the map was touched by nothing at all. The author asked for it
-- four times.
do
    local Icons = ns.Icons

    local savedMinimap = _G.Minimap
    local savedCompat = ns.Compat

    local ring = { shown = true }
    function ring:SetShown(on) self.shown = on end

    local map = { mask = nil }
    function map:SetMaskTexture(path) self.mask = path end

    _G.Minimap = map
    ns.Compat = { Resolve = function() return { "MinimapBorder" }, { ring } end }

    T.eq(Icons.Shape(true), true, "a square was asked for and set")
    T.ok(map.mask:find("WHITE8X8", 1, true) ~= nil,
        "the mask is opaque everywhere: " .. tostring(map.mask))
    T.eq(ring.shown, false, "and the round ring is taken away with it")

    T.eq(Icons.Shape(false), true, "the game's own shape was asked for")
    T.ok(map.mask:find("TempPortraitAlphaMask", 1, true) ~= nil,
        "the mask fades at the rim again: " .. tostring(map.mask))
    T.eq(ring.shown, true, "and the ring comes back")

    -- A client that cannot cut a mask says so rather than falling over: the
    -- rest of the icon pass must not be lost with it.
    _G.Minimap = { }
    T.eq(Icons.Shape(true), false, "no SetMaskTexture, no shape, no error")
    _G.Minimap = nil
    T.eq(Icons.Shape(true), false, "and no minimap at all is not an error either")

    _G.Minimap = savedMinimap
    ns.Compat = savedCompat
end

T.suite("an icon is found on the clients that keep it in a global")

-- Everything on the Icons page rests on finding the icon of a button: the
-- outline is drawn around it and the trimming is done to it. Today's templates
-- hand it over in a field (parentKey="icon"); the older XML writes
-- "$parentIcon", which makes the global and leaves the button with no field.
-- On such a client both settings did nothing at all, whatever was ticked, and
-- the pass still reported buttons touched because that count is shared with
-- work that did succeed.
do
    local Icons = ns.Icons

    local function texture()
        return { SetTexCoord = function() end, GetTexCoord = function() end }
    end

    -- A button of today: the icon is right there in a field.
    local mine = texture()
    T.eq(Icons.IconOf({ icon = mine }), mine, "a field is read first")

    -- A button of the older line: no field, a global named after it.
    local theirs = texture()
    _G.DarkenTestButton7Icon = theirs
    local old = {
        GetName = function() return "DarkenTestButton7" end,
    }
    T.eq(Icons.IconOf(old), theirs, "and a global named after the button after that")

    -- Neither: nothing, rather than something belonging to somebody else.
    T.eq(Icons.IconOf({ GetName = function() return "DarkenTestNoSuch" end }), nil,
        "no field and no global means no icon")
    T.eq(Icons.IconOf({}), nil, "a button that cannot even say its name is skipped")
    T.eq(Icons.IconOf(nil), nil, "and nothing at all is not an error")

    -- A name the client refuses to give is not an error either.
    T.eq(Icons.IconOf({ GetName = function() error("secret") end }), nil,
        "a name that cannot be read is skipped")

    _G.DarkenTestButton7Icon = nil
end

T.suite("the game's bright button frame is answered in the same breath")

-- The white edge around a filled slot is the button's own NormalTexture. The
-- dimming does write a dark colour into it - the probe says "dims: 22" on one
-- button - and it still looks white, because the game writes inside its own
-- handler and we answered a frame later through a timer. The fifty-seven
-- thousand repaints the watcher counted in one session are that fight.
do
    local Icons = ns.Icons

    local hooks = {}
    local savedHook = _G.hooksecurefunc
    _G.hooksecurefunc = function(object, method, fn)
        hooks[#hooks + 1] = { object = object, method = method, fn = fn }
    end

    local art = { alpha = 1 }
    function art:SetAlpha(a) self.alpha = a end

    local button = {
        GetNormalTexture = function() return art end,
        SetNormalTexture = function() end,
    }

    T.eq(Icons.BlankArt(button, true), true, "the frame was answered")
    T.eq(art.alpha, 0, "and taken off")
    T.eq(#hooks, 1, "the game's own setter is hooked once")
    T.eq(hooks[1].method, "SetNormalTexture", "and it is the setter")

    -- The game hands the button a new picture. The hook runs inside that call.
    art.alpha = 1
    hooks[1].fn(button)
    T.eq(art.alpha, 0, "a frame set by the game is taken off in the same call")

    T.eq(Icons.BlankArt(button, true), true, "asked twice")
    T.eq(#hooks, 1, "no second hook on the same button")

    -- A hook placed with hooksecurefunc cannot be removed, so it has to be
    -- able to do nothing instead.
    T.eq(Icons.BlankArt(button, false), true, "switched off")
    T.eq(art.alpha, 1, "the game's frame comes back")
    art.alpha = 1
    hooks[1].fn(button)
    T.eq(art.alpha, 1, "and the standing hook now leaves it alone")

    -- A button of a client that has no such texture is not an error.
    T.eq(Icons.BlankArt({}, true), false, "no normal texture, nothing done")
    T.eq(Icons.BlankArt(nil, true), false, "and no button at all is not an error")

    _G.hooksecurefunc = savedHook
end

T.suite("a spell's picture is dimmed only when asked")

-- The dimming pass spares icons on purpose - an icon is how a spell is
-- recognised, which is the same rule that spares gold, silver and copper. The
-- author wants the opposite on his action bars and names Masque, which dims
-- the whole button. Both are defensible, so it is a setting rather than a
-- change of the rule.
do
    local Icons = ns.Icons

    local icon = { r = 1, g = 1, b = 1 }
    function icon:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end

    T.eq(Icons.Tint(icon, 1), false, "one means untouched, and nothing is written")
    T.eq(icon.r, 1, "the picture keeps the colour it had")

    T.eq(Icons.Tint(icon, 0.4), true, "a shade below one is written")
    T.eq(icon.r, 0.4, "and it is the shade asked for")
    T.eq(icon.g, 0.4, "on every channel")

    T.eq(Icons.Tint(icon, 1), true, "back to one")
    T.eq(icon.r, 1, "and the picture is white again")

    -- An icon somebody else shaded is not ours to reset: only what we tinted
    -- is put back.
    local foreign = { r = 0.5 }
    function foreign:SetVertexColor(r) self.r = r end
    T.eq(Icons.Tint(foreign, 1), false, "an icon we never tinted is left alone")
    T.eq(foreign.r, 0.5, "with the shade its own addon gave it")

    T.eq(Icons.Tint(nil, 0.4), false, "no icon is not an error")
    T.eq(Icons.Tint({}, 0.4), false, "and neither is one that cannot be coloured")
end

T.suite("the icon shade is put back where the game repaints it")

-- The first cut held the shade with a hook on the icon texture, and the
-- author's own probe showed what that was worth: every texture of a button
-- read 0.27 while the icon read 1.00 1.00 1.00. We wrote, the game overwrote,
-- and the hook never answered - because the game does not reach the icon
-- through anything we can sit on. It takes it by its global name inside
-- ActionButton_UpdateUsable and writes there, so that function is the thing
-- to sit on.
do
    local Icons = ns.Icons

    local hooks = {}
    local savedHook = _G.hooksecurefunc
    _G.hooksecurefunc = function(target, fn)
        hooks[#hooks + 1] = { target = target, fn = fn }
    end

    local savedUsable = _G.ActionButton_UpdateUsable
    _G.ActionButton_UpdateUsable = function() end

    -- Icons.IconOf asks for SetTexCoord before it will call something an
    -- icon: the trimming lives on the same object, and a texture that cannot
    -- be trimmed is not one.
    local icon = { r = 1, g = 1, b = 1, SetTexCoord = function() end }
    function icon:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
    function icon:GetVertexColor() return self.r, self.g, self.b end

    local button = { icon = icon }

    T.eq(Icons.Tint(icon, 0.4), true, "the shade is written")
    T.eq(icon.r, 0.4, "and it is on the icon")
    T.eq(#hooks, 1, "the game's own repaint is hooked")
    T.eq(hooks[1].target, "ActionButton_UpdateUsable",
        "and it is that function, not the texture")

    -- The game repaints a usable spell white. Our shade goes back in the same
    -- call.
    icon.r, icon.g, icon.b = 1, 1, 1
    hooks[1].fn(button)
    T.eq(icon.r, 0.4, "white is answered: it reports nothing")

    -- Not enough mana: the game's blue is an answer, and it keeps.
    icon.r, icon.g, icon.b = 0.5, 0.5, 1
    hooks[1].fn(button)
    T.eq(icon.b, 1, "the blue of not enough mana is left alone")

    -- Cannot use it at all: the grey keeps too.
    icon.r, icon.g, icon.b = 0.4, 0.4, 0.4
    hooks[1].fn(button)
    T.eq(icon.r, 0.4, "and so does the grey of unusable")

    -- Switched off, the standing hook leaves white alone.
    T.eq(Icons.Tint(icon, 1), true, "the setting is switched off")
    icon.r, icon.g, icon.b = 1, 1, 1
    hooks[1].fn(button)
    T.eq(icon.r, 1, "and the icon stays white")

    T.eq(#hooks, 1, "the function is hooked once, not once per icon")

    _G.ActionButton_UpdateUsable = savedUsable
    _G.hooksecurefunc = savedHook
end
