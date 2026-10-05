local helpers = require("helpers")

-- The core's case folding is needed before the modules' files are read: the
-- windows' headers are raised by the core's Casefold.Upper, and the door to
-- it is opened with the real Core/Casefold.lua rather than a fake beside it.
local coreCasefold, restoreCore = helpers.installCasefold()

-- The modules' windows take up the contract's eleventh version.
--
-- Version 11 exposed three things, and all three are answers the core had and
-- the modules did not: the dictionary of states (RowColors, ButtonColors,
-- FieldState), the height of a line of text in the scale and the font
-- category of our own windows. Before it not one module's window could do
-- selection, hovering or focus, and not one asked the player what font it is
-- written in.
--
-- What is checked here is not "what colour the selection is" — the colour
-- belongs to the core and is checked there (tests/test_skinfocus.lua,
-- tests/test_contractstates.lua). Everything in this file is about one property:
--
--   a module asks the core for a state at the moment it paints and keeps
--   neither a state colour's name, nor a number of transparency, nor a font of its own.
--
-- Hence the build of the fakes. The palette here is our own, not the real
-- one, and it can be replaced on the fly: a window that remembered a colour
-- will survive the replacement silently and fail on exactly that. The states'
-- names meanwhile are returned by the real Core/Skin.lua — so what is checked is the path to the rule rather than a copy of it.

--============================================================================
-- The core: the real rules of states and the real scale
--============================================================================

local core = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", core)
local coreSkin = core.Skin

local METRICS = {}
for key, value in pairs(coreSkin.Metrics) do METRICS[key] = value end

-- The prefix to a colour's name.
--
-- The fake's dictionary of states answers with the same states and the same
-- transparency as the core, but it returns the colours' names with a prefix
-- of its own. That is what separates "the module asked the dictionary" from
-- "the module copied lilacDeep 0.85 for itself and paints through the
-- palette": a copied name is in the palette and does paint, but it paints with something other than what the core paints with — and the check sees that.
local MARK = "probe-"

--- A fake palette: the names are the core's and marked, the numbers ours.
-- @param shift number the shift by which one palette differs from another
-- @return table name -> { r, g, b }
local function makePalette(shift)
    local names = {}
    for name in pairs(coreSkin.Palette) do names[#names + 1] = name end
    table.sort(names)

    local out = {}
    for i = 1, #names do
        out[names[i]] = { (i + shift) / 100, (i + shift) / 200,
            (i + shift) / 300 }
        out[MARK .. names[i]] = { (i + shift) / 7, (i + shift) / 11,
            (i + shift) / 13 }
    end
    return out
end

--============================================================================
-- The fake engine: labels, textures and scripts
--============================================================================
--
-- A texture here remembers its colour: that is what it is all written for. A
-- label remembers the font object and the template it was created with — by
-- the template the numeric columns living on the game's digit font are told apart.

local regions = {}

--- A region: a label or a texture.
-- @param template string|nil the font template, if this is a label
-- @return table
local function fakeRegion(template)
    local region = { shown = true, template = template }
    function region:SetText(value) self.text = value end
    function region:GetText() return self.text end
    function region:SetPoint() end
    function region:ClearAllPoints() end
    function region:SetAllPoints() end
    function region:SetJustifyH(value) self.justify = value end
    function region:SetWordWrap() end
    function region:SetWidth(value) self.width = value end
    function region:SetHeight() end
    function region:SetSize() end
    function region:SetTexture() end
    function region:SetVertexColor() end
    function region:SetFontObject(value) self.font = value end
    function region:GetFont() return "font.ttf", 12, "" end
    function region:SetFont() return true end
    function region:SetColorTexture(r, g, b, a)
        self.color = { r, g, b, a }
    end
    function region:GetStringWidth() return 10 end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    regions[#regions + 1] = region
    return region
end

local created = {}

--- A frame covering exactly what the modules' windows call.
-- @param name string|nil
-- @return table
local function fakeFrame(name)
    local frame = { name = name, shown = false, scripts = {}, attributes = {} }
    function frame:GetName() return self.name end
    function frame:SetPoint() end
    function frame:ClearAllPoints() end
    function frame:SetSize(w, h) self.width, self.height = w, h end
    function frame:SetWidth(w) self.width = w end
    function frame:SetHeight(h) self.height = h end
    function frame:GetTop() return nil end
    function frame:GetHeight() return self.height end
    function frame:GetWidth() return self.width end
    function frame:SetFrameStrata() end
    function frame:SetMovable() end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:RegisterForClicks() end
    function frame:SetAllPoints() end
    function frame:SetScript(key, fn) self.scripts[key] = fn end
    function frame:GetScript(key) return self.scripts[key] end
    function frame:SetAutoFocus() end
    function frame:SetFontObject(value) self.font = value end
    function frame:GetFont() return "font.ttf", 12, "" end
    function frame:SetFont() return true end
    function frame:SetText(value) self.text = value end
    function frame:GetText() return self.text end
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:Show()
        self.shown = true
        local fn = self.scripts.OnShow
        if fn then fn(self) end
    end
    function frame:Hide()
        local was = self.shown
        self.shown = false
        local fn = self.scripts.OnHide
        if was and fn then fn(self) end
    end
    function frame:IsShown() return self.shown end
    function frame:CreateFontString(_, _, template)
        return fakeRegion(template)
    end
    function frame:CreateTexture() return fakeRegion(nil) end
    return frame
end

--- Call a frame's script the way the engine calls it.
-- @param frame table
-- @param key string
local function fire(frame, key)
    local fn = frame and frame.scripts and frame.scripts[key]
    if fn then fn(frame) end
end

local function fakeEngine()
    return function(_, name)
        local frame = fakeFrame(name)
        if type(name) == "string" then
            _G[name] = frame
            created[#created + 1] = name
        end
        return frame
    end
end

local function forgetFrames()
    for i = 1, #created do _G[created[i]] = nil end
    created = {}
    regions = {}
end

--============================================================================
-- The fakes of the styling and the media
--============================================================================

--- The styling: the core's rules of states over a replaceable palette.
--
-- The dictionary's three functions are the real ones, out of Core/Skin.lua:
-- what is checked is a module's path to the core's rule rather than a second
-- copy of that rule in the check. The palette is our own and replaceable: a window that remembered a colour will survive the replacement silently.
--
-- @return table the styling and a handle for replacing the palette
local function fakeSkin()
    local palette = makePalette(0)

    local skin = {}

    function skin.Color(name, alpha)
        local c = palette[name]
        if not c then return nil end
        return c[1], c[2], c[3], alpha or 1
    end

    function skin.Colors()
        local out = {}
        for name in pairs(palette) do out[#out + 1] = name end
        table.sort(out)
        return out
    end

    function skin.Metrics()
        local out = {}
        for key, value in pairs(METRICS) do out[key] = value end
        return out
    end

    function skin.Backdrop(frame, back, border)
        if type(frame) ~= "table" then return false end
        frame.umbraBack, frame.umbraBorder = back, border
        return true
    end

    function skin.Outline() return true end

    function skin.Text(region, color)
        if type(region) ~= "table" then return false end
        region.umbraColor = color
        return true
    end

    -- The rules are the core's, the names are marked: the state and the
    -- transparency come out of Core/Skin.lua, while a module can get a
    -- colour's name only from here and no other way.
    function skin.RowColors(state)
        local name, alpha = coreSkin.RowColors(state)
        if name == nil then return nil end
        return MARK .. name, alpha
    end

    function skin.ButtonColors(state, kind)
        local fill, border, text = coreSkin.ButtonColors(state, kind)
        return MARK .. fill, MARK .. border, MARK .. text
    end

    skin.FieldState = coreSkin.FieldState

    --- Replace the palette without touching the rules.
    function skin.Repaint(shift) palette = makePalette(shift) end

    --- The colour a row is obliged to be filled with in this state.
    function skin.Expect(state)
        local name, alpha = skin.RowColors(state)
        if name == nil then return nil end
        local r, g, b, a = skin.Color(name, alpha)
        return { r, g, b, a }
    end

    return skin
end

--- The media: it remembers which category a font was applied by and to what.
-- @return table
local function fakeMedia()
    local media = { applied = {}, count = 0 }

    function media.ApplyFont(category, object)
        if type(object) ~= "table" then return false end
        media.applied[object] = category
        media.count = media.count + 1
        return true
    end

    function media.FontCategories() return {} end
    function media.BarTextures() return {} end
    function media.BarTexture() return nil end
    media.NATIVE = "__native"

    return media
end

--- Compare two colours.
-- @param got table|nil
-- @param want table|nil
-- @return boolean
local function sameColor(got, want)
    if type(got) ~= "table" or type(want) ~= "table" then return false end
    for i = 1, 4 do
        if got[i] ~= want[i] then return false end
    end
    return true
end

--- A colour as a string — for a readable check message.
-- @param c table|nil
-- @return string
local function shade(c)
    if type(c) ~= "table" then return "no colour" end
    return string.format("%.3f/%.3f/%.3f/%.3f", c[1] or 0, c[2] or 0,
        c[3] or 0, c[4] or 0)
end

--============================================================================
-- The game's fakes for the duration of the file
--============================================================================

local saved = {
    CreateFrame = _G.CreateFrame,
    Darken = _G.Darken,
    UISpecialFrames = _G.UISpecialFrames,
    UIParent = _G.UIParent,
    time = _G.time,
    NumberFontNormal = _G.NumberFontNormal,
}

local DIGIT_FONT = {}

local skin, media

local function installGame()
    skin = fakeSkin()
    media = fakeMedia()
    _G.CreateFrame = fakeEngine()
    _G.UISpecialFrames = {}
    _G.UIParent = fakeFrame(nil)
    _G.NumberFontNormal = DIGIT_FONT
    _G.Darken = {
        GetCasefold = function() return coreCasefold end,
        GetSkin     = function() return skin end,
        GetMedia    = function() return media end,
    }
end

local function restoreGame()
    forgetFrames()
    _G.CreateFrame = saved.CreateFrame
    _G.Darken = saved.Darken
    _G.UISpecialFrames = saved.UISpecialFrames
    _G.UIParent = saved.UIParent
    _G.time = saved.time
    _G.NumberFontNormal = saved.NumberFontNormal
end

--- A module's descriptor, faked exactly as far as the windows call it.
-- @param source table|nil the bags' source
-- @return table
local function fakeModule(source)
    local profile, store = {}, {}
    return {
        source = source,
        GetSettings = function(_, scope)
            if scope == "global" then return store end
            return profile
        end,
        Apply = function() end,
        Publish = function() return true end,
        Secure = function(_, _, _, fn) if fn then fn() end return true end,
        IsEnabled = function() return true end,
        Localize = function(_, key) return key end,
    }
end

local DAY = 86400
local NOW = 1758700000

--- A bags source with three looks: there is something to choose from.
-- @return table
local function fakeSource()
    local empty = { slots = 4, used = 0, free = 4 }
    local source
    source = {
        Name = function() return "a check" end,
        Containers = function() return { { id = 0, slots = 4 } } end,
        Read = function() return {}, empty end,
        Roster = function()
            return {
                { key = "Zoe-R-H", name = "Zoe", realm = "R", faction = "H",
                  current = true, seen = NOW, bankSeen = NOW - DAY },
                { key = "Bob-R-H", name = "Bob", realm = "R", faction = "H",
                  seen = NOW - DAY * 3 },
            }
        end,
        Open = function() return {}, empty, { known = true, seen = NOW } end,
    }
    return source
end
T.suite("version 11: a row of the info panel's menu under the cursor")

do
    installGame()

    local panel = helpers.loadModule("Features/InfoPanel", nil,
        { withRegistration = false })
    panel.Localize = function(key) return key or "" end

    local cell = fakeFrame(nil)
    local entries = {
        { label = "first", kind = "own", enabled = true },
        { label = "second", kind = "own", enabled = true },
    }

    panel.Panel.Menu(entries, cell, "cell", skin, media, function() end)

    local rows = panel.Panel.menuRows or {}
    T.ok(#rows >= 2, "the menu built its rows: " .. #rows)

    local row = rows[1]
    T.ok(row.umbraFill == nil or row.umbraFill.shown == false,
        "an ordinary menu row is filled with nothing")

    fire(row, "OnEnter")
    T.ok(sameColor(row.umbraFill.color, skin.Expect("hover")),
        "under the cursor a row is filled with what the core called hovering: "
        .. shade(row.umbraFill.color))

    fire(row, "OnLeave")
    T.eq(row.umbraFill.shown, false, "the cursor left, the film left")

    restoreGame()
end

restoreCore()
