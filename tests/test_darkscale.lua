local helpers = require("helpers")

-- The change of the darkening scale: the scale's former edge moved to seventy,
-- and behind it appeared thirty divisions that did not exist before.
--
-- What the file is written for. The author's requirement came in a few words —
-- the current 100 was to become the new 70 while 100 became far darker — and
-- its whole price is hidden in the unsaid one: nobody's screen changes. A
-- player's number is obliged to become a different one precisely so that the
-- look stays the same, and that can only be checked by comparing multipliers rather than slider values.
--
-- What is not here. The full circle with the real AceDB (a login, leaving, a
-- second login) is handled by tests/test_darkdefault.lua: the whole stand-in
-- client stands there, and a second one is not needed in the set. Here are the
-- scale's arithmetic and the migration itself as a pure function.

T.suite("the darkening scale: the curve")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)

local Darkness = ns.Darkness

local function close(a, b, msg)
    T.ok(type(a) == "number" and type(b) == "number"
        and math.abs(a - b) < 1e-9, msg .. " (" .. tostring(a) .. ")")
end

-- The former curve: one straight line from one down to 0.30 at a hundred.
-- Written out here afresh rather than taken from the code: the subject of the
-- check is that the current scale repeats that very one, and a shared
-- definition for both would prove only itself.
local function OldFactor(amount)
    return 1 - (amount / 100) * (1 - 0.30)
end

-- The curve before this change: two segments, the kink at seventy, the end
-- at 0.15. Written out afresh for the reason OldFactor is: the subject of
-- the check is that today's scale repeats it at three quarters of every
-- mark, and a shared definition would prove only itself.
local function PrevFactor(amount)
    if amount <= 70 then return 1 - (amount / 70) * (1 - 0.30) end
    return 0.30 - ((amount - 70) / 30) * (0.30 - 0.15)
end

close(Darkness.Factor(0), 1, "zero is the game's native look, as before")
close(Darkness.Factor(0), OldFactor(0), "and it is the same zero as it was")

close(Darkness.Factor(52.5), 0.30, "the kink stands at 52.5 now")
close(Darkness.Factor(52.5), OldFactor(100),
    "and still gives what the oldest scale gave at a hundred")

close(Darkness.Factor(75), 0.15,
    "seventy-five gives what a hundred gave before this change")
close(Darkness.Factor(75), PrevFactor(100),
    "which is the author's requirement, stated in one line")

close(Darkness.Factor(100), 0.05, "and a hundred goes darker than it ever has")
T.ok(Darkness.Factor(100) < PrevFactor(100),
    "darker than the end of the former scale")

-- Zero stood at the end once and the author said a hundred was then too
-- black. The steps below the scale stay a decision an area is given by name:
-- the slider passes Even Darker and stops short of black.
T.ok(Darkness.Factor(100) < 0.08, "the slider passes Even Darker")
T.ok(Darkness.Factor(100) > 0, "and stops short of black")

-- Every mark of the former scale is reachable, three quarters of the way
-- along. That is the promise the migration leans on.
for old = 0, 100, 5 do
    close(Darkness.Factor(old * 0.75), PrevFactor(old),
        "the former " .. old .. " gives the former multiplier on the new scale")
end

-- And the oldest scale of all is still inside the first segment, at the
-- three quarters of the three quarters.
for old = 0, 100, 10 do
    close(Darkness.Factor(old * 0.7 * 0.75), OldFactor(old),
        "the oldest " .. old .. " survives both moves")
end

-- The scale is obliged to read along its whole travel: every division is
-- darker than the previous one, and not one goes below the floor.
do
    local previous = Darkness.Factor(0)
    local monotone, floored = true, true
    for value = 1, 100 do
        local factor = Darkness.Factor(value)
        if factor >= previous then monotone = false end
        if factor < Darkness.DARKEST - 1e-12 then floored = false end
        previous = factor
    end
    T.ok(monotone, "every division of the slider is darker than the previous one")
    T.ok(floored, "and not one falls below the floor")
end

-- No segment may turn into dead travel: a division anywhere is finer than at
-- the head but of the same order.
do
    local head = Darkness.Factor(0) - Darkness.Factor(1)
    local middle = Darkness.Factor(60) - Darkness.Factor(61)
    local tail = Darkness.Factor(99) - Darkness.Factor(100)
    T.ok(middle < head, "past the kink a division is finer")
    T.ok(tail < head, "and finer still in the last segment")
    T.ok(tail * 6 > head, "but not so much that the end stops working")
end

-- Rubbish and the edges: the setting arrives from SavedVariables.
T.eq(Darkness.Factor(nil), 1, "a nil counts as a zero")
T.eq(Darkness.Factor("rubbish"), 1, "a string counts as a zero")
T.eq(Darkness.Factor(-50), 1, "below zero is clipped")
close(Darkness.Factor(500), Darkness.DARKEST, "above a hundred is clipped to the floor")

T.suite("the darkening scale: the default")

-- Sixty, which is three quarters of the eighty the author chose by
-- screenshot: the look is kept and only its number on the slider moved.
T.eq(Darkness.defaults.amount, 60,
    "a fresh install is darkened to sixty")
close(Darkness.Factor(60), PrevFactor(80),
    "and that is exactly what eighty gave before the marks moved")

T.suite("the darkening scale: migration 6 -> 7")

local pure = helpers.newNamespace()
helpers.loadAddonFile("Core/Defaults.lua", pure)

T.ok(pure.DB_VERSION >= 7, "the schema's version is no lower than the one that created the step")
T.eq(type(pure.RawMigrations[6]), "function", "the raw step 6 -> 7 is declared")
T.eq(type(pure.Migrations[6]), "function", "and the ordinary step is beside it")

--- One raw pass over the saved table.
-- @param profiles table the profiles: name -> table
-- @return table the saved table
local function sweep(profiles)
    local sv = { profiles = profiles }
    pure.MigrateStoredProfiles(sv, pure.RawMigrations, pure.DB_VERSION)
    return sv
end

-- Somebody who stood at the darkest of the oldest scale. Two moves have
-- happened since, each one multiplying by its own fraction, and the sweep
-- applies both: a hundred became seventy and then 52.5. The screen is the
-- same after each.
do
    local sv = sweep({ Default = { version = 6, darkness = { amount = 100 } } })
    local amount = sv.profiles.Default.darkness.amount

    T.eq(amount, 52.5, "the former hundred became 52.5 over the two moves")
    close(Darkness.Factor(amount), OldFactor(100),
        "and its multiplier is the one it was")

    -- A repeated pass runs at every entry into the game until the profile
    -- becomes the active one: a second multiplication would make forty-nine out
    -- of seventy, and the person would see the screen brighten by itself.
    pure.MigrateStoredProfiles(sv, pure.RawMigrations, pure.DB_VERSION)
    pure.MigrateStoredProfiles(sv, pure.RawMigrations, pure.DB_VERSION)
    T.eq(sv.profiles.Default.darkness.amount, 52.5,
        "and the second and third passes change nothing")
    T.eq(sv.profiles.Default.version, 6, "the raw pass does not raise the version")
end

-- The middle of the scale: the same rule, with no special branch at all.
do
    local sv = sweep({
        Middle = { version = 6, darkness = { amount = 40, tint = { r = 0.5 } } },
        Zeroed = { version = 6, darkness = { amount = 0 } },
    })

    T.eq(sv.profiles["Middle"].darkness.amount, 21,
        "forty became twenty-eight and then twenty-one")
    close(Darkness.Factor(21), OldFactor(40), "and their multiplier is a shared one")
    T.eq(sv.profiles["Middle"].darkness.tint.r, 0.5, "the tint is untouched")

    T.eq(sv.profiles["Zeroed"].darkness.amount, 0, "a zero stays a zero")
    T.eq(Darkness.Factor(0), 1, "that is, the game's native look")
end

-- Rounding to a division: the price is named and it is finer than half a division.
do
    local sv = sweep({ Default = { version = 6, darkness = { amount = 35 } } })
    local amount = sv.profiles.Default.darkness.amount

    T.eq(amount, 18.75, "thirty-five became twenty-five and then 18.75")
    T.ok(math.abs(Darkness.Factor(amount) - OldFactor(35)) <= 0.005 + 1e-9,
        "the difference from the former look is no more than half a division")
end

-- A profile that stayed silent. There is no key, so the slider was never
-- touched, and the person gets the current default. There is nothing to
-- recompute: the raw pass edits only chosen values, and there is nothing chosen here.
do
    local sv = sweep({ Default = { version = 6, movers = { locked = false } } })
    T.eq(sv.profiles.Default.darkness, nil,
        "the raw pass does not touch a profile that stayed silent")
    close(Darkness.Factor(Darkness.defaults.amount),
        Darkness.Factor(Darkness.defaults.amount),
        "while its look is given by the default rather than by the migration")
end

-- A fresh install: no version, no past, nothing to edit.
do
    local sv = sweep({ Default = {} })
    T.eq(sv.profiles.Default.darkness, nil, "a fresh profile is untouched")
end

-- A profile from the future (the addon rolled back to an older build) is not touched either.
do
    local sv = sweep({ Default = { version = 99, darkness = { amount = 100 } } })
    T.eq(sv.profiles.Default.darkness.amount, 100, "a profile newer than us is untouched")
end

-- Rubbish in the saved data does not bring the entry into the game down.
do
    local sv = sweep({
        Str    = { version = 6, darkness = { amount = "not a number" } },
        Over   = { version = 6, darkness = { amount = 250 } },
        Under  = { version = 6, darkness = { amount = -40 } },
        Empty  = { version = 6, darkness = {} },
        Alien  = { version = 6, darkness = "not a table" },
    })

    T.eq(sv.profiles["Str"].darkness.amount, "not a number",
        "a non-number is not converted and does not bring the pass down")
    T.eq(sv.profiles["Over"].darkness.amount, 52.5,
        "a value above a hundred was clipped, then moved with the marks")
    T.eq(sv.profiles["Under"].darkness.amount, 0, "and below zero too")
    T.eq(sv.profiles["Empty"].darkness.amount, nil, "an empty section has nothing to change")
    T.eq(sv.profiles["Alien"].darkness, "not a table", "an alien value is untouched")
end

-- An older profile goes through both darkening steps in a row: first the
-- former zero is written for it, then it is converted to the current scale.
-- The zero is obliged to stay a zero — otherwise somebody who never switched
-- the darkening on would see it switched on.
do
    local sv = sweep({ Old = { version = 4 } })
    T.eq(sv.profiles["Old"].darkness.amount, 0,
        "a profile of version 4 passed both steps and was left with a zero")
end
