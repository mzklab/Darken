-- The rule for showing the screen, and counting the time away.
--
-- The pure part: not one call into the game. Three facts arrive — whether the
-- module is on, whether the player carries the away flag, whether they were
-- called — and an answer leaves: is the screen shown or not. The rule is
-- tested outside the client, because testing it in the client means sitting
-- still for five minutes per attempt.

local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Missed or Screen would collide
-- silently.
local ns = core.Feature("away")

local Rules = {}
ns.Rules = Rules

-- The events the screen goes out on.
--
-- The list is here, one and whole. The temptation was to write them as
-- conditions in place ("if in combat, hide", "if a ready check, hide"), and
-- that is the very mistake that leaves a forgotten window undimmed for years:
-- a condition in seven places grows by six rather than by seven, and nobody
-- notices the sixth.
--
-- What all eight have in common: each means the player was called, and there
-- is nobody left to call them — they are not at the keyboard. A screen over
-- the interface at that minute is an unread invitation and a death taken
-- blind.
Rules.INTERRUPTS = {
    "PLAYER_REGEN_DISABLED",   -- combat started
    "READY_CHECK",             -- a ready check
    "ROLE_POLL_BEGIN",         -- a role poll
    "PARTY_INVITE_REQUEST",    -- an invitation to a group
    "LFG_PROPOSAL_SHOW",       -- a dungeon was found
    "CONFIRM_SUMMON",          -- a summon
    "RESURRECT_REQUEST",       -- a resurrection
    "DUEL_REQUESTED",          -- a duel request
}

-- The event the game reports a change of the player's flags with. An absence
-- begins and ends only by it: the module has no idle counter of its own and
-- must not — it would duplicate the game's and diverge from it by
-- seconds.
Rules.FLAGS_EVENT = "PLAYER_FLAGS_CHANGED"

--- Whether the screen is shown right now.
--
-- Three conditions, each answering its own question: did the player ask for
-- the screen at all, did they go away, and were they called while away.
--
-- An interruption puts the screen out until the END OF THE ABSENCE rather
-- than until the end of combat. Otherwise the screen would come back over a
-- fight that had just started, a second after the previous one ended — and at
-- exactly the moment the player finally sat down at the keyboard.
--
-- @param enabled any whether the module is on
-- @param away any whether the away flag is set
-- @param called any whether the player was called during this absence
-- @return boolean
function Rules.Shown(enabled, away, called, waved)
    if not enabled then return false end
    if not away then return false end
    if called then return false end

    -- Waved away with a click: not shown again until the absence ends.
    --
    -- The canvas catches the mouse, or a stray click on the black would land
    -- on a button underneath. But that also means the GAME does not see the
    -- click and does not clear the absence by it: the screen stayed up, and
    -- the only way to remove it was to touch the keyboard.
    --
    -- We do not undertake to clear the absence on the player's behalf: they
    -- did not stop being away because they brushed the overlay aside, and
    -- their "not here" is needed by whoever writes to them. So our canvas is
    -- hidden rather than their state in the game changed.
    if waved then return false end

    return true
end

--- What to do with the absence's memory on a change of flags.
--
-- Separate from Rules.Shown, because it is a different question: not "is it
-- visible" but "should the count start afresh". The tally of what was missed
-- and the "was called" mark live for exactly one absence, and they are
-- cleared at its beginning rather than at its end: the end of an absence is
-- the moment the player is looking at the screen, and wiping the "while you
-- were away" line at that moment means wiping it before their eyes.
--
-- @param was any whether there was an absence before the event
-- @param now any whether there is an absence after it
-- @return boolean whether a new absence is beginning
function Rules.Began(was, now)
    return (not was) and now and true or false
end

--- The time away, in words.
--
-- Minutes and seconds, with no hours until an hour has passed: 04:17 reads at
-- once, while 00:04:17 makes one recount the places. A day or more is
-- impossible here by meaning — the game disconnects for idling sooner — but
-- negative and non-numeric values do arrive: the machine's clock gets
-- changed, and GetTime starts afresh after entering the world.
--
-- @param seconds any
-- @return string
function Rules.Elapsed(seconds)
    local total = tonumber(seconds) or 0
    -- NaN does not equal itself. Without this line it passes further and
    -- prints as a pair of NaNs.
    if total ~= total or total < 0 then total = 0 end
    total = math.floor(total)

    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local rest = total % 60

    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, rest)
    end
    return string.format("%02d:%02d", minutes, rest)
end
