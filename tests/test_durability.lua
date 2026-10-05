local helpers = require("helpers")
local C = require("cyrillic")

-- The durability module: the pure part, the labels, the drawing and the joining with the core.
--
-- The order of the checks is the same as the other modules': first what can be
-- asked with no game at all (the worst slot, the state, the colour), then the
-- completeness of the translations, then the drawing layer on a fake engine,
-- and only at the end the registration in the real core. The first three
-- answer the question "is it correct", the last the question "will it reach the player".

local FOLDER = "Features/Durability"

--============================================================================
-- 1. The pure part
--============================================================================

T.suite("the durability: the worst slot and the state")

local pure = helpers.loadModule(FOLDER, nil, { withRegistration = false })
local Rules = pure.Rules

T.eq(type(Rules), "table", "the pure part was read")
T.ok(#Rules.SLOTS >= 10, "the equipment slots are enumerated: " .. #Rules.SLOTS)

-- The slots' numbers do not repeat: a repeated number would be read twice and
-- would double one item's weight in the choice of the worst.
do
    local seen, twice = {}, {}
    for i = 1, #Rules.SLOTS do
        local slot = Rules.SLOTS[i].slot
        if seen[slot] then twice[#twice + 1] = tostring(slot) end
        seen[slot] = true
    end
    T.eq(#twice, 0, "the slots' numbers do not repeat: " .. table.concat(twice, " "))
end

T.eq(Rules.LabelFor(1), "Head", "a slot's label is found by its number")
T.eq(Rules.LabelFor(4), nil, "a slot with no durability is not on the list")

do
    local worst, counted = Rules.Worst({
        { slot = 1,  current = 90, maximum = 100 },
        { slot = 5,  current = 30, maximum = 120 },
        { slot = 16, current = 55, maximum = 60 },
    })
    T.eq(worst and worst.slot, 5, "the most worn share was chosen as the worst")
    T.eq(counted, 3, "three usable readings were counted")
end

do
    -- An empty slot, a broken item and rubbish out of the game are three
    -- different cases, and the first and the third have no right to become zero per cent.
    local worst, counted = Rules.Worst({
        { slot = 1, current = nil, maximum = nil },
        { slot = 5, current = 10,  maximum = 0 },
        { slot = 7, current = 40,  maximum = 100 },
    })
    T.eq(worst and worst.slot, 7, "the readings with a zero maximum were skipped")
    T.eq(counted, 1, "and did not get into the count of the usable ones")
end

T.eq(Rules.Worst(nil), nil, "a non-table gives no worst slot")
T.eq(select(2, Rules.Worst({})), 0, "an empty set gives zero readings")

T.eq(Rules.State(nil, 35), nil, "with no reading there is no state")
T.eq(Rules.State(0, 35), "broken", "zero per cent is broken")
T.eq(Rules.State(34, 35), "warn", "below the threshold is an alarm")
T.eq(Rules.State(35, 35), "fine", "exactly the threshold does not count as an alarm")
T.eq(Rules.State(100, 35), "fine", "an intact item is calm")

T.eq(Rules.Tint("broken"), "warn", "the broken is painted in the alarm colour")
T.eq(Rules.Tint("warn"), "warn", "the alarming in the same one")
T.eq(Rules.Tint("fine"), "textDim", "the calm is muted")
T.eq(Rules.Tint(nil), nil, "no state means no colour")

-- "Always show" outranks the absence of readings: the player switched the
-- setting on and is entitled to see the block rather than an empty screen with nothing to understand.
T.eq(Rules.Visible(nil, true), true,
    "with no readings the block is shown all the same, since always was asked")
T.eq(Rules.Visible(nil, false), false,
    "while with no request there is nothing to show")
T.eq(Rules.Visible("fine", false), false, "a calm indicator is hidden")
T.eq(Rules.Visible("fine", true), true, "but at the player's request it is shown")
T.eq(Rules.Visible("warn", false), true, "an alarming one shows itself")
T.eq(Rules.Visible("broken", false), true, "and so does a broken one")

T.suite("the durability: the core computes the percentage")

do
    -- The percentage is taken from the core's number formatting rather than
    -- written by a division of our own: the rule of writing a number in the
    -- addon is a single one, and a copy beside it would diverge from it on the day the original is edited.
    local fmt, restore = helpers.installFormat()

    T.eq(Rules.Percent(50, 100), fmt.Percent(50, 100), "the answer is the core's")
    T.eq(Rules.Percent(1, 3), fmt.Percent(1, 3), "and on an uneven share too")
    T.eq(Rules.Percent(0, 100), 0, "a broken item is zero per cent")

    T.eq(Rules.Percent(10, 0), nil, "a zero maximum is not a zero but \"nothing\"")
    T.eq(Rules.Percent(nil, 100), nil, "rubbish out of the game gives no percentage")
    T.eq(Rules.Percent(10, nil), nil, "nor from the other side")

    restore()
end

do
    -- The core may be absent entirely: the module's file is read without it too.
    local saved = _G.Darken
    _G.Darken = {}
    T.eq(Rules.Percent(50, 100), nil, "with no door of the core's there is no percentage")
    _G.Darken = saved
end

--============================================================================
-- 2. The labels
--============================================================================

T.suite("the durability: the translations are complete")

local ru, uk = pure.Locales.ruRU, pure.Locales.ukUA
T.eq(type(ru), "table", "the Russian table is in place")
T.eq(type(uk), "table", "the Ukrainian table is in place")

--- The translation keys read out of the module's sources.
--
-- The list is asked of the files themselves rather than rewritten here: a
-- rewritten one would fall behind the module silently, and a new label would
-- reach the player untranslated. The concatenation of adjacent literals is
-- taken into account — long keys are wrapped by width and lie in the source as two pieces.
-- @param text string
-- @return table an array of keys
local function keysIn(text)
    local flat = text:gsub("%s+", " ")
    local out = {}

    --- Parse one site's concatenated literals.
    local function pieces(chunk)
        local parts = {}
        for piece in chunk:gmatch('"([^"]*)"') do parts[#parts + 1] = piece end
        return table.concat(parts)
    end

    for chunk in flat:gmatch('Localize%(%s*("[^)]-")%s*%)') do
        out[#out + 1] = pieces(chunk)
    end

    -- The schema's fields are the second place the keys live in, and it
    -- appeared with the window's move. The labels there are declared as
    -- English strings right in the page's description while the window
    -- translates them at the drawing: there is no Localize call beside them and
    -- must not be — the file is read before the core hands out the dictionary.
    for field in ("label hint title"):gmatch("%a+") do
        for chunk in flat:gmatch(field .. '%s*=%s*("[^,}]-")%s*[,}]') do
            local key = pieces(chunk)
            if key ~= "" then out[#out + 1] = key end
        end
    end

    return out
end

local wanted, seenKey = {}, {}
local function want(key)
    if not seenKey[key] then
        seenKey[key] = true
        wanted[#wanted + 1] = key
    end
end

for _, path in ipairs(helpers.moduleSources(FOLDER)) do
    for _, key in ipairs(keysIn(C.read(path))) do want(key) end
end

-- The slots' labels arrive in the translation as a table's field rather than
-- as a literal: they cannot be read out by the parse, and without this line a hole in them would slip past the check.
for i = 1, #Rules.SLOTS do want(Rules.SLOTS[i].label) end

T.ok(#wanted >= 15, "the keys were read out of the module: " .. #wanted)

for _, locale in ipairs({ "ruRU", "ukUA" }) do
    local table_ = pure.Locales[locale]
    local missing = {}
    for i = 1, #wanted do
        if type(table_[wanted[i]]) ~= "string" then
            missing[#missing + 1] = wanted[i]
        end
    end
    T.eq(#missing, 0, locale .. ": left untranslated: "
        .. table.concat(missing, " | "))

    local orphan = {}
    for key in pairs(table_) do
        if not seenKey[key] then orphan[#orphan + 1] = key end
    end
    T.eq(#orphan, 0, locale .. ": translations with no call site: "
        .. table.concat(orphan, " | "))
end

-- A key is obliged to be English: a non-English one breaks the fallback, and
-- an English client would see a foreign label.
do
    local nonAscii = {}
    for i = 1, #wanted do
        if wanted[i]:find("[\128-\255]") then
            nonAscii[#nonAscii + 1] = wanted[i]
        end
    end
    T.eq(#nonAscii, 0, "every key is English: "
        .. table.concat(nonAscii, " | "))
end

do
    local onlyRu, onlyUk, same = {}, {}, {}
    for key in pairs(ru) do
        if uk[key] == nil then onlyRu[#onlyRu + 1] = key end
    end
    for key in pairs(uk) do
        if ru[key] == nil then onlyUk[#onlyUk + 1] = key end
    end
    T.eq(#onlyRu, 0, "present in Russian only: " .. table.concat(onlyRu, " | "))
    T.eq(#onlyUk, 0, "present in Ukrainian only: "
        .. table.concat(onlyUk, " | "))

    -- Short labels may coincide legitimately; a long line that matched word for
    -- word is Russian text passed off as Ukrainian.
    for key, value in pairs(uk) do
        if #value > 40 and ru[key] == value then same[#same + 1] = key end
    end
    T.eq(#same, 0, "the Ukrainian repeats the Russian word for word: "
        .. table.concat(same, " | "))
end

-- The author's words: the Ukrainian table is written in his own vocabulary rather than copied.
T.eq(uk["Show the Durability Block"], "Показувати показник міцності",
    "the Ukrainian \"показник\" is in place")

--============================================================================
-- 3. The drawing
--============================================================================

T.suite("the durability: the block asks the scale and the palette")

--- A fake engine covering exactly what the block calls.
-- @return function CreateFrame
local function fakeEngine()
    local function fakeRegion()
        local region = {}
        function region:SetText(value) self.text = value end
        function region:GetText() return self.text end
        function region:SetPoint() end
        function region:SetJustifyH() end
        return region
    end

    local function fakeFrame(name)
        local frame = { name = name, shown = false }
        function frame:GetName() return self.name end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetFrameStrata() end
        function frame:SetPoint() end
        function frame:CreateFontString() return fakeRegion() end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:IsShown() return self.shown end
        return frame
    end

    return function(_, name) return fakeFrame(name) end
end

--- A styling that answers with a given scale and remembers what it was called with.
local function fakeSkin(metrics, log)
    return {
        Color = function() return 0, 0, 0, 1 end,
        Colors = function() return {} end,
        Metrics = function()
            local out = {}
            for key, value in pairs(metrics) do out[key] = value end
            return out
        end,
        Backdrop = function(_, back, border)
            log.backdrop = tostring(back) .. "/" .. tostring(border)
            return true
        end,
        Outline = function() return true end,
        Text = function(_, colour) log.tint = colour; return true end,
    }
end

do
    local core = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", core)

    -- The names the block paints with are obliged to exist in the core's real
    -- palette and in its real scale: a name that is not there reads as a colour
    -- while it turns out to be a nil — and the place silently slides onto a fallback number.
    for _, state in ipairs({ "broken", "warn", "fine" }) do
        T.ok(core.Skin.Palette[Rules.Tint(state)] ~= nil,
            "the state's colour exists in the core's palette: " .. state)
    end
    T.ok(core.Skin.Metrics.row ~= nil, "a row's height exists in the core's scale")

    local savedFrame, savedParent, savedCore =
        _G.CreateFrame, _G.UIParent, _G.Darken

    local log = {}
    local metrics = {}
    for key, value in pairs(core.Skin.Metrics) do metrics[key] = value end

    _G.CreateFrame = fakeEngine()
    _G.UIParent = {}
    _G.Darken = {
        GetSkin = function() return fakeSkin(metrics, log) end,
        GetMedia = function()
            return { ApplyFont = function(category)
                log.font = category
                return true
            end }
        end,
    }

    local drawn = helpers.loadModule(FOLDER, nil, { withRegistration = false })
    local Block = drawn.Block

    T.ok(Block.Build() ~= nil, "the block was built")
    T.eq(Block.Build(), Block.frame, "a second call returns the same frame")
    T.eq(Block.frame:IsShown(), false, "and before the player asks it is not shown")

    T.eq(Block.Paint("Durability 40%", "text"), true, "the block was painted")
    T.eq(Block.label:GetText(), "Durability 40%", "the label is in place")
    T.eq(log.backdrop, "panel/line", "the fill and the border come as the core's pair of names")
    T.eq(log.tint, "text", "the label's colour is the core's")
    T.eq(log.font, "windowtext", "the font was asked of the core for a window's text")

    -- This piece's main check: the block really did ask the scale rather than
    -- copying a number out of it. The difference is compared while the number itself is not named.
    local base = Block.frame.width
    metrics.row = metrics.row + 4
    Block.Paint("Durability 40%", "text")
    T.eq(Block.frame.width - base, 20, "the scale is edited and the block follows it")
    metrics.row = metrics.row - 4

    Block.SetShown(true)
    T.eq(Block.frame:IsShown(), true, "the block shows itself")
    Block.SetShown(false)
    T.eq(Block.frame:IsShown(), false, "and hides itself")

    _G.CreateFrame, _G.UIParent, _G.Darken =
        savedFrame, savedParent, savedCore
end

--============================================================================
-- 4. The joining with the core
--============================================================================

T.suite("the durability: the registration in the real core")

do
    -- The core is brought up by its real files in the order of its own TOC: a
    -- fake beside it would check the fake rather than the door the module goes through.
    local CORE_FILES = {
        "Core/Compat.lua", "Core/Casefold.lua", "Core/Format.lua",
        "Core/Skin.lua", "Skin/Draw.lua", "Core/Registry.lua",
        "Core/Defaults.lua", "Core/Command.lua", "Core/Locale.lua",
        "Core/Frames.lua", "Core/Events.lua", "Core/Combat.lua",
        "Core/Api.lua", "Core/Media.lua", "Core/AuraFilter.lua",
    }

    local saved = {
        Darken = _G.Darken,
        SlashCmdList = _G.SlashCmdList,
        CreateFrame = _G.CreateFrame,
        UIParent = _G.UIParent,
        durability = _G.GetInventoryItemDurability,
    }

    helpers.installValidator()
    _G.SlashCmdList = {}
    _G.CreateFrame = fakeEngine()
    _G.UIParent = {}

    local core = helpers.newNamespace()
    for i = 1, #CORE_FILES do helpers.loadAddonFile(CORE_FILES[i], core) end

    core.Registry.report = function() end
    core.Addon = {
        db = { profile = {}, global = {}, char = {} },
        Print = function() end,
    }
    core.flavor = "vanilla"

    local ns = helpers.loadModule(FOLDER, nil, {})
    local module = core.Registry.modules.umbradurability

    T.ok(module ~= nil, "the module was registered under its own name")
    T.eq(module and module.api, 16, "the contract version is declared")
    T.eq(module and module.defaults.enabled, false,
        "a fresh install changes nothing: the indicator is off")

    if module then
        -- In the game AceDB lays the default values out, while here the
        -- database is an ordinary table and the profile is empty. We lay them
        -- out ourselves: otherwise what would be checked is not the module but the stand's incompleteness.
        for key, value in pairs(module.defaults) do
            core.Addon.db.profile.umbradurability =
                core.Addon.db.profile.umbradurability or {}
            core.Addon.db.profile.umbradurability[key] = value
        end

        -- The game answers with durability: one item is more worn than the rest.
        _G.GetInventoryItemDurability = function(slot)
            if slot == 1 then return 20, 100 end
            if slot == 5 then return 90, 100 end
            return nil
        end

        module:OnEnable()

        local settings = module:GetSettings()
        T.eq(type(settings), "table", "the module's settings lie in the core's database")
        T.eq(settings.enabled, false, "and are off by default")
        T.eq(settings.warnBelow, 35, "the alarm threshold is in place")

        -- A switched-off module builds nothing.
        module:Apply()
        T.eq(ns.Block.frame, nil, "a switched-off indicator creates no frame")

        settings.enabled = true
        module:Apply()
        T.ok(ns.Block.frame ~= nil, "a switched-on indicator built the block")
        T.eq(ns.Block.frame:IsShown(), true,
            "a worn item makes the indicator show itself")
        T.ok(tostring(ns.Block.label:GetText()):find("20"),
            "the worst item's percentage is written in the block: "
            .. tostring(ns.Block.label:GetText()))

        -- Intact equipment hides the indicator: the block speaks when there is
        -- something to speak of rather than standing on the screen always.
        _G.GetInventoryItemDurability = function(slot)
            if slot == 1 then return 100, 100 end
            return nil
        end
        module:Apply()
        T.eq(ns.Block.frame:IsShown(), false, "intact equipment stays silent")

        settings.alwaysShow = true
        module:Apply()
        T.eq(ns.Block.frame:IsShown(), true,
            "but at the player's request the indicator stays")

        -- A client with no durability at all: there is no error while the block
        -- stays — it was asked to be shown always, and it says in words that
        -- there are no readings. An empty screen in the place of a switched-on
        -- setting cannot be explained with anything.
        _G.GetInventoryItemDurability = nil
        module:Apply()
        T.eq(ns.Block.frame:IsShown(), true,
            "with no durability in the client the block stays and explains itself")

        settings.alwaysShow = false
        module:Apply()
        T.eq(ns.Block.frame:IsShown(), false,
            "while with no request it hides")

        module:OnDisable("test")
        T.eq(ns.Block.frame:IsShown(), false,
            "a switched-off module takes its own off the screen")
    end

    helpers.removeValidator()
    _G.Darken = saved.Darken
    _G.SlashCmdList = saved.SlashCmdList
    _G.CreateFrame = saved.CreateFrame
    _G.UIParent = saved.UIParent
    _G.GetInventoryItemDurability = saved.durability
end
