local helpers = require("helpers")
local localekeys = require("localekeys")

-- The fourth increment of the nameplate engine: the placement of the parts.
--
-- The editor answers the question "what stands where on a nameplate": the
-- name, the level, the cast bar, the aura icons, the quest icon and the
-- nameplate itself take the chosen side and are corrected by two numbers. What is checked falls into six parts.
--
-- 1. The pure rule: parsing the setting into a plan, anchoring one part,
--    garbage in the saved variables, editing and resetting.
--
-- 2. A fresh install changes nothing on screen. That is the main check of the
--    increment, and it is done by comparing not "by look" but by anchor point
--    name and by numbers: an empty setting must give exactly the anchors that
--    stood in the drawing before the placement appeared.
--
-- 3. The drawing: a part really does move, the corrections add to the place,
--    and "over the bar" anchors to the bar rather than to the box.
--
-- 4. The pool. The placement is not stored on a frame in any form -- it is
--    one for every nameplate -- and a frame taken from the pool stands by the
--    current placement rather than by the one it left under.
--
-- 5. The cost and combat. The plan is assembled once per settings edit, the
--    hot path does not ask about the placement at all, and no action is
--    deferred to the end of combat.
--
-- 6. One owner of the placement. A source walk: one pure function decides,
--    one line of the drawing writes, and the layout by itself moves nothing.

local MODULE = "Features/NamePlates"
local PATH = MODULE .. "/"

helpers.installValidator()

--- Load the pure parts of the module into a fresh namespace.
-- @return table
local function pureNamespace()
    local ns = helpers.newNamespace()
    local door, restore = helpers.installCore()
    helpers.loadModule(MODULE, ns, { withRegistration = false })
    restore()
    ns.coreDoor = door
    return ns
end

local pure = pureNamespace()

T.suite("nameplate placement: the pure rule")

do
    local Arrange = pure.Arrange

    T.ok(type(Arrange) == "table", "the placement loaded from the module TOC")

    -- The parts and their places are declared once and are asked for from the
    -- same place by the settings section: a second list would diverge from this silently.
    T.eq(#Arrange.PARTS, 6, "there are six parts")
    for i = 1, #Arrange.PARTS do
        local part = Arrange.PARTS[i]
        T.ok(type(Arrange.PLACES[part]) == "table",
            "the part " .. part .. " has declared places")
        T.ok(Arrange.Default(part) ~= nil,
            "and the first of them is the default: " .. tostring(Arrange.Default(part)))
    end

    -- The default of every part is the current look rather than something chosen anew.
    T.eq(Arrange.Default("name"), "top", "the name stands above the bar")
    T.eq(Arrange.Default("level"), "top", "the level is in the same place")
    T.eq(Arrange.Default("cast"), "bottom", "the cast bar is below the nameplate")
    T.eq(Arrange.Default("auras"), "top", "the aura icons are above it")
    T.eq(Arrange.Default("quest"), "left", "the quest icon is on the left")
    T.eq(Arrange.Default("plate"), "center", "the nameplate itself is where the game put it")

    T.eq(Arrange.Has("name", "over"), true, "the name can be over the bar")
    T.eq(Arrange.Has("quest", "over"), false,
        "while the quest icon cannot be over the bar")
    T.eq(Arrange.Has("no such part", "top"), false,
        "an unknown part has no places at all")

    -- An unknown place means the default: the value comes from the saved
    -- variables, and a part with no anchor would vanish from the screen for good.
    T.eq(Arrange.Place("name", "over"), "over", "a known place is accepted")
    T.eq(Arrange.Place("name", "top-left"), "top",
        "an unknown one gives the default")
    T.eq(Arrange.Place("name", nil), "top", "and so does nothing")
    T.eq(Arrange.Place("quest", "top"), "left",
        "the place of another part does not suit this one")

    -- The correction: the bounds are the slider ones, garbage is zero.
    T.eq(Arrange.Offset(12), 12, "a number within the bounds passes as is")
    T.eq(Arrange.Offset(-12.5), -12.5, "and so does a fractional one")
    T.eq(Arrange.Offset(Arrange.OFFSET.max + 1000), Arrange.OFFSET.max,
        "a number beyond the bound is clamped to the bound")
    T.eq(Arrange.Offset(Arrange.OFFSET.min - 1000), Arrange.OFFSET.min,
        "and from the other side")
    T.eq(Arrange.Offset("garbage"), 0, "garbage is zero")
    T.eq(Arrange.Offset(nil), 0, "and nothing is zero")
    T.eq(Arrange.Offset(0 / 0), 0, "and a non-number is zero")

    -- A fresh install: the plan is complete and made entirely of defaults.
    local empty = Arrange.Compile(nil)
    for i = 1, #Arrange.PARTS do
        local part = Arrange.PARTS[i]
        T.eq(empty[part].place, Arrange.Default(part),
            part .. ": the default place")
        T.eq(empty[part].x, 0, part .. ": no sideways correction")
        T.eq(empty[part].y, 0, part .. ": no vertical correction")
        T.eq(Arrange.Moved(empty, part), false, part .. ": untouched")
    end

    T.eq(Arrange.Compile({}).name.place, "top",
        "a settings section with no record is the same thing")

    -- Edited saved variables: foreign keys, non-tables, garbage instead of numbers.
    local junk = Arrange.Compile({ arrange = {
        name = { place = "over", x = 5, y = -7 },
        level = "not a table",
        quest = { place = "above", x = "garbage" },
        ["a foreign part"] = { place = "top" },
    } })
    T.eq(junk.name.place, "over", "the live record was read")
    T.eq(junk.name.x, 5, "and the sideways correction with it")
    T.eq(junk.name.y, -7, "and the vertical one")
    T.eq(junk.level.place, "top", "a non-table gives the default")
    T.eq(junk.quest.place, "left", "an unknown place gives the default")
    T.eq(junk.quest.x, 0, "garbage instead of a number gives zero")
    T.eq(junk["a foreign part"], nil, "a foreign part is not in the plan")

    T.eq(Arrange.Moved(junk, "name"), true, "a touched part is visible")
    T.eq(Arrange.Moved(junk, "cast"), false, "an untouched one is not")
    T.eq(Arrange.Moved(nil, "name"), false, "with no plan nothing is touched")

    -- Editing and resetting.
    local settings = {}
    T.eq(Arrange.SetPlace(settings, "cast", "top"), true, "the place was written")
    T.eq(Arrange.SetPlace(settings, "cast", "sideways"), false,
        "a non-existent place is not written")
    T.eq(Arrange.SetPlace(settings, "no such", "top"), false,
        "and neither is one for a non-existent part")
    T.eq(settings.arrange.cast.place, "top", "the record went into the settings")

    T.eq(Arrange.SetOffset(settings, "cast", "x", 40), true, "the correction was written")
    T.eq(Arrange.SetOffset(settings, "cast", "z", 40), false,
        "the screen has no third axis")
    T.eq(settings.arrange.cast.x, 40, "and it is in the settings")
    Arrange.SetOffset(settings, "cast", "y", 10000)
    T.eq(settings.arrange.cast.y, Arrange.OFFSET.max,
        "the written correction is clamped to the bound rather than to the screen")

    T.eq(Arrange.Reset(settings, "name"), false, "an untouched one has nothing to reset")
    T.eq(Arrange.Reset(settings, "cast"), true, "the touched one was reset")
    T.eq(settings.arrange.cast, nil,
        "and the record was erased entirely rather than overwritten with the default")

    Arrange.SetPlace(settings, "quest", "right")
    Arrange.SetPlace(settings, "auras", "bottom")
    T.eq(Arrange.ResetAll(settings), true, "everything was reset")
    T.eq(next(settings.arrange), nil, "and nothing remained")
    T.eq(Arrange.ResetAll(settings), false, "there is nothing to reset in an empty one")
    T.eq(Arrange.ResetAll(nil), false, "and nothing without settings either")
end

-- === A fake client that remembers the anchors ==============================
--
-- It differs from the fakes of the neighbouring suites in exactly one thing:
-- SetPoint here is a record rather than a no-op. Without it there is nothing
-- to check the placement with -- and the placement is the subject of the increment.

local client = { built = 0 }

local function object(kind)
    local o = { kind = kind, children = {}, regions = {}, shown = false,
        points = {} }

    function o:Show() self.shown = true end
    function o:Hide() self.shown = false end
    function o:SetShown(v) self.shown = v and true or false end
    function o:IsShown() return self.shown end
    function o:SetPoint(point, relative, relPoint, x, y)
        self.points[#self.points + 1] = { point = point, relative = relative,
            relPoint = relPoint, x = x, y = y }
    end
    function o:ClearAllPoints() self.points = {} end
    function o:SetAllPoints() end
    function o:SetSize(w, h) self.w, self.h = w, h end
    function o:SetWidth(w) self.w = w end
    function o:SetHeight(h) self.h = h end
    function o:SetScale(s) self.scale = s end
    function o:GetScale() return self.scale or 1 end
    function o:SetAlpha(a) self.alpha = a end
    function o:GetAlpha() return self.alpha or 1 end
    function o:SetDrawLayer() end
    function o:GetChildren() return unpack(self.children) end
    function o:GetRegions() return unpack(self.regions) end

    return o
end

--- The anchor of an object by point name.
-- @return table|nil
local function pointOf(object, name)
    if type(object) ~= "table" then return nil end
    for i = 1, #object.points do
        if object.points[i].point == name then return object.points[i] end
    end
    return nil
end

--- The single anchor of an object.
-- @return table|nil
local function onlyPoint(object)
    if type(object) ~= "table" then return nil end
    if #object.points ~= 1 then return nil end
    return object.points[1]
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
        function group:SetScript() end
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
        function f:SetStatusBarColor(r, g, b) self.r, self.g, self.b = r, g, b end
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

local SKIN = {
    Backdrop = function() return true end,
    Outline = function(frame, key)
        frame[key] = frame[key] or { TOP = object("Texture") }
        return true
    end,
    Color = function() return 0.7, 0.5, 0.7 end,
    Metrics = function() return { hair = 2, gap = 4, edge = 2 } end,
}

local WIDTH, HEIGHT, GAP, EDGE, SIZE, LIMIT = 110, 10, 2, 2, 16, 4
local CASTH = 5

--- Dress a frame the way the module does: the sizes, then everything else.
local function dress(Plate, frame, plate, plan)
    Plate.Layout(frame, plate, WIDTH, HEIGHT, 1, GAP, EDGE, plan)
    Plate.LayoutExtras(frame, SKIN, WIDTH, HEIGHT, GAP, CASTH, SIZE, LIMIT,
        plan)
    Plate.ShowQuest(frame, true, SKIN)
    Plate.LayoutExtras(frame, SKIN, WIDTH, HEIGHT, GAP, CASTH, SIZE, LIMIT,
        plan)
end

T.suite("nameplate placement: a fresh install moves nothing")

do
    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }
    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")

    local Plate = pure.Plate
    local pool = Plate.NewPool()
    local frame = Plate.Acquire(pool, SKIN)
    local plate = object("Frame")

    T.ok(frame ~= nil, "the frame was built")

    dress(Plate, frame, plate, nil)

    -- The numbers below are not a recomputation by new arithmetic but the very
    -- ones that stood in Plate.Layout and Plate.LayoutExtras before the
    -- placement appeared. The comparison goes by point name too: "the same by
    -- look" would diverge from "the same" exactly on the corner nobody checks.
    local WANT = {
        { what = "the nameplate itself", object = frame,
          point = "CENTER", relative = plate, relPoint = "CENTER",
          x = 0, y = 0 },
        { what = "the health bar", object = frame.bar,
          point = "BOTTOMLEFT", relative = frame, relPoint = "BOTTOMLEFT",
          x = 0, y = 0 },
        { what = "the name", object = frame.nameText,
          point = "BOTTOMLEFT", relative = frame, relPoint = "BOTTOMLEFT",
          x = 0, y = HEIGHT + GAP },
        { what = "the level", object = frame.levelText,
          point = "BOTTOMRIGHT", relative = frame, relPoint = "BOTTOMRIGHT",
          x = -EDGE, y = HEIGHT + GAP },
        { what = "the cast bar", object = frame.cast,
          point = "TOPLEFT", relative = frame, relPoint = "BOTTOMLEFT",
          x = 0, y = -GAP },
        { what = "the quest icon", object = frame.quest,
          point = "RIGHT", relative = frame, relPoint = "LEFT",
          x = -GAP, y = 0 },
    }

    for i = 1, #WANT do
        local want = WANT[i]
        local got = onlyPoint(want.object)
        T.ok(got ~= nil, want.what .. ": anchored by exactly one anchor")
        if got then
            T.eq(got.point, want.point, want.what .. ": its own point")
            T.eq(got.relPoint, want.relPoint, want.what .. ": the other point")
            T.eq(got.relative, want.relative, want.what .. ": what it is anchored to")
            T.eq(got.x, want.x, want.what .. ": the sideways offset")
            T.eq(got.y, want.y, want.what .. ": the vertical offset")
        end
    end

    -- The aura icons: a row to the right with a step of "side plus gap" -- as
    -- it was too.
    for i = 1, LIMIT do
        local got = onlyPoint(frame.auras[i])
        T.ok(got ~= nil, "icon " .. i .. ": anchored")
        if got then
            T.eq(got.point, "BOTTOMLEFT", "icon " .. i .. ": its own point")
            T.eq(got.relPoint, "TOPLEFT", "icon " .. i .. ": the other point")
            T.eq(got.x, (i - 1) * (SIZE + GAP), "icon " .. i .. ": the step")
            T.eq(got.y, GAP, "icon " .. i .. ": the gap")
        end
    end

    -- An empty plan and no plan are the same thing: otherwise the default would
    -- be written twice.
    local second = Plate.Acquire(pool, SKIN)
    dress(Plate, second, plate, pure.Arrange.Compile(nil))
    for i = 1, #WANT do
        local want = WANT[i]
        local mine = onlyPoint(WANT[i].object)
        local theirs = onlyPoint(({ frame = second, bar = second.bar,
            name = second.nameText, level = second.levelText,
            cast = second.cast, quest = second.quest })[
            ({ "frame", "bar", "name", "level", "cast", "quest" })[i]])
        if mine and theirs then
            T.eq(theirs.point, mine.point,
                want.what .. ": an empty plan is the same as no plan")
            T.eq(theirs.x, mine.x, want.what .. ": and the same offset")
            T.eq(theirs.y, mine.y, want.what .. ": and vertically too")
        end
    end

    for key, value in pairs(saved) do _G[key] = value end
end

T.suite("nameplate placement: a part moves where it was put")

do
    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }
    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")

    local Plate, Arrange = pure.Plate, pure.Arrange
    local pool = Plate.NewPool()
    local frame = Plate.Acquire(pool, SKIN)
    local plate = object("Frame")

    local plan = Arrange.Compile({ arrange = {
        name  = { place = "over", x = 3, y = 0 },
        level = { place = "bottom" },
        cast  = { place = "top" },
        auras = { place = "bottom" },
        quest = { place = "right" },
        plate = { x = 0, y = 25 },
    } })

    dress(Plate, frame, plate, plan)

    -- "Over the bar" anchors to the bar itself rather than to the box: above
    -- the bar the box also reserves the name line, and a label anchored to the
    -- box would go to the wrong place on the first height change.
    local name = onlyPoint(frame.nameText)
    T.ok(name ~= nil, "the name is anchored")
    if name then
        T.eq(name.point, "LEFT", "the name went over the bar")
        T.eq(name.relative, frame.bar, "and is anchored to the bar rather than to the box")
        T.eq(name.x, EDGE + 3, "the correction added to the inset of the place")
    end

    local level = onlyPoint(frame.levelText)
    if level then
        T.eq(level.point, "TOPRIGHT", "the level moved below the nameplate")
        T.eq(level.relPoint, "BOTTOMRIGHT", "and is anchored to the bottom of the box")
        T.eq(level.y, -GAP, "one gap downwards")
    end

    local cast = onlyPoint(frame.cast)
    if cast then
        T.eq(cast.point, "BOTTOMLEFT", "the cast bar moved to the top")
        T.eq(cast.relPoint, "TOPLEFT", "and is anchored to the top of the box")
        T.eq(cast.y, GAP, "one gap upwards")
    end

    local quest = onlyPoint(frame.quest)
    if quest then
        T.eq(quest.point, "LEFT", "the quest icon moved to the right")
        T.eq(quest.relPoint, "RIGHT", "and is anchored to the right edge")
        T.eq(quest.x, GAP, "one gap to the right")
    end

    for i = 1, LIMIT do
        local icon = onlyPoint(frame.auras[i])
        if icon then
            T.eq(icon.relPoint, "BOTTOMLEFT",
                "icon " .. i .. " moved down along with the rest")
            T.eq(icon.x, (i - 1) * (SIZE + GAP),
                "icon " .. i .. ": the step of the row did not change")
        end
    end

    -- The nameplate itself is moved only by the corrections: it has no place of
    -- its own on screen, and no side either.
    local whole = onlyPoint(frame)
    if whole then
        T.eq(whole.point, "CENTER", "the nameplate is still by its centre")
        T.eq(whole.relative, plate, "to the game nameplate")
        T.eq(whole.y, 25, "and lifted by the correction")
    end

    -- There may be no game nameplate: the layout happens outside the client
    -- too. The part stays unanchored rather than breaking Lua.
    local loose = Plate.Acquire(pool, SKIN)
    Plate.Layout(loose, nil, WIDTH, HEIGHT, 1, GAP, EDGE, plan)
    T.eq(#loose.points, 0, "with no game nameplate the frame stayed unanchored")
    T.ok(onlyPoint(loose.nameText) ~= nil, "while the name is in its place")

    for key, value in pairs(saved) do _G[key] = value end
end

T.suite("nameplate placement: the pool remembers nothing")

do
    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }
    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")

    local Plate, Arrange = pure.Plate, pure.Arrange
    local pool = Plate.NewPool()
    local frame = Plate.Acquire(pool, SKIN)
    local plate = object("Frame")

    local moved = Arrange.Compile({ arrange = {
        quest = { place = "right" },
        auras = { place = "bottom", y = -20 },
    } })
    dress(Plate, frame, plate, moved)
    T.eq(onlyPoint(frame.quest).point, "LEFT", "the quest icon is on the right")

    -- The pool promise from the previous increments must stay true after the
    -- parts got a placement too: a child the drawing knows nothing about is
    -- extinguished by iteration.
    local tomorrow = createFrame("Frame", nil, frame)
    tomorrow:Show()
    local tomorrowText = fontString(tomorrow)
    tomorrowText:SetText("a trace of the previous unit")

    frame.record.unit = "nameplate1"
    Plate.Release(pool, frame)

    T.eq(frame.shown, false, "the frame is hidden")
    T.eq(#frame.points, 0, "and unanchored from the foreign nameplate")
    T.eq(tomorrow.shown, false, "a child unknown to the drawing went out")
    T.eq(tomorrowText:GetText(), "", "and its label is erased")
    T.eq(next(frame.record), nil, "the attachment record is empty")

    -- The placement is not stored on a frame in any form: it is one for every
    -- nameplate and arrives as a plan from outside. So a frame taken from the
    -- pool stands by the current placement rather than by the one it left
    -- under -- and that is checked the same way as the colour and the size:
    -- the same frame, a different placement.
    local again = Plate.Acquire(pool, SKIN)
    T.eq(again, frame, "the pool handed out the same frame")

    dress(Plate, again, plate, Arrange.Compile(nil))
    T.eq(onlyPoint(again.quest).point, "RIGHT",
        "the quest icon returned to the side of the current placement")
    T.eq(onlyPoint(again.auras[1]).relPoint, "TOPLEFT",
        "and so did the aura icons")
    T.eq(onlyPoint(again.auras[1]).y, GAP,
        "together with a correction that no longer exists")

    -- A part has exactly one anchor however many times it is laid out:
    -- ClearAllPoints stands in the same single door as SetPoint.
    for _ = 1, 5 do dress(Plate, again, plate, moved) end
    T.eq(#again.quest.points, 1, "five layouts did not accumulate anchors")
    T.eq(#again.nameText.points, 1, "and the name has one too")

    for key, value in pairs(saved) do _G[key] = value end
end

-- === The real module on a fake client ======================================

--- Assemble the core and the module on a fake client.
-- @param settings table the initial module settings
-- @return table core, table handle, table ns
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

local PLATES = 30
local units = {}
for i = 1, PLATES do units[i] = "nameplate" .. i end

--- Install the fake client and return what has to be restored afterwards.
local function installClient()
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
        InCombatLockdown = _G.InCombatLockdown,
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
    _G.UnitIsPlayer  = function() return false end
    _G.UnitClass     = function() return "Warrior", "WARRIOR" end
    _G.UnitReaction  = function() return 2 end
    _G.UnitName      = function() return "Pack Leader" end
    _G.UnitGUID      = function()
        return "Creature-0-3299-0-11-448-000136DF91"
    end
    _G.UnitLevel     = function() return 42 end
    _G.UnitHealth    = function() return 40 end
    _G.UnitHealthMax = function() return 80 end
    _G.UnitIsUnit    = function() return false end
    _G.UnitThreatSituation = function() return 0 end
    _G.UnitIsQuestBoss     = function() return true end

    local AURAS = {
        HARMFUL = { "Rend", "Hamstring", "Sunder Armor" },
        HELPFUL = { "Battle Shout" },
    }
    _G.UnitAura = function(_, index, filter)
        local list = AURAS[filter]
        local name = list and list[index]
        if not name then return nil end
        return name, "icon", 1, nil, 10, clock + 5, "player"
    end
    _G.UnitCastingInfo = function()
        return "Fireball", nil, nil, (clock - 1) * 1000,
            (clock + 1) * 1000, false, nil, false
    end
    _G.UnitChannelInfo = function() return nil end

    -- Combat. The engine defers nothing by construction -- it owns not a
    -- single protected object -- and the editor has no right to change that.
    _G.InCombatLockdown = function() return true end

    return saved, plates
end

local FULL = {
    enabled = true, scale = 1,
    truncate = true, threat = true, quest = true,
    castbar = true, castHeight = 5,
    auras = true, auraSize = 16, auraLimit = 4,
    auraOnlyMine = true, auraHelpful = true, auraHarmful = true,
    auraMode = "off", auraList = "",
    rules = {}, arrange = {},
}

T.suite("nameplate placement: thirty nameplates move in combat")

do
    local saved = installClient()

    local core, handle, ns = bootstrap(FULL)
    T.ok(handle ~= nil, "the module is registered")
    core.Registry:EnableAll()

    local dispatch = core.Events.Dispatch
    for i = 1, PLATES do dispatch("NAME_PLATE_UNIT_ADDED", units[i]) end

    local ours = {}
    for i = 1, #_G.UIParent.children do
        local child = _G.UIParent.children[i]
        if child.nameText and child.shown then ours[#ours + 1] = child end
    end
    T.eq(#ours, PLATES, "thirty of our nameplates are shown")

    -- The attachment counter is the very number the editor decides by whether
    -- there is anything to lay out.
    T.ok(core.Counters.plates_engine >= PLATES,
        "the engine counted the attached nameplates: "
            .. core.Counters.plates_engine)
    T.eq(core.Counters.plates, nil,
        "and it did not touch the counter of the core subsystem")

    for i = 1, #ours do
        T.eq(onlyPoint(ours[i].quest).point, "RIGHT",
            "the quest icon is on the left, as it always was")
    end

    -- The plan is assembled once per settings edit, and that is measured by a
    -- call count rather than in milliseconds: a "so many ms" limit would stay
    -- green if the parsing came back onto the hot path and simply turned out
    -- to be cheap on the fake.
    local compiles, specs = 0, 0
    local realCompile, realSpec = ns.Arrange.Compile, ns.Arrange.Spec
    ns.Arrange.Compile = function(...)
        compiles = compiles + 1
        return realCompile(...)
    end
    ns.Arrange.Spec = function(...)
        specs = specs + 1
        return realSpec(...)
    end

    local function sweep()
        for i = 1, PLATES do dispatch("UNIT_HEALTH", units[i]) end
        for i = 1, PLATES do dispatch("UNIT_AURA", units[i]) end
        for i = 1, PLATES do dispatch("UNIT_SPELLCAST_START", units[i]) end
        for i = 1, PLATES do dispatch("UNIT_THREAT_LIST_UPDATE", units[i]) end
        dispatch("PLAYER_TARGET_CHANGED")
        dispatch("QUEST_LOG_UPDATE")
    end

    sweep()
    T.eq(compiles, 0, "the hot path never parses the placement")
    T.eq(specs, 0, "and never asks about it")

    -- A placement edit in combat: it must reach all thirty immediately. A
    -- nameplate that cannot move in combat is a nameplate that is wrong for
    -- the whole fight.
    local own = handle:GetSettings()
    T.eq(_G.InCombatLockdown(), true, "the edit happens in the thick of combat")
    ns.Arrange.SetPlace(own, "quest", "right")
    ns.Arrange.SetPlace(own, "cast", "top")
    ns.Arrange.SetOffset(own, "plate", "y", 30)
    handle:Apply()

    T.eq(compiles, 1, "the settings edit parsed the placement exactly once")

    local wrong = 0
    for i = 1, #ours do
        if onlyPoint(ours[i].quest).point ~= "LEFT" then wrong = wrong + 1 end
        if onlyPoint(ours[i].cast).relPoint ~= "TOPLEFT" then
            wrong = wrong + 1
        end
        if onlyPoint(ours[i]).y ~= 30 then wrong = wrong + 1 end
    end
    T.eq(wrong, 0, "all thirty were moved in that same instant, with no deferral")

    -- And conversely: a reset placement returns everything where it was on a
    -- fresh install, also immediately.
    compiles = 0
    ns.Arrange.ResetAll(own)
    handle:Apply()
    T.eq(compiles, 1, "and the reset parsed it once")

    local back = 0
    for i = 1, #ours do
        if onlyPoint(ours[i].quest).point == "RIGHT"
            and onlyPoint(ours[i].cast).relPoint == "BOTTOMLEFT"
            and onlyPoint(ours[i]).y == 0 then
            back = back + 1
        end
    end
    T.eq(back, PLATES, "all thirty returned to the look of a fresh install")

    -- A layout per settings edit is thirty nameplates of six-odd parts each,
    -- and not one question about the placement between edits.
    specs = 0
    handle:Apply()
    T.ok(specs > 0 and specs < PLATES * 40,
        "an edit asks about the placement once per part: " .. specs)

    ns.Arrange.Compile, ns.Arrange.Spec = realCompile, realSpec

    -- The cost. The limits are the ones of the second and third increments,
    -- and the placement has no right to move any of them.
    local ROUNDS = 200
    local started = os.clock()
    for _ = 1, ROUNDS do sweep() end
    local perSweep = (os.clock() - started) / ROUNDS

    collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 20 do sweep() end
    local perSweepKb = (collectgarbage("count") - before) / 20

    local repaintStart = os.clock()
    for _ = 1, 2000 do
        for i = 1, PLATES do dispatch("UNIT_THREAT_LIST_UPDATE", units[i]) end
    end
    local perRepaint = (os.clock() - repaintStart) / 2000

    io.write(string.format(
        "  [placement cost] %d nameplates: a full run %.3f ms "
        .. "(%.2f KB), a redraw %.3f ms%s",
        PLATES, perSweep * 1000, perSweepKb, perRepaint * 1000,
        string.char(10)))

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

    for key, value in pairs(saved) do _G[key] = value end
end

T.suite("nameplate placement: nothing to lay out -- and it says so")

do
    local saved = installClient()

    -- The engine is off: not a single attached nameplate, and the counter is
    -- claimed with a zero. That is not "we do not know" but "we know nothing came of it".
    local core, handle = bootstrap({ enabled = false, rules = {}, arrange = {} })
    core.Registry:EnableAll()

    T.eq(core.Counters.plates_engine, nil,
        "a disabled engine did not claim the counter at all")

    local args = handle.options.args
    local HIDDEN = { "partPick", "partPlace", "partX", "partY", "partReset" }
    for i = 1, #HIDDEN do
        T.eq(args[HIDDEN[i]].hidden(), true,
            HIDDEN[i] .. ": the placement surface is not shown")
    end

    -- The way back is always visible: the placement may be left over from a
    -- previous session, and it must be resettable with not a single nameplate on screen.
    T.eq(args.arrangeReset.hidden, nil, "everything can be reset even now")

    local silent = args.arrangeAbout.name()
    T.ok(type(silent) == "string" and #silent > 0, "and it says why")

    -- The same section when there are nameplates: the surface is in place, and
    -- it says something else.
    core.Counters.plates_engine = 3
    for i = 1, #HIDDEN do
        T.eq(args[HIDDEN[i]].hidden(), false,
            HIDDEN[i] .. ": the surface came back along with the nameplates")
    end
    T.ok(args.arrangeAbout.name() ~= silent,
        "and the explanation changed along with it")

    -- The nameplate itself has no side, and a list of one value is not shown
    -- for it.
    handle.partChoice = "plate"
    T.eq(args.partPlace.hidden(), true, "the whole nameplate has no side")
    T.eq(args.partX.hidden(), false, "while it does have corrections")
    handle.partChoice = "name"
    T.eq(args.partPlace.hidden(), false, "the name does have a side")

    for key, value in pairs(saved) do _G[key] = value end
end

T.suite("nameplate placement: the engine counter is not the core subsystem counter")

do
    -- What this section is for. The editor asks "did THIS engine attach
    -- anything", while it used to ask the total number of attached nameplates
    -- -- the very one the core subsystem (Modules/NamePlates.lua) increments too.
    -- A fresh install keeps the engine off while the core subsystem works and
    -- styles the nameplates, and the editor was shown over a disabled engine:
    -- the controls in place while they do nothing at all.
    --
    local saved = installClient()

    local core, handle = bootstrap({ enabled = false, rules = {}, arrange = {} })
    core.Registry:EnableAll()

    -- Exactly what the core subsystem writes, and in exactly the same field.
    core.Counters.plates = (core.Counters.plates or 0) + 1

    local args = handle.options.args
    local HIDDEN = { "partPick", "partPlace", "partX", "partY", "partReset" }
    for i = 1, #HIDDEN do
        T.eq(args[HIDDEN[i]].hidden(), true,
            HIDDEN[i] .. ": a foreign counter does not open the surface")
    end

    -- While our own does.
    core.Counters.plates_engine = 1
    for i = 1, #HIDDEN do
        T.eq(args[HIDDEN[i]].hidden(), false,
            HIDDEN[i] .. ": our own counter opens the surface")
    end

    for key, value in pairs(saved) do _G[key] = value end
end

T.suite("nameplate placement: a disabled engine shows what was saved")

do
    -- What this section is for. The setting is written into settings.arrange
    -- while the controls read from the parsed plan, and the plan was parsed
    -- only after the "the engine is on" check. With the engine off the select
    -- and both sliders snapped back to the former value on screen, the "reset
    -- part" button stayed disabled -- while the written value took effect from
    -- the next login.
    local saved = installClient()

    local core, handle = bootstrap({ enabled = false, rules = {}, arrange = {} })
    core.Registry:EnableAll()

    local args = handle.options.args
    handle.partChoice = "name"

    T.eq(args.partPlace.get(), "top", "at first the name stands where it always does")
    T.eq(args.partReset.disabled(), true, "and there is nothing to reset")

    args.partPlace.set(nil, "over")
    T.eq(args.partPlace.get(), "over",
        "the chosen place is shown rather than thrown back")

    args.partX.set(nil, 7)
    T.eq(args.partX.get(), 7, "and so is the correction")

    T.eq(args.partReset.disabled(), false,
        "while \"reset part\" became available: there is something to reset now")

    args.partReset.func()
    T.eq(args.partPlace.get(), "top", "the reset is visible in the same place and at once")
    T.eq(args.partReset.disabled(), true, "and the button is disabled again")

    for key, value in pairs(saved) do _G[key] = value end
end

T.suite("nameplate placement: one owner of the anchor")

do
    local function read(path)
        local file = io.open(path, "r")
        if not file then return nil end
        local text = file:read("*a")
        file:close()
        return text
    end

    -- The files are taken from the module TOC: a new file comes under these checks by itself.
    local FILES = {}
    for _, rel in ipairs(helpers.moduleFiles(MODULE)) do
        if not rel:find("^Locale/") then FILES[#FILES + 1] = rel end
    end

    local sources = {}
    for i = 1, #FILES do sources[FILES[i]] = read(PATH .. FILES[i]) or "" end
    T.ok(sources["Arrange.lua"] ~= nil and #sources["Arrange.lua"] > 0,
        "Arrange.lua was added to the module TOC")

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

    --- The body of one function: from its declaration to the next one.
    local function bodyOf(text, name)
        local from = text:find("\nfunction " .. name .. "(", 1, true)
        if not from then return nil end
        local to = text:find("\nfunction ", from + 1, true) or #text
        return text:sub(from, to)
    end

    -- One door in the whole module writes the anchor. The same argument the
    -- colour lives by: two places moving the parts would diverge silently, and
    -- a nameplate would depend on whose layout ran last.
    local writers = {}
    for name, text in pairs(sources) do
        if countCode(text, ":SetPoint(") > 0 then writers[#writers + 1] = name end
    end
    table.sort(writers)
    T.eq(table.concat(writers, " | "), "Plate.lua",
        "only the drawing writes anchors")

    T.eq(countCode(sources["NamePlates.lua"], "SetPoint("), 0,
        "the layout in the head file anchors nothing")

    local place = bodyOf(sources["Plate.lua"], "Plate.Place")
    T.ok(place ~= nil, "Plate.Place is declared")
    T.eq(countCode(place, ":SetPoint("), 1,
        "and writes the anchor in exactly one line")
    T.eq(countCode(place, ":ClearAllPoints("), 1,
        "and clears the former one there rather than somewhere else")

    -- The two functions that used to lay the parts out themselves now anchor
    -- nothing: any future edit creating a second anchor there will fail the
    -- suite.
    for _, name in ipairs({ "Plate.Layout", "Plate.LayoutExtras" }) do
        local body = bodyOf(sources["Plate.lua"], name)
        T.ok(body ~= nil, name .. " is declared")
        T.eq(countCode(body, "SetPoint("), 0,
            name .. " anchors nothing itself")
    end

    -- The decision about the place is one, and it is pure: a declaration plus
    -- a single call.
    local decisions = 0
    for _, text in pairs(sources) do
        decisions = decisions + countCode(text, "Arrange.Spec(")
    end
    T.eq(decisions, 2, "Arrange.Spec is declared once and called once")

    T.eq(countCode(sources["NamePlates.lua"], "Arrange.Compile("), 2,
        "the placement plan is assembled by the default and by a settings edit")

    -- The layout comes from one place both for a new nameplate and for a
    -- settings edit: two identical sequences would diverge the same way two
    -- colours would.
    T.eq(countCode(sources["NamePlates.lua"], "ns.Plate.Layout("), 1,
        "the sizes are laid out by one call")
    T.eq(countCode(sources["NamePlates.lua"], "ns.Plate.LayoutExtras("), 1,
        "and so are the outer parts")
    T.eq(countCode(sources["NamePlates.lua"], "dress("), 3,
        "one function dresses the frame: a declaration and two call sites")

    -- Not a single deferred action: the engine owns no protected object, and
    -- the editor has no right to change that.
    local deferred = {}
    for name, text in pairs(sources) do
        if countCode(text, ":Secure(") > 0
            or countCode(text, "InCombatLockdown") > 0 then
            deferred[#deferred + 1] = name
        end
    end
    T.eq(#deferred, 0, "nothing is deferred in combat: "
        .. table.concat(deferred, " | "))

    -- There are still no frame tickers, and the new file stands under this check.
    local BANNED = {
        "OnUpdate", "C_Timer", "NewTicker", "NewTimer",
    }
    local offences = {}
    for name, text in pairs(sources) do
        for i = 1, #BANNED do
            if countCode(text, BANNED[i]) > 0 then
                offences[#offences + 1] = name .. ": " .. BANNED[i]
            end
        end
    end
    T.eq(#offences, 0, "not a single frame ticker: "
        .. table.concat(offences, " | "))

    -- The player-facing strings live in the head file: the translation
    -- completeness check reads the keys only from there, and a string that
    -- moved into Arrange.lua would become untranslatable silently.
    T.eq(countCode(sources["Arrange.lua"], "Localize("), 0,
        "the pure rule does not talk to the player")

    local wanted = localekeys.literal(localekeys.read(PATH .. "NamePlates.lua"))
    local seen = {}
    for i = 1, #wanted do seen[wanted[i]] = true end
    T.eq(seen["Part to Place"], true,
        "the editor keys are read out by the translation check")
end

T.suite("nameplate placement: the settings section through the eyes of the real AceConfig")

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

    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")
    _G.SlashCmdList = {}
    _G.C_NamePlate = {
        GetNamePlateForUnit = function() return nil end,
        GetNamePlates = function() return {} end,
    }

    local core, handle = bootstrap({ rules = {}, arrange = {} })
    T.ok(handle ~= nil, "the module is registered")

    if handle then
        local ok, err = pcall(registry.ValidateOptionsTable, registry,
            handle.options, "Features/NamePlates")
        T.ok(ok, "the module section passes the AceConfig validation: " .. tostring(err))

        local args = handle.options.args
        local NEW = {
            "partPick", "partPlace", "partX", "partY", "partReset",
            "arrangeReset",
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

        -- A fresh install: the placement is empty, and that means "as it was".
        T.eq(type(handle.defaults.arrange), "table",
            "the placement default is a table")
        T.eq(next(handle.defaults.arrange), nil, "and it is empty")

        -- The correction default is reachable by the slider, and the chosen
        -- place is among the values of its own list.
        T.ok(args.partX.min <= 0 and args.partX.max >= 0,
            "zero is reachable by the correction slider")
        core.Counters.plates_engine = 1
        handle.partChoice = "auras"
        local values = args.partPlace.values()
        T.ok(values[args.partPlace.get()] ~= nil,
            "the chosen place is among the list values")
        T.eq(args.partReset.disabled(), true,
            "there is nothing to reset an untouched part with")

        local parts = args.partPick.values()
        local missing = {}
        for _, part in ipairs({ "name", "level", "cast", "auras", "quest",
                "plate" }) do
            if parts[part] == nil then missing[#missing + 1] = part end
        end
        T.eq(#missing, 0, "every part is in the selection list: "
            .. table.concat(missing, " | "))
    end

    for key, value in pairs(saved) do _G[key] = value end
    helpers.removeValidator()
end
