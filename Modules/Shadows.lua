local ADDON, ns = ...

-- The shadow laid inside an element's edges.
--
-- What it is. Four thin pictures along the four edges of a frame, each
-- fading from dark at the edge to nothing a few pixels in. Together they
-- read as a recess: the element looks sunk into the dark interface rather
-- than pasted onto it. The author asked for it by the name the skinning
-- addons give it, a shadow border, and asked for it with a switch and a
-- strength of its own.
--
-- Why four gradients rather than one picture. A picture of a soft frame is
-- cut once, at one size, and an addon that lays it on a thirty-pixel button
-- and on a seven-hundred-pixel window blurs one of the two. A gradient is
-- stretched by the engine and costs no file at all.
--
-- Whose textures these are. Ours, laid on somebody else's frame, and
-- therefore kept in side memory and never released: this API gives no way
-- to destroy a texture. Switching the setting off hides them, which is what
-- makes the setting reversible without a reload - the same rule the icon
-- outline and the bag grid follow.
--
-- What it does not do. It reads and writes not one colour of the game's, it
-- creates nothing on a frame it was not asked about, and it goes nowhere
-- near an addon the player has not named. The elements it dresses are the
-- ones the compatibility layer already names as buttons.
local Shadows = {
    name = "shadows",
}
ns.Shadows = Shadows

-- The groups whose elements are dressed. A list of groups rather than a
-- walk: an inner shadow is four textures per element, and four textures per
-- element of the whole interface is the kind of price this addon has spent
-- its evenings taking out.
local GROUPS = {
    "actionbar-main-buttons",
    "actionbar-bottomleft-buttons",
    "actionbar-bottomright-buttons",
    "actionbar-right-buttons",
    "actionbar-left-buttons",
    "actionbar-pet-buttons",
    "actionbar-stance-buttons",
    "micro-buttons",
    "bags",
}

-- The four edges: the two corners each is pinned by, and which way its
-- gradient fades. The words are the engine's own anchors rather than ours.
local EDGES = {
    { key = "top",    from = "TOPLEFT",    to = "TOPRIGHT",    horizontal = false },
    { key = "bottom", from = "BOTTOMLEFT", to = "BOTTOMRIGHT", horizontal = false },
    { key = "left",   from = "TOPLEFT",    to = "BOTTOMLEFT",  horizontal = true },
    { key = "right",  from = "TOPRIGHT",   to = "BOTTOMRIGHT", horizontal = true },
}

-- How deep the shadow reaches into an element, in pixels.
--
-- Four: deep enough to read as a recess on a thirty-pixel button, shallow
-- enough not to eat an icon. The strength works on the darkness and not on
-- the depth, because a deeper shadow on a small button is not a stronger
-- shadow - it is a smaller icon.
local DEPTH = 4

-- The shadows already laid: frame -> { edge key -> texture }.
local LAID = ns.Skin.Memory()

Shadows.defaults = {
    -- Off, like every look of our own: a fresh install changes nothing
    -- until the player asks.
    inner = false,

    -- How dark the edge is, as a percentage. Sixty reads as a recess beside
    -- the addon's own dark without turning the element into a hole.
    strength = 60,
}

--- The subsystem's settings from the profile.
-- @return table|nil
local function Settings()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    if not profile then return nil end
    return profile[Shadows.name]
end

--- The alpha a strength means.
--
-- The whole of the arithmetic: the percentage is the alpha at the edge, and
-- the far end of every gradient is transparent.
--
-- @param strength any the setting's value
-- @return number between 0 and 1
function Shadows.Alpha(strength)
    local number = tonumber(strength)
    if number == nil then return 0 end
    if number < 0 then number = 0 end
    if number > 100 then number = 100 end
    return number / 100
end

--- Give one edge's texture its colour.
--
-- Black at the edge and transparent at the far end. The engine has two
-- spellings of a gradient and the clients served here do not agree on
-- which: the later takes colour objects, the earlier eight numbers. Both
-- are tried, and a client with neither gets a flat edge - the crudest kind
-- of shadow rather than none.
--
-- @param texture table
-- @param edge table one row of EDGES
-- @param alpha number
-- @return boolean whether a gradient was laid
function Shadows.Paint(texture, edge, alpha)
    if type(texture) ~= "table" or type(edge) ~= "table" then return false end

    if type(texture.SetColorTexture) == "function" then
        pcall(texture.SetColorTexture, texture, 0, 0, 0, alpha)
    end

    local direction = edge.horizontal and "HORIZONTAL" or "VERTICAL"

    -- Which end fades depends on the edge: the engine's gradient runs left
    -- to right and bottom to top, so the top and right edges fade the other
    -- way round.
    local nearFirst = edge.key == "bottom" or edge.key == "left"
    local a1 = nearFirst and alpha or 0
    local a2 = nearFirst and 0 or alpha

    if type(texture.SetGradient) == "function"
        and type(_G.CreateColor) == "function" then
        local ok = pcall(texture.SetGradient, texture, direction,
            _G.CreateColor(0, 0, 0, a1), _G.CreateColor(0, 0, 0, a2))
        if ok then return true end
    end

    if type(texture.SetGradientAlpha) == "function" then
        local ok = pcall(texture.SetGradientAlpha, texture, direction,
            0, 0, 0, a1, 0, 0, 0, a2)
        if ok then return true end
    end

    return false
end

--- One edge of one element, made if it is not there yet.
-- @param frame table
-- @param edge table one row of EDGES
-- @param alpha number
-- @return table|nil the texture
local function edgeOf(frame, edge, alpha)
    local laid = LAID[frame]
    if laid == nil then
        laid = {}
        LAID[frame] = laid
    end

    local texture = laid[edge.key]
    if texture == nil then
        if type(frame.CreateTexture) ~= "function" then return nil end

        local ok, made = pcall(frame.CreateTexture, frame, nil, "OVERLAY")
        if not ok or type(made) ~= "table" then return nil end

        texture = made
        laid[edge.key] = texture

        pcall(texture.SetPoint, texture, edge.from, frame, edge.from, 0, 0)
        pcall(texture.SetPoint, texture, edge.to, frame, edge.to, 0, 0)
        if edge.horizontal then
            pcall(texture.SetWidth, texture, DEPTH)
        else
            pcall(texture.SetHeight, texture, DEPTH)
        end
    end

    Shadows.Paint(texture, edge, alpha)
    if type(texture.Show) == "function" then pcall(texture.Show, texture) end
    return texture
end

--- Lay the shadow inside one element, or take it off.
--
-- @param frame table
-- @param on boolean whether the shadow is wanted
-- @param alpha number
-- @return boolean whether anything is laid
function Shadows.Lay(frame, on, alpha)
    if type(frame) ~= "table" then return false end
    alpha = tonumber(alpha) or 0

    if not on or alpha <= 0 then
        local laid = LAID[frame]
        if laid == nil then return false end
        for i = 1, #EDGES do
            local texture = laid[EDGES[i].key]
            if texture ~= nil and type(texture.Hide) == "function" then
                pcall(texture.Hide, texture)
            end
        end
        return false
    end

    local any = false
    for i = 1, #EDGES do
        if edgeOf(frame, EDGES[i], alpha) ~= nil then any = true end
    end
    return any
end

--- Apply the settings.
function Shadows:ApplySettings()
    local settings = Settings()
    if settings == nil then return end

    local on = settings.inner == true
    local alpha = Shadows.Alpha(settings.strength)

    -- Nothing laid and nothing wanted: not one frame of the game's is
    -- touched, which is the rule a fresh install is held to.
    if not on and next(LAID) == nil then return end
    if type(ns.Compat) ~= "table" or type(ns.Compat.Resolve) ~= "function" then
        return
    end

    for i = 1, #GROUPS do
        local ok, _, objects = pcall(ns.Compat.Resolve, GROUPS[i])
        if ok and type(objects) == "table" then
            for j = 1, #objects do Shadows.Lay(objects[j], on, alpha) end
        end
    end

    -- The buttons of the addons the player uses, under the same two
    -- conditions their windows are darkened by: named in the layer, and
    -- loaded now.
    if type(ns.Compat.ResolveAddonButtons) == "function"
        and type(ns.Compat.ResolveFunction) == "function" then
        local got, isLoaded = pcall(ns.Compat.ResolveFunction, "addon-loaded")
        if got and type(isLoaded) == "function" then
            local fine, _, objects =
                pcall(ns.Compat.ResolveAddonButtons, nil, isLoaded)
            if fine and type(objects) == "table" then
                for j = 1, #objects do Shadows.Lay(objects[j], on, alpha) end
            end
        end
    end
end

--- Enabling the subsystem.
--
-- The elements it dresses are made by the game and by other addons, and
-- some arrive after we do. Entering the world and an addon loading are the
-- two moments at which that is true, and they are the two the darkening
-- listens for as well.
function Shadows:OnEnable()
    local me = ns.Registry:NameOf(Shadows)
    if type(ns.Events) ~= "table" or me == nil then return end

    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ADDON_LOADED" }) do
        ns.Events.Subscribe(event, me, function()
            Shadows:ApplySettings()
        end)
    end
end

--============================================================================
-- The settings page, declared as data
--============================================================================

if type(ns.Schema) == "table" then
    local Schema = ns.Schema
    local PAGE = "shadows"

    Schema.Page(PAGE, {
        title = "Shadows",
        order = 8.5,
        section = "shadows",
    })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "A shadow laid inside an element's own edges, so it reads as "
            .. "sunk into the dark interface rather than laid on top of it.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Inner Shadow",
        path = { "inner" },
        apply = "shadows",
        hint = "Lays the shadow along the inside of the buttons' edges. Off "
            .. "by default, like every look of our own.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Shadow Strength",
        path = { "strength" },
        apply = "shadows",
        min = 0,
        max = 100,
        step = 5,
        hint = "How dark the edge is. The depth stays as it is: a deeper "
            .. "shadow on a small button is not a stronger shadow, it is a "
            .. "smaller icon.",
    })
end

ns.Registry:Register(Shadows)
