local helpers = require("helpers")

-- The darkness: what one application costs.
--
-- What is checked is not the colour's correctness — that is the neighbouring
-- sets' business — but the amount of work. The author reported that dragging
-- the darkening slider hangs the game entirely, and the cause was measured
-- rather than guessed: the walk of the interface and the writing of the colour
-- were one piece of work, an AceGUI slider calls the handler at every division of a drag, and the game is single-threaded.
--
-- The measurement on a stand-in interface of two hundred windows (2601 frames,
-- 20800 regions) before the edit: 302,420 protected calls, 2600 approaches to
-- GetRegions and 2601 to GetChildren — per division of the slider. After the
-- edit: 20,801 protected calls, zero approaches to the tree, and every
-- division that arrived in one frame merges into one application.
--
-- So what stands here are limits rather than numbers of "as it is now". An
-- edit that makes the pass dearer again will fail this set rather than reach the client.

T.suite("the darkness: an application's cost")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)

local Darkness = ns.Darkness

-- The counters of work. pcall is replaced globally: both the subsystem and the
-- styling layer call it by its global name, so everything is counted.
local counters = { pcall = 0, regions = 0, children = 0, writes = 0 }
local realpcall = pcall

local function countingPcall(...)
    counters.pcall = counters.pcall + 1
    return realpcall(...)
end

local function reset()
    counters.pcall, counters.regions = 0, 0
    counters.children, counters.writes = 0, 0
end

-- How many times a colour was written to each texture during the current
-- stretch. Not one must get it twice per application.
local written = {}

--- A stand-in region of the interface.
local function newRegion(opts)
    local region = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return opts.kind or "Texture" end,
        GetDrawLayer = function() return opts.layer or "ARTWORK" end,
    }
    if opts.name then region.GetName = function() return opts.name end end
    if opts.texture ~= nil then
        region.GetTexture = function() return opts.texture end
    end
    function region:GetVertexColor() return self.r, self.g, self.b, self.a end
    function region:SetVertexColor(cr, cg, cb, ca)
        counters.writes = counters.writes + 1
        written[self] = (written[self] or 0) + 1
        self.r, self.g, self.b = cr, cg, cb
        if ca ~= nil then self.a = ca end
    end
    return region
end

--- A stand-in frame: regions and children, counting the approaches to the tree.
local function newFrame(name, regions, children)
    local frame = {
        GetObjectType = function() return "Frame" end,
        GetRegions = function()
            counters.regions = counters.regions + 1
            return unpack(regions or {})
        end,
        GetChildren = function()
            counters.children = counters.children + 1
            return unpack(children or {})
        end,
    }
    if name then frame.GetName = function() return name end end
    return frame
end

-- A stand-in interface of a known size. The numbers are small: what is checked
-- is the ratio of work to size rather than the speed in itself.
local WINDOWS, FANOUT, DEPTH, CHROME = 12, 2, 3, 4

local chromeCount = 0

local function buildWindow(name, depth)
    local regions = {}
    for i = 1, CHROME do
        regions[i] = newRegion({
            texture = "Interface\\DialogFrame\\UI-DialogBox-Border" .. i })
        chromeCount = chromeCount + 1
    end
    -- Contents in every frame: the plan is obliged not to take them.
    regions[CHROME + 1] = newRegion({ texture = 132863,
        name = "MockPortrait" })
    regions[CHROME + 2] = newRegion({ kind = "FontString", layer = "OVERLAY" })

    local children = {}
    if depth > 1 then
        for i = 1, FANOUT do children[i] = buildWindow(nil, depth - 1) end
    end
    return newFrame(name, regions, children)
end

local windows = {}
for i = 1, WINDOWS do windows[i] = buildWindow("GameWindow" .. i, DEPTH) end

local savedUIParent = _G.UIParent
local savedTimer = _G.C_Timer

_G.UIParent = newFrame("UIParent", {}, windows)

ns.flavor = "vanilla"
local profile = { darkness = { amount = 30, exclude = {} } }
ns.Addon = { db = { profile = profile } }

-- A frame of the game: deferred work is done here and only here.
local queue = {}
_G.C_Timer = { After = function(_, fn) queue[#queue + 1] = fn end }

local function runFrame()
    local due = queue
    queue = {}
    for i = 1, #due do due[i]() end
end

_G.pcall = countingPcall

-- The first application: the reconnaissance of the interface. It is expensive,
-- and it is supposed to be — it is not done on a movement of the slider.
reset()
Darkness:ApplySettings()
local planSize = Darkness.PlanSize()

T.eq(planSize, chromeCount, "all the stand-in interface's framing got into the plan")
T.ok(counters.children > 0, "the first application really does walk the tree")

T.suite("the darkness: a step of the slider does not touch the interface's tree")

-- The expensive part is finding out what the interface consists of. It does
-- not depend on the slider's position, and there is no point repeating it at every division.
do
    written = {}
    reset()
    profile.darkness.amount = 31
    Darkness.Schedule()
    runFrame()

    T.eq(counters.children, 0, "a step of the slider does not ask for child frames")
    T.eq(counters.regions, 0, "nor does it ask for regions")
    T.eq(counters.writes, planSize, "but the whole plan gets a colour")

    -- A limit rather than today's number: one protected call per texture plus
    -- a small allowance for the application's overheads. Before the edit a
    -- region cost about fifteen.
    T.ok(counters.pcall <= 2 * planSize,
        "there are no more than two protected calls per texture of the plan")

    local twice = 0
    for _, times in pairs(written) do
        if times > 1 then twice = twice + 1 end
    end
    T.eq(twice, 0, "not one texture had a colour written to it twice per application")
end

T.suite("the darkness: the divisions of one frame merge into one application")

-- An AceGUI slider calls the handler at every division of a drag. The player
-- will see nothing between two frames anyway, so as much work is done as he
-- will see — one application per frame.
do
    reset()
    for value = 32, 71 do
        profile.darkness.amount = value
        Darkness.Schedule()
    end

    T.eq(counters.writes, 0, "before the frame nothing was done")

    runFrame()

    T.eq(counters.writes, planSize,
        "forty divisions in one frame gave one application")
    T.ok(counters.pcall <= 2 * planSize,
        "and the cost stayed the cost of one application")
end

T.suite("the darkness: the darkening follows the slider rather than waiting for it to be released")

-- What is deferred is the work rather than the value: in the frame what stands
-- in the settings now is taken. So the darkening is visible during the drag
-- rather than only after it.
do
    local regions = { windows[1].GetRegions() }
    local art = regions[1]

    profile.darkness.amount = 100
    Darkness.Schedule()
    runFrame()
    T.ok(math.abs(art.r - helpers.whiteAt(Darkness.DARKEST)) < 1e-9,
        "at a hundred the texture went to the darkest multiplier")

    -- A drag interrupted halfway: what is visible is the value it was
    -- interrupted at rather than half the interface on one and half on another.
    profile.darkness.amount = 60
    Darkness.Schedule()
    runFrame()
    T.ok(math.abs(art.r - helpers.whiteAt(Darkness.Factor(60))) < 1e-9,
        "an interrupted drag leaves exactly the value it stopped at")

    profile.darkness.amount = 0
    Darkness.Schedule()
    runFrame()
    T.eq(art.r, 1, "a return to zero restored the native colour")
end

T.suite("the darkness: the contents do not get into the plan")

do
    local first = windows[1]
    local regions = { first.GetRegions() }
    local portrait, label = regions[CHROME + 1], regions[CHROME + 2]

    T.eq(Darkness.Remembered(portrait), nil, "the portrait is not listed in the plan")
    T.eq(Darkness.Remembered(label), nil, "the label is not listed in the plan")
    T.eq(portrait.r, 1, "and the portrait's colour is untouched by any application")
    T.eq(label.r, 1, "and so is the label's colour")
end

T.suite("the darkness: after a drag nothing is left running")

-- The author also reported that the game stutters after the drag itself. A
-- list growing without end, a handler re-entering itself or an OnUpdate left
-- behind would give exactly that.
do
    for value = 1, 60 do
        profile.darkness.amount = value
        Darkness.Schedule()
        runFrame()
    end

    T.eq(Darkness.Pending(), false, "the subsystem has no deferred work behind it")
    T.eq(#queue, 0, "nor one unfired timer")
    T.eq(Darkness.PlanSize(), planSize, "the plan did not grow by a single texture")

    -- A repeated showing of the same window adds nothing either: a texture
    -- already lying in the plan does not get into it a second time.
    local before = Darkness.PlanSize()
    for _ = 1, 50 do Darkness.ApplyToWindow(windows[1]) end
    T.eq(Darkness.PlanSize(), before,
        "fifty showings of one window added nothing to the plan")
end

T.suite("the darkness: a window that appeared later is found all the same")

-- Making it cheaper must not narrow the reach: a window nobody enumerated is
-- obliged to darken. Showing a window adds it to the plan; a full application
-- reconnoitres the interface afresh.
do
    profile.darkness.amount = 50
    Darkness.Schedule()
    runFrame()

    local lateArt = newRegion({
        texture = "Interface\\Spellbook\\Spellbook-Page-1" })
    local late = newFrame("SomeAddonWindow", { lateArt })

    local before = Darkness.PlanSize()
    T.eq(Darkness.ApplyToWindow(late), 1, "a new window is darkened when shown")
    T.eq(Darkness.PlanSize(), before + 1, "and is added to the plan exactly once")
    T.ok(math.abs(lateArt.r - helpers.whiteAt(Darkness.Factor(50))) < 1e-9,
        "by exactly the slider's current value")

    -- A window nobody showed through ShowUIPanel is picked up by the next full
    -- application.
    local quietArt = newRegion({
        texture = "Interface\\AuctionFrame\\UI-Auction-Background" })
    windows[#windows + 1] = newFrame("QuietWindow", { quietArt })
    _G.UIParent = newFrame("UIParent", {}, windows)

    Darkness:ApplySettings()
    T.ok(math.abs(quietArt.r - helpers.whiteAt(Darkness.Factor(50))) < 1e-9,
        "a full application reconnoitres the interface afresh")
end

_G.pcall = realpcall
_G.C_Timer = savedTimer
_G.UIParent = savedUIParent
ns.Addon = nil
ns.flavor = nil

T.suite("the darkness: the walk of a window goes in slices")

-- The talents window is fifteen hundred frames, and walking it entirely in one
-- frame the player sees as the game stopping. The author saw it: the game
-- stood still when he pressed to open a window, and he wanted smoothness.
--
-- So the walk is divided by time: as much as was managed in a slice is what
-- was painted, the rest on the next frame.
do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Modules/Darkness.lua", ns)

    local Darkness = ns.Darkness
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }

    -- A clock that runs too fast: the slice ends at the very first step.
    local clock = 0
    local savedProfile, savedTimer = _G.debugprofilestop, _G.C_Timer
    _G.debugprofilestop = function()
        clock = clock + 1000
        return clock
    end

    local waits = {}
    _G.C_Timer = { After = function(delay, run) waits[#waits + 1] = run end }

    local function art()
        local region = {
            r = 1, g = 1, b = 1, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function()
                return "Interface" .. string.char(92) .. string.char(92)
                    .. "DialogFrame" .. string.char(92) .. string.char(92)
                    .. "UI-DialogBox-Background"
            end,
        }
        function region:GetVertexColor() return self.r, self.g, self.b, self.a end
        function region:SetVertexColor(cr, cg, cb)
            self.r, self.g, self.b = cr, cg, cb
        end
        return region
    end

    local first, second = art(), art()
    local child = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "MerchantFrameInner" end,
        GetRegions = function() return second end,
        GetChildren = function() return end,
    }
    local window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "MerchantFrame" end,
        GetRegions = function() return first end,
        GetChildren = function() return child end,
    }

    Darkness.ApplyToWindow(window)

    T.ok(first.r < 1, "the first slice painted nothing")
    T.eq(second.r, 1, "the slice did not end in time: everything was painted at once")
    T.ok(#waits > 0, "the walk's continuation was not deferred")

    waits[1]()
    T.ok(second.r < 1, "the next slice did not finish painting the window")

    ns.Addon, ns.flavor = nil, nil
    _G.debugprofilestop, _G.C_Timer = savedProfile, savedTimer
end

T.suite("the darkness: a repeated walk of a window does not ask afresh")

-- The rule of selection asks a picture five things — its layer, its name, its
-- atlas, its path and its colour — and every question goes through a protected
-- call. The walk comes back into a window when it is shown, when a tab is
-- switched and on the server's answer; and the answer is one and the same. The
-- author asked about it outright: could we not store every window's values with us so as to paint them in advance.
do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Modules/Darkness.lua", ns)

    local Darkness = ns.Darkness
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }

    local asked = 0
    local region = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetName = function() return nil end,
        GetTexture = function()
            asked = asked + 1
            return "Interface" .. string.char(92) .. string.char(92)
                .. "DialogFrame" .. string.char(92) .. string.char(92)
                .. "UI-DialogBox-Background"
        end,
    }
    function region:GetVertexColor() return self.r, self.g, self.b, self.a end
    function region:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end

    local window = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "MerchantFrame" end,
        GetRegions = function() return region end,
        GetChildren = function() return end,
    }

    Darkness.ApplyToWindow(window)
    local first = asked
    T.ok(first > 0, "the rule of selection never once asked the picture")

    -- A return into the same window: the picture is the same, the answer is the
    -- same, there is nothing to ask afresh.
    Darkness.ApplyToWindow(window, true)
    T.eq(asked, first, "the repeated walk asked the picture afresh")

    -- Clearing the plan means the interface's composition could have changed:
    -- the answers are no longer reliable, and the rule asks again.
    Darkness.Invalidate()
    Darkness.ApplyToWindow(window, true)
    T.ok(asked > first, "after the plan was cleared the answers were taken out of the old memory")

    ns.Addon, ns.flavor = nil, nil
end
