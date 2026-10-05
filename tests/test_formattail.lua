local helpers = require("helpers")

-- The tail of the number-formatting consolidation and the adoption of the label edge inset.
--
-- Two loose ends left over from the twelfth version of the contract.
--
-- The first. The number-formatting consolidation merged four places out of
-- five. The fifth -- the symmetric rounding in the info panel -- remained
-- because a plain "round to an integer" was not on the contract surface at
-- all: the panel shows the frame rate, the game returns 59.6, and the cell
-- says "60 fps". One remaining copy of a rule is no small thing: this
-- project has already found one piece of knowledge written twice five times,
-- and every time the second record looked harmless right up to the day the first was edited.
--
-- The second. Version 12 created the name edge in the spacing scale -- "how
-- far to push a label from the edge so it does not merge with the border" --
-- because this magnitude was written as four numbers in three subsystems (2
-- for the bar labels, 2 for the nameplate cast bar label, -1 for the level,
-- -1 for the stack counter on an aura icon). The name was created, and nobody asked for it.
--
-- What is checked here:
--
--   1. the rounding is visible from the contract and it is THE SAME function, not a lookalike;
--   2. there is one rounding, not two: "symmetric about zero" and "the half
--      moves away from zero" are one rule, and the percentage is computed by it too;
--   3. no copies of the rounding body are left anywhere -- a scan by a mark,
--      with the converse check that the mark IS in the core; the second
--      rounding rule (the half to the larger) is named out loud where it lives;
--   4. every adopting module declares the contract version it actually uses,
--      while an older module still registers;
--   5. the label edge inset is asked of the scale by all four of them;
--   6. the minus on two of the four is a side, not a different magnitude.

T.suite("number formatting tail: rounding and the label edge inset")

--- Read a whole file.
-- @param path string
-- @return string
local function read(path)
    local file = io.open(path, "r")
    if not file then error("could not open " .. path, 2) end
    local text = file:read("*a")
    file:close()
    return text
end

--- The core as the public layer sees it.
local function core()
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Skin/Draw.lua", ns)
    helpers.loadAddonFile("Core/Frames.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Combat.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/Format.lua", ns)
    helpers.loadAddonFile("Core/Media.lua", ns)
    helpers.loadAddonFile("Core/Api.lua", ns)

    local said = {}
    ns.Registry.report = function(text) said[#said + 1] = text end
    ns.Addon = {
        db = { profile = {}, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }

    return ns, said
end

--============================================================================
-- 1. The rounding is visible from the contract, and it is the same function
--============================================================================
--
-- By identity rather than by matching answers. A copy answers the same right
-- up to the day one of the two is edited -- and this whole work is an
-- analysis of how they get edited.

do
    local ns = core()
    local fmt = ns.Api:GetFormat()

    T.eq(type(fmt.Round), "function", "the rounding is handed outward")
    T.eq(fmt.Round, ns.Format.Round, "and it is the very core function")
    T.eq(ns.Api:GetFormat().Round, ns.Api:GetFormat().Round,
        "the door hands out the same one on every question")

    T.ok(ns.Api.API_VERSION >= 13, "the rounding was handed out by version thirteen")
    T.eq(ns.Api:Supports(13), true, "version thirteen is supported")
    T.eq(ns.Api:Supports(12), true, "and the twelfth is still accepted")
    T.eq(ns.Api.API_MIN_VERSION, 1, "the lower bound stayed at one")

    -- A snapshot of the whole surface: a name added by accident will demand a
    -- deliberate decision. Every one here is a promise forever.
    local surface = {}
    for key, value in pairs(fmt) do
        surface[#surface + 1] = key .. ":" .. type(value)
    end
    table.sort(surface)
    T.eq(table.concat(surface, ","),
        "Abbreviate:function,Percent:function,Round:function",
        "the number surface: " .. table.concat(surface, ","))

    -- A module of every accepted version gets the same door and the same
    -- answer: a name was added, nothing was removed.
    for version = ns.Api.API_MIN_VERSION, ns.Api.API_VERSION do
        local handle = ns.Api:RegisterModule({
            name = "rounder" .. version,
            api  = version,
        })
        T.ok(handle ~= nil, "a version " .. version .. " module is registered")
    end
    T.eq(ns.Api:GetFormat().Round, ns.Format.Round,
        "and after all the registrations the door still leads to the same place")
end

--============================================================================
-- 2. There is one rounding, not two
--============================================================================
--
-- "Symmetric about zero" and "the half moves away from zero" are not two
-- rules but one, named from two sides: the symmetry Round(-x) = -Round(x) IS
-- the requirement to move the half away from zero. So there is one name on
-- the surface. This is checked three ways at once: by the symmetry property,
-- by exact halves on both sides of zero, and by the percentage being
-- computed by this same rounding rather than its own.

do
    local ns = core()
    local fmt = ns.Api:GetFormat()

    -- Exact halves: the magnitude the two rules diverge on.
    T.eq(fmt.Round(0.5), 1, "the half moves away from zero upwards")
    T.eq(fmt.Round(-0.5), -1, "and downwards -- also away from zero")
    T.eq(fmt.Round(2.5), 3, "two and a half is three")
    T.eq(fmt.Round(-2.5), -3, "minus two and a half is minus three")
    T.eq(fmt.Round(1.5), 2, "one and a half is two")
    T.eq(fmt.Round(-1.5), -2, "minus one and a half is minus two")

    -- Not halves: the ordinary nearest.
    T.eq(fmt.Round(0), 0, "zero stays zero")
    T.eq(fmt.Round(0.4), 0, "less than a half goes down")
    T.eq(fmt.Round(0.6), 1, "more than a half goes up")
    T.eq(fmt.Round(-0.4), 0, "and the same with a minus")
    T.eq(fmt.Round(-0.6), -1, "and the same with a minus")
    T.eq(fmt.Round(59.6), 60, "the frame rate rounds to sixty")
    T.eq(fmt.Round(12), 12, "an integer stays itself")

    -- Symmetry as a property rather than as a list: it IS the meaning of the function.
    local SAMPLES = { 0, 0.1, 0.5, 0.9, 1, 1.5, 2.5, 3.5, 12.4, 59.6, 100.5,
        999.5, 1000000.5 }
    local broken = {}
    for i = 1, #SAMPLES do
        local n = SAMPLES[i]
        if fmt.Round(-n) ~= -fmt.Round(n) then
            broken[#broken + 1] = tostring(n)
        end
    end
    T.eq(#broken, 0, "the same magnitude with the other sign is computed the same way: "
        .. table.concat(broken, " | "))

    -- Garbage gives zero rather than a Lua error or nil: the rounding stands
    -- in a label that has no room for a missing answer.
    T.eq(fmt.Round(nil), 0, "nothing to round gives zero")
    T.eq(fmt.Round("garbage"), 0, "a string gives zero")
    T.eq(fmt.Round({}), 0, "a table gives zero")
    T.eq(fmt.Round(0 / 0), 0, "NaN gives zero")
    T.eq(fmt.Round(math.huge), 0, "infinity gives zero")
    T.eq(fmt.Round(-math.huge), 0, "and with the other sign too")
    T.eq(fmt.Round("12.6"), 13, "a numeric string is a number, as everywhere here")

    -- One rule serves both: a percentage is the same rounding of a fraction
    -- turned into hundredths. What is compared is not "similar" but equality over the whole set.
    local PAIRS = {
        { 1, 3 }, { 2, 3 }, { 1, 200 }, { 3, 200 }, { 5, 200 }, { 7, 8 },
        { -1, 8 }, { -1, 200 }, { 1, 1 }, { 0, 5 }, { 12437, 20000 },
    }
    local apart = {}
    for i = 1, #PAIRS do
        local c, m = PAIRS[i][1], PAIRS[i][2]
        if fmt.Percent(c, m) ~= fmt.Round(c / m * 100) then
            apart[#apart + 1] = c .. "/" .. m
        end
    end
    T.eq(#apart, 0, "the percentage is computed by the same rounding: "
        .. table.concat(apart, " | "))
end

--============================================================================
-- 3. No copies of the rounding body are left
--============================================================================
--
-- By the same means the five previous consolidations were proved: the mark of
-- the rule is searched for across every source taken from the TOC and must
-- be found nowhere but the core -- while in the core it must be found, or the
-- scan is green even when it has forgotten how to search.

do
    --- The core and subsystem files listed in Darken.toc.
    -- The list is taken from the same file the game loads them by: a file
    -- created tomorrow comes under the scan by itself.
    -- @return table an array of paths
    local function tocFiles()
        local out = {}
        for line in read("Darken.toc"):gmatch("[^\r\n]+") do
            local rel = line:match("^%s*((Core[\\/][%w_]+%.lua))%s*$")
                or line:match("^%s*((Modules[\\/][%w_]+%.lua))%s*$")
                or line:match("^%s*((Config[\\/][%w_]+%.lua))%s*$")
                or line:match("^%s*((Skin[\\/][%w_]+%.lua))%s*$")
            if rel then out[#out + 1] = (rel:gsub("\\", "/")) end
        end
        if #out == 0 then
            error("Darken.toc lists not a single file", 2)
        end
        return out
    end

    --- The text of a file without comment lines: the rule is searched for in
    -- the code rather than in the account of it. The comments in this addon
    -- are long and explain exactly the expressions that must not be in the
    -- code -- a scan over raw text would go red on its own explanations.
    -- @param path string
    -- @return string
    local function codeOf(path)
        local out = {}
        for line in read(path):gmatch("[^\r\n]+") do
            out[#out + 1] = (line:gsub("%-%-.*$", ""))
        end
        return table.concat(out, "\n")
    end

    local scanned = {}
    local files = tocFiles()
    for i = 1, #files do
        scanned[#scanned + 1] = { path = files[i], text = codeOf(files[i]) }
    end

    local folders = helpers.moduleFolders()
    T.ok(#folders >= 5, "the module folders were found: " .. #folders)
    for i = 1, #folders do
        local sources = helpers.moduleSources(folders[i])
        for j = 1, #sources do
            scanned[#scanned + 1] =
                { path = sources[j], text = codeOf(sources[j]) }
        end
    end
    T.ok(#scanned >= 60, "sources under the scan: " .. #scanned)

    -- The marks of symmetric rounding. The first is the body itself: the sign
    -- handling that distinguishes this rule from a plain math.floor(v + 0.5).
    -- The rest are the name a copy is created under: a copy is called round or
    -- Round, it never has a third name.
    local MARKS = {
        "-math.floor(-",
        "local function round",
        "local function Round",
        "local round =",
        "local Round =",
    }

    for m = 1, #MARKS do
        local mark = MARKS[m]
        local found = {}
        for i = 1, #scanned do
            if scanned[i].path ~= "Core/Format.lua"
                and scanned[i].text:find(mark, 1, true) then
                found[#found + 1] = scanned[i].path
            end
        end
        T.eq(#found, 0, "the rounding mark \"" .. mark
            .. "\" does not occur outside Core/Format.lua: "
            .. table.concat(found, " | "))
    end

    -- The other side: the body must be where it belongs. A scan that finds
    -- nothing anywhere is green even when it has forgotten how to search.
    local home = codeOf("Core/Format.lua")
    T.ok(home:find("-math.floor(-", 1, true) ~= nil,
        "in Core/Format.lua the rounding body is in place -- the scan can search")
    T.ok(home:find("function Format.Round", 1, true) ~= nil,
        "and it is named there too")

    -- The second rounding rule is "the half to the larger number",
    -- math.floor(v + 0.5). It exists in the addon, it is different, and it is
    -- not handed outward. Every place of it is named here together with the
    -- reason: a list with no reasons would be the same warehouse of copies, only written into a check.
    local HALF_UP = {
        ["Features/Auras/Icon.lua"] =
            "the digit height from the icon side: the magnitude is non-negative, and both "
            .. "rules agree on it. This is part of the rule \"the digit grows "
            .. "with the icon\", whose own consolidation is still ahead -- the copy "
            .. "is kept from diverging by tests/test_worldfixes.lua",
        ["Features/NamePlates/Plate.lua"] =
            "the same digit height rule and the same pair compared by the check",
        ["Core/Defaults.lua"] =
            "moving the darkening onto the new scale (migration 6 -> 7): the "
            .. "slider value is clamped to 0..100 right before the multiplication, that is "
            .. "non-negative, and both rounding rules agree on it. "
            .. "Calling ns.Format.Round from here is not allowed: a migration must "
            .. "work on raw SavedVariables alone, without the core -- "
            .. "and that is how it is checked (tests/test_darkscale.lua)",
        ["Features/Auras/Rules.lua"] =
            "the icon size under a rule: the product of a side and a factor, "
            .. "both magnitudes strictly positive",
    }

    local silent = {}
    local seen = {}
    for i = 1, #scanned do
        if scanned[i].path ~= "Core/Format.lua"
            and scanned[i].text:find("+ 0.5", 1, true) then
            seen[scanned[i].path] = true
            if HALF_UP[scanned[i].path] == nil then
                silent[#silent + 1] = scanned[i].path
            end
        end
    end
    table.sort(silent)
    T.eq(#silent, 0, "every rounding outside the core is stated out loud: "
        .. table.concat(silent, " | "))

    -- An entry that outlived its reason is a check silently removed.
    local stale = {}
    for path in pairs(HALF_UP) do
        if not seen[path] then stale[#stale + 1] = path end
    end
    table.sort(stale)
    T.eq(#stale, 0, "no entry outlived its reason: "
        .. table.concat(stale, " | "))

    -- The third number-formatting rule is "write it whole": the fraction is
    -- truncated towards zero and the sign is moved outside the "%d". Both
    -- halves are decisions rather than the only possible spelling: truncation
    -- differs from rounding on every fractional magnitude, and a sign inside "%d" would give "-0".
    --
    -- The rule lives in the core, as the last line of the abbreviation, and
    -- the subsystems must call it through ns.WholeNumber. The scan looks for
    -- the spelling itself -- it is exactly what none of the eleven marks of
    -- the previous consolidations caught, and precisely why the bar label kept
    -- a second body of its own: it agreed with the core one on every number and would have diverged silently.
    local WHOLE = 'string.format("%d", math.floor('
    local WHOLE_ELSEWHERE = {
        ["Features/ItemLevel/Level.lua"] =
            "the item level number: the module lives in its own folder, while the "
            .. "contract surface has no \"write this whole\" name at all -- there is Round, "
            .. "Abbreviate and Percent. The magnitudes there are strictly positive "
            .. "item levels, and this spelling cannot diverge from the core rule "
            .. "on any value",
    }

    local wholeSilent, wholeSeen = {}, {}
    for i = 1, #scanned do
        if scanned[i].path ~= "Core/Format.lua"
            and scanned[i].text:find(WHOLE, 1, true) then
            wholeSeen[scanned[i].path] = true
            if WHOLE_ELSEWHERE[scanned[i].path] == nil then
                wholeSilent[#wholeSilent + 1] = scanned[i].path
            end
        end
    end
    table.sort(wholeSilent)
    T.eq(#wholeSilent, 0,
        "every \"write it whole\" spelling outside the core is stated out loud: "
        .. table.concat(wholeSilent, " | "))

    local wholeStale = {}
    for path in pairs(WHOLE_ELSEWHERE) do
        if not wholeSeen[path] then wholeStale[#wholeStale + 1] = path end
    end
    table.sort(wholeStale)
    T.eq(#wholeStale, 0, "no whole-number entry outlived its reason: "
        .. table.concat(wholeStale, " | "))

    -- The other side: the rule must be in the core and must be named by the
    -- name the subsystems call it by.
    T.ok(home:find(WHOLE, 1, true) ~= nil,
        "in Core/Format.lua the whole-number spelling is in place -- the scan can search")
    T.ok(home:find("ns.WholeNumber", 1, true) ~= nil,
        "and it has a name its neighbours in the core call it by")
end

--============================================================================
-- 4. Whoever uses something declares it
--============================================================================

do
    local DECLARED = {
        ["Features/InfoPanel"] = 13,
        ["Features/NamePlates"] = 12,
        ["Features/Auras"] = 12,
    }

    -- What is compared is "no older than" rather than "exactly this much". A
    -- module declares the version it needs in full, and what it needs may
    -- grow later: a snapshot of the exact number would go red on every growth
    -- of the contract while protecting nothing.
    for folder, least in pairs(DECLARED) do
        local text = read(folder .. "/" .. helpers.moduleEntry(folder))
        local declared = tonumber(text:match("\nlocal API%s*=%s*(%d+)"))
        T.ok(declared ~= nil and declared >= least,
            folder .. " declares a contract version no older than " .. least
            .. ": " .. tostring(declared))
    end

    -- The panel also refuses to assemble on a core without the rounding: a
    -- version 12 core hands out a table with no Round, and a panel that took
    -- it would fail not while reading the file but a second after entering the
    -- world -- on the first frame-rate draw and without a single word about the reason.
    local saved = _G.Darken
    _G.Darken = { GetFormat = function()
        return { Abbreviate = function() end, Percent = function() end }
    end }
    local old = helpers.newNamespace()
    helpers.loadAddonFile("Features/InfoPanel/Format.lua", old)
    T.eq(old.Format, nil, "on a core with no rounding the panel does not come up at all")
    _G.Darken = saved

    -- And it assembles on a core that has it, taking that very function.
    local fmt, restore = helpers.installFormat()
    local panel = helpers.newNamespace()
    helpers.loadAddonFile("Features/InfoPanel/Format.lua", panel)
    restore()

    T.eq(type(panel.Format), "table", "on the current core the panel assembled")
    T.eq(panel.Format.Numbers.Round, fmt.Round,
        "and it rounds with the same function as the core")
    T.eq(panel.Format.Fps(59.6), "60 fps", "the frame rate is rounded")
    T.eq(panel.Format.Fps(-0.5), "-1 fps",
        "and rounded symmetrically rather than to the larger")
    T.eq(panel.Format.Fps("garbage"), panel.Format.NONE,
        "while the input filtering stayed the panel's decision")

    -- A module older than the declared version still registers: nothing was
    -- removed and nothing renamed.
    local ns = core()
    local handle = ns.Api:RegisterModule({ name = "oldtimer", api = 1 })
    T.ok(handle ~= nil, "a version 1 module registers on a version 13 core")
    T.eq(type(ns.Api:GetFormat().Abbreviate), "function",
        "and gets the same door as everyone")
end

--============================================================================
-- 5. The label edge inset is asked of the scale
--============================================================================
--
-- Four labels at an edge, three subsystems, one magnitude. What is checked is
-- not that the number equals two but that it comes from the scale: a
-- subsystem answer is compared with the core answer, and a fake scale with a
-- different number moves the label along with it.

local skinNs = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", skinNs)
local EDGE = skinNs.Skin.Metrics.edge

do
    T.eq(type(EDGE), "number", "the scale has the label edge inset")
    T.ok(EDGE > skinNs.Skin.Metrics.hair, "it is larger than the border thickness")
    T.ok(EDGE < skinNs.Skin.Metrics.rail, "and smaller than the left rail")
end

--- A fake skin with a given scale.
-- @param edge number
-- @return table
local function skinWith(edge)
    return {
        Metrics = function()
            local out = {}
            for key, value in pairs(skinNs.Skin.Metrics) do out[key] = value end
            out.edge = edge
            return out
        end,
        Backdrop = function() return true end,
        Outline  = function() return true end,
        Color    = function() return 0.7, 0.5, 0.7 end,
    }
end

-- 5a. The bar labels (Modules/Texts.lua)
do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Combat.lua", ns)

    local savedLibStub = LibStub
    LibStub = function() return nil end
    helpers.loadAddonFile("Modules/Fonts.lua", ns)
    helpers.loadAddonFile("Modules/UnitFrames.lua", ns)
    helpers.loadAddonFile("Core/Format.lua", ns)
    helpers.loadAddonFile("Modules/Texts.lua", ns)
    LibStub = savedLibStub

    local _, _, left = ns.Texts.Anchor("left")
    local _, _, right = ns.Texts.Anchor("right")

    T.eq(left, ns.Skin.Metrics.edge, "the label on the left is pushed by the scale inset")
    T.eq(right, -ns.Skin.Metrics.edge, "and on the right by the same with a minus")
    T.eq(left, -right, "that is they share one number, and the sign is the side")

    -- Editing the scale moves the label: the magnitude is asked for on the
    -- spot rather than remembered when the file is read.
    ns.Skin.Metrics.edge = 7
    local _, _, moved = ns.Texts.Anchor("left")
    T.eq(moved, 7, "the label moves along with the scale")
    ns.Skin.Metrics.edge = EDGE

    local _, _, middle = ns.Texts.Anchor("center")
    T.eq(middle, 0, "in the centre there is no inset at all")
end

--- A fake font string that remembers its anchors.
local function fontString()
    local text = { path = "font", size = 0, flags = "", points = {} }
    function text:SetText() end
    function text:SetJustifyH() end
    function text:SetHeight(h) self.height = h end
    function text:ClearAllPoints() self.points = {} end
    function text:SetPoint(point, _, relative, x, y)
        self.points[#self.points + 1] =
            { point = point, relative = relative, x = x, y = y }
    end
    function text:GetFont() return self.path, self.size, self.flags end
    function text:SetFont(path, size, flags)
        self.path, self.size, self.flags = path, size, flags
    end
    return text
end

--- The anchor of a label by point name.
-- @param text table
-- @param point string
-- @return table|nil
local function pointOf(text, point)
    for i = 1, #text.points do
        if text.points[i].point == point then return text.points[i] end
    end
    return nil
end

--- A fake frame: the little that the layout needs.
local function frameObject(kind)
    local frame = { kind = kind, width = 0, height = 0, shown = false }
    function frame:Hide() self.shown = false end
    function frame:Show() self.shown = true end
    function frame:SetSize(w, h) self.width, self.height = w, h end
    function frame:GetWidth() return self.width end
    function frame:SetScale(v) self.scale = v end
    function frame:SetPoint() end
    function frame:ClearAllPoints() end
    function frame:SetAllPoints() end
    function frame:SetAlpha() end
    function frame:CreateTexture()
        return { SetAllPoints = function() end, SetPoint = function() end,
            SetTexCoord = function() end, SetTexture = function() end }
    end
    function frame:CreateFontString() return fontString() end
    function frame:SetMinMaxValues() end
    function frame:SetValue() end
    function frame:SetStatusBarTexture() end
    function frame:SetScript() end
    function frame:SetDrawEdge() end
    function frame:SetHideCountdownNumbers() end
    function frame:SetCooldown() end
    function frame:Clear() end
    return frame
end

-- 5b. Nameplates: the level, the cast bar label and the stack counter
do
    local platesNs = helpers.newNamespace()
    local _, restore = helpers.installCore()
    helpers.loadModule("Features/NamePlates", platesNs,
        { withRegistration = false })
    restore()

    local Plate = platesNs.Plate

    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }
    _G.CreateFrame = function(kind) return frameObject(kind) end
    _G.UIParent = frameObject("Frame")

    T.eq(Plate.Edge(skinWith(EDGE)), EDGE, "the nameplates take the inset from the scale")
    T.eq(Plate.Edge(skinWith(7)), 7, "and move along with it")
    T.eq(Plate.Edge(nil), 2, "with no skin they answer for themselves")

    for _, value in ipairs({ EDGE, 7 }) do
        local skin = skinWith(value)
        local frame = Plate.Build(skin)

        Plate.Layout(frame, nil, 110, 10, 1, 2, Plate.Edge(skin))
        local level = pointOf(frame.levelText, "BOTTOMRIGHT")
        T.ok(level ~= nil, "the level is anchored to the bottom right")
        T.eq(level.x, -value, "and pushed from the right edge by the scale inset")

        Plate.LayoutExtras(frame, skin, 110, 10, 2, 8, 20, 1)

        local label = frame.cast.label
        T.eq(pointOf(label, "LEFT").x, value,
            "the cast bar label is pushed from the left edge by the same inset")
        T.eq(pointOf(label, "RIGHT").x, -value, "and from the right by the same")

        local count = pointOf(frame.auras[1].count, "TOPRIGHT")
        T.ok(count ~= nil, "the stack counter is anchored to the top right")
        T.eq(count.x, -value, "and moved inward horizontally by the same inset")
        T.eq(count.y, -value, "and vertically by the same")
    end

    _G.CreateFrame = saved.CreateFrame
    _G.UIParent = saved.UIParent
end

-- 5c. Compact auras: the time and the stacks on an icon
do
    local aurasNs = helpers.newNamespace()
    local _, restore = helpers.installCore()
    helpers.loadModule("Features/Auras", aurasNs, { withRegistration = false })
    restore()

    local Icon = aurasNs.Icon

    T.eq(Icon.Edge(skinWith(EDGE)), EDGE, "the compact auras take the inset from the scale")
    T.eq(Icon.Edge(skinWith(7)), 7, "and move along with it")
    T.eq(Icon.Edge(nil), 2, "with no skin they answer for themselves")

    for _, value in ipairs({ EDGE, 7 }) do
        local frame = frameObject("Frame")
        frame.timeText = fontString()
        frame.countText = fontString()

        Icon.Dress(frame, 24, nil, value)

        local time = pointOf(frame.timeText, "BOTTOM")
        T.ok(time ~= nil, "the time is anchored to the bottom of the icon")
        T.eq(time.y, value, "and lifted from the bottom edge by the scale inset")

        local count = pointOf(frame.countText, "TOPRIGHT")
        T.ok(count ~= nil, "the stacks are anchored to the top right")
        T.eq(count.x, -value, "and moved inward horizontally")
        T.eq(count.y, -value, "and vertically by the same inset")

        T.eq(math.abs(time.y), math.abs(count.y),
            "both labels on one icon are pushed equally")
    end
end

--============================================================================
-- 6. The minus is a side, not a different magnitude
--============================================================================
--
-- The main question of the adoption: two of the four numbers were negative
-- (-1 for the level and -1 for the stack counter), and they can be replaced
-- by the inset only by establishing that the sign means a side. That is
-- established here as a property: one and the same subsystem writes one and
-- the same magnitude with both signs, and exactly the sign differs between
-- them, not the number. Were the minus a different magnitude, it would not
-- change along with the positive one when the scale is edited -- and it does (section 5 runs both scales in a row).

do
    -- The bar label: one function, one magnitude, both signs.
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Combat.lua", ns)

    local savedLibStub = LibStub
    LibStub = function() return nil end
    helpers.loadAddonFile("Modules/Fonts.lua", ns)
    helpers.loadAddonFile("Modules/UnitFrames.lua", ns)
    helpers.loadAddonFile("Core/Format.lua", ns)
    helpers.loadAddonFile("Modules/Texts.lua", ns)
    LibStub = savedLibStub

    local _, _, left = ns.Texts.Anchor("left")
    local _, _, right = ns.Texts.Anchor("right")
    T.eq(math.abs(left), math.abs(right),
        "the left and right edges share one number, only the sign differs")

    -- And none of the four adopters writes the inset as a number. What is
    -- searched for is the label anchoring itself rather than the string
    -- "edge": an inset written as a number is exactly what this whole work moves away from.
    local ADOPTED = {
        "Modules/Texts.lua",
        "Features/NamePlates/Plate.lua",
        "Features/Auras/Icon.lua",
    }
    local PATTERNS = {
        'SetPoint%("%u+", %w+, "%u+", (%-?%d+), %-?[%w_%.%s%+]+%)',
        'SetPoint%("%u+", %w+, "%u+", %-?[%w_%.%s%+]+, (%-?%d+)%)',
    }
    local literals = {}
    for i = 1, #ADOPTED do
        local text = (read(ADOPTED[i]):gsub("%s+", " "))
        for p = 1, #PATTERNS do
            for number in text:gmatch(PATTERNS[p]) do
                if tonumber(number) ~= 0 then
                    literals[#literals + 1] = ADOPTED[i] .. ": " .. number
                end
            end
        end
    end
    T.eq(#literals, 0, "the label inset is nowhere written as a number: "
        .. table.concat(literals, " | "))
end
