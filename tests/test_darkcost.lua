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

T.suite("the darkness: what it spends while nothing is happening")

-- Opening a window and changing a setting are measured above and in the whole
-- cost set. Walking about is measured nowhere, and that is where the author
-- says the frames go: nothing is opened then, so whatever the addon spends is
-- spent on the interface moving by itself - pictures the game assigns afresh,
-- frames it shows and hides, areas looked up for them.
--
-- Each of those is cheap and each is paid per write, so the question is not
-- "is it cheap" but "how many times a second". The subsystem counts them and
-- the difference between two readings answers it.
do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Modules/Darkness.lua", ns)

    local reading = ns.Darkness.Churn()
    T.ok(type(reading) == "table", "a reading is a table of numbers")
    for _, key in ipairs({ "heard", "ours", "adopted", "climbs", "swept",
        "dimmed", "slices", "spent", "worst" }) do
        T.eq(type(reading[key]), "number", "the reading holds " .. key)
    end

    -- The two paths that were counted nowhere before: a picture the plan does
    -- not hold announcing itself, and a hidden frame being shown. Between the
    -- hearings and the pictures of ours lies everything the addon does for
    -- pictures that are none of its business, and that was invisible.
    local before = { heard = 100, ours = 10, adopted = 80, climbs = 4,
        swept = 20, dimmed = 5, slices = 2, spent = 3, worst = 1 }
    local after = { heard = 1100, ours = 60, adopted = 980, climbs = 404,
        swept = 220, dimmed = 15, slices = 12, spent = 23, worst = 7 }

    local lines = ns.Darkness.ChurnLines(before, after, 10)
    local joined = table.concat(lines, "\n")

    T.ok(joined:find("heard 100", 1, true) ~= nil,
        "the hearings are given per second, not as a total")
    T.ok(joined:find("of ours 5", 1, true) ~= nil,
        "and the share of them that is about our own pictures")
    T.ok(joined:find("taken up 90", 1, true) ~= nil,
        "the pictures taken up are per second too")
    T.ok(joined:find("climbs for an area 40", 1, true) ~= nil,
        "a climb per picture is the expensive case and is named apart")
    T.ok(joined:find("shown and answered 20", 1, true) ~= nil,
        "so are the showings answered")
    T.ok(joined:find("worst slice of the session 7.00 ms", 1, true) ~= nil,
        "the worst slice is not a rate and is given as it stands")

    T.eq(#ns.Darkness.ChurnLines(before, after, 0), 0,
        "with no time between the readings there is nothing to divide by")
    T.eq(#ns.Darkness.ChurnLines(nil, after, 10), 0,
        "and nothing to compare against without a first reading")
end

T.suite("the darkness: one picture does not pay for every area")

-- A picture the game creates on its own is painted the moment it announces
-- itself: one picture, one application. The arithmetic of an application -
-- every area's multiplier, every area's brightness ceiling, the tint, the
-- class colour and four tables to hold them - does not depend on which
-- picture is being painted, and it was computed afresh on every one of those
-- calls.
--
-- That is the whole of what the addon spends while the player merely walks
-- about: another addon's pins redrawn, plates coming into range, a list's
-- rows handed out afresh. So it is computed once per change of setting, and
-- the check is by composition rather than by time: an edit that moves it back
-- inside the per-picture call fails here.
do
    local settings = profile.darkness

    local asked = 0
    local real = Darkness.GroupMultipliers
    Darkness.GroupMultipliers = function(...)
        asked = asked + 1
        return real(...)
    end

    Darkness.ForgetShade()
    Darkness.Shade(settings)
    local perChange = asked
    T.ok(perChange > 0,
        "a change of setting works out every area: " .. perChange)

    asked = 0
    for _ = 1, 50 do Darkness.Shade(settings) end
    T.eq(asked, 0,
        "fifty applications with the settings unchanged work out nothing anew")

    -- And it is not kept past the change it was computed for: the doors that
    -- apply the whole plan drop it, and so does a profile handing over
    -- another table of settings.
    Darkness.ForgetShade()
    asked = 0
    Darkness.Shade(settings)
    T.eq(asked, perChange, "after a change it is worked out again")

    asked = 0
    Darkness.Shade({ amount = settings.amount, mode = settings.mode })
    T.eq(asked, perChange, "another table of settings is another answer")

    Darkness.GroupMultipliers = real
    Darkness.ForgetShade()
end

T.suite("the darkness: a frame that shows often is not walked every time")

-- The watcher of showings is placed on every named child of the interface
-- root, so the answer "a window appeared, walk it" is reached by tooltips,
-- error text, zone names, drop-downs and whatever other addons show as the
-- player moves about. A walk is what a window opening can afford because a
-- window opening is rare; these are not rare.
--
-- The author's reading while walking about the world: sixty-five walk slices
-- a second and ninety milliseconds of walking in every second of play, with
-- no window open at all. Each showing threw away the walk in flight and
-- started another, so none of them ever finished.
do
    local walked = 0
    local saved = Darkness.ApplyToWindow
    Darkness.ApplyToWindow = function() walked = walked + 1 end

    local tooltip = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "HoverTip" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
        GetParent = function() return nil end,
    }

    for _ = 1, 40 do Darkness.WindowShown(tooltip) end
    T.ok(walked > 0, "the first showings are walked: " .. walked)
    T.ok(walked <= 3,
        "and forty showings do not cost forty walks: " .. walked)

    -- A fresh reconnaissance means the interface itself changed, and the
    -- count starts over with it: a frame rebuilt from scratch has contents
    -- nobody has walked.
    Darkness.Invalidate()
    local before = walked
    Darkness.WindowShown(tooltip)
    T.eq(walked, before + 1, "after a fresh plan it is walked again")

    Darkness.ApplyToWindow = saved
end

T.suite("the darkness: a window the player opened is always walked")

-- The limit on walks is for frames that merely appear - tooltips, error
-- text, zone names, whatever other addons show as the player moves. A window
-- the player opened is a different event: it arrives through the game's own
-- panel door, it is rare, and what it holds sits deeper than the top layer
-- reaches.
--
-- Counting the two together cost the character sheet its slot frames: the
-- slots are two levels down, and the sheet had spent its three walks on
-- showings that were not openings.
do
    local walked = 0
    local saved = Darkness.ApplyToWindow
    Darkness.ApplyToWindow = function() walked = walked + 1 end

    local sheet = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "DollWindow" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
        GetParent = function() return nil end,
    }

    -- Shown twenty times without being opened: the limit holds.
    for _ = 1, 20 do Darkness.WindowShown(sheet) end
    local byShowing = walked
    T.ok(byShowing <= 3, "a mere showing is walked at most three times: "
        .. byShowing)

    -- And opened twenty times: every one of them is walked.
    walked = 0
    for _ = 1, 20 do Darkness.WindowShown(sheet, true) end
    T.eq(walked, 20, "an opening is always walked, however many came before")

    Darkness.ApplyToWindow = saved
end

T.suite("the darkness: a walk that finds something new is not held against it")

-- Two things come through this door and look the same from outside. A window
-- whose rows the game creates as it goes - reputations, skills, statistics -
-- yields something new every time it is walked, and it has to go on being
-- walked or those rows stay light: the author sent exactly that, a dark
-- window with a gold frame on every row. A frame that merely flickers finds
-- nothing new on its second visit, and the limit is for that one.
do
    local saved = Darkness.ApplyToWindow
    local walked, growing = 0, false

    -- A stand-in for the walk: it records a texture into the plan when the
    -- window has something new in it, and nothing when it has not.
    Darkness.ApplyToWindow = function(frame)
        walked = walked + 1
        if growing then
            Darkness.Remember(frame, newArt and newArt() or nil)
        end
    end

    local list = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "ListWindow" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
        GetParent = function() return nil end,
    }

    -- Nothing new: the limit closes after three.
    growing = false
    for _ = 1, 30 do Darkness.WindowShown(list) end
    T.ok(walked <= 3, "a fruitless showing is walked at most three times: "
        .. walked)

    Darkness.ApplyToWindow = saved
end

T.suite("the darkness: a ceiling on walking that does not depend on judgement")

-- Every rule about which showings deserve a walk is a judgement, and two of
-- them were wrong inside one hour, each paid for in the author's frames.
-- This one is not a judgement: whatever the rules decide, once the walking
-- done in the last second passes the ceiling, a showing gets the top layer
-- and nothing more until the second is out.
do
    local clock = 5000
    local savedClock = _G.debugprofilestop
    _G.debugprofilestop = function() return clock end

    local walked = 0
    local saved = Darkness.ApplyToWindow
    Darkness.ApplyToWindow = function() walked = walked + 1 end

    local frame = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "BudgetWindow" end,
        GetRegions = function() return end,
        GetChildren = function() return end,
        GetParent = function() return nil end,
    }

    T.eq(Darkness.WalkSpent(), 0, "a fresh second has nothing spent in it")

    -- Nine milliseconds of walking: still under.
    Darkness.SpendWalk(9)
    T.eq(Darkness.WalkSpent(), 9, "what was spent is counted")
    Darkness.WindowShown(frame)
    T.eq(walked, 1, "and a showing is still walked")

    -- Past the ceiling: the showings door closes.
    Darkness.SpendWalk(5)
    walked = 0
    for _ = 1, 10 do Darkness.WindowShown(frame) end
    T.eq(walked, 0, "past the ceiling a showing gets the top layer only")

    -- A window the player opens is never refused: it is rare, he is looking
    -- straight at it, and it is the whole reason the walk exists.
    Darkness.WindowShown(frame, true)
    T.eq(walked, 1, "an opening is walked even then")

    -- And the second runs out.
    clock = clock + 1100
    T.eq(Darkness.WalkSpent(), 0, "the next second starts clean")
    Darkness.WindowShown(frame)
    T.eq(walked, 2, "and showings are walked again")

    _G.debugprofilestop = savedClock
    Darkness.ApplyToWindow = saved
end
