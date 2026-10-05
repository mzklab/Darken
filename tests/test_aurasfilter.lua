local helpers = require("helpers")

-- The aura filter in the compact auras (Features/Auras/Filter.lua) and what it
-- does to the grid.
--
-- What is checked falls into four parts, each answering its own question.
--
-- 1. The decision for one aura, in every combination of the axes. There are
--    three axes: what the list does (nothing, hide the named, show only the
--    named), whether the aura is named in the list, and whether the player
--    cast it; plus the kind of the aura, because "only mine" concerns buffs
--    and not debuffs. There are few combinations precisely because there are
--    few axes, and that is checked by enumeration rather than by examples.
--
-- 2. Parsing the list: an id and a name in one field, repeats, garbage, a
--    list typed as a column, and an entry matching nothing.
--
-- 3. The cost. The filter is called for every aura of every update, and in
--    combat the updates never stop. The claim "a list of a thousand costs the
--    same as a list of one" must be a number rather than a promise.
--
-- 4. The grid after the filter: an empty block, a block shorter than a row,
--    and the return of the icons to the pool. A fake client stands here, and
--    the real hot path of the module is run through it -- otherwise "the
--    filter removed an icon" would be checked on the absence of icons.

local MODULE = "Features/Auras"

helpers.installValidator()

--- The pure parts of the module in a fresh namespace.
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

T.suite("aura filter: parsing the list")

do
    local Filter = pure.Filter
    local shared = pure.coreFilter

    -- The list parsing, the name key and the mode words moved into the core:
    -- this module and the nameplate engine matched word for word. No copy is
    -- left here, and that is checked directly -- by identity rather than by words in a header.
    T.ok(type(shared) == "table", "the core filter is available to the module")
    T.eq(Filter.Split, shared.Split, "the module list parsing is the core one")
    T.eq(Filter.Key, shared.Key, "and so is the name key")
    T.eq(Filter.NeedsKey, shared.NeedsKey, "and so is the question about the key")
    T.eq(Filter.DEFAULT_MODE, shared.DEFAULT_MODE, "and the mode default")

    -- A comma and a newline are the same thing: the player is free to type the
    -- list as a column.
    local ids, names, count = Filter.Split("Rend, Sunder Armor\nHamstring")
    T.eq(count, 3, "three entries were parsed")
    T.eq(names["rend"], true, "the name was reduced to a key")
    T.eq(names["sunder armor"], true, "a two-word name was not torn apart")
    T.eq(names["hamstring"], true, "a newline is a separator too")
    T.eq(next(ids), nil, "there are no ids among the names")

    -- An id and a name differ by the shape of the entry rather than by a separate setting.
    ids, names, count = Filter.Split("12345, Кровопускание")
    T.eq(count, 2, "an id and a name in one field")
    T.eq(ids[12345], true, "the id went into the id dictionary")
    -- Cyrillic folds to lower case just like Latin: that is the core folding
    -- (Darken:GetCasefold, Core/Casefold.lua). Formerly the opposite was
    -- written here -- string.lower in Lua 5.1 knew one byte, and a
    -- capitalised "Кровопускание" stayed capitalised in the dictionary -- and
    -- it was written honestly; now the truth is different, and the check says it.
    T.eq(names["кровопускание"], true, "while the name went into the name dictionary")
    T.eq(names["Кровопускание"], nil,
        "the key in the dictionary is the folded one, not the typed one")
    T.eq(names["12345"], nil, "an id does not count as a name")

    -- Repeats are not doubled: a list naming one thing three times means the
    -- same as a list naming it once.
    local dupIds, dupNames, dupCount, numbered =
        Filter.Split("Rend,,rend,  ,REND, 77 , 77,\n77")
    T.eq(dupCount, 2, "repeats are not counted twice")
    T.eq(numbered, 1, "and there is one id among them")
    T.eq(dupNames["rend"], true, "one name remained")
    T.eq(dupIds[77], true, "and one id remained")

    -- Garbage creates no entries and does not break the parsing.
    local _, _, junk = Filter.Split("   ,,, \n\n  ")
    T.eq(junk, 0, "empty fragments yield no entries")
    local _, _, none = Filter.Split(nil)
    T.eq(none, 0, "and neither does a missing string")

    -- A fraction and a zero are never spell ids: such an entry goes into the
    -- names, where it simply finds nothing, instead of silently becoming
    -- someone else's spell.
    local badIds, badNames = Filter.Split("3.5, 0, -7")
    T.eq(badIds[3], nil, "a fraction does not become id 3")
    T.eq(badNames["3.5"], true, "but stays a name that will find nothing")
    T.eq(badIds[0], nil, "zero does not count as an id")
    T.eq(badNames["-7"], true, "and neither does a negative number")

    -- The name key: the edge spaces are stripped, an empty one is not an entry.
    T.eq(Filter.Key("  Rend  "), "rend", "the edge spaces are stripped")
    T.eq(Filter.Key("   "), nil, "an empty name is not an entry")
    T.eq(Filter.Key(42), nil, "and neither is a non-string")
end

T.suite("aura filter: the decision for one aura in every combination")

do
    local Filter = pure.Filter

    -- The module defaults: the filter hides nothing. That is the main property
    -- of the whole file -- a filter that hid something needed is discovered in a raid and costs dearly.
    local fresh = Filter.Compile({ filterMode = "off", filterList = "",
        onlyMine = false })
    T.eq(fresh.mode, "off", "a fresh install filters nothing")
    T.eq(Filter.Allows(fresh, nil, nil, false, false), true,
        "a foreign buff is shown")
    T.eq(Filter.Allows(fresh, nil, nil, true, true), true,
        "and so is our own debuff")
    T.eq(Filter.NeedsKey(fresh), false,
        "and with the defaults no name key is created at all")

    -- With no plan, show. A filter that failed to assemble for whatever reason
    -- must hide nothing: the opposite default is an empty screen in combat.
    T.eq(Filter.Allows(nil, "rend", 1, false, false), true,
        "with no plan the auras are not lost")
    T.eq(Filter.Allows("not a table", nil, nil, false, false), true,
        "and garbage instead of a plan hides nothing either")

    -- An invented mode from SavedVariables means nothing.
    T.eq(Filter.Compile({ filterMode = "invention", filterList = "Rend" }).mode,
        "off", "an unknown mode means \"do not touch\"")

    -- An empty list switches the mode off entirely: "show only these" with an
    -- empty list would mean an empty screen, while whoever erased the line
    -- wants their former look back rather than to be left with no auras.
    local emptyAllow = Filter.Compile({ filterMode = "allow", filterList = "" })
    T.eq(emptyAllow.mode, "off", "an empty list switches \"only these\" off")
    T.eq(Filter.Allows(emptyAllow, nil, nil, false, false), true,
        "and the auras are not lost")
    T.eq(Filter.Compile({ filterMode = "deny", filterList = "  ,  " }).mode,
        "off", "a list of nothing but spaces is empty too")

    -- A full enumeration of the axes. What is expected is computed here from
    -- the rule written in words rather than from a second list of examples:
    -- enumeration is good precisely because it covers the combinations examples forget.
    --
    -- There are five axes: what the list does, whether the aura is named,
    -- whether the player cast it, "only mine", and the two per-kind switches;
    -- the kind of the aura is the sixth, and it also chooses which switch is asked.
    --
    -- The rule in full: "hide" removes the named; "show only these" keeps the
    -- named, removes everything else and outranks all our rules at once;
    -- "hide every buff" and "hide every debuff" extinguish their own kind;
    -- "only mine" removes foreign buffs, does not touch debuffs and is not
    -- asked where the buffs are extinguished entirely.
    local MODES = { "off", "deny", "allow" }
    local BOOL  = { true, false }

    local function expected(mode, inList, mine, harmful, onlyMine,
        hideBuffs, hideDebuffs)
        if mode == "deny" and inList then return false end
        if mode == "allow" then
            if inList then return true end
            return false
        end
        if harmful then
            if hideDebuffs then return false end
        else
            if hideBuffs then return false end
            if onlyMine and not mine then return false end
        end
        return true
    end

    local combinations, wrong = 0, {}
    local blankWrong = {}
    for _, mode in ipairs(MODES) do
    for _, onlyMine in ipairs(BOOL) do
    for _, hideBuffs in ipairs(BOOL) do
    for _, hideDebuffs in ipairs(BOOL) do
        local plan = Filter.Compile({
            filterMode  = mode,
            filterList  = "Rend, 4242",
            onlyMine    = onlyMine,
            hideBuffs   = hideBuffs,
            hideDebuffs = hideDebuffs,
        })

        -- What the block of each kind learned under this set of settings:
        -- whether it let at least one aura through or none under any combination.
        local anyShown = { [true] = false, [false] = false }

        for _, inList in ipairs(BOOL) do
            for _, mine in ipairs(BOOL) do
                for _, harmful in ipairs(BOOL) do
                    -- A named aura is checked by both keys at once: by name
                    -- and by id, each in its own pass.
                    local byName = inList and "rend" or "foreign"
                    local byId   = inList and 4242 or 1

                    local want = expected(mode, inList, mine, harmful,
                        onlyMine, hideBuffs, hideDebuffs)

                    local gotName = Filter.Allows(plan, byName, nil, mine,
                        harmful)
                    local gotId   = Filter.Allows(plan, nil, byId, mine,
                        harmful)

                    if gotName then anyShown[harmful] = true end

                    combinations = combinations + 2
                    if gotName ~= want or gotId ~= want then
                        wrong[#wrong + 1] = string.format(
                            "%s/mine=%s/no-buffs=%s/no-debuffs=%s/in list=%s/"
                            .. "ours=%s/harmful=%s",
                            mode, tostring(onlyMine), tostring(hideBuffs),
                            tostring(hideDebuffs), tostring(inList),
                            tostring(mine), tostring(harmful))
                    end
                end
            end
        end

        -- The main claim of the whole enumeration: a block that cannot show
        -- anything for any aura must be called such out loud -- and what calls
        -- it such is Filter.Blank, the very answer the settings section shows
        -- its warning by. Two places computing "the block is always empty"
        -- would diverge silently, and the player would learn about the empty
        -- screen in combat.
        for _, harmful in ipairs(BOOL) do
            local blank = Filter.Blank(plan, harmful)
            if blank ~= (not anyShown[harmful]) then
                blankWrong[#blankWrong + 1] = string.format(
                    "%s/mine=%s/no-buffs=%s/no-debuffs=%s/harmful=%s: Blank=%s, "
                    .. "shown=%s",
                    mode, tostring(onlyMine), tostring(hideBuffs),
                    tostring(hideDebuffs), tostring(harmful),
                    tostring(blank), tostring(anyShown[harmful]))
            end
        end
    end
    end
    end
    end

    T.eq(#wrong, 0, "the enumeration of combinations: " .. table.concat(wrong, " | "))
    T.eq(combinations, 384, "combinations checked: " .. tostring(combinations))
    T.eq(#blankWrong, 0, "\"an always empty block\" is named out loud exactly where "
        .. "it really is always empty: " .. table.concat(blankWrong, " | "))

    -- The precedence is named out loud so it cannot be lost silently.
    local allow = Filter.Compile({ filterMode = "allow", filterList = "Rend",
        onlyMine = true })
    T.eq(Filter.Allows(allow, "rend", nil, false, false), true,
        "what is named individually outranks \"only mine\"")
    T.eq(Filter.Allows(allow, "foreign", nil, true, false), false,
        "while what is not named is not shown, even our own")

    local deny = Filter.Compile({ filterMode = "deny", filterList = "Rend",
        onlyMine = true })
    T.eq(Filter.Allows(deny, "rend", nil, true, true), false,
        "the ban outranks everything: even our own debuff disappears")
    T.eq(Filter.Allows(deny, "foreign", nil, false, true), true,
        "\"only mine\" does not touch debuffs")
    T.eq(Filter.Allows(deny, "foreign", nil, false, false), false,
        "while it does remove a foreign buff")

    -- An entry the player typed that matches nothing: the list consists of it,
    -- the mode is on, and no aura disappears from that beyond the named ones.
    --
    local miss = Filter.Compile({ filterMode = "deny",
        filterList = "A spell that does not exist, 999999" })
    T.eq(miss.mode, "deny", "with unmatched entries the mode stays on")
    T.eq(Filter.Allows(miss, "rend", 17, false, false), true,
        "an unmatched entry hides nothing")
    T.eq(Filter.NeedsKey(miss), true, "there are names in the list -- a key is needed")

    -- A list of nothing but ids needs no name key: string.lower is a new
    -- string per aura, and there is no reason to pay for an empty dictionary.
    T.eq(Filter.NeedsKey(Filter.Compile({ filterMode = "deny",
        filterList = "111, 222" })), false,
        "a list of nothing but ids needs no name key")
end

T.suite("aura filter: the cost of a decision does not depend on the list length")

do
    -- The main property of splitting in two: the decision for one aura costs
    -- the same with a list of one spell and of a thousand. It is checked by
    -- time rather than by reasoning: a filter that walked the list for every
    -- aura would show a thousandfold difference here.
    local Filter = pure.Filter

    local long = {}
    for i = 1, 1000 do long[i] = "Spell " .. i end
    local short = Filter.Compile({ filterMode = "deny", filterList = "Spell 1" })
    local big = Filter.Compile({ filterMode = "deny",
        filterList = table.concat(long, ",") })

    local ROUNDS = 200000

    local function cost(plan)
        local started = os.clock()
        for _ = 1, ROUNDS do
            Filter.Allows(plan, "spell 500", 4242, true, false)
        end
        return os.clock() - started
    end

    cost(short)
    local one = cost(short)
    local thousand = cost(big)

    io.write(string.format(
        "  [aura filter cost] %d decisions: a list of one %.3f ms, "
        .. "of a thousand %.2f ms\n", ROUNDS, one * 1000, thousand * 1000))

    -- The margin is deliberately generous: the check guards the order of magnitude, not percent.
    T.ok(thousand < (one + 0.02) * 4,
        "a list of a thousand costs the same as a list of one")

    -- And a ceiling in seconds rather than only a ratio: the ratio would stay
    -- green if both got more expensive.
    -- The ceiling is twenty times the measured value: it guards the order of
    -- magnitude, that is the return of a list walk or of a table created per
    -- decision, rather than the difference between two runs on a busy machine.
    -- Eighty decisions -- one whole update of the player auras -- cost less
    -- than two hundred-thousandths of a millisecond under this ceiling.
    T.ok(thousand < 0.05, string.format(
        "%d decisions against a list of a thousand fit into 50 ms (%.1f ms)",
        ROUNDS, thousand * 1000))
end

-- === The fake client ========================================================
--
-- The real hot path of the module is run through fake frames: outside the game
-- there is no CreateFrame, and checking "the filter removed an icon" on the
-- absence of icons would mean measuring emptiness. The fake does exactly what
-- the module asks of a frame.

local built = 0

local function object(kind)
    local o = { kind = kind, children = {}, regions = {}, shown = false }

    function o:Show() self.shown = true end
    function o:Hide() self.shown = false end
    function o:SetShown(v) self.shown = v and true or false end
    function o:IsShown() return self.shown end
    function o:SetPoint(point, parent, _, x, y)
        self.point, self.anchor = point, parent
        self.x, self.y = x, y
    end
    function o:ClearAllPoints() self.point, self.anchor = nil, nil end
    function o:SetAllPoints() end
    function o:GetParent() return self.parent end
    function o:SetParent(value) self.parent = value end
    function o:SetSize(w, h) self.w, self.h = w, h end
    function o:SetWidth(w) self.w = w end
    function o:SetHeight(h) self.h = h end
    function o:SetScale() end
    function o:SetAlpha() end
    function o:SetDrawLayer() end

    return o
end

local function texture(parent)
    local t = object("Texture")
    function t:SetTexture(path) self.path = path end
    function t:SetTexCoord() end
    function t:SetVertexColor() end
    function t:SetColorTexture(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
    parent.regions[#parent.regions + 1] = t
    return t
end

local function fontString(parent)
    local f = object("FontString")
    f.text = ""
    function f:SetText(value) self.text = value or "" end
    function f:GetText() return self.text end
    function f:SetJustifyH() end
    function f:SetFont() end
    function f:GetFont() return "font", 10, "" end
    parent.regions[#parent.regions + 1] = f
    return f
end

local function createFrame(kind, _, parent)
    local f = object(kind or "Frame")
    f.parent = parent

    function f:CreateTexture() return texture(self) end
    function f:CreateFontString() return fontString(self) end
    function f:SetScript(name, fn) self[name] = fn end
    function f:RegisterEvent() end
    function f:UnregisterEvent() end

    if kind == "Cooldown" then
        function f:SetCooldown(s, d) self.start, self.duration = s, d end
        function f:Clear() self.start, self.duration = nil, nil end
        function f:SetDrawEdge() end
        function f:SetHideCountdownNumbers() end
    end

    if type(parent) == "table" and parent.children then
        parent.children[#parent.children + 1] = f
    end

    built = built + 1
    return f
end

T.suite("aura filter: the filter, the grid and the pool on a fake client")

do
    local saved = {
        Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        UnitAura = _G.UnitAura, C_UnitAuras = _G.C_UnitAuras,
        BuffFrame = _G.BuffFrame, GetTime = _G.GetTime,
        CreateFrame = _G.CreateFrame, UIParent = _G.UIParent,
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

    _G.SlashCmdList = {}
    _G.GetTime = function() return 1000 end
    _G.C_UnitAuras = nil
    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")
    _G.BuffFrame = nil

    -- The player auras. The seventh value is the source, the tenth the spell
    -- id: that is exactly how the classic UnitAura returns them.
    local AURAS = {
        HELPFUL = {
            { "Own buff",     "icon1", 3, nil, 60, 1030, "player", nil, nil, 101 },
            { "Foreign buff", "icon2", 1, nil, 0,  0,    "party1", nil, nil, 102 },
            { "Another foreign", "icon3", 1, nil, 30, 1020, "party2", nil, nil, 103 },
        },
        HARMFUL = {
            { "Poison",  "icon4", 2, nil, 20, 1010, "target", nil, nil, 201 },
            { "Curse", "icon5", 1, nil, 40, 1040, "target", nil, nil, 202 },
        },
    }
    _G.UnitAura = function(_, index, filter)
        local aura = AURAS[filter] and AURAS[filter][index]
        if not aura then return nil end
        return aura[1], aura[2], aura[3], aura[4], aura[5], aura[6], aura[7],
            aura[8], aura[9], aura[10]
    end

    local ns = helpers.newNamespace()
    helpers.loadModule(MODULE, ns)

    local handle = core.Registry:Get("umbraauras")
    T.ok(handle ~= nil, "the module is registered: " .. table.concat(said, " | "))

    if handle then
        -- The filter defaults: nothing is hidden. A fresh install must show
        -- exactly what the game would show.
        T.eq(handle.defaults.filterMode, ns.Filter.DEFAULT_MODE,
            "the mode default is \"filter nothing\"")
        T.eq(handle.defaults.filterList, "", "the list is empty")
        T.eq(handle.defaults.onlyMine, false, "\"only mine\" is off")
        T.eq(handle.defaults.hideBuffs, false, "the buffs are not hidden")
        T.eq(handle.defaults.hideDebuffs, false, "and neither are the debuffs")

        local args = handle.options.args

        -- Every new node is in place.
        local NEW = { "onlyMine", "filterMode", "filterList",
            "hideBuffs", "hideDebuffs", "hideBoth" }
        for i = 1, #NEW do
            local node = args[NEW[i]]
            T.eq(type(node), "table", "the node exists: " .. NEW[i])
        end

        -- Every default is reachable: the mode default must be among the
        -- selection values, otherwise the player cannot get back what they started with.
        local values = args.filterMode.values()
        T.ok(values[handle.defaults.filterMode] ~= nil,
            "the mode default is in the selection list")
        for name in pairs(ns.Filter.MODES) do
            T.ok(values[name] ~= nil, "the mode is in the selection list: " .. name)
        end

        core.Registry:EnableAll()
        args.enabled.set(nil, true)

        local settings = handle:GetSettings()

        -- The icons are children of UIParent rather than of the holder: the
        -- holder is only their anchor point. So the walk goes over the children
        -- of UIParent, and an icon is recognised by its first region -- the spell texture.

        --- All icons of the module, shown or not.
        -- @return table an array of frames
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

        --- What the player sees on screen.
        -- @return table an array of texture paths, in order
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

        --- The holder the icon carrying this texture is anchored to.
        -- @param wanted string
        -- @return table|nil
        local function holderOf(wanted)
            local all = icons()
            for i = 1, #all do
                if all[i].shown and all[i].regions[1].path == wanted then
                    return all[i].anchor
                end
            end
            return nil
        end

        -- With no filter everything the game returned is shown: five auras.
        T.eq(#shown(), 5, "with no filter every aura is shown")

        -- The holders of both blocks are remembered now, while each still has
        -- an icon: an empty block has no icons, and there would be nothing to
        -- find it by later.
        local buffHolder   = holderOf("icon1")
        local debuffHolder = holderOf("icon4")
        T.ok(buffHolder ~= nil, "the holder of the buff block was found")
        T.ok(debuffHolder ~= nil and debuffHolder ~= buffHolder,
            "and the holder of the debuff block is a different one")

        -- "Only mine" removes foreign buffs and does not touch debuffs.
        args.onlyMine.set(nil, true)
        local list = shown()
        T.eq(#list, 3, "\"only mine\": our own buff and both debuffs remained")
        T.eq(table.concat(list, ","), "icon1,icon4,icon5",
            "and exactly the right ones")
        args.onlyMine.set(nil, false)

        -- A ban by name. The name is typed as it is written in the game: for
        -- Cyrillic the comparison is exact, and that is stated out loud.
        args.filterList.set(nil, "Poison")
        args.filterMode.set(nil, "deny")
        list = shown()
        T.eq(#list, 4, "the ban by name removed one aura")
        T.eq(table.concat(list, ","), "icon1,icon2,icon3,icon5",
            "and removed exactly the named one")

        -- A ban by spell id. It is also the answer to a change of client
        -- language: the name comes from the game, the id does not change.
        args.filterList.set(nil, "202")
        list = shown()
        T.eq(table.concat(list, ","), "icon1,icon2,icon3,icon4",
            "the ban by id removed an aura whose name was never typed")

        -- An entry that matched nothing removes nothing.
        args.filterList.set(nil, "A spell that does not exist, 999999")
        T.eq(#shown(), 5, "an unmatched entry hides nothing")

        -- "Show only these" applies to one block. The second block stays
        -- empty, and that is a legitimate outcome which must be drawn as empty
        -- rather than as a hole.
        args.filterList.set(nil, "101, 103")
        args.filterMode.set(nil, "allow")
        list = shown()
        T.eq(table.concat(list, ","), "icon1,icon3",
            "only the named buffs are shown")

        -- The debuff block emptied: the holder is hidden entirely. A shown
        -- empty holder is an invisible rectangle catching the mouse where
        -- there is nothing on screen.
        T.eq(debuffHolder.shown, false, "the empty block is hidden entirely")
        T.eq(buffHolder.shown, true, "while the non-empty one is shown")

        -- A block shorter than a row: two icons with twelve per row stand in
        -- one row, and the holder is exactly their size.
        local size, perRow, spacing = ns.Layout.Grid(settings)
        local width, height = ns.Layout.Block(2, perRow, size, spacing)
        T.eq(buffHolder.w, width, "the holder width matches the two icons")
        T.eq(buffHolder.h, height, "while the height is one row")
        T.eq(height, size, "a block shorter than a row takes exactly one row")

        -- The pool: an icon that stopped passing the filter returned to the
        -- pool empty rather than staying around. It is checked directly -- by walking the record.
        local before = built
        args.filterList.set(nil, "101")
        list = shown()
        T.eq(#list, 1, "one icon remained")
        T.eq(built, before, "no new frames were created for that")

        local leftovers = {}
        local all = icons()
        for i = 1, #all do
            local icon = all[i]
            if not icon.shown and type(icon.record) == "table" then
                for key in pairs(icon.record) do
                    leftovers[#leftovers + 1] = tostring(key)
                end
            end
        end
        T.eq(#leftovers, 0, "no record fields are left in the hidden icons: "
            .. table.concat(leftovers, ", "))

        -- A filter that removed every single aura: both blocks are empty, not
        -- a single shown icon, and not a single error on the path.
        args.filterList.set(nil, "999999")
        T.eq(#shown(), 0, "the filter is entitled to leave the screen empty")
        T.eq(core.Registry:IsEnabled(handle), true, "and the path ran without error")

        -- A return to the defaults restores everything: every default is
        -- reachable not only on paper.
        args.filterMode.set(nil, handle.defaults.filterMode)
        args.filterList.set(nil, handle.defaults.filterList)
        T.eq(#shown(), 5, "the return to the defaults brought every aura back")

        -- === The two per-kind switches on the live path ===================
        --
        -- What is checked is not the decision -- it is enumerated above -- but
        -- that the block really goes out entirely and the holder is hidden
        -- rather than left as an invisible rectangle catching the mouse.

        T.eq(args.hideBoth.hidden(), true,
            "with the defaults there is no line about an empty screen")
        T.eq(args.onlyMine.disabled(), false,
            "and \"only mine\" is alive")

        args.hideBuffs.set(nil, true)
        list = shown()
        T.eq(table.concat(list, ","), "icon4,icon5",
            "\"hide every buff\" removed the whole buff block")
        T.eq(buffHolder.shown, false, "the holder of the buff block is hidden")
        T.eq(debuffHolder.shown, true, "while the debuff block is untouched")

        -- There is nothing left for "only mine" to narrow, and the settings
        -- section greys it out itself: a live switch that changes nothing is a
        -- second place the player looks for the answer to "why do I not see the aura".
        T.eq(args.onlyMine.disabled(), true,
            "\"only mine\" is greyed out while the buffs are hidden entirely")
        T.eq(args.hideBoth.hidden(), true,
            "but one switch is not enough for the empty-screen line")

        -- The converse: debuffs only.
        args.hideBuffs.set(nil, false)
        args.hideDebuffs.set(nil, true)
        list = shown()
        T.eq(table.concat(list, ","), "icon1,icon2,icon3",
            "\"hide every debuff\" removed the whole debuff block")
        T.eq(debuffHolder.shown, false, "the holder of the debuff block is hidden")
        T.eq(buffHolder.shown, true, "while the buff block is untouched")
        T.eq(args.onlyMine.disabled(), false,
            "\"only mine\" is alive meanwhile: the buffs are in place")

        -- Both at once: nothing is left on screen, and that is exactly what the
        -- player is told by a line in the settings. The standard grid is
        -- already removed by that point, and learning about the emptiness in combat would be too late.
        args.hideBuffs.set(nil, true)
        T.eq(#shown(), 0, "both switches: not a single aura on screen")
        T.eq(buffHolder.shown, false, "the buff block is empty")
        T.eq(debuffHolder.shown, false, "and so is the debuff block")
        T.eq(args.hideBoth.hidden(), false,
            "and the empty screen is stated out loud rather than discovered in combat")
        T.eq(core.Registry:IsEnabled(handle), true, "the path ran without error")

        -- The list in "show only these" mode outranks the switch: what is named
        -- individually comes back, and the empty-screen line goes away because
        -- there is no emptiness any more.
        args.filterList.set(nil, "101")
        args.filterMode.set(nil, "allow")
        T.eq(table.concat(shown(), ","), "icon1",
            "the list outranks the switch: the named buff came back")
        T.eq(args.hideBoth.hidden(), true,
            "and the empty-screen line went away with the emptiness")

        -- While "hide the named" does not cancel the switch: the block was
        -- empty and stayed empty, and the line came back.
        args.filterMode.set(nil, "deny")
        T.eq(#shown(), 0, "\"hide the named\" brings nothing back")
        T.eq(args.hideBoth.hidden(), false, "the empty-screen line came back")

        -- A return to the defaults restores everything here too.
        args.hideBuffs.set(nil, false)
        args.hideDebuffs.set(nil, false)
        args.filterMode.set(nil, handle.defaults.filterMode)
        args.filterList.set(nil, handle.defaults.filterList)
        T.eq(#shown(), 5, "both switches are cleared without a trace")

        -- An aura change by an event goes the same path and does not reassemble the plan.
        core.Events.Dispatch("UNIT_AURA", "player")
        T.eq(#shown(), 5, "an aura change by an event draws the same thing")
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.BuffFrame = saved.BuffFrame
    _G.C_UnitAuras = saved.C_UnitAuras
end

T.suite("aura filter: the offset for the next block")

do
    local Layout = pure.Layout

    -- An empty block takes no space at all: a hole one icon tall reads as
    -- "something failed to draw".
    T.eq(Layout.Advance(0, 30, 4), 0, "an empty block takes no space")
    T.eq(Layout.Advance(0, 0, 4), 0, "and neither does a zero height")

    -- A non-empty one takes its own height plus a double gap: between blocks it
    -- must be more noticeable than between rows inside a block.
    T.eq(Layout.Advance(1, 30, 4), 38, "one icon: its own height and two gaps")
    T.eq(Layout.Advance(9, 64, 0), 64, "with no gap, exactly the height")
    T.eq(Layout.Advance(3, 30, -5), 30, "a negative gap is zero")
    T.eq(Layout.Advance("garbage", 30, 4), 0, "garbage instead of a number gives an empty block")
end

T.suite("aura filter: the settings section through the eyes of the real AceConfig")

do
    -- Validating the section with the real library rather than with the fake
    -- from helpers: a node with an unknown field means a settings window that
    -- does not open at all, and none of our checks would see that.
    local saved = {
        LibStub = _G.LibStub, securecallfunction = _G.securecallfunction,
        Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        CreateFrame = _G.CreateFrame, UIParent = _G.UIParent,
        UnitAura = _G.UnitAura, GetTime = _G.GetTime,
    }

    _G.LibStub = nil
    _G.securecallfunction = function(fn, ...) return fn(...) end
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    dofile("Libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua")

    local registry = LibStub("AceConfigRegistry-3.0")
    T.eq(type(registry), "table", "AceConfigRegistry-3.0 loaded")

    -- A check of the check: without it the green result below would mean nothing.
    T.err(function()
        registry:ValidateOptionsTable(
            { type = "group", name = "T", args = {
                a = { type = "toggle", name = "x", level = "basic" },
            } }, "T")
    end, "the validator rejects an invented level field")

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
        db = { profile = {}, global = {} },
        Print = function() end,
    }
    core.flavor = "mists"

    _G.SlashCmdList = {}
    _G.CreateFrame = createFrame
    _G.UIParent = object("Frame")
    _G.GetTime = function() return 1000 end
    _G.UnitAura = function() return nil end

    local ns = helpers.newNamespace()
    helpers.loadModule(MODULE, ns)

    local handle = core.Registry:Get("umbraauras")
    T.ok(handle ~= nil, "the module is registered with the real library")

    if handle then
        local ok, err = pcall(registry.ValidateOptionsTable, registry,
            handle.options, "Features/Auras")
        T.ok(ok, "the module section passes the AceConfig validation: " .. tostring(err))
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.LibStub = saved.LibStub
    _G.Darken = saved.Darken
end

helpers.removeValidator()
