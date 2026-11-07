# What changed

What is recorded here is what the player can see. Rearrangements inside
the code do not make it in: a changelog is read to decide whether an
update is worth taking, not to learn how the addon is put together.

The number here is the addon's, the one in the TOC. Two other numbers in
this project are not it and never move with it: the version in the head
of LICENSE belongs to the licence text, and `Darken.API_VERSION` belongs
to the contract a module is written against.

## 1.0.7

**The slider goes darker, and every mark moved with it.** What the
slider did at a hundred it now does at seventy-five, and a hundred goes
darker than the addon has ever gone - short of black, which stays a
decision an area is given by name. Nobody's screen changes: a stored
value is multiplied by three quarters once, so a profile at eighty
comes out at sixty and looks exactly as it did. The named steps moved
with it - Dimmed and Dark are the same two multipliers at their new
places - and so did the default.

**A section of its own: Shadows.** A shadow can now be laid inside an
element's own edges, so a button reads as sunk into the dark interface
rather than pasted onto it - what the skinning addons call a shadow
border. One switch and one strength, nothing else: the depth stays
fixed, because a deeper shadow on a small button is not a stronger
shadow, it is a smaller icon.

It is four thin gradients along the four edges rather than a picture of
a frame: a picture is cut at one size and blurs at any other, while a
gradient fits a thirty-pixel button and a seven-hundred-pixel window
alike and costs no file. The elements dressed are the furniture of the screen - what is always
there, in the same place: the action bars, the pet and stance bars, the
bags, the menu row, and the fixed buttons of the supported addons' bars.
Not the auras, the flyouts, the list rows or the tooltips, which come
and go; and never a walk of everything.
Off by default, and switching it off hides the shadows rather than
leaving them behind.

**Every bar Rack builds is darkened, not only its action bars.** The bag
bar and the row of menu buttons stood bright on a dark screen, and the
reason was a short list: Rack's own source names fifteen bars - the five
action bars, five paged ones, pet, stance, and the three that are not
action bars at all: bags, micro menu, vehicle button - and we knew
seven. A frame nobody has named is a frame the named pass never paints.
The paged bars' buttons are outlined and shaded with the rest now too.

**The darkening arrives sooner after you enter the world.** It used to
take a couple of seconds to creep over the interface, and longer on a
machine with many addons. The reason is the slicing: the walk takes
three milliseconds of each frame so that nothing stutters, and the
login walk is some five hundred milliseconds of work - a hundred and
forty frames of it. Those particular frames are the ones nobody is
looking at, the screen is still fading in, so until the first walk has
finished a slice now takes the larger share. Afterwards the ordinary
one stands again, because by then you are looking.

**The plate under a menu button darkens, the icon on it does not.** The
whole family was left alone, because a menu button's picture is its
icon and the row darkened flat stops being tellable apart. A probe of
one button showed the family is not of one kind: the square plate under
the icon is in it too, and that is framing by every argument - it says
nothing and it is the same metal as the rest of the interface. The
plate darkens now and the icons stay themselves.

**The player's own frame darkens in combat as it does out of it.** The
red variant of a unit frame's art is spared because red says that unit
is fighting. On the player's own frame it says nothing he does not
know, and he is in combat most of the time: his frame and the ring with
his level stood bright beside a dark target. The exception now holds
for other units only - the unit is written in the picture's name, so
this is by name rather than by guesswork.

**The roll on a dropped item keeps its dice, coin and pass.** Three
buttons that are nothing but their pictures - need, greed, pass - and a
few seconds to tell them apart. Two of them had become the same grey
blob. The same rule as the role icons: a picture one recognises
something by is not framing.

**The group finder keeps its role and leader icons.** The crown beside
a name says who leads; the shield, the cross and the swords say which
places a group still wants - which is the whole of what the list is
read for. All of them were darkened to the same near-black blob. They
are readings by the same rule a spell icon, a coin and a quest marker
are, and they are left alone now; the window around them goes on
darkening.

## 1.0.6

**Three more buttons of the micro menu are darkened.** A row half dark
was reported with a picture: the menu is painted by name, and three of
the names this line builds it from were not on the list.


**The settings window is in the archive.** A player wrote that he could
not open the settings at all:

    Darken/Darken_Camelot.toc:27 Error loading Darken/Options/List.lua

He was right, and so was every error like it. The addon is built from a
list of folders, the game loads from a list of files, and the two had
drifted: Options and Widgets - the settings window and everything it is
drawn with, twelve files - stood in the second and not in the first.
Every published build went out without them, and nothing in the build
said so.

The two lists are now compared, twice: the build refuses to finish if
the archive lacks a file any TOC loads, and a check does the same
comparison without building anything. Apologies to everyone who
installed it and found no settings.

**A letter the game has coloured is left as it is.** The quest titles on
the map are coloured by difficulty - grey, green, yellow, red - and red
and green were being raised to white along with the page's ink. The
rule looked only at how dark a letter was, and both of those are dark:
red is 1.00 0.10 0.10, green 0.25 0.75 0.25. The colour said something
and the addon threw it away, leaving text that was perfectly readable
and therefore said nothing about what had been lost.

The rule now asks a second question: is this a colour at all. Ink is
near-neutral - the game's dark text on parchment is a brown whose
channels sit within a few hundredths of each other - and only that is
raised. Everything tinted stays as the game wrote it, which is the same
promise the bars' fills and the item icons have always had.

**The flight map is left alone.** It was darkened into unreadability -
a continent that could not be made out at all, with the flight route
drawn across it. A map is a picture of the world and is read rather
than looked past, which is why the world map and the minimap have been
exempt from the first; the flight map is one by the same argument and
was simply not on the list. Its own framing still darkens: that is
named part by part and painted by name.

**Bar Text turns the game's own on instead of writing its own.** With a
format chosen the bars stayed blank, and the game's own text stopped
working as well. The subsystem used to write the label itself: find the
bar, find its font string, hook whatever function the client writes
values with, rewrite after it, move it, show what the game had hidden.
Every one of those is a guess at somebody else's build, and every one
of them is spelt differently on this client line.

The game already has this setting, and it does the job from inside its
own update - the only place that knows the number, knows when it
changed and may touch a protected frame's label. So the choice now
turns that on and picks its shape: the number, the percentage, or both
- which is the game's own two-ended form, the percentage at the left
end of the bar and the number at the right. One shape goes to every bar
the game draws, which is the game's rule and not ours, and the setting
says so.

Where the two values stand is the one thing the game's setting cannot
be told, so that stayed ours: "Percentage Position" and "Number
Position" move what the game wrote - to the left end, the middle or the
right end, or wherever the game itself had it. The text is never
written, shown or hidden by this addon; only moved. A bar whose labels
cannot be found keeps the game's layout, and the values stay on it.

The shortening of large numbers went with the hand-written label: it
described digits this addon no longer writes. Choosing "the game's own"
back puts the game's variables to the value the client itself calls
default, so the setting is reversible like every other one here.

## 1.0.5

**The game stopped stuttering while you play.** With the addon on, the
frames dropped steadily - walking, jumping, standing in a field with
nothing open. The cause was measured rather than guessed at: the pass
that walks a window's tree was running every single frame, ninety
milliseconds of walking in every second of play, with no window on the
screen at all. The watcher that answers "a window appeared, paint it"
is placed on every named frame the interface root holds, and most of
what it hears is not a window opening - it is a tooltip, a line of
error text, a zone name, a drop-down, another addon showing and hiding
its own frames as you move. Each of those was answered with the full
walk, and each threw away the walk already in flight, so none of them
ever finished.

Three things now stand between that door and the walk. A frame is
walked while the walking finds something new and stops being walked
when it does not. The window the player opens is never refused. And
under both of those sits a ceiling that depends on no judgement at
all: once the walking done in the last second passes ten milliseconds,
a frame appearing is answered with its top layer and nothing more
until the second is out.

**What the addon spends is now something you can read.** `/dark cost`
takes a reading, and a second one after a stretch of play prints the
difference per second: pictures the game assigned and how many of them
were ours, pictures taken up that the plan did not hold, climbs for an
area, frames shown and what each was answered with, walk slices and
the milliseconds they took. The numbers above were found with it, by
the author, in his own client.

**The interface costs less while nothing is happening.** Two things
were paid for on every write the game makes to any picture anywhere -
and nearly every such write is to a picture that is none of this
addon's business. The answer "not ours" is now remembered against the
picture, so a repeat costs one lookup instead of two protected calls
into the game, and it is forgotten again the moment the addon learns
any frame's area. And the arithmetic of an application - every area's
multiplier, its brightness ceiling, the tint, the class colour - is
worked out once per change of setting instead of once per picture
painted.

**The equipment slots darken with the rest of the character sheet.**
Every slot kept its gold frame on a dark window, and the reason was a
name: the list held the spelling another line of the client uses, and
not one of those names exists here. The slots and their frames are
named the way this client spells them now, for the character sheet and
the inspect window both, and the names are pinned by a check so they
cannot be lost again quietly. The item's own icon is deliberately not
in that list.

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

**A bar's fill is never painted, whatever it is drawn from.** The
test that tells framing from contents inside a content field asks
whether the picture came from an atlas - today's templates keep a
slot's border in a field named for an icon, and framing arrives as an
atlas while an icon arrives as a file. That question is about icons
and portraits. It was being asked about fills as well, so the fill of
any bar whose artwork happens to be an atlas was painted. A fill shows
a magnitude; what it is drawn from does not change that.

**The painting by name gets the frame budget it needs to finish.** At
a millisecond a frame the whole list takes several hundred frames, and
it does not get them: the plan is cleared and the painting restarted
at every fresh reconnaissance. A pass that never reaches the end
paints nothing, which is why windows kept appearing in the game's own
colours.

**A picture the game keeps rewriting is left to the game.** One
window was measured writing to its own artwork two hundred and
eighteen thousand times in a single session, and every one of those
was answered with a repainting of ours. A race over one picture is not
won by being quicker. Each picture is given a fixed number of answers
now and is then left with whatever colour the game gives it; the
report counts how many were given up that way, and the saved
variables name the window.

**A reputation tick no longer walks a window.** Reputation moving,
spells changing, equipment being swapped - each of these made the
addon walk the last window the player had opened, in full, forcing
past the check for whether anything had changed. They are not rare
events: reputation moves on every kill. If the last window opened was
a large one, that was thousands of pictures examined per kill. They
get the same answer a showing gets now - the window's top layer and
the names belonging to it - while what arrives deeper is caught where
it is created, by the watcher on assignment.

**The chat no longer sets the text raising going.** Raising text walks
every page the addon remembers and writes every font object it knows,
and it was asked for on the showing of any window at all - so a mouse
passing over the chat ran it, again and again, for text that is not
on a page and is never raised. It is asked for only when a window
with text on parchment appears.

**The chat windows are not painted at all.** A chat window is text on
no backdrop of its own, and the client fades it up and down
continuously - the mouse leaving it, a message arriving. Painting it
gains nothing to look at and puts a second writer on pictures the
client is already animating. Its framing is the edit box and the tab,
which are frames of their own, do not fade with the window, and are
painted as before.

**A merchant's window no longer blinks on a purchase.** The answer to
somebody else's repainting was written on the frame after it, which
is invisible on one picture and plain on a window of them - buying
rewrites the whole list at once, and the window wore the game's own
colours for a frame each time. It is written in the same call now;
the queue that folds several touches of one picture into one write
is kept and emptied there.

**An item dropping into a bag no longer stops the game.** The game
repaints bags window by window, so one item called the answer once
for each bag carried - and the answer went over every bag window
there is. Thirteen bags meant a hundred and sixty-nine paintings for
one item. They are folded into one.

**A list row appearing no longer walks anything.** The pass places a
listener on every hidden frame it meets - list rows, a pool's
reserve, tabs - and there are thousands of them. Each appearance
started a walk of that frame's subtree, and these do not appear
rarely: a row is handed out and taken back as a list scrolls, a
button as a bar changes, which in a fight is continuous. An
appearance now paints the frame's top layer, bounded, and anything
deeper is reached by the watcher that hears a picture being assigned
- which is the moment a pooled row gets its pictures in any case.

A frame is not re-read when it appears again unchanged, and "changed"
is two counts asked of the frame rather than a reading of what it
holds. A row returning from its pool with different content is
therefore still painted.

**Windows are painted whole again when they open.** Trimming the
work done on an appearance went too far: a window holds more than its
top layer, and painting only that left windows opening half dressed.
How much work an appearance deserves is decided by how often it
happens - a window is opened by hand and can afford a walk of
everything inside it, cut into slices; a row of a list, a tab, a
button out of a pool appear continuously and get the top layer and no
more. Both answers had been tried on both cases, and each was wrong
for the other.

**Text keeps its colour everywhere but on parchment.** The raising
exists for one thing: dark ink chosen for a light page - a quest, a
letter, a book, a trainer's list - which a darkened page leaves
unreadable. Everywhere else a colour is a statement: an item's
quality in a tooltip, a channel in the chat, a class on a unit frame.
Those were being rewritten, and each was reported in turn. The rule
is now a short closed list of where raising is wanted, rather than a
list of exceptions that grew one complaint at a time.

**Far fewer listeners.** A listener was placed on every hidden frame
at any depth, and an interface holds thousands - every row of every
list, every button of every pool. Each is two hooks that live for the
session and run whenever the game shows the frame, which for a pooled
row is continuous. They are placed near the top of a window now; what
is deeper is given its pictures at the moment it is handed out, and
the watcher on assignment hears exactly that.

**The answer about a picture is not thrown away on every colour.**
Working out whether a picture is framing or contents costs half a
dozen protected calls, and the answer was forgotten whenever anything
wrote to the picture - including a colour, which changes nothing
about what the picture is. Colours are written in floods: experience
ticking, a bag redrawing, a bar moving. The answer is kept now and
forgotten only when the game gives the picture a new image.

**The chat's text keeps the colour the game gave it.** The pass
raised any dark label it met, in any window, and the chat's windows
are walked like the rest - so a dark line in the chat was rewritten
in the addon's own light ink. The raising exists for dark ink on a
light page: a quest, a letter, a book, where a darkened sheet leaves
the text unreadable. A colour in the chat is the message's own -
which channel it came on, whether it was a whisper, whether it is a
warning - and a dark one there was chosen rather than inherited.
Nothing of ours writes it now.

**Only parchment keeps its ink written.** The colours written into
the game's font objects are rewritten on every raising of the pages,
which happens whenever a quest is opened. Four of those objects
belonged to no window in particular - the generic black and dark-grey
fonts - so anything in the interface inheriting from them changed
colour each time a quest was taken. They are off the list. A dark
label outside a window of parchment is raised by the walk instead,
which decides by the label's own colour and touches nothing it has
not looked at.

**The chat's text is never written.** The font settings used to give
the chat the player's font and size along with the rest of the
interface, standing down only when another addon owned the chat. They
no longer touch it at all. The chat is the one part of the interface
whose text is read continuously and whose look is settled once - in
the game's own options, or in whichever addon was installed for it -
and a second hand on it is unwelcome whether or not there is an owner
to yield to.

**The player's portrait is not painted black, by any road.** A window
names its contents in fields of its own - portrait, icon, fill - and
the picture named there frequently belongs to a frame inside the
window rather than to the window itself. Whoever reads that inner
frame's pictures asks it what its contents are, and it does not know:
the field is on the window above. A portrait has nothing else to be
recognised by - no name, and a file number for a picture, which is
what framing looks like here - so it was painted black. The window's
answer is now remembered against the picture itself, so the walk, the
painting of a top layer and the adoption of a newly assigned picture
all have it.

**The player's portrait is not painted black.** A window names its
contents in fields of its own - portrait, icon, fill - and the picture
named there is frequently a region of a frame inside it rather than of
the window itself: a unit frame holds its portrait while the texture
lives on the container below. The painting of a window's top layer
asked each frame what its own contents were and never asked the window
above, so the portrait was framing by every general rule - it has no
name and its picture is a file number, which is exactly what framing
looks like here. The window's answer is carried down to the level
below it now.

**More of what is never painted is named outright.** The list of
exceptions is merged with this client's own: every window that carries
a portrait in its corner, the unit frames' portraits, the party and
arena frames'. A portrait is a picture of a person and is never
framing, and naming it is the one way of saying so that cannot be
wrong.

**Every chat window counts as the chat.** The rule that stops the
addon answering an animation applies to the chat's area, and that
area named the first chat window and its parts - so every window a
player had made beyond the first fell into the general area, was
answered for on every frame of every fade, and blinked. A message
arriving is a fade, which is why it showed most when quests were
being taken. All ten windows, their tabs, their edit boxes and their
button frames are named now.

**The chat stops blinking.** The chat fades - its window, its tabs
and its buttons are brought up and taken down by writing a colour on
every frame of the animation - and the addon answered each of those
writes with its own colour. Two writers on one picture is a blink
rather than a shade. The chat is painted once now and nothing of ours
runs during a fade: our colour is what the fade starts from and
carries up and down from there.

**A window shown again costs nothing.** Showing a frame is not a rare
event - a chat window, its tabs and its buttons appear and vanish on
the movement of a mouse - and each appearance read every region of the
frame and of the frames inside it, building a table per frame to do
it. The pictures were painted the first time and are held by the hook
on each of them, so a frame whose top layer is done is now recognised
by a single lookup. The record is cleared with the plan, which is when
the colours have to be written again.

**A named window is dark two levels deep before it opens.** Its own
backdrop was painted before opening and the header inside it was not,
because a header is a frame directly inside the window rather than a
picture on it. Both levels are painted now, by one piece of code
shared with the answer to a showing - there were two copies of that
decision, which is two answers to "is this framing" before long.

**A check that enters the world and opens nothing.** The whole addon
is brought up on a stand-in client, the world is entered, the deferred
work is run, and a window that has never been shown is examined: its
backdrop and its header have to be dark already, its bar's fill and
its portrait untouched. That is the question the live client was being
asked by hand, and it is the check that found the gap above.

**A list of frames the darkening never touches.** The rules that tell
framing from contents decide from what a picture is - its layer, its
name, its atlas, the file behind it - and a general rule is wrong
somewhere. Thirteen frames and pictures are now named as exceptions:
portraits and icons that read as framing by every mark and are not.
The list is asked before any rule that reasons, and nothing after it
can overturn it. Exact names, because a list that exists to be certain
cannot be built out of substrings.

**The list of names is worked through once, not once per event.**
Every addon of the game's that loads makes names resolve that did not
resolve before, so the list is gone over again - and each of those
passes repeated the whole of the work already done. An entry painted
is remembered as painted and not returned to until the plan is
cleared, which is the one thing that makes the colours need writing
again.

The pass also advances by a count of entries rather than a budget of
milliseconds. A budget is spent by whatever it meets first, so one
large window could take the whole of a frame's share and the pass make
no progress through the list.

**Every window is listened for, shown or not.** The addon answers a
window by hearing it appear, and the hook that hears it was placed
only on frames a pass had reached - while a pass does not enter what
is hidden, which is nearly every window before the player opens it.
The windows that most needed answering therefore had nothing
listening, and whatever was done for them happened later, which is
what the player saw as the default artwork changing colour. Every
named window of the interface is listened for now, and the report
counts them: a zero there while windows open in the game's colours
names the cause exactly.

**A window is dark as it appears, named or not.** The framing of a
window is on the window itself and on the frames directly inside it -
the backdrop, the border, the header, the insets - which is a few
dozen pictures however large the window is. Those are painted in the
call that shows it. Nothing below that level is taken there: what is
deeper is reached by the names, by the background pass and by the
watcher, none of which is paid for while the player waits.

**A window is dark as it appears, not a moment later.** The painting
by name works through the list in the background, and a window could
be shown before its turn came - so it appeared in the game's own
colours and changed colour afterwards. Showing a window says exactly
which names matter at that instant: its own are a few dozen pictures,
and they are painted in the same call, before the frame is drawn. The
rest of the list goes on in the background as before.

**A colour written over ours is heard on the picture itself.** The
watcher sat on the method table shared by every picture in the
interface, so it ran on every colour any of them was given - four
hundred thousand times in a measured session, of which the pictures
the addon had painted were a small part. The colour of a picture we
paint is now watched on that picture alone, placed when it is painted.
A picture nobody painted costs nothing.

The shared table still carries the two methods that ASSIGN a picture,
which is how a frame handed out of a pool announces that it exists -
the one moment the addon can learn of it without walking anything.
Those are rare beside the colour writes.

**The watcher on repainting costs less per write.** It sits on the
method table shared by every picture in the interface, so it runs on
every write any of them receives - four hundred thousand times in a
measured session - and it opened a protected call for each. The two
cases that need no answer at all, our own write and a picture already
given up, are now recognised by a table lookup before that call.

**The areas are resolved once per pass rather than once per frame.**
Deciding which frames belong to a named area costs a resolution of
every group the compatibility layer holds, and the painting asked for
it on every slice.

**Opening a window costs nothing, this time including the answer to
it.** Showing one window is not one event - a window of any size shows
many frames as it opens, and each reached the answer and took a slice
of work there and then. A hundred frames took a hundred slices in the
single frame the player was waiting through. Nothing is painted on a
showing now: one continuation is asked for, however many frames
arrive, and the frames that follow carry it. The raising of a page's
text is asked for once in the same way.

**Opening a window costs nothing.** Showing one used to start a walk
of everything inside it, and a window of any size shows many frames as
it opens, each asking again - several thousand pictures examined while
the player waits to see the window. The framing is carried by the list
of names instead, which does not depend on a frame being shown, so
showing only continues the painting already under way and raises the
text of a page. Pictures the game creates after showing are caught
where they always were, by the watcher on repainting.

What this costs is plain: framing that is not in the list and is not
created after the window opens now stays as the game drew it. The list
is extended from `/dark harvest`, which names exactly those pieces.

**Opening a large window no longer stalls the game.** A window shows
dozens of frames as it opens, and each one asked for a walk of what
had appeared. That request replaced the queue instead of joining it,
so the walk restarted from the beginning dozens of times per window
and never reached the end of a large one, while the deferred
continuations of the discarded walks went on running beside it. New
work joins the queue now, and only one continuation is ever
outstanding - for the walk and for the painting by name alike.

**More of the interface is dark before it opens.** The list of window
names the darkening paints without a walk now covers 740 windows and
194 named parts inside them - the backdrops, headers, insets and
borders a window is built from. What the names do not cover the walk
still finds when the window is opened.

The painting runs in slices with a budget of its own, after the
reconnaissance rather than before it. Before, it ran whole and in one
frame, and it ran ahead of the step that clears the plan - so it cost
its full time at login and left nothing behind.

**`/dark harvest mouse` asks about the window under the cursor.** A
frame's name is not something a player is obliged to know, and
pointing at the piece that stayed light is the natural way to ask
about it. The climb goes up to the window the piece belongs to and
reports that.

**`/dark harvest` reports what the names do not reach.** It examines
the interface, hidden frames included, and lists every piece of
framing that would be darkened if something reached it but is not yet
covered - grouped by the frame it sits in, worst first, with the whole
table written to the saved variables. The list of names is extended
from that measurement rather than from guesses about which window is
missing. It reads only; nothing on screen changes.

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
