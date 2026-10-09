local helpers = require("helpers")

-- Darkness: the selection rule as a table of cases, and the common window pass.
--
-- The author saw a miss in both directions at once in the client: a darkened
-- class icon on a unit frame and darkened text on one side, an untouched
-- action bar and an untouched professions window on the other. That is one
-- defect: the selection rule decided by the absence of markers ("a texture,
-- the name says nothing -- so it is trim") while it reached only the frames
-- listed by name.
--
-- So exactly two things are checked here, and both as rules rather than as
-- lists of exceptions:
--
--   1. The selection. Only what is known to be an interface texture is
--      darkened: an atlas, a path to a trim file, or a fill with no file.
--      Everything else is content and stays untouched.
--   2. The reach. The pass starts from the interface root and goes over every
--      named window rather than over an enumerated list of names.

T.suite("darkness: the table of selection cases")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)

local Darkness = ns.Darkness

local function close(actual, expected)
    return type(actual) == "number" and math.abs(actual - expected) < 1e-9
end

--- A fake region: exactly the markers the decision is made by.
-- A missing marker is a missing method rather than a nil from a method: in
-- the client that is exactly how it goes for objects of different types.
local function newRegion(opts)
    local region = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return opts.kind end,
    }
    if opts.layer then
        region.GetDrawLayer = function() return opts.layer end
    end
    if opts.name then
        region.GetName = function() return opts.name end
    end
    if opts.texture ~= nil then
        region.GetTexture = function() return opts.texture end
    end
    if opts.atlas then
        region.GetAtlas = function() return opts.atlas end
    end
    function region:GetVertexColor() return self.r, self.g, self.b, self.a end
    function region:SetVertexColor(cr, cg, cb, ca)
        self.r, self.g, self.b = cr, cg, cb
        if ca ~= nil then self.a = ca end
    end
    return region
end

-- Every row is a case from the client rather than an invented one. The author
-- saw the first three with his own eyes and called them a defect.
local CASES = {
    {
        -- The author's screenshot: the bottom row of buttons, on which not one
        -- can be recognised. The button texture IS its icon -- there is no
        -- separate border texture around it at all, so the darkening ate the recognition.
        why = "a game menu button: the texture IS the icon",
        opts = { kind = "Texture", layer = "ARTWORK",
                 texture = "Interface\\Buttons\\UI-MicroButton-Quest-Up" },
        chrome = false,
    },
    {
        -- The same screenshot, the group finder window: a shield, a cross and a
        -- sword, darkened into equally brown circles.
        why = "a role icon: it is how one recognises the tank",
        opts = { kind = "Texture", layer = "ARTWORK",
                 atlas = "roleicon-tiny-tank" },
        chrome = false,
    },
    {
        why = "a bottom menu button by atlas: its texture IS its icon",
        opts = { kind = "Texture", layer = "ARTWORK",
                 atlas = "UI-HUD-MicroMenu-GameMenu-Up" },
        chrome = false,
    },
    -- A file id instead of a path means nothing by itself: in current builds
    -- both the window trim and an icon are named by id. What makes it content
    -- is a name, a frame field, the icon folder or the list of blocked ids.
    {
        why = "a unit frame portrait: the name says what it is",
        opts = { kind = "Texture", layer = "ARTWORK", texture = 132863,
                 name = "PlayerFramePortrait" },
        chrome = false,
    },
    {
        why = "the same id with no name is window trim",
        opts = { kind = "Texture", layer = "ARTWORK", texture = 132863 },
        chrome = true,
    },
    {
        why = "a label: the text must stay readable at any slider position",
        opts = { kind = "FontString", layer = "OVERLAY" },
        chrome = false,
    },
    {
        why = "action bar trim: a path to a trim file",
        opts = { kind = "Texture", layer = "ARTWORK",
                 texture = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf" },
        chrome = true,
    },
    {
        why = "the background of the professions window: a trim atlas",
        opts = { kind = "Texture", layer = "BACKGROUND",
                 atlas = "Professions-background", texture = 4620672 },
        chrome = true,
    },
    {
        why = "the ring around a portrait: an atlas, albeit with the word portrait",
        opts = { kind = "Texture", layer = "ARTWORK",
                 atlas = "UI-HUD-UnitFrame-Player-PortraitOn", texture = 4062583 },
        chrome = true,
    },
    {
        why = "a spell icon by the path into the icon folder",
        opts = { kind = "Texture", layer = "BACKGROUND",
                 texture = "Interface\\Icons\\Spell_Fire_FireBall" },
        chrome = false,
    },
    {
        -- Gold, silver and copper are three different circles, and the player
        -- tells them apart by colour. Darkened, they become equally brown, and
        -- "sixty-eight" stops saying sixty-eight of what.
        why = "a coin circle: it is how one recognises which coin it is",
        opts = { kind = "Texture", layer = "ARTWORK",
                 texture = "Interface\\MoneyFrame\\UI-GoldIcon" },
        chrome = false,
    },
    {
        why = "silver is the same coin, and the rule is the same",
        opts = { kind = "Texture", layer = "ARTWORK",
                 texture = "Interface\\MoneyFrame\\UI-SilverIcon" },
        chrome = false,
    },
    {
        why = "an item icon in a slot: the name ends in Icon",
        opts = { kind = "Texture", layer = "BACKGROUND", texture = 134400,
                 name = "ContainerFrame1Item1IconTexture" },
        chrome = false,
    },
    {
        why = "a bar fill by an id from the DarkMode list",
        opts = { kind = "Texture", layer = "ARTWORK", texture = 137012 },
        chrome = false,
    },
    {
        why = "a named portrait: the name says what it is",
        opts = { kind = "Texture", layer = "ARTWORK", name = "TargetFramePortrait",
                 texture = "Interface\\CharacterFrame\\TemporaryPortrait" },
        chrome = false,
    },
    {
        why = "a button icon by name",
        opts = { kind = "Texture", name = "ActionButton1Icon",
                 texture = "Interface\\Icons\\INV_Misc_QuestionMark" },
        chrome = false,
    },
    {
        why = "a highlight under the cursor: feedback rather than trim",
        opts = { kind = "Texture", layer = "HIGHLIGHT",
                 texture = "Interface\\Buttons\\ButtonHilight-Square" },
        chrome = false,
    },
    {
        why = "a window border: a path to a trim file",
        opts = { kind = "Texture", layer = "BORDER",
                 texture = "Interface\\DialogFrame\\UI-DialogBox-Border" },
        chrome = true,
    },
    {
        why = "a colour fill: there is no file at all, and such a thing is never content",
        opts = { kind = "Texture", layer = "BACKGROUND" },
        chrome = true,
    },
    {
        why = "a class icon in a portrait: the shared sheet of class circles",
        opts = { kind = "Texture", layer = "ARTWORK",
                 texture = "Interface\\TargetingFrame\\UI-Classes-Circles" },
        chrome = false,
    },
    {
        why = "a class icon by atlas",
        opts = { kind = "Texture", layer = "ARTWORK",
                 atlas = "classicon-warrior", texture = 4062583 },
        chrome = false,
    },
    {
        why = "the fallback portrait of an unknown unit",
        opts = { kind = "Texture", layer = "ARTWORK",
                 texture = "Interface\\CharacterFrame\\TemporaryPortrait" },
        chrome = false,
    },
    {
        why = "a portrait mask: not a texture but the shape of a cut-out",
        opts = { kind = "MaskTexture", texture = 132863 },
        chrome = false,
    },
    {
        why = "a character model",
        opts = { kind = "PlayerModel" },
        chrome = false,
    },
}

for i = 1, #CASES do
    local case = CASES[i]
    T.eq(Darkness.IsChrome(newRegion(case.opts)), case.chrome, case.why)
end

T.suite("darkness: content cannot be darkened even directly")

-- The rule must live in the one place where the colour changes. Otherwise
-- "the text does not darken" rests on the discipline of the callers, and there are already four of them.
do
    local label = newRegion({ kind = "FontString" })
    T.eq(Darkness.Tint(label, 0.5), false,
        "a font string does not darken even when passed straight into Tint")
    T.eq(label.r, 1, "and its colour is untouched")

    local portrait = newRegion({ kind = "Texture", texture = 132863,
        name = "PlayerFramePortrait" })
    T.eq(Darkness.Tint(portrait, 0.5), false, "a portrait does not darken even directly")

    local model = newRegion({ kind = "PlayerModel" })
    T.eq(Darkness.Tint(model, 0.5), false, "a model does not darken even directly")
end

T.suite("darkness: a texture as a standalone object")

-- The decorative gryphons of the main bar are global textures rather than
-- frames. A pass that only handled frames silently did nothing with them.
do
    local cap = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf" })

    T.eq(Darkness.ApplyToFrame(cap, 0.5), 1, "we darken a texture as it is")
    T.ok(close(cap.r, 0.5), "and its colour was multiplied")
end

T.suite("darkness: the common window pass")

--- A fake frame: a name, a type, regions and children.
local function newFrame(kind, name, regions, children)
    local frame = {
        GetObjectType = function() return kind end,
        GetRegions = function() return unpack(regions or {}) end,
        GetChildren = function() return unpack(children or {}) end,
    }
    if name then frame.GetName = function() return name end end
    return frame
end

local function newArt(path)
    return newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = path or "Interface\\DialogFrame\\UI-DialogBox-Background" })
end

do
    -- A window that is in no list of names. That is exactly the case the author
    -- called a defect: "a pile of windows, the dimming does not work on them".
    local professionsArt = newArt("Interface\\FrameGeneral\\UI-Background-Rock")
    local professions = newFrame("Frame", "ProfessionsFrame", { professionsArt })

    -- Our own window must not be darkened: it is already drawn in our palette.
    local ownArt = newArt()
    local own = newFrame("Frame", "DarkenMoverOverlay", { ownArt })

    -- An unnamed frame is the inside of a foreign addon or a library widget.
    local anonArt = newArt()
    local anon = newFrame("Frame", nil, { anonArt })

    -- A frame a named group takes care of: it has its own factor and its own
    -- checkbox in the exception list, and the common pass must walk past it.
    local groupArt = newArt()
    local group = newFrame("Frame", "PlayerFrame", { groupArt })

    local root = newFrame("Frame", "UIParent", {},
        { professions, own, anon, group })

    local skip = { [group] = true }
    local count = Darkness.SweepChildren(root, 0.5, 0.5, 0.5, skip)

    T.ok(close(professionsArt.r, 0.5),
        "a window that is in no list is darkened")
    T.eq(ownArt.r, 1, "our own window is not darkened")
    T.eq(anonArt.r, 1, "an unnamed frame was skipped")
    T.eq(groupArt.r, 1, "a frame of a named group is left to its own group")
    T.eq(count, 1, "exactly one darkening was counted")
end

T.suite("darkness: a window that appeared later")

-- The game creates most windows the moment the player opens them for the first
-- time. A pass made once at login will see none of them.
do
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 50, mode = {} } } } }

    local art = newArt("Interface\\Spellbook\\Spellbook-Page-1")
    local window = newFrame("Frame", "SpellBookFrame", { art })

    T.eq(Darkness.ApplyToWindow(window), 1, "a new window is darkened when shown")
    T.ok(close(art.r, helpers.whiteAt(Darkness.Factor(50))),
        "and by exactly the current value")

    ns.Addon = nil
    ns.flavor = nil
end

T.suite("darkness: the application reaches the whole screen")

do
    local savedUIParent = _G.UIParent
    local savedPlayer = _G.PlayerFrame

    -- A portrait and a label inside the window: the content must survive the pass.
    local portrait = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = 132863, name = "PlayerFramePortrait" })
    local label = newRegion({ kind = "FontString", layer = "OVERLAY" })
    local chrome = newArt("Interface\\CharacterFrame\\UI-Party-Background")
    local player = newFrame("Frame", "PlayerFrame", { chrome, portrait, label })

    local shopArt = newArt("Interface\\MerchantFrame\\UI-Merchant-Background")
    local shop = newFrame("Frame", "MerchantFrame", { shopArt })

    _G.PlayerFrame = player
    _G.UIParent = newFrame("Frame", "UIParent", {}, { player, shop })

    ns.flavor = "vanilla"
    local profile = { darkness = { amount = 50, mode = {} } }
    ns.Addon = { db = { profile = profile } }

    Darkness:ApplySettings()

    -- White trim arrives at the brightness ceiling, see helpers.whiteAt.
    local dim = helpers.whiteAt(Darkness.Factor(50))
    T.ok(close(chrome.r, dim), "the unit frame trim is darkened")
    T.ok(close(shopArt.r, dim), "the merchant window is darkened although nobody listed it")
    T.eq(portrait.r, 1, "the portrait is intact")
    T.eq(label.r, 1, "the label is intact")
    T.eq(Darkness.Remembered(portrait), nil, "and darkness did not remember it")

    -- Excluding the common pass returns the windows to their native look rather
    -- than merely ceasing to touch them.
    profile.darkness.mode.window = "native"
    Darkness:ApplySettings()
    T.eq(shopArt.r, 1, "the excluded windows returned to their native look")
    T.ok(close(chrome.r, dim), "while the unit frame stayed darkened by its own group")

    -- And back again.
    profile.darkness.mode.window = "follow"
    Darkness:ApplySettings()
    T.ok(close(shopArt.r, dim), "clearing the checkbox brought the window darkening back")

    -- Zero restores everything.
    profile.darkness.amount = 0
    Darkness:ApplySettings()
    T.eq(shopArt.r, 1, "zero returned the windows to their native look")
    T.eq(chrome.r, 1, "and the unit frame too")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedUIParent
    _G.PlayerFrame = savedPlayer
end

T.suite("darkness: the common pass picks a mode like the rest")

do
    T.ok(Darkness.options.args[Darkness.OptionKey("window")] ~= nil,
        "the common pass has its own mode, like the named areas")
end

T.suite("darkness: the alpha is never touched")

-- A defect from the client: the standard red button appeared again under ours.
-- The cause is not the colour but the alpha. The whole styling layer hides the
-- native game textures by alpha, while the darkening wrote it along with the
-- colour -- and a remembered one at that, the one from before the styling. The
-- written alpha brought the hidden back onto the screen, and not only on buttons.
do
    -- A texture the styling hid with a vertex alpha of zero.
    -- The path taken is an ordinary trim one: button textures have for some
    -- time counted as content (CONTENT_PATHS, the list taken from DarkMode),
    -- and this is not about them but about the alpha.
    local hidden = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = "Interface\\DialogFrame\\UI-DialogBox-Background" })
    hidden.a = 0

    T.eq(Darkness.Tint(hidden, 0.5), true, "the darkening was applied")
    T.eq(hidden.a, 0, "while what was hidden stayed hidden")
    T.ok(close(hidden.r, 0.5), "the colour meanwhile was multiplied")

    -- And on the second pass too: there is no remembered alpha any more.
    T.eq(Darkness.Tint(hidden, 0.3), true, "the second pass was applied")
    T.eq(hidden.a, 0, "the alpha is still untouched")

    -- An alpha changed by the styling between two passes stays the one the
    -- styling left rather than the one we remembered.
    local shown = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = "Interface\\Buttons\\UI-Panel-Button-Up" })
    Darkness.Tint(shown, 0.5)
    shown.a = 0
    Darkness.Tint(shown, 0.5)
    T.eq(shown.a, 0, "the darkening does not undo what the styling did")
end

T.suite("darkness: our own widgets are outside the pass")

-- The rule "we skip the unnamed" was meant for exactly this and did not work:
-- AceGUI creates its widgets as named global frames under UIParent, and the
-- pass by name walked straight into our settings window.
do
    -- An AceGUI widget: it has a name and the name is not ours, but it does have an obj field.
    local widgetArt = newArt()
    local widget = newFrame("Button", "AceGUI30Button1", { widgetArt })
    widget.obj = { type = "Button", frame = widget }

    T.eq(Darkness.IsOurs(widget), true, "a library widget is recognised by obj")
    T.eq(Darkness.ShouldSweep(widget), false, "and is not taken into the pass")
    T.eq(Darkness.ApplyToFrame(widget, 0.5), 0,
        "and it is not darkened directly either")
    T.eq(widgetArt.r, 1, "its texture is untouched")

    -- A widget with no obj but with a library name: the second line of defence.
    local tipArt = newArt()
    local tip = newFrame("Frame", "AceGUITooltip", { tipArt })
    T.eq(Darkness.IsOurs(tip), true, "a library frame is recognised by name")
    T.eq(Darkness.ApplyToFrame(tip, 0.5), 0, "and stays untouched")

    -- A frame the styling layer has already repainted in our palette:
    -- multiplying it again means turning it into a black rectangle.
    local paintedArt = newArt()
    local painted = newFrame("Frame", "SomeGameFrame", { paintedArt })
    painted.umbraStripped = true
    T.eq(Darkness.IsOurs(painted), true, "a repainted frame is recognised by its mark")
    T.eq(Darkness.ApplyToFrame(painted, 0.5), 0, "and does not get a second multiplication")

    -- Our own frame.
    T.eq(Darkness.IsOurs(newFrame("Frame", "DarkenMoverOverlay", {})), true,
        "our own frame is recognised by its prefix")

    -- While a foreign addon window in the game style is not ours and darkens as it should.
    local otherArt = newArt("Interface\\DialogFrame\\UI-DialogBox-Background")
    local other = newFrame("Frame", "SomeAddonFrame", { otherArt })
    T.eq(Darkness.IsOurs(other), false, "a foreign window in the game style is not ours")
    T.eq(Darkness.ApplyToFrame(other, 0.5), 1, "and it is darkened")

    -- A widget nested inside a darkened window is not touched either: the rule
    -- is asked at every level rather than only at the root.
    local innerArt = newArt()
    local inner = newFrame("Frame", "AceGUI30Frame2", { innerArt })
    inner.obj = { type = "Frame", frame = inner }
    local host = newFrame("Frame", "HostFrame", { newArt() }, { inner })
    T.eq(Darkness.ApplyToFrame(host, 0.5), 1,
        "only the window's own texture was darkened")
    T.eq(innerArt.r, 1, "the nested widget is untouched")
end

T.suite("darkness: the probe -- why this window did not darken")

-- A window that stayed light looks the same under any of the six causes, and
-- before the probe the answer to a screenshot was a guess. What is checked
-- here is that the probe names the actual cause rather than one of its own:
-- its questions are the walk's own -- the type, the ban, the protection, the depth and the selection rule.
do
    -- The window: its own texture (darkens), an ability icon (content), a bar
    -- (the type is skipped entirely) and a nested frame with a texture.
    local art  = newArt("Interface\\FrameGeneral\\UI-Background-Rock")
    local icon = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = "Interface\\Icons\\Spell_Holy_WordFortitude" })
    local bar  = newFrame("StatusBar", "TalentBar", { newArt() })

    local innerArt = newArt("Interface\\TalentFrame\\Priest-Discipline")
    local inner = newFrame("Frame", "TalentTreeOne", { innerArt })

    local window = newFrame("Frame", "PlayerTalentFrame",
        { art, icon }, { bar, inner })

    local records, tally = Darkness.Probe(window)

    T.eq(tally[Darkness.PROBE_DIMS], 2,
        "two textures will darken: the window border and the tree backdrop")
    T.eq(tally["content: path"], 1, "the icon is named content by its path")
    T.eq(tally["type is skipped whole"], 1,
        "the bar is named skipped by type")

    --- Find a record by object name.
    local function recordOf(name)
        for i = 1, #records do
            if records[i].name == name then return records[i] end
        end
        return nil
    end

    -- The depth in the record is the real one: without it "it did not reach"
    -- is indistinguishable from "it reached and did not take".
    T.eq(recordOf("TalentBar").depth, 1, "the child lies on the first level")

    -- A texture is named by what it was assigned: a path, an atlas or a file
    -- id. An id by itself no longer counts as content (in current builds almost
    -- all the trim is named by one), so an id from the blocked list is taken --
    -- a bar fill.
    local numbered = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = 137012 })
    local numberedWindow = newFrame("Frame", "NumberedFrame", { numbered })
    local list, count = Darkness.Probe(numberedWindow)
    T.eq(count["content: file"], 1, "a texture by file id is content")
    T.eq(list[1].image, "file 137012", "and the id is named in the line")

    -- The chat lines: the first is the tally by cause, then only what did NOT
    -- darken. Listing what did darken would mean drowning the answer.
    local lines = Darkness.ProbeLines(records, tally, 20)
    T.ok(#lines >= 2, "the lines are assembled: " .. #lines)
    T.ok(lines[1]:find("dims: 2", 1, true) ~= nil,
        "the tally by cause comes as the first line: " .. lines[1])

    local mentioned = table.concat(lines, "\\n")
    T.ok(mentioned:find("TalentBar", 1, true) ~= nil,
        "what did not darken is named individually")
    T.ok(mentioned:find("UI-Background-Rock", 1, true) == nil,
        "while what did darken did not make it into the list")

    -- The record cap is respected: hundreds of chat lines are not an answer.
    local short = Darkness.ProbeLines(records, tally, 1)
    T.eq(#short, 2, "the cap cuts the list while the tally remains")
end

T.suite("darkness: the protected game windows are the player's choice")

-- The talent window stayed light under any settings: the walk left it at level
-- zero, because the engine keeps that window under watch.
-- The probe in a live client said it in words: "1. [0] Frame
-- PlayerSpellsFrame - protected by the engine».
--
-- The price of touching such a window is not visible at once and is not paid
-- by us, so the decision is given to the player. And the buttons are not
-- touched under any answer: a click on a button IS a protected action, and it
-- was precisely on a bar button that the author's cooldown already broke.
do
    local saved = ns.Addon

    --- A protected object: the same question the walk asks.
    local function guard(object)
        object.IsProtected = function() return true end
        return object
    end

    local art = newArt("Interface\\TalentFrame\\Priest-Discipline")
    local window = guard(newFrame("Frame", "PlayerSpellsFrame", { art }))

    -- A fresh install darkens them too: an addon leaving a whole window light
    -- does not do the thing it is installed for.
    T.eq(Darkness.defaults.protectedWindows, true,
        "the default is to darken the protected windows")

    ns.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {}, protectedWindows = true } } } }
    T.eq(Darkness.EnterProtected(), true, "and it was read")
    T.eq(Darkness.ApplyToFrame(window, 0.5), 1,
        "the protected window is darkened")
    T.ok(close(art.r, 0.5), "and its texture was multiplied")

    -- The player cleared the checkbox -- the window is untouched again. The
    -- switch is there: touching a protected window has a price, and the player pays it.
    local other = newArt("Interface\\TalentFrame\\Priest-Shadow")
    local another = guard(newFrame("Frame", "PlayerSpellsFrameOff", { other }))
    ns.Addon.db.profile.darkness.protectedWindows = false
    T.eq(Darkness.EnterProtected(), false, "the player's choice was read")
    T.eq(Darkness.ApplyToFrame(another, 0.5), 0,
        "the protected window is untouched")
    T.eq(other.r, 1, "and its texture stayed native")

    ns.Addon.db.profile.darkness.protectedWindows = true

    -- An action bar button too, and that is a decision against the former one:
    -- the addon taken as a model tints it as well, and an untinted button next
    -- to a dark backdrop looks broken.
    local slot = newArt("Interface\\Buttons\\UI-Quickslot2")
    local button = guard(newFrame("Button", "ActionButton1", { slot }))
    T.eq(Darkness.ApplyToFrame(button, 0.5), 1,
        "the protected button is darkened")
    T.ok(close(slot.r, 0.5), "its trim was multiplied")

    -- While the ability icon on the same button is not: the player recognises
    -- the spell by the icon, and the selection rule is asked of every texture separately.
    local spell = newArt("Interface\\Icons\\Spell_Fire_Fireball")
    local armed = guard(newFrame("Button", "ActionButton2",
        { newArt("Interface\\Buttons\\UI-Quickslot2"), spell }))
    T.eq(Darkness.ApplyToFrame(armed, 0.5), 1, "only the trim was taken")
    T.eq(spell.r, 1, "the icon stayed its own")

    -- The ability cooldown is not touched at all: it shows time the way a bar
    -- shows a magnitude, and it is exactly where the author's button broke.
    --
    local sweep = newArt("Interface\\Cooldown\\star4")
    local cooldown = guard(newFrame("Cooldown", "ActionButton1Cooldown", { sweep }))
    local withCd = guard(newFrame("Button", "ActionButton3",
        { newArt("Interface\\Buttons\\UI-Quickslot2") }, { cooldown }))
    T.eq(Darkness.ApplyToFrame(withCd, 0.5), 1, "only the button trim was taken")
    T.eq(sweep.r, 1, "the cooldown fill is untouched")

    ns.Addon = saved
end

T.suite("darkness: a quest window darkens along with the text on it")

-- The rule "the text and what it is printed on, together or not at all"
-- stayed, but is fulfilled by the other half: the page darkens along with
-- everything, and the dark text on it is lifted into light. The author said it
-- outright: "you can just make it light, since our background is dark".
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }

    -- The page, a dark line on it and the yellow name of the speaker.
    local page = newArt("Interface\\QuestFrame\\QuestBackground")
    local body = newRegion({ kind = "FontString", layer = "OVERLAY" })
    body.r, body.g, body.b = 0.16, 0.13, 0.10
    function body:GetTextColor() return self.r, self.g, self.b, 1 end
    function body:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end

    local title = newRegion({ kind = "FontString", layer = "OVERLAY" })
    title.r, title.g, title.b = 1, 0.82, 0
    function title:GetTextColor() return self.r, self.g, self.b, 1 end
    function title:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end

    local panel = newFrame("Frame", "QuestFrameDetailPanel",
        { page, body, title })
    local quest = newFrame("Frame", "QuestFrame", {}, { panel })

    T.eq(Darkness.ApplyToWindow(quest), 1, "the page made it into the plan")
    T.ok(close(page.r, helpers.whiteAt(Darkness.Factor(64))),
        "and is darkened like everything else")

    local ink = select(1, Darkness.Ink())
    T.ok(close(body.r, ink), "the dark line was lifted into light")
    T.eq(title.r, 1, "the yellow name of the speaker is untouched")
    T.eq(title.g, 0.82, "in any channel")

    -- The restore: the page is light again, and the text must come back dark.
    T.ok(Darkness.DropText() >= 1, "the labels were restored")
    T.ok(close(body.r, 0.16), "the line is its own colour again")

    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: clearing the protected-windows checkbox restores the native look")

-- An ordinary "restore as it was" is done by the plan itself: an area in the
-- "as in the game" mode gets a one, and the application writes the remembered
-- colour back. That works exactly as long as the texture stays in the plan.
--
-- A protected window LEAVES the plan: after the checkbox is cleared the scan
-- does not enter it at all. Without restoring the plan it would stay dark
-- until an interface reload -- "I switched it off and the talents are dark".
do
    local savedFlavor, savedAddon, savedUIParent =
        ns.flavor, ns.Addon, _G.UIParent

    local art = newArt("Interface\\TalentFrame\\Priest-Discipline")
    local window = newFrame("Frame", "PlayerSpellsFrame", { art })
    window.IsProtected = function() return true end

    _G.UIParent = newFrame("Frame", "UIParent", {}, { window })
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {}, protectedWindows = true } } } }

    Darkness:ApplySettings()
    T.ok(close(art.r, helpers.whiteAt(Darkness.Factor(64))),
        "the protected window is darkened")

    -- The checkbox cleared: first the restore, then a scan without that window.
    local node = Darkness.options.args.protectedWindows
    node.set(nil, false)

    T.eq(art.r, 1, "and the window returned to its native look")

    ns.flavor, ns.Addon, _G.UIParent = savedFlavor, savedAddon, savedUIParent
end

T.suite("darkness: the probe answers about what happens now")

-- The probe goes by the same questions as the walk, and its answer must match
-- what the walk did. The protection by itself is no longer a verdict: a
-- cleared checkbox makes it one. A probe answering "protected by the engine"
-- where the walk calmly went inside would be lying about exactly the thing it
-- is called for.
do
    local saved = ns.Addon

    local art = newArt("Interface\\TalentFrame\\Priest-Discipline")
    local window = newFrame("Frame", "PlayerSpellsFrame", { art })
    window.IsProtected = function() return true end

    ns.Addon = { db = { profile = { darkness = {
        amount = 64, mode = {}, protectedWindows = true } } } }

    local records, tally = Darkness.Probe(window)
    T.eq(tally["protected by the engine, setting off"], nil,
        "with the checkbox on the protection does not count as a verdict")
    T.eq(tally[Darkness.PROBE_DIMS], 1, "and the window texture is named as darkening")

    ns.Addon.db.profile.darkness.protectedWindows = false
    records, tally = Darkness.Probe(window)
    T.eq(tally["protected by the engine, setting off"], 1,
        "with it cleared, both the protection and the cause are named")
    T.eq(tally[Darkness.PROBE_DIMS], nil, "and there is nothing left to darken")

    ns.Addon = saved
end

T.suite("darkness: the text is lifted again on every page")

-- The walk goes over a window once: the same window is not walked again until
-- it changes. But the game rewrites the text in it on every page -- a new
-- quest, a new conversation -- and the colour is set anew over ours. Without a
-- repeated lift the first page would be light and every following one black on
-- dark.
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }

    local body = newRegion({ kind = "FontString", layer = "OVERLAY" })
    body.r, body.g, body.b = 0.16, 0.13, 0.10
    function body:GetTextColor() return self.r, self.g, self.b, 1 end
    function body:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end

    local quest = newFrame("Frame", "QuestFrame", { body })

    T.eq(Darkness.ApplyToWindow(quest), 0, "there are no textures in the window")
    local ink = select(1, Darkness.Ink())
    T.ok(close(body.r, ink), "but the line was lifted")

    -- The game rewrote the colour: the next quest was opened.
    body.r, body.g, body.b = 0.16, 0.13, 0.10

    -- The window did not change, the walk is skipped -- and the text is lifted all the same.
    T.eq(Darkness.ApplyToWindow(quest), 0, "the window is the same one")
    T.ok(close(body.r, ink), "while the line was lifted again")

    Darkness.DropText()
    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: a lifted label is shadowless and almost white")

-- The shadow is drawn for dark text on a light page: there it separates the
-- letter from the background. On a dark page it does the opposite -- it blurs
-- a light letter with a dark halo. The author: "stop playing with the border,
-- the shadow and so on, just make the text colour almost white".
do
    local text = { r = 0.16, g = 0.13, b = 0.10,
        shadow = { 0, 0, 0, 1 }, offset = { 1, -1 } }
    function text:GetObjectType() return "FontString" end
    function text:GetTextColor() return self.r, self.g, self.b, 1 end
    function text:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end
    function text:GetShadowColor()
        return self.shadow[1], self.shadow[2], self.shadow[3], self.shadow[4]
    end
    function text:SetShadowColor(r, g, b, a) self.shadow = { r, g, b, a } end
    function text:GetShadowOffset() return self.offset[1], self.offset[2] end
    function text:SetShadowOffset(x, y) self.offset = { x, y } end

    T.eq(Darkness.LiftText(text), true, "the label was lifted")

    local ink = select(1, Darkness.Ink())
    -- Nine tenths of white -- the number was named by the author: "the texts on
    -- artwork should be 90% white, the texts on windows should be 90% white".
    T.ok(math.abs(ink - 0.9) < 1e-9, "the colour is nine tenths of white: " .. ink)
    T.ok(close(text.r, ink), "and the label is painted with it")
    T.eq(text.shadow[4], 0, "the shadow was removed by alpha")
    T.eq(text.offset[1], 0, "and by the horizontal offset")
    T.eq(text.offset[2], 0, "and the vertical one")

    -- The restore brings everything back: the colour, the shadow and the offset.
    T.ok(Darkness.DropText() >= 1, "the label was restored")
    T.ok(close(text.r, 0.16), "its own colour")
    T.eq(text.shadow[4], 1, "its own shadow")
    T.eq(text.offset[1], 1, "and its own offset")
end

T.suite("darkness: a page is lifted even when the text arrived later")

-- The decision "this label is dark" is made by its colour, and the game sets
-- the colour not when we walk the window: the quest page is empty until the
-- player has chosen a quest. A walk that looked in earlier finds nothing, and
-- the window has "not changed" since. The author sent exactly that: "where do
-- you see a changed colour?".
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }

    local function newText(r, g, b)
        local text = newRegion({ kind = "FontString", layer = "OVERLAY" })
        text.r, text.g, text.b = r, g, b
        function text:GetTextColor() return self.r, self.g, self.b, 1 end
        function text:SetTextColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end
        return text
    end

    -- The page is empty: the label is white because there is no text in it yet.
    local body = newText(1, 1, 1)
    local scroll = newFrame("Frame", nil, { body })
    local panel = newFrame("Frame", "QuestMapFrame", {}, { scroll })
    local map = newFrame("Frame", "WorldMapFrame", {}, { panel })

    Darkness.ApplyToWindow(map)
    T.eq(body.r, 1, "an empty label is untouched: it was never dark")

    -- The player chose a quest -- the game wrote the text in its own brown.
    body.r, body.g, body.b = 0.16, 0.13, 0.10

    -- No window changed meanwhile, and the walk would have skipped it.
    T.eq(Darkness.LiftPages() >= 1, true, "the page pass found the label")

    local ink = select(1, Darkness.Ink())
    T.ok(close(body.r, ink), "and lifted it")

    Darkness.DropText()
    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: an edit box stays an edit box")

-- The author sent a chat line with a black caret: "why is the cursor in the
-- chat black?". The caret is drawn by the engine, it is not visible to us as a
-- separate object, and it takes its colour from the box, which we darkened
-- along with all the trim. The darker the end of the scale, the less it is
-- visible, and a line in which you cannot see where you type is not an input line.
--
-- So an edit box is not darkened at all: neither itself nor from inside.
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 100, mode = {} } } } }

    local inside = newRegion({ kind = "Texture", layer = "BACKGROUND",
        texture = "Interface\\ChatFrame\\UI-ChatInputBorder-Left" })
    local box = newFrame("EditBox", "ChatFrame1EditBox", { inside })

    local chrome = newArt("Interface\\ChatFrame\\ChatFrameBackground")
    local chat = newFrame("Frame", "ChatFrame1", { chrome }, { box })

    T.eq(Darkness.ApplyToWindow(chat), 1,
        "one texture was darkened: the window trim, but not the edit box")
    T.eq(inside.r, 1, "the inside of the edit box stayed native")
    T.ok(chrome.r < 1, "while the trim of the window itself is darkened")

    -- And the box itself, if the pass starts right at it.
    T.eq(Darkness.ApplyToWindow(box), 0, "an edit box is not darkened head-on either")

    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: the world map canvas does not darken")

-- The map is a picture of the world rather than window trim: it is read, and
-- the markers on it are told apart by colour. The author sent a darkened map
-- saying "the map and the markers on it should be default".
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 80, mode = {} } } } }

    local tile = newArt("Interface\\WorldMap\\Tirisfal\\Tirisfal1")
    local pin = newArt("Interface\\WorldMap\\UI-QuestBlob")
    local canvas = newFrame("Frame", "WorldMapCanvas", { tile }, {
        newFrame("Frame", "QuestPin", { pin }) })
    local savedCanvas = _G.WorldMapDetailFrame
    _G.WorldMapDetailFrame = canvas

    local chrome = newArt("Interface\\DialogFrame\\UI-DialogBox-Border")
    local map = newFrame("Frame", "WorldMapFrame", { chrome }, { canvas })

    T.eq(Darkness.ApplyToWindow(map), 1, "only the window border was darkened")
    T.eq(tile.r, 1, "the terrain stayed native")
    T.eq(pin.r, 1, "and so did the marker on it")
    T.ok(chrome.r < 1, "while the border of the map window is darkened")

    _G.WorldMapDetailFrame = savedCanvas

    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: the colour picker window is not touched")

-- The colour wheel and the swatches are the very subject of the choice: there
-- is nothing to choose from in a darkened wheel, and a desaturated one shows
-- no colour at all. The author sent a grey colour picker: "why are the colours not visible".
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = {
        amount = 80, desaturate = true, mode = {} } } } }

    local wheel = newArt("Interface\\ColorPicker\\ColorWheel")
    local picker = newFrame("Frame", "ColorPickerFrame", { wheel })
    local savedPicker = _G.ColorPickerFrame
    _G.ColorPickerFrame = picker

    local other = newArt("Interface\\DialogFrame\\UI-DialogBox-Border")
    local window = newFrame("Frame", "MerchantFrame", { other })

    local savedRoot = _G.UIParent
    _G.UIParent = newFrame("Frame", "UIParent", {}, { picker, window })

    Darkness:ApplySettings()

    T.eq(wheel.r, 1, "the colour wheel stayed native")
    T.ok(other.r < 1, "while the neighbouring window is darkened")

    _G.ColorPickerFrame = savedPicker
    _G.UIParent = savedRoot
    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: our own window is walked on show too")

-- A window of a named area -- the character sheet, the reputation, the bags,
-- the chat -- formerly was not walked on show at all: it counted as taken by
-- a named group, and what is taken is walked only by a full scan. And the scan
-- happens on entering the world, when the character window holds not a single
-- section: the game creates them on first open.
--
-- The author found it himself: the headings in the character window stayed
-- golden, and switching any checkbox off and on fixed them -- that road goes
-- through a full scan with the window already filled.
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }

    local header = newArt("Interface\\Buttons\\UI-Panel-Button-Up")
    local pane = newFrame("Frame", "CharacterStatsPane", { header })
    local sheet = newFrame("Frame", "CharacterFrame", {}, { pane })

    local savedSheet = _G.CharacterFrame
    _G.CharacterFrame = sheet

    -- The restore paints the plan from the start, so the count here is the whole
    -- plan rather than only this texture. What matters is not the number but that the heading darkened.
    T.ok(Darkness.ApplyToWindow(sheet, true) >= 1,
        "showing our own window darkened nothing")
    T.ok(header.r < 1, "the late heading stayed light")

    _G.CharacterFrame = savedSheet
    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: the hidden is not walked")

-- The talent window is not fifteen hundred textures but ten thousand, of which
-- a tenth is shown: tabs the player never opened, list rows in reserve,
-- tooltips created in advance. The walk went over all of them while the eye
-- saw a tenth -- and the player saw the hitch.
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }

    local open = newArt("Interface\\DialogFrame\\UI-DialogBox-Border")
    local tucked = newArt("Interface\\DialogFrame\\UI-DialogBox-Border")

    local shownTab = newFrame("Frame", "ShownTab", { open })
    shownTab.IsShown = function() return true end

    local hiddenTab = newFrame("Frame", "HiddenTab", { tucked })
    hiddenTab.IsShown = function() return false end

    local window = newFrame("Frame", "MerchantFrame", {},
        { shownTab, hiddenTab })

    Darkness.ApplyToWindow(window)

    T.ok(open.r < 1, "the shown tab stayed light")
    T.eq(tucked.r, 1, "the hidden tab was walked after all")

    -- The hidden is not lost: it will be shown -- and walked at that moment.
    hiddenTab.IsShown = function() return true end
    Darkness.ApplyToWindow(window, true)
    T.ok(tucked.r < 1, "the shown tab stayed light after all")

    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: in the aura area the icon itself darkens")

-- The rule "an icon does not darken" holds for the whole interface: an icon is
-- how one recognises an item, a spell, a bar button. Buffs and debuffs have no
-- trim at all -- the icon there IS everything -- and the "Buffs and Debuffs"
-- area in the settings would answer for nothing. The author asked: "why are
-- the buffs not darkened?".
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }

    local icon = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = "Interface\\Icons\\Spell_Holy_Renew" })
    local buff = newFrame("Frame", "BuffButton1", { icon })
    local frame = newFrame("Frame", "BuffFrame", {}, { buff })

    local savedBuffs = _G.BuffFrame
    _G.BuffFrame = frame

    Darkness:ApplySettings()
    T.ok(icon.r < 1, "the buff icon stayed light")

    -- While the same icon in a bag is still untouched.
    local bagIcon = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = "Interface\\Icons\\Spell_Holy_Renew" })
    local bagWindow = newFrame("Frame", "MerchantFrame", { bagIcon })

    Darkness.ApplyToWindow(bagWindow)
    T.eq(bagIcon.r, 1, "an icon in an ordinary window is darkened")

    _G.BuffFrame = savedBuffs
    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("probe: what we wrote and what is on the texture now")

-- "It did not darken" looks the same from outside under two different
-- troubles: we did not paint it -- or we did and the game painted over us.
-- They can be told apart only by numbers, and the probe names them.
do
    local savedFlavor, savedAddon = ns.flavor, ns.Addon
    ns.flavor = "vanilla"
    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }

    local art = newArt("Interface\\DialogFrame\\UI-DialogBox-Border")
    local window = newFrame("Frame", "MerchantFrame", { art })

    Darkness.ApplyToWindow(window)

    -- The game painted over us without saying so.
    art.r, art.g, art.b = 1, 1, 1

    local records = Darkness.Probe(window)
    local found = nil
    for i = 1, #records do
        if records[i].kind == "Texture" then found = records[i] end
    end

    T.ok(found ~= nil, "the texture is not named in the probe")
    T.ok(found and found.wrote ~= nil, "it does not say what we wrote")
    T.ok(found and found.now ~= nil, "it does not say what is on the texture now")
    T.ok(found and found.wrote ~= found.now,
        "the probe does not see the difference between what was written and what is on screen")

    ns.flavor, ns.Addon = savedFlavor, savedAddon
end

T.suite("darkness: the probe says what it could not keep")

-- The ceiling was four hundred records, and one window answers with more than
-- a thousand: the character sheet counted 1273 textures, printed that number
-- in its tally and kept the first four hundred. Two thirds of the evidence
-- never reached the file and nothing said so, which is how a measurement
-- comes to be believed while being wrong.
do
    local many = {}
    for i = 1, 30 do
        many[i] = newArt("Interface\\FrameGeneral\\UI-Background-Rock")
    end

    -- A window the walk knows, for the same reason the suite above uses it:
    -- an unnamed stranger is turned back at the threshold and the
    -- regions are never reached.
    local window = newFrame("Frame", "PlayerTalentFrame", many)

    local kept, tally, dropped = Darkness.Probe(window, 10)

    T.eq(#kept, 10, "only as many records as there was room for")
    T.ok(dropped > 0, "and the rest are counted rather than lost: "
        .. tostring(dropped))

    local counted = 0
    for _, n in pairs(tally) do counted = counted + n end
    T.eq(counted, #kept + dropped,
        "the tally equals what was kept plus what was dropped")

    -- With the ordinary ceiling the whole window fits, and nothing is missing.
    local all, _, none = Darkness.Probe(window)
    T.eq(none, 0, "nothing is reported missing when everything fits")
    T.ok(#all > 10, "and the whole window is kept: " .. #all)
end

T.suite("darkness: an atlas in an icon field is still framing")

-- The field rule exists for an item's icon and a unit's portrait: the owner
-- knows what they are sooner and more exactly than any look at the picture.
-- What it did not know is that today's templates keep their OWN artwork in a
-- field of the same name. The author's probe of the character sheet named
-- them one after another - "content: owner field, atlas common-icon-zoomin",
-- the same for rotateleft, rotateright, undo and a stat bar. Those are the
-- model's turn buttons, spared as though they were a player's face and left
-- bright in a dark window.
do
    -- The frame keeps three pictures in icon fields: its own button art from
    -- an atlas, an item's icon from a file, and a portrait from a file.
    local chrome = newRegion({ kind = "Texture", layer = "ARTWORK",
        atlas = "common-icon-zoomin" })
    local item = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = 134939 })
    local face = newRegion({ kind = "Texture", layer = "ARTWORK",
        texture = 626004 })

    local window = newFrame("Frame", "PaperDollFrame", { chrome, item, face })
    window.Icon = chrome
    window.icon = item
    window.portrait = face

    local records = Darkness.Probe(window)

    local verdict = {}
    for i = 1, #records do
        local r = records[i]
        if r.image and r.image:find("zoomin", 1, true) then
            verdict.chrome = r.verdict
        end
    end

    T.eq(verdict.chrome, Darkness.PROBE_DIMS,
        "a button's own art from an atlas is framing, whatever field holds it")

    -- And the two that the rule exists for keep their exemption: an item's
    -- icon and a portrait arrive as files, never as an atlas.
    local spared = 0
    for i = 1, #records do
        if records[i].verdict ~= Darkness.PROBE_DIMS then spared = spared + 1 end
    end
    T.ok(spared >= 2, "the item icon and the portrait are still spared: " .. spared)
end
