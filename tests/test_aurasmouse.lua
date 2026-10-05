local helpers = require("helpers")

-- The mouse on a compact aura icon (Features/Auras/Mouse.lua): a tooltip on
-- hover and cancelling your own buff with the right button.
--
-- What is checked falls into five parts, each answering its own question.
--
-- 1. The tooltip. Which client door it is taken through and what happens
--    when the client knows none of them: nothing to show means showing
--    nothing rather than leaving the description of the previous aura on screen.
--
-- 2. Cancelling. What exactly is written on the secure button, which auras
--    it is aimed at at all, and which ones never.
--
-- 3. Combat. The main promise of the file: in combat the button does
--    nothing. The engine state driver holds that promise, and it is exactly
--    what is checked here -- together with the fact that in combat the module creates no protected frames and writes no attributes.
--
-- 4. The pool. An icon returned to the pool carries nothing from the
--    previous aura, and the index on the secure button is part of that
--    "nothing" just as much as the texture: a foreign index means a foreign aura cancelled by a foreign click.
--
-- 5. The cost. The mouse is called for every shown icon of every redraw,
--    that is on the same path as the filter, and in combat. The claim "it
--    does not make that path more expensive" must be a number.

local MODULE = "Features/Auras"

helpers.installValidator()

--- The pure parts of the module in a fresh namespace.
-- @return table
local function pureNamespace()
    local ns = helpers.newNamespace()
    local _, restore = helpers.installAuraFilter()
    helpers.loadModule(MODULE, ns, { withRegistration = false })
    restore()
    return ns
end

--============================================================================
-- The fake frames
--============================================================================

--- A fake secure button.
-- It does exactly what the module asks of it.
-- @return table
local function fakeButton()
    local button = { attr = {}, scripts = {} }
    function button:SetAttribute(key, value) self.attr[key] = value end
    function button:GetAttribute(key) return self.attr[key] end
    function button:SetAllPoints(parent) self.anchoredTo = parent end
    function button:RegisterForClicks(...) self.clicks = { ... } end
    function button:EnableMouse(value) self.mouse = value and true or false end
    function button:SetScript(name, fn) self.scripts[name] = fn end
    function button:IsProtected() return true end
    return button
end

--- A fake icon.
-- @return table
local function fakeIcon()
    local icon = { record = {}, scripts = {} }
    function icon:SetScript(name, fn) self.scripts[name] = fn end
    function icon:EnableMouse(value) self.mouse = value and true or false end
    return icon
end

--============================================================================

local ns = pureNamespace()
local Mouse = ns.Mouse

T.suite("aura mouse: the tooltip is taken from the game through whichever door the client has")

do
    -- A client that knows SetUnitBuff/SetUnitDebuff: that is used, and the
    -- kind of the aura decides which one.
    local said = {}
    local tooltip = {
        SetOwner = function(_, owner) said.owner = owner end,
        SetUnitBuff = function(_, unit, index)
            said.call, said.unit, said.index = "buff", unit, index
        end,
        SetUnitDebuff = function(_, unit, index)
            said.call, said.unit, said.index = "debuff", unit, index
        end,
        Show = function() said.shown = true end,
        Hide = function() said.hidden = true end,
    }

    local icon = fakeIcon()
    T.eq(Mouse.Describe(tooltip, icon, { order = 4, harmful = false }), true,
        "the buff tooltip is shown")
    T.eq(said.call, "buff", "and taken through the buff door")
    T.eq(said.unit, "player", "for the player")
    T.eq(said.index, 4, "by the slot index of the aura")
    T.eq(said.owner, icon, "the tooltip was anchored to the icon")
    T.eq(said.shown, true, "and shown")

    T.eq(Mouse.Describe(tooltip, icon, { order = 2, harmful = true }), true,
        "the debuff tooltip is shown")
    T.eq(said.call, "debuff", "and taken through the debuff door")

    -- A client that knows only SetUnitAura: the kind of the aura is passed as a word.
    local second = {}
    local older = {
        SetOwner = function() end,
        SetUnitAura = function(_, unit, index, filter)
            second.unit, second.index, second.filter = unit, index, filter
        end,
        Show = function() second.shown = true end,
        Hide = function() second.hidden = true end,
    }
    T.eq(Mouse.Describe(older, icon, { order = 7, harmful = true }), true,
        "a client without SetUnitDebuff shows the tooltip through the second door")
    T.eq(second.filter, "HARMFUL", "and the kind of the aura is passed as a word")
    T.eq(second.index, 7, "with the same slot index")

    -- A client that knows neither: the spell id remains.
    local third = {}
    local last = {
        SetOwner = function() end,
        SetSpellByID = function(_, id) third.id = id end,
        Show = function() third.shown = true end,
        Hide = function() third.hidden = true end,
    }
    T.eq(Mouse.Describe(last, icon, { order = 1, spellId = 4242 }), true,
        "only the spell id is left -- the tooltip is shown anyway")
    T.eq(third.id, 4242, "and it is shown by the spell id")

    -- There is nothing to show with. The tooltip must disappear rather than
    -- stay from the previous aura: a foreign description under a new texture reads to the player as the truth.
    local empty = {}
    local blank = {
        SetOwner = function() end,
        Show = function() empty.shown = true end,
        Hide = function() empty.hidden = true end,
    }
    T.eq(Mouse.Describe(blank, icon, { order = 3 }), false,
        "nothing to show with -- there is no tooltip")
    T.eq(empty.shown, nil, "and nobody tried to show it")
    T.eq(empty.hidden, true, "while the previous one is hidden")

    -- Garbage instead of a tooltip or a record breaks nothing.
    T.eq(Mouse.Describe(nil, icon, { order = 1 }), false, "with no tooltip, no")
    T.eq(Mouse.Describe(blank, icon, nil), false, "with no record, no")
    T.eq(Mouse.Describe(blank, icon, {}), false,
        "without a slot index the tooltip cannot be asked for")
    Mouse.Forgo(nil)
end

T.suite("aura mouse: a buff can be cancelled, and only a buff")

do
    T.eq(Mouse.Cancellable({ order = 1, harmful = false }), true,
        "your own buff can be cancelled")
    T.eq(Mouse.Cancellable({ order = 1, harmful = true }), false,
        "a debuff cannot be removed by anything, and it gets no button")
    T.eq(Mouse.Cancellable({ harmful = false }), false,
        "without a slot index there is nothing to cancel")
    T.eq(Mouse.Cancellable({ order = 0 }), false, "slot zero is not a slot")
    T.eq(Mouse.Cancellable(nil), false, "with no record, no")
end

T.suite("aura mouse: the overlay is created once and under a state driver")

do
    local ns2 = pureNamespace()
    local Mouse2 = ns2.Mouse

    local combat, drivers, built = false, {}, 0
    Mouse2.Setup({
        InCombat = function() return combat end,
        HasDriver = function() return true end,
        Driver = function(object, attribute, condition)
            drivers[#drivers + 1] = { object, attribute, condition }
            return true
        end,
        Create = function(kind, _, parent, template)
            built = built + 1
            local button = fakeButton()
            button.kind, button.parent, button.template = kind, parent, template
            return button
        end,
    })

    -- In combat the engine will not let a protected frame be created, and the module does not try.
    combat = true
    local icon = fakeIcon()
    T.eq(Mouse2.Overlay(icon), nil, "in combat the overlay is not created")
    T.eq(built, 0, "and no frame was created")
    T.eq(icon.cancel, nil, "a refusal in combat is not remembered: out of combat we will try again")

    -- Out of combat it is created, exactly once.
    combat = false
    local button = Mouse2.Overlay(icon)
    T.ok(button ~= nil, "out of combat the overlay was created")
    T.eq(built, 1, "one frame was created")
    T.eq(button.template, "SecureActionButtonTemplate",
        "and it is a secure button: the engine allows cancelling a buff no other way")
    T.eq(button.parent, icon, "the overlay is a child of the icon")
    T.eq(button.anchoredTo, icon, "and covers it entirely")
    T.eq(button.clicks and button.clicks[1], "RightButtonUp",
        "it catches the right button")
    T.eq(Mouse2.Overlay(icon), button, "the second time the same one is returned")
    T.eq(built, 1, "and nothing is created anew")

    -- The state driver is the only thing that makes the button safe.
    T.eq(#drivers, 1, "one state driver was created")
    T.eq(drivers[1][1], button, "and it was created on the button itself")
    T.eq(drivers[1][2], "type2", "it governs the action of the right button")
    T.eq(drivers[1][3], "[combat] none; cancelaura",
        "and in combat it sets an action the engine does not know")
    T.ok(Mouse2.DRIVER:find("%[combat%]") ~= nil,
        "the driver condition speaks specifically about combat")

    -- A client with no state driver. A button without one is unsafe, and
    -- there is none at all: only the tooltip remains.
    local ns3 = pureNamespace()
    local tried = 0
    ns3.Mouse.Setup({
        HasDriver = function() return false end,
        InCombat = function() return false end,
        Create = function() tried = tried + 1 return fakeButton() end,
    })
    local bare = fakeIcon()
    T.eq(ns3.Mouse.Overlay(bare), nil, "with no state driver there is no overlay")
    T.eq(tried, 0, "and no attempt was made to create one")
    T.eq(bare.cancel, false, "the refusal is remembered: we do not try a second time")
    T.eq(ns3.Mouse.Overlay(bare), nil, "and the second time there is no overlay either")
    T.eq(tried, 0, "and still no frame was created")
end

T.suite("aura mouse: in combat the attribute is not written but queued")

do
    local ns2 = pureNamespace()
    local Mouse2 = ns2.Mouse

    local combat = false
    local queue = {}
    Mouse2.Setup({
        InCombat = function() return combat end,
        HasDriver = function() return true end,
        Driver = function() return true end,
        Create = function() return fakeButton() end,
        -- The same fork as in the core (Core/Combat.lua): combat plus the
        -- object being protected means a queue under a key.
        Secure = function(object, key, action)
            if combat and object.IsProtected and object:IsProtected() then
                queue[key] = action
                return false
            end
            action()
            return true
        end,
    })

    local icon = fakeIcon()
    local button = Mouse2.Overlay(icon)
    T.ok(button ~= nil, "the overlay exists")
    T.ok(type(button.umbraKey) == "string" and button.umbraKey ~= "",
        "the overlay has its own queue key: under a shared one forty icons would defer "
        .. "a single edit between them")

    -- Out of combat the aim is written at once.
    icon.record = { order = 5, harmful = false }
    T.eq(Mouse2.Aim(icon, icon.record), true, "out of combat the aim is written at once")
    T.eq(button.attr.unit, "player", "the button cancels an aura on the player")
    T.eq(button.attr.index, 5, "and exactly the one on the icon")

    -- A debuff gets no aim at all.
    T.eq(Mouse2.Aim(icon, { order = 2, harmful = true }), true,
        "the debuff was handled")
    T.eq(button.attr.index, nil, "but it carries no aim")
    T.eq(button.attr.unit, nil, "nor a unit: the attributes travel as a pair")

    -- In combat, the queue. The attribute stays as it was, and that is safe
    -- precisely because the button cannot be pressed in combat: see the state driver.
    Mouse2.Aim(icon, { order = 3, harmful = false })
    T.eq(button.attr.index, 3, "out of combat the aim is written again")

    combat = true
    T.eq(Mouse2.Aim(icon, { order = 9, harmful = false }), false,
        "in combat the aim is deferred")
    T.eq(button.attr.index, 3, "and the attribute did not change in combat")
    T.eq(queue[button.umbraKey] ~= nil, true, "the work went into the queue")

    -- Leaving combat: the queue runs, and the button ends up with the last
    -- state rather than the history in jerks.
    combat = false
    queue[button.umbraKey]()
    T.eq(button.attr.index, 9, "on leaving combat the aim caught up with what is shown")
end

T.suite("aura mouse: an icon returned to the pool carries no foreign aim")

do
    local ns2 = pureNamespace()
    local Mouse2, Icon = ns2.Mouse, ns2.Icon

    Mouse2.Setup({
        InCombat = function() return false end,
        HasDriver = function() return true end,
        Driver = function() return true end,
        Create = function() return fakeButton() end,
    })

    -- The icon builder is accepted by the pool from outside -- that is why it is accepted.
    local function build()
        local frame = fakeIcon()
        frame.texture   = { SetTexture = function() end }
        frame.timeText  = { SetText = function() end }
        frame.countText = { SetText = function() end }
        frame.ClearAllPoints = function() end
        frame.Hide = function() end
        frame.Show = function() end
        Mouse2.Watch(frame)
        return frame
    end

    local pool = Icon.NewPool(build)
    local frame = Icon.Acquire(pool, nil)

    Icon.SetAura(frame, { order = 6, name = "Blessing", icon = "texture",
        harmful = false, spellId = 1234 }, true, true)
    T.eq(frame.record.harmful, false, "the record knows the kind of the aura")
    T.eq(frame.record.spellId, 1234, "and the spell id")

    Mouse2.Update(frame, true)
    T.eq(frame.mouse, true, "the mouse on the icon is enabled by the setting")
    T.ok(frame.cancel ~= nil, "the overlay was created")
    T.eq(frame.cancel.attr.index, 6, "and aimed at the shown aura")

    Icon.Release(pool, frame)

    T.eq(frame.cancel.attr.index, nil,
        "the icon returned to the pool with no aim: a foreign index on the button is "
        .. "a foreign aura cancelled by a foreign click")
    T.eq(frame.cancel.attr.unit, nil, "and with no unit")

    -- And the record itself is empty -- by iteration rather than by a list of
    -- fields: new mouse fields must disappear by the same iteration as the old ones.
    local leftovers = {}
    for key in pairs(frame.record) do leftovers[#leftovers + 1] = tostring(key) end
    T.eq(#leftovers, 0, "nothing is left on the record: "
        .. table.concat(leftovers, ", "))

    -- The same icon with a new aura: its own aim, not the previous one.
    local again = Icon.Acquire(pool, nil)
    T.eq(again, frame, "the pool handed out the same icon")
    Icon.SetAura(again, { order = 2, name = "Mark", harmful = true }, true, true)
    Mouse2.Update(again, true)
    T.eq(again.cancel.attr.index, nil,
        "the debuff has no aim, although the previous aura had one")

    -- The hover handler reads the record off the icon rather than remembering
    -- the aura: otherwise it would outlive the return to the pool. It is
    -- checked with the same icon: the description is asked for about the new aura, not about the one it was set up for.
    local asked = {}
    Mouse2.Setup({ Tooltip = function()
        return {
            SetOwner = function() end,
            SetUnitDebuff = function(_, _, index) asked.index = index end,
            SetUnitBuff = function(_, _, index) asked.index = index end,
            Show = function() end, Hide = function() end,
        }
    end })
    again.scripts.OnEnter(again)
    T.eq(asked.index, 2, "the tooltip was asked about the aura that is on the icon now")

    -- The setting switched off: no tooltip and no aim.
    asked.index = nil
    Mouse2.Update(again, false)
    T.eq(again.mouse, false, "the mouse on the icon is switched off")
    again.scripts.OnEnter(again)
    T.eq(asked.index, nil, "and no tooltip is asked for")
end

T.suite("aura mouse: the cost on the hot path")

do
    local ns2 = pureNamespace()
    local Mouse2 = ns2.Mouse

    Mouse2.Setup({
        InCombat = function() return false end,
        HasDriver = function() return true end,
        Driver = function() return true end,
        Create = function() return fakeButton() end,
    })

    -- Forty icons is a full player aura grid. The mouse is called for every
    -- one of them on every redraw, and the redraw arrives in combat.
    local icons = {}
    for i = 1, 40 do
        local frame = fakeIcon()
        frame.record = { order = i, harmful = (i % 2 == 0) }
        Mouse2.Watch(frame)
        icons[i] = frame
        Mouse2.Update(frame, true)   -- the overlays are created in advance, as in game
    end

    local ROUNDS = 20000

    local function cost(enabled)
        local started = os.clock()
        for _ = 1, ROUNDS do
            for i = 1, 40 do Mouse2.Update(icons[i], enabled) end
        end
        return os.clock() - started
    end

    cost(true)
    local off = cost(false)
    local on  = cost(true)

    -- The line is named for what it is, and that is a correction rather than
    -- a quibble. Formerly it said "ms per redraw", while what is measured
    -- here is forty Mouse.Update calls on bare fake tables: no core, no
    -- styling, not a single question to the game, not the redraw itself. That
    -- number was read as the cost of redrawing the grid -- and it diverged
    -- fourfold from the cost measured on the whole addon
    -- (`.superpowers/sdd/whole-cost/report.md`). It diverged not because of a frame fake: different things were measured under one name.
    --
    -- The cost of the redraw itself lives in tests/test_aurascost.lua and is
    -- measured there by the real path -- an event, Redraw, forty icons -- and
    -- in six cases rather than one.
    io.write(string.format(
        "  [aura mouse cost] %d times 40 Mouse.Update calls (this is not "
        .. "a redraw): off %.2f ms, on %.2f ms (%.4f ms per "
        .. "forty icons)\n",
        ROUNDS, off * 1000, on * 1000, on * 1000 / ROUNDS))

    -- A ceiling in milliseconds rather than in percent: the check guards the
    -- order of magnitude -- a table, a string or an iteration returned per
    -- icon -- rather than the difference between two runs on a busy machine.
    -- The mouse on forty icons must cost less than one hundredth of a millisecond.
    T.ok(on / ROUNDS < 0.00001, string.format(
        "the mouse on forty icons costs less than 0.01 ms (%.4f ms)",
        on * 1000 / ROUNDS))

    -- And not a single table on the hot path: the aim closure is created only
    -- when the aim is actually written -- that is out of combat and only on
    -- buffs.
    T.ok(on < off * 8 + 0.05,
        "the mouse switched on does not change the order of magnitude of its own call")
end

T.suite("aura mouse: the setting, the default and a full run on a client")

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

    local combat = false

    --- A fake client frame.
    local object
    function object(kind, template)
        local o = { kind = kind, template = template, children = {},
            regions = {}, attr = {}, scripts = {}, shown = false }
        function o:Show() self.shown = true end
        function o:Hide() self.shown = false end
        function o:SetShown(v) self.shown = v and true or false end
        function o:SetPoint(point, parent) self.point, self.anchor = point, parent end
        function o:ClearAllPoints() self.point, self.anchor = nil, nil end
        function o:SetAllPoints(parent) self.anchoredTo = parent end
        function o:SetSize(w, h) self.w, self.h = w, h end
        function o:SetWidth(w) self.w = w end
        function o:SetHeight(h) self.h = h end
        function o:SetAlpha() end
        function o:SetScale() end
        function o:GetParent() return self.parent end
        function o:SetParent(value) self.parent = value end
        function o:SetScript(name, fn) self.scripts[name] = fn end
        function o:RegisterEvent() end
        function o:UnregisterEvent() end
        function o:EnableMouse(v) self.mouse = v and true or false end
        function o:RegisterForClicks(...) self.clicks = { ... } end
        function o:SetAttribute(key, value) self.attr[key] = value end
        function o:GetAttribute(key) return self.attr[key] end
        -- The engine makes protected the frame built on a secure template.
        function o:IsProtected() return self.template ~= nil end
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

    local frames = {}
    _G.CreateFrame = function(kind, _, parent, template)
        local f = object(kind, template)
        f.parent = parent
        if type(parent) == "table" and parent.children then
            parent.children[#parent.children + 1] = f
        end
        frames[#frames + 1] = f
        return f
    end

    local drivers = {}
    _G.RegisterAttributeDriver = function(frame, attribute, condition)
        drivers[frame] = { attribute, condition }
    end
    _G.InCombatLockdown = function() return combat end
    _G.SlashCmdList = {}
    _G.GetTime = function() return 1000 end
    _G.C_UnitAuras = nil
    _G.UIParent = object("Frame")

    local asked = {}
    _G.GameTooltip = {
        SetOwner = function(_, owner) asked.owner = owner end,
        SetUnitBuff = function(_, unit, index)
            asked.kind, asked.unit, asked.index = "buff", unit, index
        end,
        SetUnitDebuff = function(_, unit, index)
            asked.kind, asked.unit, asked.index = "debuff", unit, index
        end,
        Show = function() asked.shown = true end,
        Hide = function() asked.hidden = true end,
    }

    -- The player auras: two own buffs and one debuff.
    local AURAS = {
        HELPFUL = {
            { "Own buff", "icon1", 1, nil, 60, 1030, "player", nil, nil, 101 },
            { "Second",   "icon2", 1, nil, 60, 1040, "player", nil, nil, 102 },
        },
        HARMFUL = {
            { "Poison", "icon3", 1, nil, 20, 1010, "target", nil, nil, 201 },
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
        -- The default: the mouse is on. A fresh install is not changed by
        -- that at all -- the module itself is off -- while an enabled module
        -- must do the same as the standard grid it takes over.
        T.eq(handle.defaults.mouse, true, "the mouse on the icon is on by default")
        T.eq(handle.defaults.enabled, false, "while the module itself is not")

        local node = handle.options.args.mouse
        T.eq(type(node), "table", "the settings node exists")
        T.eq(node.type, "toggle", "and it is one switch, not two")
        T.ok(node.desc():find("combat") ~= nil,
            "the description tells the player about combat: otherwise they will learn about it in combat")

        core.Registry:EnableAll()

        -- The defaults are put into the live database by Core/Init.lua when it
        -- is created -- there is no database here, and the section is filled
        -- with the very defaults of the descriptor. What is checked is
        -- therefore exactly what the module declared rather than what the check added.
        local settings = handle:GetSettings()
        for key, value in pairs(handle.defaults) do settings[key] = value end

        handle.options.args.enabled.set(nil, true)

        --- The shown icons of the module.
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

        local shown = icons()
        T.eq(#shown, 3, "three auras are shown")

        --- The icon carrying this texture.
        local function iconOf(path)
            local all = icons()
            for i = 1, #all do
                if all[i].regions[1].path == path then return all[i] end
            end
            return nil
        end

        local buff = iconOf("icon1")
        local debuff = iconOf("icon3")
        T.ok(buff ~= nil and debuff ~= nil, "both icons were found")

        -- The overlay on the buff is aimed, the one on the debuff is not.
        T.ok(buff.cancel ~= nil, "the buff has a secure overlay")
        T.eq(buff.cancel.template, "SecureActionButtonTemplate",
            "and it is built on a secure template")
        T.eq(buff.cancel.attr.unit, "player", "it cancels an aura on the player")
        T.eq(buff.cancel.attr.index, 1, "and exactly the one that is shown")
        T.eq(debuff.cancel.attr.index, nil,
            "the debuff has no aim: there is nothing to remove it with")

        -- The state driver is in place on every overlay.
        local driver = drivers[buff.cancel]
        T.ok(driver ~= nil, "the state driver was created")
        T.eq(driver[1], "type2", "it governs the action of the right button")
        T.eq(driver[2], "[combat] none; cancelaura",
            "and in combat it cancels the action entirely")

        -- The tooltip is asked of the game about the aura that is on the icon.
        buff.cancel.scripts.OnEnter(buff.cancel)
        T.eq(asked.kind, "buff", "the buff tooltip")
        T.eq(asked.index, 1, "about the shown aura")
        T.eq(asked.owner, buff, "and anchored to the icon itself rather than to the overlay")
        debuff.cancel.scripts.OnEnter(debuff.cancel)
        T.eq(asked.kind, "debuff", "on a debuff, the debuff tooltip")

        -- Combat. The aura set changed, the icons moved -- but the attributes
        -- did not: the engine will not let them be written in combat. The driver keeps that from being dangerous.
        combat = true
        local before = #frames
        table.remove(AURAS.HELPFUL, 1)
        core.Events.Dispatch("UNIT_AURA", "player")

        local first = iconOf("icon2")
        T.ok(first ~= nil, "the remaining buff is shown")
        T.eq(first.cancel and first.cancel.attr.index, 1,
            "in combat the attribute stayed as it was")
        T.ok(core.Combat.PendingFor("umbraauras") > 0,
            "while the edit went into the queue until combat ends")
        T.eq(#frames, before,
            "and not a single new frame was created in combat")

        -- The tooltip works in combat: it protects nothing.
        asked.index = nil
        first.cancel.scripts.OnEnter(first.cancel)
        T.eq(asked.index, 1, "the tooltip is shown in combat")

        -- Leaving combat: the queue runs, and the aim catches up with what is shown.
        combat = false
        core.Combat.DrainFor("umbraauras")
        T.eq(first.cancel.attr.index, 1,
            "after combat the aim matches the shown aura")

        -- The setting switched off removes the aim from every icon.
        handle.options.args.mouse.set(nil, false)
        local all = icons()
        for i = 1, #all do
            T.eq(all[i].cancel and all[i].cancel.attr.index, nil,
                "there is no aim with the setting switched off")
            T.eq(all[i].mouse, false, "and the mouse on the icon is off")
        end

        -- The cost on the real aura path: a full redraw on an event, with the
        -- mouse and without. This is its most expensive case -- after
        -- ReleaseAll the aim on every icon is removed and set anew, that is
        -- no "the aim is the same" comparison fires here.
        local function redraws(times)
            local started = os.clock()
            for _ = 1, times do
                core.Events.Dispatch("UNIT_AURA", "player")
            end
            return os.clock() - started
        end

        local ROUNDS = 5000
        redraws(200)
        local without = redraws(ROUNDS)
        handle.options.args.mouse.set(nil, true)
        redraws(200)
        local with = redraws(ROUNDS)

        -- The number of icons is named in the line itself, and named
        -- deliberately: the grid here holds three auras rather than forty, and
        -- this number cannot be read as the cost of redrawing the grid. What
        -- is checked here is a ratio -- the mouse against its absence -- not a cost; the cost lives in tests/test_aurascost.lua.
        io.write(string.format(
            "  [aura cost with mouse] %d redraws of a three-icon grid on "
            .. "an event: without the mouse %.0f ms (%.4f ms per redraw), with it "
            .. "%.0f ms (%.4f ms)\n",
            ROUNDS, without * 1000, without * 1000 / ROUNDS,
            with * 1000, with * 1000 / ROUNDS))

        -- The ceiling guards the order of magnitude: the mouse may not double
        -- the cost of a redraw that arrives in combat on every aura event.
        T.ok(with < without * 1.6 + 0.05, string.format(
            "the mouse does not change the order of magnitude of the redraw cost: %.4f ms against %.4f ms",
            with * 1000 / ROUNDS, without * 1000 / ROUNDS))
    end

    for name, value in pairs(saved) do _G[name] = value end
    _G.UnitAura = saved.UnitAura
    _G.C_UnitAuras = saved.C_UnitAuras
    _G.GameTooltip = saved.GameTooltip
    _G.InCombatLockdown = saved.InCombatLockdown
    _G.RegisterAttributeDriver = saved.RegisterAttributeDriver
end
