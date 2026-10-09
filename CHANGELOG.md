# What changed

What is recorded here is what the player can see. Rearrangements inside
the code do not make it in: a changelog is read to decide whether an
update is worth taking, not to learn how the addon is put together.

The number here is the addon's, the one in the TOC. Two other numbers in
this project are not it and never move with it: the version in the head
of LICENSE belongs to the licence text, and `Darken.API_VERSION` belongs
to the contract a module is written against.

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
