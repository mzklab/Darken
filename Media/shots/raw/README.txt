Raw captures for the CurseForge gallery.

Everything in this folder is a screenshot exactly as it was taken. The
store images beside it, in Media/shots, are built from these:

    python tools/shots.py

Each file becomes Media/shots/<same name>.png, 1280x720, on Darken's own
ink with the caption set in the same place every time. Rerunning the tool
overwrites them all, so a change to the look is one run away.

NAMING

    <order> - <caption>.png

The number only sorts; it is not shown. Everything after " - " becomes
the caption. A name with no " - " makes a shot with no caption, which is
right for one that speaks for itself.

The order is by what the addon is worth opening for. The game's own
windows come first and the settings pages last: what a visitor wants to
know is what their interface will look like, and only then that there is
a slider behind it. The talent frame leads because it is the window the
engine protects - the one a dark theme is least expected to reach.

WHAT IS STILL MISSING

A before-and-after pair. Every shot here is the interface after Darken,
and a visitor who has never seen the game cannot tell how much of it is
the addon. One window captured twice - the slider at zero, then at
eighty - says more than the nine below. Name the pair

    0 - The same window, before and after.png

so it sorts ahead of the rest and leads the gallery.

Also unshown: the bar textures and colours on the unit frames, the
nameplates, and the aura grid. Those are half of what the addon does and
none of them appears in a capture here.

This folder is not in the release archive: the player downloads the
addon, not the storefront.
