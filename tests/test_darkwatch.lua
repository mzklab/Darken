local helpers = require("helpers")

-- Darkness: what it is subscribed to.
--
-- The author reported that the darkening "resets" after logging out and in.
-- The value was not lost: his saved variables held amount = 91, and a full
-- out-of-game load of the addon read it back. What was lost was the
--
-- application. The settings are laid down once at login, while
-- PLAYER_ENTERING_WORLD arrives after that and redraws the interface over
-- us. From the chair it looks exactly like a reset setting: the slider is in
--
-- So what is checked here is not the colour but the subscription itself: a
-- subsystem that tints foreign windows must hear the moment those windows
-- were redrawn.

T.suite("darkness: event subscriptions")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)

local Darkness = ns.Darkness

-- A fake event receiver instead of the core: what is needed is the list of
-- what was subscribed to, not delivery.
local subscribed = {}
ns.Events = {
    Subscribe = function(event, owner, handler)
        subscribed[event] = { owner = owner, handler = handler }
    end,
}

Darkness.Watch()

T.ok(subscribed["ADDON_LOADED"] ~= nil,
     "a subscription to interface parts loading later")
T.ok(subscribed["PLAYER_ENTERING_WORLD"] ~= nil,
     "a subscription to entering the world: after it the interface is redrawn")

T.eq(subscribed["PLAYER_ENTERING_WORLD"].owner, Darkness.name,
     "the subscription belongs to the module, otherwise the registry cannot remove it")
T.eq(type(subscribed["PLAYER_ENTERING_WORLD"].handler), "function",
     "the handler was passed")

-- The handler must call the scan anew, not merely a repaint: behind the
-- loading screen the set of windows is different.
local scheduled
local realSchedule = Darkness.Schedule
Darkness.Schedule = function(rediscover) scheduled = rediscover end
subscribed["PLAYER_ENTERING_WORLD"].handler()
Darkness.Schedule = realSchedule

T.eq(scheduled, true, "entering the world starts a scan, not just an application")

T.suite("darkness: an unchanged window is not walked again")

-- Walking a window costs one object call per node, while the plan already
-- knows its textures: a second walk adds exactly nothing.
do
    T.eq(Darkness.WindowChanged(nil, 1, 3, 4), true,
        "a window never seen does need walking")
    T.eq(Darkness.WindowChanged({ generation = 1, children = 3, regions = 4 },
        1, 3, 4), false, "an unchanged one does not")
    T.eq(Darkness.WindowChanged({ generation = 1, children = 3, regions = 4 },
        2, 3, 4), true, "after a new scan it does")
    T.eq(Darkness.WindowChanged({ generation = 1, children = 3, regions = 4 },
        1, 4, 4), true, "a child was added -- it does")
    T.eq(Darkness.WindowChanged({ generation = 1, children = 3, regions = 4 },
        1, 3, 5), true, "a texture was added -- it does too")
end

T.suite("darkness: a window is revisited later")

-- The game calls ShowUIPanel BEFORE it fills the window: reputation rows,
-- statistics sections, character window headers are frame pools, and they
-- are created after the show, sometimes after the server answers. A walk in
-- the same frame does not see them: they do not exist yet. The author sent
-- golden plates from four different windows, none of which reached the scan.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }

    -- A fake clock: it collects the deferred work without running it.
    local waits = {}
    local savedTimer, savedShow, savedHook = _G.C_Timer, _G.ShowUIPanel,
        _G.hooksecurefunc
    _G.C_Timer = { After = function(delay, run)
        waits[#waits + 1] = { delay = delay, run = run }
    end }

    local hooks = {}
    _G.ShowUIPanel = function() end
    _G.hooksecurefunc = function(name, handler) hooks[name] = handler end

    Late.Watch()
    T.ok(hooks["ShowUIPanel"] ~= nil, "the watcher on window shows was not installed")

    -- A window that is empty when shown and filled afterwards.
    local regions = {}
    local window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "ReputationFrame" end,
        GetRegions = function() return unpack(regions) end,
        GetChildren = function() return end,
    }

    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    hooks["ShowUIPanel"](window)

    -- There is one revisit, and that is a decision: every revisit costs a
    -- full walk of the window, and four walks of the talent window per open
    -- read to the player as the game freezing. Everything arriving later is
    -- caught by events and by the repaint watcher.
    T.eq(#waits, 2, "the number of deferred revisits is not two but " .. #waits)
    T.ok(waits[1].delay > 0, "the revisit was scheduled for the same frame")
    T.ok(waits[2].delay > waits[1].delay, "the second revisit is not later than the first")

    -- The game filled the window: the header appeared after the show.
    local header = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function()
            return "Interface" .. string.char(92) .. string.char(92)
                .. "Buttons" .. string.char(92) .. string.char(92)
                .. "UI-Panel-Button-Up"
        end,
    }
    function header:GetVertexColor() return self.r, self.g, self.b, self.a end
    function header:SetVertexColor(cr, cg, cb)
        self.r, self.g, self.b = cr, cg, cb
    end
    regions[1] = header

    -- The count of direct children and regions of the window did NOT change:
    -- the game puts list rows deeper, inside the scroll. The revisit must go
    -- into the window anyway -- otherwise "the window did not change" would
    -- mean "nothing appeared inside it", which is untrue.
    waits[1].run()
    T.ok(header.r < 1, "the late header stayed light")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.ShowUIPanel, _G.hooksecurefunc =
        savedTimer, savedShow, savedHook
end

T.suite("darkness: a window filled on a server reply")

-- Some lists wait for the server: reputations, skills, statistics. The reply
-- arrives when it arrives, and new rows appear in an already open window.
-- The walk of that window happened long before.
do
    T.ok(subscribed["UPDATE_FACTION"] ~= nil,
        "there is no subscription to reputation updates")
    T.ok(subscribed["SKILL_LINES_CHANGED"] ~= nil,
        "there is no subscription to skill updates")

    local seen = nil
    local savedApply = Darkness.ApplyToWindow
    Darkness.ApplyToWindow = function(frame, force)
        seen = { frame = frame, force = force }
        return 0
    end

    local window = { GetObjectType = function() return "Frame" end }
    Darkness.lastWindow = window
    subscribed["UPDATE_FACTION"].handler()

    T.ok(seen ~= nil and seen.frame == window,
        "the walk did not go into the last opened window")
    T.eq(seen and seen.force, true,
        "and it went by the child count even though the window filled up inside")

    Darkness.ApplyToWindow = savedApply
    Darkness.lastWindow = nil
end

T.suite("darkness: what was touched is repainted, not the whole plan")

-- Answering a foreign repaint by repainting the whole plan is not allowed:
-- the plan holds fifteen hundred textures, the game touches a dozen, and its
-- occasions are opening a window, scrolling, any animation. Repainting the
-- plan on every occasion was the very hitch the author noticed at once.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    local savedTimer, savedHook, savedShow, savedCreate =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel, _G.CreateFrame
    _G.C_Timer = { After = function() end }
    _G.ShowUIPanel = function() end

    local methods = {
        SetVertexColor = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
    }
    local installed = {}
    _G.hooksecurefunc = function(object, method, handler)
        if object == methods then installed[method] = handler end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    local function art()
        local region = {
            r = 1, g = 1, b = 1, a = 1, writes = 0,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function()
                return "Interface" .. string.char(92) .. string.char(92)
                    .. "DialogFrame" .. string.char(92) .. string.char(92)
                    .. "UI-DialogBox-Background"
            end,
        }
        function region:GetVertexColor() return self.r, self.g, self.b, self.a end
        function region:SetVertexColor(cr, cg, cb)
            self.r, self.g, self.b = cr, cg, cb
            self.writes = self.writes + 1
        end
        return region
    end

    local touched, quiet = art(), art()
    local window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "MerchantFrame" end,
        GetRegions = function() return touched, quiet end,
        GetChildren = function() return end,
    }

    Late.ApplyToWindow(window)
    local ours = touched.r
    quiet.writes = 0

    -- The game repainted one of the two.
    touched.r, touched.g, touched.b = 1, 1, 1
    installed["SetVertexColor"](touched)

    T.eq(Late.Repaint(), 1, "the number of restored textures is not one")
    T.ok(math.abs(touched.r - ours) < 1e-9, "the touched one did not get its colour back")
    T.eq(quiet.writes, 0, "the untouched one was repainted along with it")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end

T.suite("darkness: a foreign repaint is answered by ours")

-- The game takes list rows from a pool and on every handout assigns them a
-- colour and a texture anew -- over ours. The texture is the same one, it is
-- in the plan, and no walk of ours over the window will fix anything: the
-- scan has nothing to add.
--
-- So the watcher hangs not on the textures but on the shared method table:
-- one hooksecurefunc hears every texture of the interface, including one
-- that does not exist yet.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"

    local waits = {}
    local savedTimer, savedHook, savedShow, savedCreate =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel, _G.CreateFrame
    _G.C_Timer = { After = function(delay, run) waits[#waits + 1] = run end }
    _G.ShowUIPanel = function() end

    -- The shared method table: the fake is built the way a game widget is
    -- built -- the methods live not on the object but on its type table.
    local methods = {
        SetVertexColor = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
    }

    local installed = {}
    _G.hooksecurefunc = function(object, method, handler)
        if object == methods then installed[method] = handler end
    end

    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    T.ok(installed["SetVertexColor"] ~= nil,
        "nobody watches a texture repaint")
    T.ok(installed["SetAtlas"] ~= nil, "nobody watches an atlas handout")
    T.ok(installed["SetTexture"] ~= nil, "nobody watches a texture handout")

    local header = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function()
            return "Interface" .. string.char(92) .. string.char(92)
                .. "Buttons" .. string.char(92) .. string.char(92)
                .. "UI-Panel-Button-Up"
        end,
    }
    function header:GetVertexColor() return self.r, self.g, self.b, self.a end
    function header:SetVertexColor(cr, cg, cb)
        self.r, self.g, self.b = cr, cg, cb
    end

    local window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "SkillFrame" end,
        GetRegions = function() return header end,
        GetChildren = function() return end,
    }

    local savedRoot = _G.UIParent
    _G.UIParent = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "UIParent" end,
        GetRegions = function() return end,
        GetChildren = function() return window end,
    }

    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    Late.ApplyToWindow(window)
    local ours = header.r
    T.ok(ours < 1, "the header is not darkened at all")

    -- Our own write orders nothing: otherwise it would answer itself.
    T.eq(#waits, 0, "our own write ordered a repaint")

    -- The game handed out the row again: its own colour.
    header.r, header.g, header.b = 1, 1, 1
    installed["SetVertexColor"](header)
    T.eq(#waits, 1, "the foreign repaint went unnoticed")

    waits[1]()
    T.ok(math.abs(header.r - ours) < 1e-9,
        "our colour did not come back: " .. tostring(header.r))

    fresh.Addon, fresh.flavor = nil, nil
    _G.UIParent = savedRoot
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end

T.suite("darkness: a window that gave everything up is not walked twice")

-- A revisit costs a full walk of the window: it does not ask "did it
-- change", otherwise it would not find rows created deeper. For the talent
-- window that is tens of thousands of calls, and there is no reason to pay
-- them on every open -- the author noticed at once: "the game stops dead
-- when I press to open the window".
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    local waits = {}
    local savedTimer, savedHook, savedShow =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel
    _G.C_Timer = { After = function(delay, run)
        waits[#waits + 1] = run
    end }

    local hooks = {}
    _G.ShowUIPanel = function() end
    _G.hooksecurefunc = function(name, handler)
        if type(name) == "string" then hooks[name] = handler end
    end

    Late.Watch()

    local art = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function()
            return "Interface" .. string.char(92) .. string.char(92)
                .. "DialogFrame" .. string.char(92) .. string.char(92)
                .. "UI-DialogBox-Background"
        end,
    }
    function art:GetVertexColor() return self.r, self.g, self.b, self.a end
    function art:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    local window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "MerchantFrame" end,
        GetRegions = function() return art end,
        GetChildren = function() return end,
    }

    -- First open: a walk on the show and a revisit after it.
    hooks["ShowUIPanel"](window)
    T.eq(#waits, 2, "the revisits were not deferred")
    waits[1]()
    waits[2]()

    -- The revisit found nothing new -- a second open does not order one.
    waits = {}
    hooks["ShowUIPanel"](window)
    T.eq(#waits, 0, "a revisit was ordered a second time for the same window")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel =
        savedTimer, savedHook, savedShow
end

T.suite("darkness: showing the window itself is a reason to walk it again")

-- The game calls ShowUIPanel BEFORE the show, and at that moment half the
-- window does not exist: it creates the tab, the list, the panel in its own
-- show handler, that is after us. A revisit half a second later catches up,
-- but the player has time to see the native look and its switch to ours:
-- "I see a flicker from the default into our repaint".
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    local savedHook, savedTimer = _G.hooksecurefunc, _G.C_Timer
    _G.C_Timer = { After = function() end }

    local hooks = {}
    _G.hooksecurefunc = function(object, method, handler)
        if type(object) == "table" then
            hooks[object] = hooks[object] or {}
            hooks[object][method] = handler
        end
    end

    local function art()
        local region = {
            r = 1, g = 1, b = 1, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function()
                return "Interface" .. string.char(92) .. string.char(92)
                    .. "DialogFrame" .. string.char(92) .. string.char(92)
                    .. "UI-DialogBox-Border"
            end,
        }
        function region:GetVertexColor() return self.r, self.g, self.b, self.a end
        function region:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end
        return region
    end

    -- A window whose contents appear only on the show.
    local late = art()
    local inner = nil
    local window
    window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "ProfessionsFrame" end,
        GetRegions = function() return end,
        GetChildren = function()
            if inner == nil then return end
            return inner
        end,
        IsShown = function() return true end,
        Show = function(self)
            inner = {
                GetObjectType = function() return "Frame" end,
                GetName = function() return "ProfessionsFrameInner" end,
                GetRegions = function() return late end,
                GetChildren = function() return end,
                IsShown = function() return true end,
            }
            local watch = hooks[self] and hooks[self]["Show"]
            if watch then watch(self) end
        end,
    }

    Late.ApplyToWindow(window)
    T.ok(hooks[window] and hooks[window]["Show"] ~= nil,
        "nobody watches the window show")

    window:Show()
    T.ok(late.r < 1, "what was created on the show stayed light")

    fresh.Addon, fresh.flavor = nil, nil
    _G.hooksecurefunc, _G.C_Timer = savedHook, savedTimer
end

T.suite("darkness: a texture created by the game is tinted at once")

-- This is the answer to the author's question: "why can we not tint the
-- textures right away instead of walking and knowing what to tint?".
--
-- We can -- and we do. A texture announces its own appearance (the shared
-- method table), and its owner remembers its area (FRAME_AREA). There is
-- nothing to walk: no tree, no lists, no waiting.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    local savedTimer, savedHook, savedShow, savedCreate =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel, _G.CreateFrame
    _G.C_Timer = { After = function() end }
    _G.ShowUIPanel = function() end

    local methods = {
        SetVertexColor = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
    }
    local installed = {}
    _G.hooksecurefunc = function(object, method, handler)
        if object == methods then installed[method] = handler end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    local window
    window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "MerchantFrame" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
    }

    -- The walk went over an empty window: there are no textures in it yet.
    Late.ApplyToWindow(window)

    -- The game created a texture in that window and assigned it an atlas.
    local born = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetParent = function() return window end,
        GetTexture = function()
            return "Interface" .. string.char(92) .. string.char(92)
                .. "DialogFrame" .. string.char(92) .. string.char(92)
                .. "UI-DialogBox-Background"
        end,
    }
    function born:GetVertexColor() return self.r, self.g, self.b, self.a end
    function born:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    installed["SetAtlas"](born)

    T.ok(born.r < 1, "the newly created texture stayed light")

    -- A foreign window the walk never visited is not touched: we know
    -- nothing about its area.
    local stranger = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "SomeAddonFrame" end,
    }
    local outside = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetParent = function() return stranger end,
        GetTexture = function()
            return "Interface" .. string.char(92) .. string.char(92)
                .. "DialogFrame" .. string.char(92) .. string.char(92)
                .. "UI-DialogBox-Background"
        end,
    }
    function outside:GetVertexColor() return self.r, self.g, self.b, self.a end
    function outside:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    installed["SetAtlas"](outside)
    T.eq(outside.r, 1, "a texture of a window the walk never saw was touched")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end

T.suite("darkness: a button created by the game is tinted at once too")

-- The game does not take buff icons from the pool one at a time: it takes a
-- whole button, and the walk saw neither the button nor its texture. Higher
-- in the tree, though, stands what it did see -- the buff grid itself -- and
-- its area is the same. The author saw it as "the auras flicker, default and so on".
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    local savedTimer, savedHook, savedShow, savedCreate =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel, _G.CreateFrame
    _G.C_Timer = { After = function() end }
    _G.ShowUIPanel = function() end

    local methods = {
        SetVertexColor = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
    }
    local installed = {}
    _G.hooksecurefunc = function(object, method, handler)
        if object == methods then installed[method] = handler end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    local grid = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "MerchantFrame" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
    }

    Late.ApplyToWindow(grid)

    -- The game handed out a whole button from the pool with its own texture.
    local button = {
        GetObjectType = function() return "Frame" end,
        GetParent = function() return grid end,
    }
    local icon = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetParent = function() return button end,
        GetTexture = function()
            return "Interface" .. string.char(92) .. string.char(92)
                .. "DialogFrame" .. string.char(92) .. string.char(92)
                .. "UI-DialogBox-Background"
        end,
    }
    function icon:GetVertexColor() return self.r, self.g, self.b, self.a end
    function icon:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    installed["SetTexture"](icon)
    T.ok(icon.r < 1, "the texture of the new button stayed light")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end

T.suite("darkness: an adopted texture also asks its owner")

-- An item icon in a bag slot lies in the "icon" field of its button, and the
-- texture itself has neither a name nor a special path -- just a file id, the
-- same way the trim is named in this client. The walk asks the frame about
-- it; texture adoption did not -- and the bag slots turned black.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    local savedTimer, savedHook, savedShow, savedCreate =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel, _G.CreateFrame
    _G.C_Timer = { After = function() end }
    _G.ShowUIPanel = function() end

    local methods = {
        SetVertexColor = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
    }
    local installed = {}
    _G.hooksecurefunc = function(object, method, handler)
        if object == methods then installed[method] = handler end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    local window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "ContainerFrame1" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
    }
    Late.ApplyToWindow(window)

    local slot = {
        GetObjectType = function() return "Frame" end,
        GetParent = function() return window end,
    }

    local function art()
        local region = {
            r = 1, g = 1, b = 1, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetParent = function() return slot end,
            GetTexture = function() return 134400 end,
        }
        function region:GetVertexColor() return self.r, self.g, self.b, self.a end
        function region:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end
        return region
    end

    local icon, backdrop = art(), art()
    slot.icon = icon

    installed["SetTexture"](icon)
    T.eq(icon.r, 1, "the item icon is darkened")

    installed["SetTexture"](backdrop)
    T.ok(backdrop.r < 1, "while the slot backdrop stayed light")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end

T.suite("darkness: the rule's answer is forgotten when the game changes the texture")

-- The answer memory is valid exactly as long as the texture stays itself.
-- The game, however, hands out list rows from a pool and assigns them a
-- texture anew -- and an answer given when there was no texture yet is a lie
-- from that moment on. A row once recognised as a reading stayed untouched
-- forever: the author sent four windows where nothing was tinted any more.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    local savedTimer, savedHook, savedShow, savedCreate =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel, _G.CreateFrame
    _G.C_Timer = { After = function() end }
    _G.ShowUIPanel = function() end

    local methods = {
        SetVertexColor = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
    }
    local installed = {}
    _G.hooksecurefunc = function(object, method, handler)
        if object == methods then installed[method] = handler end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    -- A list row handed out from the pool empty: it has no texture yet.
    local image = nil
    local window
    local header = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function() return image end,
        GetAtlas = function() return nil end,
        GetName = function() return nil end,
        GetParent = function() return window end,
    }
    function header:GetVertexColor() return self.r, self.g, self.b, self.a end
    function header:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    -- An empty texture is coloured: the rule counts it as a reading.
    header.r, header.g, header.b = 0.1, 0.4, 0.8

    window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "ReputationFrame" end,
        GetRegions = function() return header end,
        GetChildren = function() return end,
    }

    Late.ApplyToWindow(window)
    T.ok(math.abs(header.r - 0.1) < 1e-9,
        "a coloured fill was darkened for some reason")

    -- The game gave the row its real texture -- a section header.
    image = "Interface" .. string.char(92) .. string.char(92)
        .. "Buttons" .. string.char(92) .. string.char(92)
        .. "UI-Panel-Button-Up"
    header.r, header.g, header.b = 1, 1, 1
    installed["SetTexture"](header)

    T.ok(header.r < 1,
        "the old answer outlived the texture change: the row stayed light")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end

T.suite("darkness: something hidden that got shown is walked in that instant")

-- The game hands out a list row from the pool, assigns it a texture ONCE at
-- creation and afterwards only shows and hides it. The scan skips it
-- (hidden), the texture watcher stays silent (the texture is not assigned
-- again), and there will not be a single reason to walk the window anew.
--
-- The author's own scan showed it in numbers: for a section header the
-- selection rule says "tint" while there is no written colour at all.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    local savedHook, savedTimer = _G.hooksecurefunc, _G.C_Timer
    _G.C_Timer = { After = function() end }

    local hooks = {}
    _G.hooksecurefunc = function(object, method, handler)
        if type(object) == "table" then
            hooks[object] = hooks[object] or {}
            hooks[object][method] = handler
        end
    end

    local plate = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function()
            return "Interface" .. string.char(92) .. string.char(92)
                .. "DialogFrame" .. string.char(92) .. string.char(92)
                .. "UI-DialogBox-Border"
        end,
    }
    function plate:GetVertexColor() return self.r, self.g, self.b, self.a end
    function plate:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    local shown = false
    local row
    row = {
        GetObjectType = function() return "Frame" end,
        GetRegions = function() return plate end,
        GetChildren = function() return end,
        IsShown = function() return shown end,
        Show = function(self)
            shown = true
            local watch = hooks[self] and hooks[self]["Show"]
            if watch then watch(self) end
        end,
        SetShown = function(self, on)
            shown = on and true or false
            local watch = hooks[self] and hooks[self]["SetShown"]
            if watch then watch(self, on) end
        end,
    }

    local window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "ReputationFrame" end,
        GetRegions = function() return end,
        GetChildren = function() return row end,
        IsShown = function() return true end,
    }

    Late.ApplyToWindow(window)
    T.eq(plate.r, 1, "a hidden row was tinted for some reason")
    T.ok(hooks[row] and hooks[row]["Show"] ~= nil,
        "nobody watches a hidden row being shown")

    -- The game showed the row: it assigned no textures and reopened no
    -- window.
    row:Show()
    T.ok(plate.r < 1, "the shown row stayed light")

    -- The second way to show is SetShown(true), and it does not call Show:
    -- the new list interface uses exactly that.
    T.ok(hooks[row]["SetShown"] ~= nil, "nobody watches SetShown")

    -- A shown row also gives the walk what appeared in it later.
    local badge = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function()
            return "Interface" .. string.char(92) .. string.char(92)
                .. "DialogFrame" .. string.char(92) .. string.char(92)
                .. "UI-DialogBox-Border"
        end,
    }
    function badge:GetVertexColor() return self.r, self.g, self.b, self.a end
    function badge:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    row.GetRegions = function() return plate, badge end

    local watch = hooks[row]["SetShown"]
    watch(row, false)
    T.eq(badge.r, 1, "it was hidden -- yet the walk went in anyway")

    watch(row, true)
    T.ok(badge.r < 1, "shown via SetShown -- the new part stayed light")

    fresh.Addon, fresh.flavor = nil, nil
    _G.hooksecurefunc, _G.C_Timer = savedHook, savedTimer
end

T.suite("darkness: a map tile is not adopted")

-- Darkening does not touch the map canvas at all: the map is a picture of
-- the world, it is read, and the markers on it are told apart by colour.
--
-- The walk knew this: the canvas is in the taken set, and the pass turns
-- back at the threshold. Texture adoption, however, took another road -- up
-- the tree for the nearest known area -- and never asked the set. The
-- terrain tiles are placed by the game itself, each announces itself to the
-- watcher, the climb went through the scroll to the map window, the window
-- has an area -- and the terrain went grey. The author sent a screenshot:
-- "you broke the map, it is grey for some reason when it should be colour".
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 80, desaturate = true, mode = {} } } } }

    local savedTimer, savedHook, savedShow, savedCreate =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel, _G.CreateFrame
    _G.C_Timer = { After = function() end }
    _G.ShowUIPanel = function() end

    local methods = {
        SetVertexColor = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
    }
    local installed = {}
    _G.hooksecurefunc = function(object, method, handler)
        if object == methods then installed[method] = handler end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    -- The map canvas: the compatibility layer knows it, and darkening skips it.
    local canvas = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "WorldMapDetailFrame" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
    }
    local savedCanvas = _G.WorldMapDetailFrame
    _G.WorldMapDetailFrame = canvas

    -- The map window: the walk went over it, and it has an area.
    local map
    map = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "WorldMapFrame" end,
        GetRegions = function() return end,
        GetChildren = function() return canvas end,
    }
    canvas.GetParent = function() return map end

    Late.ApplyToWindow(map)

    -- The game placed a terrain tile on the canvas.
    local tile = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetParent = function() return canvas end,
        GetTexture = function()
            return "Interface" .. string.char(92) .. string.char(92)
                .. "WorldMap" .. string.char(92) .. string.char(92)
                .. "Tirisfal" .. string.char(92) .. string.char(92)
                .. "Tirisfal1"
        end,
    }
    function tile:GetVertexColor() return self.r, self.g, self.b, self.a end
    function tile:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    installed["SetTexture"](tile)

    T.eq(tile.r, 1, "the terrain stayed in colour")
    T.eq(tile.g, 1, "and green rather than grey")

    _G.WorldMapDetailFrame = savedCanvas
    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end

T.suite("darkness: the repainting is counted where it lands")

-- "Repaints Heard" was one number for everything, and one number cannot be
-- acted on: the watcher sits on the shared method table of textures, so it
-- hears Blizzard's own animations and other addons too. The author's session
-- showed a hundred and thirty-six thousand of them, which says nothing about
-- us until it is split - how many landed on a picture WE had painted, and in
-- which window.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    local store = {}
    fresh.Addon = { db = {
        profile = { darkness = { amount = 64, mode = {} } },
        global = { darkness = store },
    } }

    local savedTimer, savedHook, savedShow, savedCreate =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel, _G.CreateFrame
    _G.C_Timer = { After = function() end }
    _G.ShowUIPanel = function() end

    local methods = {
        SetVertexColor = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
    }
    local installed = {}
    _G.hooksecurefunc = function(object, method, handler)
        if object == methods then installed[method] = handler end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    local function art()
        local region = {
            r = 1, g = 1, b = 1, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function()
                return "Interface" .. string.char(92) .. string.char(92)
                    .. "DialogFrame" .. string.char(92) .. string.char(92)
                    .. "UI-DialogBox-Background"
            end,
        }
        function region:GetVertexColor() return self.r, self.g, self.b, self.a end
        function region:SetVertexColor(cr, cg, cb)
            self.r, self.g, self.b = cr, cg, cb
        end
        return region
    end

    local ours, stranger = art(), art()
    Late.ApplyToWindow({
        GetObjectType = function() return "Frame" end,
        GetName = function() return "MerchantFrame" end,
        GetRegions = function() return ours end,
        GetChildren = function() return end,
    })

    -- The game writes three times to a picture of ours and once to a picture
    -- that was never in the plan.
    installed["SetVertexColor"](ours)
    installed["SetVertexColor"](ours)
    installed["SetVertexColor"](ours)
    installed["SetVertexColor"](stranger)
    Late.Repaint()

    T.eq(store.churn.heard, 4, "every write the watcher heard is in the total")
    T.eq(store.churn.ours, 3,
        "and only the ones that landed on our own picture in the split")
    T.eq(store.churn.by["MerchantFrame"], 3,
        "named by the window they landed in")
    T.eq(store.churn.by["(no window)"], nil,
        "and a picture nobody painted is in no window's count")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end

T.suite("darkness: a frame we do not enter turns the climb back")

-- The minimap's pins, measured: 68382 writes heard in one short session and
-- only 2162 of them on a picture of ours. The other sixty-six thousand went
-- into the adoption path - the game writes to a picture that is not in the
-- plan, and we climb the tree looking for the area it belongs to.
--
-- The minimap is a type we skip whole, so the answer is always "nothing".
-- The walk knew that and turned back without saying so, and the climb, which
-- takes another road, asked afresh on every write: six protected calls, per
-- pin, per frame, while the player walks.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Late = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    local store = {}
    fresh.Addon = { db = {
        profile = { darkness = { amount = 64, mode = {} } },
        global = { darkness = store },
    } }

    local savedTimer, savedHook, savedShow, savedCreate =
        _G.C_Timer, _G.hooksecurefunc, _G.ShowUIPanel, _G.CreateFrame
    _G.C_Timer = { After = function() end }
    _G.ShowUIPanel = function() end

    local methods = {
        SetVertexColor = function() end,
        SetAtlas = function() end,
        SetTexture = function() end,
    }
    local installed = {}
    _G.hooksecurefunc = function(object, method, handler)
        if object == methods then installed[method] = handler end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    -- A pin of another addon's, on a minimap, inside a window the walk does
    -- enter. Every GetParent is counted: that is what the climb costs.
    local climbs = 0

    local pin = { r = 1, g = 1, b = 1, a = 1 }
    local pinFrame

    pin.GetObjectType = function() return "Texture" end
    pin.GetDrawLayer = function() return "OVERLAY" end
    pin.GetTexture = function() return 12345 end
    function pin:GetVertexColor() return self.r, self.g, self.b, self.a end
    function pin:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end
    pin.GetParent = function() climbs = climbs + 1 return pinFrame end

    pinFrame = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "QuestiePin1" end,
        GetRegions = function() return pin end,
        GetChildren = function() return end,
    }

    local map = {
        GetObjectType = function() return "Minimap" end,
        GetName = function() return "Minimap" end,
        GetRegions = function() return end,
        GetChildren = function() return pinFrame end,
    }
    pinFrame.GetParent = function() climbs = climbs + 1 return map end
    map.GetParent = function() climbs = climbs + 1 return nil end

    -- The walk meets the minimap and goes no further into it.
    Late.ApplyToWindow(map)
    T.eq(pin.r, 1, "the pin was not painted by the walk")

    -- Now the game writes to the pin, twice, as it does while walking.
    climbs = 0
    installed["SetVertexColor"](pin)
    local afterFirst = climbs
    installed["SetVertexColor"](pin)

    -- The first write still walks up as far as the minimap, which is one
    -- step: that is the climb doing its job, not the defect.
    T.ok(afterFirst <= 3,
        "the first write turns back at the minimap: " .. afterFirst)

    -- The second is the whole point: it asks the picture who owns it, reads
    -- the remembered "nothing here" and stops. One call to the game instead
    -- of the climb, and the climb was what the minimap could not afford.
    T.eq(climbs, afterFirst + 1,
        "the second write costs one question and no climb")
    T.eq(pin.r, 1, "the pin is still not ours to paint")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end
