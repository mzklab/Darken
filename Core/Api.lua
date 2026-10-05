local ADDON, ns = ...

-- The public layer for modules living in separate folders.
--
-- A separate addon folder does not see our namespace: the client gives each
-- addon its own. So the core exposes one global object — the only one besides
-- the saved variable DarkenDB — and the whole conversation with foreign code
-- goes through it.
--
-- The object's name matches the core folder's name and what a module writes in
-- its own "## Dependencies: Darken" line. That is deliberate: a module's
-- author should not have to remember two different words for one and the same
-- thing.
--
-- The surface is kept small on purpose. Every function here is a promise that
-- cannot be broken after the first release: people we cannot reach by editing
-- our own code depend on it from outside. The core's insides stay free
-- meanwhile — that is the point of a thin layer over the registry.
--
-- The surface in full:
--   Darken.API_VERSION              — the contract's version, a number
--   Darken.API_MIN_VERSION          — the oldest version accepted, a number
--   Darken:Supports(version)        — whether a version is supported
--   Darken:GetFlavor()              — the client's flavour in one word
--   Darken:GetSkin()                — palette, spacing, drawing and states
--   Darken:GetMedia()               — the addon's bar textures and fonts
--   Darken:GetAuraFilter()          — the shared aura filter by spell list
--   Darken:GetCasefold()            — case: folding and capitals
--   Darken:GetFormat()              — numbers: rounding, abbreviating, per cent
--   Darken:GetVersion()             — the addon's version as a string
--   Darken:GetFrameNames(group)     — the game's frame names by group
--   Darken:GetGameFunction(g, s)    — a group's game function of the shape asked
--   Darken:RegisterModule(t)        — registration; returns the module's handle
-- and on the handle registration returned:
--   handle:GetSettings(scope)        — its own table ("profile"/"global"/"char")
--   handle:GetFrame(key)             — an object the core or a neighbour owns
--   handle:OnRepaint(key, fn)        — subscribe to that object's repaint
--   handle:Publish(key, frame)       — expose its own object to the neighbours
--   handle:RegisterEvent(event, fn)  — subscribe to a game event
--   handle:UnregisterEvent(event)    — remove a subscription
--   handle:InCombat()                — whether combat is in progress now
--   handle:Secure(object, key, fn)   — work on a protected object
--   handle:RegisterStrings(loc, t)   — declare its own strings in language loc
--   handle:Localize(key)             — translate its own string
--   handle:RegisterCommand(word, fn) — claim a slash command
--   handle:Replaces(subsystem)       — replace a core subsystem with itself
--   handle:Releases(subsystem)       — give the subsystem back to the core
--   handle:Migrate(data, m, target)  — bring its saved data to the present form
--   handle:Own(object, owned)        — mark its own object on a foreign frame
--   handle:Counters()                — the table of work-done counters
--   handle:Refresh()                 — apply the whole addon's settings
--   handle:Apply()                   — apply only its own settings
--   handle:IsEnabled()               — whether the module works right now
--   handle:Print(text)               — a line in chat on the module's behalf
--
-- There is nothing else public. A module gets no access to the database as a
-- whole, to the registry, to other modules' settings sections or to the core's
-- internal tables — not out of distrust but because every such door would
-- become a promise forever.

-- The contract's version. It goes up on an incompatible change to the public
-- surface; API_MIN_VERSION is the oldest version this core still accepts. Both
-- numbers are public and documented in docs/module-api.md: a module wishing to
-- work with several generations of the core reads the whole range rather than
-- guessing the lower bound.
--
-- Version 2 added Darken:GetSkin() — access to the core's palette and spacing
-- scale. An addition breaks nothing, so the lower bound stayed at one: a
-- module written for version 1 works with this core as it did, while whoever
-- needs the styling need only ask Darken:Supports(2).
--
-- Version 3 closed what the contract's first real consumer found (the bags
-- module): work deferred to the end of combat, its own translated strings,
-- subscribing to game events, the game's frame names by group. The core could
-- already do all of that and did not expose it, so every module wrote its own
-- — each a little differently. Nothing was removed or renamed, and the lower
-- bound stayed at one: a module for version 1 works with this core as it did.
--
-- Version 4 closed what the contract's third consumer found (the nameplate
-- engine): our bar textures and our fonts, a slash command's word and the
-- addon's own version. The core could do the first two and did not expose them
-- — a module drawing its own bar either wrote the path to our file out as a
-- string or went without our look entirely. Modules took a command's word
-- from the engine directly, and two modules with one word displaced each other
-- silently. handle:Replaces landed here too — the only way to say "I am
-- replacing a core subsystem" out loud instead of two owners painting one
-- frame. Nothing was removed or renamed, and the lower bound stayed at one.
--
-- How the contract grows without breaking older modules. Every new version
-- adds methods onto the handle, and the handle is the very place the contract
-- tells a module to keep its state in. Taking a name away from everybody at
-- once would mean breaking somebody's addon on a line they wrote long before
-- that name existed — and the promise "a module for version 1 works as it
-- did" would break with every version. So the core's names are locked by the
-- version the module declared: see HANDLE_FIELD_VERSIONS below. A module calls
-- the whole surface while giving the core only those names that existed in its
-- version. A method added in version 5 will not take a name from any of
-- today's modules — and that is tested (tests/test_apiversion.lua).
--
-- Version 5 closed what the contract's fourth consumer found (the item
-- database): bringing its own saved data to the present form. A module's
-- settings live in the core's database, but the form of the data a module
-- writes into it belongs to the module, and that form will have to change —
-- a player who installed the module a year ago has in SavedVariables what the
-- module wrote a year ago. The core has been able to do this for its own
-- settings since the very first schema (ns.MigrateProfile, Core/Defaults.lua)
-- and did not expose it — that is, every module that reached saved data would
-- write a second answer to this question, and those answers would diverge
-- silently. The same function was exposed, not a similar one beside it.
-- Nothing was removed or renamed, and the lower bound stayed at one.
--
-- Version 6 added a third storage scope — "char", one per character. The
-- same item database found it: the setting "record this character's bags" lay
-- in the profile, that is, across the whole account at once, and switched off
-- on one alt it switched the recording off for all. AceDB has had the char,
-- realm and class scopes from the start (Core/Init.lua creates the database in
-- one call), and working around them with a key inside "global" would have
-- meant writing a second "one per character" mechanism beside a living first.
--
-- One scope was taken rather than all four: nobody needs realm and class yet,
-- and every scope in the contract is a promise forever. Nothing was removed or
-- renamed: a module written for version 5 notices nothing, and the lower
-- bound stayed at one.
--
-- Version 7 exposed the shared aura filter — Darken:GetAuraFilter(). It was
-- not we who found it: two modules wrote it separately and arrived at one and
-- the same thing, down to the mode words and the string.lower limit. While
-- there are two copies, a change in one silently leaves the other as it was,
-- and one and the same typed list starts meaning different things in two
-- windows. A module may not look into another's folder — so there is one
-- shared place, and it is the core.
--
-- Exactly what matched in both was exposed: parsing the typed list, the name
-- key and the list's verdict. Nothing that differed between them was exposed:
-- the cap on the number of icons stayed with the nameplates, the "only mine"
-- scope with the compact auras. A shared function with a flag per caller
-- would not be one rule but two copies in one table.
--
-- Nothing was removed or renamed: a module written for version 6 notices
-- nothing, and the lower bound stayed at one.
--
-- Version 8 made reversible what had been one-way since version 4:
-- handle:Replaces stood a core subsystem aside and did not give it back until
-- the interface was reloaded. A module that stopped drawing left the player
-- with the game's own bags minus our styling and with one line in chat
-- instead of a restoration — that is, "switched it off and things did not go
-- back". The bags specification demands the opposite outright: closing the
-- module brings the standard bags back without a reload.
--
-- One name was added — handle:Releases(subsystem) — and only the module that
-- took a subsystem may give it back: otherwise one module would resurrect a
-- subsystem another is replacing right now. The return is not the clearing of
-- a flag: the subsystem goes through the same path it takes at login
-- (OnEnable if it never happened, then ApplySettings), because "give the
-- styling back" means to style rather than to permit styling at some later
-- time.
--
-- Nothing was removed or renamed: a module written for version 7 notices
-- nothing, and the lower bound stayed at one.
--
-- Version 9 exposed case folding — Darken:GetCasefold(). As with the aura
-- filter, it was not we who found it: three subsystems hit one and the same
-- limit separately — the bags' search box, the item database's query language
-- and the shared aura filter — and all three wrote it down out loud as a
-- caveat about string.lower. The caveat was honest, but what it described was
-- a silent breakage: a player on a Russian client types a word in lower case,
-- does not find it capitalised and reads the empty list as "I do not have
-- one". Nobody sees this break — they simply fail to find their item.
--
-- string.lower in Lua 5.1 folds byte by byte and knows only ASCII, while the
-- game hands over names in UTF-8, where a Cyrillic letter takes two bytes. One
-- mapping table for the whole addon was exposed (Core/Casefold.lua): the whole
-- of Cyrillic, the Ukrainian Ґ and the Latin letters with diacritics — that
-- is, the letters of the clients the game shipped in. The whole of Unicode was
-- deliberately not taken, and neither was the Turkish İ: it would fold the
-- Latin I into the wrong place.
--
-- Folding is for comparison and only that: what is stored is still what the
-- game gave and what the player typed.
--
-- Nothing was removed or renamed: a module written for version 8 notices
-- nothing, and the lower bound stayed at one.
--
-- Version 10 added a third function to that same Darken:GetCasefold() —
-- Upper, capitals for display. Folding is for comparison, raising for
-- display: the work differs while the knowledge is one — which letters belong
-- to which alphabet and where they sit. It had been written down twice, and
-- the second copy (the settings window's headings in the old styling layer)
-- knew the Russian а-я and ё but knew neither the Ukrainian і, ї, є, ґ nor the
-- Latin letters with diacritics: "Профілі" was displayed as "ПРОФІЛІ" — every
-- letter capital except the author's own. That is exactly how copies diverge:
-- not by breaking but by a letter the copy never had.
--
-- It was exposed because a module draws a window of its own: GetSkin already
-- gives it the colour, the inset, the border and the label — everything the
-- core draws a heading with except the capitals. Without the door a module's
-- author would write a third copy of the same arithmetic, and it would
-- diverge on the same letter.
--
-- Nothing was removed or renamed: a module written for version 9 notices
-- nothing, and the lower bound stayed at one. Version 10 added no handle
-- names — the new name lives on the core's surface rather than on the handle,
-- and HANDLE_FIELD_VERSIONS did not change.
--
-- Version 11 exposed the dictionary of states — RowColors, ButtonColors and
-- FieldState on that same Darken:GetSkin() — and a fifth font category,
-- windowtext.
--
-- They were found by a review of nine modules at once rather than by one
-- consumer. Before it not one module's window could do selection, hover,
-- focus or disabling: a chosen look in the bags was marked only by the
-- label's colour, the info panel's menu row by nothing, the item database's
-- result row by nothing. The cause was not nine authors but this file: the
-- styling pass declared the dictionary once for the whole settings window
-- (Core/Skin.lua), while GetSkin exposed Color, Colors, Metrics, Backdrop,
-- Outline and Text — and nothing more. A module could repeat the fill on its
-- own side, and it would cost exactly what the door is placed to prevent: two
-- colour-and-opacity pairs rewritten into nine folders. The project had
-- already reconciled those same two quantities from copies once — by that
-- very styling pass.
--
-- The very functions written for the settings window were exposed rather than
-- similar ones beside them: they are pure (a colour name in, colour names
-- out), they expose nothing we own and they are already tested
-- (tests/test_skinfocus.lua). The state words — selected, hover, focus,
-- disabled, normal, pressed — and the button kind words — normal, primary,
-- select — are part of the contract: new ones may appear, existing ones will
-- not be renamed.
--
-- The fifth font category closes the neighbouring hole of the same review.
-- The four former categories — unit names, bar values, hotkeys, combat text —
-- are every one of them about text over the world, and that is why the bags
-- window and the item database window did not call the fonts door at all: the
-- player's font choice reached the nameplates and did not reach our own
-- windows. Substituting unitname there would tie a window's header to unit
-- names.
--
-- The new category's boundary is drawn exactly where the fonts subsystem drew
-- it: by a frame's purpose rather than by its authorship. A window the addon
-- draws instead of the game's interface is a subject of configuration, and
-- windowtext is about it. The settings window is the tool the player moves
-- that setting with, and it is out of scope: a window that rebuilds itself
-- under one's hands is unmanageable. No second check was introduced for this
-- — a target is still accepted by one function of the fonts subsystem, and
-- windowtext passes through it like everything else.
--
-- Nothing was removed or renamed: a module written for version 10 notices
-- nothing, and the lower bound stayed at one. Version 11, like the tenth,
-- added no handle names — the new names live on the styling surface rather
-- than on the handle, and HANDLE_FIELD_VERSIONS did not change.
--
-- Version 12 exposed the numbers — Darken:GetFormat() with Abbreviate and
-- Percent — and added Metrics.edge to the spacing scale.
--
-- A player reads a number more often than anything else on screen, and a
-- divergence in one is noticed instantly while being caught only by eye. And
-- there was a divergence: the health bar wrote "12.4k", the info panel's cell
-- below it "12k", and 999,999 became "1.0m" for one and "1000.0k" for the
-- other. The cause was not two authors but this file: GetSkin exposed colour
-- and spacing, GetMedia a texture and a font, GetCasefold the case, while the
-- rules for writing a number the contract did not expose at all. So the
-- abbreviation was written twice — by the bar texts and by the panel's cells —
-- and the review of the world family could only reconcile it by copying: a
-- module in a separate folder has no other way.
--
-- The very table our own code calls was exposed (ns.Format, Core/Format.lua)
-- rather than a similar one beside it: a second record of the thresholds
-- would diverge from the first exactly as those two did — silently and on one
-- digit. No copies remain after this door, and that is verified by function
-- identity rather than by comparing answers: copies give identical answers
-- too, until one of them is edited.
--
-- The health bar's rule was taken to the letter: it is the one the player sees
-- every fight. The one place where the reconciliation did not take it is the
-- rounding of a percentage on negative values: the bar text computed
-- math.floor(v + 0.5), which breaks the identity Percent(-c, m) =
-- -Percent(c, m), while the panel handled the sign explicitly. The explicit
-- handling was taken; negative percentages do not occur on live values, and on
-- screen this moves nothing.
--
-- Metrics.edge (2) is the same fifth place, only in the scale: "how far to
-- move a label from an edge so that it does not merge with the border" had
-- been written as four literals in three subsystems, because between hair (1)
-- and rail (4) the scale was empty.
--
-- Nothing was removed or renamed: a module written for version 11 notices
-- nothing, and the lower bound stayed at one. Version 12, like the two before
-- it, added no handle names — the new name lives on the core's surface rather
-- than on the handle, and HANDLE_FIELD_VERSIONS did not change.
--
-- Version 13 added rounding to the numbers: Darken:GetFormat().Round.
--
-- The tail of the same work. Version 12 exposed the abbreviation and the
-- percentages, and four records of the rule came together into one — all but
-- one. The info panel kept a body of the rounding of its own "for the frame
-- rate's sake": 59.6 is written in its window as "60 fps", while a plain
-- "round to an integer" was not on the surface. One remaining copy is not a
-- detail but the beginning of the next divergence: the project has found one
-- piece of knowledge written twice five times already, and every time the
-- second record looked harmless right up to the day the first was edited.
--
-- One name, not two. "Symmetric about zero" and "a half moves away from zero"
-- are one rule named from two sides: the symmetry Round(-x) = -Round(x) IS the
-- requirement to move a half away from zero. The proof lay in the tree itself
-- — the panel's body matched the core's line for line.
--
-- The rule "half towards the larger number" (math.floor(v + 0.5)) exists in
-- the addon too, and it is different rather than wrong: grid snapping
-- (Modules/Movers.lua) chose it deliberately so that the nodes attract
-- equally on both sides of zero. It is not exposed and stayed where that
-- decision is made — exactly as clamping a percentage at zero stayed with the
-- panel's cell. A second name on the surface would promise a choice a
-- module's author does not have: they need a share in per cent and a whole
-- number in a label, not a grid.
--
-- Nothing was removed or renamed: a module written for version 12 notices
-- nothing, and the lower bound stayed at one. Version 13 added no handle
-- names — the new name lives in the table GetFormat returns rather than on
-- the handle, and HANDLE_FIELD_VERSIONS did not change.
-- Version 14 exposed the mover: handle:RegisterElement and
-- handle:MoveElement.
--
-- The compact auras module found this door, and found it twice. The first time
-- through its own grid: it was positioned by two sliders, horizontal and
-- vertical, as numbers from a corner of the screen. Meanwhile the player
-- already places everything else with the mover — unit frames, bars, cast bars
-- — by the same handles, the same grid, the same snapping. Two ways to place
-- one thing on screen are not a choice but a discrepancy: a slider knows
-- nothing of the grid, of snapping or of "put it back", and repeating a
-- position on a second character with it means rewriting the numbers by hand.
--
-- The second time through the request "move that aura over there", which the
-- module refused, and refused rightly: a place in a grid is an index rather
-- than a property of a spell. The real answer to it is a place of the grid's
-- own, and that answer is here too.
--
-- Why this was not done earlier: the mover is a core subsystem
-- (Modules/Movers.lua), and a module may not write into the core. Hence a
-- door, and a narrow one on purpose.
--
-- The module hands over three things: its own frame, a label for the overlay,
-- and a default — an anchor point and two numbers. The core takes on
-- everything else: the element's name in the saved file, the handle with its
-- label, the grid, the snapping, recording the position, combat, applying it
-- on every occasion, and resetting. The module sees neither the table of
-- positions, nor the overlay, nor anybody else's elements.
--
-- A module's element's position lies where every other element's position
-- lies — in the core's profile rather than in the module's settings.
-- Otherwise "reset all elements" would stop meaning "all", and a module
-- switched off would carry the screen's layout away with it. A module
-- switched off loses only its handle: the record about its element stays
-- untouched by exactly the rule that keeps the record about a frame this
-- client does not have.
--
-- MoveElement is the other half of the same door, and without it the first
-- half would be one-way: a module whose player has already placed its block
-- with numbers has to carry that position over to the mover itself — through
-- handle:Migrate — and there is nowhere else to put it but this call.
--
-- Two handle names were added, and both are locked by version: a module
-- written for version 13 notices nothing, and the lower bound stayed at
-- one.
--
-- Version 15 exposed the "this is ours" marker: handle:Own.
--
-- The occasion is the mover's — a living module found the door. The dimming
-- subsystem walks foreign frames in depth and paints all of their chrome
-- textures, deciding by a texture's appearance. An object of our own, placed
-- by a module onto a foreign frame, is indistinguishable to that walk from
-- the game's own artwork: the dimming remembers our colour as the native one,
-- we recolour the object by our own rule, and the next movement of the slider
-- returns it to what was remembered — that is, to somebody else's colour.
-- Neither an error nor a line in chat: the colour is simply wrong.
--
-- The compact auras module worked around this by creating the border textures
-- on its own frame and merely anchoring them to the foreign icon. The
-- workaround is honest and remains correct; but it is an answer to the
-- absence of a door rather than the only way to decorate a foreign frame. A
-- module that needs a texture on the foreign object itself had nothing to do
-- but hope.
--
-- The door is narrow on purpose: it does not say "do not touch this frame"
-- but "this object is ours". The dimming already knows how to skip what is
-- ours — by the same Darkness.IsOurs question it skips the addon's settings
-- window with; the marker merely adds a fourth criterion to it, and no second
-- "do not touch" mechanism is created in the core. The other side must exist:
-- handle:Own(object, false) clears the marker, because a module that gave a
-- foreign frame back to the game must leave nothing of its own on it.
--
-- One handle name was added, and it is locked by version: a module written
-- for version 14 notices nothing, and the lower bound stayed at one.
--
-- Version 16 added not one name. It corrected the shape of three things
-- everybody stepped on.
--
-- The first and the chief one — when a module's handlers are called. The core
-- used to call OnEnable and ApplySettings from inside registration itself,
-- that is, before RegisterModule had returned the handle. An author wrote the
-- ordinary "local module = Darken:RegisterModule{...}" and used the `module`
-- variable from their own handlers — and at that moment it did not exist yet.
-- The module failed on its own first line and was switched off without
-- drawing anything. All nine modules of the repository stepped on this, and
-- the exemplary tenth too: each carries a hand-written "module = module or
-- self" in that place. Nine identical workarounds are not nine authors'
-- mistakes but one mistake of the door: what people write without thinking
-- has to be the correct thing. Now a late module's enabling moves one frame
-- ahead (EnableLater), and a naive module simply works. The workarounds stay
-- correct — self arrives in a handler as it did — but have stopped being
-- necessary.
--
-- The second — a mover element's label. It used to be a translation key the
-- module never passed through Localize: the core translated it. Which means
-- any translation-completeness check that collects keys from Localize call
-- sites did not see that label, and a forgotten translation reached the
-- player silently. Since version 16 the label is already translated text: the
-- module passes it through its own translation, and the key becomes visible
-- to any analysis of the source. A module declaring a lower version hands
-- over a key as it did, and the core translates it as it did.
--
-- The third — an alarm colour. The palette had neither red nor yellow, and a
-- watchdog module (durability, health, charges) could not say "bad" except by
-- inventing a colour from numbers. The palette now has warn, and its scope is
-- narrow — see Core/Skin.lua and section 7 of the contract.
--
-- Nothing was removed or renamed, no handle names were added, and the lower
-- bound stayed at one.
-- Version 17 exposed the tally of work done: handle:Counters().
--
-- The occasion is every previous one's — a question a live client has nothing
-- to answer with. The client report (Core/Report.lua) says what exists in the
-- client; the tally (Core/Tally.lua) says what the addon managed to do with
-- it. The second is usually the one needed: "the nameplate group found twelve
-- names" and "the nameplate engine attached to none of them" are both true,
-- and only the second explains anything. The nameplate engine is a module,
-- and without this door the report's most important number would be
-- unreachable.
--
-- The table of numbers itself is exposed rather than an "add one" function.
-- That is a decision about cost, and the only possible one: a counter sits on
-- the path every aura of every update and every nameplate on screen passes
-- through. A function call in such a position shows up in the whole-cost
-- measurement, which has ceilings of its own
-- (tests/test_wholecost.lua), while an integer addition through a local
-- reference taken once does not. So a module takes the table once while its
-- file is read and writes into it itself from then on.
--
-- The dictionary of keys belongs to the core and is documented in
-- Core/Tally.lua: the key names are part of the contract on the same footing
-- as the aura filter's mode words. Adding is allowed, renaming is not. A key
-- the core does not know is not lost: it enters the report as a section of
-- its own, because a number that vanished can be neither read nor fixed.
--
-- A module must claim its own counter itself, with a line like
-- "c.plates = c.plates or 0" while its file is read. The report reads an
-- unclaimed counter as "this subsystem is not in the build" and a claimed
-- zero as "the subsystem is there and did nothing", and the difference
-- between those two answers is everything the tally was written for.
--
-- One handle name was added, and it is locked by version: a module written
-- for version 16 notices nothing, and the lower bound stayed at one.
--
-- Version 18 exposed the objects alongside the names: Api:GetFrameNames now
-- returns an array of the objects themselves as its second value.
--
-- The occasion is a new shape of name in the compatibility layer. A group's
-- name can be a path into a foreign frame: in newer builds what the addon
-- needs to name lies as a field inside an object and has no global name at
-- all. The layer now resolves such names, checking every step of a path. But
-- a module that received a path-shaped name and went into _G with it would get
-- nil and silently do nothing — that is, a door created against silence would
-- itself become a source of it.
--
-- The public object gained no names and the previous value's behaviour did not
-- change: a module written for version 17 does not take the second value and
-- does not notice it. Nothing was removed or renamed, and the lower bound
-- stayed at one.
--
-- Version 19 added the door Darken:GetGameFunction(group, shape) — a group's
-- game function, and of the shape needed straight away.
--
-- The occasion is five modules, each deciding for itself which of two
-- spellings this client reads the bags by: a table or globals. That is
-- precisely the difference between clients the compatibility layer exists
-- for, and five forks were five second lists of other people's names.
--
-- The older door would have sufficed on its own (GetFrameNames returns names
-- and objects), but there is one thing it cannot say: the two spellings of
-- the container item reader answer differently — one with a record of fields,
-- the other with a flat list of values. A door handing over "a function"
-- silently would move the trouble into the module. So the shape is asked for:
-- the caller names the one it can read and receives a function of that shape
-- only.
--
-- One name was added, nothing was removed or renamed; a module written for
-- version 18 does not see this door. The lower bound is one.
local API_VERSION     = 23
local API_MIN_VERSION = 1

-- The version from which a mover element's label arrives already translated.
-- The number is given a name rather than written into the condition: a bare
-- ">= 16" in the middle of RegisterElement tells nothing about what it is,
-- and would survive a rename silently.
local LABEL_TEXT_VERSION = 16

-- The "this object is ours" marker field that handle:Own places.
--
-- It lives here rather than in the dimming subsystem: the field's name is part
-- of the contract (everyone who asks "is this ours" reads it), while the
-- dimming subsystem is merely the first to ask. The addon's prefix is
-- mandatory: the field is placed on a foreign object, and a bare name there
-- would be a seizure of somebody else's space.
local OWNED_FIELD = "umbraOwned"
ns.OWNED_FIELD = OWNED_FIELD

-- The table of work-done counters (Core/Tally.lua) that handle:Counters
-- returns. Created "if not already there" for the reason the subsystems
-- create it that way: the tests load the core one file at a time, and
-- Core/Tally.lua is sometimes not loaded at all among them. A module that
-- received nil instead of the table would fail on its very first line.
ns.Counters = ns.Counters or {}

local Api = {}
ns.Api = Api

Api.API_VERSION     = API_VERSION
Api.API_MIN_VERSION = API_MIN_VERSION

-- A module's name: Latin letters, digits and underscores, starting with a
-- letter. The name becomes a key in the settings profile and the id of its
-- settings section, that is, it reaches both SavedVariables and other
-- people's eyes. Cyrillic and spaces would work there, but they would read as
-- rubbish in the settings file and as a foreign string among English keys in
-- the settings.
local NAME_PATTERN = "^%a[%w_]*$"
local NAME_LIMIT   = 32

-- Translation is called by the name ns.Localize and only so, with no local
-- wrapper: the translation-completeness check reads the keys out of the
-- sources by that name (tests/test_locale_tables.lua), and a key hidden
-- behind a wrapper would stay untranslated silently. Core/Locale.lua loads
-- before this file, so the translation is in place already at load time.

--- Tell the player, on the core's behalf.
-- @param text string
local function say(text)
    local addon = ns.Addon
    if type(addon) == "table" and type(addon.Print) == "function" then
        addon:Print(text)
    elseif type(print) == "function" then
        print("Darken: " .. tostring(text))
    end
end

--- Whether a contract version is supported.
-- A module may ask in advance and, for instance, not register the part of
-- itself that needs a newer contract.
-- @param version number
-- @return boolean
function Api:Supports(version)
    if type(version) ~= "number" or version ~= version then return false end
    return version >= API_MIN_VERSION and version <= API_VERSION
end

--- The client's flavour in one word.
-- The core has it anyway (ns.flavor, Core/Compat.lua); it is exposed so that
-- every module need not grow a client detection of its own. Three such
-- detections will diverge from ours at the very first new interface, and
-- diverge silently: a module will decide it is on a different client and start
-- looking for frames under different names.
--
-- A function rather than a field: the flavour is computed in the core's
-- OnInitialize while a module's file is read later — but a module may call
-- this earlier, from its file's body. A field at such a moment would be nil
-- forever, while a function answers when it is asked.
-- The words are Core/Compat.lua's: "vanilla", "tbc", "wrath", "cata",
-- "mists", "mainline", "unknown". They are part of the contract on the same
-- footing as the frame group keys: adding is allowed, renaming is not.
-- @return string|nil the flavour's name; nil before the core determined the
--         client
function Api:GetFlavor()
    return ns.flavor
end

--- Whether this mob was tapped by somebody else.
--
-- Tapped means another player struck it and the kill will not count for you.
-- The game paints such a mob's bar grey, and the player decides by that grey
-- whether to attack or walk on. A module that paints the bars itself must ask
-- and paint the same way — otherwise it takes an answer away from the player
-- and gives nothing in return.
--
-- The door is needed for every other door's reason: the question is one while
-- the answers differ between clients. The later line asks in one word, the
-- early one assembles it from two — whether it is tapped at all and whether it
-- is tapped by you — and sorting that out in every module would mean a second
-- copy of knowledge about the client.
--
-- Not knowing means no: a mob the client is silent about must look ordinary.
-- A grey bar on a live kill is worse than a coloured one on somebody else's —
-- the first takes a target away, the second merely fails to hint.
--
-- @param unit string the unit
-- @return boolean
function Api:IsTapDenied(unit)
    return ns.Compat.UnitTapDenied(unit)
end

-- The styling, exposed outwards.
--
-- Why it is here. A module that draws a window of its own (the bags were the
-- first) needs our look: the same colours, the same one-pixel border, the
-- same spacing scale. Without this door a module's author has two paths and
-- both are bad. Either they rewrite the palette on their side — and then our
-- lilac and theirs diverge at the very first edit, and diverge silently; or
-- they reach into ns.Skin through a core global they do not have, that is,
-- they do not reach it at all.
--
-- The surface is small for the reason all the rest of it is: every function
-- is a promise forever. Exactly those actions every one of our windows is made
-- of were exposed: take a colour, take a spacing, fill a frame with a border,
-- outline a region, colour a label — and, since version 11, ask the
-- dictionary of states (see below).
--
-- Ownership is not transferred here either. This is not access to the
-- palette table but functions over it: Metrics returns a copy, Color three
-- numbers. A module given the table itself could write into it — and would
-- recolour the core along with every neighbour.
local SkinApi = {}

--- A palette colour by name.
-- @param name string the colour's name (see docs/module-api.md)
-- @param alpha number|nil the opacity; 1 by default
-- @return number|nil red, green, blue, opacity
function SkinApi.Color(name, alpha)
    return ns.Skin.Get(name, alpha)
end

--- The palette's colour names.
-- A new array is returned: a module needs the list so as not to guess the
-- names, while a shared table would let it change them.
-- @return table array of names, in a fixed order
function SkinApi.Colors()
    local out = {}
    for name in pairs(ns.Skin.Palette) do out[#out + 1] = name end
    table.sort(out)
    return out
end

--- The spacing scale: a copy rather than the shared table.
-- @return table
function SkinApi.Metrics()
    local out = {}
    for key, value in pairs(ns.Skin.Metrics) do out[key] = value end
    return out
end

--- A fill and a one-pixel border.
-- @param frame table the module's frame
-- @param background string the fill colour's name
-- @param border string|nil the border colour's name; nil for no border
-- @return boolean whether it was accepted
function SkinApi.Backdrop(frame, background, border)
    if type(frame) ~= "table" then return false end
    if ns.Skin.Get(background) == nil then return false end
    if border ~= nil and ns.Skin.Get(border) == nil then return false end

    ns.Skin.Backdrop(frame, background, border)
    return true
end

--- A one-pixel border around an arbitrary region of a frame.
--
-- The texture set is remembered in one of two ways, and choosing between them
-- is choosing whose frame it is:
--
--   a field name (string) — on a frame the module created itself; an extra
--     field on its own frame harms nothing;
--   side memory (SkinApi.Memory, version 21) — on a GAME frame: a nameplate,
--     an action button, a bag slot. Writing a field into a game object's
--     table taints the object itself, and the taint surfaces in somebody
--     else's file.
--
-- The door used to accept only the first kind, although the core could do
-- both, and silently answered "not accepted" to the second: a module moved to
-- side memory lost its borders entirely and then failed reading emptiness out
-- of it. That is exactly what happened to the nameplates module.
--
-- @param frame table the frame that owns the textures
-- @param key string|table a field name, or the side memory
-- @param target table the region to border
-- @param color string the colour's name
-- @return boolean whether it was accepted
function SkinApi.Outline(frame, key, target, color)
    if type(frame) ~= "table" or type(target) ~= "table" then return false end

    local named = type(key) == "string" and key ~= ""
    local aside = type(key) == "table"
    if not named and not aside then return false end

    if ns.Skin.Get(color) == nil then return false end

    ns.Skin.Outline(frame, key, target, color)
    return true
end

--- A label's colour from the palette.
-- @param fontString table the font string
-- @param color string the colour's name
-- @return boolean whether it was accepted
function SkinApi.Text(fontString, color)
    if type(fontString) ~= "table" then return false end
    if ns.Skin.Get(color) == nil then return false end

    ns.Skin.Text(fontString, color)
    return true
end

-- The dictionary of states, exposed outwards (version 11).
--
-- Colour and spacing answer the question "what does this look like". The
-- three functions below answer a different one — "what does this look like
-- right now": the row is selected, the row is under the cursor, the field
-- accepts letters, the element is disabled. That answer was settled once for
-- the whole window (Core/Skin.lua) and until now was visible only from inside
-- the core; from outside a module either rewrote both fill quantities for
-- itself or drew no states at all — and not one of the nine drew them.
--
-- The very functions the settings window calls were exposed rather than
-- similar ones beside them: a second record of "selection is lilacDeep 0.85"
-- would diverge from the first silently, and would diverge not by breaking
-- but by a tenth of opacity nobody checks by eye.
--
-- Ownership is not transferred here either, and for free: what goes out is
-- colour names,
-- an opacity and a state name — strings and numbers rather than tables. A
-- module paints with them through that same SkinApi.Color, so the palette
-- stays one.

--- A row's fill colour name and opacity, by state.
-- An unknown state (an ordinary row included) means no fill rather than a
-- default one: two nils rather than a colour at random.
-- @param state string|nil "selected" | "hover"
-- @return string|nil the palette colour's name
-- @return number|nil the opacity
function SkinApi.RowColors(state)
    return ns.Skin.RowColors(state)
end

--- The fill, border and label colour names of a button in a given state.
-- An unknown state and an unknown kind count as the ordinary ones: the name
-- comes from a module's code, and a typo in it must not leave a button with
-- no colour at all.
-- @param state string|nil "normal" | "hover" | "pressed" | "focus" | "disabled"
-- @param kind string|nil "normal" | "primary" | "select"
-- @return string, string, string three palette colour names
function SkinApi.ButtonColors(state, kind)
    return ns.Skin.ButtonColors(state, kind)
end

--- The state of a field typed into from the keyboard.
-- The order of precedence is written down here: disabled beats focus, focus
-- beats hover. The middle step is the function's whole point — focus answers
-- "where will the letters go" and has to stay visible after the cursor has
-- left.
-- @param disabled any whether the field is disabled
-- @param focused any whether the field has keyboard focus
-- @param over any whether the cursor is over the field
-- @return string the state name for ButtonColors with the "select" kind
function SkinApi.FieldState(disabled, focused, over)
    return ns.Skin.FieldState(disabled, focused, over)
end

--- A value one can compute with, or nil.
--
-- The door was opened by version 20, and what opened it was the bill the
-- addon paid on a live client. The client hands over the properties of
-- protected and restricted objects as secret values: a secret number's type
-- is number, a secret string's is string, they can be passed anywhere, and
-- the first action on them breaks the execution while it is tainted by an
-- addon. A type check misses precisely the case it would be written for.
--
-- A module that draws a bar from a unit's health or a label from its name
-- will meet this on its first day. It has two answers of its own and both are
-- bad: either a type check, which is that very mistake, or a second pcall
-- probe beside ours — and there should be exactly as many such probes in one
-- addon as there are rules, that is, one.
--
-- @param value any
-- @return number|nil the same number, if it can be computed with
function SkinApi.Numeric(value)
    return ns.Skin.Numeric(value)
end

--- A string one can work with, or nil.
-- The string counterpart to Numeric and the same trouble: see its note above.
-- @param value any
-- @return string|nil the same string, if it can be worked with
function SkinApi.Textual(value)
    return ns.Skin.Textual(value)
end

--- A yes-or-no answer one can work with.
-- The third counterpart to Numeric and Textual: the client hands over
-- booleans as secret too. The trouble with them is quieter than with numbers:
-- Lua tests truthiness without a comparison, and a secret yes can be stepped
-- around by accident — and the answer turns out not false but arbitrary.
-- @param value any
-- @return boolean
function SkinApi.Truth(value)
    return ns.Skin.Truth(value)
end

--- An object addons must not touch.
--
-- The third part of the same answer and the most expensive of the three. The
-- engine marks some of its objects forbidden, and touching such an object
-- taints the execution — and the taint spreads further through the frames the
-- object touches and surfaces elsewhere than where it was set: the player
-- sees an error in a game file, on an action button's cooldown, and does not
-- think of the addon at all.
--
-- A module needs this everywhere it walks somebody else's frame tree rather
-- than its own objects.
--
-- @param object any
-- @return boolean
function SkinApi.Forbidden(object)
    return ns.Skin.Forbidden(object)
end

--- Memory about an object that leaves no trace on it.
--
-- A module needs the same thing a core subsystem does: to remember one or two
-- things about somebody else's object — what it was before us, whether we
-- have touched it already. The obvious place for that is a field on the
-- object itself, and for years that is where it lay.
--
-- That turned out to be wrong. Writing a field into a game object's table
-- marks the object itself: the engine considers it touched by an addon, and
-- the taint spreads further — to the frame the object belongs to and to
-- everything that frame touches. The player sees it not in our file but in
-- somebody else's:
--
--   Blizzard_ActionBar/Shared/ActionButton.lua:891: bad argument #1 to
--   'SetCooldown' ... Secret values are only allowed during untainted
--   execution for this argument.
--
-- Looking at a foreign object and painting it is allowed. Writing on it is
-- not.
--
-- A table with weak keys is returned: the object is the key, and the record
-- about it disappears along with it. A fresh one per call: two memories about
-- different things must not share keys.
--
-- @return table
function SkinApi.Memory()
    return ns.Skin.Memory()
end

--- Show or hide the move mode.
--
-- === Why a module needs this ===
--
-- A module hands its block over to the core's mover (handle:RegisterElement,
-- version 14), and from that minute the player moves it by the same handles
-- as everything else on screen. One thing was missing: a way to get there
-- while standing at its own settings.
--
-- There was a route — the Mover page in the settings column — but it leads
-- from a different place to a different place. A player configuring the raid
-- frames while looking at a grid for fitting wants to move that grid now
-- rather than hunt for it in somebody else's page. The author put it plainly:
-- how am I supposed to move it around the screen? In Cell it is exactly as
-- asked: a button in the same window as everything else.
--
-- What this door does NOT give: placing its own block at a point without the
-- player — handle:MoveElement is for that, and it always was. Here there is
-- only "show the handles", that is, the same thing the switch on the mover
-- page does.
--
-- @param shown boolean|nil; nil toggles
-- @return boolean whether the mode is shown now
function Api:ToggleMovers(shown)
    local movers = ns.Movers
    if type(movers) ~= "table" then return false end

    if shown == nil then
        if type(movers.ToggleOverlay) ~= "function" then return false end
        local ok, out = pcall(movers.ToggleOverlay)
        return ok and out == true
    end

    local name = shown and "ShowOverlay" or "HideOverlay"
    if type(movers[name]) ~= "function" then return false end

    local ok = pcall(movers[name])
    return ok and shown and true or false
end

--- Whether the move mode is shown right now.
-- @return boolean
function Api:MoversShown()
    local movers = ns.Movers
    if type(movers) ~= "table" or type(movers.OverlayShown) ~= "function" then
        return false
    end

    local ok, out = pcall(movers.OverlayShown)
    return ok and out == true
end

--- The core's styling, for a module.
-- A function rather than a field for GetFlavor's reason: a module's file may
-- be read before the core has finished assembling itself.
-- @return table
function Api:GetSkin()
    return SkinApi
end

-- A unit's colour, exposed outwards.
--
-- The door was opened by that same version 20 and by exactly its neighbour's
-- argument. A module that draws a party member's bar has to answer the
-- question "in what colour", and the addon already has that answer: by class,
-- by reaction, by power type, a fixed colour, the game's colour. That rule
-- lives in the unit frames subsystem and cost it dearly — on a live client it
-- turned out that a foreign unit's class and reaction arrive secret, and the
-- colour has to be read rather than derived.
--
-- Without the door a module's author has one path: rewrite the class colour
-- table and the order of fallbacks on their side. The copy will diverge from
-- the original at the very first edit — and diverge silently: both will
-- answer with a colour, merely a different one. "By class" in one window of
-- the addon will start meaning something other than in another.
local ColorApi = {}

--- A bar's colour, by the player's choice.
-- @param mode string|nil "__native" | "class" | "reaction" | "power" | "fixed"
-- @param info table|nil { class, classColors, reaction, reactionColors,
--                         power, powerType, powerColors, powerFallback, fixed }
-- @return number|nil, number|nil, number|nil
function ColorApi.Bar(mode, info)
    return ns.UnitFrames.BarColor(mode, info)
end

--- The colour the game itself paints this bar with.
-- @param kind string|nil "health" | "power"
-- @param info table|nil the same data as Bar's
-- @return number|nil, number|nil, number|nil
function ColorApi.Game(kind, info)
    return ns.UnitFrames.GameColor(kind, info)
end

--- A unit's name colour.
-- @param mode string|nil
-- @param info table|nil
-- @return number|nil, number|nil, number|nil
function ColorApi.Name(mode, info)
    return ns.UnitFrames.NameColor(mode, info)
end

--- A unit's colours, for a module.
-- @return table
function Api:GetUnitColors()
    return ColorApi
end

-- The media, exposed outwards.
--
-- Why it is here. The styling (GetSkin) gives colour and spacing, and that is
-- enough for a window. A module that draws a bar and a label needs two more
-- things, and both lay behind a closed door in the core: the addon's nine
-- statusbar textures and the font settings the player set on the Fonts page.
-- Without this door a module's author has two paths and both are bad. Either
-- they write the path to our file out as a string — and it diverges from the
-- addon at the very first rename, silently; or they grow a second font choice
-- of their own, and their module's labels stop obeying a setting that looks
-- shared on screen.
--
-- The font is not "handed over" but applied: ApplyFont calls the fonts
-- subsystem, and the font's owner stays one. That subsystem also remembers an
-- object's original value, so "as in the game" returns the native look rather
-- than our latest choice.
local MediaApi = {}

--- The media library. Its absence is an ordinary nil answer, not an
--- error.
-- @return table|nil
local function mediaLib()
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok and type(lib) == "table" then return lib end
    return nil
end

-- The "the game's own texture" marker. The unit frames subsystem's, and
-- taken from there rather than written out as a string: the value reaches
-- SavedVariables, and two copies would diverge silently. A module needs it
-- because the first entry in its texture list has to mean "do not substitute"
-- rather than "paint with something".
MediaApi.NATIVE = "__native"

--- The statusbar texture names known to this client.
-- A new array every time: a shared list would let a module rewrite the
-- texture registry for the whole addon.
-- @return table array of names
function MediaApi.BarTextures()
    return ns.Media.BarNames(mediaLib())
end

--- A statusbar texture's file path, by name.
-- nil means "there is no such texture" — including for the NATIVE marker.
-- The answer must be checked: the name comes from a setting, that is, from
-- SavedVariables, where anything ends up over the years.
-- @param name string the texture's name
-- @return string|nil the file's path
function MediaApi.BarTexture(name)
    if name == MediaApi.NATIVE then return nil end
    return ns.Media.BarPath(mediaLib(), name)
end

--- The keys of the core's font categories.
-- A new array; the order is fixed — the one the categories are declared in.
-- @return table array of keys
function MediaApi.FontCategories()
    local out = {}
    local fonts = ns.Fonts
    local list = type(fonts) == "table" and fonts.CATEGORIES or nil
    if type(list) ~= "table" then return out end

    for i = 1, #list do out[i] = list[i].key end
    return out
end

--- Assign a font to an object by a core category's rules.
--
-- Not "hand over the path to a font" but apply it: the selection rule, the
-- list of fonts and the memory of an object's original value stay with the
-- fonts subsystem. A second substitution mechanism beside the first would
-- mean a second owner for one action — with its own order of application and
-- its own idea of what counts as native.
--
-- Called on every object that appears, including a nameplate's label created
-- just now: the fonts subsystem's general pass did not catch it, and waiting
-- for the next change of settings would mean showing it in the wrong font.
-- @param category string the category's key (see FontCategories)
-- @param object table a font object or a font string
-- @return boolean whether it was applied
function MediaApi.ApplyFont(category, object)
    local fonts = ns.Fonts
    if type(fonts) ~= "table" or type(fonts.ApplyCategory) ~= "function" then
        return false
    end
    return fonts.ApplyCategory(category, object) and true or false
end

--- The core's media, for a module.
-- A function rather than a field for GetFlavor's reason: a module's file may
-- be read before the core has finished assembling itself.
-- @return table
function Api:GetMedia()
    return MediaApi
end

--- The shared aura filter, for a module.
--
-- Why it is here. Two modules arrived at one and the same filter separately:
-- the nameplate engine and the compact auras. The mode words matched, the
-- parsing of the typed list, the name key and the explicitly documented
-- string.lower limit — that is, everything the player sees in their own spell
-- list. (The limit itself has since been lifted: the name key folds case
-- through the core's Core/Casefold.lua.) Two copies of one rule diverge
-- silently, and a module may not look into another's folder: the shared place
-- for both is only the core.
--
-- The same table our own code uses is exposed (ns.AuraFilter,
-- Core/AuraFilter.lua) rather than a similar one beside it: a second parsing
-- of the list would cost exactly what the door is open to prevent.
--
-- A function rather than a field for GetFlavor's reason: a module's file may
-- be read before the core has finished assembling itself.
-- @return table parsing the list (Split), compiling the plan (Compile) and
--   deciding about one aura (Decide); documented in docs/module-api.md
function Api:GetAuraFilter()
    return ns.AuraFilter
end

--- Case folding for comparison.
--
-- Why it is here. string.lower in Lua 5.1 folds byte by byte and knows only
-- ASCII, while the game hands over names in UTF-8: a capitalised name and a
-- lower-case one are different strings to it, and whoever typed their item's
-- name in lower case does not find it. Three subsystems hit that limit
-- separately — the bags' search, the item database's query language and the
-- shared aura filter — and each wrote it down as a caveat of its own. Three
-- copies of one limitation are exactly the shape this project has already
-- reconciled twice; the shared place for all three is one, and it is the
-- core.
--
-- The same table our own code uses is exposed (ns.Casefold,
-- Core/Casefold.lua) rather than a similar one beside it: a second mapping
-- table would diverge from the first silently, and would diverge on a letter
-- nobody checks.
--
-- A function rather than a field for GetFlavor's reason: a module's file may
-- be read before the core has finished assembling itself.
--
-- Since version 10 Upper — capitals for display — lies behind that same door.
-- The door is one because the table of alphabets is one: splitting folding
-- and raising across two doors would promise that they are two different
-- pieces of knowledge, and sooner or later two would be created. Folding is
-- still only for comparison and raising only for display; Upper stands
-- nowhere on a search path.
-- @return table folding a string (Fold), a comparison key (Key) and capitals
--   for display (Upper); documented in docs/module-api.md
function Api:GetCasefold()
    return ns.Casefold
end

--- Writing a number: abbreviating a large one and a share in per cent.
--
-- Why it is here. The styling gives colour and spacing, the media a texture
-- and a font, the case folding the comparison of names. The number the player
-- reads most often the contract did not expose at all, and so "how to write
-- 12,437 in a label fifty pixels wide" was written in the addon twice. The
-- records diverged without breaking: the health bar wrote "12.4k", the
-- panel's cell below it "12k", and the same 999,999 was "1.0m" for one and
-- "1000.0k" for the other. Nobody sees this break — there are simply two
-- different addons on one screen.
--
-- The same table our own code uses is exposed (ns.Format, Core/Format.lua)
-- rather than a similar one beside it: a second set of thresholds would
-- diverge from the first silently. Both functions are pure — numbers in, a
-- string and a number out — and they expose nothing we own.
--
-- A function rather than a field for GetFlavor's reason: a module's file may
-- be read before the core has finished assembling itself.
-- Rounding (Round) was added by version 13 and lies in the same table: it was
-- not on the surface, and because of that one record of the rule survived
-- version 12's reconciliation — the panel rounded the frame rate with a body
-- of its own that matched the core's line for line.
-- @return table rounding to an integer (Round), abbreviating a large number
--   (Abbreviate) and a share in per cent (Percent); documented in
--   docs/module-api.md
function Api:GetFormat()
    return ns.Format
end

--- The addon's version as a string.
--
-- Why. A module with a version of its own could not until now tell the player
-- which core it works with — and that is the first thing asked in any bug
-- report. The only way was to read the core's TOC itself, that is, to
-- establish a second place where our version is written.
--
-- A string rather than a number: in the TOC it has the form 0.1.0, and
-- turning it into a number would impose on a module a parsing we ourselves
-- would break at the first letter in a version. A module has no reason to
-- compare core versions — API_VERSION exists for that, and was invented for
-- it.
-- @return string|nil the version from the TOC; nil when there is nobody to
--         ask
function Api:GetVersion()
    local get = GetAddOnMetadata
    if type(get) ~= "function" and type(C_AddOns) == "table" then
        get = C_AddOns.GetAddOnMetadata
    end
    if type(get) ~= "function" then return nil end

    local ok, value = pcall(get, ADDON, "Version")
    if ok and type(value) == "string" and value ~= "" then return value end
    return nil
end

--- The game's frame names, by group.
--
-- Why it is here. The compatibility layer (Core/Compat.lua) is declared the
-- only place in the addon that knows other people's frame names. It is closed
-- to the outside, though, and a module needing to hide a Blizzard window or
-- to stand beside a foreign bar was left to establish exactly that list of
-- names the layer exists to keep single. A second copy of the list diverges
-- from the client at the very first patch, and diverges silently.
--
-- Only names that exist are returned. The existence filter sits outside the
-- pure resolution (Compat.FilterExisting over Compat.GetFrameNames) — the way
-- our own subsystems use it: a list of candidates without the filter would be
-- a trap, because some names are not in every build.
--
-- A new array is returned: both of the layer's functions build their own
-- tables, and a shared table would let a module rewrite the frame list for
-- the whole addon.
--
-- AS A SECOND VALUE (since version 18) — the objects themselves, one per name
-- and in the same order. Without them the door would be a trap: a name in a
-- group can be a path into a foreign frame, and _G[path] is nil. A module
-- that took a name and went into _G itself would get emptiness and silently
-- do nothing — precisely the failure both the layer and this door are written
-- against.
--
-- What exactly is in an object the core does not promise: a path may hold a
-- frame, a texture, a game API table. Only existence is promised. The kind is
-- asked of the object itself.
--
-- Before the core has determined the client the list is empty, and that is
-- not an error: names are to be resolved in OnEnable rather than in a file's
-- body. An exception here would be raised from somebody else's addon file and
-- would abort its loading.
-- @param group string the group's name (see docs/module-api.md)
-- @return table array of names, possibly empty
-- @return table array of objects, one per name
function Api:GetFrameNames(group)
    if type(group) ~= "string" or group == "" then return {}, {} end
    if ns.flavor == nil then return {}, {} end

    local ok, names, objects = pcall(ns.Compat.Resolve, group)
    if ok and type(names) == "table" then
        return names, type(objects) == "table" and objects or {}
    end

    return {}, {}
end

--- A group's game function — the one this client calls it by.
--
-- Why it stands beside GetFrameNames. Some game functions are named
-- differently on the different supported clients: the container work lies now
-- in a table, now in globals. Five modules each wrote a fork of their own,
-- "the table first, then the global" — and every such fork was a second piece
-- of knowledge about the client outside the compatibility layer, that is,
-- precisely what both the layer and this door exist against.
--
-- THE ANSWER'S SHAPE IS ASKED FOR. Two spellings of one function are
-- sometimes not merely named differently but built differently: the
-- table-based container item reader answers with a single record of fields,
-- while the global of the same name answers with a flat list of values. So
-- the caller names the shape it can read (record or values) and receives a
-- function of that shape only; for a group whose spellings answer alike the
-- word is optional. A question without the word where the shapes differ gives
-- nil, and that is not pedantry: otherwise "call the wrong thing" would stay
-- possible and silent.
--
-- A client that has not one of the spellings answers nil. A module must
-- survive that and stay with its "I do nothing": silence here is legitimate,
-- failing is not.
--
-- The second value is the shape of what was found, the third the path it was
-- found at. The path is returned for the author's messages (the report,
-- /darken) rather than so that something may be looked up by it a second
-- time.
--
-- @param group string the group's name (see docs/module-api.md)
-- @param shape string|nil the answer's shape: "record", "values" or nil
-- @return function|nil
-- @return string|nil the shape of the one found
-- @return string|nil the path it was found at
function Api:GetGameFunction(group, shape)
    if type(group) ~= "string" or group == "" then return nil end
    if ns.flavor == nil then return nil end

    local ok, fn, found, path = pcall(ns.Compat.ResolveFunction, group, shape)
    if not ok or type(fn) ~= "function" then return nil end

    return fn, found, path
end

--- Reconciling the versions.
-- A pure function: all three numbers arrive as arguments, so the rule is
-- tested outside the game in all three outcomes — older, newer, exact.
-- @param name string the module's name, for the message
-- @param required number|any the version the module declared
-- @param provided number|nil the core's version (the current one by default)
-- @param minimum number|nil the oldest accepted (the current one by default)
-- @return boolean whether they reconcile
-- @return string|nil the reason for refusal
function ns.CheckApiVersion(name, required, provided, minimum)
    provided = provided or API_VERSION
    minimum  = minimum  or API_MIN_VERSION

    -- NaN is cut off by a check of its own, and that check is not
    -- redundant: 0/0 is a number by type, but both comparisons below are
    -- false for it, and the version would pass straight through. A module
    -- with api = 0/0 would register successfully and declare anything at all
    -- by it.
    if type(required) ~= "number" or required ~= required then
        return false, string.format(ns.Localize(
            "module \"%s\" does not say which Darken module API version "
            .. "it needs"), tostring(name))
    end

    if required > provided then
        return false, string.format(ns.Localize(
            "module \"%s\" needs Darken module API version %s, and this "
            .. "core provides %s; update Darken"),
            tostring(name), tostring(required), tostring(provided))
    end

    if required < minimum then
        return false, string.format(ns.Localize(
            "module \"%s\" was written for Darken module API version %s, "
            .. "which this core no longer supports (the oldest supported is "
            .. "%s); update the module"),
            tostring(name), tostring(required), tostring(minimum))
    end

    return true
end

--- Check a module's descriptor.
-- Separate from registration, so that the rules read as one piece and are
-- tested outside the game. It returns the reason for refusal as text rather
-- than raising: a Register that raised would take somebody else's addon's
-- loading with it, and the player would see a yellow Lua error instead of a
-- comprehensible line.
-- @param descriptor any
-- @return boolean
-- @return string|nil the reason for refusal
function ns.CheckModuleDescriptor(descriptor)
    if type(descriptor) ~= "table" then
        return false, ns.Localize("a module must be given as a table")
    end

    -- The core did not start, so registration is refused out loud. It used
    -- to succeed: the module entered the registry, was never enabled,
    -- received no settings (there is no database) and knew nothing about it
    -- at all, because even handle:Print would go nowhere. A silent success is
    -- the worst possible answer: the module's author looks for the mistake on
    -- their own side.
    if ns.CoreStartupFailed then
        return false, ns.Localize(
            "Darken did not start on this client, so it cannot take modules")
    end

    local name = descriptor.name
    if type(name) ~= "string" or name == "" or #name > NAME_LIMIT
        or not name:match(NAME_PATTERN) then
        return false, ns.Localize("a module needs a name made of Latin letters, "
            .. "digits and underscores and starting with a letter")
    end

    -- A name the core claims. The refusal names the name itself and says
    -- what to do: a silent refusal here would mean a module that stopped
    -- working after a core update and an author looking for the breakage on
    -- their own side. Which names are claimed and why the list no longer
    -- grows — see Core/Defaults.lua.
    if type(ns.CoreOwnsName) == "function" and ns.CoreOwnsName(name) then
        return false, string.format(ns.Localize(
            "the name \"%s\" belongs to Darken itself and cannot be a "
            .. "module name; names starting with \"core_\" are reserved for "
            .. "the core too, so name your module after your addon"),
            name)
    end

    if ns.Registry:Get(name) then
        return false, string.format(ns.Localize(
            "the name \"%s\" is already registered"), name)
    end

    local okVersion, versionErr = ns.CheckApiVersion(name, descriptor.api)
    if not okVersion then
        return false, versionErr
    end

    local shape = {
        defaults      = "table",
        globals       = "table",
        options       = "table",
        OnEnable      = "function",
        OnDisable     = "function",
        ApplySettings = "function",
    }
    for field, wanted in pairs(shape) do
        local value = descriptor[field]
        if value ~= nil and type(value) ~= wanted then
            return false, string.format(ns.Localize(
                "module \"%s\" declares \"%s\" of the wrong type"),
                name, field)
        end
    end

    if descriptor.options ~= nil then
        local options = descriptor.options
        if options.type ~= "group" or type(options.args) ~= "table" then
            return false, string.format(ns.Localize(
                "the options section of module \"%s\" is not a group "
                .. "AceConfig can show"), name)
        end

        -- The tree is checked by the library's own real rules, and checked
        -- here rather than when the window opens. AceConfigRegistry raises on
        -- the first unfamiliar field of a node, and it used to be called from
        -- AceConfigDialog — that is, outside our guard. A malformed section
        -- of somebody else's module would mean a settings window that does
        -- not open at all, and the core would look at fault. Refusing the
        -- module here is cheaper.
        -- LibStub is a table with a __call metamethod rather than a function:
        -- it must not be checked with type(...) == "function", because such a
        -- check never succeeds and silently switches off everything behind
        -- it.
        --
        -- No library means no registration. The check used to be simply
        -- skipped, and that is the worst of the options: a refusal would look
        -- like a success, and a section AceConfig does not accept would reach
        -- the tree and close the settings window entirely. A missing
        -- validator means a broken installation of the core, and that has to
        -- be said plainly.
        --
        -- NOTE: nothing draws this section today — the settings window is
        -- declared as data (Options/Schema.lua) and never builds an AceConfig
        -- tree. The field is still accepted and still validated, so the
        -- promise made to module authors is not broken silently; removing it
        -- is part of the wider cleanup after the window's migration.
        local registry
        if LibStub ~= nil then
            local okLib, found = pcall(LibStub, "AceConfigRegistry-3.0", true)
            if okLib then registry = found end
        end

        if type(registry) ~= "table"
            or type(registry.ValidateOptionsTable) ~= "function" then
            return false, string.format(ns.Localize(
                "the options section of module \"%s\" cannot be checked: "
                .. "AceConfigRegistry-3.0 is missing from this installation"),
                name)
        end

        local okTree, treeErr = pcall(
            registry.ValidateOptionsTable, registry, options, name)
        if not okTree then
            return false, string.format(ns.Localize(
                "the options section of module \"%s\" was refused by "
                .. "AceConfig: %s"), name, tostring(treeErr))
        end

        local okGuardable, guardErr = ns.CheckGuardableOptions(name, options)
        if not okGuardable then
            return false, guardErr
        end
    end

    return true
end

-- The fields of a node whose value AceConfigDialog calls as a method of the
-- handler object when a string is in them. The list is derived from the
-- library itself: everything absent from its stringIsLiteral and
-- allIsLiteral is called, not only get/set/func. A string in any of them
-- means a call into foreign code outside our guard, so all of them are
-- checked.
local METHOD_FIELDS = {
    get = true, set = true, func = true, validate = true, confirm = true,
    hidden = true, disabled = true,
    values = true, sorting = true, order = true, hasAlpha = true,
    iconCoords = true, imageCoords = true, relWidth = true,
}

--- Check that a settings section can be guarded in full.
--
-- Why. ns.GuardOptions wraps functions — and only functions. AceConfig has a
-- documented second form: handler = t, get = "GetFoo", and then the library
-- itself calls t:GetFoo(info). Such a call bypasses the wrapper entirely: a
-- get that raised would mean a yellow Lua error over the settings window —
-- precisely what the contract document promises not to allow.
--
-- That form cannot be wrapped in place without rewriting somebody else's
-- handler table, that is, without changing the module's behaviour behind its
-- back. So the form is unsupported, and the refusal names it in words: put
-- the function itself in the field.
-- @param name string the module's name
-- @param node table a node of the tree
-- @param seen table|nil the nodes already walked (a guard against cycles)
-- @return boolean
-- @return string|nil the reason for refusal
function ns.CheckGuardableOptions(name, node, seen)
    if type(node) ~= "table" then return true end

    seen = seen or {}
    if seen[node] then return true end
    seen[node] = true

    if node.handler ~= nil then
        return false, string.format(ns.Localize(
            "the options section of module \"%s\" uses \"handler\" with "
            .. "string method names; Darken cannot guard that form, so put "
            .. "the function itself in the node instead"), name)
    end

    for key, value in pairs(node) do
        if METHOD_FIELDS[key] and type(value) == "string" then
            return false, string.format(ns.Localize(
                "the options section of module \"%s\" puts the method name "
                .. "\"%s\" in \"%s\"; Darken cannot guard that form, so put "
                .. "the function itself in the node instead"),
                name, value, tostring(key))
        end

        if type(value) == "table" then
            local ok, reason = ns.CheckGuardableOptions(name, value, seen)
            if not ok then return false, reason end
        end
    end

    return true
end

--- Pack a call's results together with their count.
-- In Lua 5.1 there is no other way to preserve a nil among the returned
-- values, and a colour setting's get returns four numbers of which the alpha
-- is sometimes nil.
local function pack(...)
    return select("#", ...), { ... }
end

-- What the wrapper answers on behalf of a handler that raised.
--
-- It used to answer nil for any field, and for get, set and func that is
-- right: the library receives "there is no value" and draws an empty widget.
-- But for half of a node's fields AceConfig consumes the value itself, and a
-- nil there is not caution but a second breakage in place of the first. A
-- dropdown's values that raised gave nil, the library did pairs(nil) inside
-- its own drawing — outside our pcall — and the player got precisely the
-- yellow error the wrapper is written to prevent.
--
-- So the fallback value is chosen by the field's meaning. It need not be
-- useful — it must be such that the library finishes drawing the window and
-- the module, rather than the core, stays at fault.
--
-- The tables are fresh every time: a shared one would outlive the call, and
-- foreign code is free to write into it.
local FALLBACK = {
    values  = function() return {} end,   -- walked by pairs while drawing
    sorting = function() return {} end,   -- and by ipairs while sorting
    name    = function() return "" end,   -- the label takes part in sorting
    desc    = function() return "" end,
    usage   = function() return "" end,
    validate = function() return true end,  -- "the value is accepted"
    confirm  = function() return false end, -- no superfluous question
    hidden   = function() return false end,
    disabled = function() return false end,
}

--- Wrap a settings section's handlers in the guard.
--
-- Why this is needed. The registry guards its own doors into a module —
-- OnEnable, ApplySettings, the repaint handler. But the get, set and func
-- handlers inside a settings section were called by AceConfigDialog rather
-- than by us: those are calls into foreign code too, and left unguarded they
-- would leave a hole of exactly the size everything here is written for. A
-- get that raised there would mean a yellow Lua error over the settings
-- window and, worse, a window stuck half-drawn.
--
-- The wrapper is installed in place, in the module's own table, rather than
-- in a copy. A copy would freeze the tree: a section the author appends to
-- while in the game would stop reaching the window. The price is that nodes
-- added after registration stay unguarded; that is what docs/module-api.md
-- says.
-- @param name string the module's name
-- @param node table a node of the tree
-- @param seen table|nil the nodes already walked (a guard against cycles)
function ns.GuardOptions(name, node, seen)
    if type(node) ~= "table" then return node end

    seen = seen or {}
    if seen[node] then return node end
    seen[node] = true

    for key, value in pairs(node) do
        if type(value) == "table" then
            ns.GuardOptions(name, value, seen)
        elseif type(value) == "function" then
            local fn = value
            local field = tostring(key)
            local fallback = FALLBACK[key]

            node[key] = function(...)
                -- A disabled module is not called even here: its section
                -- has already been removed, but an open window may not have
                -- repainted yet. The answer is the same fallback: a window
                -- stuck halfway is indistinguishable to the player from one
                -- that crashed.
                if ns.Registry:IsFailed(name) then
                    if fallback then return fallback() end
                    return nil
                end

                local count, results = pack(pcall(fn, ...))
                if results[1] then
                    return unpack(results, 2, count)
                end

                ns.Registry:Disable(name,
                    ns.ModuleFailureText(name, "options." .. field, results[2]))

                if fallback then return fallback() end
                return nil
            end
        end
    end

    return node
end

--- Assemble the module handle the author receives.
-- The methods are closures over the name rather than reads of self.name. That
-- is the isolation of the settings: by replacing handle.name a module cannot
-- reach another's section, because GetSettings never reads the name from the
-- table at all.
--
-- But one closure is not enough, and that was learned expensively. The
-- handle.name field was read by the registry (to know whom to disable) and by
-- the assembly of the settings tree (to know where to put a section). A
-- module that wrote handle.name = "a neighbour" redirected the disabling onto
-- that neighbour: it was the module that failed while the neighbour dropped
-- out of the settings, out of the defaults and out of the application. No ill
-- intent was needed for this — the contract itself tells a module to keep its
-- state on the handle, and `name` begs to be used for a display name. It is
-- closed from both sides: the registry no longer reads that field
-- (Core/Registry.lua), and a door was placed here.
--
-- The door is a metatable rather than a "check on write": the core's fields
-- lie in a separate table and the handle itself is empty, so __newindex fires
-- for `name` too. Were the name a real field of the table, a write to it
-- would bypass the metamethod entirely — __newindex is called only for absent
-- keys.
-- @param descriptor table the checked descriptor
-- @return table

-- The core subsystems a module has the right to replace with itself.
--
-- The list is closed and short, and that is a decision. The core styles the
-- standard nameplates and the standard bags — both useful in themselves,
-- because not everybody installs a separate module. But once a module is
-- installed, styling the same thing as a second owner is not allowed: two
-- subsystems on one frame give flicker, and the one that looks at fault is
-- whichever name the player remembers first.
--
-- Why not "any subsystem". Handing fonts or skin in here would let somebody
-- else's module switch off half the addon with one line — and silently for
-- everybody but one line in chat. Exactly the two whose specification says "a
-- module replaces them entirely" are listed. The list may grow; it will not
-- be renamed.
local REPLACEABLE = { nameplates = true, bags = true }

-- Who owns what right now: [subsystem] = the name of the module that stood
-- it down.
--
-- The entry is created at exactly the moment the stand-down actually
-- happened, and removed at exactly the moment the subsystem comes back. It is
-- the answer to three questions at once, and that is why it is one table
-- rather than three flags:
--
--   1. Whether the subsystem may be brought back. No entry means there is
--      nothing to bring back: either nobody took it, or it is disabled for
--      another reason (it raised itself, or a third-party nameplate addon
--      stood it down, Modules/NamePlates.lua). Bringing back a subsystem
--      disabled by a failure would undo the isolation by somebody else's
--      hands.
--   2. Who exactly may bring it back. Only whoever took it. Otherwise a
--      second module replacing the same subsystem would resurrect the core's
--      styling on top of the first — and one frame would again have two
--      owners, with neither module learning of it.
--   3. What to give back for a module that was switched off. The registry
--      calls ns.ReleaseSubsystemsOf when it disables a module: nothing of a
--      switched-off module should stay alive, and a subsystem it stood down
--      is exactly a live trace that would otherwise outlive it until the
--      interface is reloaded.
local REPLACED_BY = {}

--- Stand a core subsystem aside: a module has taken its place.
--
-- Done by the same Disable that switches off a module which raised, and that
-- is no coincidence: exactly the three things it does are what is needed —
-- tell the player once, remove the settings section and stop calling the
-- subsystem. A separate mechanism beside it would be a second owner for one
-- action.
--
-- In addition the standDown flag is raised on the subsystem itself where it
-- understands one: the nameplates subsystem checks it on every entry, and a
-- recolour through a hook on a game function bypasses the registry.
--
-- The flag is set exactly when the stand-down really happens, and the right
-- to it is established before rather than after. It used to be raised on the
-- first line, unconditionally: a subsystem already disabled for another
-- reason got muted with no owner, and there was nobody left to unmute it —
-- ResumeSubsystem requires an owner that was never recorded. The flag means
-- "a module draws instead of me"; a subsystem the core switched off for its
-- own reasons must not be marked with it, and must not be stood down either —
-- a refusal with a reason is more honest than a mute false.
--
-- @param subsystem string the core subsystem's name
-- @param moduleName string the name of the module replacing it
-- @return boolean whether it was stood down now (false means it already was,
--     or it is disabled)
-- @return string|nil the reason for refusal
function ns.StandDownSubsystem(subsystem, moduleName)
    if type(subsystem) ~= "string" or not REPLACEABLE[subsystem] then
        return false, string.format(ns.Localize(
            "Darken has no subsystem named \"%s\" that a module may replace"),
            tostring(subsystem))
    end

    -- A switched-off module takes nothing. The core stopped calling it
    -- while the module's own code keeps running — a hook on a foreign frame,
    -- a handler that has not fired yet — and a subsystem stood down by such a
    -- module would never come back: there is nobody to bring it back. This is
    -- the same door as RegisterEvent's and Secure's, locked for the same
    -- reason.
    if ns.Registry:IsFailed(moduleName) then
        return false, string.format(ns.Localize(
            "module \"%s\" is switched off and cannot stand a subsystem of "
            .. "Darken down"), tostring(moduleName))
    end

    -- A subsystem already disabled does not go to a module. It was not
    -- replacement that disabled it: it raised itself, or stood itself down
    -- before a third-party addon that owns the same thing — and the core will
    -- not record an owner for it (below), which means nobody will be able to
    -- bring it back by this path. Marking it mute meanwhile would leave a
    -- trace no existing path clears.
    if ns.Registry:IsFailed(subsystem) then
        return false, string.format(ns.Localize(
            "Darken's own \"%s\" section is already switched off, so a "
            .. "module cannot stand it down"), subsystem)
    end

    local module = ns.Registry:Get(subsystem)
    if type(module) == "table" then
        module.standDown = true
    end

    local stood = ns.Registry:Disable(subsystem, string.format(ns.Localize(
        "One owner per frame: module \"%s\" draws this now, so Darken's own "
        .. "\"%s\" section stands down until that module gives it back."),
        tostring(moduleName), subsystem))

    -- An owner is recorded only for a real stand-down. A subsystem already
    -- disabled for another reason gets no owner — and nobody will be able to
    -- bring it back by this path.
    if stood then REPLACED_BY[subsystem] = moduleName end

    return stood
end

--- Bring a core subsystem back into service: a module no longer replaces it.
--
-- The return is not the clearing of a flag. A stand-down does three things
-- (tells the player, removes the settings section, stops calling the
-- subsystem), and the return has to undo all three — and beyond that, to
-- style what the subsystem styles. Permitting it to style "some time later"
-- is not enough here: the game's own bags, returned unstyled until the next
-- change of a setting, are not the bags the player had before the module was
-- installed, and the bags specification demands the opposite outright.
--
-- So the subsystem goes through exactly the path it goes through at login,
-- and the registry decides that (Registry:Resume): OnEnable only if it never
-- happened, or the event subscriptions and the hooks over game functions
-- would double — and ApplySettings after it. There is deliberately no second
-- path for the return: a subsystem that came back differently from the way it
-- is normally enabled would end up in a state that never occurs during a
-- normal load.
--
-- A refusal is returned as a value rather than raised, and there are exactly
-- three reasons for one: there is no such name; nobody took the subsystem;
-- another module took it.
--
-- @param subsystem string the core subsystem's name
-- @param moduleName string the name of the module returning it
-- @return boolean whether the subsystem came back into service
-- @return string|nil the reason for refusal
function ns.ResumeSubsystem(subsystem, moduleName)
    if type(subsystem) ~= "string" or not REPLACEABLE[subsystem] then
        return false, string.format(ns.Localize(
            "Darken has no subsystem named \"%s\" that a module may replace"),
            tostring(subsystem))
    end

    local owner = REPLACED_BY[subsystem]
    if owner == nil then
        return false, string.format(ns.Localize(
            "Darken's own \"%s\" section was not stood down by a module, so "
            .. "there is nothing to give back"), subsystem)
    end
    if owner ~= moduleName then
        return false, string.format(ns.Localize(
            "Darken's own \"%s\" section was stood down by module \"%s\", "
            .. "and only that module can give it back"),
            subsystem, tostring(owner))
    end

    -- The entry is cleared before the attempt rather than after. A
    -- subsystem that raises inside ApplySettings right now is disabled by the
    -- isolation — and it is then disabled by a failure rather than by
    -- replacement: a second return under the same name must be refused, or a
    -- player pressing a "try again" button and a module returning it would
    -- become two owners of one action.
    REPLACED_BY[subsystem] = nil

    local module = ns.Registry:Get(subsystem)
    if type(module) == "table" then
        module.standDown = nil
    end

    local alive = ns.Registry:Resume(subsystem)
    if not alive then
        -- The subsystem raised on its return. The addon is intact and so is
        -- the module: the failure has already been reported by the
        -- isolation's line. (The page that used to explain it and offer
        -- another attempt went with the old settings window; see
        -- Registry:Disable.)
        return false, string.format(ns.Localize(
            "Darken's own \"%s\" section did not start up again"), subsystem)
    end

    ns.Registry:Report(string.format(ns.Localize(
        "Module \"%s\" does not draw this any more, so Darken's own \"%s\" "
        .. "section is back and has been applied."),
        tostring(moduleName), subsystem))

    return true
end

--- Give back everything this module stood down.
--
-- Called by the registry at the moment a module is switched off: whether it
-- raised itself or ended some other way, the subsystem it was replacing has
-- to come back. Otherwise the worst outcome: the module stopped drawing while
-- the core never started, and the player is left without either until a
-- reload.
--
-- @param moduleName string the name of the module being switched off
-- @return number how many subsystems came back
function ns.ReleaseSubsystemsOf(moduleName)
    if type(moduleName) ~= "string" or moduleName == "" then return 0 end

    local count = 0
    for subsystem, owner in pairs(REPLACED_BY) do
        if owner == moduleName and ns.ResumeSubsystem(subsystem, moduleName) then
            count = count + 1
        end
    end
    return count
end

--- The name of the module currently replacing a subsystem.
-- An internal lookup for the tests and for the registry; not exposed.
-- @param subsystem string|nil
-- @return string|nil
function ns.SubsystemOwner(subsystem)
    return REPLACED_BY[subsystem]
end

-- The handle fields that belong to the core, and the contract version each
-- of them appeared in. A module may not write a core name; it may read them
-- as much as it likes. The list is explicit rather than derived from "what is
-- not nil": the optional fields (defaults, OnDisable) are absent from most
-- modules, and a computed list would let a write through to precisely those.
--
-- The version beside a name is the way to grow without breaking older
-- modules. The list used to be flat: every new handle method instantly became
-- a name the core took away from everybody at once, including those written
-- years before it appeared. The contract meanwhile kept promising the
-- opposite (API_MIN_VERSION = 1), and that promise broke in the loudest
-- possible way — a yellow Lua error in the body of somebody else's file, on
-- the line the contract itself tells them to write ("the handle is your place
-- for your own state"). The defect was not in the particular names but in
-- the fact that every next version would take new ones.
--
-- The rule now reads as one sentence: a module gives the core those names
-- that existed in the version it was written for. What appeared later stays
-- its own field, and a write simply shadows a method the module knew nothing
-- about. It may call everything meanwhile: the handle's surface is one for
-- all, and the version limits not access but ownership of a name.
local HANDLE_FIELD_VERSIONS = {
    name = 1, api = 1, defaults = 1, globals = 1, options = 1,
    OnEnable = 1, OnDisable = 1, ApplySettings = 1,
    GetSettings = 1, GetFrame = 1, OnRepaint = 1, Publish = 1,
    Refresh = 1, Apply = 1, IsEnabled = 1, Print = 1,
    RegisterEvent = 3, UnregisterEvent = 3, InCombat = 3,
    Secure = 3, RegisterStrings = 3, Localize = 3,
    RegisterCommand = 4, Replaces = 4,
    Migrate = 5,
    Releases = 8,
    Own = 15,
    Counters = 17,
}
ns.HANDLE_FIELD_VERSIONS = HANDLE_FIELD_VERSIONS

--- The core names forbidden to a module of the declared version.
--
-- The set is assembled afresh on every call rather than taken from a cache:
-- the call happens once per module registration, while a cache would outlive
-- an edit to the version map and would hide from the tests precisely the case
-- the version stands here for.
-- @param version number|nil the version the module declared (the current one
--        by default)
-- @return table a set of names
function ns.ReservedHandleFields(version)
    if type(version) ~= "number" or version ~= version then
        version = API_VERSION
    end

    local reserved = {}
    for field, introduced in pairs(HANDLE_FIELD_VERSIONS) do
        if introduced <= version then reserved[field] = true end
    end
    return reserved
end

-- The whole set of core names as of today: the tests and the documentation
-- use it. It does not concern a live module — ns.ReservedHandleFields answers
-- to that one.
ns.RESERVED_HANDLE_FIELDS = ns.ReservedHandleFields(API_VERSION)

-- The storage scopes a module may ask GetSettings for.
--
-- Three, and that is a decision rather than the beginning of a list.
-- "profile" is the settings: their whole point is to switch along with
-- everything else, and it is the default. "global" is per-account data: the
-- item database across every character lives that way, and a profile would be
-- the wrong lifetime for it — switching profiles would swap the collected
-- index. "char" (version 6) is one character's state: what has to differ
-- between alts under a shared profile.
--
-- It used to be written here that char is expressible as a key inside global
-- and is therefore unnecessary. On a live module that turned out to be
-- exactly half wrong: expressible it is, but the character's key has to be
-- assembled first, and assembling it means asking the game for a name, a
-- realm and a faction and writing a second "one per character" mechanism
-- beside AceDB. The first time, that workaround cost the player a setting
-- that was called "this character's" and switched off for all of them at
-- once.
--
-- AceDB has two more scopes, realm and class, and they are still not taken
-- here: there is no case for them, and every scope in the contract is a
-- promise forever.
local SCOPES = { profile = true, global = true, char = true }

local function buildHandle(descriptor)
    local name = descriptor.name

    -- The core names are taken by the version the module declared: see the
    -- map above.
    local reserved = ns.ReservedHandleFields(descriptor.api)

    local fields = {
        name          = name,
        api           = descriptor.api,
        defaults      = descriptor.defaults,
        globals       = descriptor.globals,
        options       = descriptor.options,
        OnEnable      = descriptor.OnEnable,
        OnDisable     = descriptor.OnDisable,
        ApplySettings = descriptor.ApplySettings,
    }

    --- The module's own settings table.
    -- A module creates no saved variables: its data lies in the core's
    -- database under its own name. The "profile" scope (the default) switches
    -- along with the core's profile, "global" lives for the whole account,
    -- and "char" (version 6) is one per character.
    --
    -- Defaults are declared only for profile (descriptor.defaults) and global
    -- (descriptor.globals). There are deliberately none for "char": what is
    -- declared as a default AceDB cleans out of the saved file at logout,
    -- while a character scope exists precisely to keep the answer this
    -- character gave themselves. A default for such a field is the value the
    -- module reads emptiness with, and it lives in the module.
    --
    -- nil means the database is not there yet (or no longer): the core did not
    -- start on an unsupported client. Checking for nil in ApplySettings is
    -- mandatory — as the core's own subsystems do.
    -- @param scope string|nil "profile" (the default), "global" or "char"
    -- @return table|nil
    -- @return string|nil the reason when there is no table
    function fields:GetSettings(scope)
        scope = scope or "profile"
        if not SCOPES[scope] then
            return nil, string.format(ns.Localize(
                "Darken has no settings scope named \"%s\""), tostring(scope))
        end

        local addon = ns.Addon
        local db = addon and addon.db
        local section = db and db[scope]
        if type(section) ~= "table" then return nil end

        local own = section[name]
        if type(own) ~= "table" then
            own = {}
            section[name] = own
        end
        return own
    end

    --- An object the core or another module owns.
    -- @param key string a key from docs/module-api.md, or one a module
    --        published
    -- @return table|nil
    function fields:GetFrame(key)
        return ns.Frames.Get(key)
    end

    --- Subscribe to an object's repaint.
    -- The handler is called with (frame, key) after every repaint, and
    -- immediately on subscribing when the object already exists.
    -- @param key string
    -- @param fn function
    -- @return boolean whether the subscription was accepted
    function fields:OnRepaint(key, fn)
        return ns.Frames.Subscribe(key, name, fn)
    end

    --- Expose one's own object to the neighbours.
    --
    -- The showcase was one-way: the core showed, the modules looked. For
    -- three modules in the catalogue that is not enough — they own frames
    -- themselves and will want to decorate each other, and without this door
    -- they would have to agree through global names, that is, outside the
    -- contract.
    --
    -- A key must start with the module's own name: the name itself, or the
    -- name followed by a dot and anything. Otherwise the first module along
    -- would declare itself under a core key and substitute the core's object
    -- for its neighbours.
    -- @param key string
    -- @param frame table|nil the object itself
    -- @return boolean whether the key was accepted
    function fields:Publish(key, frame)
        if type(key) ~= "string" then return false end
        if key ~= name and key:sub(1, #name + 1) ~= (name .. ".") then
            return false
        end

        ns.Frames.Repaint(key, frame)
        return true
    end

    --- Mark an object as one's own.
    --
    -- Needed in exactly one case, and the case is worth naming: the module
    -- created an object of its own — a texture, a label, a frame — ON A
    -- FOREIGN FRAME. Such an object is indistinguishable from a native one to
    -- anybody walking a foreign frame top to bottom, and the core has such a
    -- walk: the dimming subsystem paints the interface chrome, deciding by a
    -- texture's appearance. Your texture would get it as a second owner: it
    -- would remember your colour as the native one, you would recolour the
    -- object by your own rule, and the next movement of the slider would
    -- return it to what was remembered. Neither an error nor a line in chat —
    -- the colour is simply wrong.
    --
    -- The marker does not say "do not touch this frame". It says one thing:
    -- this object belongs to the module rather than to the game. The core's
    -- subsystems that style what is foreign skip it; the marker does not
    -- extend to the foreign frame the object lies on.
    --
    -- It is cleared by the same call: handle:Own(object, false). Clearing is
    -- mandatory when the object is given back to the game or extinguished for
    -- good — a switched-off module must leave nothing of its own on a foreign
    -- frame, and the marker here is no different from the opacity you
    -- overwrote.
    --
    -- @param object table|nil the object the module created
    -- @param owned boolean|nil false clears the marker; anything else sets it
    -- @return boolean whether the object was accepted
    function fields:Own(object, owned)
        if type(object) ~= "table" then return false end

        if owned == false then
            object[OWNED_FIELD] = nil
        else
            object[OWNED_FIELD] = true
        end
        return true
    end

    --- The table of work-done counters.
    --
    -- Why it exists. A subsystem that silently did nothing is
    -- indistinguishable from a working one from outside: there is no error,
    -- the addon does not fail, nothing on screen simply changed. A counter is
    -- the only way to tell one from the other in a live client, and the author
    -- will be able to read it with one command (/darken report) and from the
    -- saved file.
    --
    -- The table itself is returned rather than an "add one" function: a
    -- counter sits on paths measured in microseconds, and a function call in
    -- such a position costs more than everything it counts. Take it once
    -- while your file is read, into a local, and write by integer addition
    -- from then on:
    --
    --     local counters = module:Counters()
    --     counters.plates = counters.plates or 0   -- claim the counter
    --     ...
    --     counters.plates = counters.plates + 1    -- on the hot path
    --
    -- Claiming the counter is mandatory, and mandatory while the file is read.
    -- The core reads an unclaimed counter as "this subsystem is not in the
    -- build" and a claimed zero as "the subsystem is there and did nothing";
    -- without the first line your inaction would look like the module's
    -- absence.
    --
    -- The keys are documented in Core/Tally.lua and belong to the core. A key
    -- the core does not know is not lost: it enters the report as a section of
    -- its own. The table is shared by the whole addon — write only your own
    -- counters, and only by addition.
    --
    -- @return table the table of numbers
    function fields:Counters()
        return ns.Counters
    end

    --- Subscribe to a game event.
    --
    -- There is one receiver for the whole addon and it belongs to the core,
    -- while a module's handler is called through the same guard as everything
    -- else foreign: a handler that raises disables its own module and brings
    -- down neither the core nor its neighbours. A frame of your own with a raw
    -- SetScript("OnEvent") gives no such guard — there an error becomes a
    -- yellow Lua line in the middle of combat.
    --
    -- The subscription is removed by itself when the core disables a module:
    -- the rule "a switched-off module must stop listening" is enforced by the
    -- core rather than by the author's memory.
    --
    -- One handler per event-and-module pair: subscribing again replaces the
    -- previous handler rather than adding a second.
    -- @param event string the game event's name
    -- @param fn function the handler; called with (event, ...)
    -- @return boolean whether the subscription was accepted
    function fields:RegisterEvent(event, fn)
        return ns.Events.Subscribe(event, name, fn)
    end

    --- Remove one's own subscription to an event.
    -- @param event string
    -- @return boolean whether there was a subscription
    function fields:UnregisterEvent(event)
        return ns.Events.Unsubscribe(event, name)
    end

    --- Whether combat is in progress right now.
    -- Outside the game there is no combat. A question of its own rather than
    -- only Secure: some work is cheaper to skip than to defer (a slot that
    -- will be redrawn on the next event anyway).
    -- @return boolean
    function fields:InCombat()
        return ns.Combat.InCombat()
    end

    --- Do work on an object the engine may forbid during combat.
    --
    -- What is deferred is the pair "combat is in progress AND the object
    -- answers IsProtected": nobody forbids touching an ordinary frame in
    -- combat, and deferring would make a module sluggish for nothing.
    --
    -- The key says what exactly is deferred ("slot 3's attribute"). Writing
    -- again under the same key displaces the previous action while keeping its
    -- place in the queue: ten edits of one object during combat give one
    -- application when it ends — the final state rather than the whole
    -- history in jolts.
    --
    -- Each module's queue is its own and locked to its name: somebody else's
    -- deferred work cannot be reached.
    -- @param object table|nil the object being worked on
    -- @param key string the queue key
    -- @param action function the action
    -- @return boolean whether it ran immediately (false means deferred until
    --     combat ends)
    -- @return string|nil the reason when the work was not accepted at all
    function fields:Secure(object, key, action)
        return ns.Combat.Secure(name, object, key, action)
    end

    --- Declare one's own strings in one language.
    --
    -- The model is the core's, and that is the point: the translation key is
    -- the English string itself, so an untranslated place stays readable. The
    -- client's language is determined by the core — two determinations would
    -- diverge, and a module would speak a different language from the
    -- settings window.
    --
    -- The table is copied: it stays yours and the core has its own.
    -- @param locale string the locale's name as GetLocale() spells it
    -- @param translations table key (the English string) -> translation
    -- @return boolean whether the strings were accepted
    function fields:RegisterStrings(locale, translations)
        return ns.RegisterModuleStrings(name, locale, translations)
    end

    --- Translate one's own string.
    -- With no translation the key itself is returned, that is, the English
    -- label. Other modules' strings are not visible here: the dictionary is
    -- locked to the module's name.
    -- @param key string|nil the English key string
    -- @return string
    function fields:Localize(key)
        return ns.LocalizeFor(name, key)
    end

    --- Claim a slash command.
    --
    -- The word is issued by the core rather than by the engine directly, for
    -- two reasons. First: the core alone sees everyone who already claimed a
    -- word, so the second claimant is refused and told the first one's name
    -- instead of being silently displaced. Second: the handler is called
    -- through the same guard as OnEnable and ApplySettings — a command that
    -- raises disables its own module in one line rather than becoming a
    -- yellow Lua line labelled Darken.
    --
    -- The word is passed without a slash: bags, not /bags.
    -- @param word string the command's word
    -- @param fn function the handler; called with the remainder of the text
    -- @return boolean whether the command was accepted
    -- @return string|nil the reason for refusal
    function fields:RegisterCommand(word, fn)
        return ns.RegisterModuleCommand(name, word, fn)
    end

    --- Declare that the module replaces a core subsystem with itself.
    --
    -- The core styles the standard nameplates and the standard bags — both
    -- remain useful, because not everybody installs a separate module. But
    -- where a module is installed, one frame must not have two owners: one
    -- paints, the other repaints, and that shows as flicker.
    --
    -- It is the core that yields, not the module. The specification says so
    -- and so does common sense: the styling is a fallback for those without
    -- the module, while a module is installed deliberately, as a folder of
    -- its own. The subsystem is stood aside with one line in chat, its
    -- settings section disappears, and it is not called again until the
    -- interface is reloaded.
    --
    -- This is to be called when the module actually starts drawing rather
    -- than while its file loads: a module switched off in the settings
    -- replaces nothing, and standing the core's styling down for its sake
    -- would be direct harm.
    --
    -- Not everything can be replaced. The names accepted today:
    -- "nameplates", "bags".
    -- @param subsystem string the core subsystem's name
    -- @return boolean whether this call stood the subsystem down
    -- @return string|nil the reason for refusal
    function fields:Replaces(subsystem)
        return ns.StandDownSubsystem(subsystem, name)
    end

    --- Give a core subsystem back: the module no longer replaces it.
    --
    -- The other side of handle:Replaces, and it has to exist. A player who
    -- switched the replacement off expects what was there before it was
    -- switched on — and before that the game's own bags wore the core's
    -- styling. A return deferred until the interface is reloaded means
    -- "switched it off and things did not go back", that is, a setting that
    -- does not undo.
    --
    -- What comes back is the styling rather than a flag: the subsystem goes
    -- through the same path it goes through at login and applies its settings
    -- at once. Its settings section comes back, and an open settings window
    -- repaints — that is part of the return too.
    --
    -- Only the module that took a subsystem may give it back. Somebody else's
    -- return is refused and told the real owner's name: otherwise one module
    -- would resurrect the core's styling on top of another that is drawing
    -- instead of it right now.
    --
    -- This is to be called when the module actually stopped drawing. A
    -- switched-off module need not call it at all: the core gives back what it
    -- stood down itself, at the same moment it switches the module off.
    --
    -- @param subsystem string the core subsystem's name
    -- @return boolean whether the subsystem came back into service
    -- @return string|nil the reason for refusal
    function fields:Releases(subsystem)
        if ns.Registry:IsFailed(name) then
            return false, string.format(ns.Localize(
                "module \"%s\" is switched off; Darken has already given "
                .. "back what it stood down"), name)
        end
        return ns.ResumeSubsystem(subsystem, name)
    end

    --- Bring one's own saved data to the present form.
    --
    -- A module's settings lie in the core's database, but the form of the data
    -- the module writes into it belongs to the module. That form will have to
    -- change: a player who installed the module a year ago has in their saved
    -- file what the module wrote a year ago, and a saved file outlives any
    -- update of ours.
    --
    -- The very function the core has brought its own settings over with since
    -- the first schema is exposed (ns.MigrateProfile, Core/Defaults.lua)
    -- rather than a similar one beside it: two data-migration mechanisms would
    -- diverge silently, and would diverge in the place where a mistake is seen
    -- not at once but a release later.
    --
    -- The rule: the form's version lies in the data itself as a `version`
    -- field, the migrations are a table of "version -> a function bringing the
    -- data to the next version", and only this call sets the version field.
    --
    -- Data without a number in `version` counts as fresh and simply receives
    -- the target version — that is, the form is numbered from its very first
    -- record. Data with a version above the target is not touched: that
    -- happens when a module is rolled back to an older build, and corrupting
    -- it then is not allowed.
    --
    -- The `version` field must not be in a module's defaults or globals. At
    -- logout AceDB cleans out of the saved file everything equal to a declared
    -- default, so a version declared as a default would never be saved: on
    -- every load it would again equal the target, and data of an older form
    -- would be read as new — a silent corruption.
    --
    -- A refusal is returned as a value rather than raised. A migration step
    -- may be missing (a typo in the table, a skipped number), and the core may
    -- not break somebody else's addon's loading over that.
    -- @param data table the saved data, with a `version` field
    -- @param migrations table [version] = function(data)
    -- @param target number the form's target version
    -- @return table|nil the same data, brought to the target version
    -- @return string|nil the reason for refusal
    function fields:Migrate(data, migrations, target)
        if type(data) ~= "table" then
            return nil, ns.Localize("the data to migrate must be a table")
        end
        if type(migrations) ~= "table" then
            return nil, ns.Localize("the migrations must be given as a table")
        end
        if type(target) ~= "number" or target ~= target then
            return nil, ns.Localize(
                "the target format version must be a number")
        end

        local ok, result = pcall(ns.MigrateProfile, data, migrations, target)
        if not ok then return nil, tostring(result) end

        return result
    end

    --- Apply the whole addon's settings.
    -- The same path login and a profile switch take: every module's
    -- ApplySettings. Called after a setting was changed by hand — then what
    -- changes may be more than what the module edited.
    -- Re-entry is forbidden by the registry: a Refresh from one's own
    -- ApplySettings does not recurse but simply does nothing.
    function fields:Refresh()
        return ns.Registry:ApplyAll()
    end

    --- Apply only this module's settings.
    -- For modules that redraw themselves on a game event: the nameplate
    -- engine has no reason to drive a settings pass across the whole addon for
    -- every unit that appears. The path is the same — its own ApplySettings.
    function fields:Apply()
        return ns.Registry:ApplyOne(self)
    end

    --- Whether the module works right now.
    -- The core stops calling a module that raised, but the module would keep
    -- calling outwards: a per-frame subscription, a hook on a foreign frame, a
    -- timer. This question and OnDisable are the two ways to learn that it is
    -- time to stop.
    -- @return boolean
    function fields:IsEnabled()
        return ns.Registry:IsEnabled(self)
    end

    --- A line in chat on the module's behalf.
    -- The name in square brackets is placed by the core: the player must see
    -- who is speaking, and a module cannot forge that attribution.
    -- @param text string
    function fields:Print(text)
        say(string.format("[%s] %s", name, tostring(text)))
    end

    local handle = setmetatable({}, {
        __index = fields,

        -- A module's author keeps their own state here too, and that is
        -- still legitimate: only the core's fields are refused — and only
        -- those of them that existed in the contract version the module
        -- declared.
        __newindex = function(self, key, value)
            if reserved[key] then
                error(string.format(ns.Localize(
                    "the field \"%s\" on an Darken module handle belongs to "
                    .. "the core and cannot be assigned"), tostring(key)), 2)
            end
            rawset(self, key, value)
        end,
    })

    return handle
end

--- Register a module.
-- The only entry point for foreign code.
--
-- The load order is such that a third-party module almost always arrives
-- after the core has created the database and declared its settings: the game
-- initialises the core on the core's own ADDON_LOADED, that is, before it
-- starts reading a dependent addon's files. So a "late" registration is the
-- ordinary case rather than a rare one, and it carries a module's settings
-- through to the live database.
--
-- @param descriptor table the descriptor: name, api and the optional
--        defaults,
--        globals, options, OnEnable, OnDisable, ApplySettings
-- @return table|nil the module's handle on success
-- @return string|nil the reason for refusal
function Api:RegisterModule(descriptor)
    -- A dotted call, Darken.RegisterModule(t), is accepted too: a typo in
    -- one character must not cost a module's author an hour.
    if descriptor == nil and type(self) == "table" and self ~= Api then
        descriptor = self
    end

    local ok, reason = ns.CheckModuleDescriptor(descriptor)
    if not ok then
        local text = string.format(ns.Localize("Darken rejected a module: %s"), reason)
        say(text)
        return nil, reason
    end

    local handle = buildHandle(descriptor)

    -- An options section IS NO LONGER SHOWN as a tree.
    --
    -- There is no tree: the window moved to pages declared as data
    -- (Options/Schema.lua), and those are what it draws. A module that
    -- brought only `options` gets no settings in the window — and it has to
    -- learn that here rather than from the silent absence of its own section.
    --
    -- The field is still accepted and still validated: the core may not break
    -- somebody who came to it with an older contract. It simply draws
    -- nothing, and that is said out loud once.
    if handle.options then
        ns.GuardOptions(handle.name, handle.options)

        if not ns.toldAboutOptions then
            ns.toldAboutOptions = true
            local addon = ns.Addon
            if type(addon) == "table" and type(addon.Print) == "function" then
                addon:Print(string.format(ns.Localize(
                    "module \"%s\" brings an options section, and this "
                    .. "version does not draw one: the settings window "
                    .. "builds its pages from the schema instead. The "
                    .. "module works; its settings are simply not shown."),
                    tostring(handle.name)))
            end
        end
    end

    ns.Registry:Register(handle)

    -- The default settings: into the live database when it already exists.
    -- When it does not yet, Core/Init.lua collects them while creating the
    -- database, in its general pass over the registry.
    --
    -- Both scopes are declared, and declared even when empty — for a module
    -- without defaults too. The reason lies in how AceDB works: at logout it
    -- cleans out of SavedVariables everything equal to a declared default,
    -- an empty table included, but only if it knows about that table. A module
    -- without defaults used to receive a fresh empty table from GetSettings,
    -- that table landed in the profile outside what was declared,
    -- removeDefaults did not touch it, and it stayed in DarkenDB forever —
    -- litter that outlives the module's removal.
    if type(ns.InjectModuleDefaults) == "function" then
        local okDefaults, defaultsErr = ns.InjectModuleDefaults(
            descriptor.name, handle.defaults or {}, handle.globals or {})
        if not okDefaults and defaultsErr then
            -- The database rejected the module's defaults. It is registered
            -- but has nothing to work with: it is disabled by the same road a
            -- module that raised takes, and with the same single message.
            ns.Registry:Disable(descriptor.name,
                ns.ModuleFailureText(descriptor.name, "defaults", defaultsErr))
            return nil, defaultsErr
        end
    end

    -- The settings used to be rebuilt here when the tree was already
    -- declared.
    --
    -- Under pcall, and that was not belt and braces. Registry:Disable calls
    -- the same function equally guarded, while here there was no guard: an
    -- error while assembling the tree (a neighbouring module's section, a
    -- library that went missing) would be raised out of RegisterModule
    -- straight into the body of somebody else's addon file and would abort its
    -- loading halfway. The core may not break whoever came to it.
    -- An open window now repaints by itself: the pages are declared as data,
    -- and the module that arrived added its rows to the same schema. There is
    -- nothing left to rebuild as before — there is no tree.
    if type(ns.Window) == "table" and type(ns.Window.Repaint) == "function"
    then
        pcall(ns.Window.Repaint)
    end

    -- Enabling: if the core has already enabled its modules, this one is
    -- enabled on the next frame rather than here.
    --
    -- That frame is a matter of the contract rather than a detail of the
    -- implementation. While enabling happened from here, a module's handlers
    -- ran before the call returned the handle, and the variable the author
    -- assigns it to was still nil at that moment. See Registry:EnableLater:
    -- what that cost ten modules is written there.
    ns.Registry:EnableLater(handle)

    return handle
end

-- The addon's only global object, DarkenDB aside. The name is written
-- literally rather than computed from ADDON: a global is looked for by
-- searching the code, and a computed name does not turn up in such a
-- search.
Darken = Api
