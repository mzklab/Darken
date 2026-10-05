local ADDON, ns = ...

-- The numbers a player reads: rounding to an integer, abbreviating a large
-- value and a share in per cent. The core exposes these through
-- Darken:GetFormat() (contract version 12; rounding was added in version 13,
-- docs/module-api.md).
--
-- === Why this lives in the core ===
--
-- The rule for "how to write 12,437 in a label fifty pixels wide" was written
-- in the addon twice: by the bar texts (Modules/Texts.lua) and by the info
-- panel's cells (Features/InfoPanel/Format.lua). Both were careful, both
-- carried a comment, and neither knew about the other — so the health bar
-- wrote "12.4k" while the cell below it wrote "12k", and the same 999,999
-- became "1.0m" for one and "1000.0k" for the other: the same value, three
-- characters longer and in different units.
--
-- The divergence was reconciled while sorting out the world family, but it had
-- to be reconciled by copying: the contract exposed no formatting rule at all,
-- and a module in a separate folder has no other way. A copy reconciled by
-- hand is not a solution but a deferred divergence: the next change to a
-- threshold will land in one of the two places, and land silently.
--
-- This is the fifth time the project has found one piece of knowledge written
-- in several places: before the numbers it was frame names, the shared aura
-- filter, case folding and case raising. The answer is the same every time:
-- the knowledge lives in the core, one door leads out, and no copies remain at
-- all — which is verified by function identity rather than by comparing
-- answers.
--
-- === Whose rule was taken ===
--
-- The health bar's rule, to the letter. Not because it is better by some
-- abstract measure, but because it is the one the player sees every fight and
-- the one their eye is used to. A reconciliation that changes the number on
-- the bar is a visible change of behaviour, and selling that as polish is not
-- allowed.
--
-- === What is not here ===
--
-- Not one call into the game, not one subscription, not one line of
-- translation. Both functions are pure: numbers in, a string and a number out.
-- That is exactly why they are tested outside the client, and exactly why
-- rounding errors are caught here — the one kind of error formatting
-- actually has.

local Format = {}
ns.Format = Format

-- Abbreviation thresholds. Three numbers, each of them named.
--
--   THOUSAND      — from a thousand up the number goes to "k". Below that
--                   there is nothing to abbreviate: "999" is shorter than
--                   "1.0k", and more precise.
--   MILLION       — the divisor for "m".
--   MILLION_FLOOR — the crossover into "m", and it deliberately is not a
--                   million. "%.1f" rounds, so 999,999 / 1000 gives
--                   "1000.0k": the same thing as "1.0m", only three
--                   characters longer and in units the number no longer has.
--                   The threshold accounts for that rounding — exactly where
--                   "%.1fk" stops being honest.
local THOUSAND      = 1000
local MILLION       = 1000000
local MILLION_FLOOR = 999500

--- Whether this is a number one can compute with.
-- NaN equals itself only by definition, and infinity comes out of a division
-- somebody did not check. Both reach this point alive: the values come from
-- the game and from SavedVariables.
-- @param value any
-- @return boolean
local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

--- Rounding to an integer: a half moves away from zero.
--
-- === One rule, not two ===
--
-- "Symmetric about zero" and "half away from zero" are not two roundings but
-- one, named from two sides. Symmetry is the requirement
-- Round(-x) == -Round(x); the only formulation that satisfies it while not
-- rounding halves to even is the one that moves a half away from zero. That
-- is exactly why the surface exposes one name rather than a pair: a second
-- name would promise a difference that does not exist, and the first author
-- to meet them would choose by coin toss.
--
-- This can be checked without argument: the body that lived in the info panel
-- "for the frame rate's sake" matched this one line for line. It was not the
-- rules that diverged — it was the places they were written in.
--
-- === How it differs from math.floor(v + 0.5) ===
--
-- math.floor(v + 0.5) is the usual way to write rounding, and on
-- non-negative numbers it is correct. On negative ones it lies not
-- "sometimes" but always when the fraction is exactly a half: -2.5 + 0.5 =
-- -2.0, floor gives -2, so the half moved up, while for +2.5 the same half
-- moves down (to 3). The sign then stops being a factor:
-- round(-x) ~= -round(x).
--
-- That is a rule too rather than a bug — but a different one: "half towards
-- the larger number". It lives in exactly one place in the addon, and not
-- here: grid snapping (Modules/Movers.lua, Movers.Snap) chose it deliberately
-- and wrote down why — grid nodes must attract equally to the left and to the
-- right of zero, or an element dragged across the centre of the screen would
-- jump a step. The snapping rule belongs to snapping and is written where
-- that decision is made — exactly as clamping a percentage at zero belongs to
-- the panel's cell rather than to writing the number.
--
-- === Garbage on input ===
--
-- A non-number, NaN and infinity give zero rather than a Lua error or nil:
-- values arrive here from the game, and the rounding stands in a label that
-- has no room for the absence of an answer. Whoever needs to tell "zero" from
-- "nothing to round" checks the input on their side, where it is visible.
--
-- @param value number|nil
-- @return number an integer
function Format.Round(value)
    local number = tonumber(value)
    if not finite(number) then return 0 end

    if number >= 0 then return math.floor(number + 0.5) end
    return -math.floor(-number + 0.5)
end

--- Write a number as an integer: "12437", "-12".
--
-- Two decisions here, both decisions rather than the only possible way:
--
--   1. the fraction is truncated towards zero rather than rounded. That is
--      how the bar text wrote it, and that is what the player has in front of
--      them. Fractional values never occur here anyway — neither health,
--      power, experience nor reputation arrives fractional — so the
--      difference between truncation and rounding is unreachable by anything
--      but a direct call;
--   2. the sign stands outside "%d" rather than inside: inside it would give
--      "-0" for a value between minus one and zero.
--
-- The name is not exposed: on the contract's surface the numbers are Round,
-- Abbreviate and Percent, and "write as an integer" is not among them. Its
-- callers are its neighbours in the core — the bar text (Modules/Texts.lua)
-- and the below-a-thousand case of the abbreviation, right here. The bar text
-- used to keep a second body of this: it matched this one on every number, so
-- comparing answers stayed silent, and they would have diverged the day one
-- of the two was edited.
--
-- A non-number gives "0" rather than a Lua error: the call stands in a label
-- that has no room for the absence of an answer, and it is the same decision
-- as Format.Round's.
--
-- @param value number|nil
-- @return string
local function whole(value)
    local number = tonumber(value)
    if not finite(number) then return "0" end

    if number < 0 then
        return "-" .. string.format("%d", math.floor(-number))
    end
    return string.format("%d", math.floor(number))
end
ns.WholeNumber = whole

--- Abbreviate a large number: 12437 -> "12.4k".
--
-- A pure function. nil in, nil out: "nothing to abbreviate" and "zero" are
-- different answers, and substituting one for the other is not allowed. A
-- caller who wants zero writes it themselves, where it is visible in their
-- code.
--
-- The sign is moved out in front rather than lost or clamped at zero: a
-- negative value here means an error in somebody else's arithmetic, and
-- showing it is more honest than masking it. For the same reason the whole
-- function is symmetric — Abbreviate(-x) reads as a minus followed by
-- Abbreviate(x).
--
-- Below a thousand the number is written as an integer, and `whole` writes
-- it — the same one the bar text uses. The sign does not reach this point: it
-- was taken off above, so `whole` only ever sees a non-negative number
-- here.
--
-- @param value number|nil
-- @return string|nil
function Format.Abbreviate(value)
    local number = tonumber(value)
    if not finite(number) then return nil end

    local sign = ""
    if number < 0 then
        sign = "-"
        number = -number
    end

    if number >= MILLION_FLOOR then
        return sign .. string.format("%.1fm", number / MILLION)
    end
    if number >= THOUSAND then
        return sign .. string.format("%.1fk", number / THOUSAND)
    end
    return sign .. whole(number)
end

--- The share of a maximum, in whole per cent.
--
-- A pure function. A maximum of zero gives zero per cent rather than a
-- division by zero or nil: a bar with a zero maximum occurs on a unit out of
-- sight and on a class without a resource, that is, constantly rather than as
-- an exotic case. Zero is what the bar text shows today.
--
-- The rounding is symmetric (see Format.Round above). This used to be written
-- twice and differently: the bar text computed math.floor(v + 0.5), the panel
-- handled the sign explicitly. The second was taken, and here is why: a
-- percentage is a share, that is, the same quantity in different units, and
-- Percent(-c, m) must be minus Percent(c, m). The first formulation breaks
-- that property, and breaks it silently. On live values there is no
-- difference between the two at all — negative percentages do not occur on a
-- bar — so choosing the correct rounding moves nothing on screen.
--
-- The result is not clamped at zero. The clamping belonged to the panel, and
-- it is that cell's own decision rather than part of the rounding: a negative
-- percentage means somebody computed the wrong thing, and replacing it with
-- zero hides their error behind a plausible answer. Whoever wants zero
-- instead of a minus writes math.max(0, ...) on their side, where it is
-- visible.
--
-- @param current number|nil
-- @param maximum number|nil
-- @return number a whole number of per cent
function Format.Percent(current, maximum)
    local value = tonumber(current) or 0
    local total = tonumber(maximum) or 0
    if not finite(value) or not finite(total) then return 0 end
    if total <= 0 then return 0 end

    return Format.Round(value / total * 100)
end
