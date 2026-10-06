# What changed

What is recorded here is what the player can see. Rearrangements inside
the code do not make it in: a changelog is read to decide whether an
update is worth taking, not to learn how the addon is put together.

The number here is the addon's, the one in the TOC. Two other numbers in
this project are not it and never move with it: the version in the head
of LICENSE belongs to the licence text, and `Darken.API_VERSION` belongs
to the contract a module is written against.

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
