local helpers = require("helpers")

-- The second increment of the nameplate engine: the cast bar, filtered auras,
-- the threat colour, the quest icon and the truncation of long names.
--
-- What is checked falls into three parts, and the third is the main one.
--
-- 1. The pure rules: the aura filter, the colour decision together with the
--    threat precedence, truncating a name to a given width, the arithmetic of
--    the cast bar run. All of that are functions of numbers and strings, and
--    they are checked in every outcome.
--
-- 2. The attachment tally: every new element must be extinguished when the
--    frame returns to the pool, and must be extinguished **not by a list of
--    names**. The check creates on the frame an element the drawing knows
--    nothing about, and demands that it go out too.
--
-- 3. The cost. The spec calls nameplate performance the most important thing
--    in the project, and readiness "no frame rate drop on thirty simultaneous
--    nameplates". A claim of that kind must be a number rather than a promise,
--    so a fake client for thirty nameplates stands here, and the real hot path
--    of the module is run through it.

local MODULE = "Features/NamePlates"
local PATH = MODULE .. "/"

helpers.installValidator()

--- Load the pure parts of the module into a fresh namespace.
-- @return table
local function pureNamespace()
    local ns = helpers.newNamespace()
    -- The module takes the aura filter from the core (contract version 7),
    -- and the door must be opened before its files are read: behind it is the real Core/AuraFilter.lua.
    local coreFilter, restore = helpers.installAuraFilter()
    helpers.loadModule(MODULE, ns, { withRegistration = false })
    restore()
    ns.coreFilter = coreFilter
    return ns
end

local pure = pureNamespace()

T.suite("nameplates-2: the aura filter")

do
    local Filter = pure.Filter
    local shared = pure.coreFilter

    -- The list parsing, the name key and the mode words moved into the core:
    -- this module and the compact auras matched word for word. No copy is left
    -- here, and that is checked directly -- by identity rather than by words in a header.
    T.ok(type(shared) == "table", "the core filter is available to the module")
    T.eq(Filter.Key, shared.Key, "the module name key is the core one rather than its own")
    T.eq(Filter.NeedsKey, shared.NeedsKey, "and so is the question about the key")
    T.eq(Filter.Split, nil, "the module has no list parsing of its own left")
    T.eq(Filter.MODES, nil, "nor mode words of its own")

    -- Parsing the list. A comma and a newline are the same thing: the player is
    -- free to type the list as a column. It is now asked of the core -- where
    -- it lives.
    local _, names, count = shared.Split("Rend, Sunder Armor\nHamstring")
    T.eq(count, 3, "three names were parsed")
    T.eq(names["rend"], true, "the name was reduced to a key")
    T.eq(names["sunder armor"], true, "a two-word name was not torn apart")
    T.eq(names["hamstring"], true, "a newline is a separator too")

    -- Repeats are not doubled, empty fragments are discarded.
    local _, _, twice = shared.Split("Rend,,rend,  ,REND")
    T.eq(twice, 1, "repeats and empty fragments do not count: " .. twice)

    T.eq(Filter.Key("  Rend  "), "rend", "the key is trimmed and folded")
    T.eq(Filter.Key("   "), nil, "an empty name gives no key")
    T.eq(Filter.Key(nil), nil, "and neither does a missing name")

    -- The plan is assembled from the settings, and disabled auras stay disabled
    -- regardless of everything else.
    local off = Filter.Compile(nil)
    T.eq(off.enabled, false, "with no settings the auras are off")
    T.eq(Filter.Limit(off), 0, "and not a single icon is shown")
    T.eq(Filter.Allows(off, nil, true, true), false, "and not a single aura passes")

    local plan = Filter.Compile({
        auras = true, auraHarmful = true, auraHelpful = false,
        auraOnlyMine = true, auraLimit = 3,
    })
    T.eq(plan.enabled, true, "the auras are on")
    T.eq(Filter.Limit(plan), 3, "the icon limit is taken from the setting")

    T.eq(Filter.Allows(plan, nil, true, true), true, "our own harmful one passes")
    T.eq(Filter.Allows(plan, nil, false, true), false, "a foreign harmful one does not pass")
    T.eq(Filter.Allows(plan, nil, true, false), false,
        "the helpful ones are off -- our own helpful one does not pass either")

    -- The limit is clamped to the bounds: the value comes from SavedVariables.
    T.eq(Filter.Compile({ auras = true, auraLimit = 9000 }).limit,
        Filter.LIMIT.max, "too large a limit is clamped")
    T.eq(Filter.Compile({ auras = true, auraLimit = "garbage" }).limit,
        Filter.LIMIT.default, "a non-number gives the default")
    T.eq(Filter.Compile({ auras = true, auraLimit = 0 }).limit,
        Filter.LIMIT.min, "a zero is clamped to the lower bound")

    -- A mode with a list. The ban outranks everything.
    local deny = Filter.Compile({
        auras = true, auraHarmful = true, auraHelpful = true,
        auraMode = "deny", auraList = "Rend",
    })
    T.eq(deny.mode, "deny", "the mode is taken from the setting")
    T.eq(Filter.Allows(deny, "rend", true, true), false, "what is named is denied")
    T.eq(Filter.Allows(deny, "hamstring", true, true), true,
        "what is not named passes")

    -- "Show only the named" outranks "only mine": naming a spell is already an
    -- answer.
    local allow = Filter.Compile({
        auras = true, auraHarmful = true, auraHelpful = true,
        auraOnlyMine = true, auraMode = "allow", auraList = "Rend",
    })
    T.eq(Filter.Allows(allow, "rend", false, true), true,
        "what is named passes even when foreign")
    T.eq(Filter.Allows(allow, "hamstring", true, true), false,
        "what is not named does not pass, even when our own")

    -- An empty list switches the mode off entirely: a player who erased the
    -- line wants their former look back rather than to lose auras.
    local empty = Filter.Compile({
        auras = true, auraHarmful = true, auraMode = "allow", auraList = "  ",
    })
    T.eq(empty.mode, "off", "an empty list switches the mode off")
    T.eq(Filter.Allows(empty, nil, true, true), true, "and the auras are not lost")

    -- An invented mode from SavedVariables must mean nothing.
    T.eq(Filter.Compile({ auras = true, auraMode = "invention",
        auraList = "Rend" }).mode, "off", "an unknown mode means \"do not touch\"")

    T.eq(Filter.Allows(nil, "rend", true, true), false, "with no plan nothing passes")
    T.eq(Filter.Limit(nil), 0, "and there is no limit either")
end

T.suite("nameplates-2: the filter cost does not depend on the number of nameplates")

do
    -- The main property of the filter: the decision for one aura costs the same
    -- with a list of one spell and of a thousand. It is checked directly -- by
    -- time rather than by reasoning: a filter that walked the list for every
    -- aura would show a thousandfold difference here.
    local Filter = pure.Filter

    local long = {}
    for i = 1, 1000 do long[i] = "Spell " .. i end
    local short = Filter.Compile({ auras = true, auraHarmful = true,
        auraMode = "deny", auraList = "Spell 1" })
    local big = Filter.Compile({ auras = true, auraHarmful = true,
        auraMode = "deny", auraList = table.concat(long, ",") })

    local ROUNDS = 200000

    local function cost(plan)
        local started = os.clock()
        for _ = 1, ROUNDS do
            Filter.Allows(plan, "spell 500", true, true)
        end
        return os.clock() - started
    end

    cost(short)
    local one = cost(short)
    local thousand = cost(big)

    io.write(string.format(
        "  [filter cost] %d decisions: a list of one %.3f ms, "
        .. "of a thousand %.2f ms\n", ROUNDS, one * 1000, thousand * 1000))

    -- The margin is deliberately generous: the check guards the order of magnitude, not percent.
    T.ok(thousand < (one + 0.02) * 4,
        "a list of a thousand costs the same as a list of one")
end

T.suite("nameplates-2: the colour and the threat precedence")

do
    local Colors = pure.Colors

    local CLASS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    local REACT = { [2] = { r = 1, g = 0, b = 0 }, [5] = { r = 0, g = 1, b = 0 } }

    -- With no threat the rule is the one it was: the class for players, the
    -- reaction for everyone else. The fourth return value is the name of the
    -- rule that fired -- so the precedence can be checked directly.
    local r, g, b, why = Colors.Bar({ isPlayer = true, class = "WARRIOR",
        classColors = CLASS })
    T.eq(why, "class", "a player is coloured by class")
    T.eq(r, 0.78, "and in the colour of their own class")

    r, g, b, why = Colors.Bar({ reaction = 2, reactionColors = REACT })
    T.eq(why, "reaction", "a creature by reaction")

    -- A player with an unknown class is coloured by reaction, and the rule must
    -- call itself the reaction: a lying name would devalue the check itself.
    _, _, _, why = Colors.Bar({ isPlayer = true, class = "EVOKER",
        classColors = CLASS, reaction = 2, reactionColors = REACT })
    T.eq(why, "reaction", "an unknown class is the reaction rather than the class")

    -- The threat outranks both.
    r, g, b, why = Colors.Bar({ threatOn = true, threat = 3, reaction = 2,
        reactionColors = REACT, isPlayer = true, class = "WARRIOR",
        classColors = CLASS })
    T.eq(why, "threat", "the threat outranks the class")
    T.eq(r, Colors.THREAT[3][1] or Colors.THREAT[3].r, "and paints in its own colour")

    _, _, _, why = Colors.Bar({ threatOn = true, threat = 1, reaction = 4 })
    T.eq(why, "threat", "the threat outranks the reaction")

    -- Threat colouring switched off does not take part at all.
    _, _, _, why = Colors.Bar({ threatOn = false, threat = 3, reaction = 2,
        reactionColors = REACT })
    T.eq(why, "reaction", "a disabled threat paints nothing")

    -- Zero is the ordinary state of affairs and has no colour of its own:
    -- otherwise the threat would repaint half the screen permanently.
    _, _, _, why = Colors.Bar({ threatOn = true, threat = 0, reaction = 2,
        reactionColors = REACT })
    T.eq(why, "reaction", "a zero threat has no colour")

    -- And the threat is not applied to friendly ones: on a merchant it would
    -- mean a threat that does not exist.
    _, _, _, why = Colors.Bar({ threatOn = true, threat = 3, reaction = 5,
        reactionColors = REACT })
    T.eq(why, "reaction", "a friendly one never has a threat")

    T.eq(Colors.Threat(3, false), nil, "being unfriendly is required")
    T.eq(Colors.Threat("garbage", true), nil, "garbage instead of an index is not a colour")
    T.eq(Colors.Threat(9, true), nil, "an unknown index is not a colour")

    -- The threat colours are not declared a second time: they are the same
    -- entries of the fallback reaction palette, taken by meaning.
    T.eq(Colors.THREAT[3], Colors.REACTION[1], "the \"you are holding it\" colour is the same")
    T.eq(Colors.THREAT[1], Colors.REACTION[4], "and so is \"about to break loose\"")
end

T.suite("nameplates-2: truncating long names")

do
    local Names = pure.Names

    T.eq(Names.Length("abc"), 3, "Latin is counted by characters")
    T.eq(Names.Length("Вожак"), 5, "Cyrillic too by characters rather than by bytes")
    T.ok(#"Вожак" > 5, "while it holds more bytes: " .. #"Вожак")
    T.eq(Names.Length(nil), 0, "with no string the character count is zero")

    -- A short name is not touched.
    T.eq(Names.Truncate("Вожак", 10), "Вожак", "a short name passes as is")
    T.eq(Names.Truncate("Вожак", 5), "Вожак", "exactly at the limit, also as is")

    -- The limit is counted together with the ellipsis: eight characters on
    -- screen means eight characters rather than eight plus three.
    local cut = Names.Truncate("Гоблин-торговец", 8)
    T.eq(Names.Length(cut), 8, "the cut fits into the limit: " .. cut)
    T.eq(cut:sub(-3), "...", "and is marked with three dots")

    -- The main thing: cutting is allowed only on a character boundary. A byte
    -- cut would give a broken character here, and the player would see it rather than the author.
    local head = cut:sub(1, #cut - 3)
    T.eq(Names.Length(head) , 5, "five characters were left")
    T.eq(head, "Гобли", "and the cut went on a character boundary: " .. head)

    -- Less room than the ellipsis itself: then the first characters with no
    -- ellipsis. An empty string instead of a name is worse than a cut name.
    T.eq(Names.Truncate("Вожак", 2), "Во", "a limit smaller than the ellipsis means no ellipsis")
    T.eq(Names.Truncate("Вожак", 0), "", "a zero limit leaves nothing")
    T.eq(Names.Truncate("Вожак", "garbage"), "Вожак", "garbage instead of a limit does not cut")
    T.eq(Names.Truncate(nil, 5), "", "with no name an empty string is returned")

    -- How many characters fit into a width. The width and the font height are
    -- the same numbers the drawing uses.
    T.eq(Names.Budget(110, 10), 22, "110 pixels at font 10 gives 22 characters")
    T.eq(Names.Budget(40, 12), 6, "a narrow nameplate holds fewer")
    T.eq(Names.Budget(0, 10), 1, "a zero width leaves one character rather than zero")
    T.eq(Names.Budget(110, 0), 1, "and so does a zero font height")
    T.eq(Names.Budget("garbage", nil), 1, "garbage does not break the count")

    -- And the two glued together: a name fitted to a width.
    local fitted = Names.Fit("A very long creature name", 40, 12)
    T.eq(Names.Length(fitted), 6, "the name was squeezed into a narrow nameplate: " .. fitted)
    T.eq(Names.Fit("Вожак", 110, 10), "Вожак", "a wide nameplate has nothing to cut")
end

T.suite("nameplates-2: the run of the cast bar")

do
    local Cast = pure.Cast

    -- The game returns the start and the end in milliseconds and the time in
    -- seconds. Mixing the units is exactly the mistake this function closes.
    local from, to, seconds = Cast.Progress(1000, 3000, 1.5, false)
    T.eq(from, 0.25, "a quarter of the cast is behind")
    T.eq(to, 1, "it runs to the end")
    T.eq(seconds, 1.5, "and runs for a second and a half")

    -- A channel runs the other way: the spell is being spent.
    from, to, seconds = Cast.Progress(1000, 3000, 1.5, true)
    T.eq(from, 0.75, "three quarters of the channel are still ahead")
    T.eq(to, Cast.EPSILON, "it runs to zero")
    T.eq(seconds, 1.5, "in the same second and a half")

    -- The event may have arrived after the end: then there is nowhere to run rather than backwards.
    from, to, seconds = Cast.Progress(1000, 3000, 9, false)
    T.eq(from, 1, "after the end the bar is full")
    T.eq(seconds, 0, "and it runs for zero seconds")

    -- And before the start happens too: the client and server clocks diverge.
    from = Cast.Progress(1000, 3000, 0.5, false)
    T.eq(from, Cast.EPSILON, "before the start the bar is empty but not of zero width")

    -- A zero and a negative duration: there is no bar at all.
    T.eq(Cast.Progress(3000, 3000, 3, false), nil, "a zero duration is not a bar")
    T.eq(Cast.Progress(3000, 1000, 3, false), nil, "and neither is a negative one")
    T.eq(Cast.Progress(nil, 3000, 3, false), nil, "with no start there is nothing to compute")
    T.eq(Cast.Progress(1000, nil, 3, false), nil, "nor with no end")
    T.eq(Cast.Progress(1000, 3000, nil, false), nil, "nor with no time")

    T.eq(Cast.Height(nil), Cast.HEIGHT.default, "a height with no value gives the default")
    T.eq(Cast.Height(1), Cast.HEIGHT.min, "too low is clamped")
    T.eq(Cast.Height(900), Cast.HEIGHT.max, "and so is too high")
    T.eq(Cast.Height(7), 7, "a given one passes")
end

-- === The fake client =======================================================
--
-- The real hot path of the module is run through fake frames: outside the game
-- there is no CreateFrame, and checking the cost on "the absence of a frame"
-- would mean measuring emptiness. The fake does exactly what the module asks of a frame.

local client = {}

--- The shared part of any engine object.
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
    function o:SetScale(s) self.scale = s end
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
            function anim:SetOrigin() end
            function anim:SetScaleFrom(x) self.from = x end
            function anim:SetScaleTo(x) self.to = x end
            function anim:SetDuration(s) self.seconds = s end
            group.animations[#group.animations + 1] = anim
            return anim
        end
        function group:SetScript(name, fn) self[name] = fn end
        function group:Play() self.playing = true; client.plays = client.plays + 1 end
        function group:Stop() self.playing = false end
        return group
    end
    parent.regions[#parent.regions + 1] = t
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

--- A fake CreateFrame.
local function createFrame(kind, _, parent)
    local f = object(kind or "Frame")

    function f:CreateTexture() return texture(self) end
    function f:CreateFontString() return fontString(self) end
    function f:SetScript(name, fn) self[name] = fn end
    function f:RegisterEvent() end
    function f:UnregisterEvent() end

    if kind == "StatusBar" then
        function f:SetMinMaxValues(a, b) self.min, self.max = a, b end
        function f:SetValue(v) self.value = v; client.writes = client.writes + 1 end
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

T.suite("nameplates-2: the return to the pool extinguishes everything without knowing the names")

do
    client.built, client.writes, client.colors, client.plays = 0, 0, 0, 0

    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }
    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")

    local Plate = pure.Plate

    -- The styling is a fake: the real one is checked by its own suite, and here
    -- only the calls the drawing makes are needed.
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
    T.ok(frame ~= nil, "the frame was built on the fake engine")

    -- All three new elements are created and shown.
    Plate.LayoutExtras(frame, skin, 110, 10, 2, 5, 16, 3)
    Plate.StartCast(frame, 0.25, 1, 1.5, "Fireball", 1, 1, 1)
    Plate.SetAura(frame, 1, skin, "icon", 3, 10, 100)
    Plate.SetAura(frame, 2, skin, "icon", nil, nil, nil)
    Plate.ShowQuest(frame, true, skin)
    Plate.Ready(frame)
    Plate.SetLabels(frame, "Leader", 42)
    Plate.SetHealth(frame, 5, 10)

    T.eq(frame.cast.shown, true, "the cast bar is shown")
    T.eq(frame.auras[1].shown, true, "the first aura icon is shown")
    T.eq(frame.auras[2].shown, true, "and so is the second")
    T.eq(frame.quest.shown, true, "the quest icon is shown")
    T.eq(frame.bar.shown, true, "the health bar is shown")
    T.eq(frame.nameText:GetText(), "Leader", "the name is written")
    T.eq(frame.auras[1].count:GetText(), "3", "the stacks are written")

    -- An element the drawing knows nothing about: exactly what tomorrow's
    -- feature will be. A list of fields would forget it silently.
    local tomorrow = createFrame("Frame", nil, frame)
    tomorrow:Show()
    local tomorrowText = fontString(tomorrow)
    tomorrowText:SetText("a trace of the previous unit")

    frame.record.unit = "nameplate1"
    frame.record.alpha = 0.7

    Plate.Release(pool, frame)

    T.eq(frame.shown, false, "the frame itself is hidden")
    T.eq(frame.cast.shown, false, "the cast bar went out")
    T.eq(frame.cast.run.playing, false, "and its animation was stopped")
    T.eq(frame.cast.label:GetText(), "", "the spell name is erased")
    T.eq(frame.auras[1].shown, false, "the first aura icon went out")
    T.eq(frame.auras[2].shown, false, "and so did the second")
    T.eq(frame.auras[1].count:GetText(), "", "and the stacks are erased")
    T.eq(frame.quest.shown, false, "the quest icon went out")
    T.eq(frame.bar.shown, false, "the health bar went out")
    T.eq(frame.bar:GetValue(), 0, "and was emptied")
    T.eq(frame.nameText:GetText(), "", "the name is erased")
    T.eq(frame.levelText:GetText(), "", "the level is erased")

    -- The main check of the file.
    T.eq(tomorrow.shown, false,
        "an element the drawing knows nothing about went out too")
    T.eq(tomorrowText:GetText(), "",
        "and its label is erased -- by iteration rather than by a list of fields")

    -- The attachment record is entirely empty: by walking the keys rather than by a list.
    local left = 0
    for _ in pairs(frame.record) do left = left + 1 end
    T.eq(left, 0, "the attachment record is empty")

    T.eq(#pool.free, 1, "the frame returned to the pool")

    -- A frame taken from the pool gets its health bar back rather than looking
    -- broken.
    local again = Plate.Acquire(pool, skin)
    T.eq(again, frame, "the same frame came out of the pool")
    Plate.Ready(again)
    T.eq(again.bar.shown, true, "and the health bar came back")

    for key, value in pairs(saved) do _G[key] = value end
end

-- === The real module on a fake client ======================================

--- Assemble the core and the module on a fake client.
-- @param settings table the initial module settings
-- @return table core, table handle, table plates
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

T.suite("nameplates-2: thirty nameplates, the real event path")

local PLATES = 30
local units = {}
for i = 1, PLATES do units[i] = "nameplate" .. i end

do
    client.built, client.writes, client.colors, client.plays = 0, 0, 0, 0

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
        UnitChannelInfo = _G.UnitChannelInfo,
    }

    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")
    _G.SlashCmdList = {}

    -- The game nameplates: one per unit, all created in advance.
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
    _G.UnitName      = function() return "A very long creature name" end
    _G.UnitLevel     = function() return 42 end
    _G.UnitHealth    = function() return 40 end
    _G.UnitHealthMax = function() return 80 end
    _G.UnitIsUnit    = function() return false end
    _G.UnitThreatSituation = function() return 2 end
    _G.UnitIsQuestBoss     = function() return true end

    -- Five auras on every creature: three harmful, two helpful. Exactly the
    -- case the filter was written for.
    local AURAS = {
        HARMFUL = { "Rend", "Hamstring", "Sunder Armor" },
        HELPFUL = { "Battle Shout", "Blessing" },
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

    -- Everything is on: the most expensive of the possible looks is measured.
    local core, handle, ns = bootstrap({
        enabled = true,
        truncate = true, threat = true, quest = true,
        castbar = true, castHeight = 5,
        auras = true, auraSize = 16, auraLimit = 4,
        auraOnlyMine = true, auraHelpful = true, auraHarmful = true,
        auraMode = "off", auraList = "",
    })

    T.ok(handle ~= nil, "the module is registered on the fake client")
    core.Registry:EnableAll()
    T.eq(core.Registry:IsEnabled(handle), true, "and enabled")

    local dispatch = core.Events.Dispatch

    for i = 1, PLATES do
        dispatch("NAME_PLATE_UNIT_ADDED", units[i])
    end

    local state = nil
    do
        -- The tally lives inside the module; it is checked through the one
        -- thing visible from outside -- the built frames.
        state = ns.Engine
    end
    T.ok(state ~= nil, "the tally engine is in place")

    T.eq(core.Registry:IsEnabled(handle), true,
        "thirty attachments ran without error")

    -- What of that was actually drawn.
    local plate1 = plates[units[1]]
    local ours = plate1.UnitFrame
    T.eq(ours.alpha, 0, "the native trim is hidden by alpha")

    T.ok(client.plays >= PLATES, "the cast bar was started on every one: "
        .. client.plays)

    -- One common run of the hot path: health, auras, casting, the target, the
    -- quest log -- all on thirty nameplates.
    local function sweep()
        for i = 1, PLATES do
            dispatch("UNIT_HEALTH", units[i])
        end
        for i = 1, PLATES do
            dispatch("UNIT_AURA", units[i])
        end
        for i = 1, PLATES do
            dispatch("UNIT_SPELLCAST_START", units[i])
        end
        for i = 1, PLATES do
            dispatch("UNIT_THREAT_LIST_UPDATE", units[i])
        end
        dispatch("PLAYER_TARGET_CHANGED")
        dispatch("QUEST_LOG_UPDATE")
    end

    sweep()
    T.eq(core.Registry:IsEnabled(handle), true, "the run went through without error")

    -- The cost in time. The measurement is an average over many runs: one run
    -- is shorter than the clock resolution.
    local ROUNDS = 200
    local started = os.clock()
    for _ = 1, ROUNDS do sweep() end
    local perSweep = (os.clock() - started) / ROUNDS

    -- The cost in memory. "Not a single table on the hot path" is a claim, and
    -- it is checked the only way it can be checked: by how much garbage is left
    -- after a run.
    collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 20 do sweep() end
    local perSweepKb = (collectgarbage("count") - before) / 20

    -- Separately, the most frequent path apart from the rest: the health.
    local healthStart = os.clock()
    for _ = 1, 2000 do
        for i = 1, PLATES do dispatch("UNIT_HEALTH", units[i]) end
    end
    local perHealth = (os.clock() - healthStart) / 2000

    io.write(string.format(
        "  [nameplate cost] %d nameplates: a full run %.3f ms "
        .. "(%.2f KB), health only %.3f ms\n",
        PLATES, perSweep * 1000, perSweepKb, perHealth * 1000))

    -- Limits rather than "as it is now" numbers: an edit that makes the path
    -- an order of magnitude more expensive will fail the suite rather than
    -- reach the client. A frame at 60 frames per second is 16.7 ms; a full run
    -- on thirty nameplates must fit into a small fraction of it.
    T.ok(perSweep * 1000 < 4,
        string.format("a full run fits into a fraction of a frame: %.3f ms",
            perSweep * 1000))
    T.ok(perHealth * 1000 < 1,
        string.format("thirty health updates cost less than a millisecond: "
            .. "%.3f ms", perHealth * 1000))
    T.ok(perSweepKb < 24,
        string.format("the hot path hardly litters: %.2f KB", perSweepKb))

    -- The frames are created once. That is exactly what the pool exists for,
    -- and it is checked by not a single new one being built over two thousand runs.
    local builtBefore = client.built
    for _ = 1, 5 do sweep() end
    T.eq(client.built, builtBefore, "the hot path builds no frames")

    -- The name is squeezed into the width: the truncation setting really works
    -- on the live path rather than only in the pure rule.
    local frame = nil
    for i = 1, #_G.UIParent.children do
        local child = _G.UIParent.children[i]
        if child.nameText and child.shown then frame = child break end
    end
    T.ok(frame ~= nil, "our nameplate was found among the children of UIParent")
    if frame then
        T.ok(pure.Names.Length(frame.nameText:GetText()) <= 22,
            "the name was squeezed into the width: " .. frame.nameText:GetText())
        T.eq(frame.quest.shown, true, "the quest icon stands")
        T.eq(frame.cast.shown, true, "the cast bar is shown")
        T.eq(frame.auras[1].shown, true, "the aura icons are shown")
        T.eq(frame.auras[4].shown, true, "and there are exactly as many as the limit")
        T.eq(frame.auras[5], nil, "a fifth one was not created at all")

        -- The threat colour: the bar is painted in the threat colour rather than the reaction one.
        local r = pure.Colors.THREAT[2][1] or pure.Colors.THREAT[2].r
        T.eq(frame.bar.r, r, "the bar is painted by the threat")
    end

    -- Detaching all of them: nothing is left either shown or attached.
    for i = 1, PLATES do
        dispatch("NAME_PLATE_UNIT_REMOVED", units[i])
    end
    if frame then
        T.eq(frame.shown, false, "after it leaves the nameplate is hidden")
        T.eq(frame.cast.shown, false, "and the cast bar with it")
        T.eq(frame.auras[1].shown, false, "and the aura icons")
        T.eq(frame.quest.shown, false, "and the quest icon")
    end
    T.eq(plates[units[1]].UnitFrame.alpha, 1,
        "the native trim came back the same as it was")

    -- And re-attaching to the same frames builds nothing anew.
    local reuse = client.built
    for i = 1, PLATES do dispatch("NAME_PLATE_UNIT_ADDED", units[i]) end
    T.eq(client.built, reuse, "the second attachment takes the frames from the pool")

    -- Switching an element off removes it at once rather than after the creature leaves.
    local own = handle:GetSettings()
    own.castbar = false
    own.auras = false
    own.quest = false
    handle:Apply()
    if frame then
        T.eq(frame.cast.shown, false, "a disabled cast bar disappeared at once")
        T.eq(frame.auras[1].shown, false, "and the aura icons")
        T.eq(frame.quest.shown, false, "and the quest icon")
        T.eq(frame.shown, true, "while the nameplate itself remained")
    end

    for key, value in pairs(saved) do _G[key] = value end
end

T.suite("nameplates-2: one owner of the bar colour and not a single frame ticker")

do
    --- Read a whole file.
    local function read(path)
        local handle = io.open(path, "r")
        if not handle then return nil end
        local text = handle:read("*a")
        handle:close()
        return text
    end

    -- The files are taken from the module TOC rather than listed here. This
    -- check says "there is not a single frame ticker in the whole module", and
    -- a hand-written list would quietly narrow "the whole module" to "the files
    -- that existed when the check was written": a ticker created in a new file
    -- would be seen by nobody. The locales are not read -- they hold data, not code.
    local FILES = {}
    for _, rel in ipairs(helpers.moduleFiles(MODULE)) do
        if not rel:find("^Locale/") then FILES[#FILES + 1] = rel end
    end
    T.ok(#FILES >= 8, "the module sources are listed in the TOC: " .. #FILES)

    local sources = {}
    for i = 1, #FILES do
        local text = read(PATH .. FILES[i])
        T.ok(text ~= nil, "opened " .. FILES[i])
        sources[FILES[i]] = text or ""
    end

    --- How many times a string occurs in a file, not counting comment lines.
    -- The comments are discarded because they are where the rules are discussed,
    -- while the check guards the code rather than the account of it.
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

    -- The bar colour is written from exactly one place in the whole module.
    local writers = 0
    for name, text in pairs(sources) do
        local hits = countCode(text, ":SetStatusBarColor(")
        if hits > 0 then
            writers = writers + hits
            T.eq(name, "Plate.lua", "only the drawing writes the bar colour")
        end
    end
    T.eq(writers, 1, "and exactly one line of code writes it")

    -- And that single writer is called from one place too, and the colour is
    -- given to it by the single decision function.
    local calls = 0
    for _, text in pairs(sources) do
        calls = calls + countCode(text, "Plate.SetColor(")
    end
    T.eq(calls, 2, "Plate.SetColor is declared once and called once")

    T.eq(countCode(sources["NamePlates.lua"], "Colors.Bar("), 1,
        "the colour is decided by one call of the single rule")
    T.eq(countCode(sources["NamePlates.lua"], "Colors.For("), 0,
        "the old rule is not called around the threat precedence")
    T.eq(countCode(sources["NamePlates.lua"], "colorOf("), 2,
        "and the colour fact collector is declared and called once each too")

    -- There is not a single frame ticker, and that is guarded rather than promised.
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
    T.eq(#offences, 0, "not a single frame ticker: " .. table.concat(offences, " | "))

    -- And not a single line touching the frames of the cast bar module: the
    -- boundary between it and us is written in its brief.
    local outsiders = {}
    for name, text in pairs(sources) do
        if countCode(text, "UmbraUI_CastBars") > 0
            or countCode(text, "castbars") > 0 then
            outsiders[#outsiders + 1] = name
        end
    end
    T.eq(#outsiders, 0, "the cast bar module is untouched: "
        .. table.concat(outsiders, " | "))
end

T.suite("nameplates-2: the settings section through the eyes of the real AceConfig")

do
    -- Validating the section with the real library rather than with the fake
    -- from helpers. The reason is the one such a file exists in the suite for:
    -- a node with an unknown field means a settings window that does not open
    -- at all, and none of our checks would see that.
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
    T.eq(type(registry.ValidateOptionsTable), "function", "the validation is available")

    -- A check of the check: without it the green result below would mean nothing.
    T.err(function()
        registry:ValidateOptionsTable(
            { type = "group", name = "T", args = {
                a = { type = "toggle", name = "x", level = "basic" },
            } }, "T")
    end, "the validator rejects an invented level field")

    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")
    _G.SlashCmdList = {}
    _G.C_NamePlate = {
        GetNamePlateForUnit = function() return nil end,
        GetNamePlates = function() return {} end,
    }

    local _, handle = bootstrap({})
    T.ok(handle ~= nil, "the module is registered")

    if handle then
        local ok, err = pcall(registry.ValidateOptionsTable, registry,
            handle.options, "Features/NamePlates")
        T.ok(ok, "the module section passes the AceConfig validation: " .. tostring(err))

        -- Every new node is in place, and there are no invented fields on it.
        local args = handle.options.args
        local NEW = {
            "truncate", "threat", "quest", "castHeight", "auras",
            "auraHarmful", "auraHelpful", "auraOnlyMine", "auraLimit",
            "auraSize", "auraMode", "auraList",
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

        -- A fresh install changes nothing on screen: every feature of the
        -- second increment starts switched off.
        local defaults = handle.defaults
        T.eq(defaults.castbar, false, "the cast bar is off by default")
        T.eq(defaults.auras, false, "and so are the aura icons")
        T.eq(defaults.threat, false, "and so is the threat colour")
        T.eq(defaults.quest, false, "and so is the quest icon")
        T.eq(defaults.truncate, false, "and so is the name truncation")

        -- And every default stays reachable: a number lies within the bounds of
        -- its slider, and a selection value is among its values.
        T.ok(defaults.castHeight >= args.castHeight.min
            and defaults.castHeight <= args.castHeight.max,
            "the cast bar height default is reachable by the slider")
        T.ok(defaults.auraSize >= args.auraSize.min
            and defaults.auraSize <= args.auraSize.max,
            "the icon size default is reachable")
        T.ok(defaults.auraLimit >= args.auraLimit.min
            and defaults.auraLimit <= args.auraLimit.max,
            "the icon count default is reachable")
        T.ok(args.auraMode.values()[defaults.auraMode] ~= nil,
            "the list mode default is among its values")
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.LibStub = saved.LibStub
end

helpers.removeValidator()
