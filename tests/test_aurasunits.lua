local helpers = require("helpers")

-- Auras on unit frames: the filter and the border on foreign icons.
--
-- This is the only place in the module that works on frames belonging to the
-- game. The rules there are different, and what is checked here is exactly the difference:
--
--   1. **a name is a candidate, existence is the filter.** A client without
--      these frames at all must give nothing rather than an error;
--   2. **a frame appears later** -- a focus was set, a fifth player joined the party;
--   3. **the game redraws after us.** On one and the same event the game
--      changes the aura on an icon, and the engine promises no order between
--      two handlers. The pass must happen after the game -- that is on the
--      next frame rather than on the event itself;
--   4. **combat both ways.** The engine does not protect alpha or mouse
--      acceptance, so in combat everything must work and nothing must be
--      deferred: a filter frozen in combat IS the loss;
--   5. **the filter is the same one.** A spell hidden in our own grid is
--      hidden on the target too, and literally the same function decides it.
--
-- The fake client refuses like the engine: on a protected object in combat
-- every operation forbidden by docs/module-api.md §9 fails. A unit frame is
-- protected, aura icons inherit the protection downwards -- and if the module
-- hid them through Hide, this file would be red.

local MODULE = "Features/Auras"

helpers.installValidator()

--============================================================================
-- Part 1: the pure functions, with no core and no client
--============================================================================

T.suite("unitframe auras: an icon is recognised by its structure, not by its name")

local pure = helpers.newNamespace()
do
    local _, restore = helpers.installAuraFilter()
    helpers.loadModule(MODULE, pure, { withRegistration = false })
    restore()
end

local Units = pure.Units

--- A fake client object for the pure checks.
-- @param kind string the widget type as GetObjectType would name it
-- @return table
local function obj(kind)
    local o = { kind = kind, children = {}, regions = {}, alpha = 1,
        mouse = true, shown = true, id = 0 }

    function o:GetObjectType() return self.kind end
    function o:GetChildren() return unpack(self.children) end
    function o:GetRegions() return unpack(self.regions) end
    function o:GetID() return self.id end
    function o:IsShown() return self.shown end
    function o:GetAlpha() return self.alpha end
    function o:SetAlpha(value) self.alpha = value end
    function o:IsMouseEnabled() return self.mouse end
    function o:EnableMouse(value) self.mouse = value and true or false end
    function o:GetTexture() return self.path end
    function o:SetTexture(path) self.path = path end

    return o
end

--- An aura icon the way the game builds it: a texture and a circular cooldown.
-- @param icon any the texture
-- @param index number the aura index
-- @return table
local function auraButton(icon, index)
    local button = obj("Button")
    button.id = index or 1

    local texture = obj("Texture")
    texture.path = icon
    button.regions[1] = texture
    button.icon = texture

    button.children[1] = obj("Cooldown")
    return button
end

do
    T.eq(Units.IsAuraButton(auraButton("icon", 1)), true,
        "an icon with a texture and a cooldown is recognised")

    local noCooldown = obj("Button")
    noCooldown.regions[1] = obj("Texture")
    T.eq(Units.IsAuraButton(noCooldown), false,
        "a button with no circular cooldown does not count as an aura icon")

    local noTexture = obj("Frame")
    noTexture.children[1] = obj("Cooldown")
    T.eq(Units.IsAuraButton(noTexture), false,
        "nor does a frame with no texture")

    T.eq(Units.IsAuraButton(nil), false, "and neither does nothing")
    T.eq(Units.IsAuraButton("an icon as a string"), false,
        "a name is not an object")

    -- The cast bar on a unit frame: a frame, textures exist, there is no
    -- circular cooldown. That is exactly what the walk may not take for an aura.
    local castbar = obj("Frame")
    castbar.regions[1] = obj("Texture")
    castbar.regions[2] = obj("Texture")
    castbar.children[1] = obj("StatusBar")
    T.eq(Units.IsAuraButton(castbar), false, "a cast bar is not an aura")
end

T.suite("unitframe auras: the walk finds the icons and does not go inside them")

do
    local frame = obj("Frame")
    local shallow = auraButton("a", 1)
    frame.children[1] = shallow

    -- A nested level: in some builds the icons lie not on the unit frame
    -- itself but on its content.
    local content = obj("Frame")
    content.children[1] = auraButton("b", 2)
    content.children[2] = auraButton("c", 3)
    frame.children[2] = content

    local out = Units.Collect(frame, {}, 0)
    T.eq(#out, 3, "icons were found both on the frame and on its content")

    -- The root itself does not count as an icon: otherwise a walk started from
    -- the unit frame would take the frame itself for an aura.
    T.eq(#Units.Collect(auraButton("d", 4), {}, 0), 0,
        "the root of the walk does not count as an icon")

    -- The walk does not go inside a found icon: beneath it lies its own
    -- cooldown rather than a second icon.
    local nested = auraButton("e", 5)
    nested.children[2] = auraButton("f", 6)
    local root = obj("Frame")
    root.children[1] = nested
    T.eq(#Units.Collect(root, {}, 0), 1,
        "and the walk does not go inside a found icon")

    -- The depth ceiling: the fourth level is no longer ours.
    local deep = obj("Frame")
    local cursor = deep
    for _ = 1, 5 do
        local next = obj("Frame")
        cursor.children[1] = next
        cursor = next
    end
    cursor.children[1] = auraButton("far", 1)
    T.eq(#Units.Collect(deep, {}, 0), 0,
        "the walk does not search beyond the ceiling: a foreign frame is not walked entirely")
end

T.suite("unitframe auras: whose frame this is")

do
    local byField = obj("Frame")
    byField.unit = "target"
    T.eq(Units.UnitOf(byField), "target", "the unit is taken from a frame field")

    local byAttribute = obj("Frame")
    function byAttribute:GetAttribute(key)
        if key == "unit" then return "party3" end
        return nil
    end
    T.eq(Units.UnitOf(byAttribute), "party3",
        "and with no field, from a secure template attribute")

    T.eq(Units.UnitOf(obj("Frame")), nil, "a frame with no unit is not ours")
    T.eq(Units.UnitOf(nil), nil, "and neither is nothing")
end

T.suite("unitframe auras: recognising an aura by matching its texture")

do
    local AURAS = {
        HELPFUL = { { name = "Shield", icon = "shield", spellId = 11 } },
        HARMFUL = { { name = "Poison", icon = "poison", spellId = 22 } },
    }
    local function query(_, index, filter)
        return AURAS[filter] and AURAS[filter][index] or nil
    end

    local buff = auraButton("shield", 1)
    local aura, region = Units.Identify(buff, "target", query)
    T.ok(aura ~= nil, "the buff was recognised")
    T.eq(aura and aura.spellId, 11, "and recognised correctly")
    T.eq(aura and aura.harmful, false, "the kind of the aura is derived from where it was found")
    T.eq(region, buff.icon, "and the texture the border will go around was found")

    local debuff = auraButton("poison", 1)
    local bad = Units.Identify(debuff, "target", query)
    T.ok(bad ~= nil and bad.harmful == true,
        "under the same index a debuff is recognised as a debuff")

    -- The texture on the icon is foreign: the game drew it before it updated
    -- the auras, or it is not an aura at all. The answer is "I do not know",
    -- and the icon stays as the game drew it.
    local stranger = auraButton("unknown", 1)
    T.eq(Units.Identify(stranger, "target", query), nil,
        "an unrecognised icon stays unrecognised")

    local noId = auraButton("shield", 0)
    T.eq(Units.Identify(noId, "target", query), nil,
        "an icon with no aura index is not recognised")
end

T.suite("unitframe auras: hide and restore, counting from the remembered value")

do
    local state = Units.NewState()
    local button = auraButton("shield", 1)
    button.alpha = 0.6
    button.mouse = true

    T.eq(Units.Conceal(state, button), true, "the icon is hidden")
    T.eq(button.alpha, 0, "by alpha rather than by Hide")
    T.eq(button.mouse, false, "and the mouse is taken off it: the invisible gives no tooltip")

    -- A second "hide" has no right to remember our own alpha as the native
    -- one -- otherwise the restore would stop restoring.
    T.eq(Units.Conceal(state, button), false, "a repeated hide writes nothing")
    T.eq(Units.ALPHA[button], 0.6, "the remembered native alpha is the former one")

    T.eq(Units.Reveal(state, button), true, "the icon was restored")
    T.eq(button.alpha, 0.6, "and restored to the remembered value rather than to one")
    T.eq(button.mouse, true, "the mouse came back too")
    T.eq(Units.Reveal(state, button), false, "a second restore does nothing")
end

--============================================================================
-- Part 2: a full run on the real core
--============================================================================

T.suite("unitframe auras: the full run")

do
    local saved = {
        UnitAura = _G.UnitAura, C_UnitAuras = _G.C_UnitAuras,
        GetTime = _G.GetTime, CreateFrame = _G.CreateFrame,
        UIParent = _G.UIParent, GameTooltip = _G.GameTooltip,
        InCombatLockdown = _G.InCombatLockdown,
        RegisterAttributeDriver = _G.RegisterAttributeDriver,
        SlashCmdList = _G.SlashCmdList,
    }

    -- What the engine will not let you do to a protected object in combat
    -- (docs/module-api.md §9). Alpha and mouse acceptance are not on the list,
    -- and this whole file rests on their not being there.
    local RESTRICTED = {
        Show = true, Hide = true, SetShown = true,
        SetPoint = true, ClearAllPoints = true, SetAllPoints = true,
        SetSize = true, SetWidth = true, SetHeight = true, SetScale = true,
        SetParent = true, SetAttribute = true,
    }

    local client = { frames = {}, combat = false, drivers = {}, refused = 0 }

    local function secureTemplate(template)
        return type(template) == "string"
            and template:find("Secure", 1, true) ~= nil
    end

    local object

    local function forbid(self, method)
        if client.combat and self.protectedFlag and RESTRICTED[method] then
            client.refused = client.refused + 1
            error("Interface action failed because of an AddOn: " .. method, 0)
        end
    end

    function object(kind, template, parent)
        local o = {
            kind = kind, template = template, parent = parent,
            children = {}, regions = {}, attr = {}, scripts = {},
            shown = false, alpha = 1, mouse = true, id = 0,
        }
        o.protectedFlag = secureTemplate(template)
            or (type(parent) == "table" and parent.protectedFlag or false)

        function o:IsProtected() return self.protectedFlag end
        function o:GetObjectType() return self.kind end
        function o:GetChildren() return unpack(self.children) end
        function o:GetRegions() return unpack(self.regions) end
        function o:GetID() return self.id end
        function o:SetID(value) self.id = value end

        function o:Show() forbid(self, "Show") self.shown = true end
        function o:Hide() forbid(self, "Hide") self.shown = false end
        function o:SetShown(v)
            forbid(self, "SetShown")
            self.shown = v and true or false
        end
        function o:IsShown() return self.shown end

        -- The same thing but by the engine's own hand: nobody forbids the game
        -- to show and hide its own frames in combat, and the fake client has no
        -- right to claim otherwise.
        function o:GameShow(v) self.shown = v and true or false end

        function o:SetPoint(point, anchor, _, x, y)
            forbid(self, "SetPoint")
            self.point, self.anchor, self.x, self.y = point, anchor, x, y
        end
        function o:ClearAllPoints() forbid(self, "ClearAllPoints") end
        function o:SetAllPoints() forbid(self, "SetAllPoints") end
        function o:SetSize(w, h) forbid(self, "SetSize") self.w, self.h = w, h end
        function o:SetWidth(w) forbid(self, "SetWidth") self.w = w end
        function o:SetHeight(h) forbid(self, "SetHeight") self.h = h end
        function o:SetScale() forbid(self, "SetScale") end
        function o:SetParent(value) forbid(self, "SetParent") self.parent = value end
        function o:SetAttribute(key, value)
            forbid(self, "SetAttribute")
            self.attr[key] = value
        end
        function o:GetAttribute(key) return self.attr[key] end
        function o:GetParent() return self.parent end

        -- The engine does not protect alpha, mouse acceptance or the layer.
        -- There is deliberately no refusal here: were there one, the check would be confirming itself.
        function o:SetAlpha(value) self.alpha = tonumber(value) or 1 end
        function o:GetAlpha() return self.alpha end
        function o:EnableMouse(v) self.mouse = v and true or false end
        function o:IsMouseEnabled() return self.mouse end
        function o:SetFrameStrata(value) self.strata = value end

        function o:SetScript(name, fn) self.scripts[name] = fn end
        function o:HookScript(name, fn) self.scripts[name] = fn end
        function o:RegisterEvent() end
        function o:UnregisterEvent() end
        function o:RegisterForClicks(...) self.clicks = { ... } end

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

    local function create(kind, _, parent, template)
        local protected = secureTemplate(template)
            or (type(parent) == "table" and parent.protectedFlag or false)
        if client.combat and protected then
            client.refused = client.refused + 1
            error("Interface action failed because of an AddOn: CreateFrame", 0)
        end
        local f = object(kind, template, parent)
        if type(parent) == "table" and parent.children then
            parent.children[#parent.children + 1] = f
        end
        client.frames[#client.frames + 1] = f
        return f
    end

    _G.CreateFrame = create
    _G.RegisterAttributeDriver = function(frame, attribute, condition)
        client.drivers[frame] = { attribute, condition }
    end
    _G.InCombatLockdown = function() return client.combat end
    _G.SlashCmdList = {}
    _G.GetTime = function() return 1000 end
    _G.C_UnitAuras = nil
    _G.UIParent = object("Frame")
    _G.GameTooltip = {
        SetOwner = function() end, SetUnitBuff = function() end,
        SetUnitDebuff = function() end, Show = function() end,
        Hide = function() end,
    }

    --========================================================================
    -- The unit auras and the game unit frames
    --========================================================================

    -- The aura set on every unit. It is edited right here: that IS "the game
    -- changed the auras".
    local AURAS = {
        player = {
            HELPFUL = {
                { "Shield", "icon-shield", 1, nil, 60, 1060, "player", nil, nil, 11 },
                { "Gift", "icon-gift", 1, nil, 60, 1070, "party1", nil, nil, 12 },
            },
            HARMFUL = {},
        },
        target = {
            HELPFUL = {
                { "Shield", "icon-shield", 1, nil, 60, 1060, "player", nil, nil, 11 },
                { "Gift",  "icon-gift",  1, nil, 60, 1070, "party1", nil, nil, 12 },
            },
            HARMFUL = {
                { "Poison", "icon-poison", 1, nil, 20, 1020, "player", nil, nil, 21 },
            },
        },
        focus = {
            HELPFUL = { { "Shield", "icon-shield", 1, nil, 60, 1060, "player", nil, nil, 11 } },
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

    -- Every created unit frame: they are used to count how many foreign icons
    -- take part in the cost measurement.
    local built = {}

    --- A game unit frame: a protected frame with aura icons on it.
    -- @param unit string
    -- @param buffs number how many buff slots
    -- @param debuffs number how many debuff slots
    -- @return table
    local function unitFrame(unit, buffs, debuffs)
        local frame = object("Frame", "SecureUnitButtonTemplate")
        frame.unit = unit
        frame.buffSlots, frame.debuffSlots = {}, {}

        local function slot(list, index)
            local button = object("Button", nil, frame)
            button.id = index
            button.shown = false
            button.icon = button:CreateTexture()
            -- The circular cooldown is a child of the icon, and that is how
            -- the walk recognises it.
            button.children[#button.children + 1] = object("Cooldown", nil, button)
            frame.children[#frame.children + 1] = button
            list[index] = button
            return button
        end

        for i = 1, buffs do slot(frame.buffSlots, i) end
        for i = 1, debuffs do slot(frame.debuffSlots, i) end
        built[#built + 1] = frame
        return frame
    end

    --- The game redrew the auras on a unit frame.
    --
    -- Exactly what the engine does: every slot is assigned the texture of the
    -- aura under its index, the spare slots are hidden. This is done by the
    -- engine's hand (GameShow) rather than ours: nobody forbids the game to
    -- hide its own frames in combat.
    local function gameDraw(frame)
        local byUnit = AURAS[frame.unit] or { HELPFUL = {}, HARMFUL = {} }
        local pairsOf = {
            { frame.buffSlots, byUnit.HELPFUL or {} },
            { frame.debuffSlots, byUnit.HARMFUL or {} },
        }
        for i = 1, #pairsOf do
            local slots, list = pairsOf[i][1], pairsOf[i][2]
            for index = 1, #slots do
                local aura = list[index]
                slots[index].icon:SetTexture(aura and aura[2] or nil)
                slots[index]:GameShow(aura ~= nil)
            end
        end
    end

    -- The client on this run is mists: the target, the target of target, the
    -- focus, the player and the pet lie in the "unitframe" group, and the
    -- five-player party in "raidframe-member". The names are taken from the
    -- compatibility layer, and there is no list of our own here.
    _G.TargetFrame = unitFrame("target", 16, 16)
    _G.PlayerFrame = unitFrame("player", 0, 0)

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

        --- Is the module still alive? The core swallows a failing handler and disables the module.
        local function alive(msg)
            T.eq(core.Registry:IsFailed("umbraauras"), false,
                msg .. ": " .. (said[#said] or "the module was not disabled"))
        end

        --- A frame: the only OnUpdate of the module. The pass over foreign
        --- icons waits for it deliberately -- on the event itself the game has not relaid its auras yet.
        local function frame()
            for i = 1, #_G.UIParent.children do
                local child = _G.UIParent.children[i]
                local tick = child.scripts and child.scripts.OnUpdate
                if tick then tick(child, 0) end
            end
        end

        --- An aura change as the player sees it: the game redrew its icons,
        --- the event was dispatched, the frame passed.
        local function auraEvent(unit)
            if _G.TargetFrame then gameDraw(_G.TargetFrame) end
            if _G.FocusFrame then gameDraw(_G.FocusFrame) end
            core.Events.Dispatch("UNIT_AURA", unit)
            frame()
        end

        --- The target icons shown by the game.
        local function slotOf(frameObject, kind, index)
            local list = kind == "HARMFUL" and frameObject.debuffSlots
                or frameObject.buffSlots
            return list[index]
        end

        -- === 1. A fresh install touches nothing ==============================
        handle.options.args.enabled.set(nil, true)
        auraEvent("target")
        alive("enabling the module itself")
        T.eq(settings.units, false, "unit frame auras are off by default")
        T.eq(slotOf(_G.TargetFrame, "HELPFUL", 1).alpha, 1,
            "and not a single foreign icon is touched")
        T.eq(slotOf(_G.TargetFrame, "HELPFUL", 1)[mod.Units.ALPHA], nil,
            "there is no field of ours on a foreign icon")

        -- === 2. Enabling: the filter hides nothing yet =======================
        handle.options.args.units.set(nil, true)
        frame()
        alive("enabling unit frame auras")

        local buff = slotOf(_G.TargetFrame, "HELPFUL", 1)
        local other = slotOf(_G.TargetFrame, "HELPFUL", 2)
        local debuff = slotOf(_G.TargetFrame, "HARMFUL", 1)
        T.eq(buff.alpha, 1, "a shown target aura is shown")
        T.eq(debuff.alpha, 1, "and so is a debuff")

        -- The border is built on our frame rather than on the foreign icon: on
        -- a foreign one it would become a second owner for the core darkness.
        local ours = 0
        for i = 1, #buff.regions do
            if buff.regions[i] ~= buff.icon then ours = ours + 1 end
        end
        T.eq(ours, 0, "not a single texture of ours was created on the foreign icon")

        -- === 3. The filter means the same on the target as on ourselves ======
        --
        -- One and the same spell, one and the same list, one and the same
        -- decision function. A divergence here would mean two places where the
        -- player looks for the answer to "why am I seeing it".
        T.eq(mod.Units ~= nil, true, "the unit frame part is loaded")
        settings.filterMode = "deny"
        settings.filterList = "11"
        handle:Apply()
        auraEvent("target")
        alive("the filter with a non-empty list")

        T.eq(buff.alpha, 0, "a spell hidden on ourselves is hidden on the target too")
        T.eq(buff.mouse, false, "and the mouse is taken off it")
        T.eq(other.alpha, 1, "while the neighbouring aura is untouched")
        T.eq(debuff.alpha, 1, "and so is a debuff")

        -- The very same function rather than a similar one: compared by identity.
        local door = core.AuraFilter
        T.eq(mod.Filter.Split, door.Split, "the list parsing is the core one")
        T.eq(mod.Filter.Key, door.Key, "and so is the name key")

        -- And in our own grid that spell is hidden too.
        local own = 0
        for i = 1, #_G.UIParent.children do
            local child = _G.UIParent.children[i]
            if child.shown and child.regions[1] and child.regions[1].path then
                own = own + 1
                T.ok(child.regions[1].path ~= "icon-shield",
                    "the hidden spell is absent from our own grid as well")
            end
        end
        T.ok(own > 0, "while our own grid is drawn: " .. own)

        -- The kind of an aura as a filter axis means exactly the same on the
        -- target: the decision is made by the same Filter.Allows, and the
        -- module has no second answer to "what is a debuff".
        settings.filterMode = "off"
        settings.filterList = ""
        settings.hideDebuffs = true
        handle:Apply()
        auraEvent("target")
        alive("\"hide every debuff\" on the target")

        T.eq(debuff.alpha, 0, "\"hide every debuff\" hides on the target too")
        T.eq(debuff.mouse, false, "and the mouse is taken off it")
        T.eq(buff.alpha, 1, "while the target buffs are untouched")

        settings.hideDebuffs = false
        settings.hideBuffs = true
        handle:Apply()
        auraEvent("target")
        alive("\"hide every buff\" on the target")

        T.eq(buff.alpha, 0, "\"hide every buff\" hides on the target too")
        T.eq(other.alpha, 0, "every single one rather than the named ones")
        T.eq(debuff.alpha, 1, "while the target debuffs came back")

        settings.hideBuffs = false
        handle:Apply()
        auraEvent("target")
        T.eq(buff.alpha, 1, "clearing the switch restored the foreign icon")
        T.eq(buff.mouse, true, "and the mouse was given back to it")

        -- The list is returned to the state this part started from: it is what
        -- is checked next, and the start must be the same place.
        settings.filterMode = "deny"
        settings.filterList = "11"
        handle:Apply()
        auraEvent("target")
        T.eq(buff.alpha, 0, "the list hides the named one again")

        -- === 4. The game redrew after us ====================================
        --
        -- The icon slot is the same, the aura on it is different. The answer
        -- must change, and it must change **after** the game: the pass waits for its frame.
        AURAS.target.HELPFUL[1] = { "Gift", "icon-gift", 1, nil, 60, 1070,
            "party1", nil, nil, 12 }
        AURAS.target.HELPFUL[2] = { "Shield", "icon-shield", 1, nil, 60, 1060,
            "player", nil, nil, 11 }

        gameDraw(_G.TargetFrame)
        core.Events.Dispatch("UNIT_AURA", "target")
        T.eq(buff.alpha, 0, "on the event itself the answer is still the former one: "
            .. "the game may have relaid the auras after us")
        frame()
        alive("the pass after the game")
        T.eq(buff.alpha, 1, "on the next frame the first slot is no longer hidden")
        T.eq(other.alpha, 0, "while the hidden one moved along with its aura")

        -- === 5. A frame that did not exist before ===========================
        --
        -- A focus was set mid-game. The name was a candidate, the object did
        -- not exist at all -- and until that moment the module said nothing about it.
        T.eq(_G.FocusFrame, nil, "there is no focus in the client yet")
        _G.FocusFrame = unitFrame("focus", 8, 8)
        core.Events.Dispatch("PLAYER_FOCUS_CHANGED")
        auraEvent("focus")
        alive("the focus appeared")

        local focusBuff = slotOf(_G.FocusFrame, "HELPFUL", 1)
        T.eq(focusBuff.shown, true, "the game drew an aura on the focus")
        T.eq(focusBuff.alpha, 0, "and the filter reached it too")

        -- === 6. Combat both ways ============================================
        --
        -- Nothing freezes and nothing is deferred: the engine does not protect
        -- alpha or mouse acceptance, and the border lives on our frame.
        client.combat = true
        client.refused = 0

        AURAS.target.HELPFUL[1] = { "Shield", "icon-shield", 1, nil, 60, 1060,
            "player", nil, nil, 11 }
        AURAS.target.HELPFUL[2] = { "Gift", "icon-gift", 1, nil, 60, 1070,
            "party1", nil, nil, 12 }
        auraEvent("target")
        alive("a target aura change in combat")

        T.eq(client.refused, 0, "the engine refused no operation")
        T.eq(buff.alpha, 0, "the filter works in combat: what is hidden is hidden")
        T.eq(other.alpha, 1, "while what is shown is shown")
        T.eq(buff:IsProtected(), true,
            "and that is with the aura icon being protected by the engine")

        local queue = core.Combat.queues["umbraauras"]
        local onlyButtons = true
        if queue then
            for i = 1, #queue.order do
                if not tostring(queue.order[i]):find("^cancel:") then
                    onlyButtons = false
                end
            end
        end
        T.eq(onlyButtons, true,
            "the combat queue holds nothing but overlay aiming: "
            .. "a deferred filter is a frozen filter")

        -- The list is edited right in combat: the player opened the settings
        -- window, and the answer must change at once rather than after combat.
        settings.filterList = "12"
        handle:Apply()
        frame()
        alive("editing the filter in combat")
        T.eq(client.refused, 0, "editing the filter in combat got no refusal")
        T.eq(buff.alpha, 1, "the allowed aura came back")
        T.eq(other.alpha, 0, "while the denied one hid")

        client.combat = false
        core.Events.Dispatch("PLAYER_REGEN_ENABLED")
        frame()
        alive("leaving combat")
        T.eq(buff.alpha, 1, "after combat the answer is the one it was in combat")

        -- === 7. A rule gives the border colour, and nothing else =============
        settings.filterMode = "off"
        settings.filterList = ""
        settings.rules = { { name = "important", text = "11", color = "lilac" } }
        handle:Apply()
        auraEvent("target")
        alive("a rule on a target aura")

        T.eq(buff.alpha, 1, "a rule hides nothing")
        T.eq(buff.w, nil, "and writes no size onto a foreign icon: "
            .. "that is the engine-protected geometry of a foreign layout")

        -- === 8. Switching off lets go of everything foreign ==================
        --
        -- The check walks the icon itself rather than a list of fields: a list
        -- of fields forgets a new field at exactly the moment its author does.
        --
        settings.filterMode = "deny"
        settings.filterList = "11"
        handle:Apply()
        auraEvent("target")
        T.eq(buff.alpha, 0, "before switching off the icon is hidden")

        handle.options.args.units.set(nil, false)
        frame()
        alive("switching off unit frame auras")

        T.eq(buff.alpha, 1, "the foreign icon returned to its own look")
        T.eq(buff.mouse, true, "and the mouse was given back to it")

        local left = {}
        for key in pairs(buff) do
            if type(key) == "string" and key:find("^umbra") then
                left[#left + 1] = key
            end
        end
        T.eq(#left, 0, "and not a single field of ours is left on the foreign icon: "
            .. table.concat(left, ", "))

        -- Switching the module itself off is the same question from the other side.
        handle.options.args.units.set(nil, true)
        auraEvent("target")
        T.eq(buff.alpha, 0, "hidden again")
        handle.options.args.enabled.set(nil, false)
        frame()
        T.eq(buff.alpha, 1, "a disabled module leaves nothing foreign on itself")

        -- === 9. A client with no such frames at all =========================
        --
        -- A name is a candidate, existence is the filter. A missing frame means
        -- "silently nothing" rather than an error.
        local keptTarget, keptFocus = _G.TargetFrame, _G.FocusFrame
        _G.TargetFrame, _G.FocusFrame, _G.PlayerFrame = nil, nil, nil
        handle.options.args.enabled.set(nil, true)
        core.Events.Dispatch("PLAYER_TARGET_CHANGED")
        core.Events.Dispatch("UNIT_AURA", "target")
        frame()
        alive("a client with no unit frames at all")
        _G.TargetFrame, _G.FocusFrame = keptTarget, keptFocus

        -- === 10. The cost with a full party =================================
        --
        -- The target, the focus and five in the party. The real event path is
        -- measured: the game relaid its auras, the event was dispatched, the frame passed.
        for i = 1, 5 do
            local name = "CompactPartyFrameMember" .. i
            _G[name] = unitFrame("party" .. i, 0, 3)
            AURAS["party" .. i] = {
                HELPFUL = {},
                HARMFUL = {
                    { "Poison", "icon-poison", 1, nil, 20, 1020, "player", nil, nil, 21 },
                    { "Curse", "icon-curse", 1, nil, 20, 1020, "party2",
                        nil, nil, 22 },
                },
            }
        end
        _G.PlayerFrame = unitFrame("player", 0, 0)

        settings.filterMode = "deny"
        settings.filterList = "22"
        handle:Apply()
        core.Events.Dispatch("PLAYER_TARGET_CHANGED")
        for i = 1, 5 do gameDraw(_G["CompactPartyFrameMember" .. i]) end
        auraEvent("target")
        frame()
        alive("a full party")

        local hiddenInParty = _G.CompactPartyFrameMember1.debuffSlots[2]
        T.eq(hiddenInParty.alpha, 0,
            "the filter reached the party member icons too")

        -- The cost. The whole pass is measured -- the walk is not reassembled,
        -- because the roster did not change: that is exactly how it happens in combat.
        local ROUNDS = 2000
        local started = os.clock()
        for _ = 1, ROUNDS do
            core.Events.Dispatch("UNIT_AURA", "target")
            frame()
        end
        local perPass = (os.clock() - started) * 1000 / ROUNDS

        local buttons = 0
        for i = 1, #built do
            buttons = buttons + #mod.Units.Collect(built[i], {}, 0)
        end

        print(string.format("  [unitframe aura cost] %d icons of the target, "
            .. "the focus and five party members: %.4f ms per pass",
            buttons, perPass))

        -- A ceiling rather than an observation. A frame at 60 frames per second
        -- is 16.7 ms; a pass over eighty foreign icons must fit into 2 ms, that
        -- is into 12% of a frame. It fails if the walk of foreign frames comes
        -- back on every aura change rather than on a change of target and roster.
        T.ok(perPass < 2.0, string.format(
            "the pass over foreign icons fits into 2 ms: %.4f", perPass))

        handle.options.args.enabled.set(nil, false)
        frame()
    end

    for i = 1, 5 do _G["CompactPartyFrameMember" .. i] = nil end
    _G.TargetFrame, _G.FocusFrame, _G.PlayerFrame = nil, nil, nil
    for key, value in pairs(saved) do _G[key] = value end
end

--============================================================================
-- Part 3: walking the sources
--============================================================================

T.suite("unitframe auras: a foreign icon has one writer")

do
    local sources = {}
    local files = helpers.moduleSources(MODULE)
    for i = 1, #files do
        local handle = io.open(files[i], "r")
        if handle then
            sources[files[i]:match("[^/]+$")] = handle:read("*a")
            handle:close()
        end
    end
    T.ok(sources["Units.lua"] ~= nil, "Units.lua is named in the TOC and was read")

    local function countCode(text, needle)
        local count = 0
        for line in (text or ""):gmatch("[^\r\n]+") do
            if not line:match("^%s*%-%-") then
                local pos = 1
                while true do
                    local from = line:find(needle, pos, true)
                    if not from then break end
                    count = count + 1
                    pos = from + 1
                end
            end
        end
        return count
    end

    -- A foreign icon is hidden by alpha and only by alpha. The engine does not
    -- allow Hide on a protected icon in combat, and a deferred Hide would mean
    -- a hidden aura hanging on the target until the end of combat.
    T.eq(countCode(sources["Units.lua"], "button.Hide"), 0,
        "a foreign icon is not hidden through Hide")
    T.eq(countCode(sources["Units.lua"], "SetShown"), 0,
        "nor through SetShown")

    -- Not a single font and not a single foreign texture: the fonts of game
    -- frames belong to the core (Modules/Fonts.lua), the colour of their
    -- textures to the darkness (Modules/Darkness.lua). A second owner for one
    -- object is the very defect this project has already paid for.
    T.eq(countCode(sources["Units.lua"], "SetFont"), 0,
        "the module writes no fonts on foreign frames")
    T.eq(countCode(sources["Units.lua"], "SetVertexColor"), 0,
        "nor the colour of foreign textures")
    T.eq(countCode(sources["Units.lua"], "SetColorTexture"), 0,
        "nor fills")

    -- The border is still painted by one door for the whole module.
    local painters = 0
    for name, text in pairs(sources) do
        local hits = countCode(text, "skin.Outline(")
        if hits > 0 then
            painters = painters + hits
            T.eq(name, "Icon.lua", "only Icon.lua paints the border")
        end
    end
    T.eq(painters, 1, "and exactly one styling call paints it")

    -- The precedence is the same as in our own grid: the rule is asked inside
    -- the "the filter let it through" branch, and there is nowhere else to ask it.
    T.eq(countCode(sources["Units.lua"], "Rules.For("), 1,
        "the rule on a foreign icon is asked by exactly one call")
    local body = sources["Units.lua"]:match("function Units%.Apply%(.-\nend")
    T.ok(body ~= nil, "the body of the pass was found")
    if body then
        local allows = body:find("Filter.Allows(", 1, true)
        local ruleFor = body:find("Rules.For(", 1, true)
        T.ok(allows ~= nil and ruleFor ~= nil and allows < ruleFor,
            "and it is asked after the filter rather than before it")
    end

    -- The module grew no list of foreign names of its own: the unit frames come
    -- from the core as groups. tests/test_frameknowledge.lua guards the same
    -- thing, but there the rule is general while here the place is named.
    T.eq(countCode(sources["Units.lua"], "_G["), 0,
        "Units.lua does not reach for globals by name at all")
    T.ok(countCode(sources["Auras.lua"], "GetFrameNames") >= 2,
        "the frame names are asked of the core: both the aura grid and the unit frames")

    -- There is still one frame ticker for the whole module.
    local tickers = 0
    for name, text in pairs(sources) do
        local hits = countCode(text, "SetScript(\"OnUpdate")
        if hits > 0 then
            tickers = tickers + hits
            T.eq(name, "Auras.lua", "the only OnUpdate is in Auras.lua")
        end
    end
    T.eq(tickers, 1, "and there is still one of it: no second frame ticker appeared")
end

helpers.removeValidator()
