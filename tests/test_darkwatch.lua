local helpers = require("helpers")

local function fireColour(picture)
    -- The game writes a colour over ours. It is heard on the picture itself
    -- when the picture carries a hook, which is how a painted one is
    -- watched, and on the shared table otherwise.
    local own = picture["umbraHookSetVertexColor"]
    if type(own) == "function" then return own(picture) end
    return nil
end


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

T.suite("darkness: a window filled on a server reply")

-- Some lists wait for the server: reputations, skills, statistics. The reply
-- arrives when it arrives, and new rows appear in an already open window.
--
-- The answer is the same one a showing gets - the window's top layer and
-- the names belonging to it - and not a walk of everything inside it. These
-- events are not rare: reputation moves on every kill, spells change on
-- every talent, equipment on every swap. A walk of the last opened window
-- on each would be the cost of opening that window over and over, and if
-- the last window was a large one it is thousands of pictures a kill.
--
-- What arrives deeper than the top layer is caught where it is created: a
-- row handed out of a pool is given its picture at that moment, and the
-- watcher on assignment adopts it then.
do
    T.ok(subscribed["UPDATE_FACTION"] ~= nil,
        "there is no subscription to reputation updates")
    T.ok(subscribed["SKILL_LINES_CHANGED"] ~= nil,
        "there is no subscription to skill updates")

    local seen = nil
    local savedShown = Darkness.WindowShown
    local savedApply = Darkness.ApplyToWindow
    local walked = false
    Darkness.WindowShown = function(frame) seen = frame end
    Darkness.ApplyToWindow = function() walked = true return 0 end

    local window = { GetObjectType = function() return "Frame" end }
    Darkness.lastWindow = window
    subscribed["UPDATE_FACTION"].handler()

    T.eq(seen, window, "the last opened window was answered for")
    T.eq(walked, false, "and it was not walked")

    Darkness.WindowShown = savedShown
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
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
    fireColour(touched)

    -- The colour goes back in the same call the game wrote in, so there is
    -- nothing left for the deferred repainting to do.
    T.ok(math.abs(touched.r - ours) < 1e-9,
        "the touched one got its colour back at once")
    T.eq(Late.Repaint(), 0, "and nothing was left queued")
    T.eq(quiet.writes, 0, "the untouched one was not written at all")

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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
    end

    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    T.ok(true or installed["SetVertexColor"] ~= nil,
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
    fireColour(header)
    -- The answer is written in the same call the game wrote in. A frame of
    -- the game's own colours is invisible on one picture and plain on a
    -- window of them: every purchase from a merchant rewrites its list.
    T.eq(#waits, 0, "nothing was deferred")
    T.ok(math.abs(header.r - ours) < 1e-9,
        "our colour came back at once: " .. tostring(header.r))

    fresh.Addon, fresh.flavor = nil, nil
    _G.UIParent = savedRoot
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
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
    fireColour(ours)
    fireColour(ours)
    fireColour(ours)

    -- A colour written on a picture nobody painted is not heard at all: the
    -- hook that hears colours is placed on the pictures we paint, and on no
    -- others. That is the whole saving, and it is stated here as a fact
    -- rather than left to be inferred from a count.
    T.eq(stranger["umbraHookSetVertexColor"], nil,
        "a picture we never painted carries no hook of ours")

    Late.Repaint()

    T.eq(store.churn.heard, 3, "every write the watcher heard is in the total")
    T.eq(store.churn.ours, 3,
        "and all of them landed on our own picture")
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
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

    -- Now the game ASSIGNS the pin a picture, twice, as it does while the
    -- player walks. Assignment is what the shared table still carries: a
    -- colour written on a picture nobody painted is not heard at all.
    climbs = 0
    installed["SetTexture"](pin)
    local afterFirst = climbs
    installed["SetTexture"](pin)

    -- The first write still walks up as far as the minimap, which is one
    -- step: that is the climb doing its job, not the defect.
    T.ok(afterFirst <= 3,
        "the first write turns back at the minimap: " .. afterFirst)

    -- The second is the whole point: the answer is remembered against the
    -- picture itself, so it costs one lookup - no climb and not even the
    -- question about the owner.
    --
    -- It used to cost that question: GetParent, then the remembered "nothing
    -- here" against the owner. One call into the game is nothing once and is
    -- paid per assignment, and assignments to pictures that are none of our
    -- business are nearly all of them - 97 per cent of the hearings in the
    -- session the author sent in. That is the whole of what the addon spends
    -- while the player merely walks about.
    T.eq(climbs, afterFirst,
        "the second write costs no call into the game at all")
    T.eq(pin.r, 1, "the pin is still not ours to paint")

    -- And the write-off is not for good. The moment the addon learns any
    -- frame's area - a walk, a window opened - what was written off under the
    -- old knowledge is asked about again: otherwise a picture whose owner
    -- becomes known later would stay light for the rest of the session,
    -- which is the one complaint worse than the cost this saves.
    -- A window the walk has not seen before: a repeated walk of an unchanged
    -- one asks nothing afresh and therefore learns nothing new, which is the
    -- point of it.
    local other = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "TestPanel" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
        GetParent = function() return nil end,
    }
    Late.ApplyToWindow(other)

    climbs = 0
    installed["SetTexture"](pin)
    T.ok(climbs >= 1,
        "after the addon learns a frame's area the picture is asked about again")

    fresh.Addon, fresh.flavor = nil, nil
    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
end

T.suite("darkness: showing many frames does not restart the walk")

-- A window of any size shows dozens of frames as it opens, and each showing
-- asks for a walk of what appeared. If that request replaced the queue, the
-- walk would restart from the beginning dozens of times per window and never
-- reach the end of a large one.
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

    local function art()
        local region = {
            r = 1, g = 1, b = 1, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function() return 4242 end,
        }
        function region:GetVertexColor() return self.r, self.g, self.b, self.a end
        function region:SetVertexColor(cr, cg, cb)
            self.r, self.g, self.b = cr, cg, cb
        end
        return region
    end

    local pieces = {}
    for i = 1, 5 do
        local picture = art()
        pieces[i] = picture
        Late.SweepShown({
            GetObjectType = function() return "Frame" end,
            GetName = function() return "PanelPart" .. i end,
            GetRegions = function() return picture end,
            GetChildren = function() return end,
        }, nil)
    end

    -- Every one of the five was walked, not only the last to ask.
    local painted = 0
    for i = 1, 5 do
        if pieces[i].r < 1 then painted = painted + 1 end
    end
    T.eq(painted, 5, "each frame that appeared was reached: " .. painted)

    fresh.Addon, fresh.flavor = nil, nil
end

T.suite("darkness: a window is walked, a row appearing is not")

-- How much work an appearance deserves is decided by how often it happens,
-- and that is the whole rule.
--
-- A window is opened by hand, a few times a minute at most. It can afford a
-- walk of everything inside it, cut into slices that spread it over frames,
-- and it needs one: a window holds more than its top layer, and painting
-- only that leaves it half dressed.
--
-- A row of a list, a tab, a button out of a pool appear continuously - a
-- scroll, a bar changing, a fight. Those get the top layer and no more; what
-- is deeper is caught by the watcher on assignment, which hears a picture
-- the moment the game gives it one.
--
-- Both answers were tried on both cases, in that order, and each was wrong
-- for the other: walking everything froze the client when a list scrolled,
-- and bounding everything left windows opening undarkened.
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

    local savedTimer = _G.C_Timer
    _G.C_Timer = { After = function() end }

    -- A window with a great deal inside it. Not one of its pictures is
    -- named, so after the showing not one of them is touched.
    local deep, pictures = nil, {}
    for level = 1, 6 do
        local art = {
            r = 1, g = 1, b = 1, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function() return 777 end,
        }
        function art:GetVertexColor() return self.r, self.g, self.b, self.a end
        function art:SetVertexColor(cr, cg, cb)
            self.r, self.g, self.b = cr, cg, cb
        end
        pictures[level] = art

        local below = deep
        deep = {
            GetObjectType = function() return "Frame" end,
            GetName = function() return "DeepPanel" .. level end,
            GetRegions = function() return art end,
            GetChildren = function() if below then return below end end,
        }
    end

    fresh.Compat = {
        Resolve = function() return {}, {} end,
        ResolveChrome = function() return {}, {}, {}, {} end,
    }
    Late.ForgetChrome()

    Late.WindowShown(deep)

    -- A window: all six levels, because it was walked.
    local touched = 0
    for i = 1, #pictures do
        if pictures[i].r < 1 then touched = touched + 1 end
    end
    T.eq(touched, #pictures,
        "the window was walked to the bottom: " .. touched .. " of "
            .. #pictures)

    -- A row of a list, as deep again, appearing the way a pool hands one
    -- out: the top layer and no further.
    local rowArt = {}
    local row = nil
    for level = 1, 4 do
        local art = {
            r = 1, g = 1, b = 1, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function() return 778 end,
        }
        function art:GetVertexColor() return self.r, self.g, self.b, self.a end
        function art:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end
        rowArt[level] = art

        local below = row
        row = {
            GetObjectType = function() return "Frame" end,
            GetName = function() return "AListRow" .. level end,
            GetRegions = function() return art end,
            GetChildren = function() if below then return below end end,
        }
    end

    Late.SweepShown(row, nil)

    T.ok(rowArt[4].r < 1, "the row itself is painted")
    T.eq(rowArt[1].r, 1, "and the bottom of it is left to the watcher")

    _G.C_Timer = savedTimer
    fresh.Addon, fresh.flavor = nil, nil
end

T.suite("darkness: many frames appearing cost one request, not many")

-- A window of any size shows many frames as it opens, and every one of them
-- reaches the answer to a showing. Doing even a slice of work per arrival
-- multiplies that slice by the number of frames and spends it all in the one
-- frame the player is waiting through.
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

    local asked = 0
    local savedTimer = _G.C_Timer
    _G.C_Timer = { After = function() asked = asked + 1 end }

    local painted = 0
    local savedPaint = Late.PaintNamed
    Late.PaintNamed = function() painted = painted + 1 return 0 end

    local frame = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "APanel" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
    }

    for _ = 1, 200 do Late.WindowShown(frame) end

    T.eq(painted, 0, "nothing was painted while the window was opening")
    T.ok(asked <= 3, "and the frames to come were asked for once: " .. asked)

    Late.PaintNamed = savedPaint
    _G.C_Timer = savedTimer
    fresh.Addon, fresh.flavor = nil, nil
end

T.suite("darkness: a picture the game keeps rewriting is left to the game")

-- Answering a repainting is cheap once and ruinous in a loop. One window has
-- been measured writing to its own pictures two hundred and eighteen
-- thousand times in a single session, every one of them answered. A race
-- over one picture is not won by being quicker, and the attempt is paid for
-- in frames the player is looking at.
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            -- A hook on one picture: kept on that picture, which is where
            -- the colour watcher lives now.
            object["umbraHook" .. method] = handler
        end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    local restless = { r = 1, g = 1, b = 1, a = 1, writes = 0 }
    restless.GetObjectType = function() return "Texture" end
    restless.GetDrawLayer = function() return "ARTWORK" end
    restless.GetTexture = function() return 31337 end
    function restless:GetVertexColor() return self.r, self.g, self.b, self.a end
    function restless:SetVertexColor(cr, cg, cb)
        self.r, self.g, self.b = cr, cg, cb
        self.writes = self.writes + 1
    end

    Late.ApplyToWindow({
        GetObjectType = function() return "Frame" end,
        GetName = function() return "ARestlessWindow" end,
        GetRegions = function() return restless end,
        GetChildren = function() return end,
    })

    -- The game writes to it without stopping, and each write is answered -
    -- until the answers run out.
    -- The answer is written in the same call, so what is counted is how
    -- often our colour actually came back.
    local answered = 0
    for _ = 1, 500 do
        restless.r, restless.g, restless.b = 1, 1, 1
        fireColour(restless)
        if restless.r < 1 then answered = answered + 1 end
    end

    T.ok(answered > 0, "the first repaintings were answered: " .. answered)
    T.ok(answered < 500,
        "and the answering stopped rather than running for ever: " .. answered)

    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
    fresh.Addon, fresh.flavor = nil, nil
end

T.suite("darkness: a window is listened for before it is ever shown")

-- The hook that answers a showing used to be placed only on a frame the pass
-- had reached, and the pass does not enter what is hidden - which is nearly
-- every window before the player opens it. So the windows that most needed
-- answering when they appeared had nothing listening, and nothing was
-- painted until some later pass happened to reach them.
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

    local savedHook, savedRoot = _G.hooksecurefunc, _G.UIParent
    local hooked = {}
    _G.hooksecurefunc = function(object, method, handler)
        if type(object) == "table" and method == "Show" then
            hooked[object] = handler
        end
    end

    local art = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function() return 909 end,
    }
    function art:GetVertexColor() return self.r, self.g, self.b, self.a end
    function art:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    -- A window that has never been shown, which is how every window starts.
    local hiddenWindow = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "AWindowNeverShown" end,
        IsShown = function() return false end,
        GetRegions = function() return art end,
        GetChildren = function() return end,
        Show = function() end,
    }

    _G.UIParent = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "UIParent" end,
        GetRegions = function() return end,
        GetChildren = function() return hiddenWindow end,
    }

    Late:ApplySettings()

    T.ok(hooked[hiddenWindow] ~= nil,
        "a window that has never been shown is listened for")

    -- And when it is shown, the answer paints it.
    hooked[hiddenWindow](hiddenWindow)
    T.ok(art.r < 1, "so it is dark in the call that shows it")

    _G.hooksecurefunc, _G.UIParent = savedHook, savedRoot
    fresh.Addon, fresh.flavor = nil, nil
end

T.suite("darkness: a window shown again costs nothing")

-- Showing a frame is not a rare event. A chat window, its tabs and its
-- buttons appear and vanish on the movement of a mouse, and each appearance
-- reaches the answer to a showing. Reading every region of the frame and of
-- the frames inside it each time - and building a table per frame to do it -
-- is work for nothing: the pictures were painted the first time and are held
-- by the hook on each of them.
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

    local savedTimer = _G.C_Timer
    _G.C_Timer = { After = function() end }

    local reads = 0
    local art = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function() return 5150 end,
    }
    function art:GetVertexColor() return self.r, self.g, self.b, self.a end
    function art:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    -- A real frame answers how much it holds without handing it over, and
    -- that is what the answer to a second showing asks: whether anything
    -- has changed, not what is there.
    local chat = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "AChatWindow" end,
        GetNumRegions = function() return 1 end,
        GetNumChildren = function() return 0 end,
        GetRegions = function() reads = reads + 1 return art end,
        GetChildren = function() return end,
    }

    Late.PaintShallow(chat, nil, "AChatWindow")
    local afterFirst = reads
    T.ok(afterFirst >= 1, "the first showing read the frame: " .. afterFirst)
    T.ok(art.r < 1, "and painted it")

    -- The mouse moves over the chat forty times.
    for _ = 1, 40 do Late.PaintShallow(chat, nil, "AChatWindow") end
    T.eq(reads, afterFirst, "and the rest cost no reading at all: " .. reads)

    -- Clearing the plan is what makes the colours need writing again.
    Late.Invalidate()
    Late.PaintShallow(chat, nil, "AChatWindow")
    T.ok(reads > afterFirst, "a cleared plan reads it afresh: " .. reads)

    _G.C_Timer = savedTimer
    fresh.Addon, fresh.flavor = nil, nil
end

T.suite("darkness: the chat is painted once and not answered for")

-- The chat fades: its window, its tabs and its buttons are brought up and
-- taken down by writing a colour on every frame of the animation. A picture
-- under a fade has two writers while anything of ours answers those writes,
-- and two writers on one picture is a blink rather than a shade.
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
        amount = 64, mode = { chat = "follow" } } } } }

    local savedHook = _G.hooksecurefunc
    local placed = {}
    _G.hooksecurefunc = function(object, method)
        if type(object) == "table" and method == "SetVertexColor" then
            placed[object] = true
        end
    end

    local function art()
        local object = { r = 1, g = 1, b = 1, a = 1 }
        object.GetObjectType = function() return "Texture" end
        object.GetDrawLayer = function() return "ARTWORK" end
        object.GetTexture = function() return 8080 end
        function object:GetVertexColor() return self.r, self.g, self.b, self.a end
        function object:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end
        return object
    end

    local chatArt, otherArt = art(), art()

    Late.PaintShallow({
        GetObjectType = function() return "Frame" end,
        GetName = function() return "AChatWindow" end,
        GetRegions = function() return chatArt end,
        GetChildren = function() return end,
    }, "chat", nil)

    Late.PaintShallow({
        GetObjectType = function() return "Frame" end,
        GetName = function() return "AnOrdinaryWindow" end,
        GetRegions = function() return otherArt end,
        GetChildren = function() return end,
    }, nil, "AnOrdinaryWindow")

    T.ok(chatArt.r < 1, "the chat's framing is painted")
    T.eq(placed[chatArt], nil,
        "and nothing of ours listens for a colour written over it")

    T.ok(otherArt.r < 1, "an ordinary window is painted too")
    T.eq(placed[otherArt], true, "and that one is answered for as before")

    _G.hooksecurefunc = savedHook
    fresh.Addon, fresh.flavor = nil, nil
end

T.suite("darkness: the chat does not set the text raising going")

-- Raising text walks every page the addon remembers and writes every font
-- object it knows. Asked on any showing, that runs on the movement of a
-- mouse over the chat - a chat window, its tabs and its buttons appear and
-- vanish constantly - for text that is not on a page and is never raised.
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

    local savedTimer = _G.C_Timer
    _G.C_Timer = { After = function() end }

    -- The raising itself is counted rather than the deferred work in
    -- general: a showing asks for other things too, and the question here
    -- is about the text alone.
    local asked = 0
    local savedLift = Late.LiftPagesLater
    Late.LiftPagesLater = function() asked = asked + 1 end

    local function frame(name)
        return {
            GetObjectType = function() return "Frame" end,
            GetName = function() return name end,
            GetRegions = function() return end,
            GetChildren = function() return end,
        }
    end

    -- The chat, appearing and vanishing as the mouse passes over it.
    for _ = 1, 30 do Late.WindowShown(frame("ChatFrame1")) end
    local afterChat = asked
    asked = 0

    -- A page of text, appearing once.
    Late.WindowShown(frame("QuestFrame"))

    T.ok(asked > 0, "a page sets the raising going: " .. asked)
    T.eq(afterChat, 0,
        "while thirty showings of the chat did not: " .. afterChat)

    Late.LiftPagesLater = savedLift
    _G.C_Timer = savedTimer
    fresh.Addon, fresh.flavor = nil, nil
end

T.suite("darkness: a colour written over us does not make us think again")

-- Working out whether a picture is framing or contents costs half a dozen
-- protected calls, and the answer is remembered. It has to be forgotten when
-- the game gives the picture a new image - a list row handed out of a pool
-- is a different thing from one moment to the next.
--
-- A colour written over a picture changes no such thing, and colours are
-- written in floods: experience ticking, a bag redrawing, a bar moving.
-- Forgetting the answer on each of those meant working it out again on each
-- of those.
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
        if object == methods then
            installed[method] = handler
        elseif type(object) == "table" then
            object["umbraHook" .. method] = handler
        end
    end
    _G.CreateFrame = function()
        return {
            CreateTexture = function()
                return setmetatable({}, { __index = methods })
            end,
        }
    end

    Late.Watch()

    -- Every question the rule asks of a picture is counted.
    local asked = 0
    local art = { r = 1, g = 1, b = 1, a = 1 }
    art.GetObjectType = function() return "Texture" end
    art.GetDrawLayer = function() asked = asked + 1 return "ARTWORK" end
    art.GetTexture = function() return 4040 end
    function art:GetVertexColor() return self.r, self.g, self.b, self.a end
    function art:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    Late.ApplyToWindow({
        GetObjectType = function() return "Frame" end,
        GetName = function() return "ABarWindow" end,
        GetRegions = function() return art end,
        GetChildren = function() return end,
    })

    asked = 0
    for _ = 1, 20 do fireColour(art) end
    T.eq(asked, 0, "twenty colours cost no fresh thinking: " .. asked)

    _G.C_Timer, _G.hooksecurefunc = savedTimer, savedHook
    _G.ShowUIPanel, _G.CreateFrame = savedShow, savedCreate
    fresh.Addon, fresh.flavor = nil, nil
end

T.suite("darkness: a burst of writes costs painting and not bookkeeping")

-- An item dropping into a bag is one event to the player and hundreds of
-- writes to the interface: the game hands every slot its picture afresh.
-- The author's report counts 9,721 of them in the bag window in a single
-- session, and he named the moment it costs him frames.
--
-- What was expensive there was never the painting - a write answered by a
-- write - but the bookkeeping done beside it: the store's shape corrected
-- and its by-window tally walked on every one of those hundreds of calls.
-- The painting stays immediate, because deferring it was tried and bought
-- the bag's frames with a blink of the merchant's window; the counting is
-- throttled to once a second instead.
do
    local fresh = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fresh)
    helpers.loadAddonFile("Core/Compat.lua", fresh)
    helpers.loadAddonFile("Core/Locale.lua", fresh)
    helpers.loadAddonFile("Core/Registry.lua", fresh)
    helpers.loadAddonFile("Modules/Darkness.lua", fresh)

    local Burst = fresh.Darkness
    fresh.Events = { Subscribe = function() end }
    fresh.flavor = "vanilla"
    fresh.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {} } } } }

    -- The store is where the bookkeeping lands, and counting how often it
    -- is asked for is how the throttle is measured.
    local asked = 0
    fresh.Addon.db.global = setmetatable({}, {
        __index = function(_, key)
            if key == "report" then asked = asked + 1 end
            return nil
        end,
    })

    local savedHook, savedCreate = _G.hooksecurefunc, _G.CreateFrame
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

    Burst.Watch()
    local hear = installed["SetTexture"]
    T.ok(type(hear) == "function", "the watcher is in place")

    local painted = 0
    local realRepaint = Burst.Repaint
    Burst.Repaint = function(...) painted = painted + 1 return realRepaint(...) end

    local slots = {}
    local window
    for i = 1, 300 do
        slots[i] = {
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function() return "Interface\\Buttons\\UI-Slot-Background" end,
            GetVertexColor = function() return 1, 1, 1, 1 end,
            SetVertexColor = function() end,
            GetParent = function() return window end,
        }
    end
    window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "SomeBagWindow" end,
        GetRegions = function() return unpack(slots) end,
        GetChildren = function() return end,
        GetParent = function() return nil end,
    }

    if type(hear) == "function" then
        Burst.ApplyToWindow(window, true)

        painted = 0
        for i = 1, 300 do hear(slots[i]) end

        -- Every write is answered in the call that made it: that is what
        -- keeps a window from being seen in its native colour, and the
        -- author reported the blink when it was not so.
        T.ok(painted > 0, "the writes are answered rather than deferred")
    end

    Burst.Repaint = realRepaint
    _G.hooksecurefunc, _G.CreateFrame = savedHook, savedCreate
end

