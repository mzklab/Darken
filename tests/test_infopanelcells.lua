local helpers = require("helpers")
local localekeys = require("localekeys")

helpers.installValidator()

-- The second increment of the info panel: the mouse on a cell, and a screen
-- offset that can account for itself.
--
-- What is checked here is exactly what this increment added, and it falls
-- into two halves.
--
-- The first is clicking and hovering. The LibDataBroker standard describes
-- four mouse handlers on a data source, and they belong to whoever created
-- it. The panel adds its own menu to them, and there is one main requirement
-- for it: a foreign source must get the same menu as ours. That is checked
-- not by words in a report but by comparing two menus row by row -- and once
-- more against the source, in which the names of our own sources simply do not occur.
--
-- The second is the place on screen. The UIParent offset has never once been
-- performed in a live client, and everything checked here is written for the
-- day it is: three different numbers instead of one (asked for, applied,
-- waiting for combat), a comparison of the live anchors against ours, and a
-- recomputation of the offset after a resolution change.

local MODULE = "Features/InfoPanel"

-- The module takes its number formatting from the core while reading its own
-- Format.lua (Darken:GetFormat, contract 12). The door is opened by the real
-- core file -- a fake beside it would be checking a copy instead of what the player sees.
local coreFormat, restoreCore = helpers.installFormat()


--- Load the module files into a fresh namespace.
-- @param withRegistration boolean
-- @return table
local function moduleNamespace(withRegistration)
    local ns = helpers.newNamespace()
    ns = helpers.loadModule(MODULE, ns, { withRegistration = withRegistration })
    -- The translation comes from InfoPanel.lua, while the pure parts are read
    -- without it: the key IS the English string, so the fake returns it unchanged.
    if type(ns.Localize) ~= "function" then
        ns.Localize = function(key) return key end
    end
    return ns
end

local ns = moduleNamespace(false)

--============================================================================

T.suite("info panel: what a data source can do by itself")

do
    local C = ns.Cells

    -- A source that draws its own tooltip is the most common kind among
    -- foreign ones: it has its own tooltip with its own structure, and the panel must get out of the way.
    local own = { text = "1", OnEnter = function() end,
        OnLeave = function() end, OnClick = function() end }
    local offers = C.Offers(own)
    T.eq(offers.click, true, "the source takes the click upon itself")
    T.eq(offers.enter, true, "and the hover too")
    T.eq(C.Tooltip(own, "Gold", "5").kind, "own",
        "the source draws the tooltip itself")

    -- One that asks to fill a foreign tooltip.
    local fill = { text = "1", OnTooltipShow = function() end }
    T.eq(C.Offers(fill).tooltip, true, "a tooltip is promised")
    T.eq(C.Tooltip(fill).kind, "fill", "the panel gives it its own tooltip")

    -- Ready-made text.
    local ready = { text = "1", tooltiptext = "Ten bags" }
    T.eq(C.Tooltip(ready).kind, "text", "ready-made text is shown as it is")
    T.eq(C.Tooltip(ready).text, "Ten bags", "and that is it")

    -- None of that: the panel shows what it knows anyway.
    local plain = { label = "Gold", text = "5" }
    local plan = C.Tooltip(plain, "Gold", "5")
    T.eq(plan.kind, "cell", "with no promises the label and the value are shown")
    T.eq(plan.label, "Gold", "the label is in place")
    T.eq(plan.text, "5", "the value is in place")

    T.eq(C.Tooltip(nil).kind, "cell", "there is no source -- still nothing to break")
    T.eq(C.Offers(nil).click, false, "and it promises nothing")

    -- A foreign object is entitled to be hostile: in the real library a field
    -- is backed by a metatable, that is by foreign code.
    local angry = setmetatable({}, { __index = function()
        error("the foreign metatable failed", 0)
    end })
    T.eq(C.Offers(angry).click, false, "a failing field read is a \"no\", not an error")
    T.eq(C.Tooltip(angry).kind, "cell", "and our own tooltip is assembled")
    T.eq(C.Click(angry, nil, "LeftButton"), false, "there is nobody to call")

    -- The source's own click is called with the cell frame and the button --
    -- that is what the standard describes and what foreign addons expect.
    local seen
    local clicker = { text = "1",
        OnClick = function(frame, button) seen = { frame, button } end }
    T.eq(C.Click(clicker, "cell", "LeftButton"), true, "the click arrived")
    T.eq(seen[1], "cell", "the cell frame is passed first")
    T.eq(seen[2], "LeftButton", "the button second")

    -- A failing foreign click does not break the panel.
    local boom = { text = "1", OnClick = function() error("the foreign one failed", 0) end }
    T.eq(C.Click(boom, nil, "LeftButton"), true, "the failing click was handled")
end

--============================================================================

T.suite("info panel: the cell menu")

do
    local C = ns.Cells

    local arranged = { "AAA Foreign", "Middle", "ZZZ Last" }
    local settings = { top = true, bottom = true, defaultSide = "top",
        order = {}, hidden = {}, sides = {} }

    local function kinds(entries)
        local out = {}
        for _, entry in ipairs(entries) do
            out[#out + 1] = entry.kind .. (entry.delta and tostring(entry.delta)
                or entry.side or "")
        end
        return table.concat(out, ",")
    end

    local middle = C.Menu("Middle", settings, arranged, C.Offers({ text = "1" }))
    T.eq(kinds(middle), "hide,move-1,move1,sidetop,sidebottom",
        "the menu rows and their order")

    -- An edge cell: the row is in place but greyed out. A vanished row would
    -- shift its neighbours under an already raised hand.
    local first = C.Menu("AAA Foreign", settings, arranged)
    T.eq(#first, #middle, "an edge cell has just as many rows")
    T.eq(first[2].enabled, false, "there is nowhere further left")
    T.eq(first[3].enabled, true, "while there is somewhere further right")

    local last = C.Menu("ZZZ Last", settings, arranged)
    T.eq(last[3].enabled, false, "the last one has nowhere further right")

    -- The strip: the cell is on the top one, so "to the top" is greyed out.
    T.eq(middle[4].enabled, false, "it is already on the top strip")
    T.eq(middle[5].enabled, true, "while it can be moved to the bottom one")

    -- A disabled strip is not offered at all.
    local oneBar = { top = true, bottom = false, defaultSide = "top" }
    local only = C.Menu("Middle", oneBar, arranged)
    T.eq(only[5].enabled, false, "a disabled strip is not offered")

    -- The source's own action is the first row, and only when it has one.
    --
    local withClick = C.Menu("Middle", settings, arranged,
        C.Offers({ text = "1", OnClick = function() end }))
    T.eq(withClick[1].kind, "own", "the source's own action comes first")
    T.eq(#withClick, #middle + 1, "and adds exactly one row")

    T.eq(#C.Menu(nil, settings, arranged), 0, "with no name no menu is assembled")
end

--============================================================================

T.suite("info panel: the menu changes the settings")

do
    local C = ns.Cells
    local names = { "AAA Foreign", "Middle", "ZZZ Last" }
    local settings = { top = true, bottom = true, defaultSide = "top",
        order = {}, hidden = {}, sides = {} }

    local menu = C.Menu("Middle", settings, names)

    T.eq(C.Apply(menu[1], "Middle", settings, names), true, "the hide was accepted")
    T.eq(settings.hidden["Middle"], true, "the cell is hidden")

    T.eq(C.Apply(menu[2], "Middle", settings, names), true, "the reorder was accepted")
    T.eq(settings.order[1], "Middle", "the cell moved further left")

    T.eq(C.Apply(menu[5], "Middle", settings, names), true, "the move was accepted")
    T.eq(settings.sides["Middle"], "bottom", "the cell is on the bottom strip")

    -- A greyed-out row does nothing: clicking it is possible because the
    -- frame accepts the click, while the decision is here.
    local grey = { kind = "hide", enabled = false }
    T.eq(C.Apply(grey, "AAA Foreign", settings, names), false,
        "a greyed-out row changes nothing")
    T.eq(settings.hidden["AAA Foreign"], nil, "and hid nothing")

    -- The row of the source's own action does not touch the settings: it is
    -- executed by the source itself.
    T.eq(C.Apply({ kind = "own" }, "Middle", settings, names), false,
        "a foreign action is none of our business")
end

--============================================================================

T.suite("info panel: a foreign source gets the same menu as ours")

do
    local C = ns.Cells
    local B = ns.Broker
    local S = ns.Sources

    local broker = B.NewShim()

    -- A foreign addon creates its source itself, knowing nothing about us.
    broker:NewDataObject("AAA Foreign", {
        type = "data source", label = "Gold", text = "12g 34s 56c",
    })
    S.Publish(broker)

    local names = B.Names(broker)
    local arranged = ns.Layout.Arrange(names, nil)
    local settings = { top = true, bottom = true, defaultSide = "top",
        order = {}, hidden = {}, sides = {} }

    local function sameMenu(a, b)
        if #a ~= #b then return "length: " .. #a .. " and " .. #b end
        for i = 1, #a do
            if a[i].kind ~= b[i].kind then return "row " .. i .. ": kind" end
            if a[i].label ~= b[i].label then return "row " .. i .. ": label" end
            if a[i].side ~= b[i].side then return "row " .. i .. ": strip" end
            if a[i].delta ~= b[i].delta then return "row " .. i .. ": step" end
        end
        return nil
    end

    -- Our source is placed at the same position in the row as the foreign
    -- one, and the menu must match letter for letter. What is compared is not
    -- "roughly the same capabilities" but the rows themselves.
    local ourName = S.Name("gold")
    local theirs = C.Menu("AAA Foreign", settings, { "AAA Foreign", ourName },
        C.Offers(broker:GetDataObjectByName("AAA Foreign")))
    local ours = C.Menu(ourName, settings, { ourName, "AAA Foreign" },
        C.Offers(broker:GetDataObjectByName(ourName)))
    T.eq(sameMenu(theirs, ours), nil, "the menu matches row for row")

    -- The difference appears exactly where the standard itself created it:
    -- the source has an OnClick. Give ours one and the menus match again.
    local foreign = broker:GetDataObjectByName("AAA Foreign")
    foreign.OnClick = function() end
    theirs = C.Menu("AAA Foreign", settings, { "AAA Foreign", ourName },
        C.Offers(foreign))
    T.eq(#theirs, #ours + 1, "its own action added one row to the foreign one")

    local mine = broker:GetDataObjectByName(ourName)
    mine.OnClick = function() end
    ours = C.Menu(ourName, settings, { ourName, "AAA Foreign" }, C.Offers(mine))
    T.eq(sameMenu(theirs, ours), nil,
        "with the same standard promise the menus match again")

    -- And the same rule as text over the source. An "ah, but this one is
    -- ours" branch appears not in the design but in an edit six months later -- this check will catch it.
    local source = localekeys.read("Features/InfoPanel/Cells.lua")
    T.eq(source:find("Darken ", 1, true), nil,
        "the mouse rules do not know the prefix of our names")
    T.eq(source:find("ns.Sources", 1, true), nil,
        "and never call our sources once")
end

--============================================================================

T.suite("info panel: verifying the screen offset")

do
    local L = ns.Layout

    local base = { { "TOPLEFT", nil, "TOPLEFT", 0, 0 },
        { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 } }
    local moved = L.Offsets(base, 18, 0)

    T.eq(L.Verify(moved, moved), nil, "a match stays silent")
    T.eq(L.Verify(moved, { moved[1] }) ~= nil, true, "a vanished anchor is visible")
    T.eq(L.Verify(moved, nil), "UIParent has no anchors at all",
        "a frame with no anchors is named in words")

    -- A foreign addon moved UIParent after us: the numbers diverged, and the
    -- report must name exactly where.
    local other = { { "TOPLEFT", nil, "TOPLEFT", 0, -40 }, moved[2] }
    local drift = L.Verify(moved, other)
    T.ok(drift ~= nil and drift:find("TOPLEFT", 1, true) ~= nil,
        "the divergence is named: " .. tostring(drift))

    local elsewhere = { { "CENTER", nil, "CENTER", 0, 0 }, moved[2] }
    T.ok(L.Verify(moved, elsewhere) ~= nil, "a changed anchor point is visible too")

    -- An engine refusal to protected code. Ours is recognised as ours, a
    -- foreign one as foreign, and nobody's while no screen space has been taken.
    T.eq(L.Blame("Features/InfoPanel", "Features/InfoPanel", "Darken", true),
        true, "our refusal is recognised as ours")
    T.eq(L.Blame("Darken", "Features/InfoPanel", "Darken", true), true,
        "a refusal to the core is ours too: the panel moves UIParent on its behalf")
    T.eq(L.Blame("SomeOtherAddon", "Features/InfoPanel", "Darken", true), false,
        "a foreign refusal is not ours")
    T.eq(L.Blame("Features/InfoPanel", "Features/InfoPanel", "Darken", false),
        false, "we did not move anything -- not ours")
    T.eq(L.Blame(nil, "Features/InfoPanel", "Darken", true), false,
        "with no name there is nobody to blame")
end

--============================================================================

--- An engine fake for exactly what the panel drawing calls.
-- @return function CreateFrame
-- @return table the created frames
local function fakeEngine()
    local made = {}

    local function fakeRegion()
        local region = { shown = true }
        function region:SetText(value) self.text = value end
        function region:GetText() return self.text end
        function region:GetStringWidth() return #tostring(self.text or "") * 6 end
        function region:SetJustifyH() end
        function region:SetPoint() end
        function region:ClearAllPoints() end
        function region:Show() self.shown = true end
        function region:Hide() self.shown = false end
        return region
    end

    local function fakeFrame(kind)
        local frame = { kind = kind, shown = false, scripts = {} }
        function frame:SetPoint() end
        function frame:SetAllPoints() end
        function frame:ClearAllPoints() end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetWidth(w) self.width = w end
        function frame:SetHeight(h) self.height = h end
        function frame:GetHeight() return self.height or 18 end
        function frame:GetTop() return 760 end
        function frame:SetFrameStrata() end
        function frame:EnableMouse() end
        function frame:RegisterForClicks() end
        function frame:SetScript(key, fn) self.scripts[key] = fn end
        function frame:GetScript(key) return self.scripts[key] end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:IsShown() return self.shown end
        function frame:CreateFontString() return fakeRegion() end
        function frame:CreateTexture() return fakeRegion() end
        made[#made + 1] = frame
        return frame
    end

    return function(kind) return fakeFrame(kind) end, made
end

T.suite("info panel: a cell accepts the mouse")

do
    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent,
        GameTooltip = _G.GameTooltip }

    local create = fakeEngine()
    _G.CreateFrame = create
    _G.UIParent = { GetHeight = function() return 1080 end }

    local lines = {}
    _G.GameTooltip = {
        SetOwner = function() end,
        ClearLines = function() lines = {} end,
        ClearAllPoints = function() end,
        SetPoint = function() end,
        AddLine = function(_, text) lines[#lines + 1] = text end,
        Show = function() end,
        Hide = function() end,
    }

    local P = ns.Panel
    local frame = P.Build(nil)
    T.ok(frame ~= nil, "the strip was assembled on the fake engine")

    local clicks = {}
    local mouse = {
        Click = function(name, button) clicks[#clicks + 1] = name .. "/" .. tostring(button) end,
        Enter = function(name, cell) P.Tooltip({ kind = "cell",
            label = name, text = "5" }, cell) end,
        Leave = function() P.Untooltip() end,
    }

    P.SetCells(frame, { { name = "AAA Foreign", text = "Gold: 5" },
        { name = "Darken Gold", text = "Gold: 5" } }, nil, nil, 12, mouse)

    local cells = frame.cells
    T.eq(#cells, 2, "there are now two cells")
    T.eq(cells[1].cellName, "AAA Foreign", "the cell carries the source name")
    T.eq(cells[1].label:GetText(), "Gold: 5", "and its line")

    -- The click goes out with the name and the button -- through one and the
    -- same handler for both cells, because they share one handler.
    cells[1].scripts.OnClick(cells[1], "RightButton")
    cells[2].scripts.OnClick(cells[2], "LeftButton")
    T.eq(clicks[1], "AAA Foreign/RightButton", "the foreign cell named itself")
    T.eq(clicks[2], "Darken Gold/LeftButton", "ours did so the same way")

    -- Hovering and leaving.
    cells[1].scripts.OnEnter(cells[1])
    T.eq(lines[1], "AAA Foreign", "the tooltip was assembled")
    cells[1].scripts.OnLeave(cells[1])

    -- There are fewer sources: the extra cell is hidden and its name is
    -- removed -- otherwise a click on the invisible would lead to a source that does not exist.
    P.SetCells(frame, { { name = "AAA Foreign", text = "Gold: 6" } },
        nil, nil, 12, mouse)
    T.eq(cells[2]:IsShown(), false, "the extra cell is hidden")
    T.eq(cells[2].cellName, nil, "and no name is left on it")

    -- The menu: it opens, and a second click on the same cell closes it.
    local picked
    local entries = { { kind = "hide", label = "Hide This Cell", enabled = true },
        { kind = "move", label = "Move Earlier", enabled = false } }
    P.Menu(entries, cells[1], "AAA Foreign", nil, nil,
        function(entry) picked = entry.kind end)
    T.eq(P.menu:IsShown(), true, "the menu is open")
    T.eq(P.menuOf, "AAA Foreign", "and it is open at the cell that was clicked")
    T.eq(P.catcher:IsShown(), true, "and so is the catcher for clicks outside the menu")

    P.menuRows[1].scripts.OnClick(P.menuRows[1])
    T.eq(picked, "hide", "the choice arrived")
    T.eq(P.menu:IsShown(), false, "the menu closed by itself")

    -- A greyed-out row closes the menu and chooses nothing.
    picked = nil
    P.Menu(entries, cells[1], "AAA Foreign", nil, nil,
        function(entry) picked = entry.kind end)
    P.menuRows[2].scripts.OnClick(P.menuRows[2])
    T.eq(picked, nil, "the greyed-out row chose nothing")
    T.eq(P.menu:IsShown(), false, "but it closed the menu")

    -- A second click on the same cell closes the menu.
    P.Menu(entries, cells[1], "AAA Foreign", nil, nil, function() end)
    P.Menu(entries, cells[1], "AAA Foreign", nil, nil, function() end)
    T.eq(P.menu:IsShown(), false, "the second click closed the menu")

    -- So does a click outside the menu.
    P.Menu(entries, cells[1], "AAA Foreign", nil, nil, function() end)
    P.catcher.scripts.OnClick(P.catcher)
    T.eq(P.menu:IsShown(), false, "a click outside closed the menu")

    for key, value in pairs(saved) do _G[key] = value end
    _G.UIParent = saved.UIParent
    _G.GameTooltip = saved.GameTooltip
    _G.CreateFrame = saved.CreateFrame
end

--============================================================================

T.suite("info panel: the mouse and the screen space in the assembled module")

do
    local saved = { Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        UIParent = _G.UIParent, LibStub = _G.LibStub,
        InCombatLockdown = _G.InCombatLockdown }

    local core = helpers.newNamespace()
    for _, file in ipairs({ "Core/Compat.lua", "Core/Registry.lua",
        "Core/Defaults.lua", "Core/Command.lua", "Core/Locale.lua",
        "Core/Skin.lua", "Skin/Draw.lua", "Core/Frames.lua", "Core/Events.lua",
        "Core/Combat.lua", "Core/Casefold.lua", "Core/Format.lua", "Core/Api.lua",
        "Core/Media.lua" }) do
        helpers.loadAddonFile(file, core)
    end

    local said = {}
    core.Registry.report = function(text) said[#said + 1] = text end

    local profile = { umbrainfo = { enabled = false, top = true, bottom = false,
        height = 18, push = true, defaultSide = "top",
        order = {}, hidden = {}, sides = {},
        clock12 = false, clockSeconds = false,
        xpMode = "current", repMode = "current" } }

    core.Addon = {
        db = { profile = profile, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }
    core.flavor = "mists"

    _G.SlashCmdList = {}

    local combat = false
    _G.InCombatLockdown = function() return combat end

    local anchors = {
        { "TOPLEFT", nil, "TOPLEFT", 0, 0 },
        { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 },
    }
    _G.UIParent = {
        IsProtected = function() return true end,
        GetNumPoints = function() return #anchors end,
        GetPoint = function(_, i)
            local p = anchors[i]
            return p[1], p[2], p[3], p[4], p[5]
        end,
        ClearAllPoints = function() anchors = {} end,
        SetPoint = function(_, point, relativeTo, relativePoint, x, y)
            anchors[#anchors + 1] = { point, relativeTo, relativePoint, x, y }
        end,
    }

    --- The current offset of the top screen edge.
    local function topEdge()
        for _, p in ipairs(anchors) do
            if p[1] == "TOPLEFT" then return p[5] end
        end
        return nil
    end

    --- Whether the report holds a line with these words.
    local function reported(report, needle)
        for _, line in ipairs(report) do
            if line:find(needle, 1, true) then return line end
        end
        return nil
    end

    -- LibDataBroker is not in this installation: there is nothing to show
    -- foreign sources with, and the module creates its own replacement. The
    -- path without the library must work -- it is not part of the package.
    --
    -- LibStub meanwhile is present and answers for the settings section check
    -- (AceConfigRegistry): in game it happens exactly like that -- one
    -- library exists, the other does not, and they are asked for by name.
    local aceStub = _G.LibStub

    local panelNs = moduleNamespace(true)
    local handle = core.Registry:Get("umbrainfo")
    T.ok(handle ~= nil, "the module is registered")

    -- Drawing is replaced by recording: the frames themselves are not needed
    -- here, what is needed is what the module hands to the drawing -- the
    -- cell lines and the mouse handlers. That way the real wiring is under the check rather than a retelling of it.
    local drawn, opened = {}, nil
    panelNs.Panel.Build = function() return { cells = {}, row = {} } end
    panelNs.Panel.Place = function() end
    panelNs.Panel.Show = function() end
    panelNs.Panel.Drive = function() end
    panelNs.Panel.Untooltip = function() end
    panelNs.Panel.Tooltip = function(plan) drawn.tooltip = plan end
    panelNs.Panel.CloseMenu = function() opened = nil end
    panelNs.Panel.Menu = function(entries, _, name)
        opened = { name = name, entries = entries }
    end
    panelNs.Panel.SetCells = function(_, cells, _, _, _, mouse)
        drawn.cells = cells
        drawn.mouse = mouse
    end

    if handle then
        core.Registry:EnableAll()

        local settings = handle:GetSettings()
        settings.enabled = true
        handle:Apply()

        T.ok(#drawn.cells >= 8, "our sources reached the panel without the library: "
            .. #drawn.cells)
        T.ok(drawn.mouse ~= nil, "the mouse handlers were passed to the drawing")
        T.eq(topEdge(), -18, "and the screen space was taken")

        -- The real library appeared later -- as a load-on-demand addon. Our
        -- sources move into it, and the foreign ones become visible.
        local registry = panelNs.Broker.NewShim()
        _G.LibStub = setmetatable({}, { __call = function(_, name, silent)
            if name == panelNs.Broker.LIB then return registry end
            return aceStub(name, silent)
        end })
        handle:Apply()

        local foreign = registry:NewDataObject("AAA Foreign", {
            type = "data source", label = "Gold", text = "1g",
        })
        handle:Apply()

        local seen = {}
        for _, cell in ipairs(drawn.cells) do seen[cell.name] = true end
        T.eq(seen["AAA Foreign"], true, "the foreign source appeared in the panel")
        T.eq(seen[panelNs.Sources.Name("gold")], true, "ours stayed beside it")

        -- The right button on a foreign cell and on ours: the menu is
        -- assembled by one and the same handler and matches row for row.
        drawn.mouse.Click("AAA Foreign", "RightButton", nil)
        local theirs = opened
        T.eq(theirs.name, "AAA Foreign", "the menu is open at the foreign cell")

        drawn.mouse.Click(panelNs.Sources.Name("gold"), "RightButton", nil)
        local ours = opened
        T.eq(#theirs.entries, #ours.entries, "the menus hold equally many rows")
        for i = 1, #ours.entries do
            T.eq(theirs.entries[i].kind, ours.entries[i].kind,
                "row " .. i .. ": the same kind")
            T.eq(theirs.entries[i].label, ours.entries[i].label,
                "row " .. i .. ": the same label")
        end

        -- The left button belongs to the source: for a foreign one it calls
        -- its own handler, for ours it calls nothing, because ours has no
        -- handler.
        local rang = 0
        foreign.OnClick = function() rang = rang + 1 end
        drawn.mouse.Click("AAA Foreign", "LeftButton", nil)
        T.eq(rang, 1, "the foreign source's own click worked")
        drawn.mouse.Click(panelNs.Sources.Name("gold"), "LeftButton", nil)
        T.eq(rang, 1, "on our cell there was nobody to call")

        -- And the same action is the first menu row, because the panel took
        -- its right button. Having taken it, we must give it back in one click.
        drawn.mouse.Click("AAA Foreign", "RightButton", nil)
        T.eq(opened.entries[1].kind, "own", "its own action is the first row")
        opened.entries[1] = opened.entries[1]
        T.eq(#opened.entries, #ours.entries + 1, "and added exactly one row")

        -- Choosing a menu row changes the settings and redraws the panel.
        drawn.mouse.Click("AAA Foreign", "RightButton", nil)
        for _, entry in ipairs(opened.entries) do
            if entry.kind == "hide" then
                settings.hidden = settings.hidden or {}
                settings.hidden["AAA Foreign"] = true
                handle:Apply()
            end
        end
        local afterHide = {}
        for _, cell in ipairs(drawn.cells) do afterHide[cell.name] = true end
        T.eq(afterHide["AAA Foreign"], nil, "the hidden cell left the strip")
        settings.hidden["AAA Foreign"] = nil
        handle:Apply()

        --==================================================================
        -- The screen space: three different numbers instead of one.
        --==================================================================

        local report = panelNs.Check()
        T.ok(reported(report, "the panel is on") ~= nil, "report: the panel is on")
        T.ok(reported(report, "asked for 18") ~= nil, "report: how much was asked for")
        T.ok(reported(report, "applied 18") ~= nil, "report: how much was applied")
        T.ok(reported(report, "UIParent is exactly where") ~= nil,
            "report: UIParent stands where it was left")

        -- In combat the offset is deferred: it is the engine that forbids
        -- moving UIParent, not us. The report must call that waiting rather than "done".
        combat = true
        settings.height = 30
        handle:Apply()

        T.eq(topEdge(), -18, "in combat the screen did not move")
        report = panelNs.Check()
        T.ok(reported(report, "asked for 30") ~= nil, "report: a new amount was asked for")
        T.ok(reported(report, "applied 18") ~= nil, "report: the former amount is applied")
        T.ok(reported(report, "waiting for combat") ~= nil,
            "report: the edit is waiting for the end of combat")

        combat = false
        core.Events.Dispatch("PLAYER_REGEN_ENABLED")
        T.eq(topEdge(), -30, "after combat the offset was applied")
        report = panelNs.Check()
        T.ok(reported(report, "applied 30") ~= nil, "report: the new amount was applied")
        T.eq(reported(report, "waiting for combat"), nil,
            "and there is nothing left to wait for")

        -- A foreign addon moved UIParent after us. We do not write our own
        -- anchors over foreign ones silently -- the verification names the divergence.
        anchors[1] = { "TOPLEFT", nil, "TOPLEFT", 0, -100 }
        report = panelNs.Check()
        T.ok(reported(report, "not where the panel left it") ~= nil,
            "report: UIParent does not stand where it was left")

        -- A resolution change moves UIParent by itself. The strip height is
        -- the same, that is "we asked for as much" -- and without a forced
        -- recomputation the space would stay lost until the first settings edit.
        core.Events.Dispatch("DISPLAY_SIZE_CHANGED")
        T.eq(topEdge(), -30, "after the resolution change the offset was set again")
        T.eq(reported(panelNs.Check(), "not where the panel left it"), nil,
            "and there is no divergence any more")

        -- An engine refusal to protected code. The taint cannot be checked
        -- outside the client, but recognising our own refusal and naming the switch to the player can be.
        --
        -- The name here is "Darken" rather than the module folder name:
        -- outside the game the module files are read under the core name
        -- (tests/helpers.lua), and there is nowhere else for a name to come
        -- from here. Both recognition branches are checked above, on Layout.Blame itself, where the name arrives as an argument.
        local before = #said
        core.Events.Dispatch("ADDON_ACTION_BLOCKED", "Darken",
            "UIParent:SetPoint()")
        T.ok(#said > before, "the refusal was reported to the player")
        T.ok(reported(panelNs.Check(), "refused a protected action") ~= nil,
            "and it made it into the report")

        -- It is not said a second time: a chat line per refusal is no longer a
        -- warning but a nuisance.
        before = #said
        core.Events.Dispatch("ADDON_ACTION_BLOCKED", "Darken", "x")
        T.eq(#said, before, "it is not said a second time")

        -- A foreign refusal is not ours.
        core.Events.Dispatch("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "x")
        T.ok(reported(panelNs.Check(), "2 times") ~= nil,
            "a foreign refusal was not charged to us")

        -- Switching off restores the screen as it was.
        settings.enabled = false
        handle:Apply()
        T.eq(topEdge(), 0, "the screen space was given back")
        report = panelNs.Check()
        T.ok(reported(report, "the panel is off") ~= nil, "report: the panel is off")
        T.ok(reported(report, "applied 0") ~= nil, "report: nothing is taken")
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.UIParent = saved.UIParent
    _G.LibStub = saved.LibStub
    _G.InCombatLockdown = saved.InCombatLockdown
end

helpers.removeValidator()
