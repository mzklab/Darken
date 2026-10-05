local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- A nameplate's colour: by class for players, by reaction for everybody
-- else.
--
-- Pure rules and nothing more: not one call into the game. Everything the
-- decision needs arrives as arguments — the "this is a player" flag, the class
-- token, the client's table of class colours, the reaction's index and the
-- table of reaction colours. So the rule is tested outside the client in every
-- outcome rather than inspected by eye on live nameplates.
--
-- Why the core's rule is not used. It exists there (ns.UnitFrames.BarColor),
-- but it lives in the core's insides, while a module in a separate folder sees
-- only the public contract — and that is right: what is exposed has to be kept
-- forever. The rule here is a different and a narrower one: the core has four
-- modes the player chooses between, while the nameplates engine has one mode
-- and it is not configurable — players by class, everything living by
-- reaction. The specification is written that way.

local Colors = {}
ns.Colors = Colors

-- A fallback palette of reactions in case the client has no table of faction
-- bar colours.
--
-- These are the game's colours rather than our palette: our colours come from
-- the skin through the contract and are not declared a second time here. The
-- indices are the engine's own: 1-3 hostile, 4 neutral, 5-8 friendly. The
-- numbers are needed because the absence of the client's table has no right to
-- leave a bar colourless.
local REACTION = {
    [1] = { r = 0.79, g = 0.22, b = 0.22 },
    [2] = { r = 0.79, g = 0.22, b = 0.22 },
    [3] = { r = 0.87, g = 0.44, b = 0.22 },
    [4] = { r = 0.94, g = 0.87, b = 0.32 },
    [5] = { r = 0.24, g = 0.74, b = 0.30 },
    [6] = { r = 0.24, g = 0.74, b = 0.30 },
    [7] = { r = 0.24, g = 0.74, b = 0.30 },
    [8] = { r = 0.24, g = 0.74, b = 0.30 },
}
Colors.REACTION = REACTION

--- The colour channels out of a table of either shape.
-- The engine returns class colours as { r =, g =, b = }; an array of three
-- numbers turns up in other people's tables, and parsing it is cheaper than
-- explaining to the player why a bar is white.
-- @param color table|nil
-- @return number|nil, number|nil, number|nil
local function channels(color)
    if type(color) ~= "table" then return nil end

    local r, g, b = color.r, color.g, color.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        r, g, b = color[1], color[2], color[3]
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return r, g, b
end
Colors.Channels = channels

--- A unit's colour on a nameplate.
--
-- The order of falling back is one and the same for the bar and for the name,
-- and that is not economy: a bar painted by class next to a name painted by
-- reaction would look like a failure. First the class — but only for players:
-- a creature has no class, and "by class" for it means "by reaction". Then the
-- reaction — a unit outside one's field of view has none. White at the very
-- end: a bar without a colour looks broken, and a silent nil would leave the
-- previous unit's colour on it, because the frame is reused.
--
-- @param info table|nil { isPlayer, class, classColors, reaction,
--                         reactionColors, fallback }
-- @return number, number, number
function Colors.For(info)
    info = type(info) == "table" and info or {}

    -- A creature somebody else tagged is grey, and that is not our colour
    -- but the game's answer to "is this your kill". It stands first: the class
    -- and the reaction answer WHO is in front of you, while the grey answers
    -- WHOSE it is, and the second outranks. The colour is one for the whole
    -- addon (ns.Skin.TapColor): the same one stands on a unit frame's bar.
    if info.tapDenied == true and type(ns.Skin) == "table"
        and type(ns.Skin.TapColor) == "function" then
        return ns.Skin.TapColor()
    end

    if info.isPlayer then
        local colors = info.classColors
        local token = info.class
        if type(colors) == "table" and type(token) == "string" then
            local r, g, b = channels(colors[token])
            if r then return r, g, b end
        end
    end

    local colors = type(info.reactionColors) == "table"
        and info.reactionColors or REACTION
    local index = tonumber(info.reaction)
    if index then
        local r, g, b = channels(colors[index])
        if r then return r, g, b end

        -- The client's table may turn out to have a hole at this index: the
        -- fallback always has it. Quietly returning white here would mean
        -- losing the distinction between friend and foe in exactly the place
        -- it matters most.
        r, g, b = channels(REACTION[index])
        if r then return r, g, b end
    end

    local r, g, b = channels(info.fallback)
    if r then return r, g, b end

    return 1, 1, 1
end

--- Whether a unit is hostile by its reaction index.
-- The display needs it: an enemy's name and a merchant's name must not look
-- alike even when their bars are of one shade. An unknown reaction is not a
-- hostile one: ascribing hostility to somebody nothing is known about is worse
-- than not ascribing it.
-- @param reaction any
-- @return boolean
function Colors.Hostile(reaction)
    local index = tonumber(reaction)
    if not index then return false end
    return index <= 4
end

-- === The threat colour and the order of precedence ===
--
-- Two rules writing one and the same colour is a defect the project has paid
-- for once already. So exactly one function (Colors.Bar) answers "what colour
-- is this bar", and the order of precedence is declared in it directly rather
-- than emerging from whose call happened to come later.
--
-- The precedence: **threat outranks a rule, a rule outranks class, class
-- outranks reaction**.
--
-- Why exactly that way. Class and reaction answer "who is this", and the
-- answer does not change while the creature lives. Threat answers "what is
-- happening right now", and the answer changes within a second. The permanent
-- has to yield to the urgent: a player a boar has turned on must see it on the
-- bar rather than recall that the boar used to be neutral yellow and has
-- become a reddish yellow.
--
-- === Where a rule for a single unit stands ===
--
-- The player's rule (Rules.lua) is the fourth source of colour, and it has
-- exactly one place: **under threat and above class**. It is written here, in
-- the same function, because the precedence has to be declared once and in one
-- place.
--
-- Above class and reaction — because a rule answers the same "who is this" and
-- answers it better. Class and reaction are the engine's guesses about what
-- the creature is to the player; a rule is a name or an id the player typed by
-- hand. A guess overriding a direct instruction would mean a setting that does
-- not work in exactly the place it was switched on.
--
-- Under threat — because a rule is permanent while threat is urgent: the same
-- argument by which threat already stands above class. A rule that overrode
-- threat would hide a creature turning on the player, that is, the only thing
-- the threat colouring exists for. The standing out is not lost in the
-- process: a rule changes the nameplate's size independently of the colour,
-- and threat does not touch it.
--
-- A rule does not create a second writer of the colour: it arrives here as a
-- field of info and is decided here, by one if in the same row as the other
-- three.
--
-- The threat colour is applied to the unfriendly only: on a merchant it would
-- mean a threat that does not exist and would paint half the city.

-- The threat colours. Not new numbers: the same three entries of the fallback
-- reaction palette, taken by meaning — red for "you are holding it", orange
-- for "you are about to hold it", yellow for "it is about to break onto you".
-- There are deliberately no hex values of our own here: the skin's colours
-- come from the contract, and the game's are declared above.
local THREAT = {
    [1] = REACTION[4],
    [2] = REACTION[3],
    [3] = REACTION[1],
}
Colors.THREAT = THREAT

--- The threat colour, if there is one at all.
--
-- The game's threat index: 0 — the creature is not hitting you and you are far
-- from pulling it over; 1 — you are close; 2 — you have pulled it over but it
-- is not hitting you yet; 3 — it is hitting you. Zero has no colour of its
-- own, and that is not an omission: the ordinary state of things must not
-- repaint half the screen.
--
-- @param status any the threat index, 0..3
-- @param hostile any whether the unit is unfriendly
-- @return number|nil, number|nil, number|nil
function Colors.Threat(status, hostile)
    if not hostile then return nil end

    local index = tonumber(status)
    if not index then return nil end

    local color = THREAT[index]
    if not color then return nil end

    return channels(color)
end

--- What colour this creature's bar is.
--
-- The only answer to that question in the whole engine. The fourth value is
-- the name of the rule that fired — not for display but so that the precedence
-- can be tested directly rather than inferred from the numbers.
--
-- @param info table|nil the unit's information; beyond Colors.For's fields:
--        threatOn — whether the threat colouring is on,
--        threat   — the threat index from the game,
--        rule     — the player's rule for this unit (ns.Rules.For), or nil
-- @return number, number, number, string the name of the rule that fired
function Colors.Bar(info)
    info = type(info) == "table" and info or {}

    if info.threatOn then
        local r, g, b = Colors.Threat(info.threat, Colors.Hostile(info.reaction))
        if r then return r, g, b, "threat" end
    end

    -- The player's rule. It may have no colour at all — a rule is entitled
    -- to change the size alone — and then the class and the reaction decide,
    -- as they decided before the rules existed.
    local rule = info.rule
    if type(rule) == "table" then
        local r, g, b = channels(rule)
        if r then return r, g, b, "rule" end
    end

    -- Class only for a player, and only when the client has a colour for
    -- that class. Otherwise it is the reaction, and it has no right to call
    -- itself class: the rule's name exists for the sake of testing the
    -- precedence, and a lying name would devalue the test itself.
    local byClass = false
    if info.isPlayer and type(info.classColors) == "table"
        and type(info.class) == "string" then
        byClass = channels(info.classColors[info.class]) ~= nil
    end

    local r, g, b = Colors.For(info)
    return r, g, b, byClass and "class" or "reaction"
end
