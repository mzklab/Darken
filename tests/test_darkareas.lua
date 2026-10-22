local helpers = require("helpers")

-- Area modes: every area of the screen has its own answer to "how dark",
-- and the slider has not gone anywhere.
--
-- What this file is for. The author compared the current settings with his
-- former addon (DarkMode, MIT, same author) and said: "I like the model in
-- my old plugin better than what you made, but I would keep the slider, it
-- is not bad". Hence two requirements, and both are checked here as
-- requirements rather than as code:
--
--   1. An area has a named mode, and a named mode does not listen to the
--      slider. Otherwise "More Dark" would mean different things at
--      different times, and the name would stop being a name.
--
--   2. The slider stays the one single movement by which the player makes
--      the WHOLE screen darker -- including windows nobody listed.
--      That is exactly how our model differed from the former one, and
--      losing it would mean trading one half for the other.
--
-- A third requirement followed: "what is in my old plugin should be the
-- default". The default is checked by the number and the factor -- what is
-- compared is not a digit but a look.
--
-- What is not here. The full round trip with a real AceDB is covered by
-- tests/test_darkdefault.lua, the scale arithmetic by
-- tests/test_darkscale.lua, the application to frames by
-- tests/test_darkness.lua and tests/test_darkcases.lua. Here is the model
-- itself: the modes, their meeting with the slider, the migration of the former exceptions, and the agreement of the three area lists.

T.suite("area modes: the default is the author's former addon")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)

local Darkness = ns.Darkness

local function close(a, b, msg)
    T.ok(type(a) == "number" and type(b) == "number"
        and math.abs(a - b) < 1e-9, msg .. " (" .. tostring(a) .. ")")
end

-- The DarkMode mode factors, written out here anew rather than taken from
-- the code: the subject of the check is that our modes give exactly those,
-- and one shared record for both would only prove itself.
local DARKMODE_DIMMED    = 0.50
local DARKMODE_DARK      = 0.36
local DARKMODE_MORE_DARK = 0.20

-- Eighty rather than the former sixty-four: the author sent a screenshot of
-- his settings saying "these should be the defaults".
T.eq(Darkness.defaults.amount, 80, "the slider of a fresh install is 80")
close(Darkness.Factor(64), DARKMODE_DARK,
    "while the Dark mode factor of the author's former addon stands at 64")

-- A fresh install does not separate the areas: one slider move changes
-- everything. The player separates them, and does so deliberately.
for i = 1, #Darkness.MODES do
    local mode = Darkness.MODES[i]
    T.eq(type(mode.key), "string", "the mode has a key")
    T.eq(type(mode.label), "string", "and a label: " .. tostring(mode.key))
end
for key, mode in pairs(Darkness.defaults.mode) do
    T.eq(mode, "follow", "the area follows the slider: " .. key)
end

T.suite("area modes: a name always means the same thing")

-- The main property of a named mode. The slider is neither a factor nor a
-- correction for it: it simply does not touch it. Otherwise two controls
-- would share one number, and "Dark" on a light slider would be lighter than
-- "Dark" on a dark one -- that is, the name would mean nothing.
for _, amount in ipairs({ 0, 25, 64, 100 }) do
    close(Darkness.GroupFactor("tooltip", { tooltip = "dimmed" }, amount),
        DARKMODE_DIMMED, "Dimmed does not listen to slider " .. amount)
    close(Darkness.GroupFactor("tooltip", { tooltip = "dark" }, amount),
        DARKMODE_DARK, "Dark does not listen to slider " .. amount)
    close(Darkness.GroupFactor("tooltip", { tooltip = "moredark" }, amount),
        DARKMODE_MORE_DARK, "More Dark does not listen to slider " .. amount)
    T.eq(Darkness.GroupFactor("tooltip", { tooltip = "native" }, amount), 1,
        "\"leave as is\" does not listen either: " .. amount)
end

-- There are no modes below the bottom of the scale, and that is a rule, not
-- an oversight. DarkMode had Darker, More Darker and Black below; a frame
-- you cannot make out is not darkened but lost, and the floor of the addon stands above that line.
for i = 1, #Darkness.MODES do
    local mode = Darkness.MODES[i]
    if mode.amount then
        T.ok(Darkness.Factor(mode.amount) >= Darkness.DARKEST - 1e-9,
            "the mode does not go below the bottom of the scale: " .. mode.key)
    end
end

T.suite("area modes: the slider stays the shared one")

-- An area set to "as the shared strength" follows the slider, and that is
-- the default. It is checked on the common pass ("other windows") -- the one
-- that reaches the windows nobody listed: had the area model narrowed the
-- coverage to a named list, it would break right here.
for _, amount in ipairs({ 0, 25, 64, 100 }) do
    close(Darkness.GroupFactor("window", {}, amount), Darkness.Factor(amount),
        "the common pass follows the slider: " .. amount)
    close(Darkness.GroupFactor("window", nil, amount), Darkness.Factor(amount),
        "and with a silent profile too: " .. amount)
end

-- Separating one area does not touch the rest: exactly what the former model
-- did not have at all.
do
    local modes = { unitframe = "moredark", tooltip = "native" }
    close(Darkness.GroupFactor("unitframe", modes, 10), DARKMODE_MORE_DARK,
        "the unit frames hold their own")
    T.eq(Darkness.GroupFactor("tooltip", modes, 10), 1,
        "the tooltips are left as they are")
    close(Darkness.GroupFactor("window", modes, 10), Darkness.Factor(10),
        "while everything else still follows the slider")
end

T.suite("area modes: the native look is always reachable")

-- The default is dark, and that is the author's decision. The rule it does
-- not cancel: the native look of the game must stay a choice -- both wholly
-- and area by area.
T.eq(Darkness.GroupFactor("unitframe", {}, 0), 1,
    "zero on the slider returns the native look to everything")
do
    local reachable = false
    for i = 1, #Darkness.MODES do
        if Darkness.MODES[i].key == "native" then reachable = true end
    end
    T.ok(reachable, "and every area has a \"leave as is\"")
end

T.suite("area modes: three area lists are one list")

-- The areas are listed in three places: the pass itself (GROUPS), the
-- defaults, and the "classic" preset. A divergence would look like an area
-- that darkens but has no control -- or like a preset promising the native
-- brightness and delivering half of it.
local presets = helpers.newNamespace()
helpers.loadAddonFile("Core/Defaults.lua", presets)
helpers.loadAddonFile("Core/Presets.lua", presets)

local classic = presets.GetPreset("classic")
T.ok(type(classic) == "table", "the \"classic\" preset is in place")

local presetModes = classic.values.darkness.mode
T.eq(type(presetModes), "table", "and it names the area modes")

local missing, extra = {}, {}
for key in pairs(Darkness.defaults.mode) do
    if presetModes[key] == nil then missing[#missing + 1] = key end
end
for key in pairs(presetModes) do
    if Darkness.defaults.mode[key] == nil then extra[#extra + 1] = key end
end
T.eq(#missing, 0, "the preset forgot no area: "
    .. table.concat(missing, " | "))
T.eq(#extra, 0, "and invented no extra ones: " .. table.concat(extra, " | "))
T.eq(classic.values.darkness.amount, 0, "and it sets the slider to zero")

T.suite("area modes: the former exceptions moved over without loss")

-- Formerly an area had two states, and the second was recorded by a checkbox
-- in "darkness.exclude". Now it is one of the modes, and the transfer must
-- be one to one: the setting did not disappear, it became more specific.
T.ok(presets.DB_VERSION >= 10, "the schema version was raised for this step")
T.eq(type(presets.Migrations[9]), "function", "the 9 -> 10 step is declared")
T.eq(type(presets.ExcludeToModes), "function", "and the work itself is named")

do
    local profile = {
        version = 9,
        darkness = {
            amount = 35,
            exclude = { unitframe = true, tooltip = false, chat = true },
        },
    }
    presets.MigrateProfile(profile, presets.Migrations, presets.DB_VERSION)

    T.eq(profile.darkness.mode.unitframe, "native",
        "a checked area became \"leave as is\"")
    T.eq(profile.darkness.mode.chat, "native", "and so did the second one")
    T.eq(profile.darkness.mode.tooltip, nil,
        "a cleared checkbox creates no mode: it had the shared one anyway")
    T.eq(profile.darkness.exclude, nil, "the former key was cleaned up")
    T.eq(profile.darkness.amount, 35, "the chosen slider is untouched")
    T.eq(profile.version, presets.DB_VERSION, "the version was raised")
end

-- A second pass is harmless: raw migrations walk the profiles on every login,
-- and a step must survive a second call.
do
    local darkness = { exclude = { minimap = true } }
    local profile = { darkness = darkness }
    presets.ExcludeToModes(profile)
    presets.ExcludeToModes(profile)
    T.eq(darkness.mode.minimap, "native", "the mode is in place after the second time too")
end

-- A profile with no darkening section, and garbage on the input, do not
-- break the step: the migration works on whatever lies in SavedVariables.
presets.ExcludeToModes(nil)
presets.ExcludeToModes({})
presets.ExcludeToModes({ darkness = "garbage" })
presets.ExcludeToModes({ darkness = { exclude = 5 } })
T.ok(true, "garbage on the input does not break the step")

T.suite("area modes: the choice in the settings window")

-- Every area has one dropdown, not a dropdown plus a checkbox. Two controls
-- for one area would raise the question "whose word wins", which the player
-- would have to answer themselves.
local args = Darkness.options.args
local seen = 0
for key in pairs(Darkness.defaults.mode) do
    local node = args[Darkness.OptionKey(key)]
    T.eq(type(node), "table", "the area has a settings node: " .. key)
    if type(node) == "table" then
        seen = seen + 1
        T.eq(node.type, "select", "and it is a select, not a checkbox: " .. key)
        T.eq(node.width, "full", "across the full row: " .. key)
        local values = node.values()
        for i = 1, #Darkness.MODES do
            T.ok(values[Darkness.MODES[i].key] ~= nil,
                "the mode is offered: " .. key .. "/" .. Darkness.MODES[i].key)
        end
    end
end
T.ok(seen >= 10, "areas in the settings window: " .. seen)

-- The node name stays one word even for an area with a hyphen in its key:
-- node names are read by people and end up in settings search paths.
T.eq(Darkness.OptionKey("actionbar-art"), "modeactionbarart",
    "the hyphen was removed from the node name")

-- Reading and writing go through the profile, and a write without a profile stays silent.
do
    ns.Addon = { db = { profile = { darkness = { amount = 20, mode = {} } } } }
    local node = args[Darkness.OptionKey("tooltip")]
    T.eq(node.get(), "follow", "an area starts at \"as the shared strength\"")
    node.set(nil, "moredark")
    T.eq(ns.Addon.db.profile.darkness.mode.tooltip, "moredark",
        "the choice went into the profile")
    T.eq(node.get(), "moredark", "and reads back")
    node.set(nil, "follow")
    T.eq(node.get(), "follow", "and comes back by the same movement")

    ns.Addon = nil
    T.eq(node.get(), "follow", "without a database the default is shown")
    node.set(nil, "native")
    T.ok(true, "and a write without a database breaks nothing")
end

T.suite("darkness: the migration removes \"as the shared strength\" from the gossip area")

-- The value was put there neither by us nor by the player but by the look
-- button: it set "as the shared strength" on every area in a row, including
-- the one where the text is printed dark on light. So it is removed -- an
-- empty slot means the default, and the default for this area is the right one.
do
    local profile = {
        version = 12,
        darkness = { amount = 64, mode = { questlog = "follow",
                                           tooltip = "follow" } },
    }
    presets.MigrateProfile(profile, presets.Migrations, presets.DB_VERSION)

    T.eq(profile.darkness.mode.questlog, nil,
        "\"as the shared strength\" was removed from the gossip area")
    T.eq(profile.darkness.mode.tooltip, "follow",
        "while the neighbouring area is untouched")

    -- The player's choice is not touched: they set "darker" themselves.
    local mine = {
        version = 12,
        darkness = { amount = 64, mode = { questlog = "moredark" } },
    }
    presets.MigrateProfile(mine, presets.Migrations, presets.DB_VERSION)
    T.eq(mine.darkness.mode.questlog, "moredark",
        "what was chosen by hand stays as it was")
end

T.suite("darkness: an area's own colour and the class colour")

-- Two steps answer not "how dark" but "in what colour": the colour itself
-- becomes the factor. That is how the model this is copied from works too,
-- and they stand in the same list as the brightness steps -- because the
-- player has one choice: what to tint this area with.
do
    local modes = { chat = "custom", tooltip = "class", bags = "dark" }
    local colors = { chat = { r = 1, g = 0, b = 0.5 } }
    local class = { r = 0.4, g = 0.8, b = 0.94 }

    -- An area's own colour is the factor as it is: neither the slider nor the
    -- shared tint adds anything to it.
    local r, g, b = Darkness.GroupMultipliers("chat", modes, 100,
        { r = 0.2, g = 0.2, b = 0.2 }, colors, class)
    T.eq(r, 1, "the red channel is taken from the chosen colour")
    T.eq(g, 0, "the green one too")
    T.eq(b, 0.5, "and the blue one")

    -- The class colour is the same thing, only the colour comes from the game.
    r, g, b = Darkness.GroupMultipliers("tooltip", modes, 100, nil, colors, class)
    T.eq(r, 0.4, "the class colour arrived in full")
    T.eq(g, 0.8, "and the second channel")
    T.eq(b, 0.94, "and the third")

    -- The neighbouring area is computed as before: a brightness step knows
    -- nothing about colour at all.
    r = Darkness.GroupMultipliers("bags", modes, 100, nil, colors, class)
    T.ok(math.abs(r - Darkness.Factor(64)) < 0.001,
        "a brightness step is computed as it was")

    -- There is no colour but the step is chosen: there is no factor, so the
    -- area stays native rather than going black. An empty slot does not mean "black".
    r, g, b = Darkness.GroupMultipliers("chat", modes, 100, nil, {}, class)
    T.eq(r, 1, "with no chosen colour the area is untouched")
    T.eq(g, 1, "not in one channel")
    T.eq(b, 1, "nor in the other")

    -- And the same when the client gave no class colour.
    r = Darkness.GroupMultipliers("tooltip", modes, 100, nil, colors, nil)
    T.eq(r, 1, "with no class colour the area is untouched")
end

T.suite("darkness: windows of foreign addons are recognised by name")

-- A frame does not remember who created it, while a window name almost
-- always starts with the addon name -- they are named that way to avoid
-- colliding in the shared global namespace. That is enough: a foreign prefix
-- does not occur in a game frame name, because the game names are older than any addon.
do
    local names = { "Details", "WeakAuras", "Bartender4" }

    T.eq(Darkness.AddonWindow("DetailsBaseFrame1", names), true,
        "a foreign addon window was recognised by its prefix")
    T.eq(Darkness.AddonWindow("WeakAurasFrame", names), true,
        "and so was the second")
    T.eq(Darkness.AddonWindow("MerchantFrame", names), false,
        "a game window does not count as foreign")

    -- The prefix matches the beginning rather than occurring anywhere:
    -- otherwise the game's "MinimapDetailsHolder" would come out foreign.
    T.eq(Darkness.AddonWindow("MinimapDetailsHolder", names), false,
        "a match not at the start does not make it foreign")

    -- Garbage on the input gives an ordinary "no" rather than an error: the
    -- name comes from the game, and the list from the game's own addon table.
    T.eq(Darkness.AddonWindow(nil, names), false, "with no name nothing can be called foreign")
    T.eq(Darkness.AddonWindow("DetailsBaseFrame1", nil), false,
        "nor with no list")
    T.eq(Darkness.AddonWindow("", names), false, "an empty name is not a name")

    -- Without a client the list is empty, and that is not an error: the
    -- windows stay in "other windows", that is they darken as they used to.
    Darkness.ForgetAddons()
    T.eq(#Darkness.AddonNames(), 0, "without a client the list is empty")
end

T.suite("darkness: a light page brings the dark text back")

-- Light letters on light parchment are the same unreadability, only from the
-- other side. So the restore happens by itself rather than from the player's
-- memory: they set the area to "as in the game" and are entitled to get the
-- page the way the game draws it.
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"

    local text = { r = 0.16, g = 0.13, b = 0.10 }
    function text:GetObjectType() return "FontString" end
    function text:GetTextColor() return self.r, self.g, self.b, 1 end
    function text:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end

    ns.Addon = { db = { profile = { darkness = {
        amount = 64, mode = { questlog = "follow" } } } } }

    T.eq(Darkness.LiftText(text), true, "the dark line was lifted")
    local ink = select(1, Darkness.Ink())
    T.ok(math.abs(text.r - ink) < 0.001, "and became light")

    -- The player returned the interface to its native look: the application
    --
    -- restores the text too. What is asked is the shared strength rather than
    -- the area mode: the text lift now goes over the whole interface, not
    -- only over the quest page, and it has one question -- is the interface touched at all.
    ns.Addon.db.profile.darkness.amount = 0
    Darkness:ApplySettings()
    T.ok(math.abs(text.r - 0.16) < 0.001, "the line is its own colour again")
    T.eq(Darkness.LiftedCount(), 0, "and it is no longer in the list of lifted ones")

    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: foreign addons are not tinted unasked")

-- A foreign addon is someone else's work: its colours were chosen by its
-- author, its windows were configured by the player. The author put it
-- twice, and the two times are not the same sentence. First: "these are
-- other addons, I want the game's windows touched and nothing else". Later,
-- about four he names: "I want Bartender4, Leatrix, Rack and the rest
-- darkened too, this matters."
--
-- Both hold, because the promise moved. It used to be the area's default -
-- the area meant EVERY addon, so it had to be off. It is now the list: the
-- pass goes into the windows of the addons whose source we have read and
-- into no others, so the area can follow the slider out of the box and
-- still touch nothing the author did not name.
T.eq(Darkness.ModeOf(nil, "addons"), "follow",
    "the addons we know follow the slider on a fresh install")

-- And this is where the promise lives now. An addon nobody named is not
-- known, and a pass that does not know an addon does not enter its windows.
T.eq(Darkness.Known("RXPGuides"), false,
    "an addon we never read the source of is not ours to paint")
T.eq(Darkness.Known("SomeAddonInventedToday"), false,
    "nor is one that does not exist")
T.eq(Darkness.Known(nil), false, "and nothing is not an addon")

-- The other areas still listen to the slider.
T.eq(Darkness.ModeOf(nil, "window"), "follow",
    "the other windows stopped listening to the slider")

-- And it still switches off with one click, for a player who wants the
-- game's own windows dark and everything else untouched.
T.eq(Darkness.ModeAmount("addons", { addons = "native" }, 80), nil,
    "set to \"as in the game\", the area stops reaching them")
T.eq(Darkness.ModeAmount("addons", { addons = "follow" }, 80), 80,
    "and the strength chosen by the player reaches the ones we know")

T.suite("darkness: the client is asked who made a frame")

-- The guess by name misses whenever an addon's folder and its frames are
-- spelled differently, and the author found it with a real one: the folder
-- is RXPGuides, the frames are RXPG_something, so not one of them was
-- recognised as somebody else's and they darkened along with the game's
-- windows.
--
-- The client knows. A frame does not remember its author, but the global
-- holding it does: issecurevariable answers with the name of the addon that
-- set the variable.
do
    -- The client's answer, as the game gives it: secure, and whose.
    local function client(made)
        return function(name)
            local who = made[name]
            if who == nil then return true, nil end
            return false, who
        end
    end

    local secure = client({
        RXPG_MenuFrame = "RXPGuides",
        QuestieFrame12 = "Questie",
    })

    T.eq(Darkness.Owner("RXPG_MenuFrame", secure), "RXPGuides",
        "the frame whose name the prefix rule cannot catch")
    T.eq(Darkness.AddonWindow("RXPG_MenuFrame", { "RXPGuides" }), false,
        "and the prefix rule indeed cannot catch it")

    T.eq(Darkness.Owner("MerchantFrame", secure), nil,
        "a frame of the game's belongs to nobody")

    -- Our own frames are ours. The pass knows them by another road
    -- (Darkness.IsOurs), and an answer here would only make the question
    -- ambiguous.
    T.eq(Darkness.Owner("DarkenWindow", client({ DarkenWindow = "Darken" })),
        nil, "our own name is not an answer")

    -- Rubbish gives an ordinary no: the name comes from the game and the
    -- answer from a client that may not have the function at all.
    T.eq(Darkness.Owner(nil, secure), nil, "no name, no owner")
    T.eq(Darkness.Owner("", secure), nil, "an empty name is not a name")
    T.eq(Darkness.Owner("RXPG_MenuFrame", nil), nil,
        "and with no way to ask, nobody owns anything")
    T.eq(Darkness.Owner("RXPG_MenuFrame", function() error("no") end), nil,
        "a client that throws is a no rather than a failure")
end
