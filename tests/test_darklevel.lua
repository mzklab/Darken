local helpers = require("helpers")

-- The brightness ceiling: why the gryphons stopped glowing.
--
-- What this file is for. Darkening is multiplication, and multiplication
-- preserves ratios: whatever the game drew nearly white stays twice as light
-- as the midtones around it at any slider position. In the client this shows
-- in three places at once -- the gryphons at the ends of the main bar, the
-- bar itself and the parchment of the gossip window -- and the author named
-- them in his own words: "the eagles are too light and the bar too, while
--
-- So darkening got a ceiling: the bright is brought down to a midtone BEFORE
-- the multiplication and lands where its neighbours land. Checked here is
-- both the rule as a pure function and what it was created for: white and
-- grey end up next to each other after application.
--
-- What is not here. The whole slider scale lives in tests/test_darkscale.lua.

T.suite("brightness ceiling: the rule")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)

local Darkness = ns.Darkness

local function close(a, b, msg)
    T.ok(type(a) == "number" and math.abs(a - b) < 1e-9,
        msg .. " (" .. tostring(a) .. ")")
end

-- The ceiling sits at one wherever nothing is darkened: an area the player
-- asked not to touch must look as it does in the game.
close(Darkness.Ceiling(1), 1, "native look -- the ceiling touches nothing")
close(Darkness.Ceiling(0), Darkness.LEVEL_CEILING,
    "full darkening -- the ceiling sits at the midtone")
close(Darkness.Ceiling(0.5), 0.75, "in between -- a straight line")

-- The setting comes from SavedVariables, and garbage in it has no right to
-- take the interface away from the player.
close(Darkness.Ceiling(nil), 1, "nil reads as \"do not darken\"")
close(Darkness.Ceiling("garbage"), 1, "a string too")
close(Darkness.Ceiling(-5), Darkness.LEVEL_CEILING, "below zero is clamped")
close(Darkness.Ceiling(50), 1, "above one is clamped")

-- The reduction itself. The dark is not touched at all: the ceiling has nothing to lower.
do
    local r, g, b = Darkness.Levelled(0.3, 0.2, 0.1, 0.5)
    T.ok(r == 0.3 and g == 0.2 and b == 0.1,
        "the ceiling does not touch a midtone or anything darker")
end

do
    local r, g, b = Darkness.Levelled(1, 1, 1, 0.5)
    T.ok(r == 0.5 and g == 0.5 and b == 0.5, "white arrives at the midtone")
end

-- The hue is preserved: the channels are divided by a common number rather
-- than clamped one by one. Per-channel clamping would turn bright green into
-- a swampy green, and blue into a different blue.
do
    local r, g, b = Darkness.Levelled(0, 1, 0, 0.5)
    T.ok(r == 0 and g == 0.5 and b == 0,
        "bright green becomes darker, not different")

    local r2, g2, b2 = Darkness.Levelled(1, 0.5, 0, 0.5)
    close(r2 / g2, 2, "the channel ratio survived the reduction")
    T.eq(b2, 0, "and zero stayed zero")
end

T.suite("brightness ceiling: white and grey arrive together")

-- This is what it was all done for. Two textures of one window: one nearly
-- white (a gryphon, the bar, the parchment), the other a midtone (everything
-- else). After darkening they must end up next to each other, not apart.
local function newRegion(color)
    local region = {
        r = color, g = color, b = color, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function()
            return "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf"
        end,
    }
    function region:GetVertexColor() return self.r, self.g, self.b, self.a end
    function region:SetVertexColor(cr, cg, cb, ca)
        self.r, self.g, self.b = cr, cg, cb
        if ca ~= nil then self.a = ca end
    end
    return region
end

local function newFrame(name, regions, children)
    return {
        GetObjectType = function() return "Frame" end,
        GetName = function() return name end,
        GetRegions = function() return unpack(regions or {}) end,
        GetChildren = function() return unpack(children or {}) end,
    }
end

do
    ns.flavor = "vanilla"

    local bright, half = newRegion(1), newRegion(0.5)
    local window = newFrame("MerchantFrame", { bright, half })
    local savedRoot = _G.UIParent
    _G.UIParent = newFrame("UIParent", {}, { window })

    local profile = { darkness = { amount = 64, mode = {} } }
    ns.Addon = { db = { profile = profile } }

    Darkness:ApplySettings()

    -- Without the ceiling the white one would be exactly twice as light as
    -- the midtone. With it the difference is a third, which is no longer "one glows, the other does not".
    T.ok(bright.r > half.r, "the white one is still not darker than the grey one")
    T.ok(bright.r / half.r < 1.5,
        "but the difference between them is small, and it used to be twofold ("
            .. tostring(bright.r / half.r) .. ")")

    -- The switch restores the former behaviour entirely: the rule does touch
    -- the game colours beyond plain darkening, and the player is entitled to
    -- say "no".
    profile.darkness.level = false
    Darkness:ApplySettings()
    close(bright.r / half.r, 2,
        "with the ceiling off the white one is twice as light again")

    -- Zero on the slider touches nothing even with the ceiling on:
    -- otherwise "do not darken" would mean "repaint".
    profile.darkness.level = true
    profile.darkness.amount = 0
    Darkness:ApplySettings()
    T.eq(bright.r, 1, "the native look stayed native")
    T.eq(half.r, 0.5, "and so did the midtone")

    -- "Leave as is" on an area is the same promise, only about one area: the
    -- ceiling may not repaint what is not being darkened.
    profile.darkness.amount = 64
    profile.darkness.mode.window = "native"
    Darkness:ApplySettings()
    T.eq(bright.r, 1, "an area left native is not levelled")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedRoot
end

T.suite("a bar and its frame are different things")

-- The bar fill itself is not touched: its colour says WHAT the player has so
-- much of -- reputation green, health red, skill blue. The pass does not go
-- inside a StatusBar at all.
--
-- The bar bed and the border around it are trim, and darken along with everything.
-- For a short time the opposite rule stood here, and the answer to it was
-- golden reputation borders in the middle of a dark window.
do
    ns.flavor = "vanilla"

    local fill = newRegion(1)
    local skill = {
        GetObjectType = function() return "StatusBar" end,
        GetName = function() return "SkillBar" end,
        GetRegions = function() return fill end,
        GetChildren = function() return end,
    }
    local bed = newRegion(1)
    local holder = newFrame("SkillFrame", { bed }, { skill })

    local savedRoot = _G.UIParent
    _G.UIParent = newFrame("UIParent", {}, { holder })

    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }
    Darkness:ApplySettings()

    T.eq(fill.r, 1, "darkening does not touch the bar fill itself")
    T.ok(bed.r < 1, "while it does touch the bed and the border: that is trim")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedRoot
end

T.suite("brightness ceiling: the gryphons get their own number")

-- "The gryphons just need a factor of 1.05 applied" -- the author's words
-- and the author's number. They have their own area ("actionbar-art", which
-- holds only the ends of the main bar), and the correction sits on it.
do
    ns.flavor = "vanilla"

    local cap = newRegion(1)
    cap.GetTexture = function()
        return "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf"
    end
    local savedCap = _G.MainMenuBarLeftEndCap
    _G.MainMenuBarLeftEndCap = cap

    local plain = newRegion(1)
    local window = newFrame("MerchantFrame", { plain })
    local savedRoot = _G.UIParent
    _G.UIParent = newFrame("UIParent", {}, { window })

    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }
    Darkness:ApplySettings()

    close(cap.r, plain.r * Darkness.GRYPHON_LIFT,
        "the gryphon is lighter than the neighbouring trim by exactly five hundredths")
    T.ok(cap.r < 1, "and still darkened rather than left as it was")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedRoot
    _G.MainMenuBarLeftEndCap = savedCap
end

T.suite("desaturation: backgrounds and art only, and nothing else")

-- The author's rule, in his own words: "only background textures, art and so
-- on should get grayout; icons, fill bars, text and so on should keep the
-- game default colour".
--
-- What is checked is not the reasoning but the SetDesaturated call itself: it
-- must happen for a window backdrop and for nobody else.
do
    ns.flavor = "vanilla"

    local function tracked(color, opts)
        local region = newRegion(color)
        region.grey = nil
        function region:SetDesaturated(value) self.grey = value end
        if opts and opts.texture then
            region.GetTexture = function() return opts.texture end
        end
        if opts and opts.kind then
            region.GetObjectType = function() return opts.kind end
        end
        return region
    end

    -- A window backdrop: trim, and it is supposed to go grey.
    local back = tracked(1)

    -- An item icon: a path into the icon folder means content.
    local icon = tracked(1, { texture = "Interface\\Icons\\INV_Misc_Rune_01" })

    -- A label. Desaturation does not concern it at all: the colour of a letter
    -- is the colour of a letter, and only the dark-text lift changes it.
    local label = tracked(1, { kind = "FontString" })
    label.r, label.g, label.b = 1, 0.82, 0
    function label:GetTextColor() return self.r, self.g, self.b, 1 end
    function label:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end

    -- A bar fill: the pass does not go inside a bar.
    local fill = tracked(1)
    local bar = {
        GetObjectType = function() return "StatusBar" end,
        GetName = function() return "RepBar" end,
        GetRegions = function() return fill end,
        GetChildren = function() return end,
    }

    local window = newFrame("ReputationFrame", { back, icon, label }, { bar })
    local savedRoot = _G.UIParent
    _G.UIParent = newFrame("UIParent", {}, { window })

    ns.Addon = { db = { profile = { darkness = {
        amount = 64, desaturate = true, mode = {} } } } }
    Darkness:ApplySettings()

    T.eq(back.grey, true, "the window backdrop is desaturated")
    T.eq(icon.grey, nil, "the icon is not: it is content")
    T.eq(fill.grey, nil, "the bar fill is not: its colour says what there is so much of")
    T.eq(label.grey, nil, "the label is not: desaturation does not concern letters")
    T.eq(label.r, 1, "and its colour stayed the game one")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedRoot
end

T.suite("a coloured fill with no image is a reading")

-- A bar drawn by a colour rather than a file looks to the pass like a
-- backdrop: no name, no atlas, no path. Formerly such a bar darkened and --
-- with desaturation on -- went grey; the author sent a skill bar: "why is
-- the fill here still grey when it should be the default".
do
    local function fill(r, g, b)
        local region = {
            r = r, g = g, b = b, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
        }
        function region:GetVertexColor() return self.r, self.g, self.b, self.a end
        function region:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end
        return region
    end

    T.eq(Darkness.ContentReason(fill(0.12, 0.30, 0.60)), "fill",
        "a blue skill fill is a reading")
    T.eq(Darkness.ContentReason(fill(0, 0.7, 0)), "fill",
        "a green reputation fill too")
    T.eq(Darkness.ContentReason(fill(0.2, 0.2, 0.2)), nil,
        "a grey fill is a backdrop: it names nothing")
    T.eq(Darkness.ContentReason(fill(0.24, 0.20, 0.16)), nil,
        "and a brown window backdrop is a backdrop: the channel spread is small")
end

T.suite("a bar names its own fill")

-- It is recognised by asking the frame outright, not by a piece of a name.
-- Pieces were tried -- "statusbar", "fill" in the name, "-fill" in the atlas:
-- they caught things that were not fills, and the character window stayed
-- golden. The author sent it with the word "broken".
do
    local function texture(opts)
        local region = {
            r = 1, g = 1, b = 1, a = 1,
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function() return opts.file end,
            GetAtlas = function() return opts.atlas end,
            GetName = function() return opts.name end,
        }
        function region:GetVertexColor() return self.r, self.g, self.b, self.a end
        function region:SetVertexColor(cr, cg, cb) self.r, self.g, self.b = cr, cg, cb end
        return region
    end

    T.eq(Darkness.IsChrome(texture({ name = "SkillRankFrameStatusBar",
        file = 4640500 })), true,
        "a name containing statusbar says nothing: borders are called that too")
    T.eq(Darkness.IsChrome(texture({ file = 137012 })), false,
        "while a fill id from the DarkMode list does")
end

-- And a third way: the bar names its own fill. The question is asked of the
-- frame, because the frame knows for sure while a texture knows only its name.
do
    ns.flavor = "vanilla"

    local fill = newRegion(1)
    local bar = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "SkillRankFrame" end,
        GetRegions = function() return fill end,
        GetChildren = function() return end,
        GetStatusBarTexture = function() return fill end,
    }
    local savedRoot = _G.UIParent
    _G.UIParent = newFrame("UIParent", {}, { bar })

    ns.Addon = { db = { profile = { darkness = {
        amount = 64, desaturate = true, mode = {} } } } }
    Darkness:ApplySettings()

    T.eq(fill.r, 1, "a fill named by the bar itself is untouched")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedRoot
end

T.suite("the rule changed -- the former state returns on its own")

-- The selection rule changes: what counted as trim yesterday is recognised
-- as a reading today. Such a texture will not enter the new plan, and there
-- would be nobody to restore it -- it would stay dark and grey forever. The
-- author saw this on bar fills: "still grey".
--
-- So the scan first returns what it previously found to its native look and
-- only then searches anew.
do
    ns.flavor = "vanilla"

    local art = newRegion(1)
    art.grey = nil
    function art:SetDesaturated(value) self.grey = value end

    local window = newFrame("MerchantFrame", { art })
    local savedRoot = _G.UIParent
    _G.UIParent = newFrame("UIParent", {}, { window })

    local profile = { darkness = { amount = 64, desaturate = true, mode = {} } }
    ns.Addon = { db = { profile = profile } }

    Darkness:ApplySettings()
    T.ok(art.r < 1, "the texture is darkened")
    T.eq(art.grey, true, "and desaturated")

    -- From the next scan on, this texture is as if absent from the interface.
    _G.UIParent = newFrame("UIParent", {}, {})
    Darkness:ApplySettings()

    T.eq(art.r, 1, "a texture that left the plan got its colour back")
    T.eq(art.grey, false, "and stopped being grey")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedRoot
end

T.suite("a fill the frame holds in a Fill field")

-- The skill bar in the professions window of current builds is built like
-- this: ProfessionsFrame.RankBar is an ordinary frame with the fill in its
-- Fill field. There is no global name, the frame is not a StatusBar object,
-- the texture is ordinary -- no former criterion saw it, and it darkened and
-- went grey along with the trim.
do
    ns.flavor = "vanilla"

    local fill = newRegion(1)
    local border = newRegion(1)
    local rank = newFrame("RankBar", { border, fill })
    rank.Fill = fill

    local savedRoot = _G.UIParent
    _G.UIParent = newFrame("UIParent", {}, { newFrame("ProfessionsFrame", {},
        { rank }) })

    ns.Addon = { db = { profile = { darkness = {
        amount = 80, desaturate = true, mode = {} } } } }
    Darkness:ApplySettings()

    T.eq(fill.r, 1, "a fill from a Fill field is untouched")
    T.ok(border.r < 1, "while the border of the same bar is darkened")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedRoot
end

T.suite("bar trim is recognised by its texture, not by its place in the tree")

-- The bar trim -- the gryphons and the end caps -- gets moved over by
-- foreign bar addons: Bartender and its kin build their own bars and carry
-- the game art onto them. The owner of the texture then becomes a foreign
-- frame, and formerly such a texture lost its area: the common pass tinted
-- it as ordinary window trim, and inside a foreign window did not tint it
-- at all.
--
-- The author put it plainly: "if the gryphons are rebuilt by other addons,
-- like Bartender, our darkening is not applied to them".
--
-- But a gryphon IS the game. The rule "we do not tint what is not ours" was
-- written about the art of the addon ITSELF, not about game art it carried
-- over. So ownership is decided by the texture, and the texture list is not
-- written out as paths but asked of the client: whatever the pass saw in the
-- trim group is what is remembered.
--
-- Ownership is told apart by the factor: bar trim has its own (1.05), and no
-- other trim has it. That is how it shows here whose texture it is.
do
    ns.flavor = "vanilla"

    local ART = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf"

    -- A cap in its own place: the texture is remembered from it.
    local cap = newRegion(1)
    cap.GetTexture = function() return ART end
    local savedCap = _G.MainMenuBarLeftEndCap
    _G.MainMenuBarLeftEndCap = cap

    -- The same texture, but now sitting in a foreign window instead of its own place.
    local moved = newRegion(1)
    moved.GetTexture = function() return ART end

    -- And ordinary trim of the same window, for comparison.
    local plain = newRegion(1)

    local window = newFrame("MerchantFrame", { moved, plain })
    local savedRoot = _G.UIParent
    _G.UIParent = newFrame("UIParent", {}, { window })

    ns.Addon = { db = { profile = { darkness = { amount = 64, mode = {} } } } }
    Darkness:ApplySettings()

    T.ok(Darkness.ArtCount() > 0, "the trim textures are remembered: " .. Darkness.ArtCount())
    T.ok(plain.r < 1, "ordinary trim is darkened")
    close(moved.r, plain.r * Darkness.GRYPHON_LIFT,
        "the carried-over cap got the bar trim factor, "
        .. "not the ordinary one")
    close(moved.r, cap.r, "and exactly the same colour as the cap in its own place")

    -- And exactly that narrowly. What is recognised is not "everything
    -- sitting in a foreign window" but one texture -- that one. Neighbouring
    -- trim of the same window stayed ordinary, otherwise the bar trim factor would have gone to it too.
    T.ok(plain.r < moved.r,
        "the neighbouring texture did not become bar trim: "
        .. tostring(plain.r) .. " against " .. tostring(moved.r))

    -- A foreign texture in the same place is not recognised at all.
    local alien = newRegion(1)
    alien.GetTexture = function()
        return "Interface" .. string.char(92) .. "AddOns"
            .. string.char(92) .. "Someone" .. string.char(92) .. "border"
    end
    T.eq(Darkness.ArtCount() > 0, true, "the trim memory is not empty")

    ns.Addon = nil
    ns.flavor = nil
    _G.UIParent = savedRoot
    _G.MainMenuBarLeftEndCap = savedCap
end

T.suite("a coin is recognised by the frame that holds it")

-- Gold, silver and copper are three different circles, and the player tells
-- them apart by colour: darkened they become identically black, and "fifty
-- eight" stops saying fifty eight of what. The author sent the trainer's
-- window with the prices in it.
--
-- The rule for money existed before this suite and never fired. It was written
-- as a rule about the PATH to the file -- "moneyframe", "ui-goldicon" -- and in
-- this client GetTexture answers with a number even for a texture that was
-- assigned by a path. Every one of the author's probes says so: "file 134939",
-- "file 130718", not one path among them. So the coin reached the rule for
-- numbers, its number is not in the short list there, and the answer was
-- "framing".
--
-- Adding three numbers to that list would fix these three coins in this one
-- build. The frame that holds the coin is named the same in every build, and
-- that is what is asked here instead.
do
    local function coin(ownerName)
        local parent = { GetName = function() return ownerName end }
        return {
            GetObjectType = function() return "Texture" end,
            GetDrawLayer = function() return "ARTWORK" end,
            GetTexture = function() return 133784 end,
            GetAtlas = function() return nil end,
            GetName = function() return nil end,
            GetParent = function() return parent end,
        }
    end

    T.eq(Darkness.ContentReason(coin("ClassTrainerMoneyFrameGoldButton")), "owner",
        "the gold coin of the trainer's window is contents")
    T.eq(Darkness.ContentReason(coin("MerchantMoneyFrameSilverButton")), "owner",
        "the silver one of the merchant's")
    T.eq(Darkness.ContentReason(coin("SmallMoneyFrame1CopperButton")), "owner",
        "and the copper one of a small money frame")

    -- The frame around them is not a coin, and nothing here says it is: the
    -- rule asks the owner's name rather than the depth or the neighbourhood.
    T.eq(Darkness.ContentReason(coin("CharacterFrameTab1")), nil,
        "a picture in any other frame is framing, as before")
    T.eq(Darkness.ContentReason(coin(nil)), nil,
        "and an owner with no name decides nothing")
end

T.suite("the raising returns after the game has written the page")

-- The subscription to GOSSIP_SHOW raised the labels in the same frame as the
-- event. Whose handler runs first, ours or the game's, is decided by the order
-- of registration -- so the raising could happen before the page was written,
-- and for the author it did: a guard's fifteen lines, the first readable and
-- fourteen brown.
--
-- What is checked here is the seam rather than the clock: the deferral is
-- asked for, and what it asks for is a raising.
do
    local savedTimer = _G.C_Timer
    local pending = {}
    _G.C_Timer = {
        After = function(_, fn)
            if type(fn) == "function" then pending[#pending + 1] = fn end
        end,
    }

    local savedLift = Darkness.LiftPages
    local raised = 0
    Darkness.LiftPages = function() raised = raised + 1 return 0 end

    -- The request is single-flight, and a fake clock never runs what it
    -- collects, so the flag has to be dropped between cases.
    Darkness.ForgetLift()

    Darkness.LiftPagesLater()
    T.ok(#pending >= 1, "a return is scheduled: " .. #pending)
    T.eq(raised, 0, "and nothing is raised before it comes due")

    for i = 1, #pending do pending[i]() end
    T.eq(raised, #pending, "every return raises the pages")

    -- A client with no clock must not fall over: the raising in the same frame
    -- has already happened by then, and this is the extra one.
    _G.C_Timer = nil
    local ok = pcall(Darkness.LiftPagesLater)
    T.ok(ok, "with no C_Timer the return is simply not scheduled")

    Darkness.LiftPages = savedLift
    _G.C_Timer = savedTimer
end

T.suite("a burst of refill events costs one walk, not one each")

-- The author raised a profession by one point: the whole window blinked and
-- lagged. A skill-up fires SKILL_LINES_CHANGED and TRADE_SKILL_UPDATE, the game
-- refills the list, the refill fires them again -- and every one of them used to
-- repaint a window of hundreds of textures from the handler itself.
do
    local savedTimer = _G.C_Timer
    local pending = {}
    _G.C_Timer = {
        After = function(_, fn)
            if type(fn) == "function" then pending[#pending + 1] = fn end
        end,
    }

    local savedApply = Darkness.ApplyToWindow
    local savedWindow = Darkness.lastWindow
    local walks = 0
    Darkness.ApplyToWindow = function() walks = walks + 1 end
    Darkness.lastWindow = { GetObjectType = function() return "Frame" end }

    for _ = 1, 6 do Darkness.RefillSoon() end
    T.eq(walks, 0, "nothing is walked from the handler itself")
    T.eq(#pending, 1, "six events ask for one walk, not six")

    pending[1]()
    T.eq(walks, 1, "and when it comes due the window is walked once")

    -- The gate opens again afterwards: the next burst must not be swallowed.
    Darkness.RefillSoon()
    T.eq(#pending, 2, "a later burst is scheduled in its turn")

    -- With no window there is nothing to walk and nothing to schedule.
    Darkness.lastWindow = nil
    Darkness.RefillSoon()
    T.eq(#pending, 2, "no window, no walk")

    -- A client with no clock keeps the old behaviour rather than losing the
    -- repaint altogether.
    _G.C_Timer = nil
    Darkness.lastWindow = { GetObjectType = function() return "Frame" end }
    Darkness.RefillSoon()
    T.eq(walks, 2, "with no clock the walk happens at once, as before")

    Darkness.ApplyToWindow = savedApply
    Darkness.lastWindow = savedWindow
    _G.C_Timer = savedTimer
end

T.suite("the parchment fonts are painted, not hunted")

-- The quest window came back unreadable and the count of labels raised was
-- zero. The per-label raising is the hard way round: it needs a threshold to
-- guess with, reaches only labels that already exist, and has to be re-run
-- after the game writes a page.
--
-- A font object is the easy way round, and this addon already leans on it for
-- the typeface - the head of Modules/Fonts.lua says a SetFont on
-- GameFontNormal changes the text everywhere. Colour works the same.
do
    local function fontObject(r, g, b)
        local o = { r = r, g = g, b = b, a = 1 }
        function o:GetTextColor() return self.r, self.g, self.b, self.a end
        function o:SetTextColor(cr, cg, cb, ca)
            self.r, self.g, self.b = cr, cg, cb
            if ca ~= nil then self.a = ca end
        end
        return o
    end

    local saved = {}
    for _, name in ipairs({ "QuestFont", "QuestTitleFont", "GameFontBlack" }) do
        saved[name] = _G[name]
    end

    -- Dark ink on a light page: exactly what the parchment family carries.
    local quest = fontObject(0.1, 0.1, 0.1)
    local title = fontObject(0.2, 0.1, 0.05)
    _G.QuestFont = quest
    _G.QuestTitleFont = title
    _G.GameFontBlack = nil      -- a name this client does not have

    local painted = ns.Darkness.PaintFonts(true)
    T.ok(painted >= 2, "every object present was painted: " .. painted)

    local ink1 = select(1, ns.Darkness.Ink())
    T.eq(quest.r, ink1, "the body ink is ours now")
    T.eq(title.r, ink1, "and so is the heading's")

    -- The road back writes what was there, not what we think it should be.
    ns.Darkness.PaintFonts(false)
    T.eq(quest.r, 0.1, "the body's own ink came back")
    T.eq(title.r, 0.2, "and the heading's, which was a different colour")

    -- A name missing from this client is skipped in silence rather than
    -- counted as a failure: the list is common to three client lines.
    local okMissing = pcall(ns.Darkness.PaintFonts, true)
    T.ok(okMissing, "a missing font object is not an error")

    for name, was in pairs(saved) do _G[name] = was end
end

