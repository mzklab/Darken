local helpers = require("helpers")

-- One family: what the addon draws over the world.
--
-- The unit frames, the action bars, the cast bars, the texts on the bars, the
-- nameplates, the compact auras, the item level numbers, the info panel's bars
-- and the pet feeding plate were written separately, by one and the same
-- contract, and there was nobody to compare them against each other. The
-- predictable result is a look whose parts are sensible separately and are no
-- kin beside one another: one and the same number is written in two ways in two
-- places on the screen, the digit on an aura's icon stands in two different
-- corners, a plate over the world is painted like a window.
--
-- What is checked here are properties rather than numbers we chose:
--
--   1. a large number is shortened by one rule everywhere;
--   2. the digit on an aura's icon stands in one and the same corner for both
--      who draw it;
--   3. the surface of the chrome over the world is one pair of palette names for all three;
--   4. a font category a subsystem names is declared by the core;
--   5. an inset's name a subsystem asks the scale for exists in the scale.
--
-- Not one check below names a number, a colour or a corner we chose:
-- everywhere two subsystems are compared against each other, or a subsystem against the core.

T.suite("the world family: one look over the landscape")

--============================================================================
-- The sources: the list of files comes from the TOC, as everywhere in this set
--============================================================================

-- The core's subsystems that draw over the world. The list is taken from the
-- core's TOC rather than rewritten here: a file added tomorrow is obliged to
-- get into the check by itself.
local function coreModuleFiles()
    local handle = io.open("Darken.toc", "r")
    if not handle then error("Darken.toc did not open", 2) end

    local out = {}
    for line in handle:lines() do
        local rel = line:match("^%s*(Modules[\\/][%w_]+%.lua)%s*$")
        if rel then out[#out + 1] = (rel:gsub("\\", "/")) end
    end
    handle:close()

    if #out == 0 then
        error("not one subsystem is enumerated in Darken.toc", 2)
    end
    return out
end

--- A file's contents as one line, with the newlines reduced to spaces.
-- The styling calls are wrapped at eighty characters, and looking for them line
-- by line would mean not finding exactly half of them.
-- @param path string
-- @return string|nil
local function flatten(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("%s+", " "))
end

-- The folders of the modules that draw over the world. The modules' windows
-- are judged by the neighbouring set (tests/test_modulefamily.lua); here it is the world alone.
local WORLD_FOLDERS = {
    "Features/Auras",
    "Features/InfoPanel",
    "Features/ItemLevel",
    "Features/NamePlates",
}

--- All the family's sources: the core's subsystems plus the world modules.
-- @return table an array of { path = the path, text = the joined text }
local function worldSources()
    local out = {}

    local core = coreModuleFiles()
    for i = 1, #core do
        local text = flatten(core[i])
        if text then out[#out + 1] = { path = core[i], text = text } end
    end

    for i = 1, #WORLD_FOLDERS do
        local sources = helpers.moduleSources(WORLD_FOLDERS[i])
        for j = 1, #sources do
            local text = flatten(sources[j])
            if text then out[#out + 1] = { path = sources[j], text = text } end
        end
    end
    return out
end

local SOURCES = worldSources()
T.ok(#SOURCES >= 30, "the world family's sources were read: " .. #SOURCES)

--- One file's text by path.
-- @param path string
-- @return string
local function sourceOf(path)
    for i = 1, #SOURCES do
        if SOURCES[i].path == path then return SOURCES[i].text end
    end
    error("the source was not read: " .. path, 2)
end

--============================================================================
-- 1. A large number is shortened by one rule
--============================================================================
--
-- A health bar that wrote "12.4k" and the panel cell beneath it that wrote
-- "12k" are exactly the defect the set is written for: two numbers of one
-- quantity, typed in two ways on one screen. What is compared here are not
-- strings we chose but the two answers against each other.
--
-- The door between them now exists: the rule lives in the core
-- (Core/Format.lua, Darken:GetFormat, contract 12), both sides call it, and no
-- copies are left — that is checked by tests/test_formatadopt.lua by the
-- identity of the functions and a scan of the sources. What is left here is the
-- comparison of the answers: it judges what the player sees and will survive any rearrangement of who asks whom.

do
    local core = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", core)
    helpers.loadAddonFile("Core/Compat.lua", core)
    helpers.loadAddonFile("Core/Locale.lua", core)
    helpers.loadAddonFile("Core/Registry.lua", core)
    helpers.loadAddonFile("Core/Events.lua", core)
    helpers.loadAddonFile("Core/Combat.lua", core)

    local savedLibStub = LibStub
    LibStub = function() return nil end
    helpers.loadAddonFile("Modules/Fonts.lua", core)
    helpers.loadAddonFile("Modules/UnitFrames.lua", core)
    helpers.loadAddonFile("Core/Format.lua", core)
    helpers.loadAddonFile("Modules/Texts.lua", core)
    LibStub = savedLibStub

    local panel = helpers.newNamespace()
    local _, restoreDoor = helpers.installFormat()
    helpers.loadAddonFile("Features/InfoPanel/Format.lua", panel)
    restoreDoor()

    local bars  = core.Texts.Abbreviate
    local cells = panel.Format.Short

    T.ok(type(bars) == "function" and type(cells) == "function",
        "both shortenings are in place")

    -- The quantities are taken at the edges rather than in the middles: the
    -- thresholds break one unit away from themselves. Fractional values
    -- deliberately do not get here — integers stand on the bar and in the cell,
    -- while the rounding of fractions is each function's own and does not catch the player's eye.
    local SAMPLES = {
        0, 1, 42, 999, 1000, 1001, 1500, 9999, 10000, 12400, 15000,
        99999, 999499, 999500, 999999, 1000000, 2500000,
        -1, -1500, -12400, -2500000,
    }

    local same = 0
    for i = 1, #SAMPLES do
        local n = SAMPLES[i]
        T.eq(cells(n), bars(n),
            "the panel and the bar write " .. tostring(n) .. " identically")
        if cells(n) == bars(n) then same = same + 1 end
    end
    T.eq(same, #SAMPLES, "not one quantity diverged")

    -- Separately, what the correction at the million threshold is for: without
    -- it an almost-million is written with four digits in thousands. What is
    -- compared is not a string but that both functions chose one and the same unit.
    T.ok(cells(999999):find("m", 1, true) ~= nil,
        "an almost-million is written in millions in the panel")
    T.ok(bars(999999):find("m", 1, true) ~= nil,
        "and on the bar too")

    -- The panel's dash is a rule of its own and there is nothing to reconcile
    -- it with: on the bar the game's native label stands instead of a number rather than a dash.
    T.eq(cells(nil), panel.Format.NONE, "the panel answers a non-number with a dash")
    T.eq(bars(nil), nil, "the bar does not answer a non-number at all")
end

--============================================================================
-- 2. The digit on an aura's icon: one corner for both
--============================================================================
--
-- An aura's icon is drawn by two: the compact auras (Features/Auras/Icon.lua)
-- and the nameplates (Features/NamePlates/Plate.lua). The number of stacks on
-- a square spell icon is one and the same thing, and it is obliged to stand in
-- one corner. One's anchor is compared against the other's rather than against a corner we chose.

do
    local PATTERN =
        'count[%w]*:SetPoint%("(%u+)", %w+, "(%u+)", (%-?[%w_]+), (%-?[%w_]+)%)'

    local auras = sourceOf("Features/Auras/Icon.lua")
    local plate = sourceOf("Features/NamePlates/Plate.lua")

    local ap, ar, ax, ay = auras:match(PATTERN)
    local pp, pr, px, py = plate:match(PATTERN)

    T.ok(ap ~= nil, "the compact auras' counter anchor was found")
    T.ok(pp ~= nil, "the nameplate auras' counter anchor was found")

    T.eq(pp, ap, "the counter is anchored by one and the same point")
    T.eq(pr, ar, "and to one and the same corner of the icon")

    -- Neither of them writes the inset as a number any more: both sides take it
    -- out of the styling's scale (Metrics.edge, contract version 12). Two
    -- literals used to be compared against each other here — a comparison that
    -- stays silent while the copies match and goes red the day after one of the
    -- two is edited. Now the source is compared: a name rather than a number.
    T.eq(tonumber(ax), nil, "the compact auras do not write the inset as a number")
    T.eq(tonumber(ay), nil, "neither horizontally nor vertically")
    T.eq(tonumber(px), nil, "and the nameplate's auras do not write it either")
    T.eq(tonumber(py), nil, "along neither axis")

    -- Separately: the inset takes the label INSIDE the icon rather than
    -- outside. The corner is the top right, so inside means left and down, that
    -- is, both numbers carry a minus. A label that stuck out past the edge lies
    -- over a neighbouring icon at any tight gap.
    T.eq(ax:sub(1, 1), "-", "the compact auras' counter is taken inside the icon")
    T.eq(ay:sub(1, 1), "-", "along both axes")
    T.eq(px:sub(1, 1), "-", "and the nameplate auras' counter goes inside too")
    T.eq(py:sub(1, 1), "-", "along both axes")

    -- And the answer is one for both: both helpers return that very quantity of
    -- the scale the core returns. What is compared is not the coincidence of two
    -- numbers but that the number is one between them and taken from the core.
    local skinNs = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", skinNs)

    local stub = { Metrics = function()
        local out = {}
        for key, value in pairs(skinNs.Skin.Metrics) do out[key] = value end
        return out
    end }

    local auraNs = helpers.newNamespace()
    helpers.loadAddonFile("Features/Auras/Icon.lua", auraNs)
    local plateNs = helpers.newNamespace()
    helpers.loadAddonFile("Features/NamePlates/Plate.lua", plateNs)

    T.eq(type(auraNs.Icon.Edge), "function", "the compact auras ask for the inset")
    T.eq(type(plateNs.Plate.Edge), "function", "and the nameplates ask too")
    T.eq(auraNs.Icon.Edge(stub), skinNs.Skin.Metrics.edge,
        "the compact auras take the inset out of the core's scale")
    T.eq(plateNs.Plate.Edge(stub), auraNs.Icon.Edge(stub),
        "and the nameplates take the same quantity")

    -- The typeface. The digit on an icon is a number, and the font object is one for both.
    local FONT = 'CreateFontString%(nil, "OVERLAY", "(%w+)"%)'
    local auraFonts, plateFonts = {}, {}
    for name in auras:gmatch(FONT) do auraFonts[name] = true end
    for name in plate:gmatch(FONT) do plateFonts[name] = true end
    T.ok(auraFonts.NumberFontNormal, "the compact auras write the number in the digit font")
    T.ok(plateFonts.NumberFontNormal, "and so do the nameplate's auras")
end

--============================================================================
-- 3. The chrome over the world: one pair of palette names
--============================================================================
--
-- The rule was written down aloud by the analysis of the windows already: the
-- chrome over the world is "ink", a window is "panel". Over the world the addon
-- draws three surfaces of its own: a nameplate, the info panel's bar and the
-- feeding plate. They are compared against each other rather than against a colour name we chose.

do
    local PAIR = 'skin%.Backdrop%(%w+, "(%w+)", "(%w+)"%)'

    --- The first surface the file paints.
    -- @param path string
    -- @return string, string the names of the fill and of the border
    local function surfaceOf(path)
        local background, border = sourceOf(path):match(PAIR)
        T.ok(background ~= nil, path .. ": the surface's fill was found")
        return background, border
    end

    local plateBg, plateLine = surfaceOf("Features/NamePlates/Plate.lua")
    local panelBg, panelLine = surfaceOf("Features/InfoPanel/Panel.lua")

    T.eq(panelBg, plateBg, "the panel's bar is painted with the same as the nameplate")
    T.eq(panelLine, plateLine, "the panel bar's border is the same")

    -- The names are obliged to be palette names rather than an invention: the
    -- contract does not paint an unfamiliar name at all, and on the screen that looks like a vanished fill.
    local skinNs = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", skinNs)
    T.ok(skinNs.Skin.Palette[plateBg] ~= nil, "the chrome's fill exists in the palette")
    T.ok(skinNs.Skin.Palette[plateLine] ~= nil, "the chrome's border exists in the palette")

    -- And it differs from a window's surface: a panel cell's menu is a small
    -- window, and it is painted unlike the bar beneath it. One file, two
    -- surfaces, and the difference between them is the rule's point.
    local panelText = sourceOf("Features/InfoPanel/Panel.lua")
    local windowBg = nil
    for background in panelText:gmatch(PAIR) do
        if background ~= panelBg then windowBg = background end
    end
    T.ok(windowBg ~= nil and windowBg ~= panelBg,
        "a cell's menu is painted unlike the bar beneath it")
    T.ok(skinNs.Skin.Palette[windowBg] ~= nil, "and its fill comes out of the palette too")
end

--============================================================================
-- 4. A font category is declared by the core
--============================================================================
--
-- A category the core does not hold does nothing and reports nothing:
-- ApplyFont simply answers "no" while the label stays on the template's font.
-- On the screen that looks like "the font setting does not work right here",
-- and such a thing cannot be found by eye — one has to know where to look.

do
    local fonts = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", fonts)
    helpers.loadAddonFile("Core/Compat.lua", fonts)
    helpers.loadAddonFile("Core/Locale.lua", fonts)
    helpers.loadAddonFile("Core/Registry.lua", fonts)
    helpers.loadAddonFile("Core/Events.lua", fonts)
    helpers.loadAddonFile("Core/Combat.lua", fonts)

    local savedLibStub = LibStub
    LibStub = function() return nil end
    helpers.loadAddonFile("Modules/Fonts.lua", fonts)
    LibStub = savedLibStub

    local known = {}
    local count = 0
    for i = 1, #fonts.Fonts.CATEGORIES do
        known[fonts.Fonts.CATEGORIES[i].key] = true
        count = count + 1
    end
    T.ok(count >= 5, "the core's categories were read: " .. count)

    -- A category's name is declared as a constant at the top of the file: that
    -- way it is visible from one place, and that way this check finds it.
    local named = 0
    for i = 1, #SOURCES do
        for constant, key in SOURCES[i].text:gmatch('local ([%u_]+) = "(%w+)"') do
            if constant:find("FONT", 1, true) then
                named = named + 1
                T.ok(known[key] ~= nil,
                    SOURCES[i].path .. ": the category \"" .. key
                        .. "\" is declared by the core")
            end
        end
    end
    T.ok(named >= 5, "the categories named by the subsystems were found: " .. named)
end

--============================================================================
-- 5. An inset's name exists in the scale
--============================================================================
--
-- The same rule the modules' windows live by (tests/test_modulefamily.lua),
-- extended here to the core's own subsystems. A name that does not exist in the
-- scale reads as an inset while a nil arrives, and on the screen that simply
-- looks like "the elements float".

do
    local skinNs = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", skinNs)

    local asked = 0
    for i = 1, #SOURCES do
        for name in SOURCES[i].text:gmatch("metrics%.(%w+)") do
            asked = asked + 1
            T.ok(skinNs.Skin.Metrics[name] ~= nil,
                SOURCES[i].path .. ": the inset \"" .. name .. "\" exists in the scale")
        end
    end
    T.ok(asked >= 5, "the inset names the family asked for: " .. asked)
end
