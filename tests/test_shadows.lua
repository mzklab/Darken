local helpers = require("helpers")

-- The shadow laid inside an element's edges.
--
-- The author asked for it by the name the skinning addons give it - a shadow
-- border - with a switch and a strength of its own, in a section of its own.
-- What is checked here is the arithmetic and the reversibility, because the
-- look itself is not checkable outside the game and the rules are.

T.suite("shadows: the strength is the darkness at the edge")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Events.lua", ns)
helpers.loadAddonFile("Modules/Shadows.lua", ns)

local Shadows = ns.Shadows
T.ok(type(Shadows) == "table", "the subsystem is in place")

T.eq(Shadows.Alpha(0), 0, "nothing at zero")
T.eq(Shadows.Alpha(100), 1, "black at a hundred")
T.eq(Shadows.Alpha(60), 0.6, "and the percentage in between")
T.eq(Shadows.Alpha(140), 1, "above the scale is the scale's end")
T.eq(Shadows.Alpha(-20), 0, "and below it the other end")
T.eq(Shadows.Alpha("rubbish"), 0, "what cannot be read is nothing")

T.eq(Shadows.defaults.inner, false,
    "a fresh install lays no shadow until the player asks")

T.suite("shadows: four edges, laid once and hidden rather than destroyed")

do
    local made = 0
    local frame = { textures = {} }
    function frame:CreateTexture()
        made = made + 1
        local texture = { shown = true, points = {}, colour = nil,
            gradient = nil }
        function texture:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function texture:SetWidth(w) self.width = w end
        function texture:SetHeight(h) self.height = h end
        function texture:SetColorTexture(r, g, b, a) self.colour = { r, g, b, a } end
        function texture:SetGradientAlpha(dir, _, _, _, a1, _, _, _, a2)
            self.gradient = { dir, a1, a2 }
        end
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        self.textures[#self.textures + 1] = texture
        return texture
    end

    T.ok(Shadows.Lay(frame, true, 0.6), "the shadow is laid")
    T.eq(made, 4, "four edges and no more: " .. made)

    for i = 1, #frame.textures do
        local texture = frame.textures[i]
        T.eq(#texture.points, 2, "each edge is pinned by two corners")
        T.ok(texture.gradient ~= nil, "and fades rather than standing flat")
        local dir, a1, a2 = texture.gradient[1], texture.gradient[2],
            texture.gradient[3]
        T.ok(dir == "VERTICAL" or dir == "HORIZONTAL", "in one direction")
        T.ok((a1 == 0) ~= (a2 == 0), "dark at one end and clear at the other")
    end

    -- Laying it again costs nothing new: the textures are kept, because this
    -- API gives no way to destroy one.
    Shadows.Lay(frame, true, 0.6)
    T.eq(made, 4, "a second application makes no more textures")

    -- And switching it off hides them, which is what makes the setting
    -- reversible without a reload.
    Shadows.Lay(frame, false, 0.6)
    local hidden = 0
    for i = 1, #frame.textures do
        if frame.textures[i].shown == false then hidden = hidden + 1 end
    end
    T.eq(hidden, 4, "switching it off hides every edge")

    Shadows.Lay(frame, true, 0.6)
    local shown = 0
    for i = 1, #frame.textures do
        if frame.textures[i].shown then shown = shown + 1 end
    end
    T.eq(shown, 4, "and switching it on shows the same four again")

    -- A strength of nothing is the same as off.
    Shadows.Lay(frame, true, 0)
    T.eq(frame.textures[1].shown, false, "no strength means no shadow")

    -- Nothing is made on a frame that cannot hold a texture, and nothing
    -- raises.
    T.eq(Shadows.Lay({}, true, 0.6), false, "a frame with no textures is left")
    T.eq(Shadows.Lay(nil, true, 0.6), false, "and so is nothing at all")
end

T.suite("shadows: the furniture of the screen and nothing else")

-- The author drew the line himself: a shadow belongs on what is always
-- there, in the same place, and not on what appears and vanishes. A
-- flyout's buttons exist only while the flyout is open, so they are asked
-- for apart - the outline and the shade still reach them, because those are
-- a look an icon carries wherever it is.
do
    local globals = {
        RackBar_main_1 = { fixed = true },
        RackFlyoutButton1 = { transient = true },
    }
    local function loaded(addon) return addon == "Rack" end

    local all = select(1, ns.Compat.ResolveAddonButtons(globals, loaded))
    local fixed = select(1, ns.Compat.ResolveAddonButtons(globals, loaded, true))

    local function holds(list, name)
        for i = 1, #list do if list[i] == name then return true end end
        return false
    end

    T.ok(holds(all, "RackBar_main_1"), "a bar's button is a button")
    T.ok(holds(all, "RackFlyoutButton1"), "and so is a flyout's, when all are asked for")

    T.ok(holds(fixed, "RackBar_main_1"), "the fixed list holds the bar's button")
    T.ok(not holds(fixed, "RackFlyoutButton1"),
        "and leaves out the one that comes and goes")
end
