local helpers = require("helpers")

-- The third increment of the nameplate engine: rules for an individual unit.
--
-- A rule is a list of creatures (by name or by id) and what makes their
-- nameplate differ from the rest: the bar colour and the size. What is checked
-- falls into four parts.
--
-- 1. The pure rule: parsing the list into a plan, the decision for one unit,
--    parsing a GUID, the size factor, a dispute between two rules over one creature.
--
-- 2. The colour precedence. A rule is the fourth source of the bar colour, and
--    the whole question of the increment is where exactly it stands. The
--    answer is declared in one place (Colors.Bar) and is checked here
--    directly, by the name of the rule that fired rather than by matching digits.
--
-- 3. The pool. A rule changes the scale of the frame itself -- the one thing
--    that cannot be made a child frame. So it must be extinguished when the
--    frame returns to the pool just like the health bar, and that is checked
--    the same way the second increment checked everything else: a child
--    unknown to the drawing must be extinguished too.
--
-- 4. The cost. Thirty nameplates, half of them under a rule, the real event
--    path of the module. Limits rather than "as it is now" numbers.

local MODULE = "Features/NamePlates"
local PATH = MODULE .. "/"

helpers.installValidator()

--- Load the pure parts of the module into a fresh namespace.
-- @return table
local function pureNamespace()
    local ns = helpers.newNamespace()
    -- The core doors -- the shared aura filter (version 7) and the case folding
    -- (version 9) -- are opened by the real core files: a fake beside them
    -- would be checking a copy instead of what the player sees.
    local door, restore = helpers.installCore()
    helpers.loadModule(MODULE, ns, { withRegistration = false })
    restore()
    ns.coreCasefold = door:GetCasefold()
    ns.coreFilter = door:GetAuraFilter()
    return ns
end

local pure = pureNamespace()

T.suite("nameplate rules: parsing the list and one decision")

do
    local Rules = pure.Rules

    T.ok(type(Rules) == "table", "the rules loaded from the module TOC")

    -- The case folding is a core function rather than a copy beside it: a copy
    -- would diverge from the core one on the letter nobody checks.
    T.eq(Rules.Key, pure.coreCasefold.Key,
        "the name key is the core function rather than our own")

    -- A fresh install: there are no rules, and the hot path must learn that
    -- with its very first question.
    local empty = Rules.Compile(nil)
    T.eq(Rules.Any(empty), false, "with no rules the plan is empty")
    T.eq(Rules.NeedsKey(empty), false, "and there is no reason to build a name key")
    T.eq(Rules.NeedsId(empty), false, "and no reason to read a GUID")
    T.eq(Rules.For(empty, "hogger", 448), nil, "and nothing to decide")

    T.eq(Rules.Any(Rules.Compile({})), false, "an empty list is the same thing")

    -- A rule by name.
    local list = {
        { name = "Rare", text = "Hogger", color = { 1, 0, 0 } },
    }
    local plan = Rules.Compile(list)
    T.eq(Rules.Any(plan), true, "the rule made it into the plan")
    T.eq(Rules.NeedsKey(plan), true, "and a name has something to compare against in it")
    T.eq(Rules.NeedsId(plan), false, "while it holds no ids at all")

    local hit = Rules.For(plan, Rules.Key("Hogger"), nil)
    T.ok(hit ~= nil, "the creature was found by name")
    T.eq(hit.r, 1, "and the rule colour comes with it")

    -- The case does not matter: the folding is the core one, and Cyrillic folds
    -- just like Latin.
    T.eq(Rules.For(plan, Rules.Key("hogger"), nil), hit,
        "the name is found when typed in lower case")

    -- A rule that did not name this creature does not fire.
    T.eq(Rules.For(plan, Rules.Key("Murloc"), nil), nil,
        "a creature not named by the rule does not get the rule")

    -- A rule by id.
    local byIdPlan = Rules.Compile({
        { name = "By ids", text = "448, 12345", color = { 0, 1, 0 } },
    })
    T.eq(Rules.NeedsId(byIdPlan), true, "there are ids in the plan")
    T.eq(Rules.NeedsKey(byIdPlan), false, "while there are no names")
    T.ok(Rules.For(byIdPlan, nil, 448) ~= nil, "the creature was found by id")
    T.eq(Rules.For(byIdPlan, nil, 449), nil, "a foreign id does not match")
    T.eq(Rules.For(byIdPlan, Rules.Key("448"), nil), nil,
        "an id asked as a name does not match: those are different questions")

    -- A rule that changes nothing does not enter the plan: there is nothing to
    -- compare against it, while it costs as much as a working one.
    local idle = Rules.Compile({ { name = "Empty", text = "Hogger" } })
    T.eq(Rules.Any(idle), false, "a rule with no colour and no size does not count")

    local sized = Rules.Compile({
        { name = "Bigger", text = "Hogger", scale = 1.5 },
    })
    T.eq(Rules.Any(sized), true, "while a rule with just a size does count")
    T.eq(Rules.For(sized, Rules.Key("Hogger"), nil).r, nil,
        "it has no colour, and the bar is painted by the ordinary precedence")

    -- A spoiled record in the saved variables -- people edit them by hand -- is skipped.
    local junk = Rules.Compile({ "not a table", {}, { text = "" },
        { name = "Fine", text = "Hogger", scale = 1.5 } })
    T.eq(junk.count, 1, "the garbage in the saved variables was skipped, the live one remained")
end

T.suite("nameplate rules: one creature and two rules")

do
    local Rules = pure.Rules

    -- Two rules name the same creature by name. The one standing earlier in
    -- the player's list outranks: a precedence invisible in the list could be
    -- neither predicted nor fixed by the player.
    local plan = Rules.Compile({
        { name = "First",  text = "Hogger", color = { 1, 0, 0 } },
        { name = "Second", text = "Hogger", color = { 0, 0, 1 } },
    })
    local hit = Rules.For(plan, Rules.Key("Hogger"), nil)
    T.eq(hit.name, "First", "a dispute between two names is settled by the order in the list")
    T.eq(hit.r, 1, "and the colour goes to the senior one")

    -- A dispute between the dictionaries: one rule named the creature by name,
    -- the other by id. It is settled by the same thing -- the position of the rule in the list.
    local cross = Rules.Compile({
        { name = "By name", text = "Hogger", color = { 1, 0, 0 } },
        { name = "By id",   text = "448",    color = { 0, 0, 1 } },
    })
    local both = Rules.For(cross, Rules.Key("Hogger"), 448)
    T.eq(both.name, "By name", "the name comes before the id -- the name wins")

    local swapped = Rules.Compile({
        { name = "By id",   text = "448",    color = { 0, 0, 1 } },
        { name = "By name", text = "Hogger", color = { 1, 0, 0 } },
    })
    T.eq(Rules.For(swapped, Rules.Key("Hogger"), 448).name, "By id",
        "the list was reordered -- the precedence was reordered with it")

    -- And on its own each of them still works by itself.
    T.eq(Rules.For(swapped, Rules.Key("Hogger"), nil).name, "By name",
        "with no id the name decides")
    T.eq(Rules.For(swapped, nil, 448).name, "By id",
        "with no name the id decides")
end

T.suite("nameplate rules: the creature id out of a GUID")

do
    local Rules = pure.Rules

    T.eq(Rules.NpcId("Creature-0-3299-0-11-448-000136DF91"), 448,
        "the creature id was taken from the GUID")
    T.eq(Rules.NpcId("Vehicle-0-3299-0-11-27850-000136DF91"), 27850,
        "a vehicle has its id in the same place")
    T.eq(Rules.NpcId("Pet-0-3299-0-11-42651-0102030405"), 42651,
        "and so does a pet")

    -- A player has no creature id at all, and taking their field for an id
    -- would mean painting a random player with a rule about a boar.
    T.eq(Rules.NpcId("Player-970-0002FD64"), nil, "a player has no id")
    T.eq(Rules.NpcId("Item-970-0-4000000005D1B1F8"), nil, "and neither does an item")
    T.eq(Rules.NpcId(nil), nil, "with no GUID there is no id")
    T.eq(Rules.NpcId(""), nil, "nor out of an empty string")
    T.eq(Rules.NpcId("garbage"), nil, "nor out of garbage")
end

T.suite("nameplate rules: the size factor")

do
    local Rules = pure.Rules
    local S = Rules.SCALE

    T.eq(Rules.Scale(1.5), 1.5, "a given factor passes")
    T.eq(Rules.Scale(0.1), S.min, "too small is clamped to the bound")
    T.eq(Rules.Scale(99), S.max, "and so is too large")
    T.eq(Rules.Scale("garbage"), S.default, "a non-number gives the default")
    T.eq(Rules.Scale(0 / 0), S.default, "NaN gives the default")

    -- A factor rather than a number of its own: the shared scale is the
    -- player's setting, and a rule replacing it entirely would unhook the creature from the slider.
    -- The numbers are chosen so the product is exact in binary too: the
    -- precedence check must not fail on rounding.
    T.eq(Rules.Apply(nil, 1.25), 1.25, "with no rule the shared scale remains")
    T.eq(Rules.Apply({ scale = 1.5 }, 1.25), 1.875, "a rule multiplies the shared one")
    T.eq(Rules.Apply({ scale = 1 }, 1.25), 1.25, "a one changes nothing")
    T.eq(Rules.Apply({}, 1.25), 1.25, "and neither does a rule with no size")
    T.eq(Rules.Apply(nil, "garbage"), 1, "garbage instead of a scale gives one")
    T.eq(Rules.Apply({ scale = -3 }, 1.25), 1.25,
        "a negative factor does not flip the nameplate")
end

T.suite("nameplate rules: the list is edited by the player")

do
    local Rules = pure.Rules
    local list = {}

    T.eq(select(2, Rules.Add(list, nil, "Hogger")), "noname",
        "a rule with no name is not created")
    T.eq(select(2, Rules.Add(list, "  ", "Hogger")), "noname",
        "a single space does not count as a name")
    T.eq(select(2, Rules.Add(list, "A name", "")), "notext",
        "a rule naming not a single creature is not created")
    T.eq(select(2, Rules.Add(list, string.rep("a", 200), "Hogger")), "long",
        "too long a name is not created")

    local rule = Rules.Add(list, "Rare", "Hogger, 448")
    T.ok(rule ~= nil, "the rule was created")
    T.eq(#list, 1, "and went into the list")
    T.eq(rule.scale, Rules.SCALE.default,
        "a new rule has the ordinary size: it changes nothing yet")

    T.eq(select(2, Rules.Add(list, "rare", "Murloc")), "taken",
        "a name is not repeated, and the case does not help here")

    T.eq(Rules.SetColor(list, "Rare", 1, 0.5, 0.2), true, "the colour was assigned")
    T.eq(rule.color[1], 1, "and went into the rule")
    T.eq(Rules.SetColor(list, "Rare", nil, nil, nil), true, "the colour was removed")
    T.eq(rule.color, nil, "and the rule stopped touching the colour")

    T.eq(Rules.SetScale(list, "Rare", 99), true, "the size was assigned")
    T.eq(rule.scale, Rules.SCALE.max, "and clamped to the bound")

    T.eq(Rules.Rename(list, "Rare", "Rare beasts"), true,
        "the rule was renamed")
    T.eq(select(2, Rules.SetText(list, "Rare beasts", "")), "notext",
        "the creature list cannot be erased dry")

    Rules.Add(list, "Second one", "Murloc")
    T.eq(Rules.Move(list, "Second one", -1), true, "the rule was moved up")
    T.eq(list[1].name, "Second one", "and became the first")
    T.eq(Rules.Move(list, "Second one", -1), false, "there is nowhere above the first")
    T.eq(Rules.Move(list, "Second one", 5), false, "a step is only ever one position")

    T.eq(Rules.Remove(list, "Second one"), true, "the rule was forgotten")
    T.eq(#list, 1, "and left the list")
    T.eq(Rules.Remove(list, "Second one"), false, "a second time there is nothing to forget")

    -- The list is handed out of the settings without a copy: an edit through a
    -- copy would be lost on logout.
    local settings = { rules = { { name = "From the saved variables", text = "Hogger" } } }
    T.eq(Rules.List(settings), settings.rules, "the list is handed out without a copy")
    T.eq(#Rules.List(nil), 0, "with no settings the list is empty")
    T.eq(#Rules.List({}), 0, "and with no key either")
end

T.suite("nameplate rules: where a rule stands in the colour precedence")

do
    local Colors = pure.Colors

    local CLASS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    local REACTION = { [2] = { r = 1, g = 0, b = 0 }, [5] = { r = 0, g = 1, b = 0 } }
    local RULE = { r = 0.2, g = 0.4, b = 0.8 }

    -- A rule outranks the class: the class is the engine's guess about who this
    -- is, a rule is a direct instruction from the player.
    local r, g, b, why = Colors.Bar({
        isPlayer = true, class = "WARRIOR", classColors = CLASS,
        reaction = 5, reactionColors = REACTION, rule = RULE })
    T.eq(why, "rule", "a rule outranks the class")
    T.eq(b, 0.8, "and the colour was taken from the rule")

    -- And it outranks the reaction.
    r, g, b, why = Colors.Bar({ reaction = 2, reactionColors = REACTION,
        rule = RULE })
    T.eq(why, "rule", "a rule outranks the reaction")

    -- But it is junior to the threat: a rule is permanent, a threat is urgent,
    -- and threat colouring exists precisely to show a creature turning on the
    -- player. A rule overriding it would hide the only thing it is enabled for.
    --
    r, g, b, why = Colors.Bar({ threatOn = true, threat = 3, reaction = 2,
        reactionColors = REACTION, rule = RULE })
    T.eq(why, "threat", "the threat outranks the rule")
    T.eq(r, Colors.THREAT[3].r, "and the colour was taken from the threat")

    -- A threat with nothing to say does not cancel the rule.
    r, g, b, why = Colors.Bar({ threatOn = true, threat = 0, reaction = 2,
        reactionColors = REACTION, rule = RULE })
    T.eq(why, "rule", "a zero threat does not override the rule")

    -- A rule with no colour changes only the size, and the bar is painted by
    -- the ordinary precedence.
    r, g, b, why = Colors.Bar({ reaction = 2, reactionColors = REACTION,
        rule = { scale = 1.5 } })
    T.eq(why, "reaction", "a rule with no colour does not touch the colour")
    T.eq(r, 1, "and the bar is painted by the reaction")

    -- A spoiled rule does not leave the bar colourless.
    r, g, b, why = Colors.Bar({ reaction = 2, reactionColors = REACTION,
        rule = "garbage" })
    T.eq(why, "reaction", "garbage instead of a rule decides nothing")

    -- The whole order as one list: it IS the answer of the increment.
    local ORDER = {
        { info = { threatOn = true, threat = 2, reaction = 2, rule = RULE,
            isPlayer = true, class = "WARRIOR", classColors = CLASS },
          want = "threat" },
        { info = { reaction = 2, rule = RULE, isPlayer = true,
            class = "WARRIOR", classColors = CLASS }, want = "rule" },
        { info = { reaction = 2, isPlayer = true, class = "WARRIOR",
            classColors = CLASS }, want = "class" },
        { info = { reaction = 2, reactionColors = REACTION }, want = "reaction" },
    }
    for i = 1, #ORDER do
        T.eq(select(4, Colors.Bar(ORDER[i].info)), ORDER[i].want,
            "the precedence, step " .. i .. ": " .. ORDER[i].want)
    end
end

-- === The fake client =======================================================
--
-- The same as in the second increment: the fake does exactly what the module
-- asks of a frame. It cannot be a separate copy -- the checks run in different
-- files of one Lua state, and a shared buffer of one would spoil the tally of
-- the other -- so the counters here are its own.

local client = { built = 0, colors = 0, scales = 0 }

local function object(kind)
    local o = { kind = kind, children = {}, regions = {}, shown = false }

    function o:Show() self.shown = true end
    function o:Hide() self.shown = false end
    function o:SetShown(v) self.shown = v and true or false end
    function o:IsShown() return self.shown end
    function o:SetPoint() end
    function o:ClearAllPoints() end
    function o:SetAllPoints() end
    function o:SetSize(w, h) self.w, self.h = w, h end
    function o:SetWidth(w) self.w = w end
    function o:SetHeight(h) self.h = h end
    function o:SetScale(s) self.scale = s; client.scales = client.scales + 1 end
    function o:GetScale() return self.scale or 1 end
    function o:SetAlpha(a) self.alpha = a end
    function o:GetAlpha() return self.alpha or 1 end
    function o:SetDrawLayer() end
    function o:GetChildren() return unpack(self.children) end
    function o:GetRegions() return unpack(self.regions) end

    return o
end

local function texture(parent)
    local t = object("Texture")
    function t:SetTexture(path) self.path = path end
    function t:SetTexCoord() end
    function t:SetColorTexture(r, g, b) self.r, self.g, self.b = r, g, b end
    function t:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
    function t:CreateAnimationGroup()
        local group = object("AnimationGroup")
        group.animations = {}
        function group:CreateAnimation()
            local anim = object("Animation")
            function anim:SetDuration(v) self.duration = v end
            function anim:SetScaleFrom(x) self.from = x end
            function anim:SetScaleTo(x) self.to = x end
            function anim:SetOrigin() end
            function anim:SetSmoothing() end
            self.animations[#self.animations + 1] = anim
            return anim
        end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        function group:IsPlaying() return self.playing end
        return group
    end
    if parent ~= nil then parent.regions[#parent.regions + 1] = t end
    return t
end

local function fontString(parent)
    local f = object("FontString")
    f.text = ""
    function f:SetText(value) self.text = value or "" end
    function f:GetText() return self.text end
    function f:SetJustifyH() end
    function f:SetTextColor() end
    function f:SetFont() end
    function f:GetFont() return "font", 10, "" end
    parent.regions[#parent.regions + 1] = f
    return f
end

local function createFrame(kind, _, parent)
    local f = object(kind or "Frame")

    function f:CreateTexture() return texture(self) end
    function f:CreateFontString() return fontString(self) end
    function f:SetScript(name, fn) self[name] = fn end
    function f:RegisterEvent() end
    function f:UnregisterEvent() end

    if kind == "StatusBar" then
        function f:SetMinMaxValues(a, b) self.min, self.max = a, b end
        function f:SetValue(v) self.value = v end
        function f:GetValue() return self.value end
        function f:SetStatusBarTexture(path) self.texturePath = path end
        function f:SetStatusBarColor(r, g, b)
            self.r, self.g, self.b = r, g, b
            client.colors = client.colors + 1
        end
    end

    if kind == "Cooldown" then
        function f:SetCooldown(s, d) self.start, self.duration = s, d end
        function f:Clear() self.start, self.duration = nil, nil end
        function f:SetDrawEdge() end
        function f:SetHideCountdownNumbers() end
    end

    if parent ~= nil and type(parent) == "table" and parent.children then
        parent.children[#parent.children + 1] = f
    end

    client.built = client.built + 1
    return f
end

T.suite("nameplate rules: the scale is extinguished along with everything else")

do
    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }
    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")

    local Plate = pure.Plate
    local skin = {
        Backdrop = function() return true end,
        Outline = function(frame, key)
            frame[key] = frame[key] or { TOP = object("Texture") }
            return true
        end,
        Color = function() return 0.7, 0.5, 0.7 end,
    }

    local pool = Plate.NewPool()
    local frame = Plate.Acquire(pool, skin)
    T.ok(frame ~= nil, "the frame was built")

    -- A creature under a rule: the shared scale is 1.25, the rule multiplies by 1.5.
    Plate.Layout(frame, nil, 110, 10, 1.25, 2)
    T.eq(frame.scale, 1.25, "the shared scale was set by the layout")

    Plate.SetScale(frame, pure.Rules.Apply({ scale = 1.5 }, 1.25))
    T.eq(frame.scale, 1.875, "the rule enlarged the nameplate")

    -- Garbage instead of a number gives one rather than an invisible
    -- nameplate: the value comes from the saved variables, and a zero would hide the creature for good.
    Plate.SetScale(frame, 0)
    T.eq(frame.scale, 1, "a zero does not hide the nameplate")
    Plate.SetScale(frame, "garbage")
    T.eq(frame.scale, 1, "and neither does garbage")
    Plate.SetScale(nil, 2)
    T.eq(Plate.SetScale(frame, nil), nil, "with no frame and no number it stays silent")

    Plate.SetScale(frame, 1.875)

    -- An element the drawing knows nothing about: the pool promise from the
    -- second increment must stay true after the frame got a scale too.
    local tomorrow = createFrame("Frame", nil, frame)
    tomorrow:Show()
    local tomorrowText = fontString(tomorrow)
    tomorrowText:SetText("a trace of the previous unit")

    frame.record.unit = "nameplate1"

    Plate.Release(pool, frame)

    T.eq(frame.scale, 1, "the scale of the previous unit did not go into the pool")
    T.eq(frame.shown, false, "the frame itself is hidden")
    T.eq(tomorrow.shown, false,
        "and a child unknown to the drawing went out, as before")
    T.eq(tomorrowText:GetText(), "", "and its label is erased")
    T.eq(next(frame.record), nil, "the attachment record is empty")

    for key, value in pairs(saved) do _G[key] = value end
end

-- === The real module on a fake client ======================================

--- Assemble the core and the module on a fake client.
-- @param settings table the initial module settings
-- @return table core, table handle, table plates, table ns
local function bootstrap(settings)
    local core = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", core)
    helpers.loadAddonFile("Core/Registry.lua", core)
    helpers.loadAddonFile("Core/Defaults.lua", core)
    helpers.loadAddonFile("Core/Command.lua", core)
    helpers.loadAddonFile("Core/Locale.lua", core)
    helpers.loadAddonFile("Core/Skin.lua", core)
    helpers.loadAddonFile("Skin/Draw.lua", core)
    helpers.loadAddonFile("Core/Frames.lua", core)
    helpers.loadAddonFile("Core/Events.lua", core)
    helpers.loadAddonFile("Core/Combat.lua", core)
    helpers.loadAddonFile("Core/Api.lua", core)
    helpers.loadAddonFile("Core/Casefold.lua", core)
    helpers.loadAddonFile("Core/AuraFilter.lua", core)
    helpers.loadAddonFile("Core/Media.lua", core)

    core.Registry.report = function() end
    core.Addon = {
        db = { profile = { umbraplates = settings }, global = {} },
        Print = function() end,
    }
    core.flavor = "mists"
    core.Registry:Register({ name = "nameplates" })

    local ns = helpers.newNamespace()
    helpers.loadModule(MODULE, ns)

    return core, core.Registry:Get("umbraplates"), ns
end

T.suite("nameplate rules: thirty nameplates, half of them under a rule")

local PLATES = 30
local units = {}
for i = 1, PLATES do units[i] = "nameplate" .. i end

do
    client.built, client.colors, client.scales = 0, 0, 0

    local saved = {
        Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        CreateFrame = _G.CreateFrame, UIParent = _G.UIParent,
        C_NamePlate = _G.C_NamePlate, GetTime = _G.GetTime,
        UnitIsPlayer = _G.UnitIsPlayer, UnitClass = _G.UnitClass,
        UnitReaction = _G.UnitReaction, UnitName = _G.UnitName,
        UnitLevel = _G.UnitLevel, UnitHealth = _G.UnitHealth,
        UnitHealthMax = _G.UnitHealthMax, UnitIsUnit = _G.UnitIsUnit,
        UnitThreatSituation = _G.UnitThreatSituation,
        UnitIsQuestBoss = _G.UnitIsQuestBoss, UnitAura = _G.UnitAura,
        UnitCastingInfo = _G.UnitCastingInfo,
        UnitChannelInfo = _G.UnitChannelInfo, UnitGUID = _G.UnitGUID,
    }

    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")
    _G.SlashCmdList = {}

    local plates = {}
    for i = 1, PLATES do
        local plate = object("Frame")
        plate.UnitFrame = object("Frame")
        plate.namePlateUnitToken = units[i]
        plates[units[i]] = plate
    end

    _G.C_NamePlate = {
        GetNamePlateForUnit = function(unit) return plates[unit] end,
        GetNamePlates = function() return {} end,
    }

    local clock = 100
    _G.GetTime = function() return clock end

    -- Half the creatures are under a rule, and they match in different ways:
    -- the even ones by name, the multiples of four by id as well. That way what
    -- is measured is not "the rule fired" but both decision paths at once.
    local function index(unit) return tonumber(unit:match("(%d+)$")) or 0 end

    _G.UnitIsPlayer  = function() return false end
    _G.UnitClass     = function() return "Warrior", "WARRIOR" end
    _G.UnitReaction  = function() return 2 end
    _G.UnitName      = function(unit)
        if index(unit) % 2 == 0 then return "Pack Leader" end
        return "A very long creature name"
    end
    _G.UnitGUID = function(unit)
        local id = (index(unit) % 4 == 0) and 448 or 9999
        return "Creature-0-3299-0-11-" .. id .. "-000136DF91"
    end
    _G.UnitLevel     = function() return 42 end
    _G.UnitHealth    = function() return 40 end
    _G.UnitHealthMax = function() return 80 end
    _G.UnitIsUnit    = function() return false end
    _G.UnitThreatSituation = function() return 0 end
    _G.UnitIsQuestBoss     = function() return true end

    local AURAS = {
        HARMFUL = { "Rend", "Hamstring", "Sunder Armor" },
        HELPFUL = { "Battle Shout", "Blessing" },
    }
    _G.UnitAura = function(_, index2, filter)
        local list = AURAS[filter]
        local name = list and list[index2]
        if not name then return nil end
        return name, "icon", 1, nil, 10, clock + 5, "player"
    end

    _G.UnitCastingInfo = function()
        return "Fireball", nil, nil, (clock - 1) * 1000,
            (clock + 1) * 1000, false, nil, false
    end
    _G.UnitChannelInfo = function() return nil end

    -- Everything is on, and there are as many rules as a live player has:
    -- measuring the cost on one rule would mean measuring emptiness.
    local RULES = {
        { name = "Pack leaders", text = "Pack Leader", color = { 0.2, 0.4, 0.8 },
          scale = 1.4 },
        { name = "By id", text = "448", color = { 0.9, 0.1, 0.1 },
          scale = 1.2 },
    }
    for i = 1, 10 do
        RULES[#RULES + 1] = { name = "Idle " .. i,
            text = "Creature " .. i .. ", " .. (100000 + i),
            color = { 0.5, 0.5, 0.5 }, scale = 1.1 }
    end

    local core, handle, ns = bootstrap({
        enabled = true, scale = 1,
        truncate = true, threat = true, quest = true,
        castbar = true, castHeight = 5,
        auras = true, auraSize = 16, auraLimit = 4,
        auraOnlyMine = true, auraHelpful = true, auraHarmful = true,
        auraMode = "off", auraList = "",
        rules = RULES,
    })

    T.ok(handle ~= nil, "the module with rules is registered")
    core.Registry:EnableAll()
    T.eq(core.Registry:IsEnabled(handle), true, "and enabled")

    local dispatch = core.Events.Dispatch

    for i = 1, PLATES do dispatch("NAME_PLATE_UNIT_ADDED", units[i]) end
    T.eq(core.Registry:IsEnabled(handle), true,
        "thirty attachments with rules ran without error")

    -- What was drawn. Our frames are children of UIParent, and they differ by
    -- scale: 1.4 under a rule, 1 without one.
    local ours = {}
    for i = 1, #_G.UIParent.children do
        local child = _G.UIParent.children[i]
        if child.nameText and child.shown then ours[#ours + 1] = child end
    end
    T.eq(#ours, PLATES, "thirty of our nameplates are shown")

    local big, plain = 0, 0
    for i = 1, #ours do
        if ours[i].scale == 1.4 then big = big + 1
        elseif ours[i].scale == 1 then plain = plain + 1 end
    end
    T.eq(big, PLATES / 2, "half the nameplates grew by a rule: " .. big)
    T.eq(plain, PLATES / 2, "the other half stayed ordinary: " .. plain)

    -- The rule colour really is on the bar, and precisely on the one under the
    -- rule. "Pack Leader" matches both by name (rule 1) and, for every fourth,
    -- by id (rule 2) -- the first one outranks.
    local ruled, untouched = nil, nil
    for i = 1, #ours do
        if ours[i].scale == 1.4 then ruled = ruled or ours[i]
        else untouched = untouched or ours[i] end
    end
    T.ok(ruled ~= nil and untouched ~= nil, "both kinds of nameplate were found")
    if ruled then
        T.eq(ruled.bar.r, 0.2, "a bar under a rule is painted by the rule")
        T.eq(ruled.bar.b, 0.8, "in every channel")
    end
    if untouched then
        T.eq(untouched.bar.r, pure.Colors.REACTION[2].r,
            "while without a rule, by the reaction, as before")
    end

    -- A full run of the hot path: the same thing the second increment measures,
    -- but half the nameplates are now under a rule.
    local function sweep()
        for i = 1, PLATES do dispatch("UNIT_HEALTH", units[i]) end
        for i = 1, PLATES do dispatch("UNIT_AURA", units[i]) end
        for i = 1, PLATES do dispatch("UNIT_SPELLCAST_START", units[i]) end
        for i = 1, PLATES do dispatch("UNIT_THREAT_LIST_UPDATE", units[i]) end
        dispatch("PLAYER_TARGET_CHANGED")
        dispatch("QUEST_LOG_UPDATE")
    end

    sweep()
    T.eq(core.Registry:IsEnabled(handle), true, "the run went through without error")

    local ROUNDS = 200
    local started = os.clock()
    for _ = 1, ROUNDS do sweep() end
    local perSweep = (os.clock() - started) / ROUNDS

    collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 20 do sweep() end
    local perSweepKb = (collectgarbage("count") - before) / 20

    -- Separately, the redraw path on which the rule is decided: the threat
    -- event arrives most often in combat, and it is what calls paint.
    local repaintStart = os.clock()
    for _ = 1, 2000 do
        for i = 1, PLATES do dispatch("UNIT_THREAT_LIST_UPDATE", units[i]) end
    end
    local perRepaint = (os.clock() - repaintStart) / 2000

    io.write(string.format(
        "  [rule cost] %d nameplates, half of them under a rule: a full "
        .. "run %.3f ms (%.2f KB), a redraw %.3f ms\n",
        PLATES, perSweep * 1000, perSweepKb, perRepaint * 1000))

    -- The limits are the ones of the second increment: the rules have no right
    -- to move any of them.
    T.ok(perSweep * 1000 < 4,
        string.format("a full run fits into a fraction of a frame: %.3f ms",
            perSweep * 1000))
    T.ok(perRepaint * 1000 < 1,
        string.format("thirty redraws cost less than a millisecond: %.3f ms",
            perRepaint * 1000))
    T.ok(perSweepKb < 24,
        string.format("the hot path hardly litters: %.2f KB", perSweepKb))

    local builtBefore = client.built
    for _ = 1, 5 do sweep() end
    T.eq(client.built, builtBefore, "the hot path builds no frames")

    -- The cost of the rules does not depend on their number: three dozen rules
    -- are no more expensive than two, because a dictionary decides rather than a scan.
    local many = {}
    for i = 1, pure.Rules.MAX do
        many[i] = { name = "Rule " .. i, text = "Creature " .. i,
            color = { 0.5, 0.5, 0.5 }, scale = 1.1 }
    end
    many[1] = RULES[1]
    many[2] = RULES[2]

    local own = handle:GetSettings()
    own.rules = many
    handle:Apply()

    local manyStart = os.clock()
    for _ = 1, 2000 do
        for i = 1, PLATES do dispatch("UNIT_THREAT_LIST_UPDATE", units[i]) end
    end
    local perMany = (os.clock() - manyStart) / 2000

    io.write(string.format(
        "  [rule cost] %d rules instead of 12: a redraw %.3f ms\n",
        pure.Rules.MAX, perMany * 1000))
    T.ok(perMany < perRepaint * 2 + 0.0005, string.format(
        "thirty rules are not twice as expensive as twelve: %.3f against %.3f ms",
        perMany * 1000, perRepaint * 1000))

    -- === A frame reused from under a rule ===
    --
    -- The main pool check for this increment. A creature under a rule leaves,
    -- the same frame goes to a creature with no rule, and the size must return
    -- to the ordinary one -- otherwise the rule would creep onto someone else.
    own.rules = RULES
    handle:Apply()

    local grown = nil
    for i = 1, #ours do
        if ours[i].scale == 1.4 then grown = ours[i] break end
    end
    T.ok(grown ~= nil, "a nameplate under a rule was found")

    for i = 1, PLATES do dispatch("NAME_PLATE_UNIT_REMOVED", units[i]) end
    if grown then
        T.eq(grown.scale, 1, "the return to the pool removed the rule size")
        T.eq(grown.shown, false, "and the frame itself is hidden")
    end

    -- Now nobody matches a rule: every creature is named differently and
    -- carries a foreign id.
    _G.UnitName = function() return "An ordinary boar" end
    _G.UnitGUID = function() return "Creature-0-3299-0-11-9999-000136DF91" end

    local reuse = client.built
    for i = 1, PLATES do dispatch("NAME_PLATE_UNIT_ADDED", units[i]) end
    T.eq(client.built, reuse, "the frames were taken from the pool rather than built anew")

    local left = 0
    for i = 1, #ours do
        if ours[i].scale ~= 1 then left = left + 1 end
        if ours[i].bar.r == 0.2 then left = left + 1 end
    end
    T.eq(left, 0,
        "neither the size nor the colour of the previous rule is left on the "
        .. "reused nameplates")

    -- And conversely: a rule no longer in the settings stops applying at once
    -- rather than after the creature leaves.
    _G.UnitName = function() return "Pack Leader" end
    for i = 1, PLATES do dispatch("NAME_PLATE_UNIT_REMOVED", units[i]) end
    for i = 1, PLATES do dispatch("NAME_PLATE_UNIT_ADDED", units[i]) end

    local ruledAgain = 0
    for i = 1, #ours do if ours[i].scale == 1.4 then ruledAgain = ruledAgain + 1 end end
    T.eq(ruledAgain, PLATES, "all thirty are under a rule again")

    own.rules = {}
    handle:Apply()

    local stillRuled = 0
    for i = 1, #ours do if ours[i].scale ~= 1 then stillRuled = stillRuled + 1 end end
    T.eq(stillRuled, 0, "a forgotten rule stopped applying at once")

    for key, value in pairs(saved) do _G[key] = value end
end

T.suite("nameplate rules: one owner of the colour and of the size")

do
    local function read(path)
        local handle = io.open(path, "r")
        if not handle then return nil end
        local text = handle:read("*a")
        handle:close()
        return text
    end

    -- The files are taken from the module TOC rather than listed here: a new
    -- file comes under these checks by itself.
    local FILES = {}
    for _, rel in ipairs(helpers.moduleFiles(MODULE)) do
        if not rel:find("^Locale/") then FILES[#FILES + 1] = rel end
    end
    T.ok(#FILES >= 9, "the module sources are listed in the TOC: " .. #FILES)

    local sources = {}
    for i = 1, #FILES do
        local text = read(PATH .. FILES[i])
        T.ok(text ~= nil, "opened " .. FILES[i])
        sources[FILES[i]] = text or ""
    end

    T.ok(sources["Rules.lua"] ~= nil, "Rules.lua was added to the module TOC")

    --- How many times a string occurs in a file, not counting comment lines.
    local function countCode(text, needle)
        local count = 0
        for line in text:gmatch("[^\r\n]+") do
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

    -- The bar colour is still written by one line of code in the whole module:
    -- a rule is the fourth source of the colour but not the fourth writer.
    local writers = 0
    for name, text in pairs(sources) do
        local hits = countCode(text, ":SetStatusBarColor(")
        if hits > 0 then
            writers = writers + hits
            T.eq(name, "Plate.lua", "only the drawing writes the bar colour")
        end
    end
    T.eq(writers, 1, "and it is still written by exactly one line of code")

    local calls = 0
    for _, text in pairs(sources) do
        calls = calls + countCode(text, "Plate.SetColor(")
    end
    T.eq(calls, 2, "Plate.SetColor is declared once and called once")

    T.eq(countCode(sources["NamePlates.lua"], "Colors.Bar("), 1,
        "the colour is decided by one call of the single rule")
    T.eq(countCode(sources["NamePlates.lua"], "Colors.For("), 0,
        "the old rule is not called around the precedence")

    -- The decision about a rule is one too: two places asking "which rule does
    -- this unit have" would diverge exactly as two colours would.
    T.eq(countCode(sources["NamePlates.lua"], "ruleFor("), 2,
        "the rule for a unit is asked by a declaration and one call")
    T.eq(countCode(sources["NamePlates.lua"], "Rules.For("), 1,
        "and one function decides it")

    -- The nameplate size is written by one line: the shared setting and the
    -- rule both go through it.
    local scalers = 0
    for name, text in pairs(sources) do
        local hits = countCode(text, "frame:SetScale(")
        if hits > 0 then
            scalers = scalers + hits
            T.eq(name, "Plate.lua", "only the drawing writes the nameplate scale")
        end
    end
    T.eq(scalers, 1, "and it is written by exactly one line of code")

    -- The case folding is the core one throughout the module. A copy of our own
    -- means a letter the copy will not have, and a silently unmatched rule.
    local folders = {}
    for name, text in pairs(sources) do
        if countCode(text, "string.lower") > 0
            or countCode(text, ":lower(") > 0 then
            folders[#folders + 1] = name
        end
    end
    T.eq(#folders, 0, "there is no case folding of its own in the module: "
        .. table.concat(folders, " | "))

    -- There is still not a single frame ticker, and the new file already stands
    -- under this check: the list is read from the TOC.
    local BANNED = {
        "OnUpdate", "C_Timer", "NewTicker", "NewTimer", "SetScript(\"OnUpdate",
    }
    local offences = {}
    for name, text in pairs(sources) do
        for i = 1, #BANNED do
            if countCode(text, BANNED[i]) > 0 then
                offences[#offences + 1] = name .. ": " .. BANNED[i]
            end
        end
    end
    table.sort(offences)
    T.eq(#offences, 0, "not a single frame ticker: "
        .. table.concat(offences, " | "))
end

T.suite("nameplate rules: the settings section through the eyes of the real AceConfig")

do
    local saved = {
        LibStub = _G.LibStub, securecallfunction = _G.securecallfunction,
        Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        CreateFrame = _G.CreateFrame, UIParent = _G.UIParent,
        C_NamePlate = _G.C_NamePlate,
    }

    _G.LibStub = nil
    _G.securecallfunction = function(fn, ...) return fn(...) end
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    dofile("Libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua")

    local registry = LibStub("AceConfigRegistry-3.0")
    T.eq(type(registry), "table", "AceConfigRegistry-3.0 loaded")

    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")
    _G.SlashCmdList = {}
    _G.C_NamePlate = {
        GetNamePlateForUnit = function() return nil end,
        GetNamePlates = function() return {} end,
    }

    -- An empty settings section but with a rule list: in the game it is created
    -- by the module default (defaults.rules), while a fake profile does not go
    -- through the defaults.
    local _, handle = bootstrap({ rules = {} })
    T.ok(handle ~= nil, "the module is registered")

    if handle then
        local ok, err = pcall(registry.ValidateOptionsTable, registry,
            handle.options, "Features/NamePlates")
        T.ok(ok, "the module section passes the AceConfig validation: " .. tostring(err))

        local args = handle.options.args
        local NEW = {
            "rulesList", "rulePick", "ruleNew", "ruleName", "ruleText",
            "ruleColor", "ruleRecolor", "ruleScale", "ruleAdd", "ruleUp",
            "ruleDown", "ruleForget",
        }
        local wrong = {}
        for i = 1, #NEW do
            local node = args[NEW[i]]
            if type(node) ~= "table" then
                wrong[#wrong + 1] = NEW[i] .. ": the node is missing"
            elseif node.level ~= nil then
                wrong[#wrong + 1] = NEW[i] .. ": there is an invented level field"
            end
        end
        T.eq(#wrong, 0, "every new node is in place and without extra fields: "
            .. table.concat(wrong, " | "))

        -- A fresh install changes nothing on screen: there are no rules.
        T.eq(type(handle.defaults.rules), "table", "the rules default is a table")
        T.eq(#handle.defaults.rules, 0, "and it is empty")

        -- The factor default is reachable by the slider.
        T.ok(handle.defaults ~= nil and args.ruleScale.min <= 1
            and args.ruleScale.max >= 1,
            "one is reachable by the rule size slider")

        -- The rule fields are inert until a rule is chosen: a button that does
        -- something with no rule chosen does it to the wrong one.
        T.eq(args.ruleColor.disabled(), true, "with no choice the colour is not editable")
        T.eq(args.ruleScale.disabled(), true, "and neither is the size")
        T.eq(args.ruleForget.disabled(), true, "and there is nothing to forget")
        T.eq(args.ruleAdd.disabled(), false, "while creating a new one is possible")

        -- The rule list in the settings is edited by the same buttons the player
        -- edits it with, and after an edit the plan is reassembled.
        handle.ruleDraftName = "Pack leaders"
        handle.ruleDraftText = "Pack Leader, 448"
        args.ruleAdd.func()

        local settings = handle:GetSettings()
        T.eq(#settings.rules, 1, "the rule was created by a section button")
        T.eq(handle.ruleChoice, "Pack leaders", "and chosen for editing right away")
        T.eq(args.ruleForget.disabled(), false, "now there is something to forget")

        args.ruleRecolor.set(nil, true)
        T.eq(type(settings.rules[1].color), "table", "the rule was assigned a colour")
        args.ruleColor.set(nil, 0.2, 0.4, 0.8)
        T.eq(settings.rules[1].color[3], 0.8, "and overwritten by the chosen one")
        T.eq(select(3, args.ruleColor.get()), 0.8, "and reads back")

        args.ruleScale.set(nil, 1.4)
        T.eq(settings.rules[1].scale, 1.4, "the size was assigned")

        args.ruleRecolor.set(nil, false)
        T.eq(settings.rules[1].color, nil, "and is removed by the same switch")

        args.ruleForget.func()
        T.eq(#settings.rules, 0, "the rule was forgotten by a section button")
        T.eq(handle.ruleChoice, nil, "and the choice was cleared with it")
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.LibStub = saved.LibStub
end

helpers.removeValidator()
