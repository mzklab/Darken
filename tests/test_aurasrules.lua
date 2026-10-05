local helpers = require("helpers")

-- Rules for an individual aura (Features/Auras/Rules.lua): an icon size of
-- its own, a border colour of its own and a sound when it expires.
--
-- Six questions are checked, and each has its own section.
--
-- 1. The pure part: parsing the list through the core door, the player
--    editing the list, compiling into two dictionaries, the precedence
--    between rules, the size bounds.
-- 2. The expiry memory: what counts as an expiry and what does not. It is the
--    only thing in the module that happens on a transition, and it fails loudly.
-- 3. The live path on a fake client: a rule by id and by name, an aura under
--    two rules, a rule that named nobody, a grid that did not shift, and an
--    icon returned to the pool after a rule.
-- 4. The filter outranks a rule: a rule neither shows what is hidden nor hides what is shown.
-- 5. The sound: exactly once on a real expiry, never on a filter edit and
--    never on entering the world.
-- 6. Combat, the cost and the source walk: a rule does not touch anything
--    protected, the redraw cost does not change its order of magnitude, and
--    there is still a single writer of the size and the colour.

local MODULE = "Features/Auras"

helpers.installValidator()

--- The pure parts of the module in a fresh namespace.
-- @return table
local function pureNamespace()
    local ns = helpers.newNamespace()
    local coreFilter, restore = helpers.installAuraFilter()
    helpers.loadModule(MODULE, ns, { withRegistration = false })
    restore()
    ns.coreFilter = coreFilter
    return ns
end

local pure = pureNamespace()

T.suite("aura rules: the list is parsed by the core rather than by us")

do
    local Rules = pure.Rules
    local shared = pure.coreFilter

    T.eq(type(Rules), "table", "the rules are present in the module namespace")

    -- Parsing the list and the name key are the very same core functions as
    -- the filter uses. Not "the same kind" but the same ones: a copy would
    -- diverge silently, and one and the same string would mean different things in two fields of one window.
    T.eq(Rules.Split, shared.Split, "parsing the rule list is the core one")
    T.eq(Rules.Key, shared.Key, "and so is the name key")
    T.eq(Rules.Split, pure.Filter.Split, "and it is the same one the module filter uses")

    -- An id and a name differ by the shape of the entry rather than by a separate setting.
    local ids, names, count = Rules.Split("12345, Bloodletting")
    T.eq(count, 2, "an id and a name live in one field")
    T.eq(ids[12345], true, "the id went into the dictionary of ids")
    T.eq(names["bloodletting"], true, "and the name as a folded key")
end

T.suite("aura rules: the player editing the list")

do
    local Rules = pure.Rules
    local list = {}

    T.eq(select(2, Rules.Add(list, "  ", "1")), "noname", "a name is required")
    T.eq(select(2, Rules.Add(list, "Shields", "   ,, ")), "notext",
        "a list of spells is required")
    T.eq(select(2, Rules.Add(list, string.rep("a", Rules.MAX_NAME + 1), "1")),
        "long", "an over-long name is not accepted")

    local rule = Rules.Add(list, "Shields", "17, Power Word: Shield")
    T.ok(rule ~= nil, "the rule was created")
    T.eq(#list, 1, "and went into the list")
    T.eq(rule.scale, Rules.SCALE.default, "the size on creation is the ordinary one")
    T.eq(rule.color, nil, "there is no colour on creation")
    T.eq(rule.sound, nil, "and no sound either")

    T.eq(select(2, Rules.Add(list, "shields", "1")), "taken",
        "a name is not repeated, and the case does not help here")

    -- The size: bounds rather than taste. Garbage means the default.
    Rules.SetScale(list, "Shields", 99)
    T.eq(rule.scale, Rules.SCALE.max, "the size is clamped to the upper bound")
    Rules.SetScale(list, "Shields", 0)
    T.eq(rule.scale, Rules.SCALE.min, "and to the lower one")
    Rules.SetScale(list, "Shields", "garbage")
    T.eq(rule.scale, Rules.SCALE.default, "garbage means the default")

    Rules.SetColor(list, "Shields", "lilac")
    T.eq(rule.color, "lilac", "the border colour is a name from the palette")
    Rules.SetColor(list, "Shields", nil)
    T.eq(rule.color, nil, "and is cleared the same way")

    Rules.SetSound(list, "Shields", true)
    T.eq(rule.sound, true, "the sound is turned on")
    Rules.SetSound(list, "Shields", false)
    T.eq(rule.sound, nil, "and is turned off for good rather than to false")

    -- Renaming and reordering.
    Rules.Add(list, "Poisons", "Poison")
    T.eq(Rules.Move(list, "Poisons", -1), true, "a rule moves up one step")
    T.eq(list[1].name, "Poisons", "and ends up first")
    T.eq(Rules.Move(list, "Poisons", -1), false, "there is no move above the first place")
    T.eq(Rules.Move(list, "Poisons", 3), false, "and a step is only ever one place")

    T.eq(Rules.Rename(list, "Poisons", "Shields"), false, "a taken name is not accepted")
    T.eq(Rules.Rename(list, "Poisons", "Venoms"), true, "a free one is accepted")
    T.eq(Rules.Remove(list, "Venoms"), true, "the rule is forgotten")
    T.eq(#list, 1, "and leaves the list")
    T.eq(Rules.Remove(list, "Venoms"), false, "there is nothing to forget a second time")

    -- The limit on the number of rules: the list goes into SavedVariables and
    -- is shown as a select list.
    local many = {}
    for i = 1, Rules.MAX do Rules.Add(many, "r" .. i, tostring(i)) end
    T.eq(select(2, Rules.Add(many, "extra", "999")), "full",
        "no rule is created beyond the limit")
end

T.suite("aura rules: compiling and precedence")

do
    local Rules = pure.Rules

    -- A fresh install: there are no rules, and the hot path pays for nothing.
    local empty = Rules.Compile(nil)
    T.eq(Rules.Any(empty), false, "with no list there are no active rules")
    T.eq(Rules.NeedsKey(empty), false, "and the name key is not needed")
    T.eq(Rules.HasSound(empty), false, "and the expiry memory is not needed")

    -- A rule that changes nothing does not make it into the plan: it costs as
    -- much as an active one and does zero.
    local idle = Rules.Compile({ { name = "empty", text = "111" } })
    T.eq(Rules.Any(idle), false, "a rule with no size, colour or sound does not count")

    -- A rule made of ids alone does not require the name key: the key is a new
    -- string for every aura of every refresh.
    local byIds = Rules.Compile({ { name = "n", text = "111,222", scale = 1.5 } })
    T.eq(Rules.Any(byIds), true, "a rule by ids is active")
    T.eq(Rules.NeedsKey(byIds), false, "while it does not need the name key")
    T.eq(Rules.For(byIds, nil, 111).scale, 1.5, "and it is decided by the id")
    T.eq(Rules.For(byIds, nil, 333), nil, "a foreign id finds no rule")

    -- A rule by name: the case is folded by the core.
    local byName = Rules.Compile({
        { name = "n", text = "Bloodletting", color = "lilac" },
    })
    T.eq(Rules.NeedsKey(byName), true, "a rule with a name needs the key")
    T.ok(Rules.For(byName, Rules.Key("bloodletting"), nil) ~= nil,
        "a name is found in any case")

    -- An aura under two rules: the one standing earlier in the list wins.
    -- They contend differently -- one named it by id, the other by name.
    local both = Rules.Compile({
        { name = "first", text = "Rend",  scale = 1.5 },
        { name = "second", text = "12345", scale = 0.5 },
    })
    local won = Rules.For(both, Rules.Key("Rend"), 12345)
    T.eq(won.name, "first", "the contest is decided by the rule place in the list")
    T.eq(won.scale, 1.5, "and the aura gets exactly its size")

    -- The same contest the other way round: the rule by id stands earlier.
    local flipped = Rules.Compile({
        { name = "by id",  text = "12345", scale = 0.5 },
        { name = "by name", text = "Rend", scale = 1.5 },
    })
    T.eq(Rules.For(flipped, Rules.Key("Rend"), 12345).name, "by id",
        "and the same thing decides when the rules swap places")

    -- Two rules naming the same thing in one dictionary: the first one takes it.
    local twice = Rules.Compile({
        { name = "earlier", text = "777", scale = 1.5 },
        { name = "later", text = "777", scale = 0.5 },
    })
    T.eq(Rules.For(twice, nil, 777).name, "earlier",
        "the dictionary is taken by the first rule that named it")
    -- What counts is what was named rather than what was written: the second
    -- rule took nothing in the dictionary, and counting it as active would
    -- promise the player a rule that decides no aura at all.
    T.eq(twice.count, 1, "the second rule took nothing and does not count")

    -- A rule that named no shown aura changes nothing and does not get in the
    -- way of the rest.
    local nobody = Rules.Compile({
        { name = "miss", text = "999999", scale = 2 },
        { name = "hit", text = "101", scale = 1.5 },
    })
    T.eq(Rules.For(nobody, nil, 202), nil, "an unnamed aura has no rule")
    T.eq(Rules.For(nobody, nil, 101).scale, 1.5, "while a named one has its own")

    -- A corrupt entry in the saved file -- people edit it by hand -- is skipped.
    local junk = Rules.Compile({ 42, "a string", {}, { text = "1", scale = 2 } })
    T.eq(junk.count, 1, "garbage in the list does not break the compilation")
end

T.suite("aura rules: the icon size and its place in the cell")

do
    local Rules, Layout = pure.Rules, pure.Layout

    -- The size is a multiplier on the common one rather than a number of its
    -- own: otherwise a named aura would come loose from the slider the player just moved.
    T.eq(Rules.Size(nil, 30), 30, "with no rule it is the common size")
    T.eq(Rules.Size({ scale = 1.5 }, 30), 45, "a rule multiplies")
    T.eq(Rules.Size({ scale = 0.5 }, 30), 15, "downwards as well")
    T.eq(Rules.Size({ scale = 2 }, 12), 24, "the multiplier is taken from the common size")
    T.eq(Rules.Size({ scale = 0.5 }, 12), Rules.MIN_SIZE,
        "an icon does not go below the readable size")
    T.eq(Rules.Size({ scale = 1.5 }, 25), 38, "the size is a whole number of pixels")
    T.eq(Rules.Size(nil, "garbage"), Layout.BOUNDS.size.default,
        "garbage instead of the common size gives the default")

    -- A grid cell does not depend on the rules at all: an icon of a different
    -- size stands in the middle of its own cell, and the neighbours do not move.
    local dx, dy = Layout.Inset(30, 30, "downleft")
    T.eq(dx, 0, "an icon of the ordinary size is not shifted")
    T.eq(dy, 0, "neither horizontally nor vertically")

    dx, dy = Layout.Inset(30, 20, "downleft")
    T.eq(dx, -5, "a smaller icon moves inwards within the cell")
    T.eq(dy, -5, "equally on both sides")

    dx, dy = Layout.Inset(30, 20, "upright")
    T.eq(dx, 5, "the sign of the shift sets the direction of growth")
    T.eq(dy, 5, "and vertically too")

    dx = Layout.Inset(30, 40, "downleft")
    T.eq(dx, 5, "a larger icon sticks out of the cell equally on both sides")

    -- The place in the grid and the size of the block know nothing about the
    -- rules: the common icon size computes them, and the set of auras does not move the grid.
    T.eq(Layout.Place(2, 12, 30, 4, "downleft"), -34,
        "the place of the second icon follows the common size")
    local w, h = Layout.Block(2, 12, 30, 4)
    T.eq(w, 64, "and so does the width of the block")
    T.eq(h, 30, "and the height")
end

T.suite("aura rules: what counts as an expiry")

do
    local Rules = pure.Rules

    local watch = Rules.NewWatch()

    -- The first set is only remembered: there is nothing to compare with, and
    -- enabling the module has no right to sound like forty expired auras.
    Rules.Watch(watch, 101)
    Rules.Watch(watch, 102)
    T.eq(Rules.Settle(watch), 0, "the first set yields no expiries")

    -- The same set -- nothing expired.
    Rules.Watch(watch, 101)
    Rules.Watch(watch, 102)
    T.eq(Rules.Settle(watch), 0, "an unchanged set yields no expiries")

    -- Refreshing an aura is the same spell id: a new duration does not count
    -- as an expiry.
    Rules.Watch(watch, 101)
    Rules.Watch(watch, 102)
    Rules.Watch(watch, 103)
    T.eq(Rules.Settle(watch), 0, "a new aura appearing is not an expiry")

    -- One went away.
    Rules.Watch(watch, 101)
    Rules.Watch(watch, 103)
    T.eq(Rules.Settle(watch), 1, "an aura that went away is one expiry")

    -- Two went away at once: the answer is one per set rather than one per aura.
    T.eq(Rules.Settle(watch), 2, "an empty set after two auras is two expiries")

    -- Unarming: everything seen is forgotten, and the first set after it is
    -- again only remembered.
    Rules.Watch(watch, 201)
    Rules.Settle(watch)
    Rules.Disarm(watch)
    T.eq(Rules.Settle(watch), 0, "after unarming there are no expiries")
    Rules.Watch(watch, 201)
    T.eq(Rules.Settle(watch), 0, "and the next set is only remembered")
    T.eq(Rules.Settle(watch), 1, "while after that an expiry is visible")

    -- The name of an aura in the memory is the spell id, and the name key when
    -- there is none. The icon does not enter that name at all, and so the pool
    -- cannot fake an expiry.
    T.eq(Rules.Token(101, "shield"), 101, "the spell id outranks the name")
    T.eq(Rules.Token(nil, "shield"), "shield", "with no id it is the name key")
    T.eq(Rules.Token(0, nil), nil, "neither an id nor a name -- nothing to call it by")
    T.eq(Rules.Token("garbage", ""), nil, "and garbage is nothing to call it by either")

    -- The sound plays at most once per redraw, however many auras expired:
    -- three sounds at once add up to noise.
    local played = 0
    Rules.Setup({ Play = function() played = played + 1 return true end })
    T.eq(Rules.Play(0), false, "zero expiries means zero sounds")
    T.eq(played, 0, "and the outward door is untouched")
    Rules.Play(5)
    T.eq(played, 1, "five expiries means one sound")
end

-- === The fake client ========================================================
--
-- The same one as in tests/test_aurascombat.lua, and for the same reason: in
-- combat every engine-forbidden operation on a protected object must fail,
-- otherwise the fake confirms itself. Here it also remembers the colour of the
-- textures -- there is otherwise nothing to read a rule border with.

local RESTRICTED = {
    Show = true, Hide = true, SetShown = true,
    SetPoint = true, ClearAllPoints = true, SetAllPoints = true,
    SetSize = true, SetWidth = true, SetHeight = true, SetScale = true,
    SetParent = true, SetAttribute = true,
}

local function newClient()
    local client = { frames = {}, combat = false, drivers = {} }

    local function secureTemplate(template)
        return type(template) == "string"
            and template:find("Secure", 1, true) ~= nil
    end

    local object

    local function forbid(self, method)
        if client.combat and self.protectedFlag and RESTRICTED[method] then
            client.refused = (client.refused or 0) + 1
            error("Interface action failed because of an AddOn: " .. method, 0)
        end
    end

    function object(kind, template, parent)
        local o = {
            kind = kind, template = template, parent = parent,
            children = {}, regions = {}, attr = {}, scripts = {},
            shown = false,
        }
        o.protectedFlag = secureTemplate(template)
            or (type(parent) == "table" and parent.protectedFlag or false)

        function o:IsProtected() return self.protectedFlag end

        function o:Show() forbid(self, "Show") self.shown = true end
        function o:Hide() forbid(self, "Hide") self.shown = false end
        function o:SetShown(v)
            forbid(self, "SetShown")
            self.shown = v and true or false
        end
        function o:IsShown() return self.shown end
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
            function t:SetColorTexture(r, g, b, a)
                self.r, self.g, self.b, self.a = r, g, b, a
            end
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
            function f:SetFont(path, height) self.height = height end
            function f:GetFont() return "font", self.height or 10, "" end
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

    return client
end

--============================================================================

T.suite("aura rules: the live path on a fake client")

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
        SetOwner = function() end, SetUnitBuff = function() end,
        SetUnitDebuff = function() end, Show = function() end,
        Hide = function() end,
    }

    -- The player auras. The seventh value is the source, the tenth is the spell id.
    local AURAS = {
        HELPFUL = {
            { "Shield",   "shield",   1, nil, 60, 1060, "player", nil, nil, 101 },
            { "Boon", "boon", 1, nil, 60, 1060, "player", nil, nil, 102 },
            { "Rend",  "rend",  1, nil, 60, 1060, "player", nil, nil, 103 },
        },
        HARMFUL = {
            { "Poison", "poison", 1, nil, 20, 1020, "target", nil, nil, 201 },
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

    local played = 0
    mod.Rules.Setup({ Play = function() played = played + 1 return true end })

    local handle = core.Registry:Get("umbraauras")
    T.ok(handle ~= nil, "the module is registered: " .. table.concat(said, " | "))

    if handle then
        -- The default: there are no rules, and a fresh install changes nothing.
        T.eq(type(handle.defaults.rules), "table", "the rules default is a table")
        T.eq(next(handle.defaults.rules), nil, "and it is empty")

        -- Every new node of the rule editor is in place.
        local args = handle.options.args
        local NEW = {
            "rulesList", "rulePick", "ruleNew", "ruleName", "ruleText",
            "ruleSize", "ruleRecolor", "ruleColor", "ruleSound", "ruleAdd",
            "ruleUp", "ruleDown", "ruleForget",
        }
        for i = 1, #NEW do
            T.eq(type(args[NEW[i]]), "table", "the node exists: " .. NEW[i])
        end

        core.Registry:EnableAll()
        local settings = handle:GetSettings()
        for key, value in pairs(handle.defaults) do settings[key] = value end
        settings.rules = {}
        args.enabled.set(nil, true)

        --- Every icon of the module, shown or not.
        local function icons()
            local out = {}
            for i = 1, #_G.UIParent.children do
                local child = _G.UIParent.children[i]
                if child.regions[1] ~= nil
                    and type(child.regions[1].SetTexture) == "function" then
                    out[#out + 1] = child
                end
            end
            return out
        end

        --- The shown icon carrying this image.
        local function iconOf(path)
            local all = icons()
            for i = 1, #all do
                if all[i].shown and all[i].regions[1].path == path then
                    return all[i]
                end
            end
            return nil
        end

        --- What the player sees on the screen.
        local function shown()
            local out = {}
            local all = icons()
            for i = 1, #all do
                if all[i].shown and all[i].regions[1].path then
                    out[#out + 1] = all[i].regions[1].path
                end
            end
            table.sort(out)
            return out
        end

        --- The colour of the icon border as the engine sees it.
        -- The border is built by the core skinning and is read from the same
        -- place: the module creates no four textures of its own.
        local function border(icon)
            local set = icon and icon.umbraAuraBorder
            local side = set and set.TOP
            if type(side) ~= "table" then return nil end
            return side.r, side.g, side.b
        end

        local function sameColor(icon, name)
            local r, g, b = border(icon)
            local pr, pg, pb = core.Skin.Get(name)
            return r == pr and g == pg and b == pb
        end

        local function redraw() core.Events.Dispatch("UNIT_AURA", "player") end

        local function alive(msg)
            T.eq(core.Registry:IsFailed("umbraauras"), false,
                msg .. ": " .. (said[#said] or "the module is not disabled"))
        end

        alive("the first draw with no rules")
        T.eq(#shown(), 4, "with no rules all four auras are shown")

        -- What the grid looks like with no rules: that is the yardstick
        -- everything else is compared against.
        local size = mod.Layout.Grid(settings)
        local plain = iconOf("boon")
        T.ok(plain ~= nil, "the icon was found")
        T.eq(plain.w, size, "and it is of the ordinary size")
        T.eq(sameColor(plain, mod.Icon.BORDER_COLOR), true,
            "and has the ordinary border")

        local holder = plain.anchor
        local plainX, plainY = plain.x, plain.y
        local holderW, holderH = holder.w, holder.h

        -- === A rule by spell id ===========================================
        settings.rules = {
            { name = "Shield", text = "101", scale = 1.5, color = "lilac" },
        }
        handle:Apply()
        alive("a rule by id")

        local ruled = iconOf("shield")
        T.ok(ruled ~= nil, "the aura under the rule is still shown")
        T.eq(ruled.w, mod.Rules.Size({ scale = 1.5 }, size),
            "and its icon is larger")
        T.eq(sameColor(ruled, "lilac"), true, "and its border is its own")

        -- The grid did not shift: the neighbouring icon stands where it stood
        -- and the block is of the same size. The cell is computed by the common
        -- icon size, and the rule does not enter that arithmetic at all.
        local neighbour = iconOf("boon")
        T.eq(neighbour.x, plainX, "the neighbouring icon did not shift horizontally")
        T.eq(neighbour.y, plainY, "nor vertically")
        T.eq(holder.w, holderW, "and the width of the block is the same")
        T.eq(holder.h, holderH, "and so is the height")

        -- The rule icon stands in the middle of its cell rather than in its corner.
        local dx = mod.Layout.Inset(size, ruled.w, settings.direction)
        T.eq(ruled.x, 0 + dx, "the rule icon landed in the middle of its cell")

        -- The labels are computed from the size of that icon rather than from
        -- the common one: the time on an enlarged icon must grow with it.
        T.ok(ruled.timeText.height > plain.timeText.height,
            "the font on an enlarged icon is bigger")

        -- === A rule by name ===============================================
        settings.rules = {
            { name = "By name", text = "rend", scale = 0.5 },
        }
        handle:Apply()
        alive("a rule by name")

        local named = iconOf("rend")
        T.eq(named.w, mod.Rules.Size({ scale = 0.5 }, size),
            "the rule by name found its aura")
        T.eq(iconOf("shield").w, size,
            "while nothing touches the aura of the previous rule any more")

        -- === An aura under two rules ======================================
        settings.rules = {
            { name = "earlier", text = "Rend", scale = 1.5 },
            { name = "later", text = "103", scale = 0.5 },
        }
        handle:Apply()
        alive("an aura under two rules")
        T.eq(iconOf("rend").w, mod.Rules.Size({ scale = 1.5 }, size),
            "a contest of two rules is decided by the place in the player list")

        -- === A rule that named nobody =====================================
        settings.rules = {
            { name = "miss", text = "999999, No such spell", scale = 2,
              color = "text", sound = true },
        }
        handle:Apply()
        alive("a rule that misses")
        T.eq(#shown(), 4, "a rule that named nobody hides nothing")
        local all = icons()
        local odd = 0
        for i = 1, #all do
            if all[i].shown and all[i].w ~= size then odd = odd + 1 end
        end
        T.eq(odd, 0, "and changes no icon at all")

        -- === The pool: an icon from under a rule goes to an aura with none =
        --
        -- An icon returned to the pool carries nothing of the previous aura --
        -- the size and the border colour belong to that "nothing" just as much
        -- as the image and the labels do.
        settings.rules = {
            { name = "Shield", text = "101", scale = 2, color = "lilac" },
        }
        handle:Apply()
        local big = iconOf("shield")
        T.eq(big.w, mod.Rules.Size({ scale = 2 }, size), "an icon under a rule")

        local builtBefore = #client.frames
        table.remove(AURAS.HELPFUL, 1)          -- the aura under the rule went away
        AURAS.HELPFUL[#AURAS.HELPFUL + 1] =
            { "New", "new", 1, nil, 60, 1060, "player", nil, nil, 104 }
        redraw()
        alive("the icon was reused")

        T.eq(#client.frames, builtBefore,
            "no new frames were created for it -- the icon came from the pool")
        local reused = iconOf("new")
        T.ok(reused ~= nil, "the aura with no rule is shown")
        T.eq(reused.w, size, "and its icon is of the ordinary size")
        T.eq(sameColor(reused, mod.Icon.BORDER_COLOR), true,
            "and the border is of the ordinary colour")

        -- And the same thing directly: no rule fields are left on the hidden icons.
        local leftovers = {}
        all = icons()
        for i = 1, #all do
            if not all[i].shown and type(all[i].record) == "table" then
                for key in pairs(all[i].record) do
                    leftovers[#leftovers + 1] = tostring(key)
                end
            end
        end
        T.eq(#leftovers, 0, "the hidden icons carry no rule fields: "
            .. table.concat(leftovers, ", "))

        -- An icon in the pool has the ordinary border rather than the lilac one
        -- from the previous rule: Icon.Release clears it outright.
        local dirty = 0
        for i = 1, #all do
            if not all[i].shown and all[i].umbraAuraBorder ~= nil
                and not sameColor(all[i], mod.Icon.BORDER_COLOR) then
                dirty = dirty + 1
            end
        end
        T.eq(dirty, 0, "the pool holds no icon with the colour of a foreign rule")

        -- A deleted rule stops acting at once rather than after the aura has
        -- gone away and come back.
        AURAS.HELPFUL[#AURAS.HELPFUL + 1] =
            { "Shield", "shield", 1, nil, 60, 1060, "player", nil, nil, 101 }
        redraw()
        T.eq(iconOf("shield").w, mod.Rules.Size({ scale = 2 }, size),
            "the rule acts on the returned aura again")
        settings.rules = {}
        handle:Apply()
        T.eq(iconOf("shield").w, size, "a deleted rule stops acting at once")
        T.eq(sameColor(iconOf("shield"), mod.Icon.BORDER_COLOR), true,
            "and the colour comes back at the same moment")

        -- === The filter outranks a rule ===================================
        --
        -- A rule neither shows what is hidden nor hides what is shown: WHAT to
        -- draw is the filter answer, a rule only says HOW.
        settings.rules = {
            { name = "Shield", text = "101", scale = 2, color = "lilac",
              sound = true },
        }
        args.filterList.set(nil, "101")
        args.filterMode.set(nil, "deny")
        alive("a rule under a filter ban")
        T.eq(iconOf("shield"), nil, "an aura banned by the filter is not shown, and "
            .. "the rule did not bring it back")

        -- The converse: "show only these" without our spell -- a rule does not
        -- show what the filter did not let through.
        args.filterMode.set(nil, "allow")
        args.filterList.set(nil, "102")
        T.eq(iconOf("shield"), nil, "and in the \"only these\" mode a rule does not help")
        T.ok(iconOf("boon") ~= nil, "what the filter named is shown")

        args.filterMode.set(nil, handle.defaults.filterMode)
        args.filterList.set(nil, "")
        T.ok(iconOf("shield") ~= nil, "with no filter the aura came back")
        T.eq(iconOf("shield").w, mod.Rules.Size({ scale = 2 }, size),
            "and the rule is visible again")

        -- === The sound ====================================================
        --
        -- Editing the settings arms the memory anew, so the count starts from
        -- here.
        played = 0
        redraw()
        T.eq(played, 0, "the first redraw after a settings edit stays silent")
        redraw()
        T.eq(played, 0, "and an unchanged set stays silent")

        -- A real expiry: the aura left the player.
        for i = 1, #AURAS.HELPFUL do
            if AURAS.HELPFUL[i][10] == 101 then
                table.remove(AURAS.HELPFUL, i)
                break
            end
        end
        redraw()
        T.eq(played, 1, "a real expiry sounds exactly once")
        redraw()
        T.eq(played, 1, "and does not sound a second time")

        -- A filter edit: the aura stopped being drawn but did not expire.
        AURAS.HELPFUL[#AURAS.HELPFUL + 1] =
            { "Shield", "shield", 1, nil, 60, 1060, "player", nil, nil, 101 }
        redraw()
        redraw()
        played = 0
        args.filterList.set(nil, "101")
        args.filterMode.set(nil, "deny")
        T.eq(iconOf("shield"), nil, "the filter hid the aura under the rule")
        T.eq(played, 0, "and a filter edit makes no sound")
        redraw()
        T.eq(played, 0, "nor does the next redraw")

        args.filterMode.set(nil, handle.defaults.filterMode)
        args.filterList.set(nil, "")
        redraw()
        T.eq(played, 0, "the aura returning to the set stays silent too")

        -- Entering the world: the set of auras arrives anew, and the first read
        -- has nothing to compare with. A zone that changed along with half the
        -- buffs has no right to sound like an expiry.
        redraw()
        played = 0
        local keep = AURAS.HELPFUL
        AURAS.HELPFUL = {}
        core.Events.Dispatch("PLAYER_ENTERING_WORLD")
        T.eq(played, 0, "entering the world with an empty set stays silent")
        AURAS.HELPFUL = keep
        redraw()
        T.eq(played, 0, "and so does the first redraw after entering")

        -- Disabling and enabling the module: the same thing.
        redraw()
        played = 0
        args.enabled.set(nil, false)
        args.enabled.set(nil, true)
        T.eq(played, 0, "enabling the module does not sound like forty expiries")

        -- The pool does not fake an expiry: the icon of a departed aura goes to
        -- another one, and the sound is still one.
        redraw()
        played = 0
        for i = 1, #AURAS.HELPFUL do
            if AURAS.HELPFUL[i][10] == 101 then
                table.remove(AURAS.HELPFUL, i)
                break
            end
        end
        AURAS.HELPFUL[#AURAS.HELPFUL + 1] =
            { "Other", "other", 1, nil, 60, 1060, "player", nil, nil, 105 }
        redraw()
        T.eq(played, 1,
            "an icon that went to another aura added no second sound")

        -- A rule with no sound does not sound at all.
        AURAS.HELPFUL[#AURAS.HELPFUL + 1] =
            { "Shield", "shield", 1, nil, 60, 1060, "player", nil, nil, 101 }
        settings.rules = {
            { name = "Shield", text = "101", scale = 1.5 },
        }
        handle:Apply()
        redraw()
        played = 0
        for i = 1, #AURAS.HELPFUL do
            if AURAS.HELPFUL[i][10] == 101 then
                table.remove(AURAS.HELPFUL, i)
                break
            end
        end
        redraw()
        T.eq(played, 0, "a rule with no sound stays silent on an expiry")

        -- === Combat =======================================================
        --
        -- A rule changes the icon size and its border colour, and an icon is an
        -- ordinary frame: the one protected thing under it is the buff-cancel
        -- overlay. A rule has no right to create any new deferred work.
        AURAS.HELPFUL[#AURAS.HELPFUL + 1] =
            { "Shield", "shield", 1, nil, 60, 1060, "player", nil, nil, 101 }
        settings.rules = {
            { name = "Shield", text = "101", scale = 2, color = "lilac",
              sound = true },
        }
        handle:Apply()

        client.combat = true
        client.refused = nil
        redraw()
        alive("a redraw with a rule in combat")
        T.eq(client.refused, nil,
            "a rule in combat got not a single refusal from the engine")
        T.eq(iconOf("shield").w, mod.Rules.Size({ scale = 2 }, size),
            "and the rule size is written in combat")

        -- An aura expired in combat: a sound in combat protects nothing and plays.
        played = 0
        for i = 1, #AURAS.HELPFUL do
            if AURAS.HELPFUL[i][10] == 101 then
                table.remove(AURAS.HELPFUL, i)
                break
            end
        end
        redraw()
        alive("an expiry in combat")
        T.eq(played, 1, "the expiry sound plays in combat")
        T.eq(client.refused, nil, "and still not a single refusal")

        -- The combat queue holds nothing but the aiming of the overlays. A
        -- deferred layout would mean a grid frozen in combat.
        local queue = core.Combat.queues["umbraauras"]
        local onlyButtons = true
        if queue then
            for i = 1, #queue.order do
                if not tostring(queue.order[i]):find("^cancel:") then
                    onlyButtons = false
                end
            end
        end
        T.eq(onlyButtons, true, "the combat queue holds nothing but cancel:")

        client.combat = false
        core.Combat.DrainFor("umbraauras")

        -- === The cost =====================================================
        --
        -- The rules stand on the aura path, and in combat it arrives on every
        -- event. The real path is measured: event -> redraw, forty icons.
        AURAS.HELPFUL = {}
        AURAS.HARMFUL = {}
        for i = 1, 20 do
            AURAS.HELPFUL[i] =
                { "H" .. i, "h" .. i, 1, nil, 60, 1060, "player", nil, nil,
                  1000 + i }
            AURAS.HARMFUL[i] =
                { "D" .. i, "d" .. i, 1, nil, 60, 1060, "target", nil, nil,
                  2000 + i }
        end

        settings.rules = {}
        handle:Apply()

        local function redraws(times)
            local started = os.clock()
            for _ = 1, times do redraw() end
            return os.clock() - started
        end

        local ROUNDS = 5000
        redraws(300)
        local without = redraws(ROUNDS)

        -- Twelve rules -- as many as a live player tends to have -- and half
        -- the auras under a rule. They match differently: some by id, some by
        -- name, so that what is measured is not "the id path" but both decision
        -- paths at once. Every fourth rule also carries a sound.
        local many = {}
        for i = 1, 12 do
            local entry = { name = "r" .. i, scale = 1 + i * 0.05 }
            if i % 2 == 0 then
                entry.text = tostring(1000 + i)
            else
                entry.text = "h" .. i .. ", d" .. i
            end
            if i % 4 == 0 then entry.sound = true end
            many[i] = entry
        end
        settings.rules = many
        handle:Apply()

        redraws(300)
        local with = redraws(ROUNDS)

        io.write(string.format(
            "  [the cost of rules on auras] %d grid redraws per event, 40 "
            .. "icons: with no rules %.0f ms (%.4f ms per redraw), with "
            .. "twelve rules %.0f ms (%.4f ms)\n",
            ROUNDS, without * 1000, without * 1000 / ROUNDS,
            with * 1000, with * 1000 / ROUNDS))

        -- The ceiling guards the order of magnitude: the rules have no right to
        -- double the cost of a redraw that in combat arrives on every aura event.
        T.ok(with < without * 1.6 + 0.05, string.format(
            "the rules do not change the order of the redraw cost: %.4f against %.4f ms",
            with * 1000 / ROUNDS, without * 1000 / ROUNDS))

        -- And the main property of the split in two: thirty rules cost no more
        -- than twelve. The decision is made by a dictionary compiled once per
        -- settings edit rather than by walking the list on every aura.
        local huge = {}
        for i = 1, 30 do
            huge[i] = { name = "m" .. i, text = tostring(1000 + i),
                        scale = 1.25 }
        end
        settings.rules = huge
        handle:Apply()
        redraws(300)
        local thirty = redraws(ROUNDS)

        io.write(string.format(
            "  [the cost of rules on auras] 30 rules instead of 12: %.4f ms per "
            .. "redraw\n", thirty * 1000 / ROUNDS))
        T.ok(thirty < with * 1.5 + 0.05,
            "thirty rules cost no more than twelve")

        settings.rules = {}
        handle:Apply()
        alive("the module is alive after the measurement")
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.C_UnitAuras = saved.C_UnitAuras
    _G.UnitAura = saved.UnitAura
    _G.GameTooltip = saved.GameTooltip
    _G.InCombatLockdown = saved.InCombatLockdown
    _G.RegisterAttributeDriver = saved.RegisterAttributeDriver
end

T.suite("aura rules: there is still a single writer")

do
    -- The source walk. The file list is taken from the module TOC, so a new
    -- file comes under the check by itself.
    local sources = {}
    local files = helpers.moduleSources("Features/Auras")
    for i = 1, #files do
        local handle = io.open(files[i], "r")
        if handle then
            sources[files[i]:gsub(".*/", "")] = handle:read("*a")
            handle:close()
        end
    end
    T.ok(next(sources) ~= nil, "the module sources were read")
    T.ok(sources["Rules.lua"] ~= nil, "and Rules.lua is among them -- it is named in the TOC")

    --- How many times a string occurs in the code, not counting comment lines.
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

    -- One line of code in the whole module writes the icon size: the common
    -- size and a rule both go through it. The block holder is not an icon, and
    -- its size is written by its own line in Auras.lua.
    local writers = 0
    for name, text in pairs(sources) do
        local hits = countCode(text, "frame:SetSize(")
        if hits > 0 then
            writers = writers + hits
            T.eq(name, "Icon.lua", "only the display writes the icon size")
        end
    end
    T.eq(writers, 1, "and exactly one line of code writes it")

    -- The border colour is the same: the only skinning call in the whole module
    -- sits in Icon.Border, and both the ordinary border and a rule go through it.
    local painters = 0
    for name, text in pairs(sources) do
        local hits = countCode(text, "skin.Outline(")
        if hits > 0 then
            painters = painters + hits
            T.eq(name, "Icon.lua", "only the display paints the border")
        end
    end
    T.eq(painters, 1, "and exactly one skinning call paints it")

    local doors = 0
    for _, text in pairs(sources) do
        doors = doors + countCode(text, "Icon.Border(")
    end
    T.eq(doors, 4, "Icon.Border is declared once and called three times: "
        .. "the birth of an icon, the display and the return to the pool")

    -- The rule decision is single too: two places asking "which rule does this
    -- aura have" would diverge just as two sizes would.
    T.eq(countCode(sources["Auras.lua"], "Rules.For("), 1,
        "the rule for an aura is asked by exactly one call")

    -- And it is asked after the filter: the precedence is held not by reasoning
    -- but by there being nowhere else to ask for a rule.
    local read = sources["Auras.lua"]:match(
        "local function Read%(.-\n    return out\nend")
    T.ok(read ~= nil, "the body of the aura read was found")
    if read then
        local allows = read:find("Filter.Allows(", 1, true)
        local ruleFor = read:find("Rules.For(", 1, true)
        T.ok(allows ~= nil and ruleFor ~= nil and allows < ruleFor,
            "the rule is asked after the filter rather than before it")
    end

    -- The grid layout knows nothing about the rules: a cell is computed by the
    -- common icon size, and the set of auras does not move the grid.
    T.eq(countCode(sources["Layout.lua"], "Rules."), 0,
        "the layout knows nothing about the rules")
    T.eq(countCode(sources["Sort.lua"], "Rules."), 0,
        "and neither does the icon order")

    -- Case folding and list parsing are the core ones throughout the module.
    local folders, splitters = {}, {}
    for name, text in pairs(sources) do
        if countCode(text, "string.lower") > 0
            or countCode(text, ":lower(") > 0 then
            folders[#folders + 1] = name
        end
        if countCode(text, ":gmatch(\"[^,") > 0 then
            splitters[#splitters + 1] = name
        end
    end
    T.eq(#folders, 0, "the module has no case folding of its own: "
        .. table.concat(folders, " | "))
    T.eq(#splitters, 0, "and no list parsing of its own either: "
        .. table.concat(splitters, " | "))

    -- The rules introduced no frame walks: a sound happens on an event rather
    -- than on a frame. The only OnUpdate of the module sits in Auras.lua and
    -- was there before the rules.
    local tickers = 0
    for name, text in pairs(sources) do
        local hits = countCode(text, "SetScript(\"OnUpdate")
        if hits > 0 then
            tickers = tickers + hits
            T.eq(name, "Auras.lua", "the countdown is the only OnUpdate")
        end
    end
    T.eq(tickers, 1, "and it is still the only one")
    T.eq(countCode(sources["Rules.lua"], "C_Timer"), 0,
        "the rules introduced no timers")
end

helpers.removeValidator()
