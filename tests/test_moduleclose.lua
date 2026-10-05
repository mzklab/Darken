local helpers = require("helpers")

-- The core's case folding is needed before the modules' files are read: the
-- windows' headers are raised by the core's Casefold.Upper, and the door to
-- it is opened with the real Core/Casefold.lua rather than a fake beside it.
local coreCasefold, restoreCore = helpers.installCasefold()

-- The modules' windows: what they are closed with.
--
-- Before this work the bag window and the item database window were closed
-- by nothing: no button, no Escape, no record in the game's list. Formally
-- "every window of the addon closes the same way" — the same way as in not at all.
--
-- Escape in this game works through one shared table: UISpecialFrames holds
-- the frames' names, and at every press the game hides those of them that
-- are shown. The table is shared across the whole interface and survives
-- everything but a reload — so what is checked here is not only "it closed"
-- but the price: a name is entered exactly once, other names are not touched,
-- and a switched-off module leaves nothing in somebody else's table.
--
-- What is checked are properties rather than numbers we chose:
--
--   1. a window enters its name once, however many times it is entered;
--   2. Escape hides what is shown and does not stumble when there is nothing to hide;
--   3. two open windows close in the order reverse to their entry — that is
--      how the game itself walks the list;
--   4. a switched-off module takes its own name away and does not touch anybody else's;
--   5. the close button of both windows is one and the same and stands in the same corner;
--   6. the numbers in the list stand in a column: the same vertical at any
--      width of the number itself.

T.suite("closing the windows: the fake engine")

--============================================================================
-- The fake engine: frames with names, scripts and remembered anchors
--============================================================================
--
-- The names here are not decoration. The Escape list stores names rather than
-- objects, and the game fetches a frame out of the global table — which means
-- the fake is obliged to put itself there too, or the check would check a path other than the one the game goes.

local created = {}

--- A label: everything that is called on it when a window is shown.
-- @return table
local function fakeRegion()
    local region = { shown = true, points = {} }
    function region:SetText(value) self.text = value end
    function region:GetText() return self.text end
    function region:SetPoint(point, relativeTo, relativePoint, x, y)
        self.points[#self.points + 1] =
            { point, relativeTo, relativePoint, x, y }
        self.point, self.x, self.y = point, x, y
    end
    function region:ClearAllPoints() self.points = {} end
    function region:SetJustifyH(value) self.justify = value end
    function region:SetWordWrap(value) self.wrap = value end
    function region:SetWidth(value) self.width = value end
    function region:SetFontObject(value) self.font = value end
    function region:GetStringWidth() return 10 end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    return region
end

--- A frame. Hide calls OnHide — that is exactly how the engine calls it, and
--- that is exactly the path Escape goes: it knows nothing of any doors of ours, it calls Hide.
-- @param name string|nil
-- @return table
local function fakeFrame(name)
    local frame = { name = name, shown = false, scripts = {}, points = {} }
    function frame:GetName() return self.name end
    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self.points[#self.points + 1] =
            { point, relativeTo, relativePoint, x, y }
        self.point, self.x, self.y = point, x, y
    end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetSize(w, h) self.width, self.height = w, h end
    function frame:SetWidth(w) self.width = w end
    function frame:SetHeight(h) self.height = h end
    function frame:GetTop() return nil end
    function frame:SetFrameStrata() end
    function frame:SetMovable() end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:RegisterForClicks() end
    function frame:SetAllPoints() end
    function frame:SetScript(key, fn) self.scripts[key] = fn end
    function frame:GetScript(key) return self.scripts[key] end
    function frame:HookScript(key, fn) self.scripts[key] = fn end
    function frame:SetAutoFocus() end
    function frame:SetFontObject(value) self.font = value end
    function frame:SetText(value) self.text = value end
    function frame:GetText() return self.text end
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
    function frame:CreateFontString() return fakeRegion() end
    function frame:CreateTexture() return fakeRegion() end
    return frame
end

--- A CreateFrame that puts a named frame into the global table.
-- @return function
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

--- Clear up the globals the fake engine made.
local function forgetFrames()
    for i = 1, #created do _G[created[i]] = nil end
    created = {}
end

--- A styling that answers with the core's real scale and draws nothing.
-- @param metrics table
-- @return table
local function fakeSkin(metrics)
    return {
        Color    = function() return 0, 0, 0, 1 end,
        Colors   = function() return {} end,
        Metrics  = function()
            local out = {}
            for key, value in pairs(metrics) do out[key] = value end
            return out
        end,
        Backdrop = function() return true end,
        Outline  = function() return true end,
        Text     = function() return true end,
    }
end

local core = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", core)
local METRICS = {}
for key, value in pairs(core.Skin.Metrics) do METRICS[key] = value end

--- A press of Escape the way the game itself carries it out.
--
-- The game walks UISpecialFrames from the end and hides every shown frame.
-- Hence the order of closing: the last entered closes first.
-- @return table the names in the order of closing
local function pressEscape()
    local list = _G.UISpecialFrames
    local closed = {}
    if type(list) ~= "table" then return closed end

    for i = #list, 1, -1 do
        local frame = _G[list[i]]
        if type(frame) == "table" and frame:IsShown() then
            frame:Hide()
            closed[#closed + 1] = list[i]
        end
    end
    return closed
end

--- How many times a name occurs in the Escape list.
-- @param name string
-- @return number
local function timesListed(name)
    local list = _G.UISpecialFrames
    if type(list) ~= "table" then return 0 end

    local seen = 0
    for i = 1, #list do
        if list[i] == name then seen = seen + 1 end
    end
    return seen
end

--- A module's descriptor, faked exactly as far as the windows call it.
-- @return table
local function fakeModule()
    local store, profile = {}, {}
    return {
        GetSettings = function(_, scope)
            if scope == "global" then return store end
            return profile
        end,
        Apply = function() end,
        Localize = function(_, key) return key end,
    }
end

-- The game's state, faked for the duration of the whole file.
local saved = {
    CreateFrame = _G.CreateFrame,
    Darken = _G.Darken,
    UISpecialFrames = _G.UISpecialFrames,
    time = _G.time,
    NumberFontNormal = _G.NumberFontNormal,
}

-- A font object with digits of one width. In the game FrameXML creates it;
-- here it is enough that it exists and is distinguishable from the others.
local DIGIT_FONT = {}

local function installGame()
    _G.CreateFrame = fakeEngine()
    _G.UISpecialFrames = {}
    _G.NumberFontNormal = DIGIT_FONT
    _G.Darken = {
        GetCasefold = function() return coreCasefold end,
        GetSkin     = function() return fakeSkin(METRICS) end,
    }
end

local function restoreGame()
    forgetFrames()
    _G.CreateFrame = saved.CreateFrame
    _G.Darken = saved.Darken
    _G.UISpecialFrames = saved.UISpecialFrames
    _G.time = saved.time
    _G.NumberFontNormal = saved.NumberFontNormal
end
T.suite("closing the windows: a panel cell's menu goes away on Escape too")

do
    installGame()

    local panel = helpers.loadModule("Features/InfoPanel", nil,
        { withRegistration = false })
    panel.Localize = function(key) return key or "" end

    local picked = nil
    panel.Panel.Menu({ { label = "one" }, { label = "two" } }, nil, "fps",
        fakeSkin(METRICS), nil, function(entry) picked = entry end)

    T.eq(timesListed("DarkenInfoPanelMenuFrame"), 1,
        "the menu's name was entered into the Escape list")
    T.eq(panel.Panel.menu:IsShown(), true, "the menu is open")
    T.eq(panel.Panel.catcher:IsShown(), true, "and so is the click catcher beneath it")

    local closed = pressEscape()
    T.eq(#closed, 1, "Escape closed the menu")
    T.eq(panel.Panel.menu:IsShown(), false, "the menu is closed")
    -- The most important thing here. Escape hides only what lies in the list,
    -- and the full-screen catcher does not lie in it. Left shown, it would
    -- eat every click of the player's — an interface that has stopped
    -- answering the mouse, and not one error in the chat.
    T.eq(panel.Panel.catcher:IsShown(), false, "the catcher went away along with the menu")
    T.eq(panel.Panel.menuOf, nil, "and the menu is nobody's any more")
    T.eq(picked, nil, "the closing chose nothing")

    panel.Panel.Dismissable(false)
    T.eq(timesListed("DarkenInfoPanelMenuFrame"), 0,
        "the switched-off module took the menu's name away")

    restoreGame()
end