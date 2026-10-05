-- The away screen: a dark canvas with the character's card while the player
-- is gone.
--
-- The registering file. Everything that decides whether the screen is visible
-- lives in Rules.lua; everything that counts what was missed, in Missed.lua;
-- everything that draws, in Screen.lua. Here there is only the joint with the
-- core: the descriptor, the settings, the events, the command.

local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Screen would collide
-- silently.
local ns = core.Feature("away")

-- The core may be absent entirely: the player switched it off in the addon
-- list. One readable line rather than a Lua error.
if type(_G.Darken) ~= "table"
    or type(_G.Darken.RegisterModule) ~= "function" then
    print("|cffff4040Darken Away|r: Darken is not loaded, so this part does "
        .. "nothing.")
    return
end

-- The contract version the module is written against. The sixteenth: the
-- module translates its own strings, and the core's palette has a muted colour
-- without which the card has nothing to set the name apart with.
local API = 16

local DEFAULTS = {
    -- A fresh install changes nothing: a screen-wide cover must not appear
    -- for somebody who did not ask for one.
    enabled = false,
    missed  = true,

    -- The canvas's density as a percentage. Not a fraction: the settings
    -- slider shows the player a number, and 97 reads at once while 0.97 asks
    -- to be converted in one's head.
    darkness = 97,
}

local module

--============================================================================
-- The state of one absence
--============================================================================

-- Lives for exactly one absence and is cleared at its BEGINNING rather than
-- at its end. The end of an absence is the moment the player is finally
-- looking at the screen, and wiping the "while you were away" line at that
-- moment means wiping it before their eyes.
local away = false      -- whether the away flag is set
local called = false    -- whether the player was called during this absence
local began = 0         -- when the absence began, by the game's clock
local tally             -- the tally of what was missed
local forced = false    -- the screen is shown by the command, not by the flag

--- The module's settings, if the core has handed over its handle already.
-- @return table|nil
local function settings()
    return module and module:GetSettings() or nil
end

--- The game's clock. Outside the client there is none, and that is not a
-- failure: without a client there is no absence either, and the timer then
-- stands at zero.
-- @return number
local function now()
    local clock = _G.GetTime
    if type(clock) ~= "function" then return 0 end
    local ok, value = pcall(clock)
    return (ok and tonumber(value)) or 0
end

--- Whether the away flag is set on the player right now.
-- @return boolean
local function flagged()
    local ask = _G.UnitIsAFK
    if type(ask) ~= "function" then return false end
    local ok, value = pcall(ask, "player")
    return (ok and value) and true or false
end

--============================================================================
-- The card
--============================================================================

--- One word of the game's, asked for safely.
-- @param name string the global function's name
-- @return any
local function game(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
end

--- The "while you were away" line, already translated and joined up.
--
-- Only somebody who knows the language can inflect a caption by its number,
-- and that is here: Missed gives pairs of kind and count, while the word for
-- them is chosen by the translation.
-- @return string|nil nil when there is nothing to show
local function missedLine()
    local chosen = settings()
    if not chosen or not chosen.missed then return nil end
    if not ns.Missed.Any(tally) then return nil end

    local pieces = {}
    for _, part in ipairs(ns.Missed.Parts(tally)) do
        local one = part.kind == "whisper" and "%d whisper" or "%d letter"
        local many = part.kind == "whisper" and "%d whispers" or "%d letters"
        pieces[#pieces + 1] = string.format(
            module:Localize(part.count == 1 and one or many), part.count)
    end

    return ns.Missed.Join(pieces)
end

--- Everything that is printed on the canvas.
-- @return table
local function card()
    local name = game("UnitName", "player") or ""
    local level = tonumber(game("UnitLevel", "player")) or 0
    local class = game("UnitClass", "player") or ""
    local guild = game("GetGuildInfo", "player")

    local who = string.format(module:Localize("Level %d %s"), level, class)
    if type(guild) == "string" and guild ~= "" then
        who = who .. " \194\183 <" .. guild .. ">"
    end

    local where = game("GetRealZoneText") or game("GetZoneText") or ""

    local spent = forced and 0 or (now() - began)

    return {
        name   = name,
        who    = who,
        where  = where,
        timer  = string.format(module:Localize("Away %s"),
            ns.Rules.Elapsed(spent)),
        missed = missedLine(),
        clock  = date and date("%H:%M") or nil,
    }
end

--============================================================================
-- Display
--============================================================================

local refresh

-- Whether the canvas was waved away with a click. Lives until the end of the
-- absence: having come back and gone away again, the player expects the
-- overlay again — they waved away THAT absence rather than switching the
-- display off for good. The checkbox in the settings switches it off for
-- good.
local waved = false

--- Recompute whether the screen is visible and bring it into that state.
local function apply()
    local chosen = settings()
    if not chosen then return end

    local shown = forced
        or ns.Rules.Shown(chosen.enabled, away, called, waved)

    if not shown then
        ns.Screen.SetShown(false)
        if ns.Screen.frame then
            -- The clock's tick is removed along with the display: the
            -- engine does not walk a hidden frame anyway, but a removed
            -- script is more honest — it says there is nothing left to
            -- count.
            local frame = ns.Screen.frame
            if type(frame.SetScript) == "function" then
                pcall(frame.SetScript, frame, "OnUpdate", nil)
            end
        end
        return
    end

    if not ns.Screen.Build() then return end

    -- A click on the canvas removes it. Set once: a handler assigned afresh
    -- on every repaint is a new closure once a second.
    if not ns.Screen.waves then
        ns.Screen.OnWave(function()
            waved = true
            apply()
        end)
        ns.Screen.waves = true
    end

    -- The canvas's look is set before painting: the density and the model's
    -- movement are not part of the card — they change by a slider and a list
    -- rather than once a second.
    ns.Screen.Density((tonumber(chosen.darkness) or 97) / 100)
    ns.Screen.Animate()

    ns.Screen.Paint(card())
    ns.Screen.SetShown(true)

    -- The timer is the module's only OnUpdate, and it ticks no more often
    -- than once a second: the card changes by the second, while there are
    -- sixty frames in one.
    local frame = ns.Screen.frame
    if type(frame.SetScript) == "function" then
        local since = 0
        pcall(frame.SetScript, frame, "OnUpdate", function(_, elapsed)
            since = since + (tonumber(elapsed) or 0)
            if since < 1 then return end
            since = 0
            ns.Screen.Paint(card())
        end)
    end
end

refresh = apply

--============================================================================
-- Events
--============================================================================

--- The away flag changed.
local function flagsChanged()
    local chosen = settings()
    if not chosen then return end

    local current = flagged()

    if ns.Rules.Began(away, current) then
        -- A new absence begins with a clean slate: the previous
        -- interruption, the previous tally and the previous "waved away" have
        -- nothing to do with it.
        called = false
        waved = false
        began = now()
        tally = ns.Missed.New()
    end

    away = current

    -- The command shows the screen only until the first movement of the
    -- mouse: the game clears the flag itself and reports it by this same
    -- event. Keeping the canvas after that would mean not letting go of the
    -- screen until the player clicked on it.
    if forced and not current then forced = false end

    apply()
end

--- The player was called.
local function called_()
    if not away then return end
    called = true
    forced = false
    apply()
end

--- A whisper arrived.
local function whispered()
    if not away or type(tally) ~= "table" then return end
    ns.Missed.Add(tally, "whisper", 1)
    apply()
end

--- A letter arrived.
local function mailed()
    if not away or type(tally) ~= "table" then return end
    -- The event also arrives when no letters were added (they were read on
    -- another character). The game is asked rather than the event counted.
    if not game("HasNewMail") then return end
    ns.Missed.Add(tally, "mail", 1)
    apply()
end

--============================================================================
-- Settings
--============================================================================

--- The read and write pair for one settings field.
-- @param key string
-- @return function, function
local function field(key)
    return
        function()
            local chosen = settings()
            return chosen and chosen[key]
        end,
        function(_, value)
            local chosen = settings()
            if not chosen then return end
            chosen[key] = value and true or false
            module:Apply()
        end
end

--- The read and write pair for a field that holds something other than true
--- and false.
-- @param key string
-- @return function, function
local function value(key)
    return
        function()
            local chosen = settings()
            return chosen and chosen[key]
        end,
        function(_, got)
            local chosen = settings()
            if not chosen then return end
            chosen[key] = got
            module:Apply()
        end
end

local OPTIONS
do
    local enabledGet, enabledSet = field("enabled")
    local missedGet, missedSet = field("missed")
    local darknessGet, darknessSet = value("darkness")

    -- The labels stand as functions rather than strings: the file is read
    -- before registration hands over the handle, and at that moment there is
    -- nothing to translate a string with.
    OPTIONS = {
        type = "group",
        name = function() return module:Localize("Away Screen") end,
        args = {
            enabled = {
                type  = "toggle",
                order = 1,
                width = "full",
                name  = function()
                    return module:Localize("Show the Away Screen")
                end,
                desc  = function()
                    return module:Localize(
                        "While the game marks you away, cover the screen "
                        .. "with a dark card: your character, where you are "
                        .. "and how long you have been gone. Off by default "
                        .. "- a fresh install changes nothing.")
                end,
                get = enabledGet,
                set = enabledSet,
            },
            missed = {
                type  = "toggle",
                order = 2,
                width = "full",
                name  = function()
                    return module:Localize("Show What I Missed")
                end,
                desc  = function()
                    return module:Localize(
                        "Add a line with the whispers and letters that "
                        .. "arrived while you were gone.")
                end,
                get = missedGet,
                set = missedSet,
            },
            darkness = {
                type  = "range",
                order = 3,
                min   = 50,
                max   = 100,
                step  = 1,
                name  = function() return module:Localize("Darkness") end,
                desc  = function()
                    return module:Localize(
                        "How solid the cover is. Below a hundred the world "
                        .. "still shows through as a silhouette.")
                end,
                get = darknessGet,
                set = darknessSet,
            },
        },
    }
end

--============================================================================
-- Registration
--============================================================================

module = _G.Darken:RegisterModule({
    name     = "umbraafk",
    api      = API,
    defaults = DEFAULTS,
    options  = OPTIONS,

    OnEnable = function(self)
        module = self

        for locale, strings in pairs(ns.Locales or {}) do
            self:RegisterStrings(locale, strings)
        end

        tally = ns.Missed.New()

        self:RegisterEvent(ns.Rules.FLAGS_EVENT, flagsChanged)

        -- The interruptions go as one list. Conditions written in place
        -- ("if in combat, hide", "if a ready check, hide") grow by six out of
        -- seven, and nobody notices the sixth.
        for _, event in ipairs(ns.Rules.INTERRUPTS) do
            self:RegisterEvent(event, called_)
        end

        self:RegisterEvent("CHAT_MSG_WHISPER", whispered)
        self:RegisterEvent("UPDATE_PENDING_MAIL", mailed)

        -- Show the screen now, without waiting for the game to mark an
        -- absence. Without this every check would cost five minutes of
        -- sitting still.
        self:RegisterCommand("afk", function()
            local chosen = settings()
            if not chosen then return end

            -- The command SWITCHES a disabled module ON rather than
            -- refusing.
            --
            -- A refusal was written here out of the habit that "the setting
            -- comes first", and it turned out to be wrong: the command is
            -- typed in order to see the screen, and the answer "the screen is
            -- switched off" does exactly not what one came for. The author
            -- typed it first thing and got a refusal.
            --
            -- The switching on is said out loud: a setting changed, and
            -- changing it silently by a command is not allowed — the player
            -- has to know that the checkbox in the window is now ticked.
            if not chosen.enabled then
                chosen.enabled = true
                self:Print(self:Localize("the away screen is on now"))
                self:Apply()
            end

            forced = not forced
            if forced then began = now() end
            apply()
        end)
    end,

    ApplySettings = function()
        refresh()
    end,

    OnDisable = function()
        -- The core stopped calling us: take everything of ours off the
        -- screen.
        forced = false
        ns.Screen.SetShown(false)
    end,
})

if not module then return end

--============================================================================
-- The settings page, declared as data
--============================================================================

-- Declared beside its own code, as it is for the core's subsystems. The old
-- tree (OPTIONS above) stays for now: the window built on it works until the
-- last step of the move.

if type(core.Schema) == "table" then
    local Schema = core.Schema
    local PAGE = "umbraafk"

    Schema.Page(PAGE, {
        title = "Away Screen",
        order = 10,
        section = "umbraafk",
    })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "While the game marks you away, the screen is covered with "
            .. "a dark card: your character, where you are and how long you "
            .. "have been gone. It draws over the interface rather than "
            .. "hiding it, and it goes away for good the moment something "
            .. "wants you - combat, a ready check, an invite.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show the Away Screen",
        path = { "enabled" },
        apply = "umbraafk",
        hint = "Off by default - a screen-wide cover should not appear for "
            .. "someone who did not ask for one.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show What I Missed",
        path = { "missed" },
        apply = "umbraafk",
        hint = "Add a line with the whispers and letters that arrived while "
            .. "you were gone.",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Darkness",
        path = { "darkness" },
        min = 50, max = 100, step = 1,
        apply = "umbraafk",
        hint = "How solid the cover is. Below a hundred the world still "
            .. "shows through as a silhouette.",
    })
end
