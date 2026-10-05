local helpers = require("helpers")

-- Cost of redrawing the player aura grid (Features/Auras/Auras.lua, Redraw).
--
-- Why this file exists. The whole-addon measurement
-- (`.superpowers/sdd/whole-cost/report.md`) found that a single `UNIT_AURA`
-- on the player is the most expensive line of a combat frame: more expensive
-- than all thirty nameplates together. The report named one single cause:
-- **event frequency multiplied by a full rebuild**. The grid was released
-- into the pool and reassembled from scratch on every aura update, no matter
-- how few auras had actually changed.
--
-- What is guarded here. Not milliseconds. Milliseconds measured on a fake
-- frame measure the fake -- the whole-cost report says so, and proved it
-- there with a number that was 97% wrong. What is guarded is the **shape of
-- the work**, and it is guarded by counting engine writes:
--
--   * a redraw in which nothing changed writes to the engine **not even
--     once**;
--   * a ticking stack rewrites **one** icon out of forty;
--   * an expiring aura rewrites **none** -- it only removes its own;
--   * none of these redraws creates **a single** frame, and none returns to
--     the pool any icon that stays on screen;
--   * a settings change, conversely, is obliged to rewrite **every** icon: a
--     path that fails to is a setting that never reached the screen.
--
-- There is deliberately no "so many milliseconds plus slack" ceiling here.
-- Such a ceiling would stay green if the full rebuild came back -- it would
-- be enough to buy its cost back somewhere else -- whereas the write counter
-- fails on the very first line that restores the old shape.
--
-- The numbers are still printed, all six cases: they are not a ceiling, they
-- are a yardstick showing that the shape really did change.

local MODULE = "Features/Auras"

helpers.installValidator()

--============================================================================
-- Fake client with a counter of engine writes
--============================================================================
--
-- The fake does exactly what the module asks of a frame, and counts every
-- call that **writes**. Reads (Get/Is) do not count: they change nothing on
-- screen, and counting them would guard the wrong thing.
--
-- Writes are charged to the owner, not to the object they were addressed to:
-- the texture, the label, the dimming and the secure overlay are parts of an
-- icon, and "how many icons were rewritten" must count them as their icon.
-- Ownership is assigned at creation: a texture or a label to whoever created
-- it, a frame to its parent.

local tally = {
    writes = 0,     -- total writes into the engine
    others = 0,     -- of those, not on icons (block holders, anchor point)
    icons  = {},    -- icon -> how many times it was written to
    built  = 0,     -- how many frames were created
}

--- Forget what was counted.
local function reset()
    tally.writes = 0
    tally.others = 0
    tally.icons  = {}
    tally.built  = 0
end

--- How many distinct icons were rewritten since the last reset.
-- @return number
local function touched()
    local count = 0
    for _ in pairs(tally.icons) do count = count + 1 end
    return count
end

--- Whose object this is: an icon, or something else.
--
-- Walking up the "who created me" chain: a texture and a label know their
-- creator, the dimming and the secure overlay know their parent. An icon is
-- recognised by its aura record -- created by Icon.Build and by nothing else
-- -- whereas a list of field names here would silently drift from the module.
--
-- This is not always decidable at creation: the dimming is created before the
-- icon has a record. So the answer is resolved on the first write and
-- remembered right there.
--
-- @param object table
-- @return table|nil the icon
local function ownerOf(object)
    local node, guard = object, 0
    while type(node) == "table" and guard < 8 do
        if node.record ~= nil then return node end
        node = node.owner or node.parent
        guard = guard + 1
    end
    return nil
end

--- Charge a write to the object's owner.
-- @param object table
local function note(object)
    tally.writes = tally.writes + 1

    local owner = object.iconOwner
    if owner == nil then
        owner = ownerOf(object)
        if owner ~= nil then object.iconOwner = owner end
    end

    if owner ~= nil then
        tally.icons[owner] = (tally.icons[owner] or 0) + 1
    else
        tally.others = tally.others + 1
    end
end

local object

--- Fake engine object.
-- @param kind string
-- @param owner table|nil who owns it
-- @return table
function object(kind, owner)
    local o = {
        kind = kind, owner = owner,
        children = {}, regions = {}, attr = {}, scripts = {}, shown = false,
    }

    function o:IsProtected() return true end
    function o:GetParent() return self.parent end
    function o:GetAttribute(key) return self.attr[key] end
    function o:IsShown() return self.shown end

    function o:Show() note(self) self.shown = true end
    function o:Hide() note(self) self.shown = false end
    function o:SetShown(v) note(self) self.shown = v and true or false end
    function o:SetPoint(point, anchor, _, x, y)
        note(self)
        self.point, self.anchor, self.x, self.y = point, anchor, x, y
    end
    function o:ClearAllPoints()
        note(self)
        self.point, self.anchor, self.x, self.y = nil, nil, nil, nil
    end
    function o:SetAllPoints(anchor) note(self) self.anchoredTo = anchor end
    function o:SetSize(w, h) note(self) self.w, self.h = w, h end
    function o:SetWidth(w) note(self) self.w = w end
    function o:SetHeight(h) note(self) self.h = h end
    function o:SetScale() note(self) end
    function o:SetAlpha() note(self) end
    function o:SetParent(value) note(self) self.parent = value end
    function o:SetAttribute(key, value) note(self) self.attr[key] = value end
    function o:EnableMouse(v) note(self) self.mouse = v and true or false end
    function o:RegisterForClicks(...) note(self) self.clicks = { ... } end

    function o:SetScript(name, fn) self.scripts[name] = fn end
    function o:GetScript(name) return self.scripts[name] end
    function o:RegisterEvent() end
    function o:UnregisterEvent() end

    function o:CreateTexture()
        local t = object("Texture", self.owner or self)
        function t:SetTexture(path) note(self) self.path = path end
        function t:SetTexCoord() note(self) end
        function t:SetVertexColor() note(self) end
        function t:SetColorTexture(r, g, b, a)
            note(self)
            self.r, self.g, self.b, self.a = r, g, b, a
        end
        function t:SetDrawLayer() note(self) end
        self.regions[#self.regions + 1] = t
        return t
    end

    function o:CreateFontString()
        local f = object("FontString", self.owner or self)
        f.text = ""
        function f:SetText(value) note(self) self.text = value or "" end
        function f:GetText() return self.text end
        function f:SetJustifyH() note(self) end
        function f:SetFont(path, height) note(self) self.height = height end
        function f:GetFont() return "font", self.height or 10, "" end
        self.regions[#self.regions + 1] = f
        return f
    end

    if kind == "Cooldown" then
        function o:SetCooldown() note(self) end
        function o:Clear() note(self) end
        function o:SetDrawEdge() note(self) end
        function o:SetHideCountdownNumbers() note(self) end
    end

    return o
end

local frames = {}

local function createFrame(kind, _, parent, template)
    local f = object(kind, nil)
    f.parent = parent
    f.template = template
    if type(parent) == "table" and parent.children then
        parent.children[#parent.children + 1] = f
    end
    frames[#frames + 1] = f
    tally.built = tally.built + 1
    return f
end

--============================================================================
-- Scene
--============================================================================

T.suite("auras-cost: a redraw costs what actually changed")

do
    local saved = {
        Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        UnitAura = _G.UnitAura, C_UnitAuras = _G.C_UnitAuras,
        GetTime = _G.GetTime, CreateFrame = _G.CreateFrame,
        UIParent = _G.UIParent, GameTooltip = _G.GameTooltip,
        InCombatLockdown = _G.InCombatLockdown,
        RegisterAttributeDriver = _G.RegisterAttributeDriver,
    }

    local core = helpers.newNamespace()
    local CORE = {
        "Core/Compat.lua", "Core/Registry.lua", "Core/Defaults.lua",
        "Core/Command.lua", "Core/Locale.lua", "Core/Skin.lua",
        "Skin/Draw.lua", "Core/Frames.lua", "Core/Events.lua",
        "Core/Combat.lua", "Core/Api.lua", "Core/Casefold.lua",
        "Core/AuraFilter.lua", "Core/Media.lua",
    }
    for i = 1, #CORE do helpers.loadAddonFile(CORE[i], core) end

    local said = {}
    core.Registry.report = function(text) said[#said + 1] = text end
    core.Addon = {
        db = { profile = {}, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }
    core.flavor = "mists"

    local clock = 1000

    _G.CreateFrame = createFrame
    _G.RegisterAttributeDriver = function() end
    _G.InCombatLockdown = function() return false end
    _G.SlashCmdList = {}
    _G.GetTime = function() return clock end
    _G.C_UnitAuras = nil
    _G.UIParent = object("Frame")
    _G.GameTooltip = {
        SetOwner = function() end, SetUnitBuff = function() end,
        SetUnitDebuff = function() end, Show = function() end,
        Hide = function() end,
    }

    -- Forty auras: twenty buffs and twenty debuffs, that is a full grid.
    -- The worst case is measured, not the usual one.
    local AURAS = { HELPFUL = {}, HARMFUL = {} }

    --- One aura: the seventh value is the source, the tenth the spell id.
    -- @param kind string
    -- @param index number
    -- @param mark number|nil anything that tells this aura from its former self
    -- @return table
    local function aura(kind, index, mark)
        local tag = (kind == "HELPFUL" and 1000 or 2000) + index
        return { kind .. index, "art" .. index .. (mark or ""), 1, nil,
                 60, clock + 60, "player", nil, nil, tag }
    end

    local function fill(count)
        for i = 1, 20 do AURAS.HELPFUL[i] = aura("HELPFUL", i) end
        for i = 1, (count or 20) do AURAS.HARMFUL[i] = aura("HARMFUL", i) end
        for i = (count or 20) + 1, 40 do AURAS.HARMFUL[i] = nil end
    end
    fill(20)

    _G.UnitAura = function(_, index, filter)
        local list = AURAS[filter] and AURAS[filter][index]
        if not list then return nil end
        return list[1], list[2], list[3], list[4], list[5], list[6],
            list[7], list[8], list[9], list[10]
    end

    local mod = helpers.newNamespace()
    helpers.loadModule(MODULE, mod)

    local handle = core.Registry:Get("umbraauras")
    T.ok(handle ~= nil, "the module is registered: " .. table.concat(said, " | "))

    if handle then
        core.Registry:EnableAll()
        local settings = handle:GetSettings()
        for key, value in pairs(handle.defaults) do settings[key] = value end
        settings.rules = {}
        settings.separate = false
        settings.enabled = true
        handle:Apply()

        local function redraw() core.Events.Dispatch("UNIT_AURA", "player") end

        --- All icons of the module, shown or not.
        local function icons()
            local out = {}
            for i = 1, #frames do
                if frames[i].record ~= nil then out[#out + 1] = frames[i] end
            end
            return out
        end

        --- What the player sees: textures of the shown icons, in order.
        local function screen()
            local out = {}
            local all = icons()
            for i = 1, #all do
                if all[i].shown then
                    out[#out + 1] = tostring(all[i].regions[1].path)
                        .. "@" .. tostring(all[i].x) .. "," .. tostring(all[i].y)
                        .. "/" .. tostring(all[i].w)
                        .. ":" .. tostring(all[i].regions[2] and
                            all[i].regions[2].text)
                end
            end
            table.sort(out)
            return table.concat(out, " | ")
        end

        redraw()
        T.eq(#icons(), 40, "forty icons on screen")

        -- === Case 1: nothing changed =====================================
        --
        -- The main claim of the whole change. A redraw with nothing to change
        -- does not touch the engine at all -- neither icons nor holders.
        local before = screen()
        reset()
        redraw()

        T.eq(tally.writes, 0,
            "a redraw with no changes never writes to the engine (writes: "
            .. tostring(tally.writes) .. ")")
        T.eq(tally.built, 0, "and creates no frame at all")
        T.eq(screen(), before, "and the screen shows exactly the same")

        -- === Case 2: one stack ticked ====================================
        AURAS.HELPFUL[5][3] = 7
        reset()
        redraw()

        T.eq(touched(), 1, "a ticking stack rewrites exactly one icon "
            .. "out of forty (rewritten: " .. tostring(touched()) .. ")")
        T.eq(tally.others, 0, "and no holder: the grid did not move")
        T.eq(tally.built, 0, "and no new frame")

        -- === Case 3: one aura appeared ===================================
        --
        -- A new aura goes last: the icons before it stay in place, and there
        -- is no reason to rewrite them.
        AURAS.HARMFUL[21] = aura("HARMFUL", 21)
        reset()
        redraw()

        T.eq(touched(), 1, "an appearing aura rewrites one icon "
            .. "(rewritten: " .. tostring(touched()) .. ")")
        T.eq(#icons(), 41, "and there is one more icon on screen")

        -- === Case 4: one aura expired ====================================
        AURAS.HARMFUL[21] = nil
        reset()
        redraw()

        T.eq(touched(), 1, "an expiring aura touches one icon -- its own "
            .. "(rewritten: " .. tostring(touched()) .. ")")
        T.eq(tally.built, 0, "and no new frame")

        local hidden = 0
        local all = icons()
        for i = 1, #all do if not all[i].shown then hidden = hidden + 1 end end
        T.eq(hidden, 1, "and exactly one icon left the screen")

        -- === Pool: an icon that outlived other auras =====================
        --
        -- The pool rule got stricter, not weaker: an icon now stays on screen
        -- across dozens of updates, and it carries two tables through the
        -- pool -- the aura record and the marks of what was drawn. Both are
        -- obliged to be empty.
        local leftovers = {}
        for i = 1, #all do
            local icon = all[i]
            if not icon.shown then
                for key in pairs(icon.record or {}) do
                    leftovers[#leftovers + 1] = "record." .. tostring(key)
                end
                for name, set in pairs(icon.drawn or {}) do
                    if type(set) == "table" then
                        for key in pairs(set) do
                            leftovers[#leftovers + 1] =
                                "drawn." .. tostring(name) .. "." .. tostring(key)
                        end
                    else
                        leftovers[#leftovers + 1] = "drawn." .. tostring(name)
                    end
                end
            end
        end
        T.eq(#leftovers, 0, "an icon in the pool carries neither a record "
            .. "field nor draw marks: " .. table.concat(leftovers, ", "))

        -- And the same from the other side: an icon taken from the pool by a
        -- different aura shows that aura, not the previous one. The comparison
        -- with the marks must differ -- otherwise the icon would keep someone else's texture.
        for i = 1, 20 do AURAS.HARMFUL[i] = aura("HARMFUL", i + 100) end
        redraw()
        local stale = {}
        all = icons()
        for i = 1, #all do
            local path = all[i].shown and all[i].regions[1].path or nil
            if path and path:match("^artHARMFUL") then
                stale[#stale + 1] = path
            end
        end
        T.eq(#stale, 0, "no icon carries the texture of its previous aura: "
            .. table.concat(stale, ", "))
        fill(20)
        redraw()

        -- === Case 5: the whole set changed ===============================
        local built = #frames
        for i = 1, 20 do AURAS.HELPFUL[i] = aura("HELPFUL", i, "x") end
        for i = 1, 20 do AURAS.HARMFUL[i] = aura("HARMFUL", i, "x") end
        reset()
        redraw()

        T.eq(touched(), 40, "a full set replacement rewrites all forty "
            .. "icons (rewritten: " .. tostring(touched()) .. ")")
        T.eq(tally.built, 0,
            "and no new frame: the same icons, different contents")
        T.eq(#frames, built, "and the total number of frames is unchanged")

        -- === Case 6: a settings change ===================================
        --
        -- The converse claim, and it matters more than the previous five
        -- together: the fast path **must** be cancelled by a settings change.
        -- A setting that never reached the screen is not a slowdown, it is a break.
        settings.spacing = 9
        reset()
        handle:Apply()

        T.eq(touched(), 40, "a settings change rewrites all forty icons "
            .. "(rewritten: " .. tostring(touched()) .. ")")
        T.ok(tally.others > 0, "and the block holders move along with them")
        T.eq(tally.built, 0, "and still no new frame")

        -- The same check from the screen side: the gap really did change.
        local wide = screen()
        settings.spacing = 4
        handle:Apply()
        T.ok(screen() ~= wide, "and the screen shows a different gap")

        -- A filter change: the same path and the same answer.
        local function lit()
            local count = 0
            local list = icons()
            for i = 1, #list do if list[i].shown then count = count + 1 end end
            return count
        end

        local visible = lit()
        handle.options.args.filterMode.set(nil, "deny")
        handle.options.args.filterList.set(nil, "HELPFUL1, HELPFUL2")
        T.eq(lit(), 38, "a filter change hides the named aura at once, not later")
        T.eq(visible, 40, "(before the change there were forty icons on screen)")

        handle.options.args.filterList.set(nil, "")
        handle.options.args.filterMode.set(nil, "off")
        T.eq(lit(), 40, "and brings them back just as promptly")

        -- === Numbers =====================================================
        --
        -- Not a ceiling: the ceiling is above and it is about shape. This is
        -- a yardstick showing what the shape change bought, with all six
        -- cases named individually. The clock has millisecond resolution, so
        -- each case is run in a batch.
        local ROUNDS = 4000

        -- How many times the same work is measured, and why the smallest
        -- result is taken.
        --
        -- The real cost of work is its floor. Everything above it was added
        -- by something other than the work: another thread that got the time,
        -- a garbage collection, a cache miss. Noise only ever adds and never
        -- subtracts, so the smallest of several measurements is closer to the
        -- truth than the average — and an average is pulled up by exactly the
        -- outlier that is beside the point.
        --
        -- This was not adopted for elegance. The comparison "a repaint with
        -- no changes is twice as cheap as a full replacement" used to
        -- flicker: one run in three showed 1.9 instead of 2 and failed the
        -- suite. A guard that fires at random is not a guard but a lottery:
        -- people stop reading it, and on the day it fires for a real reason
        -- they will not believe it.
        --
        -- Three passes were not enough. The guard flickered again at a ratio
        -- of 1.97 — a one-and-a-half-per-cent margin, that is, noise in the
        -- slower of the two measurements, which gets the fewest effective
        -- repetitions. Five passes lower the chance that every pass of one
        -- work lands in a bad patch; the price is two more passes over a
        -- measurement that already takes a fraction of a second.
        --
        -- The threshold itself is untouched. Loosening it would allow that
        -- very full rebuild to come back — and it would come back silently.
        local PASSES = 5

        --- Measure several pieces of work INTERLEAVED and return the smallest
        --- of each.
        --
        -- Interleaved rather than one after another, and that is the same
        -- guard's second lesson. The smallest of several measurements removes
        -- a random outlier but does not remove a PROLONGED slump: if the
        -- machine was slow all the while the first work was measured and
        -- stopped being slow while the second was, then all of the first
        -- one's measurements are bad. A comparison of two pieces of work then
        -- compares not the work but two different minutes.
        --
        -- That is what happened: one run in five gave a ratio of 1.6 instead
        -- of 2.3, and the one that looked more expensive was not the heavier
        -- work but the one measured earlier.
        --
        -- Interleaved, a slump is shared equally by both, and their smallest
        -- results come from one good pass.
        --
        -- @param steps table array of pieces of work
        -- @param rounds number|nil how many rounds per piece of work
        -- @return table array of smallest results, in the same order
        local function costs(steps, rounds)
            local count = rounds or ROUNDS
            local best = {}

            for _ = 1, PASSES do
                for i = 1, #steps do
                    local step = steps[i]
                    step(0)
                    local started = os.clock()
                    for k = 1, count do step(k) end
                    local spent = (os.clock() - started) * 1000 / count
                    if not best[i] or spent < best[i] then best[i] = spent end
                end
            end

            return best
        end

        local function cost(step, rounds)
            return costs({ step }, rounds)[1]
        end

        fill(20)
        redraw()

        -- These two are measured together: they are what the single ceiling
        -- below compares, and they may not be measured apart.
        local pair = costs({
            function() redraw() end,
            function(k)
                local mark = (k % 2 == 0) and "a" or "b"
                for i = 1, 20 do AURAS.HELPFUL[i] = aura("HELPFUL", i, mark) end
                for i = 1, 20 do AURAS.HARMFUL[i] = aura("HARMFUL", i, mark) end
                redraw()
            end,
        })
        local quiet, swapped = pair[1], pair[2]

        local ticking = cost(function(k)
            AURAS.HELPFUL[5][3] = (k % 9) + 1
            redraw()
        end)

        local tuning = cost(function()
            settings.spacing = (settings.spacing == 4) and 5 or 4
            handle:Apply()
        end, 600)

        -- Appearing and expiring are measured apart, and they can only be
        -- separated by a long run in one direction: the clock has millisecond
        -- resolution while one redraw costs hundredths of it. So the debuff
        -- set grows from one to forty and melts back, and the clock is read
        -- once per direction.
        settings.spacing = 4
        handle:Apply()

        local SWEEPS = 200
        local growing, fading = 0, 0
        for _ = 1, SWEEPS do
            fill(1)
            redraw()

            local started = os.clock()
            for k = 2, 40 do
                AURAS.HARMFUL[k] = aura("HARMFUL", k)
                redraw()
            end
            growing = growing + (os.clock() - started)

            started = os.clock()
            for k = 40, 2, -1 do
                AURAS.HARMFUL[k] = nil
                redraw()
            end
            fading = fading + (os.clock() - started)
        end
        growing = growing * 1000 / (SWEEPS * 39)
        fading  = fading  * 1000 / (SWEEPS * 39)

        io.write(string.format(
            "  [aura redraw cost] forty icons, ms per one UNIT_AURA: "
            .. "no changes %.4f, stack ticked %.4f, aura appeared "
            .. "%.4f, aura expired %.4f, full replacement %.4f, settings change "
            .. "%.4f\n",
            quiet, ticking, growing, fading, swapped, tuning))

        -- The one number that is a ceiling after all, and it is about shape:
        -- a redraw with no changes must be **cheaper** than a full
        -- replacement. Not by percent -- by a factor. A returning full rebuild
        -- would level them, and level them silently.
        T.ok(quiet * 2 < swapped, string.format(
            "a redraw with no changes is more than twice cheaper than a full replacement "
            .. "(%.4f against %.4f ms)", quiet, swapped))

        fill(20)
        handle:Apply()
        T.eq(core.Registry:IsFailed("umbraauras"), false,
            "the module is alive after the measurement: " .. (said[#said] or ""))
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.UnitAura = saved.UnitAura
    _G.C_UnitAuras = saved.C_UnitAuras
    _G.GameTooltip = saved.GameTooltip
    _G.InCombatLockdown = saved.InCombatLockdown
    _G.RegisterAttributeDriver = saved.RegisterAttributeDriver
end
