# What changed

What is recorded here is what the player can see. Rearrangements inside
the code do not make it in: a changelog is read to decide whether an
update is worth taking, not to learn how the addon is put together.

The number here is the addon's, the one in the TOC. Two other numbers in
this project are not it and never move with it: the version in the head
of LICENSE belongs to the licence text, and `Darken.API_VERSION` belongs
to the contract a module is written against.

## Unreleased

**A supported addon is darkened all the way through.** Rack did not
darken at all, because its bar is a one-by-one anchor with no picture
on it and all its artwork sits on buttons named after that same bar -
which the rule that keeps other addons' pins off the game's map was
reading as "somebody else's picture on our window". An addon we know
is now ours to paint wherever its frames are. An addon we do not know
is still left alone at every depth, which is what keeps those pins
off the map.

**Supported addons are darkened with the game, out of the box.**
Bartender4, Rack, Hive and Leatrix Plus are known to the addon now,
and their windows darken along with the game's on a fresh install.
The row in the settings is named for what it covers - "Supported
Addons' Windows" - and one click still sets it back to the game's own
look.

An addon nobody named is left alone, and that is not a contradiction:
the promise simply moved. It used to be this row's default, because
the row meant every addon at once and therefore had to be off. It is
now the list - the pass goes into a window of another addon only after
asking whose it is and finding that addon among the ones whose source
we have read. Everything else is not reached at all, whatever the row
is set to.

The names were read out of each addon's own source and are cited where
they are written down, one line each.

**Windows are dark before they open.** Until now the darkening found
its work by walking the interface, and the walk does not enter what is
hidden - which is its largest saving and also why a window darkened at
the moment it opened rather than before. The framing the addon can
name is now painted straight away, with no walk and no waiting for the
window to be shown. What the names do not cover the walk still finds,
and what counts as framing is decided by exactly the same rule as
before: only the finding changed.

A picture painted by name carries the area and the window it belongs
to, the same two answers the walk gives: the chat, the bags, the
tooltips and the map keep the settings the player set for them, and a
window keeps its row in the list of exceptions.

The names are the game's own, and the list covers far more of them
now: the windows this client really has, taken from the catalogue the
walk built over past sessions, plus the window names the game is known
to use, multiplied by the handful of paths it keeps a window's framing
in - and a short list of parts that belong to one window only. The
report counts what was painted that way, so how far the naming has got
is a number rather than an impression.

No window of another addon is on that list, and the rule rather than
the list is what guarantees it: before a named window is painted, the
same question the walk asks - whose frame is this - is put about it,
once per window. A name that should not be there is inert rather than
harmful.

**The minimap's icons stopped stuttering.** Questie writes to its pins
as the player walks, and every such write made us climb up to six
generations of frames through protected calls looking for the area
that picture belongs to - find nothing, remember nothing, and do it
all again on the next frame. The minimap is a type the addon skips
whole, so the answer was always "nothing"; it simply had no way of
saying so to that second road into a picture. Now it does, and so does
every frame of another addon: the climb turns back at the threshold,
and an answer of "nothing here" is remembered instead of being
re-derived for ever.

**The report says where the game's repainting lands.** "Repaints
Heard" was one number for everything - a hundred and thirty-six
thousand in one session - and one number cannot be acted on: the
watcher sits on the shared method table of textures, so it hears
Blizzard's own animations and every other addon as well as the
pictures we painted. It is now split into what was heard, what landed
on a picture of ours, and which window each of those was in.

## 1.0.4

Five of these came from one review on CurseForge and from the author
playing with the addons that review named. The theme they share is
one sentence: an addon touches what the player gave it and nothing
else.

**Other addons' windows are recognised properly, and so left alone.**
The setting that keeps them untouched has been there all along; what
failed was telling them apart. A window was judged somebody else's by
its name beginning with that addon's folder name, which misses
whenever the two are spelled differently - RXPGuides names its frames
RXPG_something, so none of them was recognised and they darkened with
the game's windows. The client is now asked instead: it records which
addon set a global, and that is the direct answer to whose frame this
is. The old guess is kept behind it for frames that never went into a
global of their own.

**The chat is left to the addon that owns it.** With Prat, Chatter,
Glass, BasicChatMods or ElvUI loaded, Darken no longer writes the
chat's font objects and gives them back the font they had. Prat never
sets a font on the chat itself - it calls the game's own
FCF_SetChatWindowFontSize, which reads whatever font the frame
currently has and writes it back with Prat's size - so Darken's font
reached the chat through Prat's own hands, and every change of any
Darken setting did it again. An addon that owns the chat and is not on
that list still gets our font; the report counts the standing down, so
the answer is there to read rather than guess at.

**Another addon's pictures on the game's windows are left alone.**
Questie's quest pins on the world map were painted black. They are
frames of Questie's placed on the map's canvas, and their picture has
no name and no path we could recognise, so every rule for telling
framing from contents answered "framing". A frame that belongs to
another addon and sits inside a window of the game's is now left
untouched with everything under it - a pin, a marker, an overlay. At
the top of the tree a frame of theirs is still their window, which the
"other addons' windows" setting goes on governing.

The report counts what was left that way, so a pin still dark has an
answer rather than a guess.

**The minimap belongs to whoever the player gave it to.** Darken's
square minimap is off by default, and "off" was written down as "cut
it round and show the round border" - so every login undid a square
minimap set in another addon. Nothing is written now until the square
is asked for, and what is put back is only what we took.

The same line was behind quest objectives flickering on the minimap.
A square map that does not say it is square leaves the libraries that
place things on it - HereBeDragons for Questie's objectives, LibDBIcon
for the buttons - clipping to a circle: an icon near a corner is
inside the map and outside the circle, so it is hidden, shown, hidden
again as the player walks. Darken now answers GetMinimapShape while
the square is its own, and gives the former answer back when it is
not.

**The report says what the darkening cost at login.** Players report a
hitch on entering the world, and nothing in the addon could say
whether it is ours: the walk is cut into slices of three milliseconds
a frame so that it should not be felt, and "should not be" is not a
measurement. The saved file now carries three numbers for the walk
that runs at login - how many slices, how long together, the longest
one - and they are of that login alone.

## 1.0.3

Everything here was reported from a live game, most of it with a probe
of the window in question attached. Where a name of the client's
appears in a rule below, it was read off one of those probes.

**The red frame of a unit in combat stays red.** The client keeps two
variants of a unit frame and swaps between them while that unit is
fighting; the second one is red, and red is the whole of what it says.
Darkened, both came out the same near-black, so the swap stopped being
an answer and became a flicker. The combat variant is left alone now,
for every unit frame that has one; its ordinary twin is the same metal
as the rest of the interface and goes on darkening. The flash of a
swinging autoattack is spared with it, for the same reason.

**Text on parchment is readable** - the quest window, the quest panel
inside the world map, books, letters and the trainer's text. All of it
is dark ink meant for a light page, and it was left dark on a darkened
one. It is painted at the source now: the game keeps one font object
per kind of text, and one call colours every label that uses it,
including the ones not on screen yet. Turning the darkening off gives
each object the ink it had. Gold and white text is left alone - those
colours are how the game tells one kind of line from another, and they
read on a dark page already.

**A quest read off the map is readable the first time.** It coloured
nothing until something else happened to come along - open it again
and it was white. Two causes, both gone. A page the addon has just
found now raises its own text instead of waiting for an announcement,
and the addon stands after the game's own filling of a quest page -
the one moment both roads into a page have in common, and the moment a
heading is set black by hand over the font object, which is why a page
could come out with a light body and a dark heading.

**Quest markers stay bright.** The bang, the question mark, the
turn-in and the number on a map pin say what a quest is and what state
it is in; darkened they were identical grey blobs and the tracker
stopped saying which line was ready to hand in. They are spared now.
The quest log's own frames, tiles and backgrounds carry the same word
in their names and still darken, because they are framing.

**A window that was shown could stay bright.** The watcher that
catches a window appearing tested a boolean the game had handed it,
and on this client that boolean is sometimes a protected value which
cannot be tested at all. The test threw, the throw happened inside the
watcher, and the walk that was to follow never ran - so the window
kept the colours it opened with. A value that cannot be read now
counts as shown: walking a frame that was hidden costs one pass and
shows nothing, while skipping one that was shown is the bug.

## 1.0.2

**The character sheet's golden slot frames darken.** The rule that spares
an item's icon works by asking the frame which of its pictures is the
icon - and today's templates keep their own artwork in a field of that
name too, so the model's turn buttons, a stat bar and the slot frames
were all spared as though they were a player's face. A picture that
comes from an atlas is framing, whatever field holds it: an item's icon
and a portrait always arrive as files.

**Dimmed icons keep their shade.** The shade was written and lost: the
author's probe read every texture of a button at 0.27 and the icon at
1.00. The game does not reach an icon through anything an addon can sit
on - it takes it by name inside its own repaint and writes there - so
that repaint is what is hooked now, once, for every button. White means
"usable, nothing to report" and is ours to overwrite; the blue of not
enough mana and the grey of unusable are answers to the player and keep.

**The minimap buttons are left where their own addons put them.** 1.1.0
moved them to the edge of a square minimap, on the sound argument that
having made the map square we owed them a sensible place. The execution
was not sound: they are placed once, and the addons that own them place
them again afterwards by their own angle around a circle. A placement
that is overwritten a moment later is worse than none, because it looks
like a bug in whichever addon loses. Removed rather than left half
working.

The square map and its edge stay.

**The report counts dimmed icons.** Five attempts at "the icons are not
dimmed" went by without anybody establishing whether the setting was on,
because nothing counted it. Now something does, and a zero beside a
ticked box means something quite different from a zero beside an
unticked one.

**"Dim the Icons Too" now actually dims them.** It was written to yield
to the game, on the grounds that the game colours an icon to tell you
something - red out of range, grey when unusable. True, but it misses
that a usable spell is coloured plain white on every update of the
button, and white is not a message, it is the lack of one. The shade was
wiped within a frame of being applied, on exactly the icons the setting
exists for. Now white is the one state the shade overwrites; red and
grey keep, so out of range and unusable read exactly as the game meant.

**The texture lists show the textures.** Choosing between "Darken
Purple" and "Darken Pink" by their names asks a word to do the one thing
a word cannot. Each row of the health and power bar texture lists now
carries a strip of the texture itself, drawn from the same place the bar
gets it - so what the list shows and what the bar gets are one answer,
not two. The game's own entry has no strip, because there is no file of
ours behind it.

**Spell icons can be dimmed with everything else.** The dimming has
always spared them on purpose - an icon is how a spell is recognised,
the same rule that spares gold, silver and copper - and that is still
what a fresh install does. "Dim the Icons Too", on the Icons page, is
how the decision gets overruled by whoever wants it overruled. The shade
follows the dimming slider, so the picture never sits darker or lighter
than the window around it. The game still colours an icon red out of
range or grey when unusable: that is the game answering you, and it
wins.

**The white edge around action buttons is gone.** It was the button's
own bevelled frame, and the addon had been losing a race for it: the
game writes that colour inside its own update, we answered on the next
frame, and we were always one frame late - the fifty-seven thousand
repaints the report counts in a session were that race. A race over one
texture is not winnable by being quicker, so the frame is taken out of
it: with "Outline Icons" on, the game's frame is hidden the instant the
game sets it, and the edge of a button becomes the addon's own line.
Turn the setting off and the game's frame comes straight back.

**The buttons around a square minimap stand along its edge.** They sat
on a circle because the map was a circle, and the map stopped being one
by our doing - so where they land is ours to answer for. Only other
addons' buttons are moved, each remembers the place it actually had, and
turning the square off puts every one of them back.

**A square minimap gets an edge.** Hiding the round ring and stopping
there left the map a bare rectangle of terrain with nothing to say where
it ends. It is now bordered with the same line that goes around an icon,
so the two read as one addon rather than two ideas. Turning the square
off takes the line away and gives the game its ring back.

**The round ring around a square minimap is gone.** The map was already
cut square; the ring stayed because the names it was looked up by do not
exist on this client line. The report said so plainly - "group
minimap-ring resolved to nothing" - and the client's own list named what
is really there: the compass art. Both names are now tried, and the ones
used before are kept behind them for the lines that have them.

**The minimap-button rounding is gone from the window.** Unticking it
set an empty mask, which on this client means "no mask" rather than "the
mask you had", so a button it had rounded came back square by our doing.

**The icon settings can work at all now.** Everything on that page rests
on finding a button's icon, and it was looked for only in a field on the
button. The older templates keep it nowhere but in a global named after
the button, and on such a client the outline and the trimming both did
nothing whatever was ticked. The icon is now looked for in both places.

**The report tells the three icon jobs apart.** Outlining, trimming and
rounding the minimap buttons all added to one number, so that number
proved nothing about any of them - and was read three times as proof of
the wrong one. Each has its own count now.

**The minimap can be square.** The setting promising it had been in the
window for a long time with nothing behind it - it wrote the key that
rounds the buttons other addons put around the minimap, and the shape of
the map was touched by nothing at all. It is a setting of its own now,
on the Icons page, and the round ring is taken away with the same tick
so it does not lie across the corners.

**The outline around icons became visible.** It was drawn around the
button instead of around the icon: a near-black hairline against the
bar's own dark art, at a UI scale below one. It was there and nobody
could see it. Against the icon the same line is what it was meant to be.

**The settings window stopped lying about the minimap.** The tick read
"Square Minimap" and did something else entirely; it now says what it
does - "Round the Minimap Buttons".

**The report counts one more thing.** How often the game repainted
something after us and the watcher meant to notice it did. A zero there,
while the screen is plainly being redrawn, names the cause of several
things that stay bright - which until now could only be guessed at.

## 1.0.1

Four things the player could see, all of them reported from a live game.

**Money stopped going black.** Gold, silver and copper were darkened into
three identical dark circles, so a price said how much but not of what.
The rule that should have spared them had been there all along and never
fired once: it was written about the path to a texture's file, and this
client answers with a file number instead, for every texture in every
window. A coin is now recognised by the frame holding it, which is named
the same in every build.

**Lines in a conversation stopped being left dark.** A guard with fifteen
options showed the first and left fourteen unreadable; a trainer's single
option looked doubled. One defect, not two: the pass that lifts dark text
out of a darkened page also takes its shadow off, so a line it never
reached kept both the dark colour and the shadow smearing it. It ran in
the same frame as the game's own "here is the page" event, which is to
say sometimes before the page existed. It now returns once the game has
finished writing.

**A refilling window stopped stuttering.** Raising a profession by one
point, or buying from a vendor, repainted the whole window once per
event - and those events arrive in bursts, several per action. A burst
now costs one repaint instead of one each.

**The addon stopped naming a file that does not exist.** Asked for a bug
report, it said to send `DarkenDB.lua`. `DarkenDB` is the variable; the
file is `Darken.lua`, under `SavedVariables`. Anyone who followed the
instruction went looking for nothing.

## 1.0.0

The first release. Everything the addon does is new, so there is nothing
here to compare it against - the README describes what it is. From the
next version on, this file lists what changed.
