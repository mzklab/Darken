local helpers = require("helpers")

-- The size of party and raid frames.
--
-- What this file is for. In the client this subsystem can hardly be checked
-- by eye: it takes a raid, a change of its roster and combat all at once,
-- while the owner of the layout is the game itself. So everything that can
-- be checked without the client is checked here: clamping the numbers,
-- combining size with scale, the return to native, the behaviour on a client
-- with no such frames at all, and deferring protected work to the end of combat.
--
-- The core deferral rule is checked separately: what is deferred is the pair
-- "the operation is protected AND the object answers IsProtected". An
-- unprotected frame is touched at once in combat -- otherwise the addon
-- would be sluggish for no reason, and the roster changes most often in combat.

local savedLibStub = LibStub
local savedCombatLockdown = InCombatLockdown
LibStub = function() return nil end

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Media.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Events.lua", ns)
helpers.loadAddonFile("Core/Combat.lua", ns)
helpers.loadAddonFile("Modules/UnitFrames.lua", ns)

local UF = ns.UnitFrames

-- ---------------------------------------------------------------------------
T.suite("group frames: the names live in the compatibility layer")

do
    local Compat = ns.Compat
    local FLAVORS = { "vanilla", "tbc", "mists" }

    for i = 1, #FLAVORS do
        local flavor = FLAVORS[i]
        T.ok(Compat.HasGroup(flavor, "raidframe-container"),
            flavor .. ": the group frame container is declared")
        T.ok(Compat.HasGroup(flavor, "raidframe-member"),
            flavor .. ": the member frames are declared")
        T.ok(Compat.HasGroup(flavor, "raidframe-setup"),
            flavor .. ": the layout table is declared")
        T.ok(Compat.HasGroup(flavor, "raidframe-relayout"),
            flavor .. ": the layout functions are declared")
    end

    -- There are many names -- that is an upper bound, not a fact. The
    -- existence filter decides how many there are today.
    local members = Compat.GetFrameNames("mists", "raidframe-member")
    T.ok(#members >= 45, "member names are declared with room to spare: " .. #members)

    -- A client with no compact frames at all: not a single name reaches the
    -- subsystem, and that is an ordinary answer, not a refusal.
    T.eq(#Compat.FilterExisting(members, {}), 0,
        "on a client without compact frames no names remain")

    -- And what does exist arrives in full and in declaration order.
    local present = Compat.FilterExisting(members,
        { CompactRaidFrame1 = {}, CompactPartyFrameMember2 = {} })
    T.eq(#present, 2, "the existing names arrive")
    T.eq(present[1], "CompactRaidFrame1", "and declaration order is preserved")
end

-- ---------------------------------------------------------------------------
T.suite("group frames: the numbers")

do
    T.eq(UF.ClampSize(100, 40, 160), 100, "a number within bounds passes as is")
    T.eq(UF.ClampSize(10, 40, 160), 40, "it is clamped from below")
    T.eq(UF.ClampSize(1000, 40, 160), 160, "and from above")
    T.eq(UF.ClampSize("120", 40, 160), 120, "a string holding a number is read")
    T.eq(UF.ClampSize("garbage", 40, 160), nil,
        "garbage is neither zero nor the minimum but the absence of a choice")
    T.eq(UF.ClampSize(nil, 40, 160), nil, "nothing is also the absence of a choice")
end

do
    -- The switch is off: we have no numbers at all. That is exactly what
    -- "a fresh install changes nothing" means.
    local w, h = UF.GroupNumbers({ groupSize = false, groupWidth = 120,
        groupHeight = 50 })
    T.eq(w, nil, "switched off -- there is no width")
    T.eq(h, nil, "switched off -- there is no height")

    w, h = UF.GroupNumbers({ groupSize = true, groupWidth = 120,
        groupHeight = 50 })
    T.eq(w, 120, "switched on -- the width is taken")
    T.eq(h, 50, "switched on -- the height is taken")

    w, h = UF.GroupNumbers({ groupSize = true, groupWidth = 5,
        groupHeight = 500 })
    T.eq(w, 40, "the width is clamped from below")
    T.eq(h, 80, "the height is clamped from above")

    w = UF.GroupNumbers(nil)
    T.eq(w, nil, "with no settings there are no numbers")
end

-- ---------------------------------------------------------------------------
T.suite("group frames: the game layout table")

do
    -- The main step of the subsystem: the game relays the list itself and
    -- takes the size from here. The native numbers are read once, before our first write.
    local options = { width = 72, height = 36, healthBarHeight = 10 }

    local w, h = UF.ApplySetup(options, 120, 50)
    T.eq(w, 120, "our width went into the table")
    T.eq(h, 50, "and our height")
    T.eq(options.width, 120, "the game will read our width")
    T.eq(options.height, 50, "and our height")
    T.eq(options.healthBarHeight, 10, "we do not touch the rest of the table")

    -- A second write: the native value is still remembered rather than
    -- re-read from our own number.
    UF.ApplySetup(options, 140, 60)
    local back = select(1, UF.ApplySetup(options, nil, nil))
    T.eq(back, 72, "the restore returns the native width, not our previous one")
    T.eq(options.width, 72, "and puts it back into the table")
    T.eq(options.height, 36, "together with the native height")
end

-- === Write only on a change ===
--
-- The table here belongs to the GAME (DefaultCompactUnitFrameSetupOptions),
-- and writing into a foreign table taints it: every group frame assembled
-- from these numbers is tainted from birth, and game code runs tainted on it.
-- The client log names us by name:
--
--   CompactUnitFrame.lua:1206: attempt to compare local 'maxHealth'
--   (a secret number value, while execution tainted by 'Darken')
--
-- We used to write it always -- including with the setting off, when the
-- native value is simply put back into the same table. That is a write with
-- not a single change, that is pure taint, and it came on every roster
-- change and every relay of the raid list.
--
-- Telling "wrote the same thing" from "did not write" by value is
-- impossible -- the value is identical. So the function says so outright, in a third return value.
do
    local options = { width = 72, height = 36 }

    local _, _, wrote = UF.ApplySetup(options, nil, nil)
    T.eq(wrote, false,
        "with the setting off nothing is written into the game table")

    _, _, wrote = UF.ApplySetup(options, 120, 50)
    T.eq(wrote, true, "a chosen size is written")

    _, _, wrote = UF.ApplySetup(options, 120, 50)
    T.eq(wrote, false, "the same size is not written a second time")

    _, _, wrote = UF.ApplySetup(options, 120, 60)
    T.eq(wrote, true, "a changed height is written")

    _, _, wrote = UF.ApplySetup(options, nil, nil)
    T.eq(wrote, true, "and so is the restore to native: that is a change")

    _, _, wrote = UF.ApplySetup(options, nil, nil)
    T.eq(wrote, false, "while a second restore in a row is not")
end

do
    -- A table of foreign shape: we write none of our fields into it and
    -- silently do nothing.
    local strange = { columns = 5 }
    T.eq(UF.ApplySetup(strange, 120, 50), nil,
        "a table with no sizes is none of our business")
    T.eq(strange.width, nil, "and no fields are created in it")

    T.eq(UF.ApplySetup(nil, 120, 50), nil, "no table, no work")
end

-- ---------------------------------------------------------------------------
T.suite("group frames: the size of a single frame")

--- A fake compact frame.
-- @param protected boolean whether it answers IsProtected
local function newCompact(protected, width, height)
    local frame = {
        width = width or 72,
        height = height or 36,
        scale = 1,
        sets = 0,
    }
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetSize(w, h)
        self.width, self.height = w, h
        self.sets = self.sets + 1
    end
    function frame:GetScale() return self.scale end
    function frame:SetScale(value) self.scale = value end
    function frame:IsProtected() return protected end
    return frame
end

local combat = false
InCombatLockdown = function() return combat end
ns.flavor = "mists"

do
    combat = false

    -- A fresh install: the frame is untouched, and there is no reason to touch it.
    local frame = newCompact(true)
    CompactRaidFrame1 = frame
    T.eq(UF.ApplyGroupFrame("CompactRaidFrame1", frame, nil, nil), false,
        "with no chosen size an untouched frame stays untouched")
    T.eq(frame.sets, 0, "and not a single call was made on it")

    -- A chosen size is applied.
    T.eq(UF.ApplyGroupFrame("CompactRaidFrame1", frame, 120, 50), true,
        "the chosen size was accepted")
    T.eq(frame.width, 120, "the width was applied")
    T.eq(frame.height, 50, "the height was applied")

    -- The same size a second time: there is no work.
    T.eq(UF.ApplyGroupFrame("CompactRaidFrame1", frame, 120, 50), false,
        "the same size is not assigned a second time")
    T.eq(frame.sets, 1, "there was exactly one call")

    -- The restore to native: what was there before us comes back, not our
    -- previous value.
    T.eq(UF.ApplyGroupFrame("CompactRaidFrame1", frame, nil, nil), true,
        "the restore to native was accepted")
    T.eq(frame.width, 72, "the native width came back")
    T.eq(frame.height, 36, "and the native height")

    CompactRaidFrame1 = nil
end

do
    -- No frame: an ordinary answer, not a refusal.
    T.eq(UF.ApplyGroupFrame("CompactRaidFrame1", nil, 120, 50), false,
        "a non-existent frame gives an ordinary false")
    T.eq(UF.ApplyGroupFrame("", newCompact(true), 120, 50), false,
        "a frame with no name is not taken on: there is no way to find it in the queue")
end

-- ---------------------------------------------------------------------------
T.suite("group frames: combat")

do
    -- The core rule: what is deferred is the pair "the operation is protected
    -- AND the object answers IsProtected". A protected frame in combat waits for combat to end.
    UF.Drain(UF.queue)
    combat = true

    local frame = newCompact(true)
    CompactRaidFrame1 = frame

    T.eq(UF.ApplyGroupFrame("CompactRaidFrame1", frame, 120, 50), true,
        "the work was accepted")
    T.eq(frame.width, 72, "but in combat the size of a protected frame is untouched")
    T.eq(UF.Pending(UF.queue), 1, "it waits in the queue")

    -- Ten edits in combat give one application -- the last one.
    UF.ApplyGroupFrame("CompactRaidFrame1", frame, 130, 55)
    UF.ApplyGroupFrame("CompactRaidFrame1", frame, 140, 60)
    T.eq(UF.Pending(UF.queue), 1, "a repeated write displaces the former one")

    T.eq(UF.Drain(UF.queue), 1, "leaving combat applies the deferred work")
    T.eq(frame.width, 140, "and applies the last value, not the first")
    T.eq(frame.height, 60, "for both numbers")

    CompactRaidFrame1 = nil
end

do
    -- And the converse rule: an unprotected frame is touched at once in
    -- combat. There is nothing to defer, and deferring would make the addon sluggish.
    UF.Drain(UF.queue)
    combat = true

    local frame = newCompact(false)
    CompactRaidFrame1 = frame

    UF.ApplyGroupFrame("CompactRaidFrame1", frame, 120, 50)
    T.eq(frame.width, 120, "an unprotected frame is set at once, in combat too")
    T.eq(UF.Pending(UF.queue), 0, "and the queue was not needed")

    CompactRaidFrame1 = nil
    combat = false
end

-- ---------------------------------------------------------------------------
T.suite("group frames: the whole application")

local function withSettings(settings)
    ns.Addon = { db = { profile = { unitframes = settings } } }
    return settings
end

do
    UF.Drain(UF.queue)
    combat = false

    DefaultCompactUnitFrameSetupOptions = { width = 72, height = 36 }
    CompactRaidFrame1 = newCompact(true)
    CompactRaidFrame2 = newCompact(true)
    CompactPartyFrameMember1 = newCompact(true)
    CompactRaidFrameContainer = newCompact(true)

    withSettings({
        groupSize = true, groupWidth = 120, groupHeight = 50, groupScale = 1.25,
    })
    UF:ApplyGroupFrames()

    T.eq(DefaultCompactUnitFrameSetupOptions.width, 120,
        "the number went into the table the game will build the layout from")
    T.eq(DefaultCompactUnitFrameSetupOptions.height, 50, "and the height too")
    T.eq(CompactRaidFrame1.width, 120, "the first frame got the width at once")
    T.eq(CompactRaidFrame2.height, 50, "the second got the height")
    T.eq(CompactPartyFrameMember1.width, 120, "a five-player party frame too")
    T.eq(CompactRaidFrameContainer.scale, 1.25,
        "the scale went onto the container, not onto every frame")
    T.eq(CompactRaidFrame1.scale, 1,
        "and there were no forty separate scale calls")

    -- A relay by the game: our size survives it, because the game takes it
    -- from the same table. Applying again breaks nothing.
    T.eq(UF.Reflow(), true, "the repeat after a relay went through")
    T.eq(CompactRaidFrame1.width, 120, "the size is in place")
    T.eq(CompactRaidFrame1.sets, 1, "and no extra call was made")

    -- The switch goes off: the native value comes back, not our previous one.
    withSettings({
        groupSize = false, groupWidth = 120, groupHeight = 50, groupScale = 1,
    })
    UF:ApplyGroupFrames()
    T.eq(DefaultCompactUnitFrameSetupOptions.width, 72,
        "the native width came back into the table")
    T.eq(CompactRaidFrame1.width, 72, "and the frame carries the native one too")
    T.eq(CompactRaidFrameContainer.scale, 1, "the scale returned to one")
end

do
    -- A client with no compact frames at all: a saved size means nothing, and
    -- the subsystem silently does nothing.
    UF.Drain(UF.queue)
    DefaultCompactUnitFrameSetupOptions = nil
    CompactRaidFrame1 = nil
    CompactRaidFrame2 = nil
    CompactPartyFrameMember1 = nil
    CompactRaidFrameContainer = nil

    withSettings({
        groupSize = true, groupWidth = 120, groupHeight = 50, groupScale = 1.5,
    })

    local ok = pcall(function() UF:ApplyGroupFrames() end)
    T.ok(ok, "on a client without compact frames the application passes silently")
    T.eq(UF.Pending(UF.queue), 0, "and defers nothing")
end

do
    -- Without a profile the subsystem does not work at all: it does not touch
    -- foreign frames on a guess.
    ns.Addon = nil
    CompactRaidFrame1 = newCompact(true)
    UF:ApplyGroupFrames()
    T.eq(CompactRaidFrame1.width, 72, "without a profile the frame is untouched")
    CompactRaidFrame1 = nil
end

-- ---------------------------------------------------------------------------
T.suite("group frames: the settings section")

do
    -- The group grid stands on its own tab rather than next to the scale of
    -- a single frame. Formerly they lay together, and "Group frame width" read
    -- as the width of whichever frame was selected above -- while it does not
    -- concern it at all: the grid has no unit and there is nobody to select in it.
    local args = UF.options.args.group.args

    T.eq(args.groupSize.type, "toggle", "the group size is enabled by a switch")
    T.eq(args.groupWidth.type, "range", "the width is a slider")
    T.eq(args.groupHeight.type, "range", "the height is a slider")
    T.eq(args.groupScale.type, "range", "the group scale is a slider")

    -- The difference between scale and size must be written where it is read:
    -- otherwise two similar sliders do different things silently.
    T.ok(args.groupSize.desc:find("Size changes the box") ~= nil,
        "the switch description explains the difference between size and scale")
    T.ok(args.groupSize.desc:find("180") ~= nil,
        "and says that they combine by multiplication")
    -- The explanation "why the native frames have no width" stayed with the
    -- scale of a single frame, that is on the neighbouring tab: it is read
    -- where the slider it speaks of stands.
    local size = UF.options.args.frames.args.size.args
    T.ok(size.frameNote.name:find("no width or height here") ~= nil,
        "while the native unit frames say outright why there is no width")

    -- The combat restriction is named where the player learns why the slider
    -- "did not take effect at once".
    T.ok(args.groupWidth.desc:find("combat") ~= nil,
        "the width description mentions combat")
    T.ok(args.groupScale.desc:find("combat") ~= nil,
        "and so does the group scale description")

    -- The slider bounds match the clamping in the code: a slider handing out
    -- a number outside the bounds would be lying to the player.
    T.eq(args.groupWidth.min, 40, "the lower width bound is the same as in the code")
    T.eq(args.groupWidth.max, 160, "and the upper one")
    T.eq(args.groupHeight.min, 16, "the lower height bound is the same")
    T.eq(args.groupHeight.max, 80, "and the upper one")

    -- Defaults: a fresh install imposes nothing.
    T.eq(UF.defaults.groupSize, false, "the default leaves the size to the game")
    T.eq(UF.defaults.groupScale, 1, "the default group scale is the native one")

    -- With the switch off the sliders are greyed out: the typed number is
    -- visible, and so is the fact that it has no effect.
    ns.Addon = { db = { profile = { unitframes = { groupSize = false } } } }
    T.eq(args.groupWidth.disabled(), true,
        "with the switch off the width is greyed out")
    ns.Addon = { db = { profile = { unitframes = { groupSize = true } } } }
    T.eq(args.groupHeight.disabled(), false,
        "with it on, available")
    ns.Addon = nil
end

-- ---------------------------------------------------------------------------
T.suite("group frames: a scale of one means \"leave it to the game\"")

do
    -- The scale of the raid frame container is set by the game itself, and it
    -- need not be one. So a fresh install must leave it as it is rather than
    -- level it to our one: otherwise the very first login would change the
    -- look without asking anything.
    UF.Drain(UF.queue)
    combat = false

    CompactRaidFrameContainer = newCompact(true)
    CompactRaidFrameContainer.scale = 0.9

    withSettings({ groupSize = false, groupScale = 1 })
    UF:ApplyGroupFrames()
    T.eq(CompactRaidFrameContainer.scale, 0.9,
        "a fresh install does not touch the scale set by the game")

    withSettings({ groupSize = false, groupScale = 1.4 })
    UF:ApplyGroupFrames()
    T.eq(CompactRaidFrameContainer.scale, 1.4, "the chosen scale was applied")

    withSettings({ groupSize = false, groupScale = 1 })
    UF:ApplyGroupFrames()
    T.eq(CompactRaidFrameContainer.scale, 0.9,
        "a return to one restored the game scale rather than setting one")

    CompactRaidFrameContainer = nil
    ns.Addon = nil
end

-- The client globals are cleaned up after: the following suites live in the
-- same Lua state, and a foreign frame left in _G would change them silently.
DefaultCompactUnitFrameSetupOptions = nil
CompactRaidFrame1 = nil
CompactRaidFrame2 = nil
CompactPartyFrameMember1 = nil
CompactRaidFrameContainer = nil
InCombatLockdown = savedCombatLockdown
LibStub = savedLibStub
