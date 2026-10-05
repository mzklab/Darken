local helpers = require("helpers")
local localekeys = require("localekeys")

helpers.installValidator()

-- The nameplate engine from a separate folder (Features/NamePlates).
--
-- The third real consumer of the public contract, and it is checked here by
-- the same code the game will load it with. What is checked falls into four
-- parts: the pure colour rules, the size arithmetic, the tally of what is
-- attached (the very place where nameplate reuse puts a foreign name on a
-- foreign bar), and the registration in the core together with standing the core styling down.
--
-- The drawing (Plate.lua) enters here exactly as far as it works without a
-- client: outside the game there is no CreateFrame, and the whole file is
-- written so that this is an absent frame rather than a breakage.

local MODULE = "Features/NamePlates"
local PATH = MODULE .. "/"

--- Load the module files into a fresh namespace.
-- The file list and the order are taken from the module TOC rather than copied here.
-- @param withRegistration boolean whether to load NamePlates.lua (it registers itself)
-- @return table
local function moduleNamespace(withRegistration)
    local ns = helpers.newNamespace()
    -- The module takes the aura filter from the core (contract version 7),
    -- and the door must be opened before its files are read: behind it is the real Core/AuraFilter.lua.
    local coreFilter, restore = helpers.installAuraFilter()
    helpers.loadModule(MODULE, ns, { withRegistration = withRegistration })
    restore()
    ns.coreFilter = coreFilter
    return ns
end

local ns = moduleNamespace(false)

T.suite("nameplate module: colour by class and by reaction")

do
    local Colors = ns.Colors

    local CLASS = {
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
        MAGE    = { 0.41, 0.80, 0.94 },
    }
    local REACTION = {
        [2] = { r = 1, g = 0, b = 0 },
        [5] = { r = 0, g = 1, b = 0 },
    }

    -- A player is coloured by class, and that is the only case where the
    -- class takes part at all: a creature has no class.
    local r, g, b = Colors.For({
        isPlayer = true, class = "WARRIOR", classColors = CLASS })
    T.eq(r, 0.78, "the player is coloured by class")

    r, g, b = Colors.For({
        isPlayer = true, class = "MAGE", classColors = CLASS })
    T.eq(g, 0.80, "an array of three numbers also reads as a colour")

    -- A non-player with the same class marker goes by reaction. Otherwise a
    -- creature with a class field in a foreign table would be enough to turn
    -- a boar into a warrior.
    r, g, b = Colors.For({ isPlayer = false, class = "WARRIOR",
        classColors = CLASS, reaction = 2, reactionColors = REACTION })
    T.eq(r, 1, "a creature is coloured by reaction rather than by class")
    T.eq(g, 0, "and specifically in the colour of its own reaction")

    r, g, b = Colors.For({ isPlayer = false, reaction = 5,
        reactionColors = REACTION })
    T.eq(g, 1, "a friendly reaction gives its own colour")

    -- A player whose class is not in the client table falls back to reaction:
    -- the class name comes from the game and may turn out to be unknown.
    r, g, b = Colors.For({ isPlayer = true, class = "EVOKER",
        classColors = CLASS, reaction = 2, reactionColors = REACTION })
    T.eq(r, 1, "an unknown class falls back to reaction")

    -- The client may have no reaction table at all -- then our own is used.
    r, g, b = Colors.For({ reaction = 4 })
    T.eq(r, Colors.REACTION[4].r, "with no client table the fallback is used")

    -- A holey client table: the index exists, the colour under it does not.
    r, g, b = Colors.For({ reaction = 4, reactionColors = { [4] = "garbage" } })
    T.eq(r, Colors.REACTION[4].r, "a hole in the client table is covered by the fallback")

    -- A unit out of sight has no reaction: then the chosen colour is used.
    r, g, b = Colors.For({ fallback = { r = 0.2, g = 0.3, b = 0.4 } })
    T.eq(g, 0.3, "with no class and no reaction the fallback colour is used")

    -- And white at the very end: a bar with no colour looks broken, while a
    -- silent nil would leave the colour of the previous unit on it.
    r, g, b = Colors.For(nil)
    T.eq(r, 1, "white at the very end")
    T.eq(b, 1, "in all three channels")

    T.eq(Colors.Hostile(2), true, "a hostile reaction is visible")
    T.eq(Colors.Hostile(4), true, "a neutral one counts as unfriendly")
    T.eq(Colors.Hostile(5), false, "a friendly one is not hostile")
    T.eq(Colors.Hostile(nil), false, "an unknown reaction is not hostile")
end

T.suite("nameplate module: sizes from the settings")

do
    local Geometry = ns.Geometry
    local B = Geometry.BOUNDS

    T.eq(Geometry.Clamp("width", 150), 150, "a given value passes")
    T.eq(Geometry.Clamp("width", 5), B.width.min, "too narrow is clamped")
    T.eq(Geometry.Clamp("width", 9000), B.width.max, "and so is too wide")

    -- The setting comes from SavedVariables, where anything can end up.
    T.eq(Geometry.Clamp("width", "garbage"), B.width.default,
        "a non-number means the default")
    T.eq(Geometry.Clamp("width", nil), B.width.default,
        "a missing value also means the default")
    T.eq(Geometry.Clamp("width", 0 / 0), B.width.default, "NaN means the default")
    T.eq(Geometry.Clamp("no such setting", 10), 0, "an unknown name gives zero")

    local w, h, s = Geometry.Plate({ width = 120, height = 14, scale = 1.5 })
    T.eq(w, 120, "the width is taken from the settings")
    T.eq(h, 14, "the height too")
    T.eq(s, 1.5, "and the scale")

    w, h, s = Geometry.Plate(nil)
    T.eq(w, B.width.default, "with no settings everything is default")
    T.eq(s, B.scale.default, "including the scale")

    -- The layout: the name above the bar, the full height is the sum plus the gap.
    local total, nameHeight, gap = Geometry.Layout(120, 14, 2)
    T.eq(total, 14 + 2 + 14, "the full height: the bar, the gap and the name line")
    T.eq(nameHeight, 14, "the name line is as tall as the bar")
    T.eq(gap, 2, "the gap is the one that was given")

    -- A bar four pixels tall is a legitimate setting, while a name line below
    -- eight pixels is unreadable.
    total, nameHeight = Geometry.Layout(120, 4, 2)
    T.eq(nameHeight, 8, "the name line is never below eight pixels")
    T.eq(total, 4 + 2 + 8, "and the full height is computed from it")

    T.eq(select(3, Geometry.Layout(120, 10, -5)), 0,
        "a negative gap is zero")

    T.eq(Geometry.Fill(50, 100), 0.5, "half the health is half the bar")
    T.eq(Geometry.Fill(0, 100), 0, "dead means an empty bar")
    T.eq(Geometry.Fill(100, 100), 1, "full health means a full bar")
    T.eq(Geometry.Fill(150, 100), 1, "there is nothing above the maximum")
    T.eq(Geometry.Fill(50, 0), 0, "a zero maximum does not divide by zero")
    T.eq(Geometry.Fill(nil, nil), 0, "with no numbers the bar is empty")
end

T.suite("nameplate module: standing down before a foreign engine")

do
    local Engine = ns.Engine

    local function loaded(name)
        return name == "Plater"
    end

    T.eq(Engine.ForeignOwner(loaded, {}), "Plater", "the foreign addon was found by name")
    T.eq(Engine.ForeignOwner(nil, { NeatPlates = {} }), "NeatPlates",
        "and by its global table too")
    T.eq(Engine.ForeignOwner(nil, {}), nil, "with no foreign addons there is nobody")
    T.eq(Engine.ForeignOwner(function() error("the foreign addon broke") end, {}),
        nil, "a failing foreign function does not count as a sign of an addon")

    -- A decision with three outcomes, each with its own word: the player
    -- needs to know not "yes or no" but why.
    T.eq(Engine.Decide(true, "Plater"), "foreign",
        "with a foreign engine it is we who stand down")
    T.eq(select(2, Engine.Decide(true, "Plater")), "Plater",
        "and we name before whom")
    T.eq(Engine.Decide(true, nil), "draw", "enabled with no foreigners, it draws")
    T.eq(Engine.Decide(false, nil), "off", "disabled, it does not draw")
    T.eq(Engine.Decide(false, "Plater"), "foreign",
        "a foreign engine outweighs our setting: it must be mentioned either way")
end

T.suite("nameplate module: the tally of reused nameplates")

do
    local Engine = ns.Engine
    local state = Engine.NewState()

    local plateA, plateB = { "game nameplate A" }, { "game nameplate B" }
    local frameA, frameB = { record = {} }, { record = {} }

    local record = Engine.Attach(state, "nameplate1", plateA, frameA,
        frameA.record)
    T.eq(record, frameA.record, "the record was taken off our frame rather than created")
    T.eq(record.unit, "nameplate1", "the unit is recorded")
    T.eq(record.plate, plateA, "the game nameplate is recorded")
    T.eq(state.count, 1, "one is in the tally")
    T.eq(Engine.Held(state, "nameplate1"), record, "and it is found by unit")

    -- The same game frame went to another unit while no "left" event
    -- arrived. That IS reuse, and here it must displace the former one.
    record.alpha = 0.7
    local second, stale = Engine.Attach(state, "nameplate2", plateA, frameB,
        frameB.record)
    T.eq(stale ~= nil, true, "the former unit of this nameplate was displaced")
    T.eq(stale.unit, "nameplate1", "and it is named")
    T.eq(stale.alpha, 0.7, "with the remembered alpha, so it can be restored")
    T.eq(state.count, 1, "the tally still holds one")
    T.eq(Engine.Held(state, "nameplate1"), nil,
        "the previous unit did not stay in the tally")
    T.eq(Engine.Clean(state, "nameplate1", nil), true,
        "and nothing is recorded under it")
    T.eq(state.byPlate[plateA], second, "the nameplate is recorded against the new unit")

    -- Returning a frame to the pool wipes the record clean: it lives on the
    -- frame and outlives the returns, so an unwiped field would go to a foreign unit.
    Engine.Wipe(stale)
    T.eq(next(stale), nil, "the record of a returned frame is empty")
    T.eq(frameA.record.unit, nil, "and no unit is left on our frame")
    T.eq(frameA.record.alpha, nil, "nor the alpha of the previous nameplate")

    -- Detaching clears both maps at once: one left behind would mean a frame
    -- that will never go to anyone again.
    local gone = Engine.Detach(state, "nameplate2")
    T.eq(gone, second, "detaching returns the record")
    T.eq(state.count, 0, "the tally is empty")
    T.eq(Engine.Clean(state, "nameplate2", plateA), true,
        "nothing is recorded by unit or by nameplate")
    T.eq(Engine.Detach(state, "nameplate2"), nil,
        "a repeated detach stays silent: the \"left\" event arrives for foreign ones too")

    -- Re-attaching the same unit to a different nameplate.
    Engine.Attach(state, "nameplate1", plateA, frameA, frameA.record)
    local again, previous = Engine.Attach(state, "nameplate1", plateB, frameB,
        frameB.record)
    T.eq(previous ~= nil, true, "the former attachment of this unit was displaced")
    T.eq(state.byPlate[plateA], nil, "the former nameplate did not stay in the tally")
    T.eq(state.byPlate[plateB], again, "the new one is recorded")
    T.eq(state.count, 1, "and the tally still holds one")

    -- A zone change takes away every nameplate at once.
    Engine.Attach(state, "nameplate2", plateA, frameA, frameA.record)
    local all = Engine.DetachAll(state)
    T.eq(#all, 2, "everything recorded was detached")
    T.eq(state.count, 0, "the tally is empty")
    T.eq(next(state.byUnit), nil, "the unit map is empty")
    T.eq(next(state.byPlate), nil, "and so is the nameplate map")

    -- Garbage on the input creates no records.
    T.eq(Engine.Attach(state, nil, plateA, frameA), nil, "with no unit we do not attach")
    T.eq(Engine.Attach(state, "nameplate1", nil, frameA), nil,
        "with no game nameplate we do not attach")
    T.eq(state.count, 0, "and the tally did not grow from it")

    T.eq(Engine.Wipe(nil), nil, "nothing to wipe -- fine")
    T.eq(Engine.Held(state, nil), nil, "a nil unit never appears in the tally")
end

T.suite("nameplate module: drawing without a client")

do
    -- Outside the game there is no CreateFrame, and the whole drawing is
    -- written so that this is an absent frame rather than a breakage: the checks must pass without a client.
    local Plate = ns.Plate
    local pool = Plate.NewPool()

    T.eq(Plate.Build(nil), nil, "with no engine no frame is built")
    T.eq(Plate.Acquire(pool, nil), nil, "and there is nothing to take from the pool")

    -- Every drawing function must survive a nil instead of a frame: in combat
    -- that is the difference between an empty screen and a yellow Lua error.
    Plate.Layout(nil, nil, 100, 10, 1, 2)
    Plate.SetTexture(nil, nil)
    Plate.SetColor(nil, 1, 1, 1)
    Plate.SetHealth(nil, 10, 20)
    Plate.SetLabels(nil, "Name", 42)
    Plate.ShowTarget(nil, true)
    Plate.ApplyFont(nil, nil)
    Plate.Release(pool, nil)
    T.eq(#pool.free, 0, "nothing to return -- the pool did not grow")
    T.eq(Plate.Native(nil, nil), nil, "there is no foreign nameplate -- nothing to touch")

    -- The unit frame inside a nameplate: the field does not exist at all --
    -- meaning the frame IS the nameplate, some builds keep the bars right on it.
    local inner = { "unit frame" }
    T.eq(Plate.UnitFrameOf({ UnitFrame = inner }), inner, "the UnitFrame field was found")
    T.eq(Plate.UnitFrameOf({ unitFrame = inner }), inner, "and the other spelling too")
    local bare = { "the nameplate itself" }
    T.eq(Plate.UnitFrameOf(bare), bare, "with no field the frame is the nameplate")
    T.eq(Plate.UnitFrameOf(nil), nil, "with no nameplate there is no frame")

    -- The alpha of a foreign nameplate: it is remembered and restored, and
    -- not a single field is left on the foreign frame.
    local calls = {}
    local foreign = {
        SetAlpha = function(_, value) calls[#calls + 1] = value end,
        GetAlpha = function() return 0.8 end,
    }
    T.eq(Plate.Native(foreign, nil), 0.8, "the former alpha is remembered")
    T.eq(calls[1], 0, "the native trim is hidden by alpha rather than by Hide")
    Plate.Native(foreign, 0.8)
    T.eq(calls[2], 0.8, "and restored to the same it was")

    local left = 0
    for key in pairs(foreign) do
        if key ~= "SetAlpha" and key ~= "GetAlpha" then left = left + 1 end
    end
    T.eq(left, 0, "not a single field of ours is left on the foreign nameplate")
end

T.suite("nameplate module: the translation")

do
    -- The rule is the same as in the core: the English string serves as the
    -- key, and a typo in a key shows in nothing -- the label simply stays English.
    local wanted = localekeys.literal(localekeys.read(PATH .. "NamePlates.lua"))
    T.ok(#wanted >= 12, "the keys were read out of the module sources: " .. #wanted)

    local seen = {}
    for i = 1, #wanted do seen[wanted[i]] = true end

    local nonAscii = {}
    for i = 1, #wanted do
        if wanted[i]:find("[\128-\255]") then
            nonAscii[#nonAscii + 1] = wanted[i]
        end
    end
    T.eq(#nonAscii, 0, "every key is English: " .. table.concat(nonAscii, " | "))

    for _, locale in ipairs({ "ruRU", "ukUA" }) do
        local translations = ns.Strings[locale]
        T.ok(type(translations) == "table", locale .. ": the table exists")

        local missing = {}
        for i = 1, #wanted do
            if type(translations[wanted[i]]) ~= "string" then
                missing[#missing + 1] = wanted[i]
            end
        end
        T.eq(#missing, 0, locale .. ": left untranslated: "
            .. table.concat(missing, " | "))

        local orphan = {}
        for key in pairs(translations) do
            if not seen[key] then orphan[#orphan + 1] = key end
        end
        T.eq(#orphan, 0, locale .. ": translations with no call site: "
            .. table.concat(orphan, " | "))
    end
end

T.suite("nameplate module: registering in the core and standing the styling down")

do
    -- The core is assembled for real and exposed as a global -- exactly as a
    -- separate addon sees it in the game.
    local saved = {
        Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        C_NamePlate = _G.C_NamePlate, UnitIsPlayer = _G.UnitIsPlayer,
        UnitReaction = _G.UnitReaction, UnitName = _G.UnitName,
        UnitLevel = _G.UnitLevel, UnitHealth = _G.UnitHealth,
        UnitHealthMax = _G.UnitHealthMax, UnitIsUnit = _G.UnitIsUnit,
    }

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

    local said = {}
    core.Registry.report = function(text) said[#said + 1] = text end
    core.Addon = {
        db = { profile = {}, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }
    core.flavor = "mists"

    -- The core nameplate styling subsystem is the one that must stand down.
    -- Here it is a fake: what is checked is the stand-down rule rather than
    -- the subsystem itself (which has its own suite).
    local coreStyling = { name = "nameplates", enabled = true }
    core.Registry:Register(coreStyling)

    -- The client: the game nameplate API and the unit facts.
    _G.SlashCmdList = {}
    _G.C_NamePlate = {
        GetNamePlateForUnit = function(unit) return { unit = unit } end,
        GetNamePlates = function() return {} end,
    }
    _G.UnitIsPlayer  = function() return false end
    _G.UnitReaction  = function() return 2 end
    _G.UnitName      = function(unit) return "Unit " .. tostring(unit) end
    _G.UnitLevel     = function() return 17 end
    _G.UnitHealth    = function() return 40 end
    _G.UnitHealthMax = function() return 80 end
    _G.UnitIsUnit    = function() return false end

    local module = moduleNamespace(true)

    local handle = core.Registry:Get("umbraplates")
    T.ok(handle ~= nil, "the module is registered: " .. table.concat(said, " | "))

    -- The name "nameplates" is taken by a core subsystem, and the module must
    -- be called something else. The check stands here so the name cannot be changed to the taken one.
    T.eq(core.Registry:Get("nameplates"), coreStyling,
        "the name \"nameplates\" belongs to the core, not to the module")

    if handle then
        T.eq(handle.api, 12, "the module declares contract version twelve")

        local settings = handle:GetSettings()
        T.eq(type(settings), "table", "the module settings live in the core profile")

        -- The default: off. A fresh install changes nothing on screen.
        T.eq(handle.defaults.enabled, false, "a fresh install draws nothing")

        core.Registry:EnableAll()
        T.eq(core.Registry:IsEnabled(handle), true, "the module works")

        -- A disabled module does not take the core styling away.
        T.eq(core.Registry:IsFailed("nameplates"), false,
            "a disabled module does not touch the core styling")

        -- The settings section: the level lives in arg.level and only there.
        local args = handle.options and handle.options.args or {}

        -- The slider bounds are taken from the same table as the value
        -- clamping: two lists of bounds would diverge silently.
        T.eq(args.width.min, module.Geometry.BOUNDS.width.min,
            "the lower slider bound is the same as the clamping one")

        -- The texture list: the first row is the native game texture.
        local values = args.texture.values()
        T.ok(values[handle.defaults.texture] ~= nil,
            "the default texture is in the selection list")

        -- The subscriptions go through the core: the module has no receiver of its own.
        T.eq(core.Events.Count("NAME_PLATE_UNIT_ADDED"), 1,
            "the module listens for a nameplate appearing")
        T.eq(core.Events.Count("NAME_PLATE_UNIT_REMOVED"), 1,
            "and for it leaving")
        T.eq(core.Events.Count("UNIT_HEALTH"), 1, "and for health")

        -- The command word is taken through the contract rather than written
        -- into SlashCmdList by hand: two modules with one word would displace each other silently.
        T.eq(core.CommandWords["plates"], "umbraplates",
            "the command word is recorded against the module")
        -- The word has no chat command of its own: it is the second word of
        -- the single addon command. What is checked here is that the parser
        -- knows it rather than it being executed: executing it toggles the
        -- setting, and the checks below would get a different state.
        T.eq(core.RunModuleCommand("nosuchword", ""), false,
            "an unknown word does not belong to the parser")

        -- While the module is off, the nameplate-appeared event does nothing:
        -- there is nothing to attach with and no reason to.
        T.eq(core.Events.Dispatch("NAME_PLATE_UNIT_ADDED", "nameplate1"), 1,
            "the event reached the module")
        T.eq(core.Registry:IsEnabled(handle), true,
            "and the handler ran without error")

        -- Enabling: now the core styling must stand down, and say so to the
        -- player once.
        local before = #said
        args.enabled.set(nil, true)
        T.eq(handle:GetSettings().enabled, true, "the value went into the profile")
        T.eq(core.Registry:IsFailed("nameplates"), true,
            "the core nameplate styling was stood down")
        T.eq(coreStyling.standDown, true,
            "and it knows that itself: the hooks on game functions go around the registry")
        T.eq(#said, before + 1, "it was said exactly once")
        T.ok(said[#said]:find("umbraplates", 1, true) ~= nil,
            "and it says who draws now: " .. tostring(said[#said]))

        -- Applying again does not say it a second time.
        before = #said
        handle:Apply()
        T.eq(#said, before, "applying again stays silent")

        -- The nameplate-appeared event now attaches. Outside the game there
        -- is no frame, so it does not get as far as the tally -- but no error happens either.
        core.Events.Dispatch("NAME_PLATE_UNIT_ADDED", "nameplate1")
        core.Events.Dispatch("UNIT_HEALTH", "nameplate1")
        core.Events.Dispatch("PLAYER_TARGET_CHANGED")
        core.Events.Dispatch("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        core.Events.Dispatch("PLAYER_ENTERING_WORLD")
        T.eq(core.Registry:IsEnabled(handle), true,
            "the whole event path ran without error")

        -- Switching back off: the core styling returns right away, with no
        -- interface reload, and that is said in one line.
        -- Formerly an apology stood here instead of a restore, and a player
        -- who switched the engine off got native nameplates with no core styling until /reload.
        before = #said
        args.enabled.set(nil, false)
        T.eq(core.Registry:IsFailed("nameplates"), false,
            "the core nameplate styling returned to service")
        T.eq(coreStyling.standDown, nil,
            "and it knows that itself: the stand-down flag is cleared")
        T.ok(#said > before, "the restore is reported in one line")

        -- The whole round in one session: enabled, stood down, disabled,
        -- restored, and so on as many times as the player clicks.
        args.enabled.set(nil, true)
        T.eq(core.Registry:IsFailed("nameplates"), true,
            "the second round stands the core styling down again")
        args.enabled.set(nil, false)
        T.eq(core.Registry:IsFailed("nameplates"), false,
            "and the second restore goes through too")

        -- The command toggles the same setting by the same path.
        core.RunModuleCommand("plates", "")
        T.eq(handle:GetSettings().enabled, true, "the command enabled the engine")
        core.RunModuleCommand("plates", "")
        T.eq(handle:GetSettings().enabled, false, "and disabled it again")

        -- The core disabling the module removes the subscriptions: the rule "a
        -- disabled module stops listening" is executed by the core.
        core.Registry:Disable("umbraplates", "a disable check")
        T.eq(core.Events.Count("NAME_PLATE_UNIT_ADDED"), 0,
            "the disabled module stopped listening")
    end

    for key, value in pairs(saved) do _G[key] = value end
end

T.suite("nameplate module: a foreign engine stands us down")

do
    local saved = { Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        Plater = _G.Plater, C_NamePlate = _G.C_NamePlate }

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

    local said = {}
    core.Registry.report = function(text) said[#said + 1] = text end
    core.Addon = {
        db = { profile = { umbraplates = { enabled = true } }, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }
    core.flavor = "mists"
    core.Registry:Register({ name = "nameplates" })

    _G.SlashCmdList = {}
    _G.Plater = { "a foreign nameplate engine" }
    _G.C_NamePlate = { GetNamePlateForUnit = function() return nil end }

    moduleNamespace(true)

    local handle = core.Registry:Get("umbraplates")
    T.ok(handle ~= nil, "the module is registered anyway")

    if handle then
        core.Registry:EnableAll()

        -- It is we who stand down, not the foreign addon: it knows nothing
        -- about us and cannot yield. The core styling meanwhile is left
        -- untouched by us -- it checks the same list itself.
        T.eq(handle.foreign, "Plater", "the foreign engine was recognised")
        T.eq(core.Registry:IsFailed("nameplates"), false,
            "and we do not take the core styling away")
        T.eq(core.Events.Count("NAME_PLATE_UNIT_ADDED"), 0,
            "and we subscribe to nothing")

        local told = false
        for i = 1, #said do
            if said[i]:find("Plater", 1, true) then told = true end
        end
        T.eq(told, true, "the player was told whom we stood down before")
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.Plater = nil
end

helpers.removeValidator()
