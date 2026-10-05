local helpers = require("helpers")

T.suite("Skin.HexToRGB")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
-- Core/Media.lua: resolving a texture name to a file lives there, and ns.Skin.MediaTexture
-- calls it (Core/Skin.lua). Without that file the core would find no texture at all.
helpers.loadAddonFile("Core/Media.lua", ns)
local Skin = ns.Skin

local function near(a, b) return math.abs(a - b) < 0.005 end

local r, g, b = Skin.HexToRGB("FFFFFF")
T.ok(near(r, 1) and near(g, 1) and near(b, 1), "white")

r, g, b = Skin.HexToRGB("000000")
T.ok(near(r, 0) and near(g, 0) and near(b, 0), "black")

r, g, b = Skin.HexToRGB("B682BC")
T.ok(near(r, 182/255), "lilac: red channel")
T.ok(near(g, 130/255), "lilac: green channel")
T.ok(near(b, 188/255), "lilac: blue channel")

-- Case and the leading hash must not matter.
local r2 = Skin.HexToRGB("#b682bc")
T.ok(near(r2, 182/255), "a hash and lower case are allowed")

-- Garbage does not break loading.
T.eq(Skin.HexToRGB("nothex"), nil, "garbage gives nil")
T.eq(Skin.HexToRGB(nil), nil, "nil gives nil")
T.eq(Skin.HexToRGB("FFF"), nil, "the short form is not supported")

T.suite("Skin.Shade")

r, g, b = Skin.Shade(0.5, 0.5, 0.5, 2)
T.ok(near(r, 1), "multiplication is clamped at one")

r, g, b = Skin.Shade(0.5, 0.4, 0.2, 0.5)
T.ok(near(r, 0.25) and near(g, 0.2) and near(b, 0.1), "darkened by half")

r, g, b = Skin.Shade(0.5, 0.5, 0.5, -1)
T.ok(near(r, 0), "a negative factor is clamped at zero")

T.suite("Skin.Palette")

for _, key in ipairs({ "ink", "panel", "panelAlt", "line", "lilac", "lilacDeep", "text", "textDim" }) do
    local c = Skin.Palette[key]
    T.ok(type(c) == "table", "the colour exists: " .. key)
    T.ok(c and c[1] >= 0 and c[1] <= 1, "the red channel is in range: " .. key)
end

T.suite("Skin.Get")

local gr, gg, gb, ga = Skin.Get("lilac")
T.ok(near(gr, 182/255), "the colour comes from the palette")
T.eq(ga, 1, "the default alpha is one")

local _, _, _, a2 = Skin.Get("lilac", 0.4)
T.eq(a2, 0.4, "the alpha is passed through")

T.eq(Skin.Get("no-such-colour"), nil, "an unknown name gives nil")

T.suite("Skin.MediaTexture")

-- Fake library. Fetch without noDefault returns the default texture --
-- exactly the behaviour of the real LibSharedMedia that makes one Fetch
-- insufficient to decide "is this a texture or not".
local function fakeMedia(known)
    return {
        IsValid = function(self, mediatype, key)
            return mediatype == "statusbar" and known[key] ~= nil
        end,
        Fetch = function(self, mediatype, key, noDefault)
            if mediatype ~= "statusbar" then return nil end
            local path = known[key]
            if path == nil and not noDefault then return "default.tga" end
            return path
        end,
    }
end

local lsm = fakeMedia({ ["Darken"] = "Media\\mzk.tga", ["Empty"] = "" })

T.eq(Skin.MediaTexture(lsm, "Darken"), "Media\\mzk.tga", "a known name gives a path")
T.eq(Skin.MediaTexture(lsm, "Close"), nil,
    "an unknown name does not get the default texture")
T.eq(Skin.MediaTexture(lsm, "Empty"), nil, "an empty path is the same as no path")

T.eq(Skin.MediaTexture(nil, "Darken"), nil, "without the library there is no preview")
T.eq(Skin.MediaTexture(lsm, nil), nil, "nil instead of a name gives nil")
T.eq(Skin.MediaTexture(lsm, 42), nil, "a non-string name gives nil")
T.eq(Skin.MediaTexture(lsm, ""), nil, "an empty name gives nil")
T.eq(Skin.MediaTexture({}, "Darken"), nil, "an object without methods gives nil")

-- The library is third-party: its version may have a different signature.
-- A list row must not fall over because of that.
T.eq(Skin.MediaTexture({
    IsValid = function() error("a different revision") end,
    Fetch = function() return "never-asked.tga" end,
}, "Darken"), nil, "an error in IsValid does not break the call")

T.eq(Skin.MediaTexture({
    IsValid = function() return true end,
    Fetch = function() error("a different revision") end,
}, "Darken"), nil, "an error in Fetch does not break the call")

T.suite("Skin.ClearButtonTextures")

-- Clearing a button's native textures. The main property is checked: a
-- client on which Set*Texture(nil) raises an error must not break the
-- styling -- it was on this very line that the window lost its close button,
-- its keybinding button and its dropdown entirely. The texture must become
-- transparent even where removing it failed.
helpers.loadAddonFile("Skin/Draw.lua", ns)

local STATES = { "Normal", "Pushed", "Disabled", "Highlight" }

--- Fake button: every texture-clearing method raises an error.
local function fakeButton(hostile)
    local button = { textures = {} }

    for i = 1, #STATES do
        local texture = { alpha = 1, texture = "a red image" }
        texture.SetAlpha = function(self, value) self.alpha = value end
        texture.SetTexture = function(self, value)
            if hostile then error("the client does not accept nil", 0) end
            self.texture = value
        end
        texture.SetAtlas = function(self) error("there is no atlas here", 0) end

        button.textures[STATES[i]] = texture
        button["Get" .. STATES[i] .. "Texture"] = function() return texture end
        button["Set" .. STATES[i] .. "Texture"] = function()
            if hostile then error("the client does not accept nil", 0) end
        end
    end

    return button
end

local hostileButton = fakeButton(true)
local okHostile = pcall(Skin.ClearButtonTextures, hostileButton)
T.ok(okHostile, "the client error does not escape")
for i = 1, #STATES do
    T.eq(hostileButton.textures[STATES[i]].alpha, 0,
        "the state texture was cleared via alpha: " .. STATES[i])
end

local plainButton = fakeButton(false)
Skin.ClearButtonTextures(plainButton)
for i = 1, #STATES do
    T.eq(plainButton.textures[STATES[i]].texture, nil,
        "the state texture was removed: " .. STATES[i])
end

-- A button with no state textures (not UIPanelButtonTemplate) passes silently.
T.ok(pcall(Skin.ClearButtonTextures, {}), "a button with no textures does not break the call")
T.ok(pcall(Skin.ClearButtonTextures, nil), "nil does not break the call")

T.suite("skin: button states")

-- The native state textures are cleared (above), and in exchange the button
-- must get its own: a working button that responds to nothing reads as
-- broken -- that is exactly how the defect was reported.

local function colors(state, kind)
    local fill, border, text = Skin.ButtonColors(state, kind)
    return fill .. "/" .. border .. "/" .. text
end

-- All four states exist and all four are distinguishable: an identical look
-- for two states would mean no feedback for one of them.
do
    local seen = {}
    local states = { "normal", "hover", "pressed", "disabled" }
    for i = 1, #states do
        local key = colors(states[i], "normal")
        T.eq(seen[key], nil, "the state is distinguishable from the rest: " .. states[i])
        seen[key] = states[i]
    end
end

-- Colours come from the palette and only from it: an invented colour would
-- diverge from the rest of the window on the first palette change.
do
    local states = { "normal", "hover", "pressed", "disabled" }
    local kinds = { "normal", "primary", "select" }
    for i = 1, #kinds do
        for j = 1, #states do
            local fill, border, text = Skin.ButtonColors(states[j], kinds[i])
            T.ok(Skin.Palette[fill] ~= nil, "the fill is from the palette: " .. fill)
            T.ok(Skin.Palette[border] ~= nil, "the border is from the palette: " .. border)
            T.ok(Skin.Palette[text] ~= nil, "the label is from the palette: " .. text)
        end
    end
end

-- A disabled button must look disabled, not merely carry a dim label: its
-- label is the one colour that tells it from a normal one.
T.eq(select(3, Skin.ButtonColors("disabled", "normal")), "textDim",
    "a disabled button dims its label")

-- A dropdown is darker than the block it sits in (panel): otherwise it
-- blends into it and does not read as a separate control.
T.eq(select(1, Skin.ButtonColors("normal", "select")), "ink",
    "the dropdown is filled with ink, not with the panel shade")
T.eq(select(2, Skin.ButtonColors("normal", "select")), "lilacDeep",
    "and outlined with a visible border, not with line")

-- A typo in a state or kind name does not leave the button colourless.
T.eq(colors("invention", "normal"), colors("normal", "normal"),
    "an unknown state counts as normal")
T.eq(colors("hover", "invention"), colors("hover", "normal"),
    "an unknown kind counts as a normal button")
T.eq(colors(nil, nil), colors("normal", "normal"), "nil is a normal button too")
T.suite("Skin.Shade: a factor per channel")

-- Tinted darkening is the same multiplication, only the channels are dimmed
-- differently. A single factor must keep working as it did: all the former
-- darkness arithmetic rests on it.
do
    local sr, sg, sb = Skin.Shade(1, 0.8, 0.6, 0.5)
    T.ok(near(sr, 0.5) and near(sg, 0.4) and near(sb, 0.3),
        "one factor dims all three channels equally")

    sr, sg, sb = Skin.Shade(1, 1, 1, 1, 0.5, 0.25)
    T.ok(near(sr, 1) and near(sg, 0.5) and near(sb, 0.25),
        "three factors dim the channels differently")

    -- Out-of-range values are clamped: the engine accepts colours from zero to one.
    sr, sg, sb = Skin.Shade(1, 1, 1, 2, -1, 0.5)
    T.ok(near(sr, 1) and near(sg, 0) and near(sb, 0.5),
        "the result stays within zero and one")
end

T.suite("Skin.Metrics: the spacing scale")

-- The scale exists so that a spacing value is not a number written into four
-- files in four different ways. The check holds two of its properties: every
-- value is in place, and they form an ascending series rather than a random set.
do
    local M = Skin.Metrics
    for _, name in ipairs({ "hair", "rail", "gap", "inset", "group",
                            "header", "footer", "window", "flow" }) do
        T.eq(type(M[name]), "number", "the scale has " .. name)
        T.ok(M[name] > 0, "and it is a positive number: " .. name)
    end

    -- The order of magnitudes is the hierarchy itself: a hairline is thinner
    -- than a rail, a rail is smaller than the gap between controls, the gap
    -- between controls is smaller than a block inset, a block inset is smaller
    T.ok(M.hair < M.rail, "a hairline is thinner than a rail")
    T.ok(M.rail < M.gap, "a rail is smaller than the gap between controls")
    T.ok(M.gap < M.inset, "the gap between controls is smaller than a block inset")
    T.ok(M.inset < M.group, "a block inset is smaller than the gap between blocks")
    T.ok(M.group < M.footer, "the footer is taller than the gap between blocks")

    -- The scale step is a multiple of four: a two-pixel difference between
    -- neighbouring controls reads as an accident, four reads as a decision.
    for _, name in ipairs({ "rail", "gap", "inset", "group" }) do
        T.eq(M[name] % 4, 0, "the scale value is a multiple of four: " .. name)
    end
end

T.suite("Skin.Slack: the addition to a control's height")

-- AceGUI inserts its own three pixels between layout rows. The addition is
-- counted from those, otherwise the gap would come out three pixels larger
-- than requested -- the very discrepancy that makes controls "float".
do
    local M = Skin.Metrics
    T.eq(Skin.Slack(), M.gap - M.flow, "by default the addition reaches the common gap")
    T.eq(Skin.Slack(M.group), M.group - M.flow, "a requested gap is taken into account")
    T.eq(Skin.Slack(M.flow), 0, "a gap equal to the library one asks for no addition")
    T.eq(Skin.Slack(0), 0, "nothing below the library one: controls would overlap")
    T.eq(Skin.Slack("garbage"), M.gap - M.flow, "garbage counts as the default")
end

T.suite("Skin: the palette accent")

-- The accent is the single colour with which the dark theme says "look
-- here": a section heading, a checkbox tick, the filled part of a slider,
-- a scrollbar, a selected row, a hover.
--
-- What is checked here are the properties of the set, not the numbers
-- themselves: the numbers were picked by eye and may change, whereas "there
-- are as many sets as names in the order" and "deep is darker than light"
-- are rules, and breaking either shows in game at once.
do
    local Skin = ns.Skin

    T.eq(type(Skin.ACCENTS), "table", "the accent sets are declared")
    T.eq(#Skin.ACCENT_ORDER > 1, true, "there is more than one")

    -- The order and the sets are one and the same list from two sides. Let
    -- them diverge and the window would show an entry with no colour, or a colour with no entry.
    local counted = 0
    for _ in pairs(Skin.ACCENTS) do counted = counted + 1 end
    T.eq(counted, #Skin.ACCENT_ORDER,
        "the list for the window names all the sets and only them")

    for _, key in ipairs(Skin.ACCENT_ORDER) do
        local set = Skin.ACCENTS[key]
        T.eq(type(set), "table", "the set exists: " .. key)

        local ar, ag, ab = Skin.HexToRGB(set.accent)
        local dr, dg, db = Skin.HexToRGB(set.deep)
        T.ok(ar ~= nil, "the light colour of the set parses: " .. key)
        T.ok(dr ~= nil, "and the deep one too: " .. key)

        -- The deep colour fills a selected row and a pressed button, and
        -- light text lies on it. Were it brighter than the accent, the text would vanish.
        T.ok(ar + ag + ab > dr + dg + db,
            "the deep colour is darker than the light one: " .. key)
    end

    -- A switch changes exactly two palette colours and nothing more: the
    -- blacks, the lines and the text are not tied to the accent, and the theme does not drift.
    local wasInk = { Skin.Get("ink") }
    local wasText = { Skin.Get("text") }

    T.ok(Skin.SetAccent("gold"), "gold is accepted")
    local gr = select(1, Skin.Get("lilac"))
    T.ok(Skin.SetAccent("steel"), "steel is accepted")
    local sr, sg, sb = Skin.Get("lilac")
    T.ok(gr ~= sr, "the accent colour really did change")
    T.ok(sb > sr, "steel is cool: it holds more blue than red")

    T.eq(Skin.accent, "steel", "the palette remembers the chosen set")
    T.eq(select(1, Skin.Get("ink")), wasInk[1], "the blacks are untouched")
    T.eq(select(1, Skin.Get("text")), wasText[1], "and the text colour too")

    -- An unknown name is not accepted at all: a palette painted by a typo
    -- into nil would break SetColorTexture on every widget.
    T.eq(Skin.SetAccent("invention"), false, "an unknown set is rejected")
    T.eq(Skin.SetAccent(nil), false, "and so is a missing name")
    T.eq(Skin.accent, "steel", "and the chosen set stayed in place")

    Skin.SetAccent("lilac")
end
