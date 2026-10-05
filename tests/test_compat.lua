local helpers = require("helpers")

T.suite("Compat.DetectFlavor")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", ns)
local Compat = ns.Compat

-- The interface number is built like this: major * 10000 + minor * 100 + patch.
T.eq(Compat.DetectFlavor(11507),  "vanilla",  "Classic Era 1.15.7")
T.eq(Compat.DetectFlavor(16001),  "vanilla",  "the 1.60.1 line's beta")
T.eq(Compat.DetectFlavor(20504),  "tbc",      "TBC Classic 2.5.4")
T.eq(Compat.DetectFlavor(30404),  "wrath",    "Wrath Classic 3.4.4")
T.eq(Compat.DetectFlavor(40402),  "cata",     "Cataclysm Classic 4.4.2")
T.eq(Compat.DetectFlavor(50500),  "mists",    "Mists Classic 5.5.0")
T.eq(Compat.DetectFlavor(110107), "mainline", "Retail 11.1.7")

-- Rubbish on the input must not bring the addon down at load.
T.eq(Compat.DetectFlavor(nil),     "unknown", "nil")
T.eq(Compat.DetectFlavor(0),       "unknown", "a zero")
T.eq(Compat.DetectFlavor(-1),      "unknown", "a negative number")
T.eq(Compat.DetectFlavor("rubbish"), "unknown", "a non-numeric string")
T.eq(Compat.DetectFlavor(true),    "unknown", "a boolean value")

-- A numeric string is accepted: there is no guarantee every client returns
-- GetBuildInfo()'s fourth value as a number, and a false "unknown" would
-- switch the addon off on a supported client.
T.eq(Compat.DetectFlavor("11507"), "vanilla", "a numeric string is coerced to a number")

T.suite("Compat.IsSupported")

T.eq(Compat.IsSupported("vanilla"),  true,  "vanilla is supported")
T.eq(Compat.IsSupported("tbc"),      true,  "tbc is supported")
T.eq(Compat.IsSupported("mists"),    true,  "mists is supported")
T.eq(Compat.IsSupported("mainline"), false, "retail is out of scope")
T.eq(Compat.IsSupported("wrath"),    false, "wrath is not declared yet")
T.eq(Compat.IsSupported("unknown"),  false, "an unknown client")

T.suite("Compat.GetFrameNames")

local vanillaUnits = Compat.GetFrameNames("vanilla", "unitframe")
T.ok(type(vanillaUnits) == "table", "a table is returned")
T.ok(#vanillaUnits > 0, "vanilla has unit frames")
T.eq(vanillaUnits[1], "PlayerFrame", "the player's frame comes first")

-- Unknown keys do not bring the call down but give an empty list.
-- The rule "a module silently does nothing" rests on that.
T.eq(#Compat.GetFrameNames("mainline", "unitframe"), 0, "an unsupported flavour")
T.eq(#Compat.GetFrameNames("vanilla", "no-such-group"), 0, "an unknown group")
T.eq(#Compat.GetFrameNames(nil, nil), 0, "nil on the input")

-- The caller must have no way of spoiling the shared table.
local copy = Compat.GetFrameNames("vanilla", "unitframe")
copy[1] = "SPOILED"
T.eq(Compat.GetFrameNames("vanilla", "unitframe")[1], "PlayerFrame",
     "a copy is returned rather than the internal table")

T.suite("Compat.HasGroup")

T.eq(Compat.HasGroup("vanilla", "unitframe"), true,  "the group exists")
T.eq(Compat.HasGroup("vanilla", "no-such"), false, "the group does not exist")
T.eq(Compat.HasGroup("mainline", "unitframe"), false, "the flavour does not exist")

T.suite("Compat.FilterExisting")

-- A stand-in global dictionary: that is how the function is checked without a client.
local fakeGlobals = {
    PlayerFrame = {},
    TargetFrame = {},
}

local found = Compat.FilterExisting(
    { "PlayerFrame", "NoSuchFrame", "TargetFrame" }, fakeGlobals)
T.eq(#found, 2, "a non-existent name was dropped")
T.eq(found[1], "PlayerFrame", "the order is kept: the first")
T.eq(found[2], "TargetFrame", "the order is kept: the second")

T.eq(#Compat.FilterExisting({}, fakeGlobals), 0, "an empty input, an empty output")
T.eq(#Compat.FilterExisting(nil, fakeGlobals), 0, "a nil instead of a list")
T.eq(#Compat.FilterExisting({ "PlayerFrame" }, {}), 0, "an empty client")

T.suite("compatibility: whose kill is this")

-- The question is one while on different clients there are two answers: the
-- later line says it in one word, the earlier one adds it up out of two —
-- "is it tapped at all" and "is it tapped by me". Somebody has to add them up, and that is the layer.
do
    -- The later line: there is an answer, and it decides everything.
    T.eq(Compat.TapDenied(true, nil, nil), true, "denied means somebody else's")
    T.eq(Compat.TapDenied(false, true, false), false,
        "not denied means ours, whatever the halves may say")

    -- The earlier line: tapped, but not by me.
    T.eq(Compat.TapDenied(nil, true, false), true, "tapped by somebody else")
    T.eq(Compat.TapDenied(nil, true, true), false, "tapped by me means mine")
    T.eq(Compat.TapDenied(nil, false, false), false, "not tapped at all")

    -- Uncertainty means "no": a grey bar on a live kill takes the target away
    -- from the player, while a coloured one on somebody else's merely fails to hint.
    T.eq(Compat.TapDenied(nil, nil, nil), false, "the client is silent, so the creature is an ordinary one")
    T.eq(Compat.TapDenied(nil, nil, true), false, "half an answer is not enough")
end
