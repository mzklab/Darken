local helpers = require("helpers")
local localekeys = require("localekeys")

helpers.installValidator()

-- The item level from a separate folder (Features/ItemLevel).
--
-- What is checked falls into four parts: the pure display rules (which
-- number, in what colour, in which corner, and whether the level means
-- anything on this client), the tally of deferred redraws, the display on a
-- foreign button, and the registration in the core together with the full path "the data arrived later -- the number appeared anyway".
--
-- The last is the main thing checked here. The game does not hand out data
-- about an unknown item at once, and without the tally of deferred redraws
-- some numbers do not appear at all -- and precisely the part that depends on
-- what the player opened earlier. From the outside that looks random and
-- cannot be found from a bug report -- so the path is checked in full, by the
-- same code the game will run it with.

local MODULE = "Features/ItemLevel"
local PATH = MODULE .. "/"

--- Load the module files into a fresh namespace.
-- The file list and the order are taken from the module TOC rather than copied here.
-- @param withRegistration boolean whether to load ItemLevel.lua (it registers itself)
-- @return table
local function moduleNamespace(withRegistration)
    local ns = helpers.newNamespace()
    return helpers.loadModule(MODULE, ns, { withRegistration = withRegistration })
end

local ns = moduleNamespace(false)

T.suite("item level: the meaning is decided by the client, not by the version")

do
    local Level = ns.Level

    -- One rule for the whole module: the existence of a game object is asked
    -- about. The build number does not enter here in any form -- it changes
    -- within one client and matches across different lines.
    T.eq(Level.Meaningful({ GetDetailedItemLevelInfo = function() end }), true,
        "the detailed item level is a sign of a client where it means something")
    T.eq(Level.Meaningful({ GetAverageItemLevel = function() end }), true,
        "the average equipment level is the same kind of sign")
    T.eq(Level.Meaningful({ C_PaperDollInfo = {} }), true,
        "and so is the character window data table")

    -- The vanilla and TBC clients: an item has a level, but it decides
    -- nothing, and none of the signs exists in the client.
    T.eq(Level.Meaningful({ GetItemInfo = function() end }), false,
        "general item data alone is not enough")
    T.eq(Level.Meaningful({}), false, "an empty client hides the section")
    T.eq(Level.Meaningful(nil), false, "nobody to ask -- the section is hidden")

    -- The name exists but there is no object behind it: anything can be found
    -- in SavedVariables and in foreign addons, and a string under a function
    -- name does not make the client something it is not.
    T.eq(Level.Meaningful({ GetAverageItemLevel = "yes" }), false,
        "neither a function nor a table is a sign")
end

T.suite("item level: which number to show")

do
    local Level = ns.Level

    T.eq(Level.Choose(226, 200), 226, "the detailed level outranks the plain one")
    T.eq(Level.Choose(nil, 200), 200, "with no detailed one the plain one is used")
    T.eq(Level.Choose(0, 200), 200, "a detailed zero is not a level")

    -- A zero from the game means "I do not know yet": it arrives both for an
    -- item whose data is not loaded and for an item with no level at all.
    T.eq(Level.Choose(0, 0), nil, "zero on both means there is no number")
    T.eq(Level.Choose(nil, nil), nil, "no data means no number")
    T.eq(Level.Choose("garbage", nil), nil, "a non-number means no number")
    T.eq(Level.Choose(0 / 0, nil), nil, "NaN means no number")
    T.eq(Level.Choose(-5, nil), nil, "a negative level means no number")
    T.eq(Level.Choose(226.7, nil), 226, "a fractional level is rounded down")

    T.eq(Level.Format(226), "226", "the number as a string")
    T.eq(Level.Format(nil), "", "no number gives an empty string rather than nil")
    T.eq(Level.Format(0), "", "zero is not shown")

    T.eq(Level.ItemID("|cff9d9d9d|Hitem:7073:0:0:0|h[Broken Fang]|h|r"), 7073,
        "the item id is read out of the link")
    T.eq(Level.ItemID("item:19019"), 19019, "a short link is read too")
    T.eq(Level.ItemID("not a link"), nil, "not a link means no id")
    T.eq(Level.ItemID(nil), nil, "nil means no id")
end

T.suite("item level: the decision for one slot")

do
    local Level = ns.Level
    local LINK = "|Hitem:12345:0|h[Item]|h"

    local verdict, value = Level.Decide(LINK, 226, 200)
    T.eq(verdict, "show", "the level is known -- we show it")
    T.eq(value, 226, "and specifically the detailed one")

    -- The very case the whole tally was written for: there is a link but no
    -- level. That is not "empty", that is "wait for data about this very item".
    verdict, value = Level.Decide(LINK, nil, nil)
    T.eq(verdict, "wait", "there is a link and no level -- we wait")
    T.eq(value, 12345, "and we wait by the item id from the link")

    verdict = Level.Decide(nil, nil, nil)
    T.eq(verdict, "clear", "an empty slot means erase")

    -- A link with no item id: there is nothing to wait by, and waiting
    -- forever would be worse than an erased slot.
    verdict = Level.Decide("|Hspell:133|h[Fireball]|h", nil, nil)
    T.eq(verdict, "clear", "a link that is not to an item means erase rather than wait")
end

T.suite("item level: colour, corner and size")

do
    local Level = ns.Level

    local COLORS = {
        [4] = { r = 0.64, g = 0.21, b = 0.93 },
        [3] = { 0, 0.44, 0.87 },
    }
    local FALLBACK = { r = 0.9, g = 0.9, b = 0.9 }

    local r, g, b = Level.Color({ byQuality = true, quality = 4,
        colors = COLORS, fallback = FALLBACK })
    T.eq(r, 0.64, "colouring by quality takes the quality colour")

    r, g, b = Level.Color({ byQuality = true, quality = 3,
        colors = COLORS, fallback = FALLBACK })
    T.eq(g, 0.44, "an array of three numbers also reads as a colour")

    r, g, b = Level.Color({ byQuality = false, quality = 4,
        colors = COLORS, fallback = FALLBACK })
    T.eq(r, 0.9, "colouring off gives the addon text colour")

    -- The quality comes from the game and is sometimes unknown: a hole in the
    -- client table must not leave the colour of the previous item on the string.
    r, g, b = Level.Color({ byQuality = true, quality = 9,
        colors = COLORS, fallback = FALLBACK })
    T.eq(b, 0.9, "an unknown quality falls back to the text colour")

    r, g, b = Level.Color(nil)
    T.eq(r, 1, "with no data, white")
    T.eq(b, 1, "in all three channels")

    local point, x, y = Level.Anchor("bottomright", 2)
    T.eq(point, "BOTTOMRIGHT", "the corner from the setting")
    T.eq(x, -2, "the sign of the inset belongs to the corner")
    T.eq(y, 2, "on both axes")

    point = Level.Anchor("garbage", 2)
    T.eq(point, "TOPLEFT", "an unknown value gives the default")
    T.eq(Level.DEFAULT_POSITION, "topleft", "the default is declared in one place")

    -- The fallback answer to "there is no scale at all" is the same as for the
    -- neighbours (Icon.Edge, Plate.Edge, Window.edgeOf in the bags): a two
    -- standing in for a missing answer rather than a second record of the
    -- magnitude. Formerly there was a one here -- exactly the number hair
    -- returned -- and that coincidence was accidental.
    point, x, y = Level.Anchor("topleft", nil)
    T.eq(x, 2, "with no spacing scale the fallback answer is used")

    local B = Level.BOUNDS.size
    T.eq(Level.ClampSize(14), 14, "a given size passes")
    T.eq(Level.ClampSize(2), B.min, "too small is clamped")
    T.eq(Level.ClampSize(900), B.max, "and so is too large")
    T.eq(Level.ClampSize("garbage"), B.default, "a non-number gives the default")
    T.eq(Level.ClampSize(nil), B.default, "and so does a missing value")
    T.eq(Level.ClampSize(0 / 0), B.default, "NaN gives the default")

    -- Parsing the item slot on a foreign button of the UmbraUI_Bags bag window.
    local container, slot = Level.ParseItemAttribute("0 12")
    T.eq(container, 0, "the bag was read out of the attribute")
    T.eq(slot, 12, "and the slot")
    T.eq(Level.ParseItemAttribute("item 0 12"), nil,
        "a foreign attribute shape is not parsed")
    T.eq(Level.ParseItemAttribute(nil), nil, "no attribute means no slot")
end

T.suite("item level: the tally of deferred redraws")

do
    local Pending = ns.Pending
    local state = Pending.New()

    T.eq(Pending.Count(state), 0, "a fresh tally is empty")

    T.eq(Pending.Remember(state, 111, "bag:0:1", { id = "a" }), true,
        "the slot was deferred")
    T.eq(Pending.Count(state), 1, "and is recorded in the tally")
    T.eq(Pending.Held(state, "bag:0:1").id, "a", "and is found by key")

    -- The key is a place on screen rather than an item: the item in one slot
    -- changes, and a second record about the same slot would draw it as something that is not there.
    Pending.Remember(state, 222, "bag:0:1", { id = "b" })
    T.eq(Pending.Count(state), 1, "a repeat for the same slot does not breed records")
    T.eq(#Pending.Take(state, 111), 0, "and under the former id there is no slot any more")
    T.eq(Pending.Held(state, "bag:0:1").id, "b", "while under the new one there is a new target")

    -- Several slots wait for one item at once: two identical items in a bag.
    Pending.Remember(state, 222, "bag:0:2", { id = "c" })
    local taken = Pending.Take(state, 222)
    T.eq(#taken, 2, "every slot that waited for this item is taken")
    T.eq(Pending.Count(state), 0, "and the tally is empty afterwards")

    -- Take rather than read: otherwise an item that never arrived would wait
    -- forever, and one that arrived would be redrawn on every following event.
    T.eq(#Pending.Take(state, 222), 0, "a repeated handout is empty")

    Pending.Remember(state, 333, "bag:0:3", { id = "d" })
    T.eq(Pending.Forget(state, "bag:0:3"), true, "the slot was taken off the waiting list")
    T.eq(Pending.Forget(state, "bag:0:3"), false, "and taken off exactly once")
    T.eq(Pending.Count(state), 0, "the tally is empty")

    T.eq(Pending.Remember(state, "garbage", "k", {}), false,
        "with no item id there is nothing to wait for")
    T.eq(Pending.Remember(state, 1, nil, {}), false, "nor with no slot key")
    T.eq(Pending.Remember(state, 1, "k", nil), false, "nor with no target")

    -- The limit. The bank and a foreign character's equipment give hundreds
    -- of unknown items in a row, and the readiness event for some of them may never arrive.
    local full = Pending.New()
    for i = 1, Pending.LIMIT do
        Pending.Remember(full, i, "k" .. i, { i = i })
    end
    T.eq(Pending.Count(full), Pending.LIMIT, "the tally filled up to the limit")
    T.eq(Pending.Remember(full, 9001, "more", {}), false,
        "beyond the limit a new record is refused")
    T.eq(Pending.Remember(full, 1, "k1", { i = "new" }), true,
        "while replacing an already recorded slot goes through even at the limit")

    T.eq(Pending.Wipe(full), Pending.LIMIT, "the tally was cleared entirely")
    T.eq(Pending.Count(full), 0, "and is empty after the clearing")
end

T.suite("item level: the display on a foreign button")

do
    local Display = ns.Display

    --- A fake font string: as many methods as the display calls.
    local function fontString()
        local fs = { shown = false, text = "", r = 0, g = 0, b = 0,
            font = { "Path", 12, "" }, points = 0 }
        function fs:SetText(value) self.text = value end
        function fs:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end
        function fs:Show() self.shown = true end
        function fs:Hide() self.shown = false end
        function fs:ClearAllPoints() self.points = 0 end
        function fs:SetPoint() self.points = self.points + 1 end
        function fs:GetFont() return self.font[1], self.font[2], self.font[3] end
        function fs:SetFont(path, size, flags) self.font = { path, size, flags } end
        return fs
    end

    local function button()
        local b = {}
        function b:CreateFontString() return fontString() end
        return b
    end

    local registry = Display.NewRegistry()
    local slot = button()

    T.eq(Display.Show(registry, slot, { text = "226", r = 1, g = 0, b = 0,
        point = "TOPLEFT", x = 1, y = -1, size = 14 }), true, "the number was drawn")

    local text = Display.FIELD[slot]
    T.eq(text.text, "226", "the string shows the number")
    T.eq(text.shown, true, "and is visible")
    T.eq(text.font[2], 14, "the size is our setting")
    T.eq(text.font[1], "Path", "while the typeface stays the one the core assigned")

    -- A second call on the same button does not create a second string:
    -- otherwise strings would pile up on the slot, each with its own setting.
    Display.Show(registry, slot, { text = "200", size = 10 })
    T.eq(Display.FIELD[slot], text, "there is one string on the button")
    T.eq(text.text, "200", "and it is the one that gets updated")
    T.eq(registry.count, 1, "the button is recorded once in the registry")

    -- Switching the module off must remove the numbers entirely, and walking
    -- the whole screen for that is not allowed -- that is what the registry is kept for.
    T.eq(Display.HideAll(registry), 1, "every number is hidden")
    T.eq(text.shown, false, "the string is not visible")
    T.eq(text.text, "", "and does not hold the former number")

    -- A button on which we created nothing does not get a string just so it
    -- can be hidden.
    local untouched = button()
    T.eq(Display.Clear(untouched), false, "nothing to hide -- we do nothing")
    T.eq(Display.FIELD[untouched], nil, "and no string is created")

    -- Outside the game there is no CreateFontString, and that is not a
    -- breakage: the display simply does not happen while every rule stays checkable.
    T.eq(Display.Show(registry, {}, { text = "226" }), false,
        "with no engine the number is not drawn")
end

-- The file list of a part and its place in the addon TOC are checked by one
-- suite for every part -- tests/test_moduletoc.lua. Formerly that check stood
-- here: the part had a TOC of its own and answered for it itself.

T.suite("item level: the translations")

do
    -- The module sources are taken from its TOC rather than listed here.
    local SOURCES = helpers.moduleSources(MODULE)

    local seen, wanted = {}, {}
    for i = 1, #SOURCES do
        local keys = localekeys.literal(localekeys.read(SOURCES[i]))
        for j = 1, #keys do
            if not seen[keys[j]] then
                seen[keys[j]] = true
                wanted[#wanted + 1] = keys[j]
            end
        end
    end

    -- The icon corner labels come from a table rather than from a literal at
    -- the call site, and they cannot be found by reading out ns.Localize
    -- calls. So they are added to the list from here -- from the same place the module takes them.
    for i = 1, #ns.Level.POSITIONS do
        local label = ns.Level.POSITIONS[i].label
        if not seen[label] then
            seen[label] = true
            wanted[#wanted + 1] = label
        end
    end

    T.ok(#wanted >= 12, "the keys were read out of the module sources: " .. #wanted)

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

T.suite("item level: registering in the core and late data")

do
    -- The core is assembled for real and exposed as a global -- exactly as a
    -- separate addon sees it in the game.
    local saved = {
        Darken = _G.Darken,
        SlashCmdList = _G.SlashCmdList,
        GetDetailedItemLevelInfo = _G.GetDetailedItemLevelInfo,
        GetItemInfo = _G.GetItemInfo,
        GetContainerItemLink = _G.GetContainerItemLink,
        hooksecurefunc = _G.hooksecurefunc,
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
    helpers.loadAddonFile("Core/Media.lua", core)

    -- The client is determined: without that the core door to the game
    -- functions (Darken:GetGameFunction, contract 19) answers with nothing,
    -- and the number over an item in a bag would not appear at all. In the game the flavour is set by
    -- Core/Init.lua.
    core.flavor = "mists"

    local said = {}
    core.Registry.report = function(text) said[#said + 1] = text end
    core.Addon = {
        db = { profile = {}, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }

    _G.SlashCmdList = {}

    -- A client on which the item level means something. A fake of exactly the
    -- object the module decides that by.
    _G.GetDetailedItemLevelInfo = function() return nil end

    -- The data about items the client "already knows". The table is empty:
    -- that is the whole point of the check -- the first walk finds the item unknown.
    local known = {}
    _G.GetItemInfo = function(link)
        local entry = known[link]
        if not entry then return nil end
        return "Item", link, entry.quality, entry.level
    end

    -- What lies in the bag.
    local contents = { [1] = { [1] = "|Hitem:777:0|h[Late item]|h" } }
    _G.GetContainerItemLink = function(bag, slot)
        local inBag = contents[bag]
        return inBag and inBag[slot] or nil
    end

    local hooked = {}
    _G.hooksecurefunc = function(name, fn) hooked[name] = fn end

    -- A fake bag window with one slot: as many methods as the walk calls. The
    -- module asks the core for the frame names, and the core answers with what
    -- was substituted into it below.
    local function fontString()
        local fs = { shown = false, text = "", font = { "Path", 12, "" } }
        function fs:SetText(value) self.text = value end
        function fs:SetTextColor() end
        function fs:Show() self.shown = true end
        function fs:Hide() self.shown = false end
        function fs:ClearAllPoints() end
        function fs:SetPoint() end
        function fs:GetFont() return self.font[1], self.font[2], self.font[3] end
        function fs:SetFont(path, size, flags) self.font = { path, size, flags } end
        return fs
    end

    local slotButton = { icon = true }
    function slotButton:GetID() return 1 end
    function slotButton:GetName() return "FakeBagFrameItem1" end
    function slotButton:CreateFontString() return fontString() end

    local bagFrame = {}
    function bagFrame:GetID() return 1 end
    function bagFrame:IsShown() return true end
    function bagFrame:GetChildren() return slotButton end

    _G.FakeBagFrame = bagFrame

    local module = moduleNamespace(true)

    -- The frame names are substituted over the public layer: outside the game
    -- the core does not know which client this is and honestly returns empty lists.
    -- Two answers, as from the real door (contract 18): the names and the
    -- objects themselves. A fake returning only names would be checking a
    -- different module from the one that runs for the player.
    _G.Darken.GetFrameNames = function(_, group)
        if group == "bag-window" then
            return { "FakeBagFrame" }, { _G.FakeBagFrame }
        end
        return {}, {}
    end

    local handle = core.Registry:Get("umbrailevel")
    T.ok(handle ~= nil, "the module is registered: " .. table.concat(said, " | "))

    if handle then
        local settings = handle:GetSettings()
        T.eq(type(settings), "table", "the module settings live in the core profile")
        T.eq(handle.defaults.enabled, false,
            "a fresh install changes nothing on screen")
        T.eq(handle.defaults.quality, true,
            "and every default stays selectable")

        core.Registry:EnableAll()
        T.eq(core.Registry:IsEnabled(handle), true, "the module works")

        -- The settings section: the level lives in arg.level and only there.
        local args = handle.options.args

        -- The section is visible: the faked client understands the item level.
        T.eq(handle.options.hidden(), false,
            "on such a client the settings section is visible")

        -- Switched off, there is not a single number, and the subscription is
        -- still alive: the display can be enabled mid-session.
        T.eq(module.Display.NewRegistry().count, 0, "the button registry is fresh")

        -- We enable the display by the same path the player enables it.
        args.enabled.set(nil, true)
        T.eq(handle:GetSettings().enabled, true, "the value went into the profile")
        T.eq(core.Registry:IsEnabled(handle), true,
            "and applying the settings ran without error")

        -- === The main place of the check ===
        --
        -- The walk went through, the slot exists, the item in it exists, and
        -- the client has not received its data yet. There is no number -- and
        -- it is not lost: the slot is recorded against the item id.
        T.eq(module.Display.FIELD[slotButton], nil,
            "there is no number yet: the item data is still on its way")

        -- The data arrives. That event is exactly what turns a deferred redraw
        -- into a number on the icon.
        known["|Hitem:777:0|h[Late item]|h"] = { level = 226, quality = 4 }
        T.eq(core.Events.Dispatch("GET_ITEM_INFO_RECEIVED", 777, true), 1,
            "the data readiness event reached the module")

        local text = module.Display.FIELD[slotButton]
        T.ok(text ~= nil, "the string on the slot appeared only now")
        T.eq(text and text.text, "226",
            "an item whose data arrived later got its number")
        T.eq(text and text.shown, true, "and the number is visible")

        -- An event about a foreign item touches nothing.
        core.Events.Dispatch("GET_ITEM_INFO_RECEIVED", 42, true)
        T.eq(text.text, "226", "a foreign event does not erase the number")

        -- The same event arriving a second time has nothing to do: the slot
        -- was taken out of the tally rather than left waiting forever.
        text.text = ""
        core.Events.Dispatch("GET_ITEM_INFO_RECEIVED", 777, true)
        T.eq(text.text, "", "the slot was taken off the waiting list after the first draw")

        -- The bags change, the walk runs again, and the number takes its place.
        T.eq(core.Events.Dispatch("BAG_UPDATE_DELAYED"), 1,
            "the bag change reached the module")
        T.eq(text.text, "226", "and the number came back onto the slot")

        -- Switching off removes the numbers entirely and with no interface reload.
        args.enabled.set(nil, false)
        T.eq(text.text, "", "switching off erased the number")
        T.eq(text.shown, false, "and hid the string")

        -- A disabled module stops listening: the core removes the subscriptions.
        core.Registry:Disable("umbrailevel", "a disable check")
        T.eq(core.Events.Count("GET_ITEM_INFO_RECEIVED"), 0,
            "the disabled module stopped listening")
    end

    _G.FakeBagFrame = nil
    _G.Darken = saved.Darken
    _G.SlashCmdList = saved.SlashCmdList
    _G.GetDetailedItemLevelInfo = saved.GetDetailedItemLevelInfo
    _G.GetItemInfo = saved.GetItemInfo
    _G.GetContainerItemLink = saved.GetContainerItemLink
    _G.hooksecurefunc = saved.hooksecurefunc
end

T.suite("item level: a client with no item level")

do
    -- The same module on a client where the item level means nothing: the
    -- settings section is hidden, there are no subscriptions. The decision is
    -- made by the presence of a game object, and here there simply is none.
    local saved = { Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        GetDetailedItemLevelInfo = _G.GetDetailedItemLevelInfo }

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
    helpers.loadAddonFile("Core/Media.lua", core)

    -- The client is determined: without that the core door to the game
    -- functions (Darken:GetGameFunction, contract 19) answers with nothing,
    -- and the number over an item in a bag would not appear at all. In the game the flavour is set by
    -- Core/Init.lua.
    core.flavor = "mists"

    core.Registry.report = function() end
    core.Addon = { db = { profile = {}, global = {} },
        Print = function() end }

    _G.SlashCmdList = {}
    _G.GetDetailedItemLevelInfo = nil

    moduleNamespace(true)

    local handle = core.Registry:Get("umbrailevel")
    T.ok(handle ~= nil, "the module registers on such a client too")

    if handle then
        core.Registry:EnableAll()
        T.eq(core.Registry:IsEnabled(handle), true,
            "and does not fail: it simply does nothing")
        T.eq(handle.options.hidden(), true,
            "the settings section is hidden: the item level means nothing here")
        T.eq(core.Events.Count("GET_ITEM_INFO_RECEIVED"), 0,
            "and the module is subscribed to no event")
    end

    _G.Darken = saved.Darken
    _G.SlashCmdList = saved.SlashCmdList
    _G.GetDetailedItemLevelInfo = saved.GetDetailedItemLevelInfo
end

T.suite("item level: the slots of a foreign bag window arrive as a showcase")

do
    -- What is checked here is what the module no longer has: searching for a
    -- foreign window by global name and reading the item slot from a protected
    -- attribute. The neighbour (UmbraUI_Bags) puts the list of its slots onto
    -- the core showcase, and the showcase also serves as the witness of the
    -- redraw: we are called after it has finished rather than racing it on a shared event.
    --
    -- At the same time this is a check of the second promise: a client with
    -- not a single game frame from our groups does not break the module -- it
    -- simply draws nothing on them.
    local saved = {
        Darken = _G.Darken,
        SlashCmdList = _G.SlashCmdList,
        GetDetailedItemLevelInfo = _G.GetDetailedItemLevelInfo,
        GetItemInfo = _G.GetItemInfo,
        GetContainerItemLink = _G.GetContainerItemLink,
        hooksecurefunc = _G.hooksecurefunc,
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
    helpers.loadAddonFile("Core/Media.lua", core)

    -- The client is determined: without that the core door to the game
    -- functions (Darken:GetGameFunction, contract 19) answers with nothing,
    -- and the number over an item in a bag would not appear at all. In the game the flavour is set by
    -- Core/Init.lua.
    core.flavor = "mists"

    core.Registry.report = function() end
    core.Addon = {
        db = { profile = {}, global = {} },
        Print = function() end,
    }

    _G.SlashCmdList = {}
    _G.GetDetailedItemLevelInfo = function() return nil end
    _G.hooksecurefunc = function() end

    local known = {
        ["|Hitem:301:0|h[Cloak]|h"] = { level = 226, quality = 4 },
        ["|Hitem:302:0|h[Belt]|h"] = { level = 187, quality = 3 },
    }
    _G.GetItemInfo = function(link)
        local entry = known[link]
        if not entry then return nil end
        return "Item", link, entry.quality, entry.level
    end

    local contents = {
        [1] = { [5] = "|Hitem:301:0|h[Cloak]|h" },
        [2] = { [7] = "|Hitem:302:0|h[Belt]|h" },
    }
    _G.GetContainerItemLink = function(bag, slot)
        local inBag = contents[bag]
        return inBag and inBag[slot] or nil
    end

    local function fontString()
        local fs = { shown = false, text = "", font = { "Path", 12, "" } }
        function fs:SetText(value) self.text = value end
        function fs:SetTextColor() end
        function fs:Show() self.shown = true end
        function fs:Hide() self.shown = false end
        function fs:ClearAllPoints() end
        function fs:SetPoint() end
        function fs:GetFont() return self.font[1], self.font[2], self.font[3] end
        function fs:SetFont(path, size, flags) self.font = { path, size, flags } end
        return fs
    end

    local function slotButton(attribute)
        local button = { attribute = attribute }
        function button:CreateFontString() return fontString() end
        function button:GetAttribute(name)
            if name == "item" then return self.attribute end
            return nil
        end
        return button
    end

    local module = moduleNamespace(true)

    -- A client with not a single known frame: no game bag windows, no
    -- equipment slots, no inspect window. That is exactly what a group absent
    -- from this build looks like -- and the module must survive it.
    _G.Darken.GetFrameNames = function() return {}, {} end

    local handle = core.Registry:Get("umbrailevel")
    T.ok(handle ~= nil, "the module is registered")

    if handle then
        core.Registry:EnableAll()
        handle.options.args.enabled.set(nil, true)
        T.eq(core.Registry:IsEnabled(handle), true,
            "a client without these frames does not break the module")

        local first  = slotButton("1 5")
        local second = slotButton(nil)

        -- The neighbour redrew its window and put out the list. The numbers
        -- appear from that notification rather than from the bag change event:
        -- the order of two handlers of one event is not defined, and our number would lag behind.
        core.Frames.Repaint("umbrabags.slots", {
            { button = first,  shown = true, container = 1, slot = 5 },
            { button = second, shown = true, container = 2, slot = 7 },
        })

        local firstText  = module.Display.FIELD[first]
        local secondText = module.Display.FIELD[second]
        T.eq(firstText and firstText.text, "226",
            "the number took its place on the neighbour's slot on the showcase notification")
        T.eq(secondText and secondText.text, "187",
            "and on the one whose attribute the neighbour had no time to set in combat")

        -- The item slot is taken from the list rather than from the attribute:
        -- the second button has no attribute at all, yet it carries a number.
        T.eq(second.attribute, nil, "the attribute of the second slot was never assigned")

        -- Backwards compatibility of the list: a record with no item slot is
        -- not a lost slot yet, the slot is asked of the button itself.
        firstText.text = ""
        core.Frames.Repaint("umbrabags.slots", {
            { button = first, shown = true },
        })
        T.eq(firstText.text, "226", "the slot was asked of the button by attribute")

        -- A slot marked as hidden carries no number.
        core.Frames.Repaint("umbrabags.slots", {
            { button = first, shown = false },
        })
        T.eq(firstText.text, "", "the hidden slot was erased")
        T.eq(firstText.shown, false, "and the string is hidden")

        -- Garbage in a foreign list does not break the walk: a record with no
        -- button, and one that is not a table at all.
        core.Frames.Repaint("umbrabags.slots", { {}, "garbage", 7 })
        T.eq(core.Registry:IsEnabled(handle), true,
            "a foreign list of the wrong shape does not disable the module")
    end

    _G.Darken = saved.Darken
    _G.SlashCmdList = saved.SlashCmdList
    _G.GetDetailedItemLevelInfo = saved.GetDetailedItemLevelInfo
    _G.GetItemInfo = saved.GetItemInfo
    _G.GetContainerItemLink = saved.GetContainerItemLink
    _G.hooksecurefunc = saved.hooksecurefunc
end

helpers.removeValidator()
