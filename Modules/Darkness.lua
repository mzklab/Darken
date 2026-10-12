local ADDON, ns = ...

-- Darkness: a shared brightness factor applied by multiplication to the
-- textures of the frames the compatibility layer returns.
--
-- The slider stores "how much to darken" from 0 to 100, while the engine needs
-- a brightness multiplier: 0 on the slider is a multiplier of 1 (we change
-- nothing), 100 is the darkest the addon goes, and that is deliberately not
-- zero: zero is black, and a black frame is not darkened, it is gone. The
-- conversion of one into the other is the subsystem's only arithmetic, and it
-- is split out into a pure function.
--
-- The multiplication is done by ns.Skin.Shade — the same operation the engine
-- lays a colour onto a texture with. There is no separate mechanism of
-- darkening and there must not be: the spec says plainly that a colour and a
-- darkening are both multipliers and fold into one SetVertexColor call. When
-- the unit frames subsystem appears, it will multiply the colour the player
-- chose by the same factor rather than draw a black film over the bar.
--
-- Reversibility. The styling in Skin/ is deliberately one-way: a texture once
-- removed is not put back, and that gave a defect once already — a switch that
-- switched nothing off. Here that is not allowed: a slider returned to zero is
-- obliged to restore the former look. So at the first touch of a texture its
-- own colour is remembered, and after that every computation starts from the
-- remembered colour rather than from the current one.
--
-- It is remembered BESIDE THE TEXTURE (ns.Skin.Memory) rather than as a field
-- on the texture itself, as it used to be. A field on somebody else's object
-- taints that object: the engine considers it touched by an addon, the taint
-- spreads to the frame and onwards, and the player sees it in a file that is
-- none of ours — "Secret values are only allowed during untainted execution"
-- on the cooldown of an override bar's button. Looking at somebody else's
-- object and painting it is allowed; writing onto it is not.
--
-- Computing the darkening from the current colour would be wrong: two
-- movements of the slider in a row would multiply the factors together, and
-- "60 after 40" would not give the same as "60 straight away", while a return
-- to zero would restore nothing. The remembered colour outlives any number of
-- movements of the slider: it is written once and never changes again.
--
-- What is not here and why. The former design was the same — read the colour
-- and multiply it — and it fell over in the client: the engine returns the
-- colours of some objects as "secret" numbers, arithmetic over which is
-- forbidden to an addon (in detail at ns.Skin.Numeric). Three ways out were
-- considered.
--
--   Not to read at all but to lay a dark film over the window. Rejected: a
--   film covers everything beneath it, while the framing and the contents in a
--   window of the game's lie mixed together across the layers of one frame — a
--   bag slot's border is drawn over the item's icon. There is no separate layer
--   below which only framing lies, and the film would break the rule "the
--   contents do not darken" in exactly the three cases the author had already
--   seen on his screen.
--
--   To read nothing but to remember our own values, counting the native colour
--   as white. Rejected: the textures the game paints itself (the alarming red
--   highlight, the class colours) would lose their colour forever, and a
--   return of the slider to zero would restore to them not the native look but
--   white.
--
--   To read, but to ask whether the value is usable before multiplying.
--   Chosen: the only way to learn about secrecy is to try the computation
--   inside a protected call, and that costs one pcall per texture per pass. An
--   object whose colour cannot be computed stays in its native look and lands
--   in the counter of refusals (ns.Counters.blocked_darkness) rather than
--   bringing the subsystem down.

local Darkness = {
    name = "darkness",
}
ns.Darkness = Darkness

-- The tally of what was done (Core/Tally.lua). The reference is taken once
-- when the file is read: the application pass walks the whole plan of the
-- interface, and incrementing a counter on it is obliged to be a single
-- addition of integers.
local counters = ns.Counters or {}
ns.Counters = counters

-- How many textures the subsystem really repainted and how many it left alone
-- as contents. The first, were it zero, would mean the darkening touched
-- nothing; the second is the other half of the same question: a pass that
-- skipped everything and a pass that found nothing look alike.
counters.dimmed  = counters.dimmed  or 0
counters.content = counters.content or 0

-- How many objects the subsystem could not darken: their colour arrived from
-- the game as a value an addon must not compute over. Not an error and not
-- silence but a visible consequence that has a name; which objects these turn
-- out to be is written down in docs/known-issues.md.
counters.blocked_darkness = counters.blocked_darkness or 0

-- How many objects the pass walked past because the engine marked them as
-- forbidden to addons. That is neither a refusal nor a failure: the game said
-- so itself — "not yours" — and by saying it forestalled trouble. The counter
-- is a separate one because a zero here and a zero of refusals mean different
-- things, and added into one number they would mean "something did not work
-- out", which did not happen.
counters.forbidden = counters.forbidden or 0

-- The protected frames the walk went past. A zero here means not "there are
-- no protected ones" but "the walk never reached them": the action bars are
-- always protected, and a zero after entering the game is a sign that the
-- general walk does not see them at all.
counters.protected_darkness = counters.protected_darkness or 0

-- The hidden frames the walk did not go inside.
--
-- There are more of them in the game than of the shown ones: tabs the player
-- never opened, list rows lying in reserve, windows created in advance. There
-- is no point painting them — they are not visible — while they cost as much as
-- the shown ones.
counters.hidden = counters.hidden or 0

-- Subscriptions placed and subscriptions fired. The first, were it zero,
-- would mean not one guessed name of a function of the game's was found; the
-- second, with a non-zero first, that a name was found and nothing came of
-- it.
counters.hooked_darkness = counters.hooked_darkness or 0
counters.fired_darkness  = counters.fired_darkness  or 0

-- How often the game repainted a picture after us and the watcher heard it.
--
-- It had no count, and the absence cost an evening: "Hooks That Ran" was read
-- as this watcher's firings when it counts openings of windows, and on that
-- reading the watcher was cleared of a defect it may well own.
counters.repainted = counters.repainted or 0

-- Labels raised out of a darkened page, and labels looked at and left
-- because their own colour reads on dark. Two counters rather than one:
-- a zero in the first beside a number in the second says the threshold
-- is wrong, while two zeroes say the raising never reached the page.
counters.lifted = counters.lifted or 0
counters.lightText = counters.lightText or 0
counters.foreign = counters.foreign or 0

-- The names of the game's functions whose subscription has already been
-- counted.
local counted = {}

-- The groups of frames the subsystem darkens, and their labels for the list
-- of exceptions.
--
-- The order is the one the player looks at his screen in: first what is in
-- front of him all the time, then what he opens when he needs it. The frames'
-- names lie in Core/Compat.lua and only there; what arrives here is a group's
-- key and a label for the list of exceptions.
--
-- The groups are divided by what the player calls them. The list of exceptions
-- is for him, and a "minimap" row in it is obliged to mean the minimap as a
-- whole: its border and the buttons around it, not half of it.
local GROUPS = {
    { key = "unitframe",     label = "Unit Frames"        },
    -- Nameplates are created and torn down by the game constantly, and no
    -- list of their names exists (see Core/Compat.lua). So what darkens them
    -- is not the general pass from here but their own subsystem — at the
    -- moment a nameplate is attached to a creature (Modules/NamePlates.lua).
    -- The group is written down here for one thing: a row in the list of
    -- exceptions. The dynamic marker tells the pass not to look for its frames
    -- — there is nothing to look for.
    { key = "nameplate",     label = "Nameplates", dynamic = true },
    { key = "actionbar-art", label = "Action Bar Art"     },
    { key = "minimap",       label = "Minimap"            },
    -- The default grid of buffs and debuffs. As an area of its own rather
    -- than part of "other windows": an aura's icon is something the player
    -- looks at in combat, and he is entitled to decide about it separately.
    -- The names are taken by the compatibility layer (the "auras" group), and
    -- there is no list of our own here.
    { key = "auras",         label = "Buffs and Debuffs"  },
    { key = "bags",          label = "Bags and Micro Menu" },
    { key = "chat",          label = "Chat"               },
    { key = "objectives",    label = "Objective Tracker"  },
    { key = "tooltip",       label = "Tooltips"           },
    { key = "character",     label = "Character Sheet"    },
    { key = "questlog",      label = "Quest and Dialog Text" },
    -- Other addons' windows. The group lists no frames of its own and starts
    -- no walk of its own: those windows are found by the same general pass,
    -- and an area is assigned to them by name (Darkness.AddonWindow).
    --
    -- The dynamic marker is the same as the nameplates' and for the same
    -- reason: "there is nothing to look for". A general marker here would be a
    -- second walk over the whole interface tree, that is, doubled
    -- reconnaissance for nothing.
    { key = "addons",        label = "Other Addons' Windows", dynamic = true },
    -- Everything else there is on the screen. The general marker tells the
    -- pass to look for these frames not by name but by walking the interface
    -- tree: the names above are listed only so that the groups named there get
    -- a checkbox of their own in the list of exceptions. Hence the label: the
    -- player ticks "other windows" rather than the ones he listed himself.
    { key = "window",        label = "Other Windows", general = true },
}

-- A texture's original colour: texture -> { r, g, b }.
--
-- Beside the texture rather than on it, because we do not write onto somebody
-- else's object (see the explanation at the top of the file). The keys are
-- weak: a texture the game has thrown away is not held in memory by the fact
-- that we remember its colour.
local BASE = ns.Skin.Memory()

-- The area a frame belongs to: frame -> the area's key.
--
-- Filled in by the walk along the way and needed for one thing: to answer the
-- question "which area does a picture the game has only just created belong
-- to" without walking anything. The picture knows its owner (GetParent), and
-- the owner knows its area.
local FRAME_AREA = ns.Skin.Memory()

-- The windows whose showing we are already watching: window -> true.
local SHOWN_WATCH = ns.Skin.Memory()

-- Whether a window yielded anything new on its last return: window ->
-- yes/no.
--
-- Needed so as not to pay for a full walk of a window that has already given
-- everything up (see sweepLater).
local GREW = ns.Skin.Memory()

-- A texture's place in the plan: texture -> index.
--
-- Needed for one thing: to answer somebody else's repainting without hunting
-- the texture down by enumeration. The index is valid for the current plan,
-- and it is cleared along with it.
local INDEX = ns.Skin.Memory()

-- The textures whose repainting we are already watching: texture -> true.
--
-- Separate from the plan's marker: a watcher is placed once and lives as long
-- as the texture itself does, while the plan is reassembled many times.
local WATCHED = ns.Skin.Memory()

-- The marker "this texture is already in the plan": texture -> generation
-- number.
--
-- What is stored is not a "true" but a number: when the plan is cleared, the
-- generation goes up by one, and every former marker stops matching at a
-- stroke. Walking the list and clearing the markers would amount to the same
-- thing, only at the price of a pass over tens of thousands of objects on
-- every clearing.
local PLANNED = ns.Skin.Memory()

--- An object's remembered original colour, or nil.
--
-- Exposed because "has the darkness touched this object" is a question the
-- tests ask, and they used to put it to a field on the object itself. The
-- field is gone, the question remains, and the one obliged to answer it is the
-- place that remembers the answer.
--
-- @param object table|nil
-- @return table|nil { r, g, b }
function Darkness.Remembered(object)
    if type(object) ~= "table" then return nil end
    return BASE[object]
end

-- The slider's scale: two straight lines with a kink at seventy.
--
-- The seventy mark is the scale's former edge. Everything the addon could do
-- before the change lies between zero and seventy: the multiplier at seventy
-- is 0.30 — exactly what used to stand at a hundred. The conversion of an old
-- value into a new one is a multiplication by seven tenths, one for everybody
-- (the migration and its tests are in tests/test_darkscale.lua). Hence the
-- default too: 64 gives 0.36, that is, the Dark mode of the author's former
-- addon.
--
-- The tail from seventy to a hundred leads from 0.30 down to DARKEST. Where
-- exactly it leads the author named himself and corrected twice.
--
-- At first the tail ended at 0.20 — the former floor, chosen by calculation:
-- an addon window's background gives a brightness of about 0.05, a half-tone
-- of framing below 0.125 merges with that background, and below that a frame
-- is not darkened but lost. The author said he did not understand why our
-- black was too weak a value and that it came down to allowing it to go
-- darker still — and the tail was taken down to zero.
--
-- The zero he saw in the game and said a second thing: he wanted the current
-- 85 to be the new 100, because 100 was too black. That is not a reversal of
-- the first but a refinement of it: on the line down to zero the 85 mark gave
-- 0.15, and now 0.15 is the end of the scale. Darker than the former floor
-- (0.20) and lighter than black, that is, exactly the place the author chose
-- by eye rather than by calculation.
--
-- What was left beyond the scale. The example's three lowest steps — Darker
-- (0.14), Even Darker (0.08), Black (0) — lie below its end, and it is the
-- player himself who takes an area there, by name: the overall strength will
-- not reach it. The difference between them and the scale's floor is small
-- (0.15 against 0.14), and that is the whole point of the place chosen: the
-- slider reaches almost to the darkest step, while the last step stays a
-- decision of its own.
--
-- Why a kink rather than one straight line. A line of the former steepness
-- carried to a hundred would arrive at 0.30 — that is, there would be no tail
-- at all. One line from one down to 0.15 would shift every division between
-- zero and seventy, and what stands there is the look everybody who plays
-- already sees with their own eyes: the conversion of the old values would stop
-- being a multiplication by a constant. The kink leaves the first segment as it
-- was and simply adds a second one to it.
local EDGE = 70
local EDGE_FACTOR = 0.30
local DARKEST = 0.15
Darkness.EDGE = EDGE
Darkness.EDGE_FACTOR = EDGE_FACTOR
Darkness.DARKEST = DARKEST

--============================================================================
-- The areas' modes
--============================================================================
--
-- Where this came from. The author has a former addon of his own (DarkMode,
-- MIT, the same author), and he said outright that he liked the model in his
-- old plugin better than the one I had made, though he would keep the slider,
-- which was not bad. There every area of the screen — the unit frames, the
-- nameplates, the tooltips, the buttons — has a NAMED mode of its own rather
-- than a number. Here it is the same thing, only together with the slider
-- rather than instead of it.
--
-- How the two settings coexist. They are not multiplied together and do not
-- argue: a mode ANSWERS FOR A WHOLE AREA, while the slider answers for every
-- area whose mode is "the overall strength". Multiplying one by the other
-- would mean giving one number two owners, and then "More Dark" would turn out
-- to be not more dark but whatever it happened to be. So:
--
--   follow  — the area takes the slider's value. The default for every area,
--             and that is why the slider remains the single movement by which
--             the player makes EVERYTHING darker.
--   native  — the area is not darkened at all. This is the former list of
--             exceptions turned into a value of the same choice: "leave it as
--             it is" is not a separate switch beside the mode but one of the
--             modes. Two controls about one area would differ in opinion, and
--             the player would have to guess whose word carried.
--   the rest — a strength of its own, named by a word, and it does not listen
--             to the slider.
--
-- The names and the numbers. Taken from DarkMode literally (its colors.lua,
-- the MIT licence, a copy of the notice is in docs/backlog.md): Dimmed is a
-- multiplier of 0.50, Dark 0.36, More Dark 0.20. There is no point inventing
-- words of our own in their place: the author already knows those three from
-- his former addon, and the look they give is the very one he liked.
--
-- All six were taken. The top three are expressible as divisions of our slider
-- and are written as divisions: on the first segment the multiplier equals
-- 1 - amount/70 * 0.7, whence 0.50 -> 50 and 0.36 -> 64. The bottom three lie
-- on the second segment, where a division of the scale is not expressible as a
-- round number, and are written as multipliers: pretending they are expressible
-- as a division would mean lying about the scale. The slider does reach each of
-- them, but it arrives at them on no round number.
--
-- "More Dark" stands among the lower ones although it used to be the hundred:
-- its 0.20 is the former floor, and a hundred now means black. It is written as
-- a multiplier so that it states its own number and does not change it in the
-- scale's wake: a step's name was taken from the example together with its
-- number, and that number belongs to the step rather than to the slider.
--
-- The labels. The key is ours, the label is for the player, and the labels of
-- the two service modes were rewritten twice.
--
-- At first there stood "Follow Strength", and the author asked what that meant:
-- the word "follow" does not say what to follow. In its place came a sentence —
-- "As the Slider Above" — and the author said writing like that was ugly and
-- unprofessional. He is right, and here is exactly why. The other labels of
-- this list are "Dimmed", "Dark", "More Dark": short names of a strength. A
-- sentence among them is not a name but an instruction, and eleven identical
-- instructions in a row read as an unfilled form, exactly the thing we were
-- getting away from.
--
-- Now both service modes are named the way everything else in the addon names
-- itself. "Overall Strength" is the name of the strength that decides for this
-- area, and it stands higher up on the same page. "Game's Own Look" is the same
-- wording the addon uses everywhere for the game's untouched look: "Game's Own
-- Texture" for the bars, "Game's Own Font" for the fonts, "Game's Own Button
-- Look" for the action bars.
local MODES = {
    { key = "follow",     label = "Overall Strength"           },
    { key = "native",     label = "Game's Own Look"            },
    { key = "dimmed",     label = "Dimmed",     amount = 50    },
    { key = "dark",       label = "Dark",       amount = 64    },
    { key = "moredark",   label = "More Dark",  factor = 0.20  },
    { key = "darker",     label = "Darker",     factor = 0.14  },
    { key = "moredarker", label = "Even Darker", factor = 0.08 },
    { key = "black",      label = "Black",      factor = 0     },
    -- The last two answer not the question "how dark" but the question "in
    -- what colour": the colour itself becomes the multiplier. ClassColor and
    -- Custom are arranged the same way in the example, and they stand in the
    -- same list as the brightness steps there too — because the player's
    -- choice is a single one: what to paint this area with.
    { key = "class",      label = "Class Color",  color = "class"  },
    { key = "custom",     label = "Custom Color", color = "custom" },
}
Darkness.MODES = MODES

-- A mode by its key: key -> a record out of MODES.
local MODE = {}
for i = 1, #MODES do MODE[MODES[i].key] = MODES[i] end

-- The mode an area has until the player has touched it.
local FOLLOW = "follow"
Darkness.FOLLOW = FOLLOW

-- The areas whose default is not "as the slider".
--
-- There is one such: other addons' windows.
--
-- Why they do not darken of their own accord. Somebody else's addon is
-- somebody else's work. Its colours were chosen by its author, its windows
-- were set up by the player himself, and coming in there unasked is the same
-- as repainting a neighbour's walls while he is out. The author said so
-- plainly: he hoped we did not paint third-party addons, only what concerned
-- the game.
--
-- The area stays in the settings and works all the same: whoever wants one
-- look for the whole screen sets it to "the overall strength" with a single
-- click. The default is "as in the game", that is, do not touch.
--
-- There was a second one: the quest window and the conversation with a
-- creature — the one place in the game where the text is printed DARK on
-- light, and a darkened sheet reduced the difference to nothing. The answer
-- was "do not darken that sheet at all". The author reversed that answer and
-- named another: that we could simply make it light, since our background was
-- dark — and now the sheet darkens along with everything else while the text
-- on it rises into the light (Darkness.LiftText).
local DEFAULT_MODES = {
    addons = "native",
}
Darkness.DEFAULT_MODES = DEFAULT_MODES

--- An area's mode brought to one of the known ones.
-- The setting arrives from SavedVariables: anything at all can lie there, down
-- to a mode the addon once knew and no longer knows. What is not understood
-- counts as "the overall strength" — that is, exactly what an area nobody has
-- touched has.
-- @param modes table|nil area key -> mode
-- @param group string the area's key
-- @return string the mode's key
function Darkness.ModeOf(modes, group)
    local fallback = DEFAULT_MODES[group] or FOLLOW
    if type(modes) ~= "table" then return fallback end

    local mode = modes[group]
    if type(mode) ~= "string" or MODE[mode] == nil then return fallback end
    return mode
end

--- An area's darkening strength, or nil if it is not darkened at all.
-- The only place where a mode meets the slider, and they meet by a choice
-- rather than by a multiplication.
-- @param group string the area's key
-- @param modes table|nil area key -> mode
-- @param amount number|nil the slider's value
-- @return number|nil a strength from 0 to 100, or nil
function Darkness.ModeAmount(group, modes, amount)
    local mode = Darkness.ModeOf(modes, group)
    if mode == "native" then return nil end
    if mode == FOLLOW then return tonumber(amount) or 0 end
    return MODE[mode].amount
end

--- The brightness multiplier for a slider's value.
-- A pure function. Rubbish on the input counts as a zero: the setting arrives
-- from SavedVariables, and over the years anything at all can get in there,
-- and losing the whole interface over that is not allowed.
-- @param amount number|nil the darkening from 0 to 100
-- @return number a multiplier from DARKEST to 1
function Darkness.Factor(amount)
    local value = tonumber(amount) or 0
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end

    -- The whole of the former scale, squeezed into the first seventy
    -- divisions.
    if value <= EDGE then
        return 1 - (value / EDGE) * (1 - EDGE_FACTOR)
    end

    -- The tail: from the scale's former edge to its present end.
    return EDGE_FACTOR
        - ((value - EDGE) / (100 - EDGE)) * (EDGE_FACTOR - DARKEST)
end

-- The brightness ceiling: no darkened texture stays above it.
--
-- Why it is needed. Darkening is a multiplication, and a multiplication
-- preserves ratios: a texture that was twice as light as its neighbour will
-- stay twice as light afterwards. The game's framing consists mostly of
-- half-tones (a brightness of about a half), but not all of it: the gryphons
-- at the ends of the main bar, the bar itself and the parchment of the
-- conversation window are painted almost white. At one and the same multiplier
-- a half-tone goes twice as low as white — and in a dark interface those three
-- things glow while everything around them is dark.
--
-- The author sent in exactly that: the eagles were too light, and the bar, while
-- the other elements looked darker — along with a screenshot of the conversation
-- window asking why the black was like that.
--
-- What the ceiling does. It brings a bright texture down to a half-tone BEFORE
-- the multiplication: after that the same multiplier darkens it as everything
-- else, and it arrives where its neighbours arrive. A half-tone and everything
-- darker the ceiling does not touch at all — it has nothing to bring down.
--
-- A half is the very brightness most of the framing is painted at. Taking a
-- lower number would mean quenching not the discrepancy but the picture
-- itself.
local LEVEL_CEILING = 0.5
Darkness.LEVEL_CEILING = LEVEL_CEILING

-- How much lighter the gryphons are than everything else.
--
-- The two artistic beasts at the ends of the main bar are the one place in the
-- interface the author spoke about separately and with a number: a multiplier
-- of 1.05 was to be applied to the gryphons alone. The request is exact, and it
-- is carried out literally: their area's multiplier is multiplied by that
-- number.
--
-- Why they are owed a number of their own. The brightness ceiling
-- (LEVEL_CEILING) brings the bright down to a half-tone, and the gryphons,
-- painted almost white, go where everything else goes. That was what was
-- needed: they used to glow. But having gone down with everybody, they stopped
-- reading as a drawing — and that drawing the player keeps on his screen
-- deliberately; he has a switch of his own for it. Five hundredths give them
-- back exactly enough to be seen and do not give back the glow it all started
-- with.
--
-- Their group is "actionbar-art", and it holds them alone: the names of the
-- bar's ends are listed in Core/Compat.lua and name nothing but the ends.
local GRYPHON_GROUP = "actionbar-art"
local GRYPHON_LIFT = 1.05
Darkness.GRYPHON_LIFT = GRYPHON_LIFT

-- The bar's framing images seen in this client.
--
-- Why they are remembered. The bar's framing — the gryphons and the end caps —
-- is moved across by other addons' bars: Bartender and its like build bars of
-- their own and carry the game's artwork onto them. The image's owner becomes
-- somebody else's frame after that, and its area is lost: the general pass
-- paints it as an ordinary window's framing, and inside somebody else's window
-- it does not paint at all — that is what the author asked for: we do not paint
-- third-party addons, only what concerns the game.
--
-- But a gryphon IS the game. It does not stop being so because it was rehung:
-- the rule "we do not paint somebody else's" is written about an addon's OWN
-- artwork rather than about the game's, which it carried over to itself. The
-- author named it outright: if the gryphons are rebuilt by other addons, of the
-- Bartender sort, our darkening is not applied to them.
--
-- So the belonging is decided by the image rather than by the place in the
-- tree.
local ART_IMAGES = {}

--- The bar's framing area, if the image belongs to it.
--
-- Answers only about what has already been seen: an empty memory is an empty
-- answer, and before the group is first resolved this check does nothing.
--
-- @param image any
-- @return string|nil the area's key, or nil
local function artArea(image)
    if image == nil then return nil end
    if ART_IMAGES[image] then return GRYPHON_GROUP end
    return nil
end

--- The brightness ceiling at such a darkening strength.
--
-- The ceiling does not stand still but comes down along with everything else,
-- and here is why. An area that is not darkened at all (the slider at zero, the
-- mode "as in the game", a window in the list of exceptions) is obliged to look
-- exactly as the game drew it: bringing its bright parts down to a half-tone
-- would mean repainting the interface where the player asked for it not to be
-- touched. A constant ceiling did precisely that.
--
-- So the ceiling is a straight line from one (we do not darken — we do not
-- touch) down to LEVEL_CEILING (we darken to the limit — we bring everything
-- bright down to a half-tone). A movement of the slider off zero gives no jump:
-- the ceiling leaves the one as smoothly as everything around it darkens.
--
-- @param factor number|nil the area's brightness multiplier from 0 to 1
-- @return number a ceiling from LEVEL_CEILING to 1
function Darkness.Ceiling(factor)
    local value = tonumber(factor) or 1
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end

    return LEVEL_CEILING + (1 - LEVEL_CEILING) * value
end

--- A colour brought under the brightness ceiling, with its hue preserved.
--
-- The channels are divided by a common number rather than clipped each on its
-- own. The difference is visible on anything coloured: the division turns a
-- bright green (0, 1, 0) into a dark green — the same colour — while clipping
-- the red and the blue per channel would leave the green alone and change the
-- hue of everything that is not grey.
--
-- A pure function. Rubbish on the input is not checked for: what arrives here
-- are numbers read during the reconnaissance and already checked there.
--
-- @param r number
-- @param g number
-- @param b number
-- @param ceiling number the brightness ceiling from 0 to 1
-- @return number, number, number
function Darkness.Levelled(r, g, b, ceiling)
    local top = r
    if g > top then top = g end
    if b > top then top = b end

    if top <= ceiling then return r, g, b end

    local scale = ceiling / top
    return r * scale, g * scale, b * scale
end

--- Three brightness multipliers: the darkening, coloured by the chosen tint.
--
-- A tint is not a second mechanism but the very same multiplier, one whose
-- channels are not equal to one another. A white tint (1, 1, 1) changes
-- nothing and therefore stands as the default: a fresh install is darkened but
-- not recoloured.
--
-- The tint is in effect at a zero on the slider too. That is not an oversight:
-- the darkening answers the question "how much darker", the tint "in what
-- colour", and there is no reason to demand a darkening for a colour's sake.
--
-- A channel that is absent or is not a number counts as a one: the setting
-- arrives from SavedVariables.
--
-- @param amount number|nil the darkening from 0 to 100
-- @param tint table|nil { r, g, b } from 0 to 1
-- @return number, number, number the red, green and blue multipliers
function Darkness.Multipliers(amount, tint)
    return Darkness.Tinted(Darkness.Factor(amount), tint)
end

--- A ready multiplier, coloured by a tint.
--
-- Separate from Darkness.Multipliers because the multiplier arrives from two
-- sides: out of a division of the slider (Factor) and out of a step that has a
-- number of its own (MODES, the factor field). The colouring is one and the
-- same for them, and there must be no second copy of it.
--
-- A pure function.
--
-- @param factor number the brightness multiplier
-- @param tint table|nil { r, g, b }
-- @return number, number, number
function Darkness.Tinted(factor, tint)
    if type(tint) ~= "table" then return factor, factor, factor end

    local function channel(value)
        local number = tonumber(value)
        if number == nil then return factor end
        if number < 0 then number = 0 end
        if number > 1 then number = 1 end
        return factor * number
    end

    return channel(tint.r), channel(tint.g), channel(tint.b)
end

--- The colour a step paints with, if it paints with a colour.
--
-- Two steps work by colour rather than by brightness: "class colour" takes the
-- colour from the game, "custom colour" from the player. The multiplier in both
-- cases becomes the colour itself, that is, the brightness comes out as
-- whatever the colour is.
--
-- A pure function over tables: the class arrives as a colour, the custom colour
-- as a table out of the profile. The client is not asked anything here, and
-- that is why the rule is tested outside the game.
--
-- @param group string the area's key
-- @param modes table|nil area key -> mode
-- @param colors table|nil area key -> { r, g, b }
-- @param class table|nil { r, g, b } — the player's class colour
-- @return number|nil, number|nil, number|nil
function Darkness.ModeColor(group, modes, colors, class)
    local mode = Darkness.ModeOf(modes, group)
    local entry = MODE[mode]
    local kind = entry and entry.color or nil
    if kind == nil then return nil end

    local color
    if kind == "class" then
        color = class
    else
        color = type(colors) == "table" and colors[group] or nil
    end

    if type(color) ~= "table" then return nil end

    local function channel(value)
        local number = tonumber(value)
        if number == nil then return nil end
        if number < 0 then return 0 end
        if number > 1 then return 1 end
        return number
    end

    local r, g, b = channel(color.r), channel(color.g), channel(color.b)
    if r == nil or g == nil or b == nil then return nil end

    return r, g, b
end

--- A step's own number, if it has one.
--
-- The three darkest modes lie beyond the slider's end and are expressed as a
-- multiplier rather than as a division (see MODES). Here is where it is decided
-- whom to ask: the step or the scale.
--
-- A pure function.
--
-- @param group string the area's key
-- @param modes table|nil area key -> mode
-- @return number|nil
function Darkness.ModeFactor(group, modes)
    local mode = Darkness.ModeOf(modes, group)
    local entry = MODE[mode]
    return entry and entry.factor or nil
end

--- The brightness multiplier for an area, taking its mode into account.
-- An area in the "leave it as it is" mode gets a one rather than a "skip": a
-- one restores the remembered colour, that is, it REMOVES a darkening laid on
-- earlier. A plain skip would leave the area dark forever, and the choice would
-- do nothing — precisely the defect the comment above is written for.
-- @param group string the area's key
-- @param modes table|nil area key -> mode
-- @param amount number|nil the slider's value
-- @return number the multiplier for this area
function Darkness.GroupFactor(group, modes, amount)
    local fixed = Darkness.ModeFactor(group, modes)
    if fixed ~= nil then return fixed end

    local own = Darkness.ModeAmount(group, modes, amount)
    if own == nil then return 1 end
    return Darkness.Factor(own)
end

--- Three multipliers for an area: its mode, coloured by the shared tint.
-- The same rule as Darkness.GroupFactor's, only for three channels. The tint is
-- one for the whole addon and is not overridden by a mode: it answers the
-- question "in what colour", while a mode answers "how dark".
-- @param group string the area's key
-- @param modes table|nil area key -> mode
-- @param amount number|nil the slider's value
-- @param tint table|nil { r, g, b }
-- @return number, number, number
function Darkness.GroupMultipliers(group, modes, amount, tint, colors, class)
    -- A step that paints with a colour answers first: its answer IS the
    -- multiplier, and neither the tint nor the slider adds anything to it —
    -- the player chose a colour rather than a strength.
    local cr, cg, cb = Darkness.ModeColor(group, modes, colors, class)
    if cr ~= nil then return cr, cg, cb end

    local fixed = Darkness.ModeFactor(group, modes)
    if fixed ~= nil then return Darkness.Tinted(fixed, tint) end

    local own = Darkness.ModeAmount(group, modes, amount)
    if own == nil then return 1, 1, 1 end
    return Darkness.Multipliers(own, tint)
end

-- How deep a frame's children are walked.
--
-- Why the walk descends at all. At first it did not — it took only the frame's
-- own regions — and the slider did nothing visible in the client: in today's
-- builds a unit frame's pictures lie not in the frame's regions but in its
-- child container frames (the framing, the portrait, the bars' backings). A
-- one-level walk found zero textures and honestly reported success. That was
-- the defect "the slider changes nothing".
--
-- The depth is the walk's budget rather than the rule of selection. The rule of
-- selection is below, in Darkness.IsChrome: what to darken is decided by the
-- texture's own marks rather than by the nesting level it was found at.
--
-- Four levels were right while the interface consisted of the old windows:
-- there everything visible lay in the first levels. Today's windows are built
-- differently — the talents window holds the tabs' frame, that one the tree's
-- canvas, that one the rows, and only in the rows do the pictures lie. The
-- author sent in exactly that: there was still no darkening on any of the
-- windows, the talents for instance. The walk reached the fourth level, took
-- fourteen textures of the frame and stopped short of the window itself.
--
-- Ten is not "a bit more just in case" but a measure: deeper than the tenth
-- level in the game's windows lie individual icons and models, which the rule
-- of selection does not touch anyway. The walk's price is paid once per
-- reconnaissance (see the plan below) rather than on every movement of the
-- slider.
local MAX_DEPTH = 10

-- The object types the walk does not go inside at all.
--
-- These are the interface's contents rather than its framing, and the general
-- rule ("the framing darkens, the contents do not") is applied to them as a
-- whole, together with their children, rather than to each texture
-- separately.
--
-- StatusBar — a bar of health, power or experience. A bar's fill shows a
-- magnitude, and darkening it is the same as dimming a gauge's needle. A unit
-- frame bar's colour belongs on top of that to the unit frames subsystem: two
-- owners of one colour would give a war of repaintings.
--
-- Minimap — the map of the terrain itself. That is a picture of the world
-- rather than the frame around it; the map's border lies in neighbouring
-- frames and darkens as it should.
--
-- Model and its varieties — the character's model in the character sheet, the
-- portraits of three-dimensional unit frames and the tabard's preview.
--
-- Cooldown — the fill of an ability's cooldown. It shows a time as a bar shows
-- a magnitude, and quenching it means taking a reading away from the
-- player.
local SKIP_TYPES = {
    StatusBar       = true,
    Minimap         = true,
    Model           = true,
    PlayerModel     = true,
    DressUpModel    = true,
    CinematicModel  = true,
    TabardModel     = true,
    Cooldown        = true,
}

-- The fields a frame keeps its contents in rather than its framing.
--
-- A unit frame's portrait and a button's icon are assigned a file by a numeric
-- identifier rather than by a path. The general rule below catches them without
-- this list too, but their owner knows about them earlier and more exactly, and
-- an extra check here costs one comparison.
local CONTENT_FIELDS = {
    "portrait", "Portrait", "PortraitTexture", "portraitTexture",
    "icon", "Icon", "IconTexture", "iconTexture", "SpellIcon",

    -- A bar's fill that a frame keeps in a field rather than as a bar.
    --
    -- That is how the skill bar in today's builds' professions window is
    -- built: ProfessionsFrame.RankBar is an ordinary frame, and its fill lies
    -- in the Fill field. It has no global name, it is not a StatusBar object,
    -- and its picture is an ordinary one — that is, not one of the former
    -- marks saw it, and it darkened and greyed out along with the framing. The
    -- author sent that window in four times.
    --
    -- The mark here is not a piece of a name but a field on the owner: it is
    -- the frame itself that is asked, and "Fill" on a frame means exactly one
    -- thing — a fill.
    "fill", "Fill", "BarFill", "barFill",

    -- The flash of a frame whose unit is fighting.
    --
    -- The target frame puts a red glow around the portrait while the target is
    -- in combat, and pulses it. That glow is the frame answering a question -
    -- is this thing fighting - in the same way the grey of a mob somebody else
    -- tapped answers "is this kill yours". Darkened, the answer turns black
    -- and stops being one, and because the game shows the glow again on every
    -- pulse, we darkened it again on every pulse: a red light flickering black
    -- for as long as the fight lasted.
    --
    -- The same field holds the yellow flash on an action button while the
    -- autoattack is swinging, which is a reading for the same reason.
    "flash", "Flash",
}

-- The pieces of a name by which a texture is recognised as contents.
--
-- The interface's textures in the client are sometimes named, and their names
-- speak: PlayerPortrait, TargetFramePortrait, ActionButton1Icon. The mark is a
-- crude one — by substring — and that is deliberate: an extra undarkened
-- picture costs nothing, while a darkened portrait of the character the author
-- has already seen and called a defect.
--
-- There are no pieces about the bars here, and that is a correction made after
-- a screenshot.
--
-- There used to be: "statusbar" and "fill", out of the reasoning "a bar's fill
-- names itself". The pieces caught things other than fills: the character sheet
-- stayed golden, and the author sent it in with the word "broken". A bar's fill
-- is recognised by an exact question put to the frame itself
-- (GetStatusBarTexture in the walk) and by the rule about a coloured fill with
-- no picture — it must not be guessed at by a piece of a name.
--
-- "flash" stands here as well as in the fields above, because the two client
-- lines reach the same glow by different roads: the older frames name it
-- (TargetFrameFlash), the newer ones keep it only in a field of its owner. A
-- name is asked before the atlas, so the older road does not depend on how the
-- glow happens to be drawn.
local CONTENT_NAMES = { "portrait", "icon", "flash" }

-- The pieces of an OWNER's name by which a picture is recognised as contents.
--
-- Why a second list about names, and why about somebody else's name. The money
-- rule below is written as a rule about the path to a file — "moneyframe",
-- "ui-goldicon" — and in this client it never fires: GetTexture answers with a
-- number even for a texture that was assigned by a path, and the probe shows
-- that in every window at once ("file 134939", "file 130718", not one path
-- among them). A picture named by a number reaches the rule for numbers, its
-- number is not in the short list there, and the answer comes out "framing".
-- So the coins went black, and "fifty eight" stopped saying fifty eight of
-- what.
--
-- Three numbers could be added to CONTENT_FILES instead. They would fix three
-- coins in one build, and the next build renumbers them. The frame that holds
-- a coin carries the same name in every build, while the coin itself has
-- neither a name nor a field on its owner — it is a button's normal texture.
-- The owner is the only stable mark it has.
--
-- The list is deliberately short and about one thing. It is not a place for
-- "everything that looked wrong": a piece of somebody else's name is a blunt
-- instrument, and the character sheet has already been lost once to exactly
-- that kind of guessing (the note above this one).
local CONTENT_OWNERS = {
    "moneyframe", "goldbutton", "silverbutton", "copperbutton",
}

-- The pieces of file paths by which a picture is recognised as contents.
--
-- The icons folder — a spell or an item: by an icon the player recognises an
-- ability, and recoloring it means taking his means of recognition away.
--
-- The sheet of class circles — the very class icon the author saw darkened on a
-- unit frame. It lies as one shared file while the circle needed is cut out of
-- it by coordinates, which is why it is visible by its path.
--
-- The fallback portrait — the picture the game puts up while a unit's real
-- portrait is unknown. It is a portrait, and the rule for it is the same.
local CONTENT_PATHS = {
    "interface\\icons", "interface/icons",
    "ui-classes-circles",
    "temporaryportrait",

    -- Money and currency. Gold, silver and copper are three different
    -- circles, and the player tells them apart by colour: darkened, they
    -- become identically brown, and "sixty-eight" stops saying sixty-eight of
    -- what.
    --
    -- This is the same rule by which a spell's icon does not darken, and the
    -- case is the same: a picture one recognises something by rather than the
    -- frame around it.
    "moneyframe",

    -- The game's menu buttons at the bottom of the screen. A button's
    -- picture IS its icon: the quest scroll, the bag, the spellbook — the
    -- player has no other way of telling one from another. There is no frame
    -- around them as a separate texture at all, so the darkening ate the icon
    -- itself: the author sent in a screenshot of the bottom row in which not
    -- one button could be recognised.
    "ui-microbutton",

    -- Below is the list of the very addon the author gave as an example
    -- (DarkMode, MIT, the same author; a copy of the notice is in
    -- docs/backlog.md). There it is called the block of textures and answers
    -- the same question as this whole enumeration: which picture must not be
    -- darkened, because it is not framing but a thing.
    --
    -- Taken whole and word for word, because the author said to take it:
    -- everything in DarkMode was done nicely and the way he wanted, so why
    -- could I not copy it. The numeric identifiers of pictures from that list
    -- were not carried over here — with us any picture named by a number counts
    -- as contents anyway.
    --
    -- The first rows of the list are the most important ones: these are the
    -- fills of the game's bars.
    --
    -- A bar is a gauge: its fill shows a magnitude, and the fill's colour says
    -- a magnitude of what. It must neither be darkened nor drained of colour,
    -- and the second the author said separately, having seen a grey profession
    -- bar: with "grey out the artwork" switched on, that did not mean the
    -- game's sliders for professions and so on were to be grey too.
    --
    -- The path is written out whole rather than as a piece, and that is a
    -- correction made after a screenshot.
    --
    -- At first there stood pieces — "statusbar", "skill-bar", "xp-bar" — out of
    -- the reasoning "there are a dozen fills in the game and they are all named
    -- alike". The pieces caught more than the fills: the section headers in the
    -- character sheet are drawn with that same skill bar, and the window stayed
    -- golden in the middle of a dark interface — the author sent it in asking
    -- why there was no grey-out there. Guessing by a piece of a name is not
    -- allowed; DarkMode's list names exactly one picture, and it is the fill of
    -- any bar of the game's.
    "targetingframe\\ui-statusbar",
    "questframe\\ui-questlog-bookicon",
    "spellbook\\spellbook-icon",
    "spellbook-skilllinetab-glow",
    "friendsframescrollicon",
    "macroframe\\macroframe-icon",
    "mailframe\\mail-icon",
    "timemanager\\globeicon",
    "containerframe\\ui-bag-1slot",
    -- The button pictures from DarkMode's list are not here, and that is a
    -- correction made after four screenshots in a row.
    --
    -- There "ui-panel-button-up", "ui-checkbox-check", "ui-minusbutton-up" and
    -- the buttons' highlights are blocked. Having taken them for ourselves, we
    -- got golden "Horde", "Bandages" and "General" headers and yellow "minus"
    -- buttons in the middle of dark windows: in DarkMode the buttons are
    -- painted by a separate pass with its own colour, and the block is needed
    -- there so as not to paint them twice, while we have no second pass and the
    -- block simply meant "do not touch".
    --
    -- The highlights under the cursor did not vanish along with the list: they
    -- are taken off by the layer rule (SKIP_LAYER, HIGHLIGHT), and that one is
    -- about the whole interface at once rather than about four file names.

    -- The role icons in the group finder: the shield, the cross, the sword.
    -- This too is recognition, and the price is the same: three identically
    -- brown circles do not say who the tank is.
    "ui-lfg-icon",
    "lfgrole",
    "ui-goldicon", "ui-silvericon", "ui-coppericon",
    "currency",

}

-- The pieces of atlas names by which a picture is recognised as contents.
--
-- An atlas in itself is a mark of framing (see the rule below), and this list
-- is short for exactly that reason: what is cut out of a shared sheet is not
-- only framing but also the class icons, the race icons and the quest
-- portraits. The word "portrait" is not among them:
-- "UI-HUD-UnitFrame-Player-PortraitOn" is the ring around the portrait, that
-- is, framing.
--
-- An atlas is read by the same rule as a path and for the same reason: an
-- atlas's name says what is in the picture.
--
-- "roleicon" and "microbutton" are the same two things as in the paths above:
-- on today's clients some of these pictures are declared as an atlas and some
-- as a path, and it is not the addon that chooses which.
--
-- "micromenu" is the same name in a new spelling. In this client the bottom row
-- of buttons is named by atlases of the form "UI-HUD-MicroMenu-GameMenu-Up",
-- and the piece "microbutton" does not catch them: the author sent in a
-- darkened row in which not one button could be recognised. A menu button's
-- picture IS its icon — the quest scroll, the bag, the spellbook — and the
-- player has no other way of telling one from another.
local CONTENT_ATLASES = {
    "classicon", "raceicon", "questportrait",
    "roleicon", "microbutton", "micromenu", "lfg-icon",

    -- The markers that say what a quest is and what state it is in: the
    -- bang, the question mark, the turn-in, the number on a pin, the
    -- storyline mark. Darkened, they become identical grey blobs, and the
    -- tracker stops saying which of its lines is ready to hand in - the same
    -- loss as three identically brown circles not saying who the tank is,
    -- which is why the role icons are two lines above.
    --
    -- The author reported these going dark, and the names are read off his
    -- own probe rather than guessed: the frames, tiles, tabs and backgrounds
    -- of the quest log sit in the same list of atlases and are deliberately
    -- NOT here - they are framing and are meant to darken. That is why these
    -- are the marker families by name and not the word "quest".
    "ui-questpoi", "ui-questicon", "questnormal",
    "quest-in-progress-icon", "questlog-storylineicon", "taskpoi",
    "questlog-icon-checkmark", "questlog-icon-ticksquare",
    "waypoint-mappin", "questionmark",

    -- The red frame around a portrait while that unit is fighting.
    --
    -- The frame of a unit comes in variants of one atlas, and the client
    -- swaps between them: "UI-HUD-UnitFrame-Target-PortraitOn" ordinarily,
    -- "...-PortraitOn-InCombat" while the target is in combat. The second is
    -- red, and red is the whole of what it says.
    --
    -- Darkened, both came out the same near-black, so the swap stopped being
    -- an answer and became a flicker - which is how the author reported it,
    -- in a fight, watching his target's frame go from red to black and back.
    --
    -- The ordinary variant beside it is framing and goes on darkening: it is
    -- the same metal as the rest of the interface and says nothing. Only the
    -- variant whose name says "in combat" is spared, and it is spared for
    -- every unit frame that has one at once.
    "-incombat",
}

-- The layer that is not subject to darkening.
--
-- HIGHLIGHT is the highlight under the cursor. The engine shows it over
-- everything else and only while the cursor is in place. Having darkened it, we
-- would have taken away a button's response to a hover, that is, made it
-- indistinguishable from one that does not work — precisely the defect the
-- button states in Skin/ are written for.
--
-- There are no other layers on this list, and that is a decision rather than an
-- oversight. There was an attempt to separate a backing from the things on it
-- by layer: BACKGROUND and BORDER darken, ARTWORK and OVERLAY do not. The mark
-- turned out to be no good — the game draws half the windows' backings on
-- ARTWORK too, and the darkening stopped reaching the windows themselves, that
-- is, the one thing it exists for. What separates the things from the backings
-- is the list of pictures below (CONTENT_PATHS) and the rule about the bars
-- (see the walk) — the same way DarkMode, the addon the author gave as an
-- example, separates them.
local SKIP_LAYER = "HIGHLIGHT"

--- An object of the game's type, or nil.
-- @param object table
-- @return string|nil
local function objectType(object)
    if type(object) ~= "table" or type(object.GetObjectType) ~= "function" then
        return nil
    end
    local ok, value = pcall(object.GetObjectType, object)
    if not ok then return nil end
    return ns.Skin.Textual(value)
end

--- A string from an object, if the method exists and returned one.
-- @param object table
-- @param method string
-- @return string|nil
local function stringFrom(object, method)
    if type(object) ~= "table" or type(object[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(object[method], object)
    if not ok then return nil end
    return ns.Skin.Textual(value)
end

--- Ask an object for another object, and answer nothing if it cannot.
--
-- The same shape as stringFrom and for the same reason: every question put to
-- a frame of the game's may fail, and a failed question is "no answer" rather
-- than an error travelling up through the walk. No secret-value guard here —
-- the answer is an object, and nothing is read out of it on this line.
--
-- @param object table
-- @param method string
-- @return table|nil
local function objectFrom(object, method)
    if type(object) ~= "table" or type(object[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(object[method], object)
    if not ok or type(value) ~= "table" then return nil end
    return value
end

--- An object's picture: a path to a file or its numeric identifier.
-- The difference between them is the main mark of selection, which is why a
-- number here is neither converted to a string nor thrown away.
-- @param object table
-- @return string|number|nil
local function imageOf(object)
    if type(object) ~= "table" or type(object.GetTexture) ~= "function" then
        return nil
    end
    local ok, value = pcall(object.GetTexture, object)
    if not ok then return nil end
    local text = ns.Skin.Textual(value)
    if text then return text end

    -- The number is passed through ns.Skin.Numeric rather than returned as
    -- it is.
    --
    -- The engine returns the numbers of protected pictures as "secret" ones:
    -- such a number can be compared but cannot be taken as a table's key — the
    -- attempt ends with the line "attempted to index a table that cannot be
    -- indexed with secret keys" in a file that is none of ours. The author sent
    -- it in: the walk reached CooldownViewer right after a death.
    --
    -- A number that cannot be computed over means "there is no picture": what
    -- decides after that is the colour, and it is read by the same check and
    -- just as safely.
    if type(value) == "number" then return ns.Skin.Numeric(value) end
    return nil
end

--- Remember the bar's framing images as they exist in this client.
--
-- The list is not written down as paths but asked of the client: whatever the
-- compatibility layer found in the framing group is what is remembered. A path
-- written by hand would be a guess about somebody else's client, while this is
-- what is in it.
--
-- The group may be absent entirely (the compatibility layer is still silent) —
-- then the memory stays empty, and recognition by picture simply does
-- nothing.
local function learnArt()
    local ok, names, objects = pcall(ns.Compat.Resolve, GRYPHON_GROUP)
    if not ok or type(objects) ~= "table" then return end

    for i = 1, #objects do
        -- Both the path and the file's number are remembered. An addon sets
        -- its own artwork by path and the game sets its own by number, and
        -- taking the strings alone would mean being left with an empty memory
        -- on the very client all this is written for.
        --
        -- By this moment the number is already safe: imageOf passes it through
        -- ns.Skin.Numeric, and no secret value comes out of there — such a
        -- number cannot be a table's key.
        local image = imageOf(objects[i])
        if image ~= nil then ART_IMAGES[image] = true end
    end
end

--- How many of the bar's framing images are remembered.
-- A door outwards for the tests' sake: "recognition by picture did not work"
-- has two different causes — we did not remember and we did not recognise — and
-- there is nothing else to tell them apart from outside.
-- @return number
function Darkness.ArtCount()
    local n = 0
    for _ in pairs(ART_IMAGES) do n = n + 1 end
    return n
end

--- Whether this is a texture.
-- The only type the darkening is allowed on at all. A font string is text, a
-- model is not a picture, and a mask is the shape of a cut-out rather than an
-- image.
-- @param object table
-- @return boolean
local function isTexture(object)
    return objectType(object) == "Texture"
end

--- Whether this is a label.
-- @param object table
-- @return boolean
local function isText(object)
    return objectType(object) == "FontString"
end

--- Whether a string contains one of the substrings.
-- @param haystack string already in lower case
-- @param needles table
-- @return boolean
local function containsAny(haystack, needles)
    for i = 1, #needles do
        if haystack:find(needles[i], 1, true) then return true end
    end
    return false
end

-- The pictures named by a file number that must not be darkened.
--
-- Where the list comes from. It is taken from DarkMode (its data.lua,
-- DMTextureBlockGroups, MIT, the same author; the notice is in
-- docs/backlog.md) together with the numbers: the icons of the quest log, the
-- spellbook, the mail, the friends list, the macros and the battleground, a
-- bar's fill, the buttons' highlights, the chat tabs.
--
-- Why it is needed as a list specifically. There used to stand a rule here: "a
-- number instead of a path means contents" — a path is written in XML for
-- framing, while a number is substituted by the game when a picture becomes
-- known as things go along: an item's icon, a portrait. The rule is right for
-- the old builds and no good for today's: in client 5.5 almost everything is
-- named by a number, section headers and window frames included, and the
-- darkening stopped reaching them. The author sent in four screenshots in a row
-- — golden "General", "Primary Attributes", "Weapons", "Horde", "Bandages" —
-- and one line: nothing had changed of what he had asked for.
--
-- The icons stayed untouched in the process without this rule too: they are
-- caught by name (CONTENT_NAMES: ActionButton1Icon,
-- ContainerFrame1Item1IconTexture, CharacterHeadSlotIconTexture) and by the
-- path to the icons folder.
local CONTENT_FILES = {
    [130709] = true,   -- the battleground icon
    [131116] = true,   -- the friends window icon
    [136377] = true,   -- the macro window portrait
    [136382] = true,   -- the mail icon
    [136797] = true,   -- the quest log icon
    [136830] = true,   -- the spellbook icon
    [137012] = true,   -- a bar's fill
}

-- What is not on this list and why.
--
-- In the same place DarkMode has the buttons' highlights (130717, 130718,
-- 130719, 130724), the chat tabs' pictures (374168...374178) and half a dozen
-- numbers with no explanation in the "Other" group (130832, 413584, 442272,
-- 526421, 1500877, 2056011). All of them were taken along with the list — and
-- all of them were removed.
--
-- The reason is the same one the button PATHS were removed for: in DarkMode the
-- buttons, the tabs and the highlights are painted by a separate pass with its
-- own colour, and it needs the block so as not to paint them twice. We have no
-- second pass, and the block simply means "do not touch" — while in this
-- client, where the pictures are named by numbers, section headers fell under
-- those numbers: "Horde", "Professions", "Weapon Skills", "Character". The
-- author sent them in golden out of four windows in a row.
--
-- The highlight under the cursor has not gone anywhere in the process: it is
-- taken off by the layer rule (SKIP_LAYER, HIGHLIGHT), one for the whole
-- interface.

-- How coloured a fill has to be to count as a reading.
--
-- The measure is the spread of the channels: for grey, white and black it is
-- zero, and for any colour it grows with the colour's saturation. Fifteen
-- hundredths is the boundary beyond which a colour is already named: a dark blue
-- skill bar (0.12, 0.30, 0.60) gives 0.48, while a window's brown backing
-- (0.24, 0.20, 0.16) gives eight hundredths.
local FILL_CHROMA = 0.15

--- Whether this is a coloured fill with no picture.
--
-- Why such a rule. A bar drawn not by a file but by a colour
-- (SetColorTexture) looks to the walk like a backing: no name, no atlas, no
-- path. That used to count as framing and darkened along with everything else,
-- and with the draining of colour switched on it greys out as well — the author
-- sent in a skill bar asking why its fill was still grey when it was supposed
-- to be the default.
--
-- A fill's colour IS its meaning: by blue the game says "a skill", by green "a
-- reputation", by red "health". Grey and white do not fall in here: such a fill
-- names nothing and remains a backing.
--
-- The remembered colour is the one asked for, if there is one: after the first
-- application it is already ours that stands on the object, and deciding by it
-- would mean deciding by our own answer.
--
-- @param region table
-- @return boolean
local function isColorFill(region)
    local base = BASE[region]
    local r, g, b

    if base then
        r, g, b = base[1], base[2], base[3]
    else
        if type(region.GetVertexColor) ~= "function" then return false end
        local ok, cr, cg, cb = pcall(region.GetVertexColor, region)
        if not ok then return false end
        r, g, b = ns.Skin.Numeric(cr), ns.Skin.Numeric(cg), ns.Skin.Numeric(cb)
    end

    if r == nil or g == nil or b == nil then return false end

    local high, low = r, r
    if g > high then high = g end
    if b > high then high = b end
    if g < low then low = g end
    if b < low then low = b end

    return (high - low) >= FILL_CHROMA
end

--- Why this texture is contents rather than framing. A nil means "framing".
--
-- The only place where the decision "to darken or not" is made.
--
-- How it is built and why exactly so. The former rule decided by the ABSENCE of
-- marks: a texture whose name says nothing and whose path says nothing is
-- framing. It missed symmetrically and missed in the client by both ends at
-- once. A unit frame's portrait in today's builds is created without a name,
-- and its picture is assigned by a file number (SetPortraitTexture), so by the
-- former rule it came out as "framing" — the author saw a darkened class icon.
-- And the windows that were not on the list of names did not darken at all.
--
-- The new rule decides by the PRESENCE of marks and demands proof that what is
-- before us is a picture of framing:
--
--   1. The type. Only a Texture is darkened. A font string is text, and it is
--      obliged to be readable at any position of the slider; a model and a
--      mask are not pictures at all.
--   2. The layer. The highlight under the cursor (HIGHLIGHT) is a response
--      rather than framing.
--   3. The name. PlayerPortrait, ActionButton1Icon: a portrait and an icon are
--      named for what they are.
--   4. The atlas. An atlas is a piece of a shared sheet of framing, and it is
--      not used otherwise: a portrait and an item's icon are never an atlas. So
--      any atlas is framing, even if the word portrait stands in its name:
--      "UI-HUD-UnitFrame-Player-PortraitOn" is the ring around the portrait
--      rather than the portrait itself.
--   5. The path to a file. Everything out of the icons folder is a spell or an
--      item. Everything else that has a path is a file of framing.
--   6. A file number instead of a path. That is how a picture is assigned at
--      the moment it becomes known: a unit's portrait, an item's icon, a
--      spell's icon. Framing is not assigned that way — it lies in XML by a
--      path or an atlas. That is the very mark the former rule lacked.
--   7. There is no picture at all. That is a fill by colour (SetColorTexture)
--      or a texture not yet assigned one. Such a thing is never contents.
--
-- A pure function over an object: all it needs is five methods, and that is
-- faked with a table, so the rule is tested without a client.
--
-- @param region table the region object
-- @return string|nil the reason it is contents
function Darkness.ContentReason(region)
    if not isTexture(region) then return "type" end

    if stringFrom(region, "GetDrawLayer") == SKIP_LAYER then return "layer" end

    local name = stringFrom(region, "GetName")
    if name and containsAny(name:lower(), CONTENT_NAMES) then return "name" end

    -- The owner's name. A coin has none of its own and sits in no field: it is
    -- the normal texture of a button, and the only thing that says what it is
    -- is the frame holding it. Asked here, before the atlas and the number,
    -- because both of those answer "framing" for it.
    local owner = stringFrom(objectFrom(region, "GetParent"), "GetName")
    if owner and containsAny(owner:lower(), CONTENT_OWNERS) then
        return "owner"
    end

    local atlas = stringFrom(region, "GetAtlas")
    if atlas then
        if containsAny(atlas:lower(), CONTENT_ATLASES) then return "atlas" end
        return nil
    end

    local image = imageOf(region)
    if type(image) == "string" then
        if containsAny(image:lower(), CONTENT_PATHS) then return "path" end
        return nil
    end
    if type(image) == "number" then
        if CONTENT_FILES[image] then return "file" end

        -- Everything else named by a number is framing.
        --
        -- For a short while a correction stood here: "on a button a number
        -- means an icon" — the game puts items' and spells' icons on buttons
        -- specifically. The mark turned out to be no good, and precisely
        -- because section headers are made as buttons in the game too —
        -- "Professions", "Weapon Skills", "Horde" — the very ones a number
        -- stopped meaning contents for. The author sent them in golden twice.
        --
        -- The icons did not darken as a result of this: they are recognised by
        -- their name (CONTENT_NAMES: ActionButton1Icon,
        -- ContainerFrame1Item1IconTexture), by a frame's field
        -- (CONTENT_FIELDS: icon, Icon, portrait) and by the path to the icons
        -- folder.
        return nil
    end

    -- There is no picture at all: a fill by colour. A coloured one is a
    -- reading, a grey one a backing (see isColorFill).
    if isColorFill(region) then return "fill" end

    return nil
end

-- The rule of selection's ready answer: picture -> whether it is framing.
--
-- Why remember it. The rule asks a picture five things — its layer, its name,
-- its atlas, its path and its colour — and every question goes through a
-- protected call. It is asked more than once: the walk comes back into a window
-- when it is shown, when a tab is switched, on the server's answer — and every
-- time it finds out the same thing about the same picture afresh. And the answer
-- is one and the same: a region's name, layer and picture do not change until it
-- is handed out of a pool again.
--
-- The memory lives for one generation of the plan. The plan is cleared exactly
-- when the interface's composition could have changed (entering the world, a
-- load-on-demand addon of the game's, a change of setting) — that is, at the
-- same time the former answers stop being reliable.
local VERDICT = ns.Skin.Memory()

--- Whether this is framing, with a memory for the plan's generation.
-- @param region table
-- @return boolean
local function chromeOf(region)
    local known = VERDICT[region]
    if known ~= nil then return known end

    local answer = Darkness.IsChrome(region)
    VERDICT[region] = answer
    return answer
end

-- The answer to "whose artwork is this", with the same memory for the plan's
-- generation.
--
-- Without the memory the question would cost a reading of the picture of every
-- region of the interface on every walk — and a repeated walk of a window would
-- stop being free. That was caught by the measurement of the cost rather than by
-- the client.
local ART_MEMO = ns.Skin.Memory()

--- The bar's framing area for a region, with a memory.
-- @param region table
-- @return string|nil
local function artOf(region)
    local known = ART_MEMO[region]
    if known ~= nil then
        if known == false then return nil end
        return known
    end

    local answer = artArea(imageOf(region)) or false
    ART_MEMO[region] = answer
    if answer == false then return nil end
    return answer
end

-- The area in which an icon is not contents but an object of the darkening.
--
-- The rule "an icon does not darken" stands for the whole interface and stands
-- rightly: by an icon one recognises an item, a spell, a bar's button. With the
-- buffs and debuffs it is otherwise: there the icon is ALL there is, it has no
-- framing at all, and the "Buffs and Debuffs" area in the settings would answer
-- for nothing. The author asked shortly: why are the buffs not darkened.
--
-- The example is built the same way: in DarkMode the buffs and debuffs are a
-- type of their own with a colour of their own, and it is their pictures it
-- paints.
local ICON_AREA = "auras"

--- Whether this is framing or contents.
-- The reverse side of Darkness.ContentReason: there is a reason — it is
-- contents; there is no reason — it is framing.
-- @param region table the region object
-- @return boolean
function Darkness.IsChrome(region)
    return Darkness.ContentReason(region) == nil
end

--- Darken one texture.
-- Works with any object that has GetVertexColor and SetVertexColor, so it is
-- tested on a stand-in texture, without a client.
-- There are one or three multipliers: one is an ordinary darkening, three a
-- darkening with a tint. An absent second and third equal the first.
--
-- The rule of selection is asked here rather than in the pass alone, and that
-- is not excess strictness. The colour is changed in one single place in the
-- addon, and the rule "the contents do not darken" is obliged to stand in
-- exactly that place: SetVertexColor belongs to a font string and to a model
-- too, and Tint already has four callers. Resting the rule on their discipline
-- means waiting for a fifth — and darkened text the author has already seen in
-- the client.
--
-- A colour that cannot be computed over. Some objects return their colour as
-- "secret" numbers: such a number can be taken but an addon must not multiply
-- it — the engine brings the execution down (see ns.Skin.Numeric). That is what
-- used to happen: the pass reached such an object, the multiplication inside
-- Shade fell over, and the subsystem switched itself off together with its own
-- settings section. Now the colour's usability is asked about before the
-- multiplication, the object silently stays in its native look, and the counter
-- of refusals (ns.Counters.blocked_darkness) counts them: silent inaction
-- without a trace would be worse than an error.
--
-- A refusal is not remembered on the object. Secrecy is a property not of a
-- texture but of the state of execution, and a texture unavailable now may turn
-- out to be available on the next pass. The price of a second attempt is one
-- protected call, and paying it is cheaper than striking a window out of the
-- darkening forever.
--
-- @param texture table the texture object
-- @param factor number the brightness multiplier (of the red)
-- @param fg number|nil the green's multiplier
-- @param fb number|nil the blue's multiplier
-- @return boolean whether it was applied
function Darkness.Tint(texture, factor, fg, fb)
    if type(texture) ~= "table" then return false end
    if not Darkness.IsChrome(texture) then return false end
    if type(texture.GetVertexColor) ~= "function" then return false end
    if type(texture.SetVertexColor) ~= "function" then return false end

    local base = BASE[texture]
    if not base then
        -- The colour is read exactly once — at the moment it has not yet
        -- been touched by us.
        local ok, r, g, b, a = pcall(texture.GetVertexColor, texture)
        if not ok then return false end

        r, g, b = ns.Skin.Numeric(r), ns.Skin.Numeric(g), ns.Skin.Numeric(b)
        if r == nil or g == nil or b == nil then
            counters.blocked_darkness = counters.blocked_darkness + 1
            return false
        end

        base = { r, g, b }
        BASE[texture] = base
    end

    local r, g, b = ns.Skin.Shade(base[1], base[2], base[3], factor, fg, fb)

    -- The multiplier comes out of our own arithmetic and is obliged to
    -- compute. Should Shade refuse all the same, there is nothing to write:
    -- the colour stays native.
    if r == nil then
        counters.blocked_darkness = counters.blocked_darkness + 1
        return false
    end

    -- The transparency is not ours, and it must not be touched by a hair.
    -- That is not taste but a defect that has already happened: the whole
    -- styling layer quenches the game's native pictures by transparency
    -- (SetAlpha(0), a vertex alpha of zero), and the darkening, having written
    -- the transparency along with the colour, brought them back onto the
    -- screen. The author saw that as the buttons being the standard red
    -- again.
    --
    -- And the transparency written was the remembered one — the one that was on
    -- the texture at the moment of the first touch, that is, as a rule, before
    -- the styling. So it is not remembered at all any more: if it has to be
    -- given to SetVertexColor, it is taken afresh, right now, and returned
    -- exactly as it was. There is no arithmetic over it — the value passes
    -- straight through, and a secret one passes on a par with an ordinary one.
    --
    -- The three-argument form is not enough: without a fourth argument the
    -- engine sets the transparency to one, that is, does precisely what is not
    -- allowed here. It remains only for the case where there is nothing to
    -- read.
    local okRead, _, _, _, alpha = pcall(texture.GetVertexColor, texture)

    local ok
    if okRead and alpha ~= nil then
        ok = pcall(texture.SetVertexColor, texture, r, g, b, alpha)
    else
        ok = pcall(texture.SetVertexColor, texture, r, g, b)
    end
    return ok and true or false
end

--- Gather the regions a frame keeps as its own contents.
-- A portrait and an icon are assigned by a file's numeric identifier, and they
-- cannot be told apart by the texture itself. Their owner, however, keeps them
-- in a field with a speaking name — and that is what we use.
-- @param frame table
-- @return table a set of objects
--- Whether a picture sitting in an owner's icon field is really contents.
--
-- The field rule exists for an item's icon and a unit's portrait: the owner
-- knows what they are earlier and more exactly than any look at the picture
-- would. What it does not know is that today's templates keep their OWN
-- artwork in a field of the same name. The author's probe of the character
-- sheet named them one after another:
--
--     content: owner field, atlas common-icon-zoomin
--     content: owner field, atlas common-icon-rotateleft
--     content: owner field, atlas common-stat-bar-green
--
-- Those are the model's turn buttons and a stat bar - framing, spared as
-- though they were a player's face, and left bright in a dark window.
--
-- The question that separates them is already answered in this file, by the
-- rule about atlases: "a portrait and an item's icon are never an atlas". An
-- atlas is a piece of a shared sheet, which is how framing is drawn and how
-- contents never are. So a picture in an icon field that comes from an atlas
-- is framing, and only the handful of atlases this file already calls
-- contents keep their exemption.
--
-- @param region table
-- @return boolean
local function fieldIsContent(region)
    local atlas = stringFrom(region, "GetAtlas")
    if atlas == nil then return true end
    return containsAny(atlas:lower(), CONTENT_ATLASES)
end

local function contentRegions(frame)
    local set = {}
    for i = 1, #CONTENT_FIELDS do
        local region = frame[CONTENT_FIELDS[i]]
        if type(region) == "table" and fieldIsContent(region) then
            set[region] = true
        end
    end
    return set
end

-- The areas in which raising text is allowed right now: area key -> true.
--
-- Why the area is asked about. The raising decides by the colour of the label
-- itself: a dark one is raised, a light one is not. That is enough exactly as
-- long as the sheet under the label darkens. An area the player set to "as in
-- the game" stays light — and dark text on it is obliged to stay dark, or the
-- result is white on light, that is, the same unreadability from the other
-- side. The author sent in exactly such a screenshot: the light parchment of a
-- conversation and white letters on it.
--
-- The table is computed once per reconnaissance rather than once per label:
-- there are ten areas and thousands of labels.
local LIFT = {}

--- Recompute where the raising of text is allowed.
local function refreshLift(settings)
    for i = 1, #GROUPS do
        local key = GROUPS[i].key
        LIFT[key] = settings ~= nil
            and Darkness.GroupFactor(key, settings.mode, settings.amount) < 1
    end
end

-- The hidden frames whose showing we are watching: frame -> true.
local SHOWN_WAIT = ns.Skin.Memory()

-- The walk of a subtree, declared in advance: it stands further down the file
-- (it needs the plan and the slices) while it is called from here.
local sweepShown

--- Whether the game just said this frame was being hidden.
--
-- Why a function for one boolean.
--
-- The hook was written as "if not on then return end", and the author's error
-- log says what that costs here:
--
--     Darkness.lua:1665: attempt to perform boolean test on local 'on'
--     (a secret boolean value, while execution tainted by 'Darken')
--
-- The client hands out secret values for things an addon may not read, and a
-- plain test on one throws. The throw happens inside the hook, so the walk
-- that was to follow never runs - and a window that is never walked is a
-- window that stays bright. That is the shape of several complaints at once.
--
-- Skin.Truth cannot be used here, and the reason is worth writing down: it
-- answers false both for "this is false" and for "this cannot be read", and
-- those two must part company in this one place. Unreadable has to mean
-- SHOWN, because walking a frame that was in fact hidden costs one pass and
-- changes nothing anybody can see, while skipping one that was shown leaves
-- it light. The same rule the pictures follow: the unknown is read in favour
-- of work.
--
-- @param on any what the game passed to SetShown
-- @return boolean true only when it is readable AND says hidden
function Darkness.ToldHidden(on)
    local ok, hidden = pcall(function() return not on end)
    if not ok then return false end
    return hidden == true
end

--- Watch for the moment the hidden is shown.
--
-- The watcher is placed on the frame itself and only once: there are not many
-- such frames — list rows, tabs, a pool's reserve — and each of them is shown
-- rarely.
--
-- @param frame table
-- @param area string|nil the area the frame belongs to
local function watchShown(frame, area)
    if SHOWN_WAIT[frame] then return end
    if type(_G.hooksecurefunc) ~= "function" then return end

    -- The game can show a frame in two ways, and both have to be listened
    -- to.
    --
    -- Show is the obvious one. SetShown(true) is the one the new list
    -- interface uses, and it does not call Show: a watcher hung on Show alone
    -- stayed silent the whole way. The author's reconnaissance showed exactly
    -- that: the header's plate was left without the colour written for it.
    local watched = false

    if type(frame.Show) == "function" then
        if pcall(_G.hooksecurefunc, frame, "Show", function(self)
            if type(sweepShown) == "function" then
                pcall(sweepShown, self, area)
            end
        end) then
            watched = true
        end
    end

    if type(frame.SetShown) == "function" then
        if pcall(_G.hooksecurefunc, frame, "SetShown", function(self, on)
            -- It was hidden — there is nothing to walk: the next showing
            -- will call again.
            if Darkness.ToldHidden(on) then return end
            if type(sweepShown) == "function" then
                pcall(sweepShown, self, area)
            end
        end) then
            watched = true
        end
    end

    if watched then SHOWN_WAIT[frame] = true end
end

--- Everything a method of the game's returns, as an array.
-- @param method function
-- @param object table
-- @return table
local function gather(method, object)
    return { method(object) }
end

-- The name prefixes of the windows whose text lies on parchment.
--
-- === Why a rule rather than a list of names ===
--
-- The conversation windows — a quest, a guard, a trainer, a book — are written
-- DARK ON LIGHT: the game draws parchment on them and lays brown letters over
-- it. Having darkened the parchment, we get dark letters on dark, that is, a
-- window in which nothing can be read. The author sent in two screenshots and
-- wrote exactly that: the text was unreadable.
--
-- A list by name does not fix that trouble. There was one already — thirteen
-- names in the compatibility layer — and it did not help: the quest log window
-- in this client lives inside the world map, and the trainer's window is not
-- named at all. The general pass reaches them FROM ABOVE, from the map, and a
-- child window's name does not stop it.
--
-- A rule by a name's prefix does stop it. It also outlives the patch that
-- introduces a fourteenth conversation window: the names in this family of
-- windows are related for a reason — they are given by the game by a scheme of
-- its own.
--
-- The strings are prefixes rather than pieces: "^Quest" recognises QuestFrame
-- and QuestLogPopupDetailFrame but not another addon's SearchQuestFrame.
local TEXT_WINDOWS = {
    "Quest", "Gossip", "ItemText", "ClassTrainer", "Trainer", "Petition",
    "Greeting", "Book",
}
Darkness.TEXT_WINDOWS = TEXT_WINDOWS

--- Whether this is a window with text on parchment.
--
-- A pure function: one name is asked about and a yes/no is answered.
--
-- @param name any the frame's name
-- @return boolean
function Darkness.TextWindow(name)
    if type(name) ~= "string" or name == "" then return false end

    for i = 1, #TEXT_WINDOWS do
        local prefix = TEXT_WINDOWS[i]
        if name:sub(1, #prefix) == prefix then return true end
    end

    return false
end

-- The names of the installed addons, by which their windows are recognised.
--
-- The list is asked of the game once per session and remembered: addons do not
-- appear in the middle of a session, while a walk over two hundred windows
-- would ask for it two hundred times.
local addonNames = nil

--- The names of all the installed addons.
--
-- Asked for through the compatibility layer: on later clients these functions
-- are gathered into the C_AddOns table and on earlier ones lie as globals, and
-- there is no point in the subsystem knowing about that.
--
-- @return table an array of names
function Darkness.AddonNames()
    if addonNames ~= nil then return addonNames end

    addonNames = {}

    -- The layer fails deliberately if the client is not determined yet
    -- (Compat.Resolve), while the walk is obliged to work before that too: it
    -- runs both on the first application and in the tests, where there is no
    -- client at all. Not knowing the list means "no other addons' windows are
    -- visible", that is, they stay in "other windows" — the same answer as
    -- before this area existed.
    --
    -- The list is not remembered in the process: an answer of "we do not know
    -- yet" must not be remembered, or it will stay for the whole session.
    if type(ns.Compat.ResolveFunction) ~= "function" then
        addonNames = nil
        return {}
    end

    local gotCount, count = pcall(ns.Compat.ResolveFunction, "addon-count")
    local gotInfo,  info  = pcall(ns.Compat.ResolveFunction, "addon-info")
    if not gotCount or not gotInfo
        or type(count) ~= "function" or type(info) ~= "function" then
        addonNames = nil
        return {}
    end

    local ok, total = pcall(count)
    total = ok and ns.Skin.Numeric(total) or nil
    if total == nil then
        addonNames = nil
        return {}
    end

    for i = 1, total do
        local gotName, name = pcall(info, i)
        name = gotName and ns.Skin.Textual(name) or nil
        -- Our own name does not go onto the list: no pass touches our
        -- windows, and an area for them would be a promise that cannot be
        -- kept.
        if name and name ~= ADDON then
            addonNames[#addonNames + 1] = name
        end
    end

    return addonNames
end

--- Forget the list of addons.
-- Needed by the tests: the list is remembered for a session, while in the tests
-- a session is one file, and its second case would arrive with somebody else's
-- answer.
function Darkness.ForgetAddons()
    addonNames = nil
end

--- Whether this is another addon's window.
--
-- Recognised by name: a frame does not remember who created it, while a
-- window's name almost always begins with the addon's name — that is how they
-- are named, so as not to collide in the shared dictionary of globals. A match
-- on the prefix is enough: another addon's prefix does not occur in the name of
-- a frame of the game's, because the game's names are older than any addon.
--
-- It was not recognised — an ordinary answer rather than an error: the window
-- stays in "other windows", that is, darkens as it darkened. That area is a
-- refinement rather than a condition of the work.
--
-- A pure function: the list of names arrives as an argument.
--
-- @param name any the frame's name
-- @param names table|nil the addons' names
-- @return boolean
function Darkness.AddonWindow(name, names)
    if type(name) ~= "string" or name == "" then return false end
    if type(names) ~= "table" then return false end

    for i = 1, #names do
        local addon = names[i]
        if #addon > 0 and name:sub(1, #addon) == addon then return true end
    end

    return false
end

-- The labels currently raised into the light: an array of objects.
--
-- Separate from the plan of textures rather than together with it: a label has
-- a question of its own ("is it dark"), a colour of its own and a "restore it
-- as it was" of its own, and putting them into one list would mean asking every
-- texture about text.
local lifted, liftedN = {}, 0

-- A label's native colour: label -> { r, g, b, a }.
--
-- Beside the label rather than on it, and for the same reason as a texture's
-- colour: we do not write fields of our own onto somebody else's object.
local TEXT_BASE = ns.Skin.Memory()

-- The light colour for dark text on a darkened sheet.
--
-- This is not a choice of taste but a forced measure, and here is the matter.
-- The quest window and the conversation with a creature are the one place in
-- the game where the text is printed DARK on light. By darkening the sheet we
-- reduce the difference to nothing, and the page vanishes entirely: the author
-- sent in such screenshots three times.
--
-- There are two answers to that. The first is not to darken the sheet at all
-- (and so it was done); the second is to darken the sheet and raise the text.
-- The author chose the second and said it in words: that we could simply make
-- it light, since our background was dark.
--
-- The tone is almost white, and its number was named by the author.
--
-- At first a muted light stood here — "white cuts the eye on a long text". On a
-- dark page it turned out to be grey on brown, and the author said to simply
-- make the text's colour almost white; then, having seen the spellbook, he
-- named the measure too: the texts on artwork were to be 90% white and the
-- texts on windows were to be 90% white.
--
-- Nine tenths across all three channels is exactly that: not a pure white,
-- which cuts the eye on a long text, and not a muted tone, which reads as grey
-- on dark.
local INK = { 0.90, 0.90, 0.90 }

-- Below what brightness a label counts as dark.
--
-- A half: above it the text is readable on dark anyway (yellow names, green
-- quest titles, white reward lines), and it must not be touched — a letter's
-- colour carries meaning. Below it the text vanishes on a darkened sheet.
local INK_EDGE = 0.5

--- Whether this label is a dark one.
--
-- A pure function over three channels. The brightness is computed as a mean
-- rather than as the "real" weighted luminance: the difference between them
-- here is smaller than the spread of the game's own colours, while a mean needs
-- no numbers explained.
--
-- @param r number|nil
-- @param g number|nil
-- @param b number|nil
-- @return boolean
function Darkness.DarkText(r, g, b)
    local red, green, blue = tonumber(r), tonumber(g), tonumber(b)
    if red == nil or green == nil or blue == nil then return false end

    return (red + green + blue) / 3 < INK_EDGE
end

--- The light colour dark text is replaced with.
-- @return number, number, number
function Darkness.Ink()
    return INK[1], INK[2], INK[3]
end

-- Down to what depth the pass asks for a name for the conversation area's
-- sake.
--
-- Two is the world map and its quest panel, that is, the deepest of the real
-- cases. Asking every frame for its name at any depth would mean paying a
-- reading for every frame of the interface, and the measurement of the
-- reconnaissance's cost catches that.
-- Six, from a measurement rather than a guess.
--
-- It was two, and the note here said two was "the world map and its quest
-- panel, that is, the deepest of the real cases". The author's probe of that
-- very panel puts its labels at depth five. Six leaves one step of room; the
-- price of asking more frames for their name is what the whole-cost
-- measurement exists to catch, and it does.
local TEXT_DEPTH = 6

-- The game's font objects whose ink is dark because the page under it is
-- light.
--
-- Why this exists beside the per-label raising, and why it comes first.
--
-- The raising walks a page, reads each label's colour and decides. That is
-- the hard way round, and it showed: it needs a threshold to guess with, it
-- only reaches labels that already exist, and it has to be re-run after the
-- game writes a page. A quest window arrived unreadable and the count of
-- labels raised was zero.
--
-- A font object is the easy way round, and this addon already relies on it
-- for the typeface - the note at the head of Modules/Fonts.lua puts it
-- plainly: a SetFont on GameFontNormal changes the text everywhere. Colour
-- works the same way. One call per object paints every label that uses it,
-- including the ones the game has not created yet, with no walk, no
-- threshold and nothing to re-run.
--
-- Only the dark-on-parchment family is here. GameFontNormal is gold and
-- GameFontHighlight is white: both read on a dark page already, and their
-- colour is how the game tells one kind of line from another. Taking that
-- away would cost more than it gives.
--
-- Fonts owns the typeface, this owns the colour, and the split is not
-- arbitrary: the typeface is a choice the player makes, while the colour here
-- is a consequence of the page having been darkened, and it is undone when
-- the darkening is.
local PARCHMENT_FONTS = {
    -- The quest family. More than the three obvious ones, and the author
    -- found out why the hard way: the window an NPC opens went white while
    -- the quest panel inside the world map stayed dark. Both are quest text;
    -- they simply inherit from different objects of the same family, and the
    -- first list only had the ones the NPC window happens to use.
    "QuestFont", "QuestFontNormalSmall", "QuestTitleFont",
    "QuestTitleFontBlackShadow",
    "QuestFont_Large", "QuestFont_Huge", "QuestFont_Super_Huge",
    "QuestFont_Enormous", "QuestFont_Shadow_Small", "QuestFont_Shadow_Huge",
    "QuestMapObjectiveFont",

    -- Books, letters and the rest of the parchment.
    "ItemTextFontNormal", "ItemTextFontNormalLarge",
    "MailTextFontNormal", "MailFont_Large",

    -- Ink named for being ink: black and dark grey are dark because the page
    -- was light, which is this list's whole subject.
    "GameFontBlack", "GameFontBlackSmall", "GameFontBlackMedium",
    "GameFontDarkGraySmall",
}

--- The ink each font object had before we touched it: name -> { r, g, b, a }.
local FONT_BASE = {}

--- Paint the parchment fonts with our ink, or give them back their own.
--
-- The native colour is remembered at the first painting and restored from
-- that rather than from any idea of what it ought to be - the same rule the
-- per-label raising follows.
--
-- A name this client does not have is skipped in silence: the list is common
-- to three client lines and that is the ordinary case, not a failure.
--
-- @param lift boolean true to paint our ink, false to give theirs back
-- @return number how many objects were written
function Darkness.PaintFonts(lift)
    local written = 0

    for i = 1, #PARCHMENT_FONTS do
        local name = PARCHMENT_FONTS[i]
        local object = _G[name]

        if type(object) == "table"
            and type(object.SetTextColor) == "function"
            and type(object.GetTextColor) == "function" then

            if FONT_BASE[name] == nil then
                local ok, r, g, b, a = pcall(object.GetTextColor, object)
                r, g, b = ns.Skin.Numeric(r), ns.Skin.Numeric(g),
                    ns.Skin.Numeric(b)
                if ok and r ~= nil and g ~= nil and b ~= nil then
                    FONT_BASE[name] = { r, g, b, ns.Skin.Numeric(a) or 1 }
                end
            end

            local base = FONT_BASE[name]
            if base ~= nil then
                if lift then
                    local r, g, b = Darkness.Ink()
                    if pcall(object.SetTextColor, object, r, g, b, base[4]) then
                        written = written + 1
                    end
                elseif pcall(object.SetTextColor, object,
                    base[1], base[2], base[3], base[4]) then
                    written = written + 1
                end
            end
        end
    end

    return written
end

--- Raise a dark label into the light, if it is a dark one.
--
-- Called by the walk on every label of the conversation areas. The decision is
-- made by the label's own colour: the interlocutor's yellow name, a quest's
-- green title and the white reward lines stay as they are — their colour
-- carries meaning, and they are readable on dark anyway. What is raised is only
-- what is printed dark on light, that is, exactly what vanishes on a darkened
-- sheet.
--
-- The native colour is remembered at the first raising: restoring it means
-- setting exactly what stood there rather than what we consider usual.
--
-- @param text table the label
-- @return boolean whether it was raised
function Darkness.LiftText(text)
    if type(text) ~= "table" then return false end
    if type(text.SetTextColor) ~= "function" then return false end
    if type(text.GetTextColor) ~= "function" then return false end

    local base = TEXT_BASE[text]
    if base == nil then
        local ok, r, g, b, a = pcall(text.GetTextColor, text)
        if not ok then return false end

        r, g, b = ns.Skin.Numeric(r), ns.Skin.Numeric(g), ns.Skin.Numeric(b)
        if r == nil or g == nil or b == nil then
            counters.blocked_darkness = counters.blocked_darkness + 1
            return false
        end

        if not Darkness.DarkText(r, g, b) then
            counters.lightText = counters.lightText + 1
            return false
        end

        base = { r, g, b, ns.Skin.Numeric(a) or 1 }

        -- A letter's shadow is taken off along with the raising.
        --
        -- It is drawn for dark text on a light sheet: there a shadow separates
        -- a letter from the background. On a dark page it does the opposite —
        -- it blurs a light letter with a dark halo, and the text reads worse
        -- than without it. The author wrote plainly: stop playing with the
        -- border, the shadow and so on.
        --
        -- The native state is remembered right here: the restoration is
        -- obliged to bring it back too.
        local okShadow, sr, sg, sb, sa = pcall(text.GetShadowColor, text)
        local okOffset, sx, sy = pcall(text.GetShadowOffset, text)
        if okShadow then
            base.shadow = { ns.Skin.Numeric(sr) or 0, ns.Skin.Numeric(sg) or 0,
                ns.Skin.Numeric(sb) or 0, ns.Skin.Numeric(sa) or 0 }
        end
        if okOffset then
            base.offset = { ns.Skin.Numeric(sx) or 0, ns.Skin.Numeric(sy) or 0 }
        end

        TEXT_BASE[text] = base

        liftedN = liftedN + 1
        lifted[liftedN] = text
    end

    local ink1, ink2, ink3 = Darkness.Ink()
    Darkness.Unshadow(text)

    local ok = pcall(text.SetTextColor, text, ink1, ink2, ink3, base[4])
    if ok then counters.lifted = counters.lifted + 1 end
    return ok
end

--- Take the shadow off a raised label.
-- A function of its own because it is called twice: at the raising and at every
-- repeated raising (the game sets the shadow afresh along with the colour).
-- @param text table
function Darkness.Unshadow(text)
    if type(text.SetShadowOffset) == "function" then
        pcall(text.SetShadowOffset, text, 0, 0)
    end
    if type(text.SetShadowColor) == "function" then
        pcall(text.SetShadowColor, text, 0, 0, 0, 0)
    end
end

-- The windows in which the text is printed dark on light: an array of the ones
-- found.
--
-- Why remember the windows themselves when the labels are already remembered.
-- Because the decision "this label is a dark one" is made by its colour, and
-- the game sets the colour NOT AT THE TIME we walk the window: a quest's page
-- is empty before the player has chosen a quest, and a label in it at that
-- instant is not dark but nothing at all. A walk that looked in earlier finds
-- nothing and never comes back — the window has "not changed" since.
--
-- The author sent in exactly that: a quest's page chosen in the log, with the
-- words "where do you see a changed colour?". Nowhere: by the time of the walk
-- this text did not yet exist.
--
-- So the windows are remembered, and they are walked afresh — when a window is
-- opened and on the game's events about quests and conversations.
local pages, pagesN = {}, 0
local pageSeen = ns.Skin.Memory()

--- Remember a window with text.
-- @param frame table
local function rememberPage(frame)
    if type(frame) ~= "table" then return end
    if pageSeen[frame] then return end

    pageSeen[frame] = true
    pagesN = pagesN + 1
    pages[pagesN] = frame

    -- A page just became known: raise it shortly, without waiting for an
    -- event.
    --
    -- The author: the text is not coloured the first time, only the second.
    -- That is this exactly. A page is remembered while the walk is passing
    -- through it, and the raising of the pages runs on the game's own
    -- announcements - a quest offered, a page turned. Picking a quest out of
    -- the list on the map announces nothing we listen for, so the page was
    -- remembered and then left alone until something else happened to run
    -- the raising, which is what "the second time" is.
    --
    -- Deferred rather than immediate for the reason the deferral already
    -- exists elsewhere in this file: the game fills a page after it builds
    -- it, and a raising in the same frame reads colours that are about to be
    -- overwritten.
    if type(Darkness.LiftPagesLater) == "function" then
        Darkness.LiftPagesLater()
    end
end

--- Raise every dark label inside a window.
--
-- A pass over the labels alone: this window's pictures are already in the plan,
-- and there is nothing here to touch them with and no reason to. The depth is
-- the same as the general walk's — a quest's page lies in a scroll frame inside
-- a tab inside a window.
--
-- @param object table
-- @param depth number|nil
-- @return number how many labels were raised
function Darkness.LiftPage(object, depth)
    if type(object) ~= "table" then return 0 end

    depth = tonumber(depth) or 0
    if depth > MAX_DEPTH then return 0 end
    if ns.Skin.Forbidden(object) then return 0 end
    if Darkness.IsOurs(object) then return 0 end

    local count = 0

    if isText(object) then
        if Darkness.LiftText(object) then count = 1 end
        return count
    end

    if type(object.GetRegions) == "function" then
        local ok, regions = pcall(gather, object.GetRegions, object)
        if ok then
            for i = 1, #regions do
                local region = regions[i]
                if isText(region) and not ns.Skin.Forbidden(region)
                    and not Darkness.IsOurs(region) then
                    if Darkness.LiftText(region) then count = count + 1 end
                end
            end
        end
    end

    if depth < MAX_DEPTH and type(object.GetChildren) == "function" then
        local ok, children = pcall(gather, object.GetChildren, object)
        if ok then
            for i = 1, #children do
                count = count + Darkness.LiftPage(children[i], depth + 1)
            end
        end
    end

    return count
end

--- Raise afresh everything that has already been raised.
--
-- Why this exists when the walk does the raising. The walk goes over a window
-- once: a second time the same window is not walked at all until it has changed
-- (see SEEN). And the text in it the game rewrites on EVERY page: a new quest, a
-- new conversation — and the colour is set afresh, over ours. From the outside
-- that would look like this: the first page light, all the following ones black
-- on dark.
--
-- So the colour is set afresh every time such a window is opened. The work here
-- is on dozens of labels rather than on thousands of textures, and it costs one
-- protected call per label.
--
-- @return number how many labels were raised afresh
function Darkness.RelightText()
    local ink1, ink2, ink3 = Darkness.Ink()
    local count = 0

    for i = 1, liftedN do
        local text = lifted[i]
        local base = text and TEXT_BASE[text] or nil
        if base then
            Darkness.Unshadow(text)
            if pcall(text.SetTextColor, text, ink1, ink2, ink3, base[4]) then
                count = count + 1
            end
        end
    end

    return count
end

--- Restore the raised labels' native colour.
--
-- Called when the conversation area stops darkening: the sheet is light again,
-- and light text on it would vanish exactly as dark text vanished on dark. The
-- list is cleared: a restored label is no longer ours.
--
-- @return number how many labels were restored
function Darkness.DropText()
    local count = 0

    for i = 1, liftedN do
        local text = lifted[i]
        lifted[i] = nil

        local base = text and TEXT_BASE[text] or nil
        if base then
            TEXT_BASE[text] = nil

            if base.shadow and type(text.SetShadowColor) == "function" then
                pcall(text.SetShadowColor, text, base.shadow[1],
                    base.shadow[2], base.shadow[3], base.shadow[4])
            end
            if base.offset and type(text.SetShadowOffset) == "function" then
                pcall(text.SetShadowOffset, text, base.offset[1],
                    base.offset[2])
            end

            if pcall(text.SetTextColor, text, base[1], base[2], base[3],
                base[4]) then
                count = count + 1
            end
        end
    end

    liftedN = 0
    return count
end

--- How many labels are raised right now. Needed by the tests.
-- @return number
function Darkness.LiftedCount()
    return liftedN
end

--- Walk an object and its children, handing every usable texture to a sink.
--
-- The subsystem's only walker. The walk and the writing of the colour used to be
-- one function, and that was the very cause of the freezing: every movement of
-- the slider found out afresh what the interface consists of at all. The
-- separation is a simple one — "what to darken" is sought by the walk, "how
-- much" is decided by the application, and the second is repeated at every step
-- of the slider while the first is not.
--
-- The rule of selection (Darkness.IsChrome) is asked here, and what reaches the
-- sink is framing alone.
--
-- @param object table a frame or a texture
-- @param depth number|nil the current depth
-- @param skip table|nil a set of objects that are skipped
-- @param sink function the texture's sink
local function walk(object, depth, skip, sink, area, push)
    if type(object) ~= "table" then return end
    if type(skip) == "table" and skip[object] then return end
    if Darkness.IsOurs(object) then return end

    -- The engine's prohibition. It stands ahead of every other question, and
    -- not for speed's sake: every question that follows is an approach to the
    -- object, and an approach to a forbidden object IS the thing that is not
    -- allowed. The taint spreads further over the frames the object touches, and
    -- the player sees it not here but in a file that is none of ours — "Secret
    -- values are only allowed during untainted execution" on the cooldown of a
    -- bar's button.
    if ns.Skin.Forbidden(object) then
        counters.forbidden = counters.forbidden + 1
        return
    end

    -- The engine's protection. It stands beside the prohibition and for a
    -- related reason.
    --
    -- A forbidden object must not be touched at all. A protected one may be,
    -- and addons legitimately do a great deal with it. But everything we have
    -- changed on it the engine considers changed by an addon from then on, and
    -- the frame's own code starts running tainted. The player sees that not in
    -- our file:
    --
    --   ActionButton.lua:891: bad argument #1 to 'SetCooldown' ... Secret
    --   values are only allowed during untainted execution.
    --
    -- The cooldown of a bar's button whose picture is all we recoloured. And the
    -- cooldown of the OVERRIDE bar — the one that appears on a vehicle — which
    -- the action bars subsystem does not know by name at all: the only thing
    -- that reaches it is this general walk, because the darkening is obliged to
    -- lie on every window of the game's.
    --
    -- The protected frames are not left light as a result of this. Their look is
    -- the business of whichever subsystem they belong to: the action bars paint
    -- their own buttons themselves (the "Button Look" setting), the raid frames
    -- draw their own entirely. The general walk yields that work to them rather
    -- than cancelling it.
    --
    -- The object itself is asked rather than a list of names: the override bar,
    -- the pet bar, the raid frames' container and whatever the next patch adds
    -- all answer this question themselves.
    if ns.Skin.Protected(object) then
        -- A protected window used to be skipped entirely, and the talents
        -- window stayed light under any settings: the walk left it at level
        -- zero. The reconnaissance ("/dark probe") named that in words —
        -- "1. [0] Frame PlayerSpellsFrame - protected by the engine" — and that
        -- is no longer a guess but the cause.
        --
        -- The action bars' buttons come in here on a par with the windows, and
        -- that is a decision against the former one. They used not to be touched
        -- at all: a click on a button is a protected action, and a taint on it
        -- costs more than anything. But the addon the author took as an example
        -- paints them too (its "ActionButtons" list), and next to an unpainted
        -- button the bar's dark backing looks like a failure rather than
        -- caution.
        --
        -- How this is safer than before: the colour is read through
        -- ns.Skin.Numeric (a secret value does not reach the arithmetic), the
        -- write goes through a protected call, a button's cooldown is not
        -- touched at all (SKIP_TYPES, Cooldown), and an ability's icon stays an
        -- icon (the rule of selection). What changes is exactly the picture's
        -- colour — neither the position, nor the visibility, nor the
        -- attributes.
        if not Darkness.EnterProtected() then
            counters.protected_darkness = counters.protected_darkness + 1
            return
        end
    end

    depth = tonumber(depth) or 0
    if depth > MAX_DEPTH then return end
    if SKIP_TYPES[objectType(object)] then return end

    -- The hidden is not walked.
    --
    -- This is the cheapest of all the edits made for speed's sake and the
    -- largest of them in the result. The talents window is not fifteen hundred
    -- pictures but ten thousand, of which a tenth is shown: tabs the player
    -- never opened, list rows lying in reserve, tooltips created in advance. The
    -- walk went over all of them while the eye saw a tenth.
    --
    -- The hidden is not lost: it will be shown — and walked at that same moment.
    -- There is an occasion for that in every way of showing something
    -- (ShowUIPanel, a tab, the opening of a bag, an event from the server),
    -- while a picture that has once got into the plan holds its colour itself.
    --
    -- The question is put to a frame alone: a region has no visibility of its
    -- own, it is visible exactly when its owner is.
    --
    -- And only INSIDE a window rather than to the window itself. The game calls
    -- ShowUIPanel BEFORE showing the frame: at that instant the window is still
    -- hidden, and the rule, applied to the window itself, turned the walk back
    -- at the threshold — the window stayed light entirely. The author saw that
    -- at once: part was painted, part was not.
    if depth > 0 and type(object.IsShown) == "function" then
        local ok, shown = pcall(object.IsShown, object)
        if ok and shown == false then
            counters.hidden = counters.hidden + 1

            -- The hidden is not walked — but it will be shown, and then
            -- somebody is obliged to walk it.
            --
            -- That used to be left to hope: there are six occasions to walk a
            -- window afresh, and it seemed that at least one of them would
            -- happen. For list rows not one of them happens: the game hands a
            -- row out of its reserve, assigns it a picture ONCE at creation and
            -- after that only shows and hides it. The reconnaissance missed that
            -- row (it was hidden), the watcher of pictures stays silent (the
            -- picture is never assigned again), and there will be no occasion to
            -- walk the window.
            --
            -- The author's reconnaissance showed exactly that in numbers: the
            -- rule of selection does take a section's header ("dims") while it
            -- has no written colour at all — that is, we never reached it.
            watchShown(object, area)
            return
        end
    end


    -- A conversation window takes both itself and everything inside it into
    -- its own area: the player chooses that area's mode separately, and "as in
    -- the game" stands in it. The area travels down the tree, because the
    -- parchment lies not on the window itself but on a panel inside it.
    -- Two conditions used to guard this, and both were wrong for the quest
    -- panel inside the world map.
    --
    -- "area == nil" meant a conversation window was only recognised where no
    -- area had been assigned yet. The map has an area of its own, so the
    -- panel inside it was never recognised, never remembered, and its text
    -- never raised - while the same quest read from an NPC, which opens at
    -- the top with no area, worked. That is exactly what the author
    -- reported: open it from the map and it is dark, open it from the NPC
    -- and it is white.
    --
    -- The depth was two, with a note saying two reached the map's quest
    -- panel. The author's own probe puts its labels at five.
    --
    -- The two questions were conflated. Which area a frame belongs to
    -- decides how hard it is dimmed; whether it is a page of text decides
    -- whether its labels are raised. A frame can be both inside somebody
    -- else's area and a page of text, and the map's quest panel is.
    --
    -- So the page is remembered whatever area it is in, and the area is
    -- still only claimed when nobody else has claimed it.
    if depth <= TEXT_DEPTH then
        local said = stringFrom(object, "GetName")
        -- Whose frame this is, asked before what it looks like.
        --
        -- The order is the finding of a test rather than a preference.
        -- Questie names its pins QuestieFrame<n>, and "Quest" is one of the
        -- prefixes by which a page of parchment is recognised - so a quest
        -- pin was taken for the quest log, remembered as a page of text, and
        -- walked like one. A name tells us what a frame is only once we know
        -- it is the game's to name.
        if Darkness.AddonWindow(said, Darkness.AddonNames()) then
            if depth == 0 then
                -- Another addon's window takes both itself and everything
                -- inside it into its own area: the player's question is "how
                -- dark are other addons' windows" rather than "how dark is
                -- this particular frame inside somebody else's window".
                area = "addons"
            else
                -- Another addon's frame INSIDE a window of the game's is not
                -- a window of theirs - it is their picture placed on ours,
                -- and it is left alone entirely.
                --
                -- The author sent the world map with Questie loaded: its
                -- quest pins were black blobs. They are frames of Questie's
                -- named QuestieFrame<n>, reparented onto the map's canvas,
                -- and their picture sits in a field of their own naming with
                -- no name and no path we could recognise - so every rule in
                -- ContentReason answers "framing" and we painted another
                -- addon's icons black.
                --
                -- The two cases are told apart by depth, and the same depth
                -- the rest of this block uses: at the top of the tree a
                -- frame of theirs is their window, which the player may
                -- choose to dim through the "other addons' windows" area;
                -- inside somebody else's window it is a pin, a marker, an
                -- overlay - a thing that says something, placed by someone
                -- who is not us.
                --
                -- This file already states the rule for another addon's
                -- property, in Icons.Round: we neither repair nor break what
                -- belongs to others.
                counters.foreign = counters.foreign + 1
                return
            end
        elseif Darkness.TextWindow(said) then
            if area == nil then area = "questlog" end
            rememberPage(object)
        end
    end

    -- An edit box is not darkened at all — neither itself nor from inside.
    --
    -- The author sent in a chat line with a black caret, asking why the cursor
    -- in the chat was black. The caret is drawn by the engine, it is not visible
    -- to us as an object of its own, and it takes its colour from the box, which
    -- we darkened along with all the framing. The caret used to come out dark
    -- grey and could be seen with difficulty; now that the scale's end means
    -- black, it cannot be seen at all — and a line in which you cannot see where
    -- you are typing is not a line of input.
    --
    -- The rule is broader than the case itself, and deliberately so. An edit box
    -- is the one place in the interface where the player WRITES, and not only
    -- the letters matter there: the caret, the selection, the prompt inside the
    -- box. Not one of those is framing, and there is nothing to tell them apart
    -- from outside. So the whole of the entrance stands: we do not go inside and
    -- write nothing.
    if objectType(object) == "EditBox" then return end

    -- A label. A dark one is raised into the light, a light one is not touched
    -- at all — the label itself decides by its colour (Darkness.DarkText).
    --
    -- This question used to be asked only in the quest window and the
    -- conversation: there the game prints on parchment, and only there is the
    -- text ever dark. That turned out to be untrue — the author sent in the
    -- spellbook, where brown is printed on a dark backing — and he stated the
    -- rule in full: the texts on artwork were to be 90% white and the texts on
    -- windows were to be 90% white.
    if isText(object) then
        if LIFT[area or "window"] then Darkness.LiftText(object) end
        return
    end

    -- A texture on its own: it has no regions and no children but it does
    -- have a colour.
    if isTexture(object) then
        -- The game's artwork stays ours wherever it lies. What counts as
        -- somebody else's is what an addon drew itself rather than what it
        -- carried over to itself (ART_IMAGES).
        if area == nil or area == "addons" then
            local claimed = artOf(object)
            if claimed then area = claimed end
        end

        if area == ICON_AREA or chromeOf(object) then
            sink(object, area)
        else
            counters.content = counters.content + 1
        end
        return
    end

    -- A frame remembers its area: a picture the game creates in it later is
    -- painted by that area (see FRAME_AREA and gameRecolored).
    FRAME_AREA[object] = area or false

    local content = contentRegions(object)

    -- A bar and its setting are different things, and the rule for them
    -- differs.
    --
    -- The BAR ITSELF is not touched: the walk does not go inside a StatusBar at
    -- all (SKIP_TYPES), and the fill stays the colour the game says what exactly
    -- the player has that much of with. A reputation stays green, health red, a
    -- skill blue.
    --
    -- But a bar's bed, its frame and the header of the row it stands in are
    -- framing, and they darken along with everything else. For a short while the
    -- opposite rule stood here ("a frame with a bar is a gauge as a whole"), and
    -- the answer to it was golden reputation frames and golden section headers
    -- in the middle of a dark window: the author sent in two such screenshots.
    --
    -- The bar's fill, if this frame is a bar and says where it is.
    --
    -- The question is put to the frame rather than to the picture: the picture
    -- itself knows only its name and its atlas about itself, while the frame
    -- knows for certain. One protected call per frame, and only on those that
    -- have this method at all.
    local fillTexture = nil
    if type(object.GetStatusBarTexture) == "function" then
        local ok, found = pcall(object.GetStatusBarTexture, object)
        if ok and type(found) == "table" then fillTexture = found end
    end

    local children = nil
    if depth < MAX_DEPTH and type(object.GetChildren) == "function" then
        local ok, found = pcall(gather, object.GetChildren, object)
        if ok then children = found end
    end

    if type(object.GetRegions) == "function" then
        local ok, regions = pcall(gather, object.GetRegions, object)
        if ok then
            for i = 1, #regions do
                local region = regions[i]
                -- The question "is this ours" is put to a region too rather
                -- than to the frame alone. It used to be put to the frame the
                -- walk goes into, and an object a module created **on somebody
                -- else's frame** did not fall under it at all: the walk took it
                -- on a par with the game's own pictures. One and the same
                -- question is obliged to decide in both places, or "ours" means
                -- "our frame" rather than "our object".
                --
                -- The prohibition is asked about for a region too rather than
                -- for the frame the walk goes into alone: an individual picture
                -- inside a permitted frame can be forbidden as well.
                if ns.Skin.Forbidden(region) then
                    counters.forbidden = counters.forbidden + 1
                elseif isText(region) then
                    -- A raised label is an occasion to remember its frame:
                    -- the game often writes the text in it later than our walk
                    -- (see pages).
                    if LIFT[area or "window"]
                        and Darkness.LiftText(region) then
                        rememberPage(object)
                    end
                elseif not content[region]
                    and not (type(skip) == "table" and skip[region])
                    and not Darkness.IsOurs(region) then
                    -- The rule of selection is asked once, and its answer
                    -- parts the two branches. A second question here would cost
                    -- extra readings on every region of the interface — exactly
                    -- what the measurement of the whole cost guards against.
                    --
                    -- The game's artwork stays ours wherever it lies: another
                    -- bar addon that rehung a gryphon onto itself does not make
                    -- the gryphon its own (ART_IMAGES).
                    --
                    -- That is asked about here rather than in the branch for an
                    -- individual texture alone: a frame's region does not pass
                    -- through that branch at all — it is painted straight from
                    -- here. A rule laid on one of two roads does not work
                    -- once.
                    local mine = area
                    if mine == nil or mine == "addons" then
                        local claimed = artOf(region)
                        if claimed then mine = claimed end
                    end

                    if region == fillTexture then
                        -- A gauge's reading: a fill's colour IS its
                        -- meaning.
                        counters.content = counters.content + 1
                    elseif mine == ICON_AREA or chromeOf(region) then
                        sink(region, mine)
                    else
                        -- Left alone as contents specifically: a portrait, an
                        -- icon, a highlight. Somebody else's and our own do not
                        -- come here — the condition above did not let them
                        -- through, and that is a different cause, which must not
                        -- be added to this one into a single number.
                        counters.content = counters.content + 1
                    end
                end
            end
        end
    end

    if children ~= nil then
        for i = 1, #children do
            -- A child goes either deeper right now or outwards — to whoever
            -- counts the time (see Darkness.Drain). The second is what makes
            -- the walk of a large window divisible: a recursion over fifteen
            -- hundred frames stops the game while a queue does not.
            if push ~= nil then
                push(children[i], depth + 1, area)
            else
                walk(children[i], depth + 1, skip, sink, area)
            end
        end
    end
end

-- How many milliseconds of the walk are allotted to one frame of video.
--
-- Three is less than a quarter of a frame at sixty frames a second, that is, a
-- hitch the eye does not see. The talents window is walked in several such
-- slices and darkens visibly from the top down — instead of the game stopping
-- for a third of a second. The author named it outright: the game stood still
-- when he pressed to open a window, and he wanted smoothness.
local SLICE_MS = 3

-- How many milliseconds are allotted to the FIRST slice of a window's walk.
--
-- More than the usual one, and that is a trade chosen for us by the author. A
-- slice of three milliseconds does not manage to paint the talents window
-- entirely, and the player sees it darken in a wave: he saw the default textures
-- and a blink onto ours. A slice of twenty is one dropped frame, and in it any
-- window of the game's manages to be painted entirely: the walk now does not go
-- into the hidden (counters.hidden), and there is several times less shown in a
-- window.
--
-- A hitch of one frame the eye does not read as a hitch; a flash of the native
-- look it reads at once. So the first slice is a generous one and all the
-- following ones are ordinary: a large window's tail will arrive quietly while
-- the player looks at what is already dark.
local FIRST_SLICE_MS = 20

--- How many milliseconds have passed inside this frame of video.
--
-- Asked of the game's clock exactly (debugprofilestop). The tests have no clock
-- of their own and must not have one: outside the game the walk is obliged to be
-- done whole and at once — a test needs a finished answer rather than half of
-- one — and the absence of a clock here means precisely that.
--
-- @return number|nil
local function nowMs()
    local profile = _G.debugprofilestop
    if type(profile) ~= "function" then return nil end

    local ok, value = pcall(profile)
    if ok and type(value) == "number" then return value end
    return nil
end

-- An unfinished walk: the queue of subtrees and everything it needs.
--
-- One for the whole addon: windows are opened one at a time, and if a second one
-- was opened in the middle of the first's walk, its subtrees simply join the
-- same queue.
local slice = nil

--- Which areas this window's pictures will fall to.
--
-- The same walk as the darkening's, but it paints nothing: it answers the
-- question "whose mode will this window be painted by". The question is not an
-- idle one — a conversation window hidden inside the world map falls to the
-- conversation's area while the map itself stays the common one — and until now
-- the answer to it could only be had by eye, with the game open.
--
-- @param frame table the window
-- @param skip table|nil a set of objects somebody else is occupied with
-- @return table area -> how many pictures
function Darkness.AreasIn(frame, skip)
    local seen = {}

    walk(frame, 0, skip, function(_, area)
        local key = area or "window"
        seen[key] = (seen[key] or 0) + 1
    end)

    return seen
end

--- Darken an object's framing and that of its children.
--
-- The frame's regions are walked and, down to MAX_DEPTH, its child frames.
-- What exactly is darkened is decided by Darkness.IsChrome: the interface's
-- pictures yes; portraits, icons, bars' fills, the map and text no.
--
-- A texture handed in here on its own is handled as a texture. That is not a
-- convenience for the caller: the main bar's decorative gryphons are global
-- textures rather than frames, and a pass that could only do frames silently
-- did nothing with them. The author's action bar stayed bright for that
-- reason.
--
-- The skip set holds the objects this pass does not touch and does not go
-- inside. Somebody else is occupied with them: a named group with a multiplier
-- of its own and a checkbox of its own in the list of exceptions. Without it
-- the general pass would turn out to be a second owner of the same colour.
--
-- The function stays testable outside the client: all it needs from an object
-- is GetRegions, GetChildren, GetObjectType and a couple of colour methods,
-- and that is faked with a table.
--
-- @param frame table a frame or a texture
-- @param fr number the brightness multiplier (of the red)
-- @param fg number|nil the green's multiplier
-- @param fb number|nil the blue's multiplier
-- @param depth number|nil the current depth; not passed in from outside
-- @param skip table|nil a set of objects that are skipped
-- @return number how many textures were processed
function Darkness.ApplyToFrame(frame, fr, fg, fb, depth, skip)
    local count = 0
    walk(frame, depth, skip, function(region)
        if Darkness.Tint(region, fr, fg, fb) then count = count + 1 end
    end)
    return count
end

-- The name prefixes behind which stands a widget we have already styled rather
-- than a window of the game's.
--
-- "Darken" is our own frames. "AceGUI" and "AceConfigDialog" are the library the
-- settings window is assembled from: ours and other addons' alike.
local SKIP_PREFIXES = { "Darken", "AceGUI", "AceConfigDialog" }

-- The root of the game's interface. Every window of the game's and almost
-- every window of other addons lives under it; the world and the nameplates
-- live under WorldFrame, and the pass deliberately does not go there: the
-- nameplates are darkened by their own subsystem at the moment a nameplate
-- appears.
local ROOT = "UIParent"
Darkness.ROOT = ROOT

--- A widget we have already styled rather than a window of the game's.
--
-- Why a name is not enough for this. The rule "we skip the nameless" was
-- conceived for exactly the purpose of leading the pass away from our settings
-- window — and it did not work: AceGUI creates its widgets as named global
-- frames under UIParent ("AceGUI30Button1" and their like), because a name is
-- needed by the game's templates. The pass by names walked straight into our
-- own window. The cost of the mistake was not "the window darkened": the
-- darkening wrote a transparency onto the textures, and transparency is what
-- the styling layer quenches the native pictures with — and the standard red
-- came out from under our button. The transparency is no longer written here,
-- but there is no reason for the pass to come in here either.
--
-- The mark is taken not from the name but from the library's build: AceGUI puts
-- an obj field onto each of its frames — a reference to the widget itself,
-- which has a type and a frame of its own. That works for a widget with any
-- name, including the ones that do not yet exist.
--
-- The name prefixes remain the second line: by them are caught the library's
-- frames that are not entitled to an obj (the shared AceGUITooltip) and our own
-- named frames.
--
-- This rule does not take other addons' windows away from the darkening. It
-- leads the pass away from the settings windows built on AceGUI — the very ones
-- the addon styles itself — while another addon's window made in the game's
-- style carries no obj at all and darkens on a par with the game's windows.
--
-- @param frame table|nil
-- @return boolean
function Darkness.IsOurs(frame)
    if type(frame) ~= "table" then return false end

    local obj = frame.obj
    if type(obj) == "table" and type(obj.type) == "string"
        and obj.frame ~= nil then
        return true
    end

    -- The markers the styling layer puts onto everything it has stripped and
    -- redrawn with its own palette (Skin/Draw.lua, Skin/Containers.lua,
    -- Skin/Dropdown.lua). Multiplying our own palette once more means taking it
    -- into a black rectangle.
    if frame.umbraStripped or frame.umbraSkinned then return true end

    -- A module's marker: "this object was created by me". It is put there by
    -- the contract (handle:Own, Core/Api.lua), the field's name belongs to the
    -- core and is asked of it — no second spelling of that name is created
    -- here.
    --
    -- This is a fourth mark of the same question rather than a second
    -- mechanism. An object a module laid onto somebody else's frame is
    -- indistinguishable to the walk from a native picture of the game's, and
    -- without the marker the darkness would become its second owner: it would
    -- remember the module's colour as the native one and, after a repainting,
    -- restore the object to somebody else's colour. Silently.
    --
    -- ns.OWNED_FIELD is absent only where Core/Api.lua is not loaded at all
    -- (one subsystem's own tests): then nobody has the marker, and the question
    -- is decided by the other three marks.
    local owned = ns.OWNED_FIELD
    if owned ~= nil and frame[owned] then return true end

    local name = stringFrom(frame, "GetName")
    if name then
        for i = 1, #SKIP_PREFIXES do
            local prefix = SKIP_PREFIXES[i]
            if name:sub(1, #prefix) == prefix then return true end
        end
    end

    return false
end

--- Whether the general pass takes this object on.
--
-- The rule of reach, and also the only place where the general pass does not
-- take somebody on. There are four conditions, and each answers its own
-- question.
--
--   1. The type. A bar, the map, a model are contents entirely (SKIP_TYPES).
--   2. The name. A window of the game's and another addon's window in the
--      game's style are a named global frame; nameless frames are libraries'
--      innards and widgets with styling of their own.
--   3. Ours. A widget the addon has already styled itself
--      (Darkness.IsOurs).
--   4. Taken. A frame of a named group with a multiplier of its own.
--
-- What is not here is a list of names. It was the defect itself: every
-- forgotten window the player sees as "the darkening does not work", and
-- forgetting a window with a living client that keeps adding them by patches is
-- a question of time rather than of attentiveness.
--
-- @param frame table
-- @param skip table|nil a set of objects somebody else is occupied with
-- @return boolean
function Darkness.ShouldSweep(frame, skip)
    if type(frame) ~= "table" then return false end
    if type(skip) == "table" and skip[frame] then return false end
    if ns.Skin.Forbidden(frame) then return false end
    if SKIP_TYPES[objectType(frame)] then return false end
    if Darkness.IsOurs(frame) then return false end

    local name = stringFrom(frame, "GetName")
    if not name then return false end

    return true
end

--- Darken everything that hangs on the interface's root.
--
-- This is the general pass itself: the list of names was replaced by a walk of
-- the tree, and a window nobody listed — another addon's window in the game's
-- style included — darkens on a par with the rest.
--
-- @param root table the root frame (in the client, UIParent)
-- @param fr number
-- @param fg number|nil
-- @param fb number|nil
-- @param skip table|nil a set of objects somebody else is occupied with
-- @return number how many textures were processed
function Darkness.SweepChildren(root, fr, fg, fb, skip)
    if type(root) ~= "table" or type(root.GetChildren) ~= "function" then
        return 0
    end

    local ok, children = pcall(function() return { root:GetChildren() } end)
    if not ok then return 0 end

    local count = 0
    for i = 1, #children do
        local child = children[i]
        if Darkness.ShouldSweep(child, skip) then
            count = count + Darkness.ApplyToFrame(child, fr, fg, fb, 0, skip)
        end
    end
    return count
end

-- The default settings.
--
-- The darkening is the one place in the whole addon where a fresh install
-- changes the game's look by itself. That is the author's decision, and it was
-- stated in words: a dark interface that is indistinguishable from an untouched
-- game after installation does not do the thing it is installed for. The rule "a
-- fresh install touches nothing" still extends to every other setting, and this
-- case must not be extended to them.
--
-- Where the number comes from. The author named the reference point in words:
-- what was in his old plugin was to be the default. In his former addon every
-- area stood at the "Dark" mode, that is, at a multiplier of 0.36, and on our
-- scale that is exactly sixty-four (1 - 64/100 * 0.7 ... see Darkness.Factor).
-- The earlier forty-nine gave 0.51 — noticeably lighter than what he had set for
-- himself and played with.
--
-- NOTE: what actually stands below is eighty, not sixty-four. The author later
-- sent in a screenshot of his own settings with the words "these are what the
-- defaults should be" — the slider at eighty, grey on, the levelling off — and
-- the fields below follow that screenshot. The sixty-four reasoning is kept
-- because it explains where the scale's marks come from, not because it is the
-- value in force.
--
-- Zero has not gone anywhere and remains the slider's first division: the
-- game's native look in one movement, as with any other setting of the addon's.
-- Every area has the same by its own mode ("leave it as it is"), and that is a
-- rule rather than a convenience: a default is entitled to be dark, but the
-- native look is obliged to stay reachable — both as a whole and area by area.
--
-- To somebody who is already playing this default falls in exactly one case: he
-- never touched the slider. A value chosen deliberately lies in the saved data
-- and is rewritten by no migration. One can be told from the other only by the
-- presence of the key in the raw SavedVariables table, and that is where it is
-- done (Core/Defaults.lua, ns.RawMigrations).
Darkness.defaults = {
    -- Eighty, and it comes from the author's own screenshot: "these are what
    -- the defaults should be" — the slider at eighty, grey on, the levelling
    -- off. On our scale that is the tail past the kink, that is, darker than the
    -- "Dark" mode of his former addon, which sixty-four answers to.
    --
    -- The earlier forty-nine (a multiplier of 0.51) was lighter and was chosen
    -- while the reference point was not the former addon but caution. The
    -- reference point was named by the author, and it overrides that.
    --
    -- Zero has not gone anywhere and remains the slider's first division, and
    -- "leave it as it is" the first meaningful mode of every area: the game's
    -- native look is reachable both as a whole and area by area.
    amount  = 80,
    -- Each area's mode: area key -> mode key. Filled in below from the GROUPS
    -- list, and every area stands at "the overall strength" — that is, on a
    -- fresh install one slider disposes of the whole screen until the player
    -- separates an area from it deliberately.
    --
    -- Listed by name rather than as an empty table, although Darkness.ModeOf
    -- counts silence as that same "overall strength". The reason is that the
    -- defaults are also the declared composition of the settings: the presets
    -- are checked against them (tests/test_presets.lua), and a setting that is
    -- not in the defaults is unavailable to a preset. At the same time AceDB
    -- will clean exactly the modes the player never changed out of the
    -- profile.
    mode    = {},
    -- An area's custom colour: area key -> { r, g, b }. Empty on a fresh
    -- install, and filled in only by the areas for which the player chose the
    -- "custom colour" step.
    color = {},
    -- Exceptions by a single window: window name -> true. Empty on a fresh
    -- install, and it is empty for the same reason the catalogue is: a name
    -- written in here in advance would be a guess about somebody else's
    -- taste.
    excludeWindow = {},
    -- A white tint is the one that changes nothing: a fresh install is
    -- darkened but not recoloured.
    tint    = { r = 1, g = 1, b = 1 },
    -- The framing is painted grey rather than merely darkened. On.
    --
    -- The default used to be the opposite, and the reasoning beneath it was
    -- this: the darkening answers the question "how dark", the draining of
    -- colour another one, "in what colour", and they must not be mixed in a
    -- default.
    --
    -- The reasoning is right and the answer wrong: a default is not a place for
    -- caution but the look the author considers his own. He sent in a screenshot
    -- of his settings and said plainly "these are what the defaults should be" —
    -- the slider at eighty, grey on, the levelling off.
    desaturate = true,
    -- Bright framing is brought down to a half-tone before the darkening
    -- (LEVEL_CEILING).
    --
    -- Off. That rule was introduced against the light patches — the gryphons,
    -- the main bar, the conversation's parchment — and it does its job, but it
    -- touches the game's colour beyond a plain darkening. The author looked at
    -- both checkboxes in the game and left the other one on: "these are what the
    -- defaults should be" — grey yes, the levelling no.
    level = false,
    -- The gryphons at the ends of the main bar. Shown: it is the player who
    -- removes them, not us.
    gryphons = true,
    -- The game's protected windows (the talents, the spellbook) darken on a par
    -- with everything else.
    --
    -- The default used to be the opposite, and it was wrong. The argument for
    -- caution is a real one: the engine remembers a touch of such a window, and
    -- the reckoning comes later — as the line "Interface action failed because of
    -- an AddOn" at the moment the player presses "apply" in the talents. But the
    -- price of the caution is higher: an addon called an interface darkener
    -- leaves a whole window light, and there is nothing to explain that to the
    -- player with — what he sees is not caution but work left undone. The author
    -- saw exactly that and said exactly that.
    --
    -- The switch stays in place (Darkness.EnterProtected): if it broke, untick
    -- it and reload the interface. The buttons are not touched under either
    -- answer, and it is on them that the price is a real one.
    protectedWindows = true,
}

-- The default mode of every area. Assembled from the same GROUPS the pass goes
-- by: two lists of areas would diverge when an eleventh was added, and they
-- would diverge silently.
for i = 1, #GROUPS do
    Darkness.defaults.mode[GROUPS[i].key] = FOLLOW
end

-- Shared per account rather than per profile (db.global.darkness).
--
-- The catalogue of the windows seen lies here, and it lies here because it
-- answers a question about the client rather than about taste: which windows
-- exist in this game is one and the same under any profile. The exceptions
-- themselves, on the contrary, are taste, and live in the profile.
--
-- Empty on a fresh install. Not one name in advance: a list assembled out of
-- guesses is the very list written by hand that everything below is written
-- against.
Darkness.globals = {
    -- Window name -> the number of the session the pass last saw it in.
    windows = {},
    -- The counter of sessions. Incremented once per entry into the game and
    -- serving as the only measure of "how long ago".
    session = 0,
    -- What the walk cost at this entry into the world: see Store().
    cost = { slices = 0, total = 0, worst = 0 },
}

--- The subsystem's settings out of the profile.
-- @return table|nil
local function Settings()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    if not profile then return nil end
    return profile[Darkness.name]
end

--- Whether to go into the game's protected windows.
--
-- A setting rather than a decision made for the player. The price of a touch of
-- a protected window is not visible at once and is not paid by us: from that
-- minute the engine considers the window changed by an addon, and its own code
-- runs tainted. On the talents window that looks like "Interface action failed
-- because of an AddOn" at the moment the player presses "apply" — an hour after
-- he moved our slider.
--
-- So the choice is stated in words and handed to the player: switched on, the
-- talents darken; if applying talents broke, switch it off and reload the
-- interface.
--
-- NOTE: the paragraph above says the default is "no", while Darkness.defaults
-- sets protectedWindows = true — the author overrode the caution. The reasoning
-- is kept because it explains what the switch costs.
--
-- @return boolean
function Darkness.EnterProtected()
    local settings = Settings()
    return settings ~= nil and settings.protectedWindows == true
end

--============================================================================
-- The catalogue of the windows seen
--============================================================================
--
-- Where it came from. The list of exceptions enumerated eleven rows — ten named
-- groups and "other windows" — while the general pass has since taken on every
-- named window under the interface's root. The author said outright: why were
-- there so few frames in the list of exclusions when there were far more frames
-- in the game. He is right, and the trouble is not a forgotten row: a list
-- written by hand IS the trouble. So the list of exceptions is assembled not out
-- of our groups but out of what the pass really darkened.
--
-- Why this has to be remembered between sessions. Most windows the game creates
-- at the instant the player opens them for the first time: the bank, the
-- auction house, the professions, the mail. At the entry into the game they do
-- not exist at all, and a list assembled over the current session alone would be
-- empty in exactly the session the player came looking for it in. The catalogue
-- lies in the shared section of the database (db.global.darkness) rather than in
-- the profile: which windows exist in this client is a property of the client
-- rather than of taste.
--
-- What identifies a window. Its global name, and nothing else: an object does
-- not outlive a session, while its place in the interface's tree the game
-- rearranges by patches. The name is the only thing that stays the same.
--
-- Why this is not a second list of somebody else's frame names. The rule
-- (tests/test_frameknowledge.lua) guards a DECLARED name — our knowledge about
-- the client, written into the source. A found name is the client's own answer,
-- read at work: in the addon's source there is not one line with a name from the
-- catalogue, and on a fresh install the catalogue is empty. Nobody tries to
-- address anything by it either: a name out of the catalogue serves as a row's
-- label in the list, while the frames are still found by the walk of the tree.
-- Such a "list" has nothing to diverge from the client with — it IS an imprint
-- of the client.

-- For how many sessions the catalogue remembers a window it no longer sees.
--
-- A window renamed by the game or removed from it does not stay on the list
-- forever: a row with nothing behind it is rubbish the player would be obliged
-- to tell from the real windows himself. Thirty sessions is enough even for
-- somebody who visits the bank once a month.
--
-- And what is forgotten is the row rather than the decision. The exceptions lie
-- in the profile separately and by name; the catalogue answers the question
-- "what to show", while the application asks only about the exceptions. So a
-- window that came back under its former name finds its choice untouched, and
-- "forgotten" means exactly "the row was taken off the list".
local FORGET_AFTER = 30

-- The catalogue's ceiling. It is needed not for the disk's sake but for the
-- sake of banks: another addon that creates windows with unique names would
-- otherwise grow the saved data without end.
local CATALOG_MAX = 300

Darkness.FORGET_AFTER = FORGET_AFTER
Darkness.CATALOG_MAX = CATALOG_MAX

--- Fold the case for a comparison.
-- The core's folding (Core/Casefold.lua): string.lower knows one byte. It may
-- be absent in one subsystem's own tests — then the single-byte one is enough,
-- the windows' names being Latin.
-- @param text any
-- @return string|nil
local function fold(text)
    if type(text) ~= "string" then return nil end
    local casefold = ns.Casefold
    if type(casefold) == "table" and type(casefold.Fold) == "function" then
        return casefold.Fold(text)
    end
    return text:lower()
end

--- A list row's label for a window's name.
--
-- A window's name in the game is written as one word and in capitals. Reading
-- such a thing in a list of fifty-odd rows is hard, so the words are parted by
-- spaces and a trailing "Frame" is taken off: almost every name has it and
-- therefore it distinguishes nothing.
--
-- This is a transformation of a string rather than knowledge about the game: the
-- rule is one for any name and names not one of them.
--
-- @param name string the window's name
-- @return string the label
function Darkness.WindowLabel(name)
    if type(name) ~= "string" or name == "" then return "" end

    local trimmed = (name:gsub("Frame$", ""))
    if trimmed == "" then trimmed = name end

    local spaced = (trimmed:gsub("(%l)(%u)", "%1 %2"))
    spaced = (spaced:gsub("(%u)(%u%l)", "%1 %2"))
    return spaced
end

--- Whether a window matches the query.
-- Both the name itself and its label are compared: the player types what he
-- sees, and what he sees is the label.
-- @param name string
-- @param query string|nil
-- @return boolean
function Darkness.WindowMatches(name, query)
    if type(query) ~= "string" or query == "" then return true end

    local needle = fold(query)
    if needle == nil or needle == "" then return true end

    local hay = fold(name .. " " .. Darkness.WindowLabel(name))
    return hay ~= nil and hay:find(needle, 1, true) ~= nil
end

--- The catalogue's names in alphabetical order.
-- A pure function: the list is built afresh, so a caller that spoils it does not
-- spoil the catalogue.
-- @param windows table|nil name -> session number
-- @return table an array of names
function Darkness.WindowNames(windows)
    local out = {}
    if type(windows) ~= "table" then return out end

    for name in pairs(windows) do
        if type(name) == "string" then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

--- Forget what has long been out of sight and keep the catalogue within its
--- banks.
--
-- Two rules, and they differ. The first is age: a window the pass has not seen
-- for keep sessions in a row leaves the catalogue. The second is the ceiling: if
-- there are still more than max names after that, the oldest ones leave.
--
-- A record with a non-numeric session number is thrown out on a par with an old
-- one: the catalogue lies in SavedVariables, and over the years anything at all
-- can get in there.
--
-- A pure function over a table: it edits what it is handed and knows nothing
-- about the game or the database.
--
-- @param windows table name -> session number
-- @param session number the current session's number
-- @param keep number|nil for how many sessions to remember the unseen
-- @param max number|nil the ceiling on the number of names
-- @return number how many names were forgotten
function Darkness.Forget(windows, session, keep, max)
    if type(windows) ~= "table" then return 0 end

    session = tonumber(session) or 0
    keep = tonumber(keep) or FORGET_AFTER
    max = tonumber(max) or CATALOG_MAX

    local dropped, live = 0, {}
    for name, seen in pairs(windows) do
        local number = tonumber(seen)
        if type(name) ~= "string" or number == nil
            or session - number > keep then
            windows[name] = nil
            dropped = dropped + 1
        else
            live[#live + 1] = name
        end
    end

    if #live <= max then return dropped end

    -- The oldest first. The name as a second key: at an equal age the order is
    -- obliged to be one and the same from launch to launch, or the catalogue
    -- would lose different names on different entries.
    table.sort(live, function(a, b)
        local sa, sb = tonumber(windows[a]) or 0, tonumber(windows[b]) or 0
        if sa ~= sb then return sa < sb end
        return a < b
    end)

    for i = 1, #live - max do
        windows[live[i]] = nil
        dropped = dropped + 1
    end
    return dropped
end

--- The rows of the window list for this query.
--
-- The ceiling on what is shown is not the same as the catalogue's ceiling. A
-- list of fifty checkboxes in a row is the very crowded page the author has
-- complained about more than once; so the first hundred matches are shown, and
-- how many are left beyond the edge is stated in words beside the search
-- field.
--
-- @param windows table|nil the catalogue
-- @param query string|nil the query
-- @param limit number|nil the ceiling on what is shown
-- @return table an array of names
-- @return number how many matched in all
function Darkness.WindowRows(windows, query, limit)
    local names = Darkness.WindowNames(windows)
    local rows, total = {}, 0

    for i = 1, #names do
        local name = names[i]
        if Darkness.WindowMatches(name, query) then
            total = total + 1
            if limit == nil or #rows < limit then rows[#rows + 1] = name end
        end
    end

    return rows, total
end

--- The subsystem's shared store, or nil.
-- The shape is corrected in place: anything at all can get into SavedVariables
-- over the years, and losing the whole list of exceptions over that is not
-- allowed.
-- @return table|nil
local function Store()
    local db = ns.Addon and ns.Addon.db
    local global = db and db.global
    local store = global and global[Darkness.name]
    if type(store) ~= "table" then return nil end

    if type(store.windows) ~= "table" then store.windows = {} end
    if type(store.session) ~= "number" then store.session = 0 end

    -- What the walk cost this session, in milliseconds of the game's own
    -- clock.
    --
    -- Why it is kept at all. A player's review said the interface lags on
    -- entering the game, and the author says the same of his own. Nothing in
    -- the addon could say whether that is us: the walk is cut into slices of
    -- three milliseconds a frame precisely so that it should not be felt, and
    -- "should not be" is not a measurement. A hundred slices of three
    -- milliseconds is three hundred milliseconds of the interface being busy,
    -- spread over a hundred frames - which is exactly what a login hitch
    -- feels like, and exactly what no counter here could show.
    --
    -- Three numbers and no more: how many slices ran, how long they took
    -- together, and the longest single one. The first walk is recorded apart
    -- because that is the one that happens at login, and it is the one the
    -- report is being read for.
    if type(store.cost) ~= "table" then store.cost = {} end
    local cost = store.cost
    if type(cost.slices) ~= "number" then cost.slices = 0 end
    if type(cost.total)  ~= "number" then cost.total  = 0 end
    if type(cost.worst)  ~= "number" then cost.worst  = 0 end

    return store
end

--- The catalogue for display.
-- @return table name -> session number (an empty table if there is no database
--   yet)
function Darkness.Windows()
    local store = Store()
    return store and store.windows or {}
end

--- Remember that the pass reached this window.
--
-- Called from the reconnaissance, once per window rather than per texture: the
-- price is one comparison per window, and it does not fall on the slider's path
-- at all.
--
-- The banks are checked only when a NEW name appears. There is a finite number
-- of names in a client, each arrives here for the first time once per session,
-- and a pass over the catalogue on such an event costs nothing; a repeated
-- meeting with an old name costs the writing of a number.
--
-- @param name string the window's name
local function remember(name)
    if type(name) ~= "string" or name == "" then return end

    local store = Store()
    if not store then return end

    local windows = store.windows
    local known = windows[name] ~= nil
    if windows[name] == store.session then return end

    windows[name] = store.session
    if not known then
        Darkness.Forget(windows, store.session, FORGET_AFTER, CATALOG_MAX)
    end
end

--- The brightness factor assigned to a group right now.
--
-- The only answer to the question "how darkened is this group". Anybody outside
-- may put it: the unit frames subsystem folds it together with its own bar
-- colour into one SetStatusBarColor call, because the bar's colour belongs to it
-- while the amount of darkening belongs to this file. A second computation
-- beside the first would diverge from it at the first edit.
--
-- There are no settings yet (the window was opened before the profile loaded) —
-- then a one, that is, do not darken.
--
-- @param group string the group's key
-- @return number a multiplier from 0 to 1
function Darkness.FactorFor(group)
    local settings = Settings()
    if not settings then return 1 end

    return Darkness.GroupFactor(group, settings.mode, settings.amount)
end

--- The player's class colour as a table, or nil.
-- A door of the core's rather than a reading of somebody else's tables of our
-- own: the same colours are taken by the unit frames' "by class" bar
-- (ns.Skin.GameClassColors).
-- @return table|nil { r, g, b }
local function playerClassColor()
    if type(ns.Skin.PlayerClassColor) ~= "function" then return nil end

    local r, g, b = ns.Skin.PlayerClassColor()
    if r == nil then return nil end

    return { r = r, g = g, b = b }
end

--- The tint out of the profile, brought to a table of channels.
-- The setting arrives from SavedVariables: neither the table nor the individual
-- channels may be there. White is the tint that changes nothing.
-- @return table { r, g, b }
local function tintOf(settings)
    local tint = settings and settings.tint
    if type(tint) ~= "table" then return Darkness.defaults.tint end
    return tint
end

--- The three brightness multipliers for a group right now.
--
-- The same as Darkness.FactorFor, only with the tint: the only answer to the
-- question "how much and into what colour is this group darkened". Needed by
-- the subsystems that darken their own frames themselves, because no list of
-- their frames exists.
--
-- There are no settings yet (it was called before the profile loaded) — then
-- ones, that is, do not darken.
--
-- @param group string the group's key
-- @return number, number, number
function Darkness.MultipliersFor(group)
    local settings = Settings()
    if not settings then return 1, 1, 1 end

    return Darkness.GroupMultipliers(group, settings.mode, settings.amount,
        tintOf(settings), settings.color, playerClassColor())
end

-- The compatibility layer's groups the darkening does not touch at all.
local UNTOUCHED_GROUPS = { "map-canvas", "color-picker" }

-- The marker "we do not go here" in the memory of areas (FRAME_AREA).
--
-- The walk does not touch such a frame anyway: it lies in the set of the taken,
-- and the rule of reach turns the pass back at the threshold. But the adoption
-- of a picture (adopt) went another road — up the tree, after the nearest
-- familiar area — and did not ask the set of the taken at all. The map's canvas
-- is not painted by the walk: the game lays the terrain's tiles onto it itself,
-- every tile tells the watcher about itself, the climb passes through the map's
-- scroll frame up to the map's window — and the window does have an area — and
-- the terrain turns grey. The author sent in exactly that: you broke the map, it
-- is grey for some reason.
--
-- The marker is put on the group's frame itself, and the climb, meeting it,
-- stays silent. A table rather than a string or a false: it can never be an
-- area's key.
local UNTOUCHED = {}

--- The frames of the named groups: object -> true.
--
-- Needed by the general pass rather than by the groups themselves. A named group
-- has a multiplier of its own (it is excluded from the darkening separately),
-- and if the general pass reached the same frames, one colour would have two
-- owners and the checkbox in the list of exceptions would stop having effect.
--
-- Resolve returns only the names that exist in this client and requires
-- ns.flavor; before the initialisation it fails deliberately, hence the pcall
-- here: the general pass is obliged to work even when the compatibility layer is
-- still silent.
--
-- @return table a set of objects
local function coveredFrames()
    local set = {}
    for i = 1, #GROUPS do
        if not GROUPS[i].general then
            -- The objects are taken from the layer itself as a second array:
            -- a group's name is sometimes a path into somebody else's frame,
            -- and _G[a path] would give a nil — that is, a named group's frame
            -- would silently fall into the general pass, where its colour
            -- would have a second owner.
            local ok, names, objects = pcall(ns.Compat.Resolve, GROUPS[i].key)
            if ok and type(names) == "table" and type(objects) == "table" then
                for j = 1, #names do
                    local object = objects[j]
                    -- What is put there is not "taken" but BY WHOM it is
                    -- taken: the area's key. To the general pass there is no
                    -- difference (a truth either way), while the showing of a
                    -- window needs it — see Darkness.ApplyToWindow.
                    if type(object) == "table" then
                        set[object] = GROUPS[i].key
                    end
                end
            end
        end
    end

    -- The groups that are looked for in order NOT to be touched.
    --
    -- They are not an area of their own and have no setting, because there is
    -- no choice here: the map's canvas is a picture of the world, and its place
    -- is beside the minimap; the colour picker's wheel is the very object of
    -- the choice, and a darkened wheel offers nothing to choose from. The
    -- author sent in both the darkened map and the grey colour picker.
    for i = 1, #UNTOUCHED_GROUPS do
        local ok, names, objects = pcall(ns.Compat.Resolve, UNTOUCHED_GROUPS[i])
        if ok and type(objects) == "table" then
            for j = 1, #objects do
                if type(objects[j]) == "table" then
                    set[objects[j]] = true
                    -- The same news, but for the climb: it does not see the
                    -- set.
                    FRAME_AREA[objects[j]] = UNTOUCHED
                end
            end
        end
    end

    return set
end

-- The application of the plan is declared in advance: the walk's slices
-- (Darkness.Drain) stand above it in the file while calling it at each of their
-- steps.
local applyPlan

-- The plan of the darkening: what exactly is darkened and which colour to
-- compute from.
--
-- Why it appeared. The walk of the interface and the writing of the colour were
-- one piece of work, and every movement of the slider repeated both. An AceGUI
-- slider calls the handler at every division of the drag, the game is
-- single-threaded — and the client stalled. A measurement on a stand-in
-- interface of two hundred windows (2601 frames, 20800 regions) gave 302,420
-- protected calls per application: about fifteen for every region, and all of
-- them found out afresh what had not changed.
--
-- The expensive part is the reconnaissance: descending the tree, asking every
-- region for its type, layer, name, atlas and picture. It does not depend on the
-- slider's position at all. The cheap part is multiplying the remembered colour
-- by the multiplier and writing it. Here they are separated: the reconnaissance
-- gathers what it found into flat arrays, and the application goes over them and
-- does not touch the tree. One protected call per texture instead of fifteen per
-- region, and not one approach to GetChildren.
--
-- The arrays are flat and parallel rather than an array of tables: the whole
-- plan is walked at every step of the slider, and a table per record would mean
-- tens of thousands of garbage tables a second.
local plan = {
    n     = 0,
    tex   = {},   -- [i] the texture object
    group = {},   -- [i] the key of the group whose multiplier acts on it
    -- [i] the name of the window the texture was found in, or nil. Filled in
    -- only for the general pass: a named group has a checkbox of its own in the
    -- list of exceptions, and a second one is not its due.
    win   = {},
    br    = {},   -- [i] the remembered red
    bg    = {},
    bb    = {},
    -- [i] the colour we wrote last. Needed in order to put it back when the
    -- game repaints the picture its own way — and to put it back WITHOUT a
    -- recomputation: otherwise the answer to every repainting of somebody
    -- else's would cost a pass over the whole plan (see gameRecolored).
    cr    = {},
    cg    = {},
    cb    = {},
    built = false,
    root  = nil,  -- the root the plan was built from
}

-- The plan's generation number. Incremented on a clearing, and the former
-- markers on the textures stop matching at a stroke (see PLANNED).
local generation = 1

--- Forget what was found.
-- After a clearing the next application will reconnoitre the interface afresh.
-- The arrays are zeroed entirely: the plan has nothing to grow endlessly with,
-- because one and the same texture does not get into it twice, and the clearing
-- hands the former arrays to the collector.
function Darkness.Invalidate()
    generation = generation + 1

    -- The rule of selection's ready answers were gathered for the former
    -- composition of the interface and no longer mean anything.
    VERDICT = ns.Skin.Memory()

    -- A new generation means new answers: a window that formerly yielded
    -- nothing is obliged to be walked again after the plan is cleared.
    GREW = ns.Skin.Memory()
    plan.n = 0
    plan.tex, plan.group, plan.win = {}, {}, {}
    plan.br, plan.bg, plan.bb = {}, {}, {}
    plan.cr, plan.cg, plan.cb = {}, {}, {}
    plan.built = false
    plan.root = nil
end

--- How many textures are in the plan. Needed by the cost tests.
-- @return number
function Darkness.PlanSize()
    return plan.n
end

-- Whether we are writing a colour right now.
--
-- Needed in order to tell our own write from somebody else's: the watcher of
-- other people's repaintings hangs on that very same SetVertexColor, and without
-- this mark it would answer itself until the end of time.
local writing = false

-- Whether a repainting has been ordered for the near future.
local repainting = false

-- What exactly the game repainted: an array of places in the plan and a marker
-- so that one and the same picture does not get into the array twice.
local dirty, dirtyN = {}, 0
local DIRTY = ns.Skin.Memory()

-- How many seconds after somebody else's repainting we put our colour back.
--
-- Zero means "on the next frame", and that is enough.
--
-- The delay was needed for one thing: the game, handing a list row out of a
-- pool, touches its picture several times in a row, and answering every touch
-- would mean writing the colour ten times in one frame. The queue folds that up
-- anyway — by the next frame every touched picture lies in it exactly once.
--
-- Fifty milliseconds used to stand here, and they could be seen: an aura's
-- icon, redrawn by the game, had time to blink in its native look. Three frames
-- is little for a list and much for the eye.
local REPAINT_AFTER = 0

-- The calls of others our colour may not survive.
local WATCHED_METHODS = { "SetVertexColor", "SetAtlas", "SetTexture" }

-- The adoption of a picture created by the game is declared in advance: it
-- stands further down the file (it needs the write into the plan) while it is
-- called from here.
local adopt

--- The game repainted a picture that lies in our plan.
--
-- Why this exists. List rows — reputations, skills, statistics, bag slots — the
-- game takes out of a pool and assigns a picture and a colour to them afresh at
-- every handing out. The texture is one and the same in the process: it has long
-- been in the plan, the reconnaissance does not add it again, and any pass of
-- ours over the window honestly walks past it.
--
-- From the outside that looked like this: the section headers stay golden under
-- any rules of selection, while toggling any checkbox fixes them. The author
-- sent that in from five windows in a row, and the rule of selection had nothing
-- to do with it — we painted rightly and the game painted over us behind us.
--
-- So a watcher hangs on SetVertexColor itself for every texture of the plan:
-- somebody else's write is an occasion to put our colour back. The order is a
-- shared one for all of them and comes with a pause, so a series of assignments
-- in a row costs one repainting.
local function gameRecolored(texture)
    if writing then return end
    if type(texture) ~= "table" then return end

    -- The rule of selection's former answer about this picture is forgotten.
    --
    -- The memory of answers (VERDICT) is cheap and true exactly as long as the
    -- picture stays itself. The game, however, hands list rows out of a pool
    -- and assigns them a picture afresh — and an answer given when the picture
    -- did not yet exist is a lie from that instant on. A row we once deemed a
    -- reading stayed untouched forever: the author sent in four windows where
    -- everything had stopped being painted.
    --
    -- We get here exactly when the game has assigned that picture — that is, at
    -- the one moment when the answer has really gone stale.
    VERDICT[texture] = nil
    -- The game has just changed the picture, so the answer to "whose artwork"
    -- has gone stale along with it.
    ART_MEMO[texture] = nil

    local at = INDEX[texture]

    -- The picture is not in the plan yet: the game created it a moment ago —
    -- handed out a list row, assigned an icon, built a tab.
    --
    -- This is the very answer to "why can it not be painted at once": it can,
    -- and here. Nothing needs walking — the picture said itself that it had
    -- appeared, and its owner remembers its area (FRAME_AREA).
    if at == nil then
        adopt(texture)
        return
    end

    if at > plan.n then return end
    if plan.tex[at] ~= texture then return end

    -- Into the queue rather than at once: the game, handing a list row out of
    -- a pool, touches its picture several times in a row, and answering every
    -- touch would mean writing the colour ten times in one frame.
    if DIRTY[texture] then return end
    DIRTY[texture] = true
    dirtyN = dirtyN + 1
    dirty[dirtyN] = at

    if repainting then return end

    local timer = _G.C_Timer
    if type(timer) ~= "table" or type(timer.After) ~= "function" then return end

    repainting = true
    pcall(timer.After, REPAINT_AFTER, function()
        repainting = false
        pcall(Darkness.Repaint)
    end)
end

--- The watcher's wrapper, the one the game sees.
--
-- A function of its own, and that is not decoration. The handler runs INSIDE a
-- call of the game's: an error of ours here goes out as a yellow line in a file
-- that is none of ours, and the player sees a failure of an addon of the game's
-- rather than ours. So everything we do in answer to somebody else's repainting
-- goes through a protected call.
local function watchHandler(texture)
    -- Counted here rather than inside gameRecolored: what is asked is whether
    -- the watcher HEARS at all, and gameRecolored turns away early on guards
    -- of its own. A count taken past them would answer a different question
    -- than the one it exists for.
    counters.repainted = counters.repainted + 1
    pcall(gameRecolored, texture)
end

--- Place the watcher of other people's repaintings.
--
-- One and the same handler for every texture: it does not ask who exactly was
-- repainted — the answer in any case will be a repainting of the whole plan. So
-- the closure here is one for the whole addon rather than one per texture.
local function watchColor()
    if WATCHED.done then return end
    if type(_G.hooksecurefunc) ~= "function" then return end
    if type(_G.CreateFrame) ~= "function" then return end

    -- ONE watcher is placed for every picture of the game's at once.
    --
    -- How that works. A widget's methods live not on the object itself but on
    -- the shared method table of its kind: getmetatable(picture).__index. One
    -- hooksecurefunc over that table hears any picture in the interface — one
    -- that does not yet exist and one we have never gone into.
    --
    -- How this is better than before. The watcher used to be hung on every
    -- picture of the plan three times over: at the opening of a large window
    -- that is thousands of installations, and they knew nothing about the
    -- pictures created later — that is, about exactly the ones it was all
    -- started for.
    --
    -- There are three ways to knock our colour off: a direct repainting
    -- (SetVertexColor) and a fresh handing out of the picture (SetAtlas,
    -- SetTexture) — a list row taken out of a pool gets its atlas at every
    -- handing out, and the colour returns to the native one in the process.
    local made = _G.CreateFrame("Frame")
    if type(made) ~= "table" or type(made.CreateTexture) ~= "function" then
        return
    end

    local ok, sample = pcall(made.CreateTexture, made)
    if not ok or type(sample) ~= "table" then return end

    local meta = getmetatable(sample)
    local table_ = type(meta) == "table" and meta.__index or nil
    if type(table_) ~= "table" then return end

    for _, method in ipairs(WATCHED_METHODS) do
        if type(table_[method]) == "function" then
            pcall(_G.hooksecurefunc, table_, method, watchHandler)
        end
    end

    WATCHED.done = true
end

--- Remember a texture in the plan.
--
-- Here and only here is the native colour read: one protected call per texture
-- per reconnaissance rather than per application. A value that cannot be
-- computed over (a secret number, see ns.Skin.Numeric) does not get into the
-- plan — the object stays in its native look and is counted in
-- ns.Counters.blocked_darkness. A refusal is still not remembered on the object:
-- the next reconnaissance tries again.
--
-- @param region table a texture that has already passed the rule of selection
-- @param group string the group's key
-- @param window string|nil the name of the window the texture was found in
local function record(region, group, window)
    if PLANNED[region] == generation then return end
    if type(region.SetVertexColor) ~= "function" then return end
    if type(region.GetVertexColor) ~= "function" then return end

    local base = BASE[region]
    if not base then
        local ok, r, g, b = pcall(region.GetVertexColor, region)
        if not ok then return end

        r, g, b = ns.Skin.Numeric(r), ns.Skin.Numeric(g), ns.Skin.Numeric(b)
        if r == nil or g == nil or b == nil then
            -- The engine did not return the native colour: it is a secret one
            -- (ns.Skin.Numeric). Such a case still counts as a refusal and is
            -- counted the same way — but the answer to it used to be a light
            -- texture in the middle of a dark window, and there is nothing to
            -- explain that to the player with.
            --
            -- So the native colour counts as white. For framing that is almost
            -- always true — it is painted white and given its hue by the atlas
            -- — and a multiplier written over white gives exactly the colour the
            -- player chose with the slider. A texture that was painted
            -- something other than white will become an even tone instead of a
            -- darkened version of its own: that is visible to the eye and it is
            -- more honest than leaving it to glow.
            --
            -- Only what the walk went into at all gets here.
            counters.blocked_darkness = counters.blocked_darkness + 1
            r, g, b = 1, 1, 1
        end

        base = { r, g, b }
        BASE[region] = base
    end

    PLANNED[region] = generation

    local n = plan.n + 1
    plan.n = n
    plan.tex[n] = region
    plan.group[n] = group
    plan.win[n] = window
    plan.br[n], plan.bg[n], plan.bb[n] = base[1], base[2], base[3]
    plan.cr[n], plan.cg[n], plan.cb[n] = base[1], base[2], base[3]
    INDEX[region] = n


end

--- Start a walk in slices.
--
-- One queue for the whole addon: windows are opened one at a time, and if a
-- second one was opened in the middle of the first's walk, its subtrees join the
-- same queue.
--
-- @param items table an array of { object, depth, area, name }
-- @param count number how many there are
-- @param skip table|nil a set of objects that are skipped
-- @param former table|nil the plan's former array of textures
-- @param formerN number|nil how many there were
-- @return boolean|nil whether the plan's tree grew; nil means the walk is
--   unfinished
local function startSlice(items, count, skip, former, formerN)
    slice = {
        items = items,
        n = count,
        at = 0,
        skip = skip,
        former = former,
        formerN = formerN,
        hits = 0,
    }

    slice.push = function(child, depth, childArea)
        slice.n = slice.n + 1
        local parent = slice.items[slice.at]
        slice.items[slice.n] = {
            object = child,
            depth = depth,
            area = childArea,
            name = parent.name,
            skip = parent.skip,
        }
    end

    slice.named = {}

    slice.sink = function(region, regionArea)
        local item = slice.items[slice.at]
        slice.hits = slice.hits + 1
        record(region, regionArea or item.area or "window", item.name)

        -- The catalogue is assembled out of what the pass REALLY darkened
        -- rather than out of what it reached: a window without a single picture
        -- of framing is a row in the list of exceptions whose checkbox changes
        -- nothing.
        --
        -- The name is put down at this window's very first picture rather than
        -- at the end of its walk: the walk of a window is broken into slices
        -- and it no longer has an "end" in one place.
        local window = item.name
        if window ~= nil and item.area == nil and not slice.named[window] then
            slice.named[window] = true
            remember(window)
        end
    end

    return Darkness.Drain()
end

--- Walk the next piece of an unfinished walk.
--
-- The work goes on until the queue or the time allotted to the frame (SLICE_MS)
-- runs out. What is left undone stays in the queue, and the next slice goes on
-- the next frame.
--
-- What was found is applied at the end of each slice rather than at the end of
-- the whole walk: a window darkens visibly from the top down instead of standing
-- light until the walk is over.
--
-- @return boolean|nil whether the plan's tree grew; nil means the walk is
--   unfinished
function Darkness.Drain()
    local work = slice
    if work == nil then return nil end

    local settings = Settings()
    if settings == nil then
        slice = nil
        return nil
    end

    local from = plan.n + 1
    local started = nowMs()

    while work.at < work.n do
        work.at = work.at + 1
        local item = work.items[work.at]
        -- The set of the taken is taken from the record itself rather than
        -- from the queue: a named group's frame does not have it (it lies in
        -- that set itself) while a window of the general pass does.
        walk(item.object, item.depth, item.skip, work.sink, item.area,
            work.push)

        -- The frame's time ran out — the rest goes on the next frame.
        local budget = SLICE_MS
        if work.first then budget = FIRST_SLICE_MS end
        if started ~= nil and (nowMs() - started) >= budget then break end
    end

    work.first = false

    local grew = plan.n >= from
    applyPlan(settings, from)

    -- What this slice cost, painting included.
    --
    -- Measured after the painting rather than after the walk: the frame's
    -- cost to the player is both, and it is the frame he feels. The clock is
    -- the one the slicing already uses, and outside the game there is none -
    -- in which case nothing is recorded and the walk is simply done whole.
    local spent = nil
    if started ~= nil then
        local ended = nowMs()
        if ended ~= nil then spent = ended - started end
    end

    if spent ~= nil then
        local store = Store()
        if store ~= nil then
            local cost = store.cost
            cost.slices = cost.slices + 1
            cost.total = cost.total + spent
            if spent > cost.worst then cost.worst = spent end

            -- The first walk to finish is the login walk, and it is the one
            -- the question is about. After it the numbers go on growing with
            -- every window opened, which is a different question.
            if work.at >= work.n and cost.login == nil then
                cost.login = cost.total
                cost.loginSlices = cost.slices
            end
        end
    end

    if work.at >= work.n then
        slice = nil

        -- The walk is over — restore the native look to those that did not
        -- get into the new plan (see Darkness.RestoreDropped). Here rather
        -- than in the reconnaissance: "did not get in" is known only when
        -- there is nowhere left to look.
        if work.former ~= nil then
            Darkness.RestoreDropped(work.former, work.formerN)
        end

        return grew
    end

    -- The queue is not empty: the next slice goes on the next frame.
    local timer = _G.C_Timer
    if type(timer) == "table" and type(timer.After) == "function" then
        pcall(timer.After, 0, function() pcall(Darkness.Drain) end)
    else
        -- There is no clock (outside the game) — we finish it right here: a
        -- test needs a finished walk rather than half of one.
        return Darkness.Drain()
    end

    return nil
end

-- How far up the tree to climb in search of a familiar frame.
--
-- Six generations: no button stands further than that from its window, while
-- every generation is one call to the game. It is paid only for a picture that
-- is not in the plan yet, and only once: the area found is remembered.
local ADOPT_CLIMB = 6

--- The area of the nearest familiar frame up the tree.
--
-- Needed twice over: by a picture created by the game (its owner may have
-- appeared together with it) and by a subtree the game has just shown.
--
-- @param frame table
-- @return string|boolean|nil the area's key, false ("the common one") or nil
local function areaAbove(frame)
    local known = frame
    local area = FRAME_AREA[known]
    local climbed = 0

    while area == nil and climbed < ADOPT_CLIMB do
        local up = known.GetParent
        if type(up) ~= "function" then break end

        local fine, above = pcall(up, known)
        if not fine or type(above) ~= "table" then break end

        known = above
        area = FRAME_AREA[known]
        climbed = climbed + 1
    end

    return area
end


--- Walk a subtree the game has just shown.
--
-- A list row, a tab, a pool's reserve: the reconnaissance skipped them (they
-- were hidden) and now they are on the screen. The walk goes in the same slices
-- and by the same rule as everything else; the area taken is the one the frame
-- had at the instant it was skipped, or the nearest known one up the tree.
--
-- @param frame table
-- @param area string|nil
function sweepShown(frame, area)
    if type(frame) ~= "table" then return end

    local settings = Settings()
    if settings == nil then return end

    if area == nil then area = areaAbove(frame) end
    if area == UNTOUCHED then return end
    if area == false then area = nil end

    local items = { { object = frame, depth = 1, area = area,
        skip = coveredFrames(), name = nil } }

    startSlice(items, 1, nil, nil, nil)
end

--- Adopt a picture the game created a moment ago.
--
-- Why. List rows, icons and tabs the game creates as things go along — after the
-- walk over that window has already passed. They used to be picked up by a
-- return half a second later, and the player had time to see the native look.
--
-- Now the picture itself announces its appearance (the watcher on the shared
-- method table), while its owner remembers which area it belongs to
-- (FRAME_AREA). That is enough: neither a walk nor a wait.
--
-- Somebody else's window the walk never went over is not touched: we know
-- nothing about its area, and painting on a guess is worse than not painting.
--
-- @param texture table
function adopt(texture)
    local owner = texture.GetParent
    if type(owner) ~= "function" then return end

    local ok, parent = pcall(owner, texture)
    if not ok or type(parent) ~= "table" then return end

    -- The picture's owner may have appeared together with it.
    --
    -- That is how the buffs' icons work: the game takes not a picture out of
    -- its reserve but a whole button, and the walk saw neither the button nor
    -- its picture. But up the tree stands something it did see — the buff grid
    -- itself — and its area is the very same one (areaAbove).
    local area = areaAbove(parent)

    -- The bar's framing is recognised by its picture even when there is
    -- nothing familiar up the tree at all: another bar addon rehung the gryphon
    -- onto itself, and the climb runs into its frame.
    if area == nil or area == false or area == "addons" then
        local claimed = artArea(imageOf(texture))
        if claimed then area = claimed end
    end

    if area == nil then return end

    -- The climb ran into something we do not touch at all (the map's canvas,
    -- the colour picker's wheel). The marker is remembered for the direct owner:
    -- the next tile of terrain will turn back at once, without a climb.
    if area == UNTOUCHED then
        FRAME_AREA[parent] = UNTOUCHED
        return
    end

    -- The area found is remembered for the direct owner: this same button's
    -- next picture will do without a climb.
    FRAME_AREA[parent] = area

    if area == false then area = nil end

    if ns.Skin.Forbidden(texture) then return end
    if Darkness.IsOurs(texture) then return end
    if objectType(texture) ~= "Texture" then return end

    -- Contents named by their own owner.
    --
    -- The walk asks the frame about this (contentRegions): an item's icon
    -- in a bag slot lies in the "icon" field, a portrait in "portrait", a
    -- fill in whatever the bar calls its own. The picture itself, meanwhile,
    -- has neither a name nor a special path — just a file number, which is what
    -- framing is named by in this client too.
    --
    -- The adoption of a picture did not ask this question, and the bag slots
    -- turned black: the author sent in a screenshot saying he had asked for
    -- such things not to be painted.
    for i = 1, #CONTENT_FIELDS do
        if parent[CONTENT_FIELDS[i]] == texture and fieldIsContent(texture) then
            return
        end
    end

    if type(parent.GetStatusBarTexture) == "function" then
        local fine, fill = pcall(parent.GetStatusBarTexture, parent)
        if fine and fill == texture then return end
    end

    if area ~= ICON_AREA and not chromeOf(texture) then return end

    local settings = Settings()
    if settings == nil then return end

    local from = plan.n + 1
    record(texture, area or "window", nil)
    if plan.n >= from then applyPlan(settings, from) end
end

--- Reconnoitre the interface and gather what was found into the plan.
-- The very same walk as before: the named groups by their own names, everything
-- else from the interface's root over every named window. Not one list of names
-- was added here and none was taken away.
local function build()
    -- The former array is remembered so that the ONES THAT DROP OUT can be
    -- restored afterwards.
    --
    -- Why that is needed. The rule of selection changes, and a texture that was
    -- framing yesterday is deemed a reading today: it will not get into the new
    -- plan, and there will be nobody to restore it — it would stay dark and grey
    -- forever. The author saw that on the bars' fills.
    --
    -- Why not "restore everything and then search afresh". That is exactly what
    -- stood here for one edit, and it was worse: a reconnaissance is sometimes
    -- incomplete — a window is not created yet, a frame is protected by the
    -- engine, the player died and the game rebuilt half the interface — and then
    -- the restoration had already happened while the new darkening never reached
    -- half the screen. The author sent in exactly that: after a death the
    -- darkening disappeared altogether and only the grey was left.
    --
    -- So what is restored is only what really dropped out: the array of former
    -- textures is checked against the new plan by the generation's marker.
    local former, formerN = plan.tex, plan.n

    Darkness.Invalidate()
    refreshLift(Settings())

    local covered = coveredFrames()

    -- The bar's framing images are remembered here, before a single step of
    -- the walk.
    --
    -- The order decides everything here, and in the loop over the groups below
    -- it does not come out right: the general pass gets into the queue earlier
    -- than the queue reaches the framing group, while the queue is taken apart
    -- in order. What was remembered along the way would be late by exactly the
    -- window it was all started for.
    --
    -- This needs no walk: the names are resolved by the compatibility layer, and
    -- the picture is asked of the object itself.
    learnArt()

    -- The reconnaissance is gathered into a queue and goes in slices
    -- (Darkness.Drain).
    --
    -- It used to go whole, in one piece, and that was tolerable exactly as long
    -- as it was called once per entry into the game. Now it is also called by
    -- the loading of a load-on-demand addon of the game's — and those load at
    -- the very instant the player opens the talents or professions window. A
    -- full walk of the interface in that frame the player sees as a freeze, and
    -- that is exactly what the author saw.
    local items, count = {}, 0

    -- The set of the taken is not passed to a named group's own frames: they
    -- lie in it themselves, and the walk would turn back at the threshold. To
    -- the general pass it is passed: there what is taken belongs to others.
    local function add(object, area, window, skip)
        if type(object) ~= "table" then return end
        count = count + 1
        items[count] = { object = object, depth = 0, area = area,
            name = window, skip = skip }
    end

    for i = 1, #GROUPS do
        local key = GROUPS[i].key

        if GROUPS[i].general then
            -- The general pass. Not one name: the walk goes from the
            -- interface's root and takes every named window, including the ones
            -- nobody knows — that is what it is written for.
            local root = _G[ROOT]
            if type(root) == "table"
                and type(root.GetChildren) == "function" then
                local ok, children = pcall(gather, root.GetChildren, root)
                if ok then
                    for j = 1, #children do
                        local child = children[j]
                        if Darkness.ShouldSweep(child, covered) then
                            -- The name has already been asked for by the
                            -- rule of reach, and it is asked a second time:
                            -- ShouldSweep has a question of its own ("do we
                            -- take it on"), and returning a name from there
                            -- would mean making the answer to one question the
                            -- answer to two.
                            add(child, nil, stringFrom(child, "GetName"),
                                covered)
                        end
                    end
                end
            end
        elseif not GROUPS[i].dynamic then
            -- Resolve returns only the frames that exist in this client: a
            -- group that is not in the client gives an empty list, and the loop
            -- silently does nothing. There are no checks of the client's
            -- version here and there must not be.
            local ok, names, objects = pcall(ns.Compat.Resolve, key)
            if ok and type(names) == "table" and type(objects) == "table" then
                for j = 1, #names do
                    add(objects[j], key, nil, nil)
                end
            end
        end
        -- A group whose frames the game itself creates and tears down
        -- (dynamic) is darkened by its own owner and at the moment the frame
        -- appears. The skip here is not an exclusion from the darkening: its
        -- multipliers are computed by that same Darkness.MultipliersFor, and
        -- the list of exceptions acts on it in exactly the same way.
    end

    startSlice(items, count, covered, former, formerN)

    plan.built = true
    plan.root = _G[ROOT]
end

--- Drain a texture of colour or give its colour back.
-- @param texture table
-- @param grey boolean
local function setGrey(texture, grey)
    if type(texture.SetDesaturated) ~= "function" then return end
    texture:SetDesaturated(grey and true or false)
end

-- What is already drained of colour: the setting's value and how far along the
-- plan it is written.
--
-- Why remember it. The draining of colour is a second question to the same
-- texture, and it must not be asked at every step of the slider: a step of the
-- slider costs two protected calls per texture, that is measured and guarded
-- (tests/test_darkcost.lua), and a third call would double the price of a drag
-- for nothing. The setting, meanwhile, changes incomparably more rarely than the
-- colour.
--
-- So only the difference is written: the setting changed — every texture of the
-- plan is rewritten; the plan's tail was added to (a window opened) — only the
-- tail.
local greyValue, greyDone = nil, 0

--- Bring the plan's draining of colour into line with the setting.
-- @param grey boolean
local function applyGrey(grey)
    local from = greyDone + 1
    if grey ~= greyValue then
        from = 1
        greyValue = grey
    end

    for i = from, plan.n do
        pcall(setGrey, plan.tex[i], grey)
    end
    greyDone = plan.n
end

--- Write a colour without touching the transparency.
-- The reading and the writing go through one protected call rather than two: on
-- a step of the slider that is a difference of tens of thousands of calls.
--
-- The transparency is taken afresh right before the write and returned exactly
-- as it was. There is no arithmetic over it, so a secret value passes straight
-- through. The three-argument form is not enough: without a fourth argument the
-- engine sets the transparency to one, that is, brings back onto the screen what
-- the styling layer quenched.
local function writeColor(texture, r, g, b)
    local _, _, _, alpha = texture:GetVertexColor()

    if alpha ~= nil then
        texture:SetVertexColor(r, g, b, alpha)
    else
        texture:SetVertexColor(r, g, b)
    end
end

--- Mark that what follows is written by us rather than by the game.
--
-- The marker stands around the WHOLE pass rather than around one write, and
-- there are two reasons for that.
--
-- The first is the price. Writing a colour costs exactly two protected calls per
-- texture, and that is guarded (tests/test_darkcost.lua); a third, for the
-- marker's own sake, would double the cost of a drag of the slider.
--
-- The second matters more. The engine rejects a write into a protected texture
-- or one that cannot be computed over, the refusal is caught by a protected call
-- outside — and a marker raised inside the write would stay raised forever. The
-- watcher of other people's repaintings would stay silent from that instant
-- until the end of the session, that is, the whole mechanism would be switched
-- off by the very first refusal. Around the pass one texture's refusal breaks
-- nothing: the pass goes on and takes the marker off itself.
--
-- @param value boolean
local function mine(value)
    writing = value and true or false
end

local function clamp(value)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

--- Walk every remembered page and raise what is dark.
--
-- Called when such windows are opened and on the game's events by which it fills
-- those pages. Cheaper than it seems: there are three or four such pages in the
-- game, and only they are walked.
--
-- @return number how many labels were raised
function Darkness.LiftPages()
    -- The interface is not darkened at all — there is nothing to raise and
    -- raising is not allowed: light letters on a light window would be the same
    -- unreadability from the other side.
    --
    -- The overall strength is asked about rather than an area's: there are
    -- several such pages, they lie in different areas, and the question here is
    -- a single one — has the interface been touched at all.
    local settings = Settings()
    if settings == nil then return 0 end

    -- Not darkened at all: give the fonts their own ink back and stop. This
    -- is the one road back - the slider at zero has to undo the painting as
    -- surely as it undoes the dimming, or a player who turns the addon down
    -- is left with our colour on the game's own pages.
    if Darkness.Factor(settings.amount) >= 1 then
        Darkness.PaintFonts(false)
        return 0
    end

    -- The areas may have moved to "as in the game" since last time.
    refreshLift(settings)

    -- The font objects first, and the walk after. One call paints every
    -- label that inherits from an object, including the ones not created
    -- yet; the walk is then left with only what the game colours inline.
    counters.lifted = counters.lifted + Darkness.PaintFonts(true)

    local count = 0
    for i = 1, pagesN do
        count = count + Darkness.LiftPage(pages[i], 0)
    end
    return count
end

--- How long after a conversation's event the labels are raised again.
--
-- Zero is the next frame, and it is the one that matters. The rest is reserve.
local LIFT_LATER = { 0, 0.5 }

--- Raise the labels again once the game has finished writing them.
--
-- Why the repeat. The comment above PAGE_EVENTS says the raising "is obliged to
-- happen AFTER" the game fills the page — and the subscription did it in the
-- same frame as the event, which is to say possibly before. Whose handler for
-- GOSSIP_SHOW runs first, ours or the game's, is decided by the order of
-- registration, and it is not ours to decide.
--
-- What that looked like. A conversation with a guard: fifteen lines, the first
-- readable and fourteen brown. The first was the button that already existed
-- from an earlier conversation and had been raised then; the other fourteen the
-- game created and coloured after our pass, and nothing returned to them. The
-- author sent that window, and before it a trainer's with one option, dark in
-- the same way and for the same reason.
--
-- The doubling he reported on those same lines is this one defect, not a
-- second: the raising takes a letter's shadow off in the same breath as it
-- raises it (Darkness.Unshadow), so a line the raising never reached keeps
-- both its dark colour and the shadow that smears it.
--
-- Why a repeat rather than a later single pass: the page is often filled
-- within the event itself, and a raising that waited would show the player a
-- frame of brown text. Doing both costs little — a raising walks labels only,
-- the native colours are remembered (TEXT_BASE), and a label already raised is
-- written the same colour again.
--
-- This is the same trap, and the same answer, as LATER for the picture walk:
-- the game fills a window after announcing it.
-- Whether a walk of the last window is already waiting for the next frame.
local refillPending = false

--- Walk the last opened window afresh, once, however many events ask for it.
--
-- Why not on the event itself. The subscription to REFILL_EVENTS used to call
-- the walk straight from the handler, and a walk is a FULL one - it does not
-- ask whether the window has changed, or it would not find the rows created
-- deeper. One event, one full walk.
--
-- That is affordable while the events arrive one at a time. They do not. The
-- author raised a profession by one point and the whole window blinked and
-- lagged: a skill-up fires SKILL_LINES_CHANGED and TRADE_SKILL_UPDATE, the
-- game refills the list, and the list refilling fires them again. Each of them
-- repainted a window of hundreds of textures, and the repaints are what he saw
-- as blinking.
--
-- Collapsing a burst into one pass on the next frame costs nothing and is what
-- this file already does for ADDON_LOADED, where a batch of events arrives in
-- a row at login - the note there says the deferral "merges them into one
-- reconnaissance instead of a dozen". The same reasoning, the same answer.
--
-- The next frame rather than a delay: by then the game has finished refilling,
-- and the player is not shown a window that stays unpainted for half a second.
--
-- With no clock the walk happens at once, as it did before: a client without
-- C_Timer is not a reason to stop repainting refilled windows.
function Darkness.RefillSoon()
    local window = Darkness.lastWindow
    if type(window) ~= "table" then return end

    local timer = _G.C_Timer
    if type(timer) ~= "table" or type(timer.After) ~= "function" then
        pcall(Darkness.ApplyToWindow, window, true)
        return
    end

    if refillPending then return end
    refillPending = true

    pcall(timer.After, 0, function()
        refillPending = false
        local latest = Darkness.lastWindow
        if type(latest) == "table" then
            pcall(Darkness.ApplyToWindow, latest, true)
        end
    end)
end

function Darkness.LiftPagesLater()
    local timer = _G.C_Timer
    if type(timer) ~= "table" or type(timer.After) ~= "function" then return end

    for i = 1, #LIFT_LATER do
        pcall(timer.After, LIFT_LATER[i], function()
            pcall(Darkness.LiftPages)
        end)
    end
end

-- The game's own function that fills a quest page, by name.
--
-- Written as a list for the reason USABLE_HOOKS in Modules/Icons.lua is: a
-- name this client does not have is simply not hooked, and that is the same
-- rule the rest of the addon follows for a name it cannot find.
local PAGE_HOOKS = { "QuestInfo_Display" }

-- Whether we are already standing after that function.
local pagesHooked = false

--- Stand after the game's filling of a quest page.
--
-- Why a hook and not an event. The raising of pages runs on announcements -
-- a quest offered, a conversation opened - and the two roads into the same
-- page do not announce the same things. Reading a quest off an NPC announces
-- plenty; picking one out of the list on the world map announces nothing we
-- listen for, and the author put it exactly: "I open the map, pick a quest,
-- and it is not white; I close the map, open the quest, and only then it is".
--
-- The game's own filling is the one moment both roads have in common, and it
-- is the right moment besides: it is where the page's text is written, and
-- where the colour that has to be answered is written with it. A quest title
-- in the log is set black there by hand, over the font object, which is why
-- painting the font objects alone leaves the heading dark while the body of
-- the same page comes out light.
--
-- The page is taken from the call rather than looked up by a name: the
-- function is handed the frame it is filling, so the one frame that matters
-- arrives for free and no guessed name is needed.
local function hookPages()
    if pagesHooked then return end
    if type(_G.hooksecurefunc) ~= "function" then return end

    for i = 1, #PAGE_HOOKS do
        local name = PAGE_HOOKS[i]
        if type(_G[name]) == "function" then
            pcall(_G.hooksecurefunc, name, function(_, parent)
                if type(parent) == "table" then rememberPage(parent) end
                Darkness.LiftPagesLater()
            end)
        end
    end

    -- Once per session either way: a name absent now will be absent later,
    -- and trying again every time the settings are applied would cost a
    -- lookup for nothing.
    pagesHooked = true
end

Darkness.HookPages = hookPages

--- Restore the native colour to everything currently in the plan.
--
-- Why this exists. The ordinary "restore it as it was" is done by the plan
-- itself: an area in the "as in the game" mode gets a multiplier of one, and
-- the application writes the remembered colour back. That works exactly as long
-- as the texture STAYS in the plan.
--
-- There is one case where it leaves the plan: the player unticked "darken the
-- protected windows". After that the reconnaissance does not go into such a
-- window at all, its textures do not get into the plan — and they stay with the
-- colour we wrote last. From the outside that is "I switched it off and the
-- talents stayed dark until a reload".
--
-- So before such a reconnaissance the whole plan is restored: everything in it
-- gets its remembered colour, and the very next reconnaissance immediately
-- darkens whatever is still to be darkened. The extra pass over the plan costs
-- one application and happens only at a click of that checkbox.
--
-- @return number how many textures were restored
function Darkness.RestorePlan()
    local count = 0

    mine(true)
    for i = 1, plan.n do
        local texture = plan.tex[i]
        if pcall(writeColor, texture, plan.br[i], plan.bg[i], plan.bb[i]) then
            count = count + 1
        end
        -- The draining of colour is taken off along with the colour: "as it
        -- was" means as it was entirely rather than by half.
        pcall(setGrey, texture, false)
    end

    mine(false)

    -- The memory of how far the draining of colour is written is zeroed right
    -- here: otherwise the next application will decide there is nothing to
    -- write.
    greyValue, greyDone = nil, 0

    return count
end

--- Restore the native look to those that dropped out of the plan.
--
-- Why. The rule of selection changes, and a texture that was framing yesterday
-- is deemed a reading today: it will not get into the new plan, and there will
-- be nobody to restore it — it would stay dark and grey forever. The author saw
-- that on the bars' fills.
--
-- Why the ones that dropped out specifically rather than the whole former plan.
-- Restoring everything at once — before the new reconnaissance — stood here for
-- one edit already and turned out to be worse: a reconnaissance is sometimes
-- incomplete (a window is not created yet, a frame is protected by the engine,
-- the player died and the game rebuilt half the interface), and then the
-- restoration had already happened while the new darkening never reached half
-- the screen. The author sent in exactly that: after a death the darkening
-- disappeared altogether and only the grey was left.
--
-- The check goes by the generation's marker — one approach to a table per
-- texture; a protected call falls only to those that really dropped out, and
-- there are usually none of those.
--
-- @param former table the former array of textures
-- @param formerN number how many there were
-- @return number how many textures were restored
function Darkness.RestoreDropped(former, formerN)
    if type(former) ~= "table" then return 0 end

    local count = 0

    mine(true)
    for i = 1, formerN or 0 do
        local texture = former[i]
        if texture ~= nil and PLANNED[texture] ~= generation then
            local base = BASE[texture]
            if base then
                if pcall(writeColor, texture, base[1], base[2], base[3]) then
                    count = count + 1
                end
                pcall(setGrey, texture, false)
            end
        end
    end
    mine(false)

    return count
end

--- Put our colour back onto what the game repainted.
--
-- A pass over exactly what was touched rather than over the whole plan. The
-- difference is not a notional one: there are fifteen hundred pictures in the
-- plan, the game touches a dozen at a time, and its occasions are the opening of
-- a window, the scrolling of a list, any animation. Repainting the plan on every
-- such occasion was the very hitch the author saw at once: it lagged very badly
-- when he opened a window.
--
-- The colour is taken ready-made (plan.cr) rather than computed afresh: it does
-- not depend on what the game wrote over it.
--
-- @return number how many pictures were restored
function Darkness.Repaint()
    local count = 0

    mine(true)
    for i = 1, dirtyN do
        local at = dirty[i]
        local texture = plan.tex[at]

        if texture ~= nil then
            DIRTY[texture] = nil
            if pcall(writeColor, texture,
                plan.cr[at], plan.cg[at], plan.cb[at]) then
                count = count + 1
            end
            if greyValue ~= nil then pcall(setGrey, texture, greyValue) end
        end

        dirty[i] = nil
    end
    mine(false)

    dirtyN = 0
    return count
end

--- Apply the multipliers to the already reconnoitred part of the plan.
--
-- The hot path: it is repeated at every step of the slider, and everything that
-- can be left undone here is left undone here.
--
-- Why not ns.Skin.Shade. Shade exists for the sake of values read from the game:
-- it asks every channel whether it can be computed with, and that is six
-- protected calls per texture. What lies in the plan are numbers that have
-- already passed that check during the reconnaissance, while the multipliers are
-- our own arithmetic. There is nobody to ask here, and a multiplication stays a
-- multiplication.
--
-- @param settings table the subsystem's settings
-- @param from number from which place in the plan to apply
-- @return number how many textures were written
function applyPlan(settings, from)
    -- The areas' multipliers are computed once per application rather than
    -- per texture. One common multiplier for all of them used to be computed
    -- here while the areas only chose between it and a one; now an area may have
    -- a strength of its own, and the computation moved inside a loop. The loop
    -- goes over a dozen areas rather than over tens of thousands of textures,
    -- and the hot path below did not grow dearer by a single approach.
    local tint = tintOf(settings)
    -- The class colour is asked for once per application rather than per area:
    -- it is one per player and does not change during the pass.
    local class = playerClassColor()
    -- mc is an area's brightness ceiling (Darkness.Ceiling), the fourth table
    -- of the same enumeration: computed in the same place as the multipliers and
    -- over the same areas.
    local mr, mg, mb, mc = {}, {}, {}, {}

    -- The windows are light again — which means the text is obliged to become
    -- dark again.
    --
    -- Otherwise the result is the same unreadability, only from the other side:
    -- light letters on a light window. It is the multiplier that is asked about
    -- rather than the mode: a zero on the slider is also "does not darken", and
    -- it is not named by the word "native".
    if Darkness.Factor(settings.amount) >= 1 then
        Darkness.DropText()
    end
    for i = 1, #GROUPS do
        local key = GROUPS[i].key
        mr[key], mg[key], mb[key] = Darkness.GroupMultipliers(
            key, settings.mode, settings.amount, tint,
            settings.color, class)

    end

    -- Exceptions by a single window. A one instead of a multiplier is the same
    -- arithmetic as a group's: what is excluded returns to its remembered colour
    -- rather than staying dark forever.
    --
    -- The table is taken once per application, while in the loop itself it costs
    -- one lookup by key per texture. Neither a protected call nor an approach to
    -- the interface's tree was added here: the cost ceilings measure exactly
    -- those.
    local excludeWindow = settings.excludeWindow
    if type(excludeWindow) ~= "table" then excludeWindow = nil end

    -- The brightness ceiling is computed one per area rather than per texture:
    -- an area's strength is its own, and in the loop the ceiling costs one
    -- lookup by key and three comparisons.
    local levelling = settings.level ~= false
    if levelling then
        for i = 1, #GROUPS do
            local key = GROUPS[i].key
            local top = mr[key]
            if mg[key] > top then top = mg[key] end
            if mb[key] > top then top = mb[key] end
            mc[key] = Darkness.Ceiling(top)
        end
    end

    -- The gryphons get a number of their own (GRYPHON_LIFT), and it is applied
    -- last, after the ceiling.
    --
    -- The order is not a matter of indifference here. The ceiling is computed
    -- from the area's strength, and by raising the strength before it we would
    -- raise the ceiling along with it — the correction would come out twice as
    -- large as the one named. The author named a number rather than a direction:
    -- "a multiplier of 1.05".
    --
    -- It stands here rather than in GroupMultipliers: that function answers the
    -- question "what did the player ask for this area", while this is a
    -- correction for what the area is drawn with, and they must not be mixed in
    -- one answer.
    mr[GRYPHON_GROUP] = mr[GRYPHON_GROUP] * GRYPHON_LIFT
    mg[GRYPHON_GROUP] = mg[GRYPHON_GROUP] * GRYPHON_LIFT
    mb[GRYPHON_GROUP] = mb[GRYPHON_GROUP] * GRYPHON_LIFT

    local count = 0

    -- What follows is written by us: see mine.
    mine(true)

    for i = from, plan.n do
        local key = plan.group[i]
        local kr, kg, kb = mr[key], mg[key], mb[key]

        -- An excluded window is not only not darkened but not levelled
        -- either: "leave it as it is" means as it is entirely.
        local excluded = false
        if excludeWindow ~= nil then
            local window = plan.win[i]
            if window ~= nil and excludeWindow[window] then
                kr, kg, kb = 1, 1, 1
                excluded = true
            end
        end

        local lr, lg, lb = plan.br[i], plan.bg[i], plan.bb[i]
        if levelling and excluded ~= true then
            lr, lg, lb = Darkness.Levelled(lr, lg, lb, mc[key])
        end

        local r = clamp(lr * kr)
        local g = clamp(lg * kg)
        local b = clamp(lb * kb)

        plan.cr[i], plan.cg[i], plan.cb[i] = r, g, b

        if pcall(writeColor, plan.tex[i], r, g, b) then
            count = count + 1
            -- The one place where the darkening really changes the game's
            -- look. A zero here is proof that the subsystem did nothing,
            -- however full the plan may be.
            counters.dimmed = counters.dimmed + 1
        else
            counters.blocked_darkness = counters.blocked_darkness + 1
        end
    end

    mine(false)

    -- The grey last, over what is already darkened.
    --
    -- The order was named by the author: first the black's value off the slider
    -- and then the grey artwork over it. And so it stands: first the colour is
    -- written over the whole plan, and only then the draining of colour.
    --
    -- It is worth knowing what this order does NOT change. The draining of
    -- colour is a property of the picture itself rather than of the colour over
    -- it: the engine first drains the pixels of colour and then multiplies them
    -- by the colour, and an addon can do nothing to swap those two actions
    -- round. The difference is visible only with a coloured tint: the tint lies
    -- over the grey rather than drowning in it.
    applyGrey(settings.desaturate == true)
    return count
end

-- Whether the gryphons are shown as far as we are concerned.
--
-- It starts as "yes", and that is not a guess: the game draws them itself, and
-- until the player has said otherwise they are in place. The value is needed for
-- exactly one thing: not to call Show on what is shown (see ApplySettings).
local gryphonsShown = true

--- Show or hide the gryphons at the ends of the main bar.
--
-- As a setting of its own rather than part of the darkening, and here is why.
-- The darkening answers the question "how dark", while the gryphons are the
-- question "are they there at all": the player either wants the old bar's
-- artistic framing or does not want it in any colour. In the example (DarkMode)
-- this switch is also a separate one and also in the general section.
--
-- The names are taken from the compatibility layer — the "actionbar-art" group —
-- rather than enumerated here: in different builds the gryphons lie now as
-- globals, now as fields inside the bar, and a second list would diverge from
-- the first silently.
--
-- They must not be hidden in combat: the action bar is protected by the engine,
-- and a call of Hide on a part of it in combat will be rejected. So the work is
-- deferred until combat is left, by the same path everything else in the addon
-- defers it.
--
-- @param shown boolean whether to show them
-- @return number how many objects were touched
function Darkness.ShowGryphons(shown)
    local ok, names, objects = pcall(ns.Compat.Resolve, "actionbar-art")
    if not ok or type(objects) ~= "table" then return 0 end

    local touched = 0
    for i = 1, #objects do
        local object = objects[i]
        if type(object) == "table" then
            local method = shown and object.Show or object.Hide
            if type(method) == "function" and pcall(method, object) then
                touched = touched + 1
            end
        end
    end

    return touched
end

--- Apply the settings.
-- The only path of application: entering the game, changing the profile and the
-- appearance of a new window all lead here. The reconnaissance is done afresh
-- here: this path is called when the interface's composition could have changed.
--
-- An edit of the slider goes not here but to Darkness.Refresh through
-- Darkness.Schedule — what was reconnoitred is reused there.
function Darkness:ApplySettings()
    local settings = Settings()
    if not settings then return end

    -- The parchment fonts, painted or given back, on every application.
    --
    -- Here rather than only inside the page walk, because the road back has
    -- to work with no page on screen: a player who drags the slider to zero
    -- while no quest is open would otherwise keep our ink on the game's
    -- pages until the next time one was opened. One call either way, and it
    -- costs a handful of writes.
    Darkness.PaintFonts(Darkness.Factor(settings.amount) < 1)

    -- And stand after the game's own filling of a quest page, so a page it
    -- fills without announcing anything is answered at the moment it is
    -- filled. Only once the player has asked for darkening at all: until
    -- then the addon touches nothing of the game's, hook included.
    if Darkness.Factor(settings.amount) < 1 then hookPages() end

    -- The gryphons come before the darkening: there is no point darkening what
    -- is hidden, while what is shown is obliged to be in the plan.
    --
    -- They are touched only when the answer has changed. Otherwise a fresh
    -- install would show what is shown — that is, would call Show on a frame of
    -- the game's for nothing, while the addon's rule is the opposite: until the
    -- player has asked for anything, not one frame of the game's is touched. And
    -- that is guarded (tests/test_coldboot.lua).
    local wanted = settings.gryphons ~= false
    if wanted == gryphonsShown then
        -- Nothing has changed.
    elseif ns.Combat and ns.Combat.InCombat and ns.Combat.InCombat() then
        -- In combat we leave it as it is: the attempt would be rejected by
        -- the engine, and a refusal of the engine's costs more than a gryphon
        -- that will wait a minute.
        gryphonsShown = wanted
        ns.Combat.Enqueue(ns.Combat.QueueFor(Darkness.name), "gryphons",
            function() Darkness.ShowGryphons(wanted) end)
    else
        gryphonsShown = wanted
        Darkness.ShowGryphons(wanted)
    end

    -- The application goes on inside the reconnaissance, in slices: each slice
    -- paints what was found in it (Darkness.Drain). There is deliberately no
    -- second application here — it would write a colour over one just written
    -- and would count one and the same texture twice.
    build()
end

--- Apply the current value to what has already been reconnoitred.
--
-- The slider's path. The interface's tree is not touched at all: the plan was
-- built earlier and does not depend on the slider's position. If there is no
-- plan yet (a first movement before the first application) or the interface's
-- root has changed, the reconnaissance is done once, and after that the drag goes
-- over what is ready.
function Darkness.Refresh()
    local settings = Settings()
    if not settings then return end

    if not plan.built or plan.root ~= _G[ROOT] then build() end
    applyPlan(settings, 1)
end

-- What is deferred until the next frame: nil is nothing, "value" a new value of
-- the slider, "full" that the interface's composition could have changed.
local pending = nil

-- Whether a timer for the next frame has already been started. A second one for
-- the same work is not started: one frame, one application.
local scheduled = false

--- Whether there is deferred work.
-- Needed by the tests: after a drag nothing of the subsystem's should be left
-- running.
-- @return boolean
function Darkness.Pending()
    return pending ~= nil
end

--- Do what was deferred right now.
-- The flag is cleared before the work rather than after it: an application that
-- fell over halfway must not leave the subsystem with work deferred forever.
function Darkness.Flush()
    local what = pending
    if not what then return end
    pending = nil

    if what == "full" then
        Darkness:ApplySettings()
    else
        Darkness.Refresh()
    end
end

--- Defer an application until the next frame.
--
-- An AceGUI slider calls the handler at every division of a drag — that is
-- dozens of calls per drag, and each of them did a full walk of the interface
-- before this edit. Now the walk is done once while the applications themselves
-- merge into one per frame: between two frames the player sees no difference
-- anyway, and the work comes out at exactly as much as he will see.
--
-- The darkening follows the slider live in the process rather than catching up
-- with it when it is released: what is deferred is the work rather than the
-- value, and the value taken is whichever stands in the settings at the moment
-- of the frame.
--
-- This leaves nothing running behind it. C_Timer.After is a one-off call, and no
-- OnUpdate is hung anywhere; while work is deferred nothing is started a second
-- time. There is no client without C_Timer, but outside the game there is none,
-- and then the work is done at once — the path stays the very same.
--
-- @param full boolean|nil true if the interface's composition could have
--   changed
function Darkness.Schedule(full)
    -- "The composition could have changed" overrides "a new value" but not the
    -- other way round: a deferred reconnaissance must not be lost to a movement
    -- of the slider.
    if full then
        pending = "full"
    elseif not pending then
        pending = "value"
    end

    local timer = _G.C_Timer
    if type(timer) == "table" and type(timer.After) == "function" then
        -- A second timer for work already deferred is not started: one frame,
        -- one application.
        if not scheduled then
            scheduled = true
            local ok = pcall(timer.After, 0, function()
                scheduled = false
                Darkness.Flush()
            end)
            if ok then return end
            scheduled = false
        else
            return
        end
    end

    Darkness.Flush()
end

-- What we saw of a window last time: window -> { generation, children,
-- regions }.
--
-- Why. The walk of a window costs one approach to an object per node of it, and
-- the talents window is hundreds of nodes. Opening it a second time, we walked
-- all the same for zero new textures: the plan knows them already and does not
-- make a second record. That is noticeable to the eye — why does it lag a bit
-- when you open the talents.
--
-- How we learn that a window has not changed. By the number of children and the
-- number of regions on the window itself. That is two approaches instead of
-- hundreds, and it catches exactly the case the walk is repeated for: the game
-- added parts to the window (the buttons of a talent row, a tab, a row). Parts
-- added DEEPER than the first level are not caught this way — they are caught by
-- the next full reconnaissance, which runs on every entry into the world and on
-- every load of another addon.
--
-- The generation in the record is there so that a fresh reconnaissance (a change
-- of setting, an entry into the world) zeroes everything remembered at a stroke:
-- after it there is nothing in the plan, and the window has to be walked
-- again.
local SEEN = ns.Skin.Memory()

--- How many children and regions an object has.
-- Two approaches, and both protected: the object is somebody else's.
-- @param frame table
-- @return number, number
local function shapeOf(frame)
    local children, regions = 0, 0

    if type(frame.GetChildren) == "function" then
        local ok, list = pcall(gather, frame.GetChildren, frame)
        if ok then children = #list end
    end

    if type(frame.GetRegions) == "function" then
        local ok, list = pcall(gather, frame.GetRegions, frame)
        if ok then regions = #list end
    end

    return children, regions
end

--- Whether a window has changed since last time.
--
-- A pure function over two records: tested without a client.
--
-- @param seen table|nil what was seen last time
-- @param generation number the plan's current generation
-- @param children number
-- @param regions number
-- @return boolean
function Darkness.WindowChanged(seen, generation, children, regions)
    if type(seen) ~= "table" then return true end
    if seen.generation ~= generation then return true end
    if seen.children ~= children then return true end
    if seen.regions ~= regions then return true end
    return false
end

--- Darken one window right now.
--
-- Most windows the game creates at the instant the player opens them for the
-- first time: the professions, the bank, the auction house, the mail. A pass
-- done once at the entry would not have seen one of them, and the player would
-- have seen exactly what the author complained about — a heap of windows not
-- being darkened.
--
-- A named group's frame does not get here: its own pass with its own multiplier
-- is occupied with it.
--
-- @param frame table
-- @return number how many textures were processed
function Darkness.ApplyToWindow(frame, force)
    local settings = Settings()
    if not settings then return 0 end
    if type(frame) ~= "table" then return 0 end

    local covered = coveredFrames()

    -- A window of a named area: the character sheet, the reputations, the
    -- bags, the chat.
    --
    -- The showing of such a window used to do NOTHING: it was listed as taken,
    -- and what is taken only a full reconnaissance walks. And the
    -- reconnaissance happens at the entry into the world — that is, at a time
    -- when there is not one section in the character sheet, not one row in the
    -- reputation list and not one header in the statistics: all of that the
    -- game creates at the first opening.
    --
    -- And so it came about: the headers stayed golden while switching any
    -- checkbox off and on fixed them — that road goes through a full
    -- reconnaissance, with the window already open and filled. The author found
    -- that himself.
    --
    -- So we do go into our own window, and the area we take is the one it
    -- belongs to: otherwise its mode and its colour would fall to somebody
    -- else.
    local area = covered[frame]

    -- A true instead of a key means a group we do not touch at all (the world
    -- map, the colour picker window). There is still nothing to do here.
    if area == true then return 0 end

    if type(area) == "string" then
        -- The set is built afresh on every call, so the edit is a local one:
        -- for the duration of this walk the window stops being taken as far as
        -- it itself is concerned.
        covered[frame] = nil
    else
        area = nil
    end

    if not Darkness.ShouldSweep(frame, covered) then return 0 end

    -- Where the raising of text is allowed right now. Asked here too rather
    -- than at a full reconnaissance alone: a window is shown more often than it
    -- is reconnoitred afresh.
    refreshLift(settings)

    -- There is no point walking a window that has not changed since last
    -- time: all its textures are already in the plan, and a second walk would
    -- add exactly zero.
    --
    -- "Has not changed" is computed from the number of direct children and
    -- regions of the window itself — and that is exactly its limit. The rows of
    -- the reputation list, the statistics' sections and the character sheet's
    -- headers lie deeper: inside a scroll frame, inside its contents. The game
    -- creates them after the window is shown, the count of direct children does
    -- not change in the process — and the deferred pass refused to go into a
    -- window that "had not changed" although fifty new pictures had appeared
    -- inside it.
    --
    -- Hence force: a return to a window (see LATER) always happens rather than
    -- going by the count. The author found that himself — he switched the
    -- protected-windows checkbox off and on with the character sheet open, and
    -- the headers darkened: that road goes through a full reconnaissance, where
    -- there is no "has not changed" at all.
    local children, regions = shapeOf(frame)
    if force ~= true
        and not Darkness.WindowChanged(SEEN[frame], generation,
            children, regions) then
        -- Text is the exception to "it has not changed, so there is nothing
        -- to do". The window's pictures are the same while the game has
        -- rewritten the letters: a different quest was opened, a different
        -- creature was spoken to.
        --
        -- We walk the page afresh in full rather than over what is already
        -- raised alone: a label that was absent last time or was empty would
        -- otherwise stay dark forever — and a quest's page is empty before a
        -- quest is chosen.
        Darkness.LiftPages()
        return 0
    end
    SEEN[frame] = {
        generation = generation,
        children   = children,
        regions    = regions,
    }

    -- A reconnaissance of one window rather than of the whole interface, and
    -- only of what is not in the plan yet: a window opened a second time adds
    -- not one texture and does not repaint what is already repainted. What is
    -- darkened is the tail added to the plan — hence "nothing twice".
    --
    -- Where to apply from.
    --
    -- An ordinary showing of a window adds to the plan's tail and paints that
    -- alone: there is no point painting afresh what is already painted.
    --
    -- A return to a window (force) is another matter. List rows the game takes
    -- out of a pool and, at the handing out, assigns them pictures and colours
    -- afresh, over ours. The texture is one and the same in the process: it is
    -- already in the plan, the reconnaissance does not add it again, and the
    -- tail turns out to be empty — the walk honestly goes over the window and
    -- writes not one colour. That is exactly how the golden headers looked, the
    -- ones that were fixed by toggling any checkbox: that road paints the whole
    -- plan.
    --
    -- So a return paints from the beginning. That costs one pass over the plan —
    -- with no approaches to the interface's tree — and happens twice per opening
    -- of a window.
    local from = plan.n + 1
    local name = stringFrom(frame, "GetName")
    local hits = 0
    -- The area comes from the walk and is obliged to reach the record.
    --
    -- Here it used to be lost: the sink took one argument, and a quest window's
    -- texture went into the plan under the common "window" group. And the "Quest
    -- and Dialog Text" area's default is "as in the game" (DEFAULT_MODES), and
    -- it was precisely that which did not reach those windows: the parchment
    -- darkened by the overall strength while the text on it is printed dark on
    -- light — the one place in the game where it is. The author sent in two
    -- screenshots in a row, the map with its quest panel and a conversation with
    -- a creature: completely unreadable.
    --
    -- The general pass did not have that defect (its sink did accept an area),
    -- and so the trouble looked inexplicable: the same window through the same
    -- walk darkened differently depending on who had found it.
    local sink = function(region, area)
        hits = hits + 1
        record(region, area or "window", name)
    end
    -- The walk goes in slices: see Darkness.Drain.
    --
    -- The first slice is done right here, in the same frame the game showed the
    -- window in: otherwise the player sees a flash of the native look, and he
    -- has already said he will not put up with a flash. The rest go on the
    -- following frames, three milliseconds at a time, and the window darkens
    -- visibly.
    slice = {
        items = { { object = frame, depth = 0, area = area, name = name,
            skip = covered } },
        n = 1,
        at = 0,
        -- The window is being shown to the player right now: the first slice
        -- is a generous one so that he does not see the native look (see
        -- FIRST_SLICE_MS).
        first = true,
    }

    slice.push = function(child, depth, childArea)
        slice.n = slice.n + 1
        local parent = slice.items[slice.at]
        slice.items[slice.n] = {
            object = child,
            depth = depth,
            area = childArea,
            name = parent.name,
            skip = parent.skip,
        }
    end

    slice.sink = function(region, regionArea)
        hits = hits + 1
        record(region, regionArea or "window", slice.items[slice.at].name)
    end

    local grown = Darkness.Drain()

    -- The watcher of the window's own showing.
    --
    -- Why it is needed on top of ShowUIPanel. The game calls ShowUIPanel BEFORE
    -- the showing, and at that instant half the window does not yet exist: a
    -- tab, a list, a panel — all of that the game creates in its own show
    -- handler, that is, later than us. The return half a second later picks that
    -- up, but the player has time to see the native look and its change into
    -- ours: he saw a flicker from the default into our repainting.
    --
    -- Show happens AFTER the creation and in the same frame: the walk from here
    -- manages to paint the new before the frame is drawn.
    --
    -- Placed once per window and costing one call: we do not call Show
    -- ourselves, and the watcher cannot answer itself.
    if not SHOWN_WATCH[frame] and type(_G.hooksecurefunc) == "function"
        and type(frame.Show) == "function" then
        if pcall(_G.hooksecurefunc, frame, "Show", function(self)
            pcall(Darkness.ApplyToWindow, self, true)
        end) then
            SHOWN_WATCH[frame] = true
        end
    end

    -- A window opened for the first time gets into the catalogue exactly here:
    -- at the entry into the game it did not yet exist, and the reconnaissance
    -- never saw it. That is what the catalogue outlives a session for.
    if hits > 0 then remember(name) end

    -- What this walk yielded decides whether to call a return next time.
    --
    -- The measure is the plan's growth rather than the number of pictures met:
    -- the walk meets as many of them as last time, while there may not be a
    -- single new one among them.
    --
    -- Asked only of a finished walk: a slice that ran out of time says nothing
    -- yet about whether there is anything new in the window.
    if force == true and grown ~= nil then GREW[frame] = grown end

    return applyPlan(settings, from)
end

--============================================================================
-- Why this window did not darken
--============================================================================
--
-- An answer to the player's question rather than decoration for the author. A
-- window left light looks the same under any of six causes: the walk never
-- reached it, the engine forbade touching the object, the frame is protected,
-- the type is skipped entirely, the picture was deemed contents, the depth ran
-- out. While the cause cannot be named it has to be guessed at — and a guess is
-- corrected by rewriting the rule, that is, by breaking what worked.
--
-- The probe goes by THE SAME walk and the same questions as the darkening: the
-- same SKIP_TYPES, the same MAX_DEPTH, the same Darkness.ContentReason, the same
-- prohibition and the same protection. A second walk with rules of its own would
-- answer about itself rather than about what the player sees on his screen.
--
-- It paints nothing and remembers nothing.

-- The verdict "this texture will darken". Named once: the probe marks with it
-- and the display selects by it, and two different spellings would diverge
-- silently — the list of "why it did not darken" would quietly receive
-- everything that did darken.
local DIMS = "dims"
Darkness.PROBE_DIMS = DIMS

--- What is known about an object, in one line.
-- @param object table
-- @return string|nil the atlas, the path or the file's number
local function imageWord(object)
    -- A label says which font object it inherits from.
    --
    -- Added because the colour of text is set at the object, one call for
    -- every label that uses it, and the list of objects to paint was being
    -- guessed. The quest window an NPC opens went white while the quest
    -- panel inside the world map stayed dark - the same text, a different
    -- object - and there was no way to ask which one short of trying names.
    -- Now the probe says it, and the list is written from the answer instead
    -- of from memory.
    if isText(object) then
        local said = nil
        if type(object.GetFontObject) == "function" then
            local ok, font = pcall(object.GetFontObject, object)
            if ok and type(font) == "table" then
                said = stringFrom(font, "GetName")
            end
        end

        local shade = nil
        if type(object.GetTextColor) == "function" then
            local ok, r, g, b = pcall(object.GetTextColor, object)
            r, g, b = ns.Skin.Numeric(r), ns.Skin.Numeric(g),
                ns.Skin.Numeric(b)
            if ok and r and g and b then
                shade = string.format("%.2f %.2f %.2f", r, g, b)
            end
        end

        return "font " .. (said or "unnamed")
            .. (shade and (", ink " .. shade) or "")
    end

    local atlas = stringFrom(object, "GetAtlas")
    if atlas then return "atlas " .. atlas end

    local image = imageOf(object)
    if type(image) == "string" then return image end
    if type(image) == "number" then return "file " .. tostring(image) end

    return nil
end

--- Probe one window: what will darken, what will not and why.
--
-- A pure function over an object: it needs the same methods as the walk, so it
-- is tested with a fake made of tables, without a client.
--
-- The ceiling on records kept.
--
-- It was four hundred, and four hundred is less than one window. The
-- character sheet answers with 1273 textures: the probe printed that number
-- in its tally and quietly kept the first four hundred, so two thirds of the
-- evidence never reached the file - including, every time, the end of the
-- window where the thing being looked for was. A measurement that reports a
-- total it did not keep is the reassuring lie this whole file is written
-- against.
--
-- Four thousand is chosen against the biggest window there is rather than
-- against a feeling. The cost is a larger saved file on the one occasion
-- somebody typed /dark probe, which is a cost worth paying exactly then.
local PROBE_LIMIT = 4000

--- Probe one window: what will darken, what will not and why.
--
-- A pure function over an object: it needs the same methods as the walk, so it
-- is tested with a fake made of tables, without a client.
--
-- @param object table the probe's root
-- @param limit number|nil the ceiling on records (PROBE_LIMIT by default)
-- @return table an array of records { depth, name, kind, image, verdict }
-- @return table cause -> how many times
-- @return number how many records were dropped for want of room
function Darkness.Probe(object, limit)
    local out, tally = {}, {}
    limit = tonumber(limit) or PROBE_LIMIT

    -- Counted rather than left to be inferred from two numbers that do not
    -- match: a reader of the file has to be told what is missing from it.
    local dropped = 0

    local function say(depth, thing, verdict, kind)
        tally[verdict] = (tally[verdict] or 0) + 1
        if #out >= limit then
            dropped = dropped + 1
            return
        end

        -- What we wrote onto this picture and what is on it now.
        --
        -- Without that pair "it did not darken" stays a riddle with two
        -- answers: we did not paint it — or we did and the game painted over us
        -- again. From the outside both look the same, and they can be told apart
        -- only by numbers.
        local wrote, now
        local at = INDEX[thing]
        if at ~= nil and at <= plan.n and plan.tex[at] == thing then
            wrote = string.format("%.2f %.2f %.2f",
                plan.cr[at] or -1, plan.cg[at] or -1, plan.cb[at] or -1)
        end

        if type(thing) == "table" and type(thing.GetVertexColor) == "function"
        then
            local ok, r, g, b = pcall(thing.GetVertexColor, thing)
            if ok then
                r, g, b = ns.Skin.Numeric(r), ns.Skin.Numeric(g),
                    ns.Skin.Numeric(b)
                if r and g and b then
                    now = string.format("%.2f %.2f %.2f", r, g, b)
                end
            end
        end

        out[#out + 1] = {
            depth   = depth,
            name    = stringFrom(thing, "GetName"),
            kind    = kind or objectType(thing),
            image   = imageWord(thing),
            verdict = verdict,
            wrote   = wrote,
            now     = now,
        }
    end

    local function look(thing, depth)
        if type(thing) ~= "table" then return end

        if Darkness.IsOurs(thing) then return say(depth, thing, "ours") end
        if ns.Skin.Forbidden(thing) then
            return say(depth, thing, "forbidden by the engine")
        end
        -- The same question and in the same order as in the walk: protection
        -- in itself is no longer a verdict — what makes it one is the unticked
        -- checkbox. A probe answering "protected by the engine" where the walk
        -- calmly went inside would lie about exactly the thing it is called
        -- for.
        if ns.Skin.Protected(thing) and not Darkness.EnterProtected() then
            return say(depth, thing, "protected by the engine, setting off")
        end

        local kind = objectType(thing)
        if SKIP_TYPES[kind] then
            return say(depth, thing, "type is skipped whole", kind)
        end

        if depth > MAX_DEPTH then
            return say(depth, thing, "deeper than the budget", kind)
        end

        if isTexture(thing) then
            local reason = Darkness.ContentReason(thing)
            return say(depth, thing, reason and ("content: " .. reason)
                or DIMS, kind)
        end

        -- A label. It was absent from the probe entirely, and the probe's
        -- whole promise is to say why a window did not go dark - a promise it
        -- was keeping only about pictures. Text is never darkened; it is
        -- raised, by a different mechanism and for a different reason, and
        -- when a page comes out unreadable the labels are the thing one needs
        -- to see. The line names the font object behind each, which is where
        -- the colour is actually decided.
        if isText(thing) then
            return say(depth, thing, "text, raised not darkened", kind)
        end

        local content = contentRegions(thing)

        if type(thing.GetRegions) == "function" then
            local ok, regions = pcall(gather, thing.GetRegions, thing)
            if ok then
                for i = 1, #regions do
                    local region = regions[i]
                    if content[region] then
                        say(depth, region, "content: owner field")
                    else
                        look(region, depth)
                    end
                end
            end
        end

        if depth < MAX_DEPTH and type(thing.GetChildren) == "function" then
            local ok, children = pcall(gather, thing.GetChildren, thing)
            if ok then
                for i = 1, #children do look(children[i], depth + 1) end
            end
        end
    end

    look(object, 0)

    return out, tally, dropped
end

--- The probe's lines for the chat.
--
-- First the tally by cause — that is the answer in one line — then the records
-- themselves, and only the ones that did NOT darken: a light window is explained
-- by what the walk did not take, while enumerating what it did take would drown
-- the answer.
--
-- A pure function: it is handed what the probe returned.
--
-- @param records table the probe's records
-- @param tally table the tally by cause
-- @param limit number|nil how many records to show (20 by default)
-- @return table an array of lines
function Darkness.ProbeLines(records, tally, limit)
    limit = tonumber(limit) or 20

    local lines = {}

    local names = {}
    for reason in pairs(tally or {}) do names[#names + 1] = reason end
    table.sort(names)

    local counted = {}
    for i = 1, #names do
        counted[#counted + 1] = names[i] .. ": " .. tally[names[i]]
    end
    lines[#lines + 1] = table.concat(counted, ", ")

    local shown = 0
    for i = 1, #(records or {}) do
        local item = records[i]
        if item.verdict ~= DIMS and shown < limit then
            shown = shown + 1
            lines[#lines + 1] = string.format("%d. [%d] %s %s - %s%s",
                shown, item.depth, tostring(item.kind),
                tostring(item.name or "unnamed"),
                item.verdict,
                item.image and (", " .. item.image) or "")
        end
    end

    return lines
end

-- The events on which the game writes the text of a quest's page or a
-- conversation.
--
-- The list is by name because the occasion is by name too: on each of them the
-- game fills the page afresh, while our raising decides by colour — that is, it
-- is obliged to happen AFTER it.
--
-- The names are common to the three client lines served; an event that does not
-- exist in this client the subscription survives silently.
local PAGE_EVENTS = {
    "QUEST_DETAIL",
    "QUEST_PROGRESS",
    "QUEST_COMPLETE",
    "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED",
    "GOSSIP_SHOW",
    "ITEM_TEXT_READY",
    "TRAINER_SHOW",
    "SUPER_TRACKED_QUEST_CHANGED",
}

-- After how many seconds a window is walked again.
--
-- Why the repeat is needed. The game calls ShowUIPanel BEFORE it fills the
-- window: the rows of the reputation list, the sections of the statistics
-- window, the headers in the character sheet — all of those are pools of frames,
-- and they are created after the opening and sometimes after the server's answer
-- too. A walk that happened in the same frame does not see them: they do not yet
-- exist. That is how golden plates in the middle of a dark window came about —
-- the author sent them in from four different windows, and not one of them got
-- into the probe ("/dark probe" on the same window showed only the frame).
--
-- Why one number rather than three. There used to be three — the next frame,
-- half a second, one and a half — and each cost a FULL walk of the window: a
-- return does not ask "has the window changed", or it would not find the rows
-- created deeper. Four walks of the talents window per opening the player sees
-- as the game stopping, and the author saw it: the game stood still when he
-- pressed to open a window.
--
-- Half a second is the place where a walk pays for itself: by that instant the
-- game manages both to build the rows itself and to get the server's answer. Two
-- seconds is the reserve for what the game shows later and with no occasion at
-- all: an expanded tab, a tooltip, a list laid out in parts.
--
-- The second return costs little now: the rule of selection's answers are
-- remembered (VERDICT), and a window that yielded nothing last time is not
-- walked at all (GREW). Everything that arrives later still is caught by the
-- events (REFILL_EVENTS) and by the watcher of repaintings.
--
-- Why this is cheap. A window that has not changed since last time the walk does
-- not walk at all (see SEEN): a repeat over an unchanged window costs one
-- comparison of two numbers.
local LATER = { 0.5, 2 }

--- Come back to a window later and walk it afresh.
--
-- @param frame table
local function sweepLater(frame)
    if type(frame) ~= "table" then return end

    -- A window that yielded nothing new last time is not walked a second
    -- time.
    --
    -- A return costs a full walk of the window — it does not ask "has it
    -- changed", or it would not find the rows created deeper. For the talents
    -- window that is tens of thousands of approaches, and there is nothing to
    -- pay them for at every opening: a window that once gave up everything it
    -- has will give the same tomorrow.
    --
    -- The marker clears itself: the server's answer (REFILL_EVENTS) and a change
    -- of the plan's generation lead into the walk directly, bypassing this
    -- memory.
    if GREW[frame] == false then return end

    local timer = _G.C_Timer
    if type(timer) ~= "table" or type(timer.After) ~= "function" then return end

    for i = 1, #LATER do
        pcall(timer.After, LATER[i], function()
            pcall(Darkness.ApplyToWindow, frame, true)
        end)
    end
end

-- The events on which the game fills a window that is already open.
--
-- Why they are here. The return to a window by the clock (LATER) catches what
-- the game creates itself. But some lists wait for the server's answer, and that
-- answer arrives when it arrives: reputations, skills, statistics, the set of
-- spells. New rows then appear in the open window — and stay untouched, because
-- the walk of that window has already happened.
--
-- The list is by name and short: these are exactly the events on which golden
-- plates were seen with us. An event that does not exist in this client the
-- subscription survives silently.
local REFILL_EVENTS = {
    "UPDATE_FACTION",
    "SKILL_LINES_CHANGED",
    "CHARACTER_POINTS_CHANGED",
    "SPELLS_CHANGED",
    "TRADE_SKILL_UPDATE",
    "PLAYER_EQUIPMENT_CHANGED",
    "UPDATE_INVENTORY_ALERTS",
}

-- Whether the watchers of windows appearing have already been placed. They
-- must not be hung a second time: hooksecurefunc is not removable, and every
-- change of profile would add one more walk per opening of a window.
local watching = false

--- Catch the windows that did not yet exist when the settings were applied.
--
-- Two watchers, and each closes a hole of its own.
--
--   ShowUIPanel — the engine calls it at the opening of any standard window,
--   and other addons that show their windows by the game's rules call it too.
--   That is the "first showing", by which the window is already created in
--   full.
--
--   ADDON_LOADED — part of the interface the game keeps as separate addons and
--   loads on demand (the professions, the auction house, the collections).
--   After such an addon is loaded there are more windows on the screen, and the
--   general pass is obliged to run afresh.
--
--   PLAYER_ENTERING_WORLD — arrives after PLAYER_LOGIN, that is, after the
--   settings have already been applied, and by that moment the interface has
--   been redrawn afresh over us. Without this subscription the darkening laid
--   on at the entry turns out to be wiped off while the slider stays where it
--   was left. From the outside that is indistinguishable from "the setting
--   reset itself": the value is in place and does not touch the screen. The
--   event also arrives on every transition with a loading screen — the
--   redrawing there is the same.
--
-- A repeated pass spoils nothing: a texture's native colour is remembered once,
-- and the second application is computed from that same colour.
--
-- The subscription to an event is placed at every enabling while the hook is
-- placed once. The difference is not one of tidiness but of what gets removed.
-- Disabling a module removes its subscriptions (Core/Registry.lua), and a module
-- the core has put back into service is obliged to subscribe afresh; a
-- hooksecurefunc hook is not removed by anything, and a second one like it would
-- add one more walk per opening of a window.
function Darkness.Watch()
    if not watching then
        watching = true

        if type(hooksecurefunc) == "function"
        and type(_G.ShowUIPanel) == "function" then
            -- The handler goes under a pcall, and that is not superfluous. It
            -- runs inside a call of the game's rather than through the
            -- registry's door, and the core will not catch its error: it would
            -- go to the player as a yellow line over the window just opened.
            -- Nor can it switch itself off from here — there is no registry at
            -- this point.
            if pcall(hooksecurefunc, "ShowUIPanel", function(frame)
                counters.fired_darkness = counters.fired_darkness + 1

                -- Exactly the reference is remembered, and exactly for the
                -- probe's sake ("/darken dark" with no name). The window the
                -- player means when he says "this one did not darken" is the
                -- one he has just opened; asking him for a frame's name means
                -- asking him to know what he is not obliged to know.
                Darkness.lastWindow = frame

                -- We paint at once, in the same frame the game opened the
                -- window in.
                --
                -- Deferring by a frame was tried here and removed. It honestly
                -- took the hitch away but exchanged it for something worse: the
                -- game managed to draw the window in its native look, and the
                -- player saw a flash — the default first, then the dark one. He
                -- puts up with a hitch and not with a flash, and that is right:
                -- a blinking window looks like a failure while a delay of a
                -- couple of milliseconds looks like nothing.
                --
                -- And the price is no longer what it was: a window opened a
                -- second time is not walked at all (see SEEN below), while the
                -- first opening drowns in the loading of the game's own
                -- load-on-demand addon anyway.
                pcall(Darkness.ApplyToWindow, frame)

                -- And twice more later: the game fills a window after it has
                -- shown it (see LATER).
                sweepLater(frame)
            end) then
                if not counted["ShowUIPanel"] then
                    counted["ShowUIPanel"] = true
                    counters.hooked_darkness = counters.hooked_darkness + 1
                end
            end
        end
    end

    -- The watcher of pictures: one for all of them at once (see
    -- watchColor).
    watchColor()

    -- The switching of a tab inside a window that is already open.
    --
    -- ShowUIPanel is not called in the process: the window is open while its
    -- innards change. The reputation and statistics lists the game creates at
    -- exactly that moment, and without this watcher they stayed light — the
    -- author wrote in: it painted in the skills but not in the reputation and
    -- the statistics.
    if type(_G.hooksecurefunc) == "function" and type(ns.Compat) == "table"
        and type(ns.Compat.Resolve) == "function" then
        local ok, names, objects = pcall(ns.Compat.Resolve, "panel-switch")
        if ok and type(names) == "table" and type(objects) == "table" then
            for i = 1, #names do
                if type(objects[i]) == "function" then
                    pcall(_G.hooksecurefunc, names[i], function()
                        sweepLater(Darkness.lastWindow)
                    end)
                end
            end
        end

        -- The bags open past ShowUIPanel entirely, and on their calls their
        -- own windows are walked — by name (the "bag-frames" group).
        --
        -- A full reconnaissance of the interface used to stand here on every
        -- opening of a bag. It found everything, but it cost a pass over tens of
        -- thousands of objects — and opening a bag became the game stopping.
        local bags, bagNames, bagObjects = pcall(ns.Compat.Resolve,
            "bag-toggle")
        if bags and type(bagNames) == "table" and type(bagObjects) == "table"
        then
            for i = 1, #bagNames do
                if type(bagObjects[i]) == "function" then
                    pcall(_G.hooksecurefunc, bagNames[i], function()
                        local ok, _, frames = pcall(ns.Compat.Resolve,
                            "bag-frames")
                        if not ok or type(frames) ~= "table" then return end
                        for j = 1, #frames do
                            sweepLater(frames[j])
                        end
                    end)
                end
            end
        end
    end

    if type(ns.Events) == "table" and type(ns.Events.Subscribe) == "function" then
        -- The events on which the game writes a page's text. Exactly those
        -- rather than "all of them in a row": on each of them what changes is
        -- the thing the page exists for — its letters.
        --
        -- The subscription goes through the core's door, and it survives an
        -- event that does not exist in this client silently: the list is common
        -- to three client lines.
        for _, event in ipairs(PAGE_EVENTS) do
            ns.Events.Subscribe(event, Darkness.name, function()
                Darkness.LiftPages()
                Darkness.LiftPagesLater()
            end)
        end

        -- A window filled in on the server's answer (see REFILL_EVENTS). The
        -- one walked is the one the player opened last: the others are either
        -- closed or will be walked when shown.
        for _, event in ipairs(REFILL_EVENTS) do
            ns.Events.Subscribe(event, Darkness.name, Darkness.RefillSoon)
        end

        ns.Events.Subscribe("ADDON_LOADED", Darkness.name, function()
            -- The interface's composition has changed, so the
            -- reconnaissance has to be done afresh. At the entry into the game
            -- a batch of such events arrives in a row, and the deferral merges
            -- them into one reconnaissance instead of a dozen.
            Darkness.Schedule(true)
        end)

        ns.Events.Subscribe("PLAYER_ENTERING_WORLD", Darkness.name, function()
            -- The interface has been redrawn afresh — lay the darkening over
            -- it. The reconnaissance is afresh too: behind a loading screen the
            -- composition of the windows is a different one.
            Darkness.Schedule(true)
        end)
    end
end

-- Whether this session's count has already been opened. Disabling and
-- re-enabling the module does not count as a session: a "session" here means an
-- entry into the game, and the age of the catalogue's records is measured by
-- that alone.
local started = false

--- Open a session: the incrementing of the counter and the cleaning of the
--- catalogue.
-- A function of its own rather than a line in OnEnable: the cleaning needs a
-- test, and the test needs a way to call it without the game.
function Darkness.StartSession()
    if started then return false end

    local store = Store()
    if not store then return false end

    started = true
    store.session = store.session + 1

    -- The cost is of THIS entry into the world. Kept on disk so that it
    -- survives the logout a bug report is sent after, zeroed here so that
    -- what is read is one login rather than a sum of all of them.
    store.cost.slices, store.cost.total, store.cost.worst = 0, 0, 0
    store.cost.login, store.cost.loginSlices = nil, nil
    Darkness.Forget(store.windows, store.session, FORGET_AFTER, CATALOG_MAX)
    return true
end

--- Enabling the subsystem.
-- Right after OnEnable the registry calls ApplyAll, and the settings will go on
-- by the same single path as at any edit. What is placed here is only the
-- watchers of the windows that do not yet exist at this moment — they start no
-- second path of application but lead into that same ApplySettings.
function Darkness:OnEnable()
    Darkness.StartSession()
    Darkness.Watch()
end

-- The modes' labels and their order in the dropdown. Functions rather than
-- tables: the translation is taken at the moment of display rather than at the
-- moment the file is read.
local function ModeValues()
    local values = {}
    for i = 1, #MODES do
        values[MODES[i].key] = ns.Localize(MODES[i].label)
    end
    return values
end

local MODE_ORDER = {}
for i = 1, #MODES do MODE_ORDER[i] = MODES[i].key end

local function ModeSorting() return MODE_ORDER end

-- The name of an area's settings node. An area's key sometimes carries a
-- hyphen ("actionbar-art"), while the tree's nodes are read by people and end up
-- in search paths: the hyphen is taken out of there and the name stays one
-- word.
-- @param key string the area's key
-- @return string
local function optionKey(key)
    return "mode" .. tostring(key):gsub("%A", "")
end
Darkness.OptionKey = optionKey

-- How many rows of the window list are shown at once.
--
-- The ceiling exists not for the price's sake but for the page's look: fifty
-- checkboxes in a row is exactly the crowded page the author has complained
-- about more than once. Forty rows is as many as can be seen without endless
-- scrolling; the rest is found by the search field, and how many are left beyond
-- the edge is stated in words.
local WINDOW_ROWS = 40

-- What has been typed into the window search field.
--
-- Not a setting and it does not lie in the profile: a query is what the player
-- is doing now rather than what he has chosen. A stored query would meet him at
-- his next entry with a list of two rows and no explanation why.
--
-- The settings' general search (Config/Search.lua) does not have a field of its
-- own that would do for this: that one selects the tree's nodes by name and
-- description, while the rows here are the values of ONE node, and the general
-- search sees not one of them. The second field was created not for the sake of
-- a second mechanism but because what has to be searched is something else.
local windowQuery = ""

--- The catalogue as selected by the current query: the labels and what did not
--- fit.
-- @return table value -> label
-- @return number how many matched beyond what is shown
local function WindowValues()
    local rows, total = Darkness.WindowRows(
        Darkness.Windows(), windowQuery, WINDOW_ROWS)

    local values = {}
    for i = 1, #rows do
        values[rows[i]] = Darkness.WindowLabel(rows[i])
    end
    return values, total - #rows
end

--- Whether the catalogue is empty.
-- @return boolean
local function CatalogEmpty()
    return next(Darkness.Windows()) == nil
end

--- How many matching windows are left beyond the edge of the display.
-- @return number
local function WindowOverflow()
    local _, over = WindowValues()
    return over
end

-- The subsystem's section.
--
-- The section and its main slider are named by different words, and that is a
-- rule rather than chance. The previous attempt reduced them to one word: the
-- section was called "Darkness", the slider "Dimming", and two names for one
-- thing looked like a mistake; both were given the slider's "Dimming". The
-- author read the result and named the real trouble: "dimming" was not a very
-- good name, it was not quite transparent what it did. The word "dimming"
-- describes the technique — the multiplication of a colour — rather than what
-- the technique is performed on and what comes out of it.
--
-- Hence the separation: the section is "Interface Darkness", the slider
-- "Strength". The section names the subject (the interface) and the result (the
-- darkness), the slider names the measure. Neither of the two names retells the
-- other, and together they read as a sentence: how strong the interface's
-- darkness is.
--
-- The word "dim" itself stayed in the descriptions, and that is not an
-- oversight: there it is a verb naming the technique ("how much to dim the
-- artwork") rather than a second name for the thing. One name per thing is a
-- rule about labels rather than a ban on verbs.
--
-- The exceptions ("do not darken this") lie right here, as a third setting,
-- rather than as a separate row in the column of sections. The author's rule: if
-- the ability to switch something off were to be given at all, it had to be on
-- the Darkness page itself rather than moved out into a menu. "Darken everything
-- except this" is one thought, and it has one page.
--
-- NOTE: the Strength description below says a fresh install starts at
-- sixty-four, while Darkness.defaults.amount is eighty (the author's screenshot
-- overrode the earlier figure). The player-facing string is left as it is — the
-- number in it is the author's to choose.
Darkness.options = {
    type = "group",
    name = ns.Localize("Interface Darkness"),
    args = {
        amount = {
            type = "range",
            order = 1,
            width = "full",
            name = ns.Localize("Strength"),
            desc = ns.Localize("How much to dim the interface's own " ..
                "artwork: frames, borders, backgrounds and the trim " ..
                "around them. A fresh install starts at sixty-four, and that " ..
                "is the one thing installing this addon changes on its own: " ..
                "a dark interface addon that looks like the untouched game " ..
                "is not doing what it exists for. Zero is the game's own " ..
                "look and is one drag away; one hundred " ..
                "is as dark as the addon goes, and that is deliberately " ..
                "not black - a frame you cannot make out is not a dimmed " ..
                "frame, it is a missing one. Health and power bars, " ..
                "spell icons, unit portraits, the character model, the " ..
                "map itself keep their own color at every setting. Text " ..
                "keeps its own too, with one exception: the quest and " ..
                "gossip pages are the only place in the game where text is " ..
                "printed dark on light, and there the dark text is lifted " ..
                "to a light tone so the darkened page stays readable. The change applies at once, no interface " ..
                "reload needed; back to zero restores the previous look."),
            min = 0, max = 100, step = 1,
            get = function()
                local settings = Settings()
                return settings and settings.amount or 0
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.amount = value
                -- Not ApplySettings: the slider calls the handler at every
                -- division of a drag, and reconnoitring the interface afresh at
                -- every division was the very freeze.
                Darkness.Schedule()
            end,
        },
        tint = {
            type = "color",
            order = 2,
            -- The default colour sits where the setting does and as a
            -- reference to the defaults table itself rather than as a rewritten
            -- number: otherwise "restore the default" and "what a new player
            -- has" would diverge at the first edit of either. It is read by the
            -- colour swatch's styling (Skin.DefaultColor).
            arg = { default = Darkness.defaults.tint },
            width = "full",
            hasAlpha = false,
            name = ns.Localize("Tint"),
            desc = ns.Localize("The color the interface's artwork is " ..
                "tinted with. White changes nothing and is the default, " ..
                "so a fresh install is dimmed but not tinted. " ..
                "Tinting is the same multiply as dimming, only with the " ..
                "three color channels dimmed by different amounts, which " ..
                "is why it works on its own: a tint with the dimming at " ..
                "zero recolors the frames without darkening them. The " ..
                "same things dimming leaves alone are left alone here."),
            get = function()
                local settings = Settings()
                local tint = (settings and settings.tint)
                    or Darkness.defaults.tint
                return tonumber(tint.r) or 1, tonumber(tint.g) or 1,
                    tonumber(tint.b) or 1
            end,
            set = function(_, r, g, b)
                local settings = Settings()
                if not settings then return end
                settings.tint = settings.tint or {}
                settings.tint.r = r
                settings.tint.g = g
                settings.tint.b = b
                Darkness.Schedule()
            end,
        },
        desaturate = {
            type = "toggle",
            order = 3,
            width = "full",
            name = ns.Localize("Grey Out the Artwork"),
            desc = ns.Localize("Takes the color out of the interface's " ..
                "own artwork instead of only darkening it: the brown of " ..
                "the frames, the gold of the trim, the blue of the bag " ..
                "border all become grey. Dimming still applies on top, and " ..
                "everything dimming leaves alone is left alone here too - " ..
                "spell icons, portraits, the map and all text keep their " ..
                "own color. Off by default: how dark and what color are " ..
                "two questions, and a fresh install answers only the first."),
            get = function()
                local settings = Settings()
                return settings ~= nil and settings.desaturate == true
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.desaturate = value and true or false
                Darkness.Schedule()
            end,
        },
        level = {
            type = "toggle",
            order = 4,
            width = "full",
            name = ns.Localize("Level Out the Bright Artwork"),
            desc = ns.Localize("On by default. Dimming multiplies, and " ..
                "multiplying keeps ratios: artwork the game drew nearly " ..
                "white - the gryphons, the main bar panel, the parchment " ..
                "of a dialog - stays twice as bright as the half-tones " ..
                "around it at every position of the slider, and those " ..
                "pieces glow while the rest of the interface is dark. " ..
                "With this on, anything brighter than a half-tone is " ..
                "brought down to one before the dimming is applied, so it " ..
                "lands where its neighbours land. Hue is kept: a colored " ..
                "texture gets darker, not different."),
            get = function()
                local settings = Settings()
                return settings == nil or settings.level ~= false
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.level = value and true or false
                Darkness.Schedule()
            end,
        },
        gryphons = {
            type = "toggle",
            order = 5,
            width = "full",
            name = ns.Localize("Show the Gryphons"),
            desc = ns.Localize("The two beasts at the ends of the main " ..
                "action bar. They are the loudest piece of artwork the " ..
                "game draws, and a dark interface with them still in place " ..
                "looks like two different interfaces at once. On by " ..
                "default - taking away part of the game is the player's " ..
                "call, not ours. On a client with Edit Mode the bar " ..
                "belongs to it in combat, so a change made mid-fight " ..
                "applies as soon as the fight ends."),
            get = function()
                local settings = Settings()
                return settings == nil or settings.gryphons ~= false
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.gryphons = value and true or false
                Darkness.Schedule(true)
            end,
        },
        protectedWindows = {
            type = "toggle",
            order = 6,
            width = "full",
            name = ns.Localize("Dim the Windows the Engine Protects"),
            desc = ns.Localize("On by default: a few of the game's windows " ..
                "- the talent frame among them - are watched by the " ..
                "engine, and leaving them out means one bright window in a " ..
                "dark interface. The cost is worth knowing. Everything an " ..
                "addon changes on such a window, the engine counts as " ..
                "changed by an addon from then on, and the window's own " ..
                "code runs marked; you do not see that when you drag the " ..
                "slider, you see it later, as \"Interface action failed " ..
                "because of an AddOn\" at the moment you press Apply on " ..
                "your talents. If that happens, switch this off and " ..
                "reload. Buttons stay untouched either way - their click " ..
                "is the protected action itself, and that is where the " ..
                "cost is real."),
            get = function()
                local settings = Settings()
                return settings ~= nil and settings.protectedWindows == true
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end

                settings.protectedWindows = value and true or false

                if settings.protectedWindows then
                    -- The reconnaissance afresh: the composition of what the
                    -- walk takes changed entirely rather than by one texture.
                    -- It may be deferred — the window will simply darken a
                    -- frame later for it.
                    Darkness.Schedule(true)
                    return
                end

                -- An unticked checkbox restores the native look at once, and
                -- the order here is half the matter.
                --
                -- The reconnaissance after it does not go into the protected
                -- windows, their textures do not get into the plan — and they
                -- would be left with the colour written last, that is, dark
                -- until a reload. So first the restoration, then a clean plan,
                -- and only then the new reconnaissance: defer it by a frame and
                -- the very application that happens in between will darken what
                -- was restored again.
                Darkness.RestorePlan()
                Darkness.Invalidate()
                Darkness:ApplySettings()
            end,
        },
        areaHeader = {
            type = "header",
            order = 7,
            name = ns.Localize("Areas"),
        },
        areaNote = {
            type = "description",
            order = 8,
            width = "full",
            name = ns.Localize("Leave every area on \"Overall " ..
                "Strength\" and the slider alone decides how dark the " ..
                "whole interface is. Give one area a strength of its own " ..
                "and it stops listening to the slider and keeps that " ..
                "strength wherever the slider goes."),
        },


        -- Individual windows. The same question as above but at a different
        -- step: a group is a coarse switch ("every nameplate", "all the bars'
        -- framing"), a window an exact one. Neither of the two overrides the
        -- other silently: the general pass does not take the named groups'
        -- frames at all (the covered set), so a window and a group never argue
        -- over one texture. The only one that can argue is "Other Windows" — a
        -- coarse switch for that very same pass — and while it is ticked the
        -- window list goes out: it is visible that it is the one in charge
        -- now.
        otherNote = {
            type = "description",
            order = 39,
            width = "full",
            name = ns.Localize("\"Other Windows\" above means every " ..
                "window not named here, including ones later patches add " ..
                "and ones other addons build in the game's style: " ..
                "darkening finds them by walking the interface, not from " ..
                "a list of names. Single windows out of that sweep are " ..
                "handled one at a time below."),
        },
        windowHeader = {
            type = "header",
            order = 40,
            name = ns.Localize("Individual Windows"),
        },
        windowSearch = {
            type = "input",
            order = 41,
            width = "full",
            name = ns.Localize("Find a Window"),
            desc = ns.Localize("Narrows the list below to windows whose " ..
                "name contains what you type. The list is not written by " ..
                "hand: it is the windows dimming has actually reached, so " ..
                "it grows as you open the game's own windows and is " ..
                "remembered between sessions."),
            get = function() return windowQuery end,
            set = function(_, value)
                windowQuery = type(value) == "string" and value or ""
            end,
        },
        windowEmpty = {
            type = "description",
            order = 42,
            width = "full",
            hidden = function() return not CatalogEmpty() end,
            name = ns.Localize("Nothing here yet. This list fills itself " ..
                "as you open the game's windows - it is built from what " ..
                "dimming actually touched, and a fresh install starts " ..
                "empty rather than guessing at names. What appears here " ..
                "is remembered between sessions, so it is waiting for you " ..
                "the next time you log in."),
        },
        windowExclude = {
            type = "multiselect",
            order = 43,
            width = "full",
            name = ns.Localize("Windows Seen So Far"),
            desc = ns.Localize("Checked windows keep the game's own look, " ..
                "dimming and tint both, and the change happens at once, " ..
                "no interface reload needed. The list is built from what " ..
                "dimming actually reached rather than from names written " ..
                "in advance, so a window joins it the first time you open " ..
                "it and stays there between sessions. A window this game " ..
                "no longer has keeps its place for a while and is then " ..
                "dropped from the list, but your choice for it is kept: " ..
                "should the window ever come back, it comes back the way " ..
                "you left it. The groups above are the same switch, only " ..
                "coarser - while \"Other Windows\" is checked it already " ..
                "keeps every one of these native, and this list is greyed " ..
                "out to say so."),
            hidden = CatalogEmpty,
            disabled = function()
                local settings = Settings()
                return settings ~= nil
                    and Darkness.ModeOf(settings.mode, "window") == "native"
            end,
            values = function() return (WindowValues()) end,
            get = function(_, key)
                local settings = Settings()
                return settings ~= nil and settings.excludeWindow ~= nil
                    and settings.excludeWindow[key] == true
            end,
            set = function(_, key, value)
                local settings = Settings()
                if not settings then return end
                settings.excludeWindow = settings.excludeWindow or {}
                -- A false rather than a nil, for the same reason as the groups
                -- above.
                settings.excludeWindow[key] = value and true or false
                Darkness.Schedule()
            end,
        },
        windowMore = {
            type = "description",
            order = 44,
            width = "full",
            hidden = function() return WindowOverflow() <= 0 end,
            name = function()
                return string.format(ns.Localize("%d more windows are not " ..
                    "shown. Type in the box above to narrow the list."),
                    WindowOverflow())
            end,
        },
    },
}

-- The choice of mode for every area.
--
-- The nodes are assembled from the same GROUPS list the darkening's own pass
-- goes by: the list of areas and the list of choices in the settings window are
-- obliged to be one list. A second enumeration rewritten beside it would diverge
-- from the first when an area was added, and it would diverge silently — the
-- area would be darkened while there would be nothing to govern it with.
--
-- One dropdown per area rather than a dropdown plus a "do not touch" checkbox.
-- The author has already complained about a crowded page, and two controls about
-- one area are not only twice as many rows but also the question "whose word
-- carries", which the player would have to answer himself. "Leave it as it is"
-- is as much an answer to the question "how dark" as any other, and it lives in
-- the same list.
for i = 1, #GROUPS do
    local key = GROUPS[i].key
    local label = GROUPS[i].label

    Darkness.options.args[optionKey(key)] = {
        type = "select",
        order = 8 + i * 2,
        width = "full",
        name = function() return ns.Localize(label) end,
        -- The description is one for every area, and that is not laziness:
        -- their question is identical, and different words about the same thing
        -- would make one read eleven times to be sure there is no difference.
        desc = ns.Localize("How dark this area is. \"Overall " ..
            "Strength\" means the strength slider on this page decides, " ..
            "and one drag of it moves this area along with everything " ..
            "else. Any named strength here wins over the slider and stays " ..
            "put. \"Game's Own Look\" leaves this area exactly as the " ..
            "game draws it - no darkening and no tint."),
        values = ModeValues,
        sorting = ModeSorting,
        get = function()
            local settings = Settings()
            return Darkness.ModeOf(settings and settings.mode, key)
        end,
        set = function(_, value)
            local settings = Settings()
            if not settings then return end
            settings.mode = settings.mode or {}
            settings.mode[key] = value
            -- The list may have changed to "custom colour", and then a swatch
            -- is obliged to appear beside it: the window asks hidden at a
            -- redraw rather than constantly.
            Darkness.Schedule()
            if type(ns.NotifyConfigChanged) == "function" then
                pcall(ns.NotifyConfigChanged)
            end
        end,
    }

    -- The swatch of an area's custom colour.
    --
    -- It stands beside the step and is visible only at the "custom colour"
    -- step: a swatch at any other step would promise a choice that does not
    -- exist — the colour would not be applied and the player would not
    -- understand why.
    --
    -- White by default, and that is not "none": a white multiplier changes
    -- nothing, that is, at the first switch the area looks as it does in the
    -- game, and from there the player leads its colour away from the native
    -- look rather than from black.
    Darkness.options.args[optionKey(key) .. "color"] = {
        type = "color",
        order = 9 + i * 2,
        width = "full",
        hasAlpha = false,
        name = function()
            return ns.Localize(label) .. ": " .. ns.Localize("Custom Color")
        end,
        desc = ns.Localize("The color this area is painted with. It is a " ..
            "multiply, like dimming is: white changes nothing, a darker " ..
            "color darkens, and a colored one tints. The same things " ..
            "dimming leaves alone are left alone here."),
        hidden = function()
            local settings = Settings()
            return Darkness.ModeOf(settings and settings.mode, key) ~= "custom"
        end,
        get = function()
            local settings = Settings()
            local colors = settings and settings.color
            local color = type(colors) == "table" and colors[key] or nil
            if type(color) ~= "table" then return 1, 1, 1 end
            return tonumber(color.r) or 1, tonumber(color.g) or 1,
                tonumber(color.b) or 1
        end,
        set = function(_, r, g, b)
            local settings = Settings()
            if not settings then return end
            settings.color = settings.color or {}
            settings.color[key] = { r = r, g = g, b = b }
            Darkness.Schedule()
        end,
    }
end

--============================================================================
-- The settings page, declared as data
--============================================================================

-- Declared here, beside the darkening's code, rather than in a shared file of
-- pages. A setting and what it configures are edited together; split across
-- files, they are edited in two places, and one of the two will be forgotten one
-- day.
--
-- The old AceConfig tree (Darkness.options above) stays for now: the window
-- works on it until the last step of the move, and there will be no "either this
-- or that" switch — an empty window is worse than somebody else's.

if type(ns.Schema) == "table" then
    local Schema = ns.Schema
    local PAGE = "darkness"

    Schema.Page(PAGE, {
        title = "Interface Darkness",
        order = 3,
        section = "darkness",
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Strength",
        path = { "amount" },
        min = 0, max = 100, step = 1,
        -- Not "darkness" but a record of its own: the slider calls the
        -- handler at every division of a drag, and a full reconnaissance of the
        -- interface at every division was the very freeze the author complained
        -- about.
        apply = "none",
        hint = "How much to dim the interface's own artwork: frames, "
            .. "borders, backgrounds and the trim around them. Zero is the "
            .. "game's own look and is one drag away; one hundred is as dark "
            .. "as the addon goes, and that is deliberately not black - a "
            .. "frame you cannot make out is not a dimmed frame, it is a "
            .. "missing one.",
        set = function(value)
            local settings = Settings()
            if not settings then return end
            settings.amount = value
            Darkness.Schedule()
        end,
        get = function()
            local settings = Settings()
            return settings and settings.amount or 0
        end,
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Grey Out the Artwork",
        path = { "desaturate" },
        apply = "darkness",
        hint = "Drain the colour out of the interface's own artwork as well "
            .. "as darkening it. Icons, bars, portraits and the map keep "
            .. "their colour either way.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Level Out the Bright Artwork",
        path = { "level" },
        apply = "darkness",
        hint = "Bring the brightest pieces of artwork down to the same "
            .. "ceiling as the rest, so nothing stands out by being lighter "
            .. "than everything around it.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show the Gryphons",
        path = { "gryphons" },
        apply = "darkness",
        hint = "The two end caps of the main action bar. Hiding them is the "
            .. "one thing here that removes a piece of the game rather than "
            .. "darkening it.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Dim the Windows the Engine Protects",
        path = { "protectedWindows" },
        apply = "darkness",
        hint = "Some windows are protected by the engine, and touching them "
            .. "can make the game refuse an action later. Off leaves them "
            .. "exactly as the game draws them.",
    })

    Schema.Add(PAGE, { kind = "header", label = "Areas" })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "Leave every area on \"Overall Strength\" and the slider "
            .. "alone decides how dark the whole interface is. Give one area "
            .. "a strength of its own and it stops listening to the slider "
            .. "and keeps that strength wherever the slider goes.",
    })

    -- The areas are taken from the same enumeration the darkening goes by. A
    -- second enumeration rewritten beside it would diverge from the first when
    -- an area was added, and it would diverge silently: the area would be
    -- darkened while there would be nothing to govern it with.
    for i = 1, #GROUPS do
        local key = GROUPS[i].key
        local label = GROUPS[i].label

        Schema.Add(PAGE, {
            kind = "select",
            label = label,
            apply = "darkness",
            -- The description is one for every area, and that is not
            -- laziness: their question is identical, and different words about
            -- the same thing would make one read eleven times to be sure there
            -- is no difference.
            hint = "How dark this area is. \"Overall Strength\" means the "
                .. "strength slider on this page decides. Any named strength "
                .. "here wins over the slider and stays put.",
            values = ModeValues,
            get = function()
                local settings = Settings()
                return Darkness.ModeOf(settings and settings.mode, key)
            end,
            set = function(value)
                local settings = Settings()
                if not settings then return end
                settings.mode = settings.mode or {}
                settings.mode[key] = value
            end,
        })
    end
end

ns.Registry:Register(Darkness)
