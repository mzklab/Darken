local ADDON, ns = ...

-- The minimap button: a door into the settings that is always visible.
--
-- === What it is for ===
--
-- There are three doors into the settings window: the slash command, the
-- addon's page in the game's own options, and this button. The first two have
-- to be known: the command has to be remembered as a word, the page has to be
-- found among other people's. The button requires knowing nothing, which is
-- why every addon a player opens more often than once a month has one. In the
-- addon the author took as a model it is the very first setting in the list.
--
-- === Why our own rather than LibDBIcon ===
--
-- The library does exactly this and does it well, but it drags a second one
-- along (LibDataBroker) plus a store of its own for the position. What is
-- needed here is a ring, an icon and an angle — thirty lines — while every
-- library in the distribution is one more foreign version that has to be
-- updated and that fails somewhere other than our code.
--
-- === Where the angle is kept ===
--
-- In the database's shared section (db.global) rather than in the profile: the
-- button is one per account, and switching profiles must not move it. That is
-- the same rule by which the catalogue of windows that have been seen lives in
-- the shared section.

local Launcher = {
    name = "launcher",
}
ns.Launcher = Launcher

-- The button frame's name. Named with the addon's prefix, like everything it
-- creates: other addons find it by that name, and so does our own dimming
-- walk, in order not to touch our button.
local FRAME_NAME = ADDON .. "MinimapButton"

-- The button's icon — the same one the addon has in the addon list.
local ICON = "Interface\\AddOns\\" .. ADDON
    .. "\\Media\\branding\\darken-icon-64"

-- The sizes: the button, the ring around it and the icon inside.
--
-- The same as the game's buttons and as LibDBIcon, which half the addons use:
-- 31 by 31 for the button itself, 53 by 53 for the ring (it is drawn with
-- margins at the edges) and 20 by 20 for the icon. A button that stands out by
-- its size reads as a foreign one.
local SIZE, RING_SIZE, ICON_SIZE = 31, 53, 20

-- The icon's brightness at rest. Not one — otherwise "white under the mouse"
-- is indistinguishable from white at rest, and a hover is visible only by the
-- tooltip, that is, half a second later and away from the button.
local REST = 0.82

-- The margin from the minimap's edge to the button's centre.
--
-- The radius is computed from the map itself rather than written as a number:
-- a minimap can be any size — both the player in the game's settings and
-- other addons change it. With a constant radius the button ended up INSIDE a
-- large map, over the terrain: the author sent in such a screenshot.
local EDGE = 10

-- The radius for the case where there is no map on this client at all
-- (outside the game).
local RADIUS = 80

-- The mask the backdrop is cut into a circle with. The same one that rounds
-- other addons' minimap buttons (Modules/Icons.lua).
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- The button's round border.
--
-- The same one the game outlines its own minimap buttons with: a button on a
-- round map has to be round, while ours used to be drawn with a square line of
-- our own skin — on the map that reads as a foreign sticker.
local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"

-- The default angle: the button sits where a round minimap has the fewest
-- foreign buttons — at the bottom left.
local DEFAULT_ANGLE = 225

-- The button has no values of its own in the profile: it is one per
-- account.
Launcher.defaults = {}

-- The shared values (db.global.launcher). The ordinary path, the subsystem's
-- own: the core puts them under the subsystem's name
-- (ns.InjectModuleDefaults), and there is no second store beside this one.
--
-- Shown by default: a door the player does not know about is not a door, and
-- the model addon's very first setting is exactly this one.
Launcher.globals = {
    shown = true,
    angle = DEFAULT_ANGLE,
}

--- The button's shared settings (db.global.launcher).
-- @return table|nil
local function Store()
    local db = ns.Addon and ns.Addon.db
    local global = db and db.global
    if type(global) ~= "table" then return nil end

    -- The core creates the section out of Launcher.globals; here it is only
    -- read.
    local store = global[Launcher.name]
    if type(store) ~= "table" then return nil end
    return store
end

--- The button's position from an angle.
--
-- A pure function: an angle in degrees in, an offset from the minimap's centre
-- out. It is tested without a client, which is why the trigonometry is here
-- rather than in the drag handler.
--
-- @param angle number|nil the degrees
-- @param radius number|nil the distance from the centre
-- @return number, number
function Launcher.Place(angle, radius)
    local degrees = tonumber(angle) or DEFAULT_ANGLE
    local far = tonumber(radius) or RADIUS
    local radians = math.rad(degrees)

    return math.cos(radians) * far, math.sin(radians) * far
end

--- The angle the cursor ended up at, relative to the minimap's centre.
--
-- A pure function of two points. The answer is brought into 0..360: an angle
-- that went negative, saved as it is, would put the button back in the same
-- place, but it would be impossible to read it in the saved variables file.
--
-- @param cx number|nil the centre, horizontally
-- @param cy number|nil the centre, vertically
-- @param x number|nil the cursor, horizontally
-- @param y number|nil the cursor, vertically
-- @return number the degrees
function Launcher.AngleOf(cx, cy, x, y)
    local dx = (tonumber(x) or 0) - (tonumber(cx) or 0)
    local dy = (tonumber(y) or 0) - (tonumber(cy) or 0)

    local degrees = math.deg(math.atan2(dy, dx))
    if degrees < 0 then degrees = degrees + 360 end
    return degrees
end

-- The button itself. Created at its first display and living until the end of
-- the session.
local button

--- The radius the button stands at on this minimap.
--
-- Half the map's width plus the margin: the button sits with its centre on the
-- edge, the way the game's and other addons' buttons sit. There is no map
-- (outside the game) — then the old number stays, and the tests have something
-- to compute from.
--
-- @return number
local function radius()
    local map = _G.Minimap
    if type(map) ~= "table" or type(map.GetWidth) ~= "function" then
        return RADIUS
    end

    local ok, width = pcall(map.GetWidth, map)
    if not ok or type(width) ~= "number" or width <= 0 then return RADIUS end

    return width / 2 + EDGE
end

--- Put the button at its angle.
local function place()
    if not button then return end

    local store = Store()
    local x, y = Launcher.Place(store and store.angle, radius())

    button:ClearAllPoints()
    button:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

--- Create the button, if it does not exist yet.
-- @return table|nil
local function build()
    if button then return button end
    if type(_G.CreateFrame) ~= "function" then return nil end
    if type(_G.Minimap) ~= "table" then return nil end

    local frame = _G.CreateFrame("Button", FRAME_NAME, _G.Minimap)
    frame:SetSize(SIZE, SIZE)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel((_G.Minimap:GetFrameLevel() or 0) + 8)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("AnyUp")

    -- A minimap button's layout is not our invention but the one everybody
    -- shares.
    --
    -- The numbers are taken from what half the addons use (LibDBIcon): the
    -- button 31 by 31, the border 53 by 53 from the top left corner, the icon
    -- 20 by 20 offset 7 right and 5 down, and the picture trimmed at the
    -- edges. That is not arbitrary: the game's border is drawn with margins at
    -- the edges, and an icon placed in the centre spills out of its ring — the
    -- author saw exactly that and called it a scrawl.
    --
    -- The backdrop under the icon.
    --
    -- The icon is drawn transparent: on a dark map it reads as a hole in the
    -- ring, and on light terrain it disappears entirely. The backdrop is our
    -- own dark shade, the same one the addon paints the background of its
    -- windows with, and the icon stands on it rather than on whatever happens
    -- to be under the button.
    --
    -- It is round for the same reason everything here is: the ring is round. A
    -- client without masks lives through this silently — the corners are
    -- hidden by the ring anyway.
    local backdrop = frame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetSize(ICON_SIZE + 2, ICON_SIZE + 2)
    backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -4)
    if type(backdrop.SetColorTexture) == "function" then
        pcall(backdrop.SetColorTexture, backdrop, ns.Skin.Get("ink"))
    end
    if type(backdrop.SetMask) == "function" then
        pcall(backdrop.SetMask, backdrop, ROUND_MASK)
    end
    frame.backdrop = backdrop

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -5)

    -- Trimming the edges instead of a mask: the icon is square, the ring is
    -- round, and the picture's corners are hidden by the ring anyway. A mask
    -- is not needed here, while an extra call on somebody else's client is an
    -- extra failure.
    if type(icon.SetTexCoord) == "function" then
        pcall(icon.SetTexCoord, icon, 0.07, 0.93, 0.07, 0.93)
    end
    frame.icon = icon
    Launcher.Recolour()

    -- The game's ring — the same one the game's own and other addons'
    -- buttons have.
    local ring = frame:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(BORDER)
    ring:SetSize(RING_SIZE, RING_SIZE)
    ring:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.ring = ring

    frame:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function()
            if type(_G.GetCursorPosition) ~= "function" then return end

            local scale = _G.UIParent and _G.UIParent:GetEffectiveScale() or 1
            local mx, my = _G.Minimap:GetCenter()
            local cx, cy = _G.GetCursorPosition()
            if not mx or not cx then return end

            local store = Store()
            if store then
                store.angle = Launcher.AngleOf(mx, my, cx / scale, cy / scale)
            end
            place()
        end)
    end)

    frame:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
    end)

    frame:SetScript("OnClick", function()
        local addon = ns.Addon
        if type(addon) ~= "table" then return end

        -- A toggle rather than an opener. A click while the window is open
        -- has to close it: otherwise the button does nothing on a second
        -- click, and the window can only be closed by its cross. The author
        -- said so plainly.
        if type(addon.ToggleConfig) == "function" then
            addon:ToggleConfig()
        elseif type(addon.OpenConfig) == "function" then
            -- An older core — then the former behaviour stays rather than an
            -- error.
            addon:OpenConfig()
        end
    end)

    frame:SetScript("OnEnter", function(self)
        -- Under the mouse the icon brightens to white.
        --
        -- There was no response at all: the button showed a tooltip and
        -- answered with nothing else, and a hover was visible only by the
        -- tooltip — that is, half a second later and away from the button
        -- itself. Not one button of the interface behaves that way.
        --
        -- White rather than the palette's accent: the icon already has an
        -- accent of its own, and an accent on an accent does not read.
        if self.icon then
            pcall(self.icon.SetVertexColor, self.icon, 1, 1, 1)
        end

        local tooltip = _G.GameTooltip
        if type(tooltip) ~= "table" then return end

        tooltip:SetOwner(self, "ANCHOR_LEFT")
        tooltip:AddLine(ADDON)
        tooltip:AddLine(ns.Localize("Click to open the settings or close "
            .. "them, drag to move this button around the minimap."),
            1, 1, 1, true)
        tooltip:Show()
    end)

    frame:SetScript("OnLeave", function(self)
        Launcher.Recolour()

        local tooltip = _G.GameTooltip
        if type(tooltip) == "table" and type(tooltip.Hide) == "function" then
            tooltip:Hide()
        end
    end)

    button = frame
    return button
end

--- Return the icon to its resting look.
--
-- At rest the icon is muted, under the mouse it is pure white. Otherwise the
-- difference cannot be seen at all: the icon's picture is drawn light, and
-- "white under the mouse" beside white at rest is one and the same thing.
--
-- The muting is deliberately slight. A minimap icon is read by peripheral
-- vision, and a dark one is lost among the game's buttons; the task here is
-- not "make it dim" but "leave it somewhere to brighten to".
function Launcher.Recolour()
    if type(button) ~= "table" or type(button.icon) ~= "table" then return end
    pcall(button.icon.SetVertexColor, button.icon, REST, REST, REST)
end

--- Show or hide the button.
-- @param shown boolean
-- @return boolean whether it is shown now
function Launcher.Display(shown)
    if not shown then
        if button then button:Hide() end
        return false
    end

    if not build() then return false end

    place()
    button:Show()
    return true
end

--- Whether the button is shown right now, by the setting.
-- @return boolean
function Launcher.Shown()
    local store = Store()
    return store == nil or store.shown ~= false
end

--- Switch the button's display.
-- @param shown boolean
function Launcher.SetShown(shown)
    local store = Store()
    if store then store.shown = shown and true or false end
    Launcher.Display(shown and true or false)
end

function Launcher:ApplySettings()
    Launcher.Display(Launcher.Shown())
end

--- Enabling the subsystem.
--
-- Why the subscription. The button sits on the minimap, and at the moment of
-- the first application the minimap may not exist: the settings are applied on
-- PLAYER_LOGIN, and on some clients the minimap has not been assembled by
-- then. A button created once lives until the end of the session, so a repeat
-- costs nothing: it is needed for exactly the case where the first attempt did
-- not succeed.
--
-- Without it this would look like "the setting is on and there is no button",
-- and there would be nothing to explain that to the player with.
function Launcher:OnEnable()
    if type(ns.Events) ~= "table" then return end

    ns.Events.Subscribe("PLAYER_ENTERING_WORLD", Launcher.name, function()
        Launcher.Display(Launcher.Shown())
    end)
end

-- The subsystem's section. It does not stand as a row in the column: one
-- checkbox does not deserve a row of its own, and it arrives as a block on the
-- General page — where the player reads what this addon is and what opens it
-- (Config/Options.lua, ns.INLINE_SECTIONS).
Launcher.options = {
    type = "group",
    name = ns.Localize("Minimap Button"),
    args = {
        shown = {
            type = "toggle",
            order = 1,
            width = "full",
            name = ns.Localize("Button on the Minimap"),
            desc = ns.Localize("A button at the edge of the minimap that " ..
                "opens this window. Drag it around the minimap to move " ..
                "it; its place is remembered for the whole account, not " ..
                "per profile. The other two doors stay where they were: " ..
                "the /dark command and the addon's page in the game's own " ..
                "interface options."),
            get = function() return Launcher.Shown() end,
            set = function(_, value) Launcher.SetShown(value) end,
        },
    },
}

ns.Registry:Register(Launcher)
