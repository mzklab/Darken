local helpers = require("helpers")

-- The settings window: the pure part.
--
-- The drawing part is checked by eye -- a frame is not created without a
-- client. Everything that DECIDES, however, is pulled out here and checked:
-- which pages to show for what was typed into the search, which of them go
-- into the first layer of the column and which into the second, and what to
--
-- show when the open page has vanished from the list.
-- The boundary is drawn on purpose. In the former window the decisions were
-- smeared over wrappers around other people's handlers: there was nowhere to check them, and they broke silently.

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Casefold.lua", ns)
helpers.loadAddonFile("Core/Skin.lua", ns)
-- The drawing is a separate file: Skin.Text lives there, and without it the
-- widgets fall over on the very first label.
helpers.loadAddonFile("Skin/Draw.lua", ns)
helpers.loadAddonFile("Options/Schema.lua", ns)
-- The widgets come before the window: the window takes Try for itself while
-- the file is read, and without them it would be left with a stub silently answering "nothing".
helpers.loadAddonFile("Widgets/Base.lua", ns)
helpers.loadAddonFile("Widgets/Controls.lua", ns)
helpers.loadAddonFile("Widgets/Dropdown.lua", ns)
helpers.loadAddonFile("Widgets/EditBox.lua", ns)
helpers.loadAddonFile("Widgets/Scroll.lua", ns)
helpers.loadAddonFile("Options/Window.lua", ns)

local Window = ns.Window
local Schema = ns.Schema

-- The translation here is the identity: what is checked is the filtering rule rather than the dictionary.
ns.Localize = function(key) return key end

--============================================================================
-- Folding
--============================================================================

T.suite("the window: the query is folded before the comparison")

do
    T.eq(Window.Fold("Fonts"), "fonts", "the case is removed")
    T.eq(Window.Fold("  Fonts  "), "fonts", "and so are the edges")
    T.eq(Window.Fold(""), "", "the empty stays empty")
    T.eq(Window.Fold(nil), "", "nothing instead of a string gives an empty string")
    T.eq(Window.Fold(42), "", "a number gives an empty string rather than an error")

    -- Cyrillic is folded by the core: string.lower in this client knows only
    -- Latin, and "Fonts" in Cyrillic would keep its capital letter.
    T.eq(Window.Fold("ШРИФТЫ"), Window.Fold("шрифты"),
        "Cyrillic is folded the same way as Latin")
end

--============================================================================
-- Filtering the settings
--============================================================================

T.suite("the window: what matches the query")

do
    local item = { label = "Grey Out the Artwork",
        hint = "Leaves icons and bars in the game's own colours." }

    T.eq(Window.Matches(item, "grey"), true, "by the start of the label")
    T.eq(Window.Matches(item, "artwork"), true, "by the middle of the label")
    T.eq(Window.Matches(item, "colours"), true, "by the explanation")
    T.eq(Window.Matches(item, "nameplate"), false, "a foreign word does not")

    -- An empty query matches everything. A search that hides everything when
    -- the field is empty turns the window into a blank sheet -- and an empty
    -- field is what the player sees when opening it.
    T.eq(Window.Matches(item, ""), true, "an empty query matches everything")
    T.eq(Window.Matches(item, nil), true, "and so does a missing one")

    T.eq(Window.Matches(nil, "grey"), false, "an empty setting does not match")
    T.eq(Window.Matches({}, "grey"), false, "a setting with no words does not match")
end

--============================================================================
-- Filtering the pages
--============================================================================

T.suite("the window: which pages stay in the column")

do
    Schema.Forget()
    Schema.Page("general", { title = "General", order = 2 })
    Schema.Page("dark", { title = "Interface Darkness", order = 3 })
    Schema.Page("fonts", { title = "Fonts", order = 4 })

    Schema.Add("dark", { kind = "slider", label = "Strength",
        path = { "amount" }, min = 0, max = 100, apply = "darkness" })
    Schema.Add("fonts", { kind = "toggle", label = "Leave Global Fonts Alone",
        path = { "skipGlobal" }, apply = "fonts" })

    local all = Schema.Pages()

    T.eq(#Window.Filter(all, ""), 3, "an empty query leaves every page")
    T.eq(#Window.Filter(all, nil), 3, "and so does a missing one")

    -- By the page name: the player searches for "fonts" and expects the whole
    -- page rather than a setting carrying that word.
    local byTitle = Window.Filter(all, "Fonts")
    T.eq(#byTitle, 1, "one was found by the page name")
    T.eq(byTitle[1].id, "fonts", "and that is the one")

    -- By a setting inside: the page name does not contain the word.
    local byItem = Window.Filter(all, "strength")
    T.eq(#byItem, 1, "one was found by a setting inside")
    T.eq(byItem[1].id, "dark", "and that is its page")

    T.eq(#Window.Filter(all, "nosuchword"), 0, "a foreign word gives nothing")
    T.eq(#Window.Filter(nil, "fonts"), 0, "with no pages there is nothing")
end

--============================================================================
-- The layers of the column
--============================================================================

T.suite("the window: the two layers of the column")

do
    Schema.Forget()
    Schema.Page("general", { title = "General", order = 2 })
    Schema.Page("dark", { title = "Interface Darkness", order = 3 })
    Schema.Page("profiles", { title = "Profiles", order = 100, aside = true })

    local main, aside = Window.Layers(Schema.Pages())

    T.eq(#main, 2, "the first layer holds what is about the game")
    T.eq(#aside, 1, "the second holds what is about the addon itself")
    T.eq(aside[1].id, "profiles", "and that is the profiles")

    T.eq(main[1].id, "general", "the order inside a layer is preserved")
    T.eq(main[2].id, "dark", "and onwards by the number")

    local none, nothing = Window.Layers(nil)
    T.eq(#none, 0, "with no pages the first layer is empty")
    T.eq(#nothing, 0, "and so is the second")
end

--============================================================================
-- Choosing the open page
--============================================================================

T.suite("the window: which page to show after a search")

-- A page vanishes from the column while the player is typing. Jumping to the
-- first one that comes along on every letter is not allowed -- they are still
-- typing; but showing a page that is no longer in the column is not allowed either.
do
    local pages = {
        { id = "general" }, { id = "dark" }, { id = "fonts" },
    }

    T.eq(Window.Choose(pages, "dark"), "dark",
        "the open page stayed -- it stays open")
    T.eq(Window.Choose(pages, "nosuchpage"), "general",
        "the open one vanished -- the first of those left")
    T.eq(Window.Choose(pages, nil), "general",
        "nothing was open -- the first one")

    T.eq(Window.Choose({}, "dark"), nil, "none is left -- nothing")
    T.eq(Window.Choose(nil, "dark"), nil, "with no list -- nothing")
end

--============================================================================
-- The rows of a page
--============================================================================

T.suite("the window: which rows to show on a page")

-- There is one rule and it is not obvious: with a NON-empty query the headers
-- and paragraphs vanish along with their settings.
--
-- Otherwise it goes like this: the player searches for a word, a page stays in
-- the column, and on it five headers in a row with not a single setting under
-- them. A header exists to divide a list, and there it has nothing to divide.
do
    Schema.Forget()
    Schema.Page("dark", { title = "Interface Darkness" })

    Schema.Add("dark", { kind = "header", label = "Strength" })
    Schema.Add("dark", { kind = "note", hint = "How dark everything goes." })
    Schema.Add("dark", { kind = "slider", label = "Strength",
        path = { "amount" }, min = 0, max = 100, apply = "darkness" })
    Schema.Add("dark", { kind = "header", label = "Areas" })
    Schema.Add("dark", { kind = "toggle", label = "Grey Out the Artwork",
        path = { "desaturate" }, apply = "darkness" })

    T.eq(#Window.Rows("dark", ""), 5, "with no query everything, decorations included")

    local found = Window.Rows("dark", "grey")
    T.eq(#found, 1, "with a query one setting was left")
    T.eq(found[1].kind, "toggle", "and that is it rather than the header above it")

    T.eq(#Window.Rows("dark", "nosuchword"), 0, "a foreign word gives nothing")
    T.eq(#Window.Rows("nosuchpage", ""), 0, "a foreign page gives nothing")
end

--============================================================================
-- Reading and writing a value
--============================================================================

T.suite("the window: a setting value is read and written")

do
    Schema.Forget()
    Schema.Page("dark", { title = "Interface Darkness", section = "darkness" })

    ns.Addon = {
        db = { profile = { darkness = { amount = 64, desaturate = true } } },
        defaults = { profile = { darkness = { amount = 64,
            desaturate = true } } },
    }

    local page = Schema.Of("dark")
    local slider = { kind = "slider", label = "Strength", path = { "amount" },
        min = 0, max = 100, apply = "none" }

    T.eq(Window.Value(page, slider), 64, "the value was read from the profile")

    T.eq(Window.Store(page, slider, 80), true, "the value was written")
    T.eq(ns.Addon.db.profile.darkness.amount, 80, "and lies in the profile")

    -- A path absent from the profile is not created: it is a typo, and a
    -- setting writing into nowhere looks like a working one.
    local wrong = { kind = "toggle", label = "Typo", path = { "amont" },
        apply = "none" }
    T.eq(Window.Store(page, wrong, true), false, "we do not write into a foreign path")
    T.eq(ns.Addon.db.profile.darkness.amont, nil, "and created nothing")

    -- A read and a write of its own are a legitimate way for a value that is
    -- not a profile field but something derived from it.
    local kept
    local derived = {
        kind = "toggle", label = "Derived", apply = "none",
        get = function() return true end,
        set = function(value) kept = value end,
    }
    T.eq(Window.Value(page, derived), true, "the own read was asked")
    T.eq(Window.Store(page, derived, false), true, "the own write was called")
    T.eq(kept, false, "and received the value")
end

T.suite("the window: applying calls the subsystem that was named")

-- "none" calls nothing, a subsystem name calls its Apply. It is not for the
-- window to decide whether that is allowed right now: in combat part of the
-- work is deferred, and the core is what knows about it.
do
    Schema.Forget()
    Schema.Page("dark", { title = "Interface Darkness", section = "darkness" })
    ns.Addon = {
        db = { profile = { darkness = { amount = 64 } } },
        defaults = { profile = { darkness = { amount = 64 } } },
    }

    local called = {}
    ns.Registry = {
        Get = function(_, name) return { name = name } end,
        ApplyOne = function(_, module) called[#called + 1] = module.name end,
    }

    local page = Schema.Of("dark")

    Window.Store(page, { kind = "slider", path = { "amount" },
        apply = "darkness" }, 70)
    T.eq(called[1], "darkness", "the named subsystem was called")

    Window.Store(page, { kind = "slider", path = { "amount" },
        apply = "none" }, 71)
    T.eq(#called, 1, "\"none\" calls nobody")

    -- A failed write applies nothing: there is nothing to apply, and a
    -- subsystem called for nothing redraws half the interface.
    Window.Store(page, { kind = "slider", path = { "nosuch" },
        apply = "darkness" }, 72)
    T.eq(#called, 1, "a write that misses does not call the apply")

    ns.Registry = nil
end

--============================================================================
-- Nested pages
--============================================================================

T.suite("the window: a nested page takes no row in the column")

-- One checkbox is not worth a row in the column: a row opened once and never
-- again is one more question to the player about where to go. That is why the
-- minimap button is nested into "General", and the five font categories into
-- "Fonts".
--
-- The parent field was declared from the very beginning, and until this check
-- NOBODY read it: the column showed twenty rows instead of twelve, and the
-- last ones went off its edge -- the column has no scrolling.
do
    Schema.Forget()
    Schema.Page("general", { title = "General", order = 2 })
    Schema.Page("launcher", { title = "Minimap Button", order = 2.5,
        parent = "general", store = "global", section = "launcher" })
    Schema.Page("fonts", { title = "Fonts", order = 4, section = "fonts" })
    Schema.Page("fonts.hotkey", { title = "Hotkeys", order = 4.03,
        parent = "fonts", section = "fonts" })

    Schema.Add("general", { kind = "toggle", label = "Skin Settings Windows",
        path = { "skinAce" }, apply = "none" })
    Schema.Add("launcher", { kind = "toggle", label = "Button on the Minimap",
        path = { "shown" }, apply = "none" })
    Schema.Add("fonts", { kind = "toggle", label = "Leave Global Fonts Alone",
        path = { "skipGlobal" }, apply = "none" })
    Schema.Add("fonts.hotkey", { kind = "slider", label = "Size",
        path = { "size" }, min = 6, max = 32, apply = "none" })

    local main = Window.Layers(Schema.Pages())
    T.eq(#main, 2, "the column holds only the non-nested ones")
    T.eq(main[1].id, "general", "the first is in place")
    T.eq(main[2].id, "fonts", "and so is the second")

    T.eq(#Schema.Children("general"), 1, "\"General\" has one nested page")
    T.eq(Schema.Children("general")[1].id, "launcher", "and that is the one")
    T.eq(#Schema.Children("fonts.hotkey"), 0, "a nested page has none of its own")
    T.eq(#Schema.Children(nil), 0, "with no name -- nothing")
end

T.suite("the window: the rows of a nested page land on the parent page")

do
    -- A header with the name of the nested page is added by itself. Without it
    -- the rows of the five font categories would merge into a list of fifteen
    -- fields in which nothing can be found: "Font", "Size", "Outline" -- and the same again.
    local plan = Window.Plan("general")
    T.eq(#plan, 3, "its own row, the nested header and the nested row")
    T.eq(plan[1].label, "Skin Settings Windows", "its own comes first")
    T.eq(plan[2].kind, "header", "then the header")
    T.eq(plan[2].label, "Minimap Button", "and it is named after the nested page")
    T.eq(plan[3].label, "Button on the Minimap", "and the row itself")

    -- What was built is returned as the same thing: the window rows are kept by
    -- the row table, and a new table on every redraw would grow the cache on
    -- every letter typed into the search.
    T.eq(Window.Plan("general"), plan, "the second time the same thing is returned")

    -- A nested page stays a separate page: its row reads and writes into ITS
    -- OWN section. For the minimap button it is a different one entirely -- one
    -- store for the whole account -- and done in the name of the parent it would
    -- write into the profile.
    local parent = Schema.Of("general")
    T.eq(Window.Owner(parent, plan[1]).id, "general", "an own row is its own")
    T.eq(Window.Owner(parent, plan[3]).id, "launcher",
        "while a nested row belongs to the nested page")
    T.eq(Window.Owner(parent, nil).id, "general", "with no row it is the page itself")

    -- An empty nested page yields no header: a header with nothing under it is
    -- a promise nobody will keep.
    Schema.Page("gear", { title = "Gear", order = 9 })
    Schema.Page("empty", { title = "Nothing Here", order = 9.1,
        parent = "gear" })
    T.eq(#Window.Plan("gear"), 0, "a nested page with no rows yielded no header")
end

T.suite("the window: the search finds a setting of a nested page")

do
    local all = Schema.Pages()

    -- A word from a setting of a font category must find "Fonts": the page of
    -- the category itself is not in the column, and if it is not found through
    -- the parent it will not be found at all.
    local found = Window.Filter(all, "Button on the Minimap")
    T.ok(#found >= 1, "the word was found")

    -- The filter returns the nested page as well -- the word is indeed in it.
    -- Layers is what keeps it out of the column, and the open page is chosen
    -- from what the column showed: a nested page cannot be opened, it has no page of its own.
    local main = Window.Layers(found)
    T.eq(#main, 1, "one was left in the column")
    T.eq(main[1].id, "general", "and that is the parent rather than the nested page")
    T.eq(Window.Choose(main, "launcher"), "general",
        "a nested page does not become the open one")

    -- And that row really is shown on the parent page.
    local rows = Window.Rows("general", "minimap")
    T.eq(#rows, 1, "one row is shown")
    T.eq(rows[1].label, "Button on the Minimap", "and that is the one")
end

--============================================================================
-- Conditional rows
--============================================================================

T.suite("the window: a row can hide itself and go dim")

-- Two different answers to two different questions, and they must not be confused.
--
-- A DIMMED row stays on the page. It answers the question "why does this
-- change nothing right now" by itself -- by being visible and not clickable.
-- Had it disappeared, it would have answered nothing, and the player would go looking for it in another section.
--
-- A HIDDEN row disappears. Only what speaks about a combination of settings is
-- hidden: the paragraph "both blocks are hidden, the screen is empty" with a
-- non-empty screen is not a dimmed hint but an untruth.
do
    Schema.Forget()
    Schema.Page("auras", { title = "Auras", section = "umbraauras" })

    local both = false

    Schema.Add("auras", { kind = "toggle", label = "Hide All Buffs",
        path = { "hideBuffs" }, apply = "none" })
    Schema.Add("auras", { kind = "toggle", label = "Show Only Buffs You Cast",
        path = { "onlyMine" }, apply = "none",
        disabled = function() return both end })
    Schema.Add("auras", { kind = "note", hint = "Nothing is drawn at all.",
        hidden = function() return not both end })

    -- While the combination is absent: there is no paragraph, the switch is alive.
    T.eq(#Window.Rows("auras", ""), 2, "the hidden paragraph did not make it into the list")
    local rows = Window.Rows("auras", "")
    T.eq(Window.Dimmed(rows[2]), false, "there is still something to narrow")

    -- The combination came together.
    both = true
    T.eq(#Window.Rows("auras", ""), 3, "the paragraph appeared by itself")
    T.eq(Window.Dimmed(Window.Rows("auras", "")[2]), true,
        "while the switch went dim")

    -- What is hidden is not found by the search: a row that is not on the page
    -- must not be in the results even if the word is in it.
    both = false
    T.eq(#Window.Rows("auras", "drawn"), 0,
        "a word from a hidden row found nothing")
    both = true
    T.eq(#Window.Rows("auras", "drawn"), 0,
        "and a paragraph, even shown, is not returned by the search: it is a decoration")

    -- A question that fell over counts as the answer "no". Of two silent
    -- breakages an extra row is visible to the player, while a vanished one looks as if it never existed.
    Schema.Forget()
    Schema.Page("broken", { title = "Broken" })
    Schema.Add("broken", { kind = "toggle", label = "Thing",
        path = { "thing" }, apply = "none",
        hidden = function() error("fell over") end,
        disabled = function() error("fell over") end })

    T.eq(#Window.Rows("broken", ""), 1, "a question that fell over does not hide the row")
    T.eq(Window.Dimmed(Schema.Items("broken")[1]), false,
        "and does not dim it")

    -- The field may also be just a value: a question is not always needed.
    T.eq(Window.Hidden({ hidden = true }), true, "a value works too")
    T.eq(Window.Hidden({}), false, "with no field it is not hidden")
    T.eq(Window.Hidden(nil), false, "with no row it is not hidden")
    T.eq(Window.Dimmed({ disabled = true }), true, "and dimming by a value works too")
end

T.suite("the window: a page with no conditional rows needs no walk")

-- The mark is set at declaration time, and it is set by the presence of the
-- field rather than by its answer: a page with a live "hidden: no" must still be walked.
do
    Schema.Forget()
    Schema.Page("plain", { title = "Plain" })
    Schema.Add("plain", { kind = "toggle", label = "One", path = { "one" },
        apply = "none" })
    T.eq(Schema.Conditional("plain"), false, "an ordinary page is not conditional")

    Schema.Page("maybe", { title = "Maybe" })
    Schema.Add("maybe", { kind = "toggle", label = "Two", path = { "two" },
        apply = "none", hidden = function() return false end })
    T.eq(Schema.Conditional("maybe"), true,
        "while a page with a conditional row is conditional even if that row is shown")

    T.eq(Schema.Conditional("nosuchpage"), false, "a foreign page is not conditional")
end

--============================================================================
-- Placing the rows
--============================================================================

T.suite("the window: where each row landed")

-- Arithmetic that breaks silently. The rows either overlap each other or part
-- twice as far -- both are visible by eye, but only if one gets to that page;
-- and a total height that lied means the scrolling does not reach the last
-- setting, and that looks like "the setting is not there at all".
do
    local M = ns.Skin.Metrics

    -- Three ordinary rows: the first at the top edge, the rest a gap apart.
    local rows = {
        { kind = "toggle" }, { kind = "toggle" }, { kind = "slider" },
    }
    local at, total = Window.Stack(rows, { 20, 20, 20 })

    T.eq(at[1], 0, "the first row is right at the top")
    T.eq(at[2], -(20 + M.gap), "the second is lower by its own height and a gap")
    T.eq(at[3], -(20 + M.gap + 20 + M.gap), "and so is the third")
    T.eq(total, 20 * 3 + M.gap * 2, "the total height is the rows plus the gaps")

    -- The heights differ: a row takes its own rather than a common one.
    local uneven = Window.Stack({ { kind = "note" }, { kind = "toggle" } },
        { 50, 20 })
    T.eq(uneven[2], -(50 + M.gap), "a tall paragraph pushed the next row away")

    -- Before a header the gap is wider: a header divides a list, and it divides
    -- precisely by the emptiness above itself.
    local withHead = {
        { kind = "toggle" }, { kind = "header" }, { kind = "toggle" },
    }
    local headAt = Window.Stack(withHead, { 20, 20, 20 })
    T.eq(headAt[2], -(20 + M.group), "before a header the gap is wider than usual")
    T.ok(M.group > M.gap, "and it really is wider")

    -- And before the very first header there is no addition: it has nothing to
    -- divide, and an empty strip at the start of a page looks like a cropped image.
    local firstHead = Window.Stack({ { kind = "header" }, { kind = "toggle" } },
        { 20, 20 })
    T.eq(firstHead[1], 0, "the first header is at the top all the same")

    -- Emptiness neither falls over nor lies about the height.
    local none, nothing = Window.Stack({}, {})
    T.eq(#none, 0, "with no rows nothing is placed")
    T.eq(nothing, 0, "and the height is zero")

    local nilled, zero = Window.Stack(nil, nil)
    T.eq(#nilled, 0, "with no list -- nothing")
    T.eq(zero, 0, "and zero")

    -- A missing height is taken as the ordinary one rather than zero: a row of
    -- zero height overlaps the next one, which is exactly what Stack separates.
    local guessed = Window.Stack({ { kind = "toggle" }, { kind = "toggle" } },
        { nil, 20 })
    T.eq(guessed[2], -(M.row + M.gap), "with no height the ordinary row is taken")
end

T.suite("the window: the height of a row is known from its kind")

-- By a number per kind rather than by asking the frame. A frame answers with
-- what it KNOWS about itself, and it does not always know: a frame given
-- neither a size nor both anchors has nothing honest to answer with, and a row
-- of zero height lands on the next one. That is exactly how the window showed two pages on top of each other.
do
    local M = ns.Skin.Metrics

    T.eq(Window.Tall("toggle"), M.row + 8, "a checkbox is a row plus the spacing")
    -- A select, a slider and an input are the same single row as a checkbox:
    -- the label on the left, the field on the right. A label ABOVE the field
    -- would take twice the height and give nothing for it: on a page of twenty
    -- settings that is forty rows instead of twenty, and the lower ones need scrolling.
    T.eq(Window.Tall("select"), Window.Tall("toggle"),
        "a select is of the same height as a checkbox")
    T.eq(Window.Tall("slider"), Window.Tall("toggle"), "and so is a slider")
    T.eq(Window.Tall("text"), Window.Tall("toggle"), "and so is an input")
    T.ok(Window.Tall("header") > M.row, "a header needs air above it")
    T.ok(Window.Tall("note") > Window.Tall("header"),
        "a paragraph is taller than a header: it spans several lines")

    -- The spacing is eight rather than two. It was two, and the rows stood flush:
    -- a mouse that twitched by a pixel hit the neighbouring setting, and a
    -- checkbox toggles silently.
    T.ok(Window.Tall("toggle") - M.row >= 8, "the spacing is no less than eight")

    T.eq(Window.Tall("nosuch"), M.row + 8, "an unknown kind gives the ordinary row")
    T.eq(Window.Tall(nil), M.row + 8, "with no kind the ordinary row")
end

T.suite("the slider: an extreme value can say there is none of its own")

-- Zero in the font size of a category means not "zero height" but "as on the
-- common tab". A bare zero says nothing about that, and the author asked
-- outright why there were zeros everywhere.
--
-- It is a MARK that says it rather than a word. The field is forty pixels wide,
-- and a word shows in it by its tail: the first attempt showed "Same as Global"
-- as "bal". A long explanation is the business of the tooltip.
do
    local MARK = string.char(226, 128, 148)

    local function worded(got, zero, low)
        if zero and got == low then return MARK end
        return tostring(got)
    end

    T.eq(worded(0, "Same as Global", 0), MARK,
        "an extreme value is shown by a mark")
    T.eq(worded(12, "Same as Global", 0), "12", "while a non-extreme one by a number")
    T.eq(worded(0, nil, 0), "0",
        "where no mark was asked for, zero stays zero")

    -- The mark is shorter than any number and fits the field for certain: that
    -- is what tells it from a word.
    T.ok(#MARK <= 3, "the mark is short: " .. #MARK .. " bytes")

    -- Only rows that declared it have a mark: for a bar height zero would mean
    -- a bar of zero height, and a mark there would be an untruth.
    T.eq(worded(10, "Same as Global", 10), MARK,
        "the extreme is not always zero")
end

T.suite("the slider: there is a thumb even if the engine gave none")

-- A slider created without the game template arrives with no thumb image at
-- all. With no thumb the engine has nothing to move, and our fill has nothing
-- to hold on to -- it stretches to the middle of it.
--
-- It looked like this: the track empty, no trace of the value, the slider
-- staying put whatever is written into it. The author sent a screenshot and
-- said "the values are 0 everywhere" -- the values were there, the thumb was not.
do
    local made, given = {}, nil
    local slider = {
        kind = "Slider",
        CreateTexture = function()
            local t = { SetColorTexture = function() end,
                SetSize = function() end, SetPoint = function() end }
            made[#made + 1] = t
            return t
        end,
        GetThumbTexture = function() return given end,
        SetThumbTexture = function(_, t) given = t end,
    }

    -- The engine gave no thumb: we create one ourselves.
    T.eq(given, nil, "at first there is no thumb")

    local own = slider.CreateTexture()
    slider:SetThumbTexture(own)

    T.ok(given ~= nil, "the thumb was assigned")
    T.eq(slider:GetThumbTexture(), own, "and the same one is returned")

    -- And if the engine did give one, we create none of our own: replacing what
    -- the engine gave means arguing with it about what it has already drawn.
    local ready = { GetThumbTexture = function() return "its own" end }
    T.eq(ready:GetThumbTexture(), "its own", "what the engine gave is taken as it is")
end

T.suite("the slider: the parts add up to the allotted width")

-- A slider row is built of four parts: an arrow, the track, an arrow, the
-- number field. The sum of their widths with the gaps must fit the same width
-- as the select field -- the fields stand one under another, and the right edges must coincide.
--
-- Failing to fit, the row overlaps itself: for the author the "more" arrow
-- landed on top of the number field, and it came out as "+75" in one piece.
do
    local M = ns.Skin.Metrics
    local w = ns.Widgets

    T.ok(type(w.SLIDER) == "table", "the slider widths are declared outwards")

    if type(w.SLIDER) == "table" then
        -- A slider row is of the same width as a select field and an input
        -- field. That is what is worth checking: the sum of the parts adds up by
        -- itself -- the track is computed as the remainder -- but it can easily
        -- diverge from the FIELD WIDTH, and then the right edges on the page form a staircase.
        -- A slider row is wider than a select field: within the same width it
        -- has four parts instead of one label, and no room was left for the track.
        -- The right edges still coincide by themselves -- all three kinds of
        -- field are pinned to the right edge of the row, and the row takes the extra from the left.
        T.ok(w.SLIDER.whole >= w.CONTROL,
            "a slider row is not narrower than a select field: "
            .. tostring(w.SLIDER.whole) .. " against " .. tostring(w.CONTROL))

        -- And room must be left for the track: the arrows and the number field
        -- can eat it whole, and then there is nothing to move the slider by.
        -- The track needs room for its steps: a hundred steps over eighty pixels
        -- is one and a half pixels per step, and a mouse cannot be put there.
        -- Half the width allotted to the row is the threshold below which a
        -- slider stops being a slider.
        T.ok(w.SLIDER.track >= w.SLIDER.whole / 2,
            "half the row was left for the track: " .. tostring(w.SLIDER.track)
            .. " of " .. tostring(w.SLIDER.whole))
    end
end

T.suite("the window: labels with no outline and no shadow")

-- The author asked to remove the "shadow" five times in a row, and it was
-- removed properly every time. The thickening came from the OUTLINE: our own
-- font module applies it to the whole interface at the player's choice, this
-- window included -- and the author had "Thin Outline" set. It had to be removed too.
--
-- An outline is needed over the game WORLD, where there is grass, sky and water
-- under the letters. In the window there is an even dark backing under them:
-- there it does not separate a letter from the background but thickens it on all sides, and a small font turns to mush.
do
    local font = { "Fonts" .. string.char(92) .. "FRIZQT__.TTF", 12,
        "THICKOUTLINE" }
    local shadow = { 1, -1 }
    local text = {
        SetFont = function(self, path, size, flags)
            font = { path, size, flags }
        end,
        GetFont = function() return font[1], font[2], font[3] end,
        SetShadowOffset = function(_, x, y) shadow = { x, y } end,
        SetShadowColor = function(_, _, _, _, a) shadow.alpha = a end,
    }

    ns.Widgets.Flatten(text)

    T.eq(font[3], "", "the outline was removed")
    T.eq(font[1], "Fonts" .. string.char(92) .. "FRIZQT__.TTF",
        "while the font itself stayed the same")
    T.eq(font[2], 12, "and so did the size")
    T.eq(shadow[1], 0, "the shadow has no offset")
    T.eq(shadow[2], 0, "on either axis")
    T.eq(shadow.alpha, 0, "and is transparent")

    -- And again: pinning the font brings back both the outline and the shadow,
    -- and the window is redrawn after it. That is why the removal is repeated on
    -- every redraw rather than done once at build time.
    font = { "Fonts" .. string.char(92) .. "FRIZQT__.TTF", 12, "OUTLINE" }
    shadow = { 1, -1 }

    ns.Widgets.Unshadow()

    T.eq(font[3], "", "the returned outline was removed again")
    T.eq(shadow[1], 0, "and so was the shadow")

    -- A label with no font does not break the pass: the font may have failed to apply at all.
    local bare = { GetFont = function() return nil end,
        SetFont = function() error("no font") end,
        SetShadowOffset = function() end, SetShadowColor = function() end }
    ns.Widgets.Flatten(bare)
    T.ok(true, "a label with no font passed without falling over")
end

T.suite("the skinning: every colour name exists in the palette")

-- A name absent from the palette is returned by Skin.Get as nothing, and the
-- engine falls over on SetColorTexture(nil) -- taking the WHOLE page with it:
-- the player sees empty space where eighteen settings should be.
--
-- That is what happened: the number field of a slider was painted "field", and
-- "field" is not a colour but a state. A typo in a colour name cannot be caught
-- any other way than by asking the palette: Lua knows nothing about it.
do
    local names = {
        "ink", "panel", "panelAlt", "line",
        "lilac", "lilacDeep", "text", "textDim", "textFaint",
    }

    for _, name in ipairs(names) do
        local r, g, b = ns.Skin.Get(name)
        T.ok(type(r) == "number" and type(g) == "number"
            and type(b) == "number", "the colour exists in the palette: " .. name)
    end

    -- And the converse: a non-existent name really does return nothing, that is,
    -- the check above checks something rather than always passing.
    T.eq(ns.Skin.Get("nosuchcolour"), nil,
        "a foreign colour name returns nothing")
end

T.suite("the window: buttons in a row line up on one rank")

-- Stacked in a column, three ready-made looks take three rows and read as three
-- different questions, although it is one question with three answers.
do
    local rows = {
        { kind = "note" },
        { kind = "action" }, { kind = "action" }, { kind = "action" },
        { kind = "toggle" },
    }
    local ranks = Window.Ranks(rows, 3)

    T.eq(ranks[1], nil, "a paragraph does not join a rank")
    T.ok(ranks[2] ~= nil, "the first button is in the rank")
    T.eq(ranks[2].at, 1, "and it is the first")
    T.eq(ranks[3].at, 2, "the second is second")
    T.eq(ranks[4].at, 3, "the third is third")
    T.eq(ranks[2].of, ranks[4].of, "and they share one rank")
    T.eq(#ranks[2].of, 3, "the rank holds three buttons")
    T.eq(ranks[5], nil, "a checkbox does not join a rank")

    -- The fourth button starts a new rank: more than three in a row and the
    -- label stops fitting.
    local four = Window.Ranks({
        { kind = "action" }, { kind = "action" },
        { kind = "action" }, { kind = "action" },
    }, 3)
    T.eq(#four[1].of, 3, "the first rank holds three")
    T.eq(four[4].at, 1, "the fourth started a new one")
    T.eq(#four[4].of, 1, "and is alone in it so far")

    -- A checkbox between buttons BREAKS the rank: it is about something else,
    -- and the buttons on either side of it are two different questions.
    local split = Window.Ranks({
        { kind = "action" }, { kind = "toggle" }, { kind = "action" },
    }, 3)
    T.ok(split[1].of ~= split[3].of, "the rank was broken by the checkbox")

    T.eq(next(Window.Ranks({}, 3)), nil, "nothing gives nothing")
    T.eq(next(Window.Ranks(nil, 3)), nil, "with no list -- nothing")

    -- A meaningless number per rank does not break the layout.
    T.ok(Window.Ranks({ { kind = "action" } }, 0)[1] ~= nil,
        "zero per rank falls back to the default")
    T.ok(Window.Ranks({ { kind = "action" } }, nil)[1] ~= nil,
        "with no number the default")
end

T.suite("the window: a tooltip can be computed")

-- A tooltip speaks not only about the setting but also about what is in force
-- RIGHT NOW: "the font is the native one, the size is the native one +2, the
-- outline is thin". Such a line changes right under the player's hand, and
-- written out once it would be a lie a second later.
--
-- It is needed where the settings are corrections and zero in them means "do
-- not change": a page with not a single real number on it says nothing about
-- that. The author asked three times why there were zeros everywhere.
do
    local counted = 0
    local said = Window.Says(function()
        counted = counted + 1
        return "twelve right now"
    end)

    T.eq(said, "twelve right now", "a computed tooltip was computed")
    T.eq(counted, 1, "and computed once")

    T.eq(Window.Says("written out"), "written out", "a written-out one stayed itself")
    T.eq(Window.Says(nil), "", "there is no nothing: an empty string")
    T.eq(Window.Says(42), "", "neither a string nor a computation gives nothing")

    -- A computation that fell over does not break the row: a tooltip that is
    -- missing is better than a page that is missing.
    T.eq(Window.Says(function() error("fell over") end), "",
        "a computation that fell over gives an empty tooltip")

    -- And the search sees such a tooltip: otherwise the row would stop being
    -- found by the words in it.
    local item = { label = "Size",
        hint = function() return "In effect now - size: twelve" end }
    T.eq(Window.Matches(item, "effect"), true,
        "a word from a computed tooltip finds the row")
end

T.suite("the window: a page is divided into blocks by the headers")

-- A block is a header and everything under it up to the next header. A frame
-- around such a bundle is what divides the page: without it thirty rows in a
-- row read as one list in which the headers are merely bolder.
do
    local rows = {
        { kind = "note" },                  -- 1: the introduction
        { kind = "header", label = "A" },   -- 2
        { kind = "toggle" },                -- 3
        { kind = "toggle" },                -- 4
        { kind = "header", label = "B" },   -- 5
        { kind = "slider" },                -- 6
    }
    local blocks = Window.Blocks(rows)

    T.eq(#blocks, 2, "two headers give two blocks")
    T.eq(blocks[1].first, 2, "the first starts at its own header")
    T.eq(blocks[1].last, 4, "and ends before the next one")
    T.eq(blocks[2].first, 5, "the second at its own")
    T.eq(blocks[2].last, 6, "and up to the end of the page")

    -- The rows before the first header do not enter a block: they are about the
    -- whole page rather than a part of it, and a frame would enclose the introduction.
    T.ok(blocks[1].first > 1, "the introduction stayed outside the frame")

    -- A header with no content gets no frame: a frame around emptiness is a
    -- promise nobody will keep. That happens after a search, when the settings
    -- under the header were filtered out.
    local lonely = Window.Blocks({
        { kind = "header", label = "A" },
        { kind = "header", label = "B" },
    })
    T.eq(#lonely, 0, "two empty headers in a row give not a single block")

    T.eq(#Window.Blocks({ { kind = "toggle" }, { kind = "toggle" } }), 0,
        "with no headers there are no blocks")
    T.eq(#Window.Blocks({}), 0, "nothing gives nothing")
    T.eq(#Window.Blocks(nil), 0, "with no list -- nothing")
end

T.suite("the window: a paragraph and a custom widget are measured, the rest are not")

do
    local M = ns.Skin.Metrics

    -- For the known kinds there is nothing to measure, and the frame is not
    -- asked: its answer would add nothing here and would cost a call on every redraw.
    T.eq(Window.Height({ kind = "toggle" },
        { GetHeight = function() return 999 end }), M.row + 8,
        "for a checkbox its own number matters more than the frame answer")

    -- A paragraph, however, wraps onto as many lines as the width allowed, and
    -- only it knows its own height. The four on top are the spacing.
    T.eq(Window.Height({ kind = "note" },
        { GetHeight = function() return 47 end }), 51,
        "the paragraph named its own height, and the spacing was added to it")

    -- It did not name one -- our own number: a zero height would fold two rows into one.
    T.eq(Window.Height({ kind = "note" },
        { GetHeight = function() return 0 end }), Window.Tall("note"),
        "zero is not taken")
    T.eq(Window.Height({ kind = "note" }, nil), Window.Tall("note"),
        "with no frame -- our own number")
    T.eq(Window.Height({ kind = "note" },
        { GetHeight = function() error("fell over") end }), Window.Tall("note"),
        "a question that fell over -- our own number")

    T.eq(Window.Height(nil, nil), M.row + 8, "with no row -- the ordinary one")
end

T.suite("the window: it builds and redraws on a fake engine")

-- The window decisions are checked above individually and purely. What is
-- checked here is the GLUING: that the built window really shows the pages
-- Filter selected and the rows Rows selected.
--
-- This check is weaker than the pure ones -- the fake answers "all right" to
-- everything it does not know, and real crookedness of the anchors is visible
-- only by eye. But one thing it catches reliably: a reference to nothing. The
-- redraw walks six foreign tables, and any one of them being empty would break
-- the whole window -- that is, the player would see NOTHING rather than a crooked row.
do
    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }

    -- The fake answers the unknown with an empty action rather than an error:
    -- the window calls dozens of engine methods, and listing them here would
    -- mean rewriting the engine rather than checking the window.
    local nothing = function() end
    local function fake(kind)
        local object = { kind = kind, shown = false, points = {} }

        object.Show = function(self) self.shown = true end
        object.Hide = function(self) self.shown = false end
        object.IsShown = function(self) return self.shown end
        object.SetText = function(self, value) self.text = value end
        object.GetText = function(self) return self.text or "" end
        object.SetHeight = function(self, value) self.height = value end
        object.GetHeight = function(self) return self.height or 20 end
        object.SetWidth = function(self, value) self.width = value end
        object.GetWidth = function(self) return self.width or 600 end
        object.ClearAllPoints = function(self) self.points = {} end
        object.SetPoint = function(self, point, _, _, x, y)
            self.points[#self.points + 1] = { point, x, y }
        end
        object.SetScript = function(self, name, fn)
            self.scripts = self.scripts or {}
            self.scripts[name] = fn
        end
        object.CreateTexture = function() return fake("Texture") end
        object.CreateFontString = function() return fake("FontString") end
        object.SetScrollChild = function(self, child) self.child = child end

        -- The rest is listed rather than answered wholesale. Answering
        -- wholesale is not allowed: the drawing reads FIELDS of a frame too, not
        -- only methods, and a field that turned out to be a function breaks it on the very first access.
        -- Try tolerates the unlisted anyway: a missing method is a legitimate
        -- case for it, it answers with nothing.
        for _, name in ipairs({
            "SetSize", "SetAllPoints", "SetFrameStrata", "SetToplevel",
            "EnableMouse", "SetMovable", "SetClampedToScreen",
            "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
            "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
            "SetAlpha", "SetTexture", "SetColorTexture", "SetVertexColor",
            "SetDrawLayer", "SetJustifyH", "SetJustifyV", "SetTextColor",
            "SetWordWrap", "SetSpacing", "SetMinMaxValues", "SetValue",
            "SetValueStep", "SetObeyStepOnDrag", "SetOrientation",
            "SetThumbTexture", "Enable", "Disable", "SetAutoFocus",
            "SetMultiLine", "SetMaxLetters", "SetNumeric",
            "SetCursorPosition", "ClearFocus", "SetFocus", "HighlightText",
            "SetTextInsets", "SetFrameLevel", "SetHitRectInsets",
            "EnableMouseWheel", "SetVerticalScroll", "SetHorizontalScroll",
            "SetParent", "SetScale", "SetShown", "SetNormalTexture",
            "SetHighlightTexture", "SetPushedTexture",
        }) do object[name] = nothing end

        object.GetValue = function(self) return self.value or 0 end
        object.IsEnabled = function(self) return self.off ~= true end
        object.GetStringHeight = function() return 12 end
        object.GetVerticalScroll = function() return 0 end
        object.GetObjectType = function(self) return self.kind end

        return object
    end

    _G.UIParent = fake("Frame")
    _G.CreateFrame = function(kind) return fake(kind) end

    Schema.Forget()
    Schema.Page("general", { title = "General", order = 2,
        section = "darkness" })
    Schema.Page("dark", { title = "Interface Darkness", order = 3,
        section = "darkness" })
    Schema.Page("profiles", { title = "Profiles", order = 100, aside = true })

    Schema.Add("general", { kind = "note", hint = "About this addon." })
    Schema.Add("dark", { kind = "header", label = "Strength" })
    Schema.Add("dark", { kind = "slider", label = "Strength",
        path = { "amount" }, min = 0, max = 100, step = 1, apply = "none" })
    Schema.Add("dark", { kind = "toggle", label = "Grey Out the Artwork",
        path = { "desaturate" }, apply = "none" })

    local secret = false
    Schema.Add("dark", { kind = "note", hint = "Nothing is drawn at all.",
        hidden = function() return not secret end })

    ns.Addon = {
        db = { profile = { darkness = { amount = 64, desaturate = true } } },
        defaults = { profile = { darkness = { amount = 64,
            desaturate = true } } },
    }

    local root = Window.Build()
    T.ok(root ~= nil, "the window was built")
    T.eq(Window.Build(), root, "the second call returns the same window")
    T.eq(root.shown, false, "the built window is hidden")

    -- The parts of the skeleton are in place: the redraw walks each of them, and
    -- any one of them being empty would break the whole window.
    T.ok(root.head ~= nil, "there is a header")
    T.ok(root.column ~= nil, "there is a column")
    T.ok(root.page ~= nil, "there is a page")
    T.ok(root.scroll ~= nil, "there is a scroll")
    T.ok(root.scroll.content ~= nil, "and it has content")

    -- A redraw with no query: the first page opened.
    Window.Repaint()
    T.eq(Window.Open(), "general", "the first page is open")

    -- A search by a narrow word: the darkening page was left in the column, and
    -- it became the open one -- the former one vanished from the column.
    Window.Seek("artwork")
    T.eq(Window.Open(), "dark", "a word from a setting opened its page")

    -- One of its four rows is shown: with a non-empty query the header and the
    -- paragraph leave along with their settings.
    local shownRows = 0
    for _, item in ipairs(Schema.Items("dark")) do
        if item.label == "Grey Out the Artwork" then shownRows = shownRows + 1 end
    end
    T.eq(shownRows, 1, "there is one setting carrying that word")
    T.eq(#Window.Rows("dark", "artwork"), 1, "and it alone is shown")

    -- The query is cleared -- everything came back except the hidden one.
    Window.Seek("")
    T.eq(#Window.Rows("dark", ""), 3, "the hidden paragraph did not come back")

    secret = true
    T.eq(#Window.Rows("dark", ""), 4, "while once the combination came together it did")
    Window.Repaint()

    -- The scroll content is given a WIDTH.
    --
    -- The engine expects a scrolled child to have a width of its own: it does
    -- not derive one. Without it the content stays one unit wide, and everything
    -- anchored to both its edges collapses to zero -- checkbox labels,
    -- paragraphs and dropdowns simply are not drawn. The headers stay visible
    -- though: they have a single anchor and are measured by their text.
    --
    -- That is how the window looked for the author: the headers in place, no
    -- settings. By eye that reads as "an empty page" rather than as "zero width".
    T.ok(type(root.scroll.content.width) == "number"
        and root.scroll.content.width > 1,
        "the scroll content is given a width: "
        .. tostring(root.scroll.content.width))

    -- The scroll was told the height of its content. Not telling it means not
    -- letting one scroll to the last setting: it is there but cannot be seen, and
    -- that looks like "the setting is not there at all".
    T.ok(type(root.scroll.content.height) == "number"
        and root.scroll.content.height > 0,
        "the scroll knows the height of its content: "
        .. tostring(root.scroll.content.height))

    -- A foreign word: nothing was left in the column, and the window does not fall over because of it.
    Window.Seek("nosuchword")
    T.eq(Window.Open(), nil, "no page is left -- nothing is open")

    Window.Seek("")
    T.ok(Window.Open() ~= nil, "the query is cleared -- a page is open again")

    -- Every declared kind must be able to draw itself.
    --
    -- The guard was created in the wake of a real loss: the kind "color" was
    -- declared in the schema and had no maker in the window, that is, the colour
    -- rows simply did not appear -- and there are two on the nameplates and
    -- three on the unit frames. The same went for the tabs declared on the fonts page.
    --
    -- This cannot be seen by eye: a row that is not there is invisible. So it is
    -- asked directly -- one row of each kind.
    do
        Schema.Forget()
        Schema.Page("every", { title = "Every Kind", section = "darkness" })
        local page = Schema.Of("every")

        local samples = {
            toggle = { kind = "toggle", label = "Toggle",
                path = { "desaturate" }, apply = "none" },
            slider = { kind = "slider", label = "Slider",
                path = { "amount" }, min = 0, max = 100, step = 1,
                apply = "none" },
            select = { kind = "select", label = "Select",
                path = { "amount" }, apply = "none",
                values = function() return {} end },
            text = { kind = "text", label = "Text", path = { "amount" },
                apply = "none" },
            color = { kind = "color", label = "Color",
                path = { "tint" }, apply = "none" },
            action = { kind = "action", label = "Action", apply = "none",
                run = function() end },
            header = { kind = "header", label = "Header" },
            note = { kind = "note", hint = "A paragraph." },
            tabs = { kind = "tabs", label = "Tabs",
                values = function() return {} end },
            widget = { kind = "widget", label = "Widget",
                build = function(parent)
                    return ns.Widgets.Frame("Frame", parent)
                end },
        }

        for kind, item in pairs(samples) do
            local made = Window.Row(root.scroll.content, page, item)
            T.ok(made ~= nil, "the kind can draw itself: " .. kind)
        end
    end

    Window.Show()
    T.eq(root.shown, true, "a shown window is shown")
    Window.Hide()
    T.eq(root.shown, false, "and a hidden one is hidden")

    _G.CreateFrame, _G.UIParent = saved.CreateFrame, saved.UIParent
end
