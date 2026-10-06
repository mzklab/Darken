local ADDON, ns = ...

-- Icons: a border around each one, and the trimming of the native edge.
--
-- === What this is here for ===
--
-- The dimming can do exactly one thing: multiply the colour of what the game
-- has already drawn. Where there is no line it cannot help, and that is
-- exactly what can be seen on the action bar's buttons: a button's native edge
-- is part of its own picture, it goes dark along with it, and a row of buttons
-- turns into a row of dark patches with no borders. The author sent in a
-- screenshot of the bottom row asking what had happened to the shadows there —
-- there are no borders on it at all.
--
-- The addon the author took as a model answers that with a border of its own
-- over the button and with the trimming of an icon's native edge (its Borders
-- section). Here it is the same thing and by the same two settings.
--
-- === What draws it ===
--
-- The same thing the addon draws any of its own lines with — ns.Skin.Outline.
-- A second way of drawing a border would mean a second shade and a second
-- thickness on one screen, and that reads as a mistake rather than as styling.
--
-- === Why we do not touch the native textures ===
--
-- The native edge is not stripped but trimmed by the picture's coordinates
-- (SetTexCoord): a texture that was stripped does not come back, while a
-- setting that is switched off has to return the native look without a reload
-- of the interface. The trimming is reversed by one call with the former
-- numbers.
--
-- === Protected buttons ===
--
-- An action bar's button is protected by the engine. Our border is our texture
-- on a foreign frame, and creating it in combat meets a refusal from the
-- engine rather than passing quietly: so work during combat is deferred to its
-- end by the same path everything else in the addon defers by (ns.Combat).

local Icons = {
    name = "icons",
}
ns.Icons = Icons

-- The tally of what was done (Core/Tally.lua).
local counters = ns.Counters or {}
ns.Counters = counters

-- How many icons were framed. A zero with the setting on means that not one
-- button name was found on this client — that is, the setting exists and no
-- work happened.
counters.framed = counters.framed or 0

-- Trimmed edges and rounded minimap buttons, each counted on its own.
--
-- All three used to add to "framed", and the single number was then read as
-- proof of whichever of the three was being argued about. It proved none of
-- them.
counters.cropped = counters.cropped or 0
counters.rounded = counters.rounded or 0

-- An icon's border: button -> the set of sides (see ns.Skin.Outline).
--
-- Side memory rather than a field on the button: a button is a game object,
-- and a field on it would mark it. The same rule and the same reason as the
-- bag slot's outline (Modules/Bags.lua).
local FRAME = ns.Skin.Memory()

-- The icon picture's native coordinates: texture -> { left, right, top,
-- bottom }.
--
-- Remembered at the first trimming and restored when it is switched off.
-- Without this, "put it back as it was" would mean "set the numbers we
-- consider native", that is, a guess about somebody else's picture.
local COORDS = ns.Skin.Memory()

-- The backing behind a bar: bar -> our texture.
--
-- Side memory for the same reason an icon's border is: a bar is a game object,
-- and a field on it would mark it.
local SHADOW = ns.Skin.Memory()

-- The groups of the bars themselves (not of their buttons): the backing goes
-- under these.
local BAR_GROUPS = {
    "actionbar-main",
    "actionbar-bottomleft",
    "actionbar-bottomright",
    "actionbar-right",
    "actionbar-left",
    "actionbar-pet",
    "actionbar-stance",
}

-- The ring around a minimap button: button -> the set of sides.
local RING = ns.Skin.Memory()

-- The icons whose mask we set: icon -> true.
--
-- Needed for the same reason the trimming's native coordinates are: only what
-- one set oneself may be removed. Somebody else's mask, removed by us, is
-- somebody else's broken button.
local MASKED = ns.Skin.Memory()

-- The game's round mask. The game cuts portraits into circles with it
-- itself, and there is no point creating a second such picture: one of our own
-- would be the very same thing, only ours.
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- How much wider the backing is than the bar. Four pixels on each side —
-- exactly enough for it to read as a backing rather than as a second border
-- pressed against it.
local SHADOW_PAD = 4

-- The border's colour. The same one the addon draws all its lines with.
local BORDER_COLOR = "line"

-- How much of an icon's native edge is trimmed.
--
-- Eight hundredths is the same share the model addon cuts, and it is not
-- accidental: the edge is drawn inside the icon's own picture, and exactly it
-- has to be cut away without touching the drawing. More, and a spell loses the
-- edge of its drawing; less, and the border stays visible as a strip.
local CROP = 0.08

-- The fields a button keeps its icon in.
--
-- Field names rather than frame names: a field is part of a button's
-- construction rather than a name in the globals, and so it is asked of the
-- button itself. The same device and for the same reason as the contents in
-- the dimming subsystem (Modules/Darkness.lua, CONTENT_FIELDS).
local ICON_FIELDS = { "icon", "Icon", "IconTexture", "iconTexture" }

-- What the older templates append to a button's name to name its icon.
local ICON_SUFFIX = "Icon"

-- The compatibility layer's groups whose buttons are framed.
--
-- A list of groups rather than a list of names: the buttons' names live in the
-- compatibility layer, and a second list of them would diverge from the first
-- silently — precisely what the layer is written against.
local GROUPS = {
    "actionbar-main-buttons",
    "actionbar-bottomleft-buttons",
    "actionbar-bottomright-buttons",
    "actionbar-right-buttons",
    "actionbar-left-buttons",
    "actionbar-pet-buttons",
    "actionbar-stance-buttons",

    -- The buff and debuff icons. In the model addon that is a switch of its
    -- own; here they go through the same pass and the same setting, because
    -- the player's question is one: whether to outline the icons. Two switches
    -- for one question are two places where one can forget.
    "aura-buttons",
    "aura-debuff-buttons",
}

-- The default is the game's native look: a fresh install does not touch the
-- icons.
--
-- That is the same rule by which a fresh install touches not one frame of the
-- game, and there is exactly one exception to it in the whole addon — the
-- dimming slider (Modules/Darkness.lua).
Icons.defaults = {
    border = false,
    crop   = false,
    shadow = false,
    minimap = false,

    -- The shape of the minimap. False is the game's own, which on every
    -- client served here is round: a fresh install changes nothing.
    square = false,
}

--- The subsystem's settings from the profile.
-- @return table|nil
local function Settings()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    if not profile then return nil end
    return profile[Icons.name]
end

--- A button's icon, or nil.
-- A pure function of the object: the fields are asked of the object itself.
-- @param button table|nil
-- @return table|nil
function Icons.IconOf(button)
    if type(button) ~= "table" then return nil end

    for i = 1, #ICON_FIELDS do
        local icon = button[ICON_FIELDS[i]]
        if type(icon) == "table" and type(icon.SetTexCoord) == "function" then
            return icon
        end
    end

    -- The older clients keep the icon nowhere but in a global.
    --
    -- A field on the button is how today's templates hand it over
    -- (parentKey="icon"). The older XML writes the texture as "$parentIcon",
    -- which makes the global ActionButton1Icon and leaves the button itself
    -- with no field at all - and the loop above then answers nothing.
    --
    -- Everything on this page rested on that answer: the outline is drawn
    -- around the icon and the trimming is done to the icon, so on such a
    -- client BOTH settings did nothing whatever was ticked. The author said
    -- so three times - "none of the settings work" - while the pass reported
    -- buttons touched, because the count is shared with work that did
    -- succeed.
    --
    -- The suffix is composed rather than written out: a name of the game's
    -- belongs in the compatibility layer, and the button's own name comes
    -- from there already. What is added here is the one word the template
    -- appends.
    if type(button.GetName) ~= "function" then return nil end

    local ok, said = pcall(button.GetName, button)
    if not ok then return nil end

    said = ns.Skin.Textual(said)
    if said == nil or said == "" then return nil end

    local icon = _G[said .. ICON_SUFFIX]
    if type(icon) == "table" and type(icon.SetTexCoord) == "function" then
        return icon
    end

    return nil
end

--- Trim an icon's native edge, or put it back.
--
-- The native coordinates are remembered at the first trimming: restoring them
-- means setting exactly what was there rather than what we consider usual.
--
-- @param icon table|nil the icon's texture
-- @param crop boolean whether to trim
-- @return boolean whether the icon was touched
function Icons.Crop(icon, crop)
    if type(icon) ~= "table" then return false end
    if type(icon.SetTexCoord) ~= "function" then return false end

    if crop then
        if COORDS[icon] == nil then
            local ok, left, right, top, bottom = pcall(icon.GetTexCoord, icon)
            if ok and ns.Skin.Numeric(left) ~= nil then
                COORDS[icon] = { left, right, top, bottom }
            else
                -- We were not allowed to read: the native coordinates are
                -- unknown, and there is nothing to trim — we would not be
                -- able to put this back.
                return false
            end
        end

        return pcall(icon.SetTexCoord, icon, CROP, 1 - CROP, CROP, 1 - CROP)
    end

    local saved = COORDS[icon]
    if saved == nil then return false end

    COORDS[icon] = nil
    return pcall(icon.SetTexCoord, icon, saved[1], saved[2], saved[3], saved[4])
end

--- Show or hide a set of our textures.
-- @param set table|nil
-- @param show boolean
local function display(set, show)
    if type(set) ~= "table" then return end

    for _, side in pairs(set) do
        if type(side) == "table" then
            if show then pcall(side.Show, side) else pcall(side.Hide, side) end
        end
    end
end

--- The border around one button.
-- @param button table
-- @param border boolean whether to draw it
-- @return boolean whether it was drawn
local function frame(button, border)
    if type(button) ~= "table" then return false end

    if not border then
        display(FRAME[button], false)
        return false
    end

    if type(button.CreateTexture) ~= "function" then return false end

    -- Around the ICON, not around the button.
    --
    -- It used to be the button, and the line was invisible - not missing,
    -- invisible. The colour is "line", near black, and the button's outer edge
    -- is surrounded by the bar's own dark art; a near-black hairline on that,
    -- at a UI scale below one, is a thing nobody can see. The author said
    -- three times that the setting does nothing, and he was right about what
    -- he saw.
    --
    -- Against the icon the same line reads as what it was asked for: the
    -- picture is bright, the line is dark, and the icon stops bleeding into
    -- the button around it. The minimap buttons in this same file have always
    -- been outlined this way (Icons.Round) - the action bars were the odd one
    -- out.
    --
    -- The button is still what holds the textures: an icon is not a frame and
    -- cannot own one. Only the anchor moves.
    local icon = Icons.IconOf(button)
    if icon == nil then return false end

    local ok = pcall(ns.Skin.Outline, button, FRAME, icon, BORDER_COLOR)
    if not ok then return false end

    display(FRAME[button], true)
    return true
end

--- Lay the backing under one bar, or take it away.
--
-- The backing is our texture on a foreign frame, and so it lives in side
-- memory: showing it again is cheaper than creating it afresh, and this API
-- does not let a texture be released anyway.
--
-- @param bar table the bar
-- @param shadow boolean whether to lay it
-- @return boolean whether it was laid
function Icons.Shade(bar, shadow)
    if type(bar) ~= "table" then return false end

    local texture = SHADOW[bar]

    if not shadow then
        if texture and type(texture.Hide) == "function" then
            pcall(texture.Hide, texture)
        end
        return false
    end

    if texture == nil then
        if type(bar.CreateTexture) ~= "function" then return false end

        local ok, made = pcall(bar.CreateTexture, bar, nil, "BACKGROUND")
        if not ok or type(made) ~= "table" then return false end

        texture = made
        SHADOW[bar] = texture

        -- Under the bar itself and four pixels wider on each side.
        pcall(texture.SetPoint, texture, "TOPLEFT", bar, "TOPLEFT",
            -SHADOW_PAD, SHADOW_PAD)
        pcall(texture.SetPoint, texture, "BOTTOMRIGHT", bar, "BOTTOMRIGHT",
            SHADOW_PAD, -SHADOW_PAD)
        pcall(texture.SetColorTexture, texture, ns.Skin.Get("panel"))
    end

    if type(texture.Show) == "function" then pcall(texture.Show, texture) end
    return true
end

--- Round one minimap button, or return it to its look.
--
-- The button is somebody else's, and exactly one thing of its own is touched:
-- the mask on the icon's picture. The mask is removed by the same call with an
-- empty path, so switching it off returns the button to its look without a
-- reload — the same rule as for the trimming of the edge.
--
-- @param button table the minimap button
-- @param round boolean whether to round it
-- @return boolean whether it was touched
function Icons.Round(button, round)
    local icon = Icons.IconOf(button)
    if type(icon) ~= "table" then return false end
    if type(icon.SetMask) ~= "function" then return false end

    if not round then
        -- Only OUR mask is removed.
        --
        -- An unconditional removal used to stand here, and that was not an
        -- extra call but damage: an addon that set a mask of its own on its
        -- button lost it from one switch of ours — even though we had never
        -- touched that button. We neither repair nor break what belongs to
        -- others.
        if MASKED[icon] then
            MASKED[icon] = nil
            pcall(icon.SetMask, icon, "")
        end
        if RING[button] then display(RING[button], false) end
        return false
    end

    if not pcall(icon.SetMask, icon, ROUND_MASK) then return false end
    MASKED[icon] = true

    -- The ring is our own line, as it is around our own button.
    if type(button.CreateTexture) == "function" then
        if pcall(ns.Skin.Outline, button, RING, icon, BORDER_COLOR) then
            display(RING[button], true)
        end
    end

    return true
end

--- The masks a minimap is cut with.
--
-- A square needs a mask opaque everywhere, and the game ships one: a solid
-- white 8x8. A circle needs one that fades at the rim, and the portrait mask
-- is it - round, present in every client line served here, and the very file
-- the game cuts the minimap with itself.
--
-- These are paths to the game's own art rather than frame names, so they are
-- not the compatibility layer's business: that layer answers "what is this
-- frame called here", and a texture path is the same everywhere.
-- everywhere.
local MASKS = {
    square = "Interface\\BUTTONS\\WHITE8X8",
    round  = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
}

--- Cut the minimap square or round.
--
-- Why "the game's own" is reconstructed rather than remembered. Every other
-- setting here remembers what it found and writes exactly that back. A mask
-- cannot be read: the API has SetMaskTexture and no getter, so there is
-- nothing to remember at the first touch. What the native choice does instead
-- is set the shape the game itself cuts on these clients - round, ring shown.
-- The same picture by a different road, written down so that nobody later
-- reads it as carelessness.
--
-- The ring is hidden for a square map because it is drawn as a circle: left
-- up, it lies across the corners and reads as a broken addon rather than as a
-- square map. Its names come from the compatibility layer.
--
-- The zoom buttons, the mail and tracking icons and the zone text are not
-- touched. The game anchors them to the map and they follow it; moving them
-- would be a second opinion about where they belong.
--
-- @param square boolean whether to cut it square
-- @return boolean whether the shape was set
function Icons.Shape(square)
    local minimap = _G.Minimap
    if type(minimap) ~= "table" then return false end
    if type(minimap.SetMaskTexture) ~= "function" then return false end

    local mask = square and MASKS.square or MASKS.round
    if not pcall(minimap.SetMaskTexture, minimap, mask) then return false end

    local ok, _, objects = pcall(ns.Compat.Resolve, "minimap-ring")
    if ok and type(objects) == "table" then
        for i = 1, #objects do
            local ring = objects[i]
            if type(ring) == "table" and type(ring.SetShown) == "function" then
                pcall(ring.SetShown, ring, not square)
            end
        end
    end

    return true
end

--- Round other addons' minimap buttons.
--
-- Whose buttons these are is asked by the same rule the dimming tells another
-- addon's window from the game's own by: the name plus the list of installed
-- addons (Modules/Darkness.lua, Darkness.AddonWindow). The game's own buttons
-- are not touched — they are round already, and the few that are not are drawn
-- that way on purpose.
--
-- @param round boolean
-- @return number how many buttons were touched
function Icons.RoundMinimap(round)
    local minimap = _G.Minimap
    if type(minimap) ~= "table" then return 0 end
    if type(minimap.GetChildren) ~= "function" then return 0 end

    local dark = ns.Darkness
    if type(dark) ~= "table" or type(dark.AddonWindow) ~= "function" then
        return 0
    end

    local ok, children = pcall(function() return { minimap:GetChildren() } end)
    if not ok then return 0 end

    local names = dark.AddonNames()
    local touched = 0

    for i = 1, #children do
        local button = children[i]
        local said = type(button) == "table"
            and type(button.GetName) == "function" and button:GetName() or nil

        if dark.AddonWindow(ns.Skin.Textual(said), names) then
            if Icons.Round(button, round) then
                touched = touched + 1
                counters.rounded = counters.rounded + 1
            end
        end
    end

    return touched
end

--- Frame and trim the icons of every button.
--
-- The pass goes over the compatibility layer's groups: a group that does not
-- exist on this client returns an empty list, and the loop silently does
-- nothing. There are no checks of the client's version here and there must not
-- be.
--
-- @param border boolean whether to draw the border
-- @param crop boolean whether to trim the native edge
-- @return number how many buttons were touched
function Icons.Paint(border, crop, shadow, round)
    local touched = Icons.RoundMinimap(round)

    for i = 1, #BAR_GROUPS do
        local ok, names, objects = pcall(ns.Compat.Resolve, BAR_GROUPS[i])
        if ok and type(objects) == "table" then
            for j = 1, #objects do
                if Icons.Shade(objects[j], shadow) then
                    touched = touched + 1
                    counters.framed = counters.framed + 1
                end
            end
        end
    end

    for i = 1, #GROUPS do
        local ok, names, objects = pcall(ns.Compat.Resolve, GROUPS[i])
        if ok and type(objects) == "table" then
            for j = 1, #objects do
                local button = objects[j]
                local painted = frame(button, border)
                local cropped = Icons.Crop(Icons.IconOf(button), crop)
                if painted then counters.framed = counters.framed + 1 end
                if cropped then counters.cropped = counters.cropped + 1 end
                if painted or cropped then touched = touched + 1 end
            end
        end
    end

    return touched
end

--- Applying the settings.
--
-- Deferred entirely during combat: the bars' buttons are protected by the
-- engine, and creating our texture on them in combat will be rejected. Waiting
-- for the end of combat is safe here — nothing changes on screen because of
-- it except what was not changing anyway.
function Icons:ApplySettings()
    local settings = Settings()
    if not settings then return end

    local border = settings.border == true
    local crop   = settings.crop == true
    local shadow = settings.shadow == true
    local round  = settings.minimap == true
    local square = settings.square == true

    if ns.Combat and ns.Combat.InCombat and ns.Combat.InCombat() then
        ns.Combat.Enqueue(ns.Combat.QueueFor(Icons.name), "icons", function()
            Icons.Paint(border, crop, shadow, round)
            Icons.Shape(square)
        end)
        return
    end

    Icons.Paint(border, crop, shadow, round)
    Icons.Shape(square)
end

--- Enabling the subsystem.
--
-- The game does not assemble the action bars at once: the buttons appear along
-- with a bar, and a bar on entering the world. So the pass is repeated on the
-- same event the dimming repeats it on.
function Icons:OnEnable()
    if type(ns.Events) ~= "table" then return end

    ns.Events.Subscribe("PLAYER_ENTERING_WORLD", Icons.name, function()
        Icons:ApplySettings()
    end)
end

Icons.options = {
    type = "group",
    name = ns.Localize("Icon Borders"),
    args = {
        border = {
            type = "toggle",
            order = 1,
            width = "full",
            name = ns.Localize("Frame the Icons"),
            desc = ns.Localize("Draws a one pixel line around every action " ..
                "button and every buff and debuff icon, in the same color " ..
                "the addon draws all of its own " ..
                "lines. Dimming multiplies the color of what the game has " ..
                "already drawn; a line that is not there it cannot draw - " ..
                "and the game's own button edge is part of the button's " ..
                "picture, so it goes dark along with it and the row turns " ..
                "into dark patches with no borders. Off by default."),
            get = function()
                local settings = Settings()
                return settings ~= nil and settings.border == true
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.border = value and true or false
                Icons:ApplySettings()
            end,
        },
        shadow = {
            type = "toggle",
            order = 3,
            width = "full",
            name = ns.Localize("Backing Behind the Bars"),
            desc = ns.Localize("Lays the addon's own panel color behind " ..
                "each action bar, a few pixels wider than the bar itself. " ..
                "It gives the row an edge where the game draws none, the " ..
                "same way the line above gives one to a button. Off by " ..
                "default."),
            get = function()
                local settings = Settings()
                return settings ~= nil and settings.shadow == true
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.shadow = value and true or false
                Icons:ApplySettings()
            end,
        },
        minimap = {
            type = "toggle",
            order = 4,
            width = "full",
            name = ns.Localize("Round the Minimap Buttons"),
            desc = ns.Localize("Cuts the square buttons other addons put " ..
                "around the minimap into circles and gives each the same " ..
                "line the icons above get. Only other addons' buttons: the " ..
                "game's own are round already, and the few that are not " ..
                "are drawn that way on purpose. Off by default."),
            get = function()
                local settings = Settings()
                return settings ~= nil and settings.minimap == true
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.minimap = value and true or false
                Icons:ApplySettings()
            end,
        },
        crop = {
            type = "toggle",
            order = 2,
            width = "full",
            name = ns.Localize("Trim the Icon Edges"),
            desc = ns.Localize("Cuts the game's own dark edge off each " ..
                "spell icon, the way a modern interface does. Nothing is " ..
                "removed: the picture is shown without its outermost " ..
                "border, and switching this off puts back exactly the " ..
                "coordinates the icon had. Best with the line above, " ..
                "which then becomes the button's edge."),
            get = function()
                local settings = Settings()
                return settings ~= nil and settings.crop == true
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.crop = value and true or false
                Icons:ApplySettings()
            end,
        },
    },
}

--============================================================================
-- The settings page, declared as data
--============================================================================

if type(ns.Schema) == "table" then
    local Schema = ns.Schema
    local PAGE = "icons"

    Schema.Page(PAGE, {
        title = "Icons",
        order = 8,
        section = "icons",
    })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "Spell and item icons across the whole interface. Each of "
            .. "these is off on a fresh install: an icon is how the player "
            .. "recognises a spell, and changing it is a choice, not a "
            .. "default.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Outline Icons",
        path = { "border" },
        apply = "icons",
        hint = "A thin line around every icon, in the addon's own colour.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Crop Icon Borders",
        path = { "crop" },
        apply = "icons",
        hint = "Trim the dull edge the artist drew around each icon, so the "
            .. "picture itself fills the square.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Shadow Under Icons",
        path = { "shadow" },
        apply = "icons",
        hint = "A soft shadow behind every icon, so icons read apart from "
            .. "the darkened interface behind them.",
    })

    -- The label used to read "Square Minimap", and the hint under it promised
    -- to "cut the minimap square instead of round". Neither was true: this key
    -- has only ever driven Icons.RoundMinimap, which rounds the buttons OTHER
    -- addons put around the minimap. The old options table beside this one has
    -- carried the honest name all along, and the window got the wrong one.
    --
    -- A setting that names the wrong thing is worse than a missing one: the
    -- player ticks it, the minimap stays round, and what they conclude is that
    -- the addon is broken. The shape of the minimap is a separate thing and
    -- will get a setting of its own, with its own key.
    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Square Minimap",
        path = { "square" },
        apply = "icons",
        hint = "Cuts the minimap square instead of round. The ring around it "
            .. "is drawn as a circle and would lie across the corners, so it "
            .. "is taken away with the same tick. Off by default.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Round the Minimap Buttons",
        path = { "minimap" },
        apply = "icons",
        hint = "Cuts the square buttons other addons put around the minimap "
            .. "into circles and gives each the same line the icons above "
            .. "get. Only other addons' buttons: the game's own are round "
            .. "already, and the few that are not are drawn that way on "
            .. "purpose. Off by default.",
    })
end

ns.Registry:Register(Icons)
