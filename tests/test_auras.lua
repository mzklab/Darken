local helpers = require("helpers")
local localekeys = require("localekeys")

helpers.installValidator()

-- Compact auras from a separate folder (Features/Auras).
--
-- What is checked here is what the player sees on screen, and by the same
-- code the game will load it with. What is checked falls into five parts: the
-- grid arithmetic, turning the remaining time into a label (the place the
-- module is written the way it is for), the order and the separation of our
-- own effects from foreign ones, the icon pool tally (the place where reuse
-- gives a foreign time under a foreign texture) and the reversible removal of the standard grid.
--
-- The drawing (Icon.lua) enters here exactly as far as it works without a
-- client: outside the game there is no CreateFrame, and the whole file is
-- written so that this is an absent frame rather than a breakage. The pool
-- tally does not suffer from that -- the icon builder is accepted from outside.

local MODULE = "Features/Auras"

--- Load the module files into a fresh namespace.
-- The file list and the order are taken from the module TOC rather than
-- copied here: a new module file enters the check by itself.
-- @param withRegistration boolean whether to load Auras.lua (it registers itself)
-- @return table
local function moduleNamespace(withRegistration)
    local ns = helpers.newNamespace()
    -- The module takes the aura filter from the core (contract version 7),
    -- and the door must be opened before its files are read: behind it is the real Core/AuraFilter.lua.
    local coreFilter, restore = helpers.installAuraFilter()
    helpers.loadModule(MODULE, ns, { withRegistration = withRegistration })
    restore()
    ns.coreFilter = coreFilter
    return ns
end

local ns = moduleNamespace(false)

T.suite("aura module: the grid layout")

do
    local Layout = ns.Layout
    local B = Layout.BOUNDS

    -- Garbage from the profile means the default rather than a Lua error in combat.
    T.eq(Layout.Clamp("size", "abc"), B.size.default, "a non-number gives the default")
    T.eq(Layout.Clamp("size", 0 / 0), B.size.default, "nan gives the default")
    T.eq(Layout.Clamp("perRow", -3), B.perRow.min, "below the bound gives the bound")
    T.eq(Layout.Clamp("perRow", 900), B.perRow.max, "above the bound gives the bound")
    T.eq(Layout.Clamp("spacing", 7), 7, "a usable value passes as is")

    -- The direction from the profile: an unknown word means the default.
    T.eq(Layout.Direction("upright"), "upright", "a known direction")
    T.eq(Layout.Direction("sideways"), Layout.DEFAULT_DIRECTION,
        "an unknown direction gives the default")
    T.eq(Layout.Direction(nil), Layout.DEFAULT_DIRECTION, "nothing gives the default")

    -- A fractional number per row: there is no half icon in a row.
    local size, perRow = Layout.Grid({ size = 30, perRow = 4.7 })
    T.eq(perRow, 4, "the number per row is rounded down")
    T.eq(size, 30, "the size passes as is")

    -- The anchor corner is set by the direction, in exactly one place.
    T.eq(Layout.Anchor("downleft"), "TOPRIGHT", "growth down-left anchors to the top right")
    T.eq(Layout.Anchor("upright"), "BOTTOMLEFT", "growth up-right anchors to the bottom left")

    -- The grid itself. The step is the size plus the gap; a row is filled,
    -- then the next one starts.
    local x, y = Layout.Place(1, 4, 30, 4, "downright")
    T.eq(x, 0, "the first icon stands in the corner horizontally")
    T.eq(y, 0, "and vertically")

    x, y = Layout.Place(2, 4, 30, 4, "downright")
    T.eq(x, 34, "the second icon is one step to the right")
    T.eq(y, 0, "and in the same row")

    x, y = Layout.Place(5, 4, 30, 4, "downright")
    T.eq(x, 0, "the fifth with four per row starts a new row")
    T.eq(y, -34, "and goes down by one step")

    -- The direction changes only the signs, but changes them on both axes.
    x, y = Layout.Place(5, 4, 30, 4, "upleft")
    T.eq(x, -0, "growth to the left: the first in the row is still in the corner")
    T.eq(y, 34, "while the rows go upwards")

    x, y = Layout.Place(2, 4, 30, 4, "upleft")
    T.eq(x, -34, "and the row grows to the left")

    -- Garbage in the icons-per-row number must not divide by zero.
    x, y = Layout.Place(3, 0, 30, 4, "downright")
    T.eq(x, 0, "zero per row reads as one: everything goes into a column")
    T.eq(y, -68, "the third icon is in the third row")

    -- The second block starts on a new row rather than continuing someone else's.
    T.eq(Layout.Offset(0, 4), 1, "with no own effects the foreign ones start at the first slot")
    T.eq(Layout.Offset(1, 4), 5, "one own effect takes a whole row")
    T.eq(Layout.Offset(4, 4), 5, "an exactly full row does not eat an extra one")
    T.eq(Layout.Offset(5, 4), 9, "a fifth own effect takes a second row")

    -- The size of the occupied space: the block holder is placed by it.
    local w, h = Layout.Block(0, 4, 30, 4)
    T.eq(w, 30, "an empty block does not collapse to zero")
    w, h = Layout.Block(3, 4, 30, 4)
    T.eq(w, 98, "three icons in a row of four is three widths and two gaps")
    T.eq(h, 30, "and one row tall")
    w, h = Layout.Block(5, 4, 30, 4)
    T.eq(w, 132, "five icons take a full row in width")
    T.eq(h, 64, "and two rows in height")
end

T.suite("aura module: the time label and when it changes")

do
    local Layout = ns.Layout

    -- There is nothing to show: an aura with no duration and an aura that is gone.
    local text, delay = Layout.Remaining(nil)
    T.eq(text, "", "with no duration there is no label")
    T.eq(delay, nil, "and no reason to wake up")

    text, delay = Layout.Remaining(0)
    T.eq(text, "", "an expired aura gives no label")
    T.eq(delay, nil, "nor a deadline")

    text, delay = Layout.Remaining(-5)
    T.eq(text, "", "a negative remainder is the same")

    text, delay = Layout.Remaining(0 / 0)
    T.eq(text, "", "nan gives no label")

    -- Seconds. Rounded up: while a fraction of a second remains, the next
    -- integer is shown -- a "0" on a live aura is more confusing.
    text, delay = Layout.Remaining(17)
    T.eq(text, "17", "whole seconds are written as a number")
    T.eq(delay, 1, "and hold exactly until the next integer")

    text, delay = Layout.Remaining(5.4)
    T.eq(text, "6", "a fractional remainder is rounded up")
    T.eq(math.abs(delay - 0.4) < 1e-9, true,
        "while the change deadline is exactly at 5 seconds rather than \"in a second\": " .. tostring(delay))

    text, delay = Layout.Remaining(0.2)
    T.eq(text, "1", "the last fraction of a second is still \"1\"")

    -- Minutes and hours: every unit has its own threshold.
    text, delay = Layout.Remaining(59.9)
    T.eq(text, "60", "below a minute it is still seconds")

    text, delay = Layout.Remaining(60)
    T.eq(text, "1m", "exactly a minute is written in minutes")
    T.eq(delay, 60, "and holds for the whole minute")

    text, delay = Layout.Remaining(90)
    T.eq(text, "2m", "a minute and a half is rounded up")
    T.eq(delay, 30, "while the label changes in half a minute")

    text, delay = Layout.Remaining(3600)
    T.eq(text, "1h", "exactly an hour is written in hours")

    text, delay = Layout.Remaining(3599)
    T.eq(text, "60m", "just under an hour is still minutes")

    text, delay = Layout.Remaining(7200)
    T.eq(text, "2h", "two hours")
    T.eq(delay, 3600, "and an hour until the label changes")

    -- The deadline is never zero or negative: otherwise the frame handler
    -- would wake up every frame and walk every icon -- exactly what this
    -- module does not do.
    local worst = math.huge
    for i = 1, 400 do
        local _, d = Layout.Remaining(i * 0.37)
        if d and d < worst then worst = d end
    end
    T.eq(worst > 0, true, "the label change deadline is always above zero: " .. tostring(worst))

    -- Stacks: one stack is not written.
    T.eq(Layout.Stacks(nil), "", "no stacks means no label")
    T.eq(Layout.Stacks(1), "", "one stack is not written")
    T.eq(Layout.Stacks(2), "2", "two are written")
    T.eq(Layout.Stacks(12.7), "12", "a fraction is truncated")
    T.eq(Layout.Stacks("garbage"), "", "garbage is not written")
end

T.suite("aura module: the order and separating our own from foreign ones")

do
    local Sort = ns.Sort

    -- What expires soonest first, the permanent at the tail, on an equal
    local list = {
        { order = 1, expires = 0,   mine = true  },
        { order = 2, expires = 120, mine = false },
        { order = 3, expires = 30,  mine = true  },
        { order = 4, expires = nil, mine = false },
        { order = 5, expires = 30,  mine = false },
    }
    Sort.Order(list)
    T.eq(list[1].order, 3, "first comes what will expire sooner")
    T.eq(list[2].order, 5, "on an equal duration, in the game order")
    T.eq(list[3].order, 2, "then what will expire later")
    T.eq(list[4].order, 1, "the permanent goes to the tail")
    T.eq(list[5].order, 4, "and a nil also reads as \"no duration\"")

    -- The split: ours and foreign, each list ordered by its own rule.
    local own, others = Sort.Split(list)
    T.eq(#own, 2, "there are two of ours")
    T.eq(#others, 3, "and three foreign ones")
    T.eq(own[1].order, 3, "among ours the most urgent comes first")
    T.eq(own[2].order, 1, "our permanent one is at the tail of ours")
    T.eq(others[1].order, 5, "among the foreign ones the most urgent comes first")

    -- The answer tables are reused and cleared entirely: the tail of a
    -- previous list on screen is auras that no longer exist.
    local ownBuf, otherBuf = {}, {}
    Sort.Split(list, ownBuf, otherBuf)
    T.eq(#ownBuf, 2, "the first split went into its own buffer")

    Sort.Split({ { order = 9, expires = 5, mine = false } }, ownBuf, otherBuf)
    T.eq(#ownBuf, 0, "the buffer of ours was cleared rather than appended to")
    T.eq(#otherBuf, 1, "and the foreign buffer holds exactly the new aura")
    T.eq(otherBuf[1].order, 9, "that very one")

    -- Garbage instead of a list does not break the split.
    local a, b = Sort.Split(nil)
    T.eq(#a, 0, "with no list there are none of ours")
    T.eq(#b, 0, "and none foreign")

    -- A non-table record is skipped rather than breaking the walk.
    a, b = Sort.Split({ "garbage", { order = 1, mine = true } })
    T.eq(#a, 1, "the usable record was read")
    T.eq(#b, 0, "while the garbage went nowhere")
end

T.suite("aura module: the icon pool carries nothing from the previous aura")

do
    local Icon = ns.Icon

    -- Outside the game there is no CreateFrame, so a table with the same
    -- fields serves as the icon. The real pool tally is checked rather than a
    -- likeness of it: the builder is accepted from outside precisely for that.
    local built = 0
    local function build()
        built = built + 1
        local written = {}
        local function writer(key)
            return function(_, value) written[key] = value end
        end
        return {
            record = {},
            written = written,
            texture   = { SetTexture = writer("texture") },
            timeText  = { SetText = writer("time") },
            countText = { SetText = writer("count") },
            cooldown  = {
                SetCooldown = function(_, start, duration)
                    written.cooldownStart = start
                    written.cooldownDuration = duration
                end,
                Clear = function() written.cooldownCleared = true end,
            },
            ClearAllPoints = function(self) written.cleared = true end,
            Hide = function() written.hidden = true end,
            Show = function() written.shown = true end,
        }
    end

    local pool = Icon.NewPool(build)
    T.eq(#pool.free, 0, "a fresh pool is empty")

    local first = Icon.Acquire(pool, nil)
    T.eq(built, 1, "the first icon was built")
    T.eq(pool.built, 1, "and counted")

    -- The icon shows an aura with everything an aura can have.
    Icon.SetAura(first, {
        order = 3, name = "Blessing", icon = "texture",
        count = 5, duration = 300, expires = 1000, mine = true,
    }, true, true)

    T.eq(first.record.name, "Blessing", "the record knows the aura")
    T.eq(first.record.expires, 1000, "and its expiry")
    T.eq(first.written.count, "5", "the stacks are written")
    T.eq(first.written.texture, "texture", "the texture is set")
    T.eq(first.written.cooldownStart, 700, "the cooldown was started from the aura start")

    -- The countdown adds a field the record did not have at birth: exactly
    -- such a field is what a list of fields in the wipe would forget.
    first.record.due = 12345
    Icon.SetTime(first, "17")
    T.eq(first.written.time, "17", "the time is written")

    Icon.Release(pool, first)

    T.eq(#pool.free, 1, "the icon returned to the pool")
    T.eq(first.written.hidden, true, "hidden")
    T.eq(first.written.cleared, true, "and unanchored: a left anchor would drag it along with the holder")
    T.eq(first.written.texture, nil, "the texture is removed")
    T.eq(first.written.time, "", "the time label is erased")
    T.eq(first.written.count, "", "and so is the stack label")
    T.eq(first.written.cooldownCleared, true, "the cooldown is cleared")

    -- The main thing: not a single field is left on the record. It is checked
    -- by iteration rather than by a list of names -- otherwise the check would
    -- forget a field at exactly the moment the wipe did.
    local leftovers = {}
    for key in pairs(first.record) do leftovers[#leftovers + 1] = tostring(key) end
    T.eq(#leftovers, 0,
        "nothing is left on the record of the returned icon: "
        .. table.concat(leftovers, ", "))

    -- The very same icon is handed out again -- and comes out empty.
    local again = Icon.Acquire(pool, nil)
    T.eq(again, first, "the pool handed out the same frame")
    T.eq(built, 1, "and built nothing anew")
    T.eq(next(again.record), nil, "while the record on it is empty")

    -- A new aura with no stacks and no duration must show neither of them
    -- from the previous one.
    Icon.SetAura(again, { order = 1, name = "Mark", icon = "another" },
        true, true)
    T.eq(again.record.expires, nil, "the new aura has no expiry")
    T.eq(again.record.name, "Mark", "and its name is its own")
    T.eq(again.written.count, "", "the stacks of the previous aura are not visible")
    T.eq(again.written.cooldownCleared, true, "nor the cooldown of the previous one")

    -- A disabled time label leaves no foreign digits on the icon.
    Icon.SetAura(again, { order = 1, expires = 50, duration = 60 }, false, false)
    T.eq(again.record.timed, false, "the time is switched off by the setting")

    -- Garbage instead of an icon or a pool breaks nothing.
    Icon.Release(pool, nil)
    Icon.Release(nil, again)
    Icon.SetAura(nil, {}, true, true)
    Icon.SetTime(nil, "1")
    T.eq(Icon.Acquire(nil, nil), nil, "with no pool no icon can be handed out")
    T.eq(type(Icon.Wipe("garbage")), "string", "wiping a non-table does nothing")
end

T.suite("aura module: the standard grid is removed reversibly")

do
    local Grid = ns.Grid

    -- The names and the objects come from the core as one pair (contract 18),
    -- while the filtering goes by object: what this client does not have does
    -- not exist. The names here are invented deliberately: the module no
    -- longer has a list of foreign names of its own, and creating one in a check would bring back exactly what was removed.
    --
    -- The object is taken from the door rather than looked up by name in _G,
    -- and that shows here: there are no globals with such names at all, yet
    -- the grid is found. A name in a group is sometimes a path inside a foreign frame, and a lookup by name would give nil.
    local candidates = { "FirstGrid", "SecondGrid", "ThirdGrid" }
    local objects = { {}, false, {} }
    local names, frames = Grid.Names(candidates, objects)
    T.eq(#names, 2, "only the names that exist in the client were found")
    T.eq(names[1], "FirstGrid", "and in the order they were named in")
    T.eq(#frames, 2, "and there are as many frames as names")
    T.eq(frames[1], objects[1], "and they are the very objects from the core")
    T.eq(frames[2], objects[3], "including the second one, past a gap")

    T.eq(#Grid.Names(candidates, nil), 0, "with no objects from the core there are no names")

    -- A client with no such windows at all: the core returns an empty list and
    -- there is nothing to remove. It has no list of its own from which the
    -- module "would find something anyway".
    T.eq(#Grid.Names({}, objects), 0, "the core named not a single name")
    T.eq(#Grid.Names(nil, objects), 0, "and with no names from the core, nothing either")

    -- A game frame: the parent, the shown state and the calls made on it.
    local function gameFrame(parent, shown)
        local frame = { parent = parent, shown = shown }
        frame.GetParent = function(self) return self.parent end
        frame.IsShown   = function(self) return self.shown end
        frame.SetParent = function(self, value) self.parent = value end
        frame.Hide      = function(self) self.shown = false end
        frame.Show      = function(self) self.shown = true end
        return frame
    end

    local uiparent = { name = "UIParent" }
    local holder   = { name = "the hidden holder" }

    local buffs   = gameFrame(uiparent, true)
    local enchant = gameFrame(uiparent, false)

    local state = Grid.NewState()
    T.eq(state.count, 0, "the tally is empty")

    T.eq(Grid.Take(state, buffs, holder), true, "the grid was taken")
    T.eq(Grid.Take(state, enchant, holder), true, "and so were the temporary enchants")
    T.eq(state.count, 2, "and both are recorded")

    T.eq(buffs.parent, holder, "the grid moved to the hidden holder")
    T.eq(buffs.shown, false, "and is hidden")

    -- A repeated call does not overwrite the record: otherwise the holder
    -- would become the "former parent" and the restore would return the frame to nowhere.
    T.eq(Grid.Take(state, buffs, holder), false, "a repeated removal does nothing")
    T.eq(Grid.Held(state, buffs).parent, uiparent,
        "and the former parent in the record stayed the real one")

    -- The restore. A frame hidden by the player themselves must stay hidden:
    -- exactly the state that was recorded is restored.
    T.eq(Grid.Restore(state), 2, "both frames came back")
    T.eq(buffs.parent, uiparent, "the grid returned to its parent")
    T.eq(buffs.shown, true, "and is shown, because it was shown")
    T.eq(enchant.parent, uiparent, "the temporary enchants came back too")
    T.eq(enchant.shown, false, "but they were not shown and are not shown")

    T.eq(state.count, 0, "the tally is empty after the restore")
    T.eq(Grid.Held(state, buffs), nil, "and nothing is recorded against us")
    T.eq(Grid.Restore(state), 0, "a repeated restore has nothing to restore")

    -- Garbage does not break the tally.
    T.eq(Grid.Take(nil, buffs, holder), false, "with no tally nothing can be taken")
    T.eq(Grid.Take(state, nil, holder), false, "and there is nothing to take")
    T.eq(Grid.Restore(nil), 0, "with no tally there is nothing to restore")
end

T.suite("aura module: registering in the core")

do
    -- The core is assembled for real and exposed as a global -- exactly as a
    -- separate addon sees it in the game.
    local saved = {
        Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        UnitAura = _G.UnitAura, C_UnitAuras = _G.C_UnitAuras,
        BuffFrame = _G.BuffFrame, GetTime = _G.GetTime,
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

    -- The client: the player auras and the standard grid.
    _G.SlashCmdList = {}
    _G.GetTime = function() return 1000 end
    _G.C_UnitAuras = nil
    local AURAS = {
        HELPFUL = {
            { "Ours", "icon1", 3, nil, 60, 1030, "player" },
            { "Foreign", "icon2", 1, nil, 0,  0,    "party1" },
        },
        HARMFUL = {
            { "Poison", "icon3", 2, nil, 20, 1010, "target" },
        },
    }
    _G.UnitAura = function(unit, index, filter)
        local list = AURAS[filter]
        local aura = list and list[index]
        if not aura then return nil end
        return aura[1], aura[2], aura[3], aura[4], aura[5], aura[6], aura[7]
    end

    -- A trap for the irreversible way of removing the grid.
    -- UnregisterAllEvents removes it reliably and forever: the engine does not
    -- let you list back what the frame was subscribed to, and a module that
    -- "switches off" that way does not give the player their interface back until a reload.
    local unregistered = false
    _G.BuffFrame = {
        parent = "UIParent", shown = true,
        GetParent = function(self) return self.parent end,
        IsShown   = function(self) return self.shown end,
        SetParent = function(self, value) self.parent = value end,
        Hide      = function(self) self.shown = false end,
        Show      = function(self) self.shown = true end,
        UnregisterAllEvents = function() unregistered = true end,
    }

    local module = moduleNamespace(true)

    local handle = core.Registry:Get("umbraauras")
    T.ok(handle ~= nil, "the module is registered: " .. table.concat(said, " | "))

    if handle then
        T.eq(handle.api, 16, "the module declares contract version sixteen")

        local settings = handle:GetSettings()
        T.eq(type(settings), "table", "the module settings live in the core profile")

        -- The default: off. A fresh install changes nothing on screen.
        T.eq(handle.defaults.enabled, false, "a fresh install draws nothing")
        T.eq(handle.defaults.direction,
            module.Layout.Direction(handle.defaults.direction),
            "the direction default comes from the same list as the check")

        core.Registry:EnableAll()
        T.eq(core.Registry:IsEnabled(handle), true, "the module works")

        -- The settings section: the level lives in arg.level and only there.
        local args = handle.options and handle.options.args or {}
        -- There are no position sliders any more: the grid is placed by the core mover.
        T.eq(args.offsetX, nil, "there is no horizontal position slider")
        T.eq(args.offsetY, nil, "nor a vertical one")

        -- The slider bounds are taken from the same table as the value
        -- clamping: two lists of bounds would diverge silently.
        T.eq(args.perRow.min, module.Layout.BOUNDS.perRow.min,
            "the lower slider bound is the same as the clamping one")
        T.eq(args.size.max, module.Layout.BOUNDS.size.max,
            "and so is the upper one")

        -- Every default is reachable: a value from the profile must be in the
        -- selection list, otherwise the player cannot get back what they started with.
        local values = args.direction.values()
        T.ok(values[handle.defaults.direction] ~= nil,
            "the direction default is in the selection list")
        for name in pairs(module.Layout.DIRECTIONS) do
            T.ok(values[name] ~= nil, "the direction is in the list: " .. name)
        end

        -- The subscriptions go through the core: the module has no receiver of its own.
        T.eq(core.Events.Count("UNIT_AURA"), 1, "the module listens for aura changes")
        T.eq(core.Events.Count("PLAYER_ENTERING_WORLD"), 1, "and for entering the world")

        -- The command word is taken through the contract rather than written
        -- into SlashCmdList by hand: two modules with one word would displace each other silently.
        T.eq(core.CommandWords["auras"], "umbraauras",
            "the command word is recorded against the module")
        -- The word has no chat command of its own: it is the second word of
        -- the single addon command. What is checked here is that the parser
        -- knows it rather than it being executed: executing it toggles the
        -- setting, and the checks below would get a different state.
        T.eq(core.RunModuleCommand("nosuchword", ""), false,
            "an unknown word does not belong to the parser")

        -- While the module is off, the standard grid is untouched.
        T.eq(_G.BuffFrame.shown, true, "a disabled module does not touch the grid")

        -- Enabling: the grid goes away.
        args.enabled.set(nil, true)
        T.eq(handle:GetSettings().enabled, true, "the value went into the profile")
        T.eq(_G.BuffFrame.shown, false, "the standard grid was removed")
        T.eq(unregistered, false,
            "and removed reversibly rather than by unsubscribing the frame from events")
        T.eq(module.Grid.Held(nil, _G.BuffFrame), nil,
            "while the tally of what was taken is our own, and holds nothing foreign")

        -- The whole event path runs without error and without a client: there
        -- are no frames, so there are no icons, but there is no failure either.
        core.Events.Dispatch("UNIT_AURA", "player")
        core.Events.Dispatch("UNIT_AURA", "target")
        core.Events.Dispatch("PLAYER_ENTERING_WORLD")
        T.eq(core.Registry:IsEnabled(handle), true,
            "the whole event path ran without error")

        -- Switching off restores the standard grid at once, with no interface
        -- reload. That is a spec requirement and the main reason the removal is
        -- done as a move with a record.
        args.enabled.set(nil, false)
        T.eq(_G.BuffFrame.shown, true, "the standard grid came back")
        T.eq(_G.BuffFrame.parent, "UIParent", "and to its former parent")

        -- The command toggles the same setting by the same path.
        core.RunModuleCommand("auras", "")
        T.eq(handle:GetSettings().enabled, true, "the command enabled the display")
        T.eq(_G.BuffFrame.shown, false, "and the grid is removed again")
        core.RunModuleCommand("auras", "")
        T.eq(handle:GetSettings().enabled, false, "and disabled it again")
        T.eq(_G.BuffFrame.shown, true, "while the grid is back in place")

        -- The core disabling the module gives the player their grid back too:
        -- otherwise a failed module would take it away until a reload.
        core.RunModuleCommand("auras", "")
        T.eq(_G.BuffFrame.shown, false, "the grid was removed before the disabling")
        core.Registry:Disable("umbraauras", "a disable check")
        T.eq(_G.BuffFrame.shown, true,
            "a module disabled by the core gave the standard grid back")
        T.eq(core.Events.Count("UNIT_AURA"), 0,
            "and stopped listening")
    end

    for key, value in pairs(saved) do _G[key] = value end
end

-- The file list of a part and its place in the addon TOC are checked by one
-- suite for every part -- tests/test_moduletoc.lua. Formerly that check stood
-- here: the part had a TOC of its own and answered for it itself.

T.suite("aura module: the translations")

do
    -- The English string is the key. A translation that stopped being found
    -- looks like an English label in a Russian window, and that cannot be
    -- found by eye: the keys are collected from the source by parsing rather than copied here.
    local text = localekeys.read("Features/Auras/Auras.lua")
    local keys = localekeys.literal(text)
    T.ok(#keys > 10, "the translation keys were collected from the source: " .. tostring(#keys))


    for _, locale in ipairs({ "ruRU", "ukUA" }) do
        local strings = ns.Strings and ns.Strings[locale]
        T.eq(type(strings), "table", "the translation table exists: " .. locale)

        if type(strings) == "table" then
            for _, key in ipairs(keys) do
                T.ok(strings[key] ~= nil,
                    locale .. ": translated \"" .. key:sub(1, 40) .. "\"")
            end

            -- And conversely: an extra key in a translation is a string that
            -- has already been renamed in the source and forgotten here.
            local known = {}
            for _, key in ipairs(keys) do known[key] = true end
            for key in pairs(strings) do
                T.ok(known[key] == true,
                    locale .. ": extra key \"" .. tostring(key):sub(1, 40) .. "\"")
            end
        end
    end
end

helpers.removeValidator()
