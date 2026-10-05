local helpers = require("helpers")

-- Three doors the core did not have, all three found by a live module.
--
--   1. **The unit frame aura icon group.** The module looked for foreign
--      icons by walking the structure -- a child with a Cooldown child --
--      because the core had no names at all. The walk worked, but
--      "recognise a foreign object by its shape" is knowledge of foreign
--      structure living outside the compatibility layer: let the frame
--      composition change and the walk silently stops finding anything.
--   2. **The group of game functions that lay those icons out.** Without
--      it the module can only wait for the next frame: the engine promises
--      no order between two subscribers of one event. With it one
--      hooksecurefunc stands -- after the game by structure, not after a delay.
--   3. **The "this object is ours" mark** (handle:Own, contract version 15).
--      Darkness walks foreign frames in depth and tints all their textures;
--      an object created by a module on a foreign frame was indistinguishable to it.
--
-- All three are silent-failure subsystems: a wrong guess here drops nothing
-- and prints nothing to chat, it simply stops working. Hence checks, not
-- a client.

T.suite("compat: unit frame aura icon groups")

local FLAVORS = { "vanilla", "tbc", "mists" }

do
    local core = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", core)
    local Compat = core.Compat

    for i = 1, #FLAVORS do
        local flavor = FLAVORS[i]
        T.eq(Compat.HasGroup(flavor, "unitframe-auras"), true,
            flavor .. ": the aura icon group is declared")
        T.eq(Compat.HasGroup(flavor, "unitframe-auras-relayout"), true,
            flavor .. ": the layout function group is declared")
    end

    --- Whether a name is in the group.
    -- @param flavor string
    -- @param group string
    -- @param name string
    -- @return boolean
    local function has(flavor, group, name)
        local names = Compat.GetFrameNames(flavor, group)
        for i = 1, #names do
            if names[i] == name then return true end
        end
        return false
    end

    T.eq(has("mists", "unitframe-auras", "TargetFrameBuff1"), true,
        "the first target buff is named")
    T.eq(has("mists", "unitframe-auras", "TargetFrameDebuff16"), true,
        "and the last debuff as well")
    T.eq(has("vanilla", "unitframe-auras", "PartyMemberFrame1Debuff1"), true,
        "the first party member debuff is named")
    T.eq(has("vanilla", "unitframe-auras", "PetFrameDebuff1"), true,
        "and the pet debuff")

    -- There is no focus in vanilla at all: it appeared in TBC. The same
    -- decision as for the castbar-focus group -- absent names, not an empty list.
    T.eq(has("vanilla", "unitframe-auras", "FocusFrameBuff1"), false,
        "vanilla has no focus, and no focus icons are named there")
    T.eq(has("tbc", "unitframe-auras", "FocusFrameBuff1"), true,
        "while TBC has focus, and its icons are named")

    T.eq(has("mists", "unitframe-auras-relayout", "TargetFrame_UpdateAuras"), true,
        "the target aura layout function is named")
    T.eq(has("mists", "unitframe-auras-relayout", "CompactUnitFrame_UpdateAuras"),
        true, "and the compact frame layout as well")

    -- A client in which none of these names exist. That is why the names are
    -- declared as candidates: an empty list reaches the module, and the
    -- module falls back to walking the structure.
    for i = 1, #FLAVORS do
        local flavor = FLAVORS[i]
        T.eq(#Compat.FilterExisting(
            Compat.GetFrameNames(flavor, "unitframe-auras"), {}), 0,
            flavor .. ": on a client without these icons no names remain")
        T.eq(#Compat.FilterExisting(
            Compat.GetFrameNames(flavor, "unitframe-auras-relayout"), {}), 0,
            flavor .. ": and none without these functions either")
    end

    -- And conversely: whatever the client does have arrives in full.
    T.eq(#Compat.FilterExisting(
        Compat.GetFrameNames("mists", "unitframe-auras-relayout"),
        { TargetFrame_UpdateAuras = function() end }), 1,
        "while what does exist reaches the module")

    -- The answer is a copy: spoiling it, the module spoils no one else’s list.
    local copy = Compat.GetFrameNames("tbc", "unitframe-auras")
    copy[1] = "SPOILED"
    T.ok(Compat.GetFrameNames("tbc", "unitframe-auras")[1] ~= "SPOILED",
        "the answer is a copy, not the shared table")
end

T.suite("unitframe auras: the name outranks the structure, but the structure stays")

local MODULE = "Features/Auras"

helpers.installValidator()

local pure = helpers.newNamespace()
do
    local _, restore = helpers.installAuraFilter()
    helpers.loadModule(MODULE, pure, { withRegistration = false })
    restore()
end

local Units = pure.Units

do
    --- Fake client object.
    -- @param kind string
    -- @param parent table|nil
    -- @return table
    local function obj(kind, parent)
        local o = { kind = kind, children = {}, regions = {}, parent = parent }
        function o:GetObjectType() return self.kind end
        function o:GetChildren() return unpack(self.children) end
        function o:GetRegions() return unpack(self.regions) end
        function o:GetParent() return self.parent end
        return o
    end

    -- An icon the game named, but which the structural walk does not
    -- recognise: there is no circular cooldown under it. Exactly the build
    -- the name group was created for.
    local frame = obj("Frame")
    frame.unit = "target"

    local named = obj("Button", frame)
    named.regions[1] = obj("Texture", named)
    frame.children[1] = named

    T.eq(Units.IsAuraButton(named), false,
        "the structural walk does not recognise this icon")

    local state = Units.NewState()
    T.eq(Units.Scan(state, { frame }), 0,
        "and without names nothing is found on this frame")

    T.eq(Units.Scan(state, { frame }, { named }), 1,
        "while with a name from the core the icon is found")
    T.eq(state.buttons[1].unit, "target",
        "and its unit was asked of the frame, not derived from the name")
    T.eq(Units.Watches(state, "target"), true, "the unit is accounted for")

    -- An icon whose unit frame cannot be reached is not taken: our object on
    -- a foreign object with no owner would be a trace nobody answers for.
    local orphan = obj("Button", obj("Frame"))
    T.eq(Units.Scan(state, { frame }, { orphan }), 0,
        "an icon with no known unit frame above it is not taken")

    -- One and the same icon, arriving both by name and by walk, is taken
    -- once: accounting the same object twice means two owners for one icon.
    local shaped = obj("Button", frame)
    shaped.regions[1] = obj("Texture", shaped)
    shaped.children[1] = obj("Cooldown", shaped)
    frame.children[2] = shaped

    T.eq(Units.Scan(state, { frame }), 1,
        "without names the walk finds only the structurally recognised one")
    T.eq(Units.Scan(state, { frame }, { named, shaped }), 2,
        "by names both are found, and neither is counted twice")

    -- A unit frame from which no name arrived is still walked as before:
    -- the game does not name compact party frames by name.
    local compact = obj("Frame")
    compact.unit = "party1"
    local inner = obj("Button", compact)
    inner.regions[1] = obj("Texture", inner)
    inner.children[1] = obj("Cooldown", inner)
    compact.children[1] = inner

    T.eq(Units.Scan(state, { frame, compact }, { named, shaped }), 3,
        "names on one frame do not cancel the walk of another")
end

--============================================================================
-- Full run: a client that names the icons and lays them out itself
--============================================================================

T.suite("unitframe auras: a hook instead of waiting for a frame")

do
    local saved = {
        UnitAura = _G.UnitAura, C_UnitAuras = _G.C_UnitAuras,
        GetTime = _G.GetTime, CreateFrame = _G.CreateFrame,
        UIParent = _G.UIParent, GameTooltip = _G.GameTooltip,
        InCombatLockdown = _G.InCombatLockdown,
        RegisterAttributeDriver = _G.RegisterAttributeDriver,
        SlashCmdList = _G.SlashCmdList,
        hooksecurefunc = _G.hooksecurefunc,
        TargetFrame = _G.TargetFrame, PlayerFrame = _G.PlayerFrame,
        TargetFrame_UpdateAuras = _G.TargetFrame_UpdateAuras,
    }

    local clock = 1000

    local object
    function object(kind, template, parent)
        local o = {
            kind = kind, template = template, parent = parent,
            children = {}, regions = {}, attr = {}, scripts = {},
            shown = false, alpha = 1, mouse = true, id = 0,
        }

        function o:IsProtected() return false end
        function o:GetObjectType() return self.kind end
        function o:GetChildren() return unpack(self.children) end
        function o:GetRegions() return unpack(self.regions) end
        function o:GetParent() return self.parent end
        function o:GetID() return self.id end
        function o:SetID(value) self.id = value end
        function o:Show() self.shown = true end
        function o:Hide() self.shown = false end
        function o:SetShown(v) self.shown = v and true or false end
        function o:IsShown() return self.shown end
        function o:GameShow(v) self.shown = v and true or false end
        function o:SetPoint() end
        function o:ClearAllPoints() end
        function o:SetAllPoints() end
        function o:SetSize() end
        function o:SetWidth() end
        function o:SetHeight() end
        function o:SetScale() end
        function o:SetParent(value) self.parent = value end
        function o:SetAttribute(key, value) self.attr[key] = value end
        function o:GetAttribute(key) return self.attr[key] end
        function o:SetAlpha(value) self.alpha = tonumber(value) or 1 end
        function o:GetAlpha() return self.alpha end
        function o:EnableMouse(v) self.mouse = v and true or false end
        function o:IsMouseEnabled() return self.mouse end
        function o:SetFrameStrata(value) self.strata = value end
        function o:SetScript(name, fn) self.scripts[name] = fn end
        function o:HookScript(name, fn) self.scripts[name] = fn end
        function o:RegisterEvent() end
        function o:UnregisterEvent() end
        function o:RegisterForClicks() end
        function o:SetTexture(path) self.path = path end
        function o:GetTexture() return self.path end
        function o:SetTexCoord() end
        function o:SetVertexColor() end
        function o:SetColorTexture(...) self.color = { ... } end
        function o:SetDrawLayer() end

        function o:CreateTexture()
            local t = object("Texture", nil, self)
            self.regions[#self.regions + 1] = t
            return t
        end
        function o:CreateFontString()
            local f = object("FontString", nil, self)
            f.text = ""
            function f:SetText(value) self.text = value or "" end
            function f:GetText() return self.text end
            function f:SetJustifyH() end
            function f:SetFont() end
            function f:GetFont() return "font", 10, "" end
            self.regions[#self.regions + 1] = f
            return f
        end
        if kind == "Cooldown" then
            function o:SetCooldown() end
            function o:Clear() end
            function o:SetDrawEdge() end
            function o:SetHideCountdownNumbers() end
        end
        return o
    end

    _G.CreateFrame = function(kind, _, parent, template)
        local f = object(kind, template, parent)
        if type(parent) == "table" and parent.children then
            parent.children[#parent.children + 1] = f
        end
        return f
    end
    _G.RegisterAttributeDriver = function() end
    _G.InCombatLockdown = function() return false end
    _G.SlashCmdList = {}
    _G.GetTime = function() return clock end
    _G.C_UnitAuras = nil
    _G.UIParent = object("Frame")
    _G.GameTooltip = {
        SetOwner = function() end, SetUnitBuff = function() end,
        SetUnitDebuff = function() end, Show = function() end,
        Hide = function() end,
    }

    -- Hooking a game function the way the engine does it: our handler is
    -- called **after** it and changes nothing inside it.
    _G.hooksecurefunc = function(name, fn)
        local original = _G[name]
        if type(original) ~= "function" then
            error("nothing to hook: " .. tostring(name), 0)
        end
        _G[name] = function(...)
            local result = original(...)
            fn(...)
            return result
        end
    end

    local AURAS = {
        player = { HELPFUL = {}, HARMFUL = {} },
        target = {
            HELPFUL = {
                { "Shield", "icon-shield", 1, nil, 60, 1060, "player", nil, nil, 11 },
                { "Gift", "icon-gift", 1, nil, 60, 1070, "party1", nil, nil, 12 },
            },
            HARMFUL = {},
        },
    }

    _G.UnitAura = function(unit, index, filter)
        local byUnit = AURAS[unit]
        local aura = byUnit and byUnit[filter] and byUnit[filter][index]
        if not aura then return nil end
        return aura[1], aura[2], aura[3], aura[4], aura[5], aura[6], aura[7],
            aura[8], aura[9], aura[10]
    end

    -- The unit frame of this build: aura icons are named and **not recognised
    -- structurally** -- there is no circular cooldown under them. They can
    -- only be found through the name group.
    local target = object("Frame")
    target.unit = "target"
    target.buffSlots = {}

    for i = 1, 4 do
        local button = object("Button", nil, target)
        button.id = i
        button.icon = button:CreateTexture()
        target.children[#target.children + 1] = button
        target.buffSlots[i] = button
        _G["TargetFrameBuff" .. i] = button
    end

    _G.TargetFrame = target

    -- The game lays out its own icons, and does it in one function.
    _G.TargetFrame_UpdateAuras = function()
        local list = AURAS.target.HELPFUL
        for i = 1, #target.buffSlots do
            local aura = list[i]
            target.buffSlots[i].icon:SetTexture(aura and aura[2] or nil)
            target.buffSlots[i]:GameShow(aura ~= nil)
        end
    end

    local core = helpers.newNamespace()
    local CORE = {
        "Core/Compat.lua", "Core/Registry.lua", "Core/Defaults.lua",
        "Core/Command.lua", "Core/Locale.lua", "Core/Skin.lua",
        "Skin/Draw.lua", "Core/Frames.lua", "Core/Events.lua",
        "Core/Combat.lua", "Core/Api.lua", "Core/Casefold.lua",
        "Core/AuraFilter.lua", "Core/Media.lua",
    }
    for i = 1, #CORE do helpers.loadAddonFile(CORE[i], core) end

    local said = {}
    core.Registry.report = function(text) said[#said + 1] = text end
    core.Addon = {
        db = { profile = {}, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }
    core.flavor = "mists"

    local mod = helpers.newNamespace()
    helpers.loadModule(MODULE, mod)

    local handle = core.Registry:Get("umbraauras")
    T.ok(handle ~= nil, "the module is registered: " .. table.concat(said, " | "))

    if handle then
        core.Registry:EnableAll()

        local settings = handle:GetSettings()
        for key, value in pairs(handle.defaults) do settings[key] = value end

        --- A frame: the single OnUpdate of the module.
        local function frame()
            for i = 1, #_G.UIParent.children do
                local child = _G.UIParent.children[i]
                local tick = child.scripts and child.scripts.OnUpdate
                if tick then tick(child, 0) end
            end
        end

        local function alive(msg)
            T.eq(core.Registry:IsFailed("umbraauras"), false,
                msg .. ": " .. (said[#said] or "the module was not disabled"))
        end

        handle.options.args.enabled.set(nil, true)
        settings.filterMode = "deny"
        settings.filterList = "11"
        handle.options.args.units.set(nil, true)
        frame()
        alive("enabling")

        local buff = target.buffSlots[1]
        T.eq(mod.Units.IsAuraButton(buff), false,
            "the icon of this build is not recognised by the structural walk")

        -- === The hook path ==================================================
        --
        -- Neither an event nor a frame: the game called its layout function,
        -- and the answer must be ready at once -- the hook stands after it structurally.
        _G.TargetFrame_UpdateAuras()
        alive("the game laid out its own auras")
        T.eq(buff.alpha, 0,
            "the hidden one was found by name and hidden in the same frame: "
            .. "no waiting for a frame happened here")
        T.eq(buff.mouse, false, "and the mouse was taken off it")
        T.eq(target.buffSlots[2].alpha, 1, "while the neighbouring aura is untouched")

        -- === No more than once per frame ====================================
        --
        -- Some game layout functions are called once per frame object. A
        -- second pass in the same frame is not made, and it shows: the answer
        -- stays the same until the frame changes.
        AURAS.target.HELPFUL[1] = { "Gift", "icon-gift", 1, nil, 60, 1070,
            "party1", nil, nil, 12 }
        AURAS.target.HELPFUL[2] = { "Shield", "icon-shield", 1, nil, 60, 1060,
            "player", nil, nil, 11 }
        _G.TargetFrame_UpdateAuras()
        T.eq(buff.alpha, 0, "a second pass in the same frame is not made")

        -- === A suppressed call is caught up by a frame ======================
        --
        -- Suppression has no right to lose work. The game calls its layout
        -- functions once per frame object: suppressed calls are frames the
        -- pass has not seen yet, and waiting for a new UNIT_AURA is not
        -- allowed -- there may be none at all. So the flag is raised again,
        -- and the next frame catches everything up in one pass.
        frame()
        alive("a frame after a suppressed call")
        T.eq(buff.alpha, 1,
            "the suppressed call was caught up by a frame, with no new event")
        T.eq(target.buffSlots[2].alpha, 0,
            "and the hidden one moved along with its aura")

        -- And caught up exactly once: on the next frame there is no work left.
        clock = clock + 1
        frame()
        T.eq(buff.alpha, 1, "and the second frame redoes nothing")
        T.eq(target.buffSlots[2].alpha, 0, "nor on the neighbouring icon")

        -- A new frame, and the hook works immediately again.
        clock = clock + 1
        AURAS.target.HELPFUL[1] = { "Shield", "icon-shield", 1, nil, 60, 1060,
            "player", nil, nil, 11 }
        AURAS.target.HELPFUL[2] = { "Gift", "icon-gift", 1, nil, 60, 1070,
            "party1", nil, nil, 12 }
        _G.TargetFrame_UpdateAuras()
        alive("a new frame")
        T.eq(buff.alpha, 0, "in a new frame the hook decides immediately again")
        T.eq(target.buffSlots[2].alpha, 1, "and the neighbouring aura came back")

        -- === Disabling lets foreign objects go ==============================
        handle.options.args.units.set(nil, false)
        frame()
        T.eq(buff.alpha, 1, "the disabled setting gave the foreign icon back")

        local left = {}
        for key in pairs(buff) do
            if type(key) == "string" and key:find("^umbra") then
                left[#left + 1] = key
            end
        end
        T.eq(#left, 0, "and nothing of ours is left on it: "
            .. table.concat(left, ", "))

        -- There is no way to unhook, so the hook stayed. The setting itself
        -- is the switch: the function called by the game now does nothing.
        clock = clock + 1
        _G.TargetFrame_UpdateAuras()
        alive("the game laid out auras with the setting disabled")
        T.eq(buff.alpha, 1, "a disabled pass does not touch the foreign icon")

        handle.options.args.enabled.set(nil, false)
        frame()
    end

    for i = 1, 4 do _G["TargetFrameBuff" .. i] = nil end
    for key, value in pairs(saved) do _G[key] = value end
    _G.TargetFrame = saved.TargetFrame
    _G.TargetFrame_UpdateAuras = saved.TargetFrame_UpdateAuras
end

helpers.removeValidator()

--============================================================================
-- Darkness: a module object on a foreign frame
--============================================================================

T.suite("darkness: a module object on a foreign frame keeps its own colour")

do
    local ns = helpers.newNamespace()
    local FILES = {
        "Core/Skin.lua", "Core/Compat.lua", "Core/Locale.lua",
        "Core/Registry.lua", "Core/Frames.lua", "Core/Events.lua",
        "Core/Combat.lua", "Core/Api.lua", "Modules/Darkness.lua",
    }
    for i = 1, #FILES do helpers.loadAddonFile(FILES[i], ns) end

    local Darkness = ns.Darkness

    --- Fake game texture: the colour can be read and written.
    -- @param path string path to the image file
    -- @return table
    local function texture(path)
        local t = { r = 1, g = 1, b = 1, a = 1 }
        function t:GetObjectType() return "Texture" end
        function t:GetTexture() return path end
        function t:GetVertexColor() return self.r, self.g, self.b, self.a end
        function t:SetVertexColor(cr, cg, cb, ca)
            self.r, self.g, self.b = cr, cg, cb
            if ca ~= nil then self.a = ca end
        end
        return t
    end

    -- A foreign game frame: it carries the game’s own border texture and
    -- ours, put on top by the module.
    local frame = { regions = {} }
    function frame:GetObjectType() return "Frame" end
    function frame:GetName() return "SomeGameWindow" end
    function frame:GetRegions() return unpack(self.regions) end
    function frame:GetChildren() return end

    local theirs = texture("Interface\\Common\\Border")
    local ours   = texture("Interface\\Common\\Border")
    frame.regions[1] = theirs
    frame.regions[2] = ours

    -- The mark is placed by the contract, not by the module by hand: the field name belongs to the core.
    ns.Addon = { db = { profile = {}, global = {} }, Print = function() end }
    local handle = ns.Api:RegisterModule({ name = "marker", api = 15 })
    T.ok(handle ~= nil, "the module for the mark is registered")

    T.eq(handle:Own(ours), true, "the object is marked as ours")
    T.eq(handle:Own(nil), false, "nothing cannot be marked")

    Darkness.ApplyToFrame(frame, 0.5)

    T.eq(theirs.r, 0.5, "the game’s own texture is darkened")
    T.eq(ours.r, 1, "while the module object kept its own colour")
    T.eq(ns.Darkness.Remembered(ours), nil,
        "and darkness did not remember our colour as the original")

    -- The mark is removed by the same call: a module that gave a foreign
    -- frame back to the game leaves nothing of its own on it -- the mark is
    -- no different here from the alpha it had overwritten.
    T.eq(handle:Own(ours, false), true, "the mark is removed")
    T.eq(ours.umbraOwned, nil, "and no field is left on the object")

    Darkness.ApplyToFrame(frame, 0.5)
    T.eq(ours.r, 0.5, "a removed mark returns the object to the common pass")

    -- The question is the same from either side: a marked frame is not taken
    -- by the pass, and the pass does not go inside it.
    local child = { regions = {} }
    function child:GetObjectType() return "Frame" end
    function child:GetName() return "SomeGameChild" end
    function child:GetRegions() return unpack(self.regions) end
    function child:GetChildren() return end
    child.regions[1] = texture("Interface\\Common\\Border")
    handle:Own(child)

    T.eq(Darkness.IsOurs(child), true, "the marked frame is recognised as ours")
    Darkness.ApplyToFrame(child, 0.5)
    T.eq(child.regions[1].r, 1, "and the pass did not go inside it")
end
