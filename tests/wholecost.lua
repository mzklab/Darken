-- The whole addon's cost: a scene in which every subsystem works at once.
--
-- Why the file exists. Every subsystem is measured on its own, and several
-- have a ceiling of their own: the nameplates 0.08 ms for thirty of them, the
-- auras 0.005 ms per redraw, the item database 0.14 ms per keypress, the
-- darkness 20,801 protected calls per division of the slider, the settings
-- search 0.3 ms. Not one of those numbers answers the question the author will
-- ask: why the frame rate dropped. In the client the subsystems work in one
-- frame, in one thread, while the game draws, and the sum had never once been measured.
--
-- Here it is measured. The scene is brought up by the cold boot
-- (tests/coldboot.lua) — the same one the addon is brought up whole by — and to
-- it is added what the cold boot does not need and the measurement does: a
-- client with real data (thirty nameplates, a party with auras, a cast under
-- way), a configured profile instead of a fresh install, and a stand-in
-- interface with some depth so that the darkness has something to walk.
--
-- THE HONEST BOUNDARY. This is not the game. There is no frame engine here, no
-- drawing, no real frame and no C side of the game's functions: every call
-- such as SetVertexColor costs more in the client than here, while every
-- UnitHealth answers instantly here. So the absolute numbers read as "an order
-- of magnitude and a subsystem's share" rather than as milliseconds at the
-- player's end. What only the client can say is listed in the measurement's own report.

local coldboot = require("coldboot")

local wholecost = {}

wholecost.PLATES = 30       -- nameplates on the screen at the height of a fight
wholecost.PARTY  = 5        -- the player and four: a full classic party
wholecost.BARS   = 8        -- bars of the game's whose label the game updates

--============================================================================
-- The accounting of the work that is visible from outside
--============================================================================

-- The walks of the interface's tree and the writes of colour. They are counted
-- on the stand-in interface: it is by those very numbers that the darkness is
-- measured, and it is they that form the ceiling by shape ("in a frame of a
-- fight the tree is not walked once") rather than by milliseconds.
local counters = { children = 0, regions = 0, writes = 0 }
wholecost.counters = counters

function wholecost.reset()
    counters.children, counters.regions, counters.writes = 0, 0, 0
end

--============================================================================
-- The stand-in interface with depth
--============================================================================

-- The cold boot's stand-in answers any method but has no tree: GetChildren and
-- GetRegions return nothing. The darkness then has nothing to find, and its
-- share of the total cost would turn out to be zero through an oversight of
-- the measurement rather than through the addon's build. So a tree of a known
-- size is laid under UIParent — the same in build as in
-- tests/test_darkcost.lua and smaller in size: what is checked here is the share rather than the darkness's own limit.
local WINDOWS, FANOUT, DEPTH, CHROME = 10, 2, 3, 6

-- The tree's size is computed rather than rewritten as a number: the limit
-- "one walk per application" is expressed through it, and a divergence would
-- make the limit meaningless silently.
do
    local frames, level = 0, 1
    for _ = 1, DEPTH do
        frames = frames + WINDOWS * level
        level = level * FANOUT
    end
    wholecost.treeFrames = frames
    -- What gets into the darkness's plan is the framing and only it: an icon
    -- by file number and a label are contents, and it has no right to take them.
    wholecost.treeTextures = frames * CHROME
end

--- A region of the stand-in interface.
local function region(opts)
    local self = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return opts.kind or "Texture" end,
        GetDrawLayer = function() return opts.layer or "ARTWORK" end,
        GetTexture = function() return opts.texture end,
        GetName = function() return opts.name end,
    }
    function self:GetVertexColor() return self.r, self.g, self.b, self.a end
    function self:SetVertexColor(cr, cg, cb, ca)
        counters.writes = counters.writes + 1
        self.r, self.g, self.b = cr, cg, cb
        if ca ~= nil then self.a = ca end
    end
    return self
end

--- A frame of the stand-in interface: the approaches to the tree are counted.
local function frame(name, regions, children)
    local self = coldboot.widget(name)
    self.GetObjectType = function() return "Frame" end
    self.GetRegions = function()
        counters.regions = counters.regions + 1
        return unpack(regions)
    end
    self.GetChildren = function()
        counters.children = counters.children + 1
        return unpack(children)
    end
    return self
end

--- A window of the stand-in interface: framing, contents and children.
local function window(name, depth)
    local regions = {}
    for i = 1, CHROME do
        regions[i] = region({
            texture = "Interface\\DialogFrame\\UI-DialogBox-Border" .. i })
    end
    -- The contents: an icon by file number and a label. The darkness's plan is
    -- obliged not to take them, so they take no part in the total cost.
    regions[CHROME + 1] = region({ texture = 132863,
        name = "MockPortrait" })
    regions[CHROME + 2] = region({ kind = "FontString", layer = "OVERLAY" })

    local children = {}
    if depth > 1 then
        for i = 1, FANOUT do children[i] = window(nil, depth - 1) end
    end
    return frame(name, regions, children)
end

--============================================================================
-- The "everything on" profile
--============================================================================

--- The settings of a player in a fight: not a fresh install.
--
-- A fresh install changes nothing on the screen, and the cost of its frame is
-- the cost of an addon that does nothing. The author's question is about
-- another player: one who switched on everything the addon can do. The fields
-- are named one by one rather than "switch on every boolean setting at once":
-- at once would also switch on what a player never switches on (the
-- demonstration, the movers' grid), and the measurement would stop answering the question about a fight.
-- @return table the contents of DarkenDB
function wholecost.saved()
    return {
        profileKeys = { ["Tester - Test Realm"] = "Default" },
        profiles = {
            Default = {
                version = 5,

                -- The nameplates' engine: everything it can do at once.
                umbraplates = {
                    enabled = true, width = 110, height = 10, scale = 1,
                    truncate = true, threat = true, quest = true,
                    castbar = true, castHeight = 5,
                    auras = true, auraSize = 16, auraLimit = 4,
                    auraOnlyMine = false, auraHelpful = true,
                    auraHarmful = true, auraMode = "off", auraList = "",
                    texture = "__native", rules = {},
                },

                -- The auras of the player and of the party's units.
                umbraauras = {
                    enabled = true, units = true, separate = true,
                    showTime = true, showStacks = true, mouse = true,
                    size = 30, spacing = 4, perRow = 12,
                    direction = "downleft", filterMode = "off",
                    filterList = "", rules = {}, version = 2,
                },

                -- The cast bars of the player, the target and the focus.
                umbracastbars = {
                    player = { enabled = true, ticks = true, latency = true },
                    target = { enabled = true },
                    focus  = { enabled = true },
                    tickWidth = 1, tickColor = "ink",
                    latencyAlpha = 0.6, latencyColor = "lilacDeep",
                    shieldAlpha = 0.3, shieldColor = "lilac",
                },

                -- The labels on the game's bars.
                texts = {
                    health = "percent", power = "percent",
                    position = "center", abbreviate = true,
                },

                -- The darkness: not zero, or the application writes nothing.
                darkness = { amount = 40, exclude = {}, tint = {} },

                umbrailevel = { enabled = true, quality = true,
                    position = "topleft", size = 11, font = "hotkey" },
                umbrainfo = { enabled = true, top = true, bottom = false,
                    push = true, height = 18, sides = {}, hidden = {},
                    order = {} },
            },
        },
    }
end

--============================================================================
-- The client with data
--============================================================================

local HARMFUL = { "Rend", "Hamstring", "Sunder Armor", "Curse of Agony" }
local HELPFUL = { "Battle Shout", "Blessing", "Mark of the Wild" }

--- Bring the stand-in client up to a fight.
-- Called by coldboot.boot at the one moment when an edit of a global is still
-- visible to the whole addon: after the globals are created and before the libraries are read.
-- @param scene table
local function client(scene)
    local units = scene.units
    local clock = 1000

    _G.GetTime = function() return clock end
    scene.tick = function(step) clock = clock + (step or 0.016) end

    -- The game's nameplates: one per unit, created in advance and reusable, as
    -- in the client.
    local plates = {}
    for i = 1, #units.plates do
        local plate = coldboot.widget("GamePlate" .. i)
        plate.UnitFrame = coldboot.widget("GamePlateUnitFrame" .. i)
        plate.namePlateUnitToken = units.plates[i]
        plates[units.plates[i]] = plate
    end
    scene.plates = plates

    _G.C_NamePlate = {
        GetNamePlateForUnit = function(unit) return plates[unit] end,
        GetNamePlates = function() return {} end,
    }

    _G.UnitExists = function(unit) return units.known[unit] or false end
    _G.UnitIsPlayer = function(unit) return units.party[unit] or false end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.UnitReaction = function() return 2 end
    _G.UnitName = function(unit) return "Unit " .. tostring(unit) end
    _G.UnitLevel = function() return 60 end
    -- The health changes, and that is not decoration for the measurement. The
    -- subsystems compare a new value against the former one and do nothing on
    -- an equal one; a constant health would turn the most frequent event of a
    -- fight into a measurement of one comparison, while in a fight it is a different one at every event.
    local hp = 4100
    _G.UnitHealth = function()
        hp = hp - 37
        if hp < 100 then hp = 7300 end
        return hp
    end
    _G.UnitHealthMax = function() return 7300 end
    _G.UnitPower = function() return 620 end
    _G.UnitPowerMax = function() return 1000 end
    _G.UnitIsUnit = function(a, b) return a == b end
    _G.UnitThreatSituation = function() return 2 end
    _G.UnitIsQuestBoss = function() return true end
    _G.UnitAffectingCombat = function() return true end

    -- Seven auras per unit: four harmful, three helpful. Exactly the case the
    -- core's shared aura filter is written for.
    _G.UnitAura = function(_, index, filter)
        local list = filter == "HELPFUL" and HELPFUL or HARMFUL
        local name = list[index]
        if not name then return nil end
        return name, "Interface\\Icons\\Spell", (index % 3) + 1, "Magic",
            12, clock + 6, "player", false, false, 1000 + index
    end

    _G.UnitCastingInfo = function()
        return "Fireball", nil, "Interface\\Icons\\Fire", (clock - 1) * 1000,
            (clock + 1.5) * 1000, false, "cast-1", false, 133
    end
    _G.UnitChannelInfo = function() return nil end
    _G.GetNetStats = function() return 0, 0, 40, 40 end

    -- The game's functions the addon stands on top of through hooksecurefunc.
    -- In the cold boot their names are stand-in frames, that is, tables, and
    -- not one handler is hung; here they are real functions, and the handlers
    -- do go on. Without that the bar labels and the unit frames' repainting
    -- would take no part in the cost at all.
    local flavor = scene.flavor
    local groups = { "unitframe-recolor", "nameplate-recolor",
        "actionbar-relayout", "raidframe-relayout",
        "unitframe-auras-relayout" }
    local painters = {}
    for i = 1, #groups do
        if scene.compat.HasGroup(flavor, groups[i]) then
            local names = scene.compat.GetFrameNames(flavor, groups[i])
            for j = 1, #names do painters[#painters + 1] = names[j] end
        end
    end
    painters[#painters + 1] = "TextStatusBar_UpdateTextString"
    for i = 1, #painters do _G[painters[i]] = function() end end
    scene.painters = painters

    -- The game's bars whose label the game updates itself. They exist under
    -- their own names (the compatibility layer), and the label on them is set
    -- by our subsystem, standing behind the game.
    local bars = {}
    local named = scene.compat.GetFrameNames(flavor, "unitframe")
    for i = 1, #named do
        local object = _G[named[i]]
        if type(object) == "table" then
            bars[#bars + 1] = object
            if #bars >= wholecost.BARS then break end
        end
    end
    scene.bars = bars

    -- The stand-in interface with depth goes under UIParent, which is what the
    -- darkness walks.
    local windows = {}
    for i = 1, WINDOWS do windows[i] = window("GameWindow" .. i, DEPTH) end
    _G.UIParent.GetChildren = function()
        counters.children = counters.children + 1
        return unpack(windows)
    end
    _G.UIParent.GetRegions = function()
        counters.regions = counters.regions + 1
        return
    end
    scene.windows = windows

    -- The deferred work: there is no frame of our own outside the game, and it
    -- has to be acted out. It is here that the darkness folds the slider's divisions into one pass.
    local queue = {}
    _G.C_Timer = {
        After = function(_, fn) queue[#queue + 1] = fn end,
        NewTimer = function() return coldboot.widget(nil) end,
        NewTicker = function() return coldboot.widget(nil) end,
    }
    scene.runTimers = function()
        local due = queue
        queue = {}
        for i = 1, #due do pcall(due[i]) end
        return #due
    end
end

--============================================================================
-- The scene
--============================================================================

--- Bring the whole addon up at the height of a fight.
-- @param opts table|nil
--   opts.toc string the core TOC's name (Darken_Vanilla.toc by default)
--   opts.interface number the interface number (11507 by default)
--   opts.plates number how many nameplates are on the screen
-- @return table the scene
function wholecost.scene(opts)
    opts = opts or {}

    local plateCount = opts.plates or wholecost.PLATES
    local scene = { units = { plates = {}, party = {}, known = {} } }

    for i = 1, plateCount do
        local unit = "nameplate" .. i
        scene.units.plates[i] = unit
        scene.units.known[unit] = true
    end
    local party = { "player" }
    for i = 1, wholecost.PARTY - 1 do party[#party + 1] = "party" .. i end
    for i = 1, #party do
        scene.units.party[party[i]] = true
        scene.units.known[party[i]] = true
    end
    scene.units.list = party
    scene.units.known.target = true
    scene.units.known.focus = true

    -- The compatibility layer is needed by the client's preparation before the
    -- core comes up: the names of the game's functions are asked of it rather than rewritten here.
    local probe = {}
    do
        local helpers = require("helpers")
        helpers.loadAddonFile("Core/Compat.lua", probe)
    end
    scene.compat = probe.Compat
    scene.flavor = probe.Compat.DetectFlavor(opts.interface or 11507)

    wholecost.reset()

    local boot = coldboot.boot({
        toc           = opts.toc or "Darken_Vanilla.toc",
        interface     = opts.interface or 11507,
        saved         = wholecost.saved(),
        modules       = true,
        petHappiness  = true,
        settingsPanel = true,
        client        = function() client(scene) end,
    })

    scene.boot = boot
    scene.ns = boot.ns
    scene.restore = boot.restore

    if not boot.coreLoaded then return scene end

    -- Entering the world: the event at which the subsystems take from the game
    -- what it has just drawn. The cold boot deliberately does not reach it —
    -- that is no longer the load but the game's first frame.
    --
    -- It is dispatched by the core's door rather than by AceAddon's frame: the
    -- addon's subscriptions live behind that door, and AceAddon's frame knows only of its own ADDON_LOADED and
    -- PLAYER_LOGIN.
    local dispatch = scene.ns.Events.Dispatch
    scene.dispatch = dispatch

    wholecost.enterWorld(scene)

    return scene
end

--- Entering the world: a change of zone, a loading screen, the first frame after it.
--
-- The nameplates are attached right here, and that is not an addition to the
-- measurement but the game's own order: entering the world takes every
-- nameplate away at once (the engine detaches them itself — see detachAll in
-- the module), and after that the game creates them afresh for every creature that is visible.
-- @param scene table
function wholecost.enterWorld(scene)
    local dispatch = scene.dispatch

    dispatch("PLAYER_ENTERING_WORLD")
    scene.runTimers()

    local plates = scene.units.plates
    for i = 1, #plates do dispatch("NAME_PLATE_UNIT_ADDED", plates[i]) end
    scene.runTimers()
end

--============================================================================
-- The moments
--============================================================================

--- The most expensive frame of a fight.
--
-- What is in it and why exactly this:
--   * the health on each of the thirty nameplates — at the height of a fight
--     it changes for everybody, and that is the game's most frequent event;
--   * a change of auras on a third of the nameplates — applied and expired;
--   * a cast starting on five of them;
--   * a threat update on all thirty — it arrives as a wave;
--   * a change of auras on the player and on the four in the party;
--   * the player's own cast;
--   * the game redrew the labels on eight bars.
--
-- All of that in one frame — not an average frame but the worst: a ceiling is
-- set by the worst, or it is not a ceiling.
-- @param scene table
function wholecost.busyFrame(scene)
    local dispatch = scene.dispatch
    local plates = scene.units.plates
    local party = scene.units.list

    for i = 1, #plates do dispatch("UNIT_HEALTH", plates[i]) end
    for i = 1, #plates, 3 do dispatch("UNIT_AURA", plates[i]) end
    for i = 1, 5 do dispatch("UNIT_SPELLCAST_START", plates[i]) end
    for i = 1, #plates do dispatch("UNIT_THREAT_LIST_UPDATE", plates[i]) end

    for i = 1, #party do dispatch("UNIT_AURA", party[i]) end
    dispatch("UNIT_SPELLCAST_START", "player")

    local update = _G.TextStatusBar_UpdateTextString
    local bars = scene.bars
    if type(update) == "function" then
        for i = 1, #bars do update(bars[i]) end
    end

    scene.tick()
end

--- A repainting that spreads across the whole addon: a change of setting.
-- @param scene table
function wholecost.settingsChange(scene)
    scene.ns.Registry:ApplyAll()
    scene.runTimers()
end

--- The bags changed: loot dropped, the arrows ran out.
--
-- In a fight that happens, and happens not every frame but several times per
-- fight. It is measured apart from the frame of a fight for exactly that
-- reason: adding them together would mean declaring the bags' contents to change sixty times a second.
-- @param scene table
function wholecost.bagUpdate(scene)
    scene.dispatch("BAG_UPDATE", 0)
    scene.dispatch("BAG_UPDATE_DELAYED")
end

--- A frame of a fight in which the bags changed as well.
-- @param scene table
function wholecost.bagsFrame(scene)
    wholecost.bagUpdate(scene)
    wholecost.busyFrame(scene)
end

--============================================================================
-- Whose share
--============================================================================

-- A subsystem's share is taken on a second run, apart from the total cost, and
-- here is why. A wrapper around a handler costs two approaches to the clock,
-- and in a frame with two hundred handler calls that charge is a noticeable
-- share of the measured quantity itself. So the total number is measured
-- without wrappers while the shares are measured with them, and they read as shares rather than as milliseconds.

--- Hang timing accounting onto every subscription.
-- There is one door: ns.Events. Everything subscribed through it is named by
-- the module's name, and that is why a share is computed by itself.
-- Subscriptions past that door are unavailable to the accounting — a separate check watches over that.
-- @param scene table
-- @return table the shares: name -> seconds, function remove the wrappers
function wholecost.instrument(scene)
    local events = scene.ns.Events
    local tally, calls = {}, {}
    local undo = {}

    local clock = os.clock

    local function wrap(fn, name)
        tally[name] = tally[name] or 0
        calls[name] = calls[name] or 0
        return function(...)
            local started = clock()
            local a, b = fn(...)
            tally[name] = tally[name] + (clock() - started)
            calls[name] = calls[name] + 1
            return a, b
        end
    end

    for event, byModule in pairs(events.listeners) do
        for name, fn in pairs(byModule) do
            undo[#undo + 1] = { byModule, name, fn }
            byModule[name] = wrap(fn, name)
        end
    end
    for event, list in pairs(events.core) do
        for i = 1, #list do
            undo[#undo + 1] = { list, i, list[i] }
            list[i] = wrap(list[i], "core")
        end
    end

    return tally, calls, function()
        for i = 1, #undo do undo[i][1][undo[i][2]] = undo[i][3] end
    end
end

--- Notice who woke up without measuring the time.
-- Apart from instrument: the composition is a limit by shape, and it needs no clock.
-- @param scene table
-- @return table name -> how many times, function remove the wrappers
function wholecost.watch(scene)
    local woke, undo = {}, {}

    for _, byModule in pairs(scene.ns.Events.listeners) do
        for name, fn in pairs(byModule) do
            undo[#undo + 1] = { byModule, name, fn }
            byModule[name] = function(...)
                woke[name] = (woke[name] or 0) + 1
                return fn(...)
            end
        end
    end

    return woke, function()
        for i = 1, #undo do undo[i][1][undo[i][2]] = undo[i][3] end
    end
end

--- The sorted list of shares: the most expensive subsystem first.
-- @param tally table
-- @return table an array of { name = , seconds = }, number the sum
function wholecost.shares(tally)
    local out, total = {}, 0
    for name, seconds in pairs(tally) do
        out[#out + 1] = { name = name, seconds = seconds }
        total = total + seconds
    end
    table.sort(out, function(a, b)
        if a.seconds == b.seconds then return a.name < b.name end
        return a.seconds > b.seconds
    end)
    return out, total
end

--- The average time of one run.
-- One run is shorter than the clock's precision, so a batch is measured.
-- @param fn function
-- @param rounds number
-- @return number seconds per run
function wholecost.cost(fn, rounds)
    fn()
    local started = os.clock()
    for _ = 1, rounds do fn() end
    return (os.clock() - started) / rounds
end

return wholecost
