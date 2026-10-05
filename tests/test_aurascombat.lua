local helpers = require("helpers")

-- Compact auras in combat: a grid with protected children.
--
-- Every icon now has a secure overlay (Features/Auras/Mouse.lua), that is a
-- protected child. Auras change most often precisely in combat, and a grid
-- that stopped redrawing is a far greater loss than the gain from the
-- overlay itself. One thing is checked here: the engine, forbidding in
-- combat everything it forbids, does not stop the grid from living.
--
-- === The engine rule the fake client is written from ===
--
-- docs/module-api.md §9: in combat you may not create a protected frame,
-- reparent it, move it or write an attribute on it; protection is
-- **inherited from the parent**, that is downwards. Therefore:
--
--   * an icon is an ordinary frame, and it does not become protected just
--     because it has a protected child: a protected child does not protect its parent;
--   * the overlay is protected, and everything forbidden on it in combat
--     must either not happen at all or go through the core handle:Secure.
--
-- The fake client here is exactly like that: on a protected object in combat
-- every forbidden operation **fails**, exactly as an action fails in game
-- with the yellow "Interface action failed because of an AddOn". A silent
-- fake would be confirming itself.
--
-- There are four sections, one question each.
--
-- 1. What on the layout path touches a protected object at all. The answer
--    must be "nothing but the overlay attributes, and those through the queue".
-- 2. Pool growth in combat: there are more auras than icons. An icon must
--    appear and work; only its overlay may be missing, and only until the
--    end of combat.
-- 3. Returning an icon to the pool and handing it out again in combat.
-- 4. What goes into handle:Secure. A deferred redraw is a grid frozen in
--    combat, that is the same loss by another road.

local MODULE = "Features/Auras"

helpers.installValidator()

--============================================================================
-- A fake client forbidding in combat what the engine forbids
--============================================================================

-- What the engine will not let you do to a protected object while in combat.
-- The list comes from docs/module-api.md §9.
local RESTRICTED = {
    Show = true, Hide = true, SetShown = true,
    SetPoint = true, ClearAllPoints = true, SetAllPoints = true,
    SetSize = true, SetWidth = true, SetHeight = true, SetScale = true,
    SetParent = true, SetAttribute = true,
}

--- Build the fake client.
--
-- Returns a table of outward doors: CreateFrame itself, the combat switch
-- and the tally of created frames.
-- @return table
local function newClient()
    local client = { frames = {}, combat = false, drivers = {} }

    --- Whether a template is protected in itself.
    -- By the word Secure in the name, as in game: protection comes from a
    -- secure template, not from the frame type. CooldownFrameTemplate is ordinary.
    local function secureTemplate(template)
        return type(template) == "string"
            and template:find("Secure", 1, true) ~= nil
    end

    local object

    --- An engine refusal.
    local function forbid(self, method)
        if client.combat and self.protectedFlag and RESTRICTED[method] then
            client.refused = (client.refused or 0) + 1
            error("Interface action failed because of an AddOn: " .. method
                .. " on a protected object in combat", 0)
        end
    end

    function object(kind, template, parent)
        local o = {
            kind = kind, template = template, parent = parent,
            children = {}, regions = {}, attr = {}, scripts = {},
            shown = false,
        }
        -- Protection: either an own secure template or a protected parent.
        -- It does not travel upwards, and that is the whole question of this file.
        o.protectedFlag = secureTemplate(template)
            or (type(parent) == "table" and parent.protectedFlag or false)

        function o:IsProtected() return self.protectedFlag end

        function o:Show() forbid(self, "Show") self.shown = true end
        function o:Hide() forbid(self, "Hide") self.shown = false end
        function o:SetShown(v)
            forbid(self, "SetShown")
            self.shown = v and true or false
        end
        function o:SetPoint(point, anchor, _, x, y)
            forbid(self, "SetPoint")
            self.point, self.anchor, self.x, self.y = point, anchor, x, y
        end
        function o:ClearAllPoints()
            forbid(self, "ClearAllPoints")
            self.point, self.anchor, self.x, self.y = nil, nil, nil, nil
        end
        function o:SetAllPoints(anchor)
            forbid(self, "SetAllPoints")
            self.anchoredTo = anchor
        end
        function o:SetSize(w, h) forbid(self, "SetSize") self.w, self.h = w, h end
        function o:SetWidth(w) forbid(self, "SetWidth") self.w = w end
        function o:SetHeight(h) forbid(self, "SetHeight") self.h = h end
        function o:SetScale() forbid(self, "SetScale") end
        function o:SetParent(value)
            forbid(self, "SetParent")
            self.parent = value
        end
        function o:SetAttribute(key, value)
            forbid(self, "SetAttribute")
            self.attr[key] = value
        end
        function o:GetAttribute(key) return self.attr[key] end

        function o:GetParent() return self.parent end
        function o:SetAlpha() end
        function o:SetScript(name, fn) self.scripts[name] = fn end
        function o:RegisterEvent() end
        function o:UnregisterEvent() end
        function o:EnableMouse(v) self.mouse = v and true or false end
        function o:RegisterForClicks(...) self.clicks = { ... } end

        function o:CreateTexture()
            local t = object("Texture")
            function t:SetTexture(path) self.path = path end
            function t:SetTexCoord() end
            function t:SetVertexColor() end
            function t:SetColorTexture() end
            function t:SetDrawLayer() end
            self.regions[#self.regions + 1] = t
            return t
        end
        function o:CreateFontString()
            local f = object("FontString")
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

    client.object = object

    function client.CreateFrame(kind, _, parent, template)
        local protected = secureTemplate(template)
            or (type(parent) == "table" and parent.protectedFlag or false)
        if client.combat and protected then
            client.refused = (client.refused or 0) + 1
            error("Interface action failed because of an AddOn: CreateFrame", 0)
        end
        local f = object(kind, template, parent)
        if type(parent) == "table" and parent.children then
            parent.children[#parent.children + 1] = f
        end
        client.frames[#client.frames + 1] = f
        return f
    end

    --- How many secure frames have been created so far.
    function client.secureCount()
        local n = 0
        for i = 1, #client.frames do
            if secureTemplate(client.frames[i].template) then n = n + 1 end
        end
        return n
    end

    return client
end

--============================================================================

T.suite("auras-combat: on the layout path only the overlay touches anything protected")

do
    -- There is no core here at all: only Mouse.lua is questioned, and exactly
    -- about what it does to a protected object by itself, without the core queue.
    local ns = helpers.newNamespace()
    local _, restore = helpers.installAuraFilter()
    helpers.loadModule(MODULE, ns, { withRegistration = false })
    restore()

    local client = newClient()
    local Mouse = ns.Mouse

    local deferred = {}
    local combat = true
    Mouse.Setup({
        Secure = function(object, key, action)
            -- The core rule in full: what is deferred is the pair "combat AND
            -- the object answers IsProtected".
            local protected = type(object) == "table"
                and type(object.IsProtected) == "function"
                and object:IsProtected() or false
            if combat and protected then
                deferred[key] = action
                return false
            end
            action()
            return true
        end,
        InCombat = function() return combat end,
        Create = function(kind, name, parent, template)
            local ok, frame = pcall(client.CreateFrame, kind, name, parent,
                template)
            return ok and frame or nil
        end,
        Driver = function(frame, attribute, condition)
            client.drivers[frame] = { attribute, condition }
            return true
        end,
        HasDriver = function() return true end,
    })

    -- In combat the overlay is not created at all, and "no" here means "we
    -- will try later", not "never": the cancel field stays empty.
    local icon = client.object("Frame", nil, nil)
    icon.record = {}
    T.eq(Mouse.Overlay(icon), nil, "in combat the overlay is not created")
    T.eq(icon.cancel, nil, "and the refusal is not remembered forever")
    T.eq(#client.frames, 0, "not a single frame was created in combat")

    -- Out of combat it is created, once.
    combat = false
    local button = Mouse.Overlay(icon)
    T.ok(button ~= nil, "out of combat the overlay is created")
    T.eq(button.template, "SecureActionButtonTemplate", "on a secure template")
    T.eq(button:IsProtected(), true, "and the engine considers it protected")
    T.eq(icon:IsProtected(), false,
        "while the icon itself is not: protection goes from parent down, not up")
    T.eq(Mouse.Overlay(icon), button, "a repeated call gives the same overlay")

    -- Out of combat the aim is written at once.
    icon.record = { order = 3, harmful = false }
    T.eq(Mouse.Aim(icon, icon.record), true, "out of combat the aim is written at once")
    T.eq(button.attr.index, 3, "with the index of the shown aura")

    -- In combat it is not written but queued under the key of this button.
    combat = true
    icon.record = { order = 5, harmful = false }
    T.eq(Mouse.Aim(icon, icon.record), false, "in combat the aim is deferred")
    T.eq(button.attr.index, 3, "the attribute is untouched in combat")
    T.ok(deferred[button.umbraKey] ~= nil, "and it sits under the key of this button")

    -- The icon meanwhile moves and hides in combat like an ordinary frame:
    -- nothing fails on it, because it is not protected.
    ns.Icon.Place(icon, nil, "TOPLEFT", 10, -10, 24)
    T.eq(icon.w, 24, "the icon changes size in combat")
    icon:Hide()
    T.eq(icon.shown, false, "and hides")
    T.eq(client.refused, nil, "the engine did not refuse once")

    -- Leaving combat: the deferred work catches up.
    combat = false
    deferred[button.umbraKey]()
    T.eq(button.attr.index, 5, "after combat the aim matches what is shown")
end

--============================================================================

T.suite("auras-combat: the grid redraws, grows and is reused in combat")

do
    local saved = {
        Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        UnitAura = _G.UnitAura, C_UnitAuras = _G.C_UnitAuras,
        GetTime = _G.GetTime, CreateFrame = _G.CreateFrame,
        UIParent = _G.UIParent, GameTooltip = _G.GameTooltip,
        InCombatLockdown = _G.InCombatLockdown,
        RegisterAttributeDriver = _G.RegisterAttributeDriver,
    }

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

    local client = newClient()

    _G.CreateFrame = client.CreateFrame
    _G.RegisterAttributeDriver = function(frame, attribute, condition)
        client.drivers[frame] = { attribute, condition }
    end
    _G.InCombatLockdown = function() return client.combat end
    _G.SlashCmdList = {}
    _G.GetTime = function() return 1000 end
    _G.C_UnitAuras = nil
    _G.UIParent = client.object("Frame")
    _G.GameTooltip = {
        SetOwner = function() end,
        SetUnitBuff = function() end,
        SetUnitDebuff = function() end,
        Show = function() end,
        Hide = function() end,
    }

    -- The player auras. The set is edited right here: combat IS a changing set.
    local AURAS = {
        HELPFUL = {
            { "First", "icon1", 1, nil, 60, 1030, "player", nil, nil, 101 },
            { "Second", "icon2", 1, nil, 60, 1040, "player", nil, nil, 102 },
        },
        HARMFUL = {
            { "Poison", "poison", 1, nil, 20, 1010, "target", nil, nil, 201 },
        },
    }
    _G.UnitAura = function(_, index, filter)
        local aura = AURAS[filter] and AURAS[filter][index]
        if not aura then return nil end
        return aura[1], aura[2], aura[3], aura[4], aura[5], aura[6], aura[7],
            aura[8], aura[9], aura[10]
    end

    local mod = helpers.newNamespace()
    helpers.loadModule(MODULE, mod)

    local handle = core.Registry:Get("umbraauras")
    T.ok(handle ~= nil, "the module is registered: " .. table.concat(said, " | "))

    if handle then
        core.Registry:EnableAll()

        local settings = handle:GetSettings()
        for key, value in pairs(handle.defaults) do settings[key] = value end
        handle.options.args.enabled.set(nil, true)

        --- The shown icons.
        local function icons()
            local out = {}
            for i = 1, #_G.UIParent.children do
                local child = _G.UIParent.children[i]
                if child.shown and child.regions[1] ~= nil
                    and child.regions[1].path then
                    out[#out + 1] = child
                end
            end
            return out
        end

        --- The icon carrying this texture.
        local function iconOf(path)
            local all = icons()
            for i = 1, #all do
                if all[i].regions[1].path == path then return all[i] end
            end
            return nil
        end

        --- Redraw the grid by an event, as in game.
        local function redraw()
            core.Events.Dispatch("UNIT_AURA", "player")
        end

        --- Is the module alive? The core swallows a failing handler and
        -- disables the module, and without this question "there was no error" would mean "it is not visible".
        local function alive(msg)
            T.eq(core.Registry:IsFailed("umbraauras"), false,
                msg .. ": " .. (said[#said] or "the module was not disabled"))
        end

        alive("the first draw out of combat")
        T.eq(#icons(), 3, "out of combat three auras are shown")

        local buff = iconOf("icon1")
        T.ok(buff ~= nil and buff.cancel ~= nil, "the buff has an overlay")
        T.eq(buff.cancel:IsProtected(), true, "the overlay is protected by the engine")
        T.eq(buff:IsProtected(), false, "while the icon under it is not")
        T.eq(buff.cancel.attr.index, 1, "and it is aimed at the shown aura")

        -- === 1. Redrawing in combat ==============================================
        --
        -- The same set, the same icons, each with a protected child. A full
        -- redraw goes through: ReleaseAll hides and unanchors the icons, Fill
        -- places them again -- all of it on unprotected objects.
        client.combat = true
        client.refused = nil
        local secureBefore = client.secureCount()

        redraw()
        alive("a redraw in combat")
        T.eq(client.refused, nil,
            "the engine refused no operation of the redraw")
        T.eq(#icons(), 3, "in combat the same three auras are shown")
        T.eq(client.secureCount(), secureBefore,
            "and not a single secure button was created in combat")

        -- The grid really did redraw rather than freeze: an aura left, there
        -- are fewer icons, and the remaining ones moved.
        table.remove(AURAS.HELPFUL, 1)
        redraw()
        alive("a redraw in combat after the set changed")
        T.eq(#icons(), 2, "in combat the grid shrank to the new set")
        local moved = iconOf("icon2")
        T.ok(moved ~= nil, "the remaining buff is shown")
        T.eq(moved.x, 0, "and moved to the first place of the block")
        T.eq(client.refused, nil, "and again not a single engine refusal")

        -- === 4. What went into the queue =========================================
        --
        -- Only the overlay attribute writes may be deferred. A deferred redraw
        -- is a grid frozen in combat, that is exactly the loss everything here
        -- was written against.
        local queue = core.Combat.queues["umbraauras"]
        T.ok(queue ~= nil and #queue.order > 0,
            "the overlay attribute write is deferred in combat")
        local onlyButtons = true
        for i = 1, #queue.order do
            if not tostring(queue.order[i]):find("^cancel:") then
                onlyButtons = false
            end
        end
        T.eq(onlyButtons, true,
            "and the queue holds nothing but overlay aiming")

        -- === 2. Pool growth in combat ===========================================
        --
        -- There are more auras than built icons. An icon must appear and work:
        -- texture, place, time, tooltip. Only its overlay may be missing --
        -- the engine will not let it be created in combat.
        for i = 1, 4 do
            AURAS.HELPFUL[#AURAS.HELPFUL + 1] = {
                "New " .. i, "new" .. i, 1, nil, 60, 1050 + i, "player",
                nil, nil, 300 + i,
            }
        end

        local builtBefore = #client.frames
        redraw()
        alive("pool growth in combat")
        T.eq(client.refused, nil, "pool growth got not a single refusal")
        T.eq(#icons(), 6, "all six auras are shown")
        T.ok(#client.frames > builtBefore, "the new icons really were built")
        T.eq(client.secureCount(), secureBefore,
            "and not a single secure button was created doing so")

        -- Specifically an icon born in combat, not the first one at hand: the
        -- pool hands out the already built ones first, and those have overlays.
        local fresh
        for i = builtBefore + 1, #client.frames do
            local f = client.frames[i]
            if f.regions[1] ~= nil and f.regions[1].path then fresh = f end
        end
        T.ok(fresh ~= nil, "the icon born in combat is shown")
        T.eq(fresh and fresh.shown, true, "it is shown")
        T.ok(fresh and fresh.regions[1].path ~= nil, "with the texture of its own aura")
        T.ok(fresh and fresh.w ~= nil and fresh.w > 0, "and with a size")
        T.eq(fresh and fresh.anchor ~= nil, true,
            "and anchored to the block holder")
        T.eq(fresh and fresh.cancel, nil,
            "it has no overlay: the engine will not let one be created in combat")
        T.eq(fresh and fresh.mouse, true,
            "but the mouse on it is enabled -- the tooltip works in combat")

        -- The tooltip on such an icon comes from the icon itself, not from the overlay.
        T.eq(type(fresh.scripts.OnEnter), "function",
            "the hover handler is on the icon even without an overlay")
        T.eq(pcall(fresh.scripts.OnEnter, fresh), true,
            "and is called without error")

        -- === 3. Return to the pool and a fresh handout in combat =================
        --
        -- An icon with an aimed overlay goes into the pool and is handed out
        -- for a different aura. In combat the attribute is not written -- but
        -- neither does it stay foreign forever: the requested state sits in the queue under this button's key.
        local reused = iconOf("icon2")
        local reusedButton = reused and reused.cancel
        T.ok(reusedButton ~= nil, "the reused icon has an overlay")

        -- The buffs ran out entirely: this icon will now show a debuff.
        for i = #AURAS.HELPFUL, 1, -1 do AURAS.HELPFUL[i] = nil end
        AURAS.HARMFUL[2] = { "Burn", "burn", 1, nil, 30, 1020, "target",
            nil, nil, 202 }

        client.refused = nil
        redraw()
        alive("returning and handing out an icon in combat")
        T.eq(client.refused, nil, "returning an icon to the pool did not refuse once")
        T.eq(#icons(), 2, "two debuffs are shown")

        -- A debuff cannot be cancelled by the player, so there must be no aim
        -- -- and it is already requested, merely waiting for combat to end.
        T.eq(reusedButton.attr.index, 1,
            "in combat the attribute stayed as it was: the engine will not let it be written")

        -- === Leaving combat =====================================================
        --
        -- The queue is run by the core, then the module redraws the grid:
        -- without that redraw an icon born in combat would stay without an
        -- overlay until the next aura change, that is possibly for a long time.
        client.combat = false
        core.Events.Dispatch("PLAYER_REGEN_ENABLED")
        alive("leaving combat")

        T.eq(reusedButton.attr.index, nil,
            "after combat there is no foreign aim on the button")
        T.eq(reusedButton.attr.unit, nil, "and no unit either")
        T.eq(core.Combat.PendingFor("umbraauras"), 0,
            "the combat queue is drained")

        -- The overlays caught up with the icons born in combat.
        AURAS.HELPFUL[1] = { "After combat", "after", 1, nil, 60, 1060, "player",
            nil, nil, 400 }
        redraw()
        local after = iconOf("after")
        T.ok(after ~= nil, "the buff after combat is shown")
        T.ok(after.cancel ~= nil, "and an overlay was created on it")
        T.eq(after.cancel.attr.index, 1, "and aimed at the shown aura")

        -- And now the same thing but without a single aura change after
        -- combat: the icon was born in combat, combat ended, the auras are the same. The overlay must exist.
        client.combat = true
        local lateBefore = #client.frames
        for i = 1, 6 do
            AURAS.HELPFUL[#AURAS.HELPFUL + 1] = {
                "Late " .. i, "late" .. i, 1, nil, 60, 1070 + i,
                "player", nil, nil, 500 + i,
            }
        end
        redraw()
        alive("late pool growth in combat")

        local late
        for i = lateBefore + 1, #client.frames do
            local f = client.frames[i]
            if f.regions[1] ~= nil and f.regions[1].path then late = f end
        end
        T.ok(late ~= nil, "the late icon was built and shown in combat")
        T.eq(late and late.cancel, nil, "and in combat it has no overlay")

        -- The aura set does not change by one after combat: the only thing
        -- that can create the overlay is the redraw on leaving combat.
        client.combat = false
        core.Events.Dispatch("PLAYER_REGEN_ENABLED")
        alive("the redraw on leaving combat")
        T.ok(late and late.cancel ~= nil,
            "on leaving combat the overlay was created without a single aura change")
        T.ok(late and client.drivers[late.cancel] ~= nil,
            "and it carries a state driver: there is no such button without one")

        -- And not only for that one: after combat every shown icon has an
        -- overlay, aimed at exactly the aura written on the icon.
        local allHaveOverlay, allAimed = true, true
        local shownAfter = icons()
        for i = 1, #shownAfter do
            local icon = shownAfter[i]
            if type(icon.cancel) ~= "table" then allHaveOverlay = false end
            local want = (not icon.record.harmful) and icon.record.order or nil
            if icon.cancel and icon.cancel.attr.index ~= want then
                allAimed = false
            end
        end
        T.ok(#shownAfter > 0, "after combat the grid is not empty")
        T.eq(allHaveOverlay, true, "every shown icon has an overlay")
        T.eq(allAimed, true,
            "and each is aimed at its own aura: a buff by index, "
            .. "a debuff not at all")
    end

    for name, value in pairs(saved) do _G[name] = value end
    _G.UnitAura = saved.UnitAura
    _G.C_UnitAuras = saved.C_UnitAuras
    _G.GameTooltip = saved.GameTooltip
    _G.InCombatLockdown = saved.InCombatLockdown
    _G.RegisterAttributeDriver = saved.RegisterAttributeDriver
end
