local helpers = require("helpers")

-- The fifth font category: the text of our own windows.
--
-- The defect this set is written for. There were four categories — unit
-- names, bar values, hotkeys, floating combat text — and all four about labels
-- over the world. The text of our own windows was not among them, so the bag
-- window and the item database window did not call the replacement at all and
-- lived on the game's standard font: the player's choice reached the
-- nameplates and did not reach two windows of the addon. Substituting unitname
-- there would have meant declaring a window's header to be a unit's name.
--
-- The tension this category is obliged to resolve rather than hide. The
-- settings window is a window of the addon too, and it is excluded from the
-- font settings deliberately: a tool that rebuilds itself under your hands is
-- ungovernable. So the boundary runs not by authorship but by purpose: a
-- window the addon draws in place of the game's window is the setting's
-- subject; the window the player moves that setting with is not.
--
-- That is exactly what is checked: an edit of the category reaches the text of
-- a module's window and does not reach the settings window — by both roads at
-- once and at one and the same instant, because separately each of them looks sound.

local savedLibStub = LibStub

local fakeMedia = {
    List = function(_, kind)
        if kind == "font" then return { "Font A" } end
        return {}
    end,
    IsValid = function(_, kind, name)
        return kind == "font" and name == "Font A"
    end,
    Fetch = function(_, kind, name)
        if kind == "font" and name == "Font A" then return "Fonts\\A.ttf" end
        return nil
    end,
}

local fakeDialog = { OpenFrames = {}, BlizOptions = {} }

LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return fakeMedia end
    if name == "AceConfigDialog-3.0" then return fakeDialog end
    return nil
end

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Defaults.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Frames.lua", ns)
helpers.loadAddonFile("Core/Events.lua", ns)
helpers.loadAddonFile("Core/Combat.lua", ns)
helpers.loadAddonFile("Core/Casefold.lua", ns)
helpers.loadAddonFile("Core/Media.lua", ns)
helpers.loadAddonFile("Modules/Fonts.lua", ns)
helpers.loadAddonFile("Core/Api.lua", ns)

local Fonts = ns.Fonts
local INHERIT = Fonts.INHERIT
local KEY = "windowtext"

ns.flavor = "vanilla"

--- The game's font object: a font of its own, no parent.
local function newFont(path, size, flags)
    local object = { current = { path, size, flags } }
    object.GetFont = function(self)
        return self.current[1], self.current[2], self.current[3]
    end
    object.SetFont = function(self, p, s, f) self.current = { p, s, f } end
    return object
end

local function newFrame(name, regions, children)
    return {
        GetName = function() return name end,
        GetRegions = function() return unpack(regions or {}) end,
        GetChildren = function() return unpack(children or {}) end,
    }
end

--- A font string inheriting a font object.
local function newInherited(object, parent)
    local text = { object = object, parent = parent }
    text.GetFont = function(self)
        if self.own then return self.own[1], self.own[2], self.own[3] end
        return self.object:GetFont()
    end
    text.SetFont = function(self, p, s, f)
        self.own = { p, s, f }
        self.object = nil
    end
    text.GetFontObject = function(self) return self.object end
    text.GetParent = function(self) return self.parent end
    return text
end

--- The settings into the profile in one call.
local function settings(global, windowtext)
    ns.Addon = { db = { profile = { fonts = {
        skipGlobal = false,
        global = global,
        categories = { [KEY] = windowtext },
    } } } }
end

T.suite("The fifth category is declared by the contract")

do
    local media = ns.Api:GetMedia()
    local keys = media.FontCategories()

    local found = {}
    for i = 1, #keys do found[keys[i]] = true end

    T.ok(found[KEY], "the category of the windows' own text is visible to a module: "
        .. table.concat(keys, ", "))

    -- The former four are in place: the category was added rather than replacing somebody's.
    for _, old in ipairs({ "unitname", "barvalue", "hotkey", "combattext" }) do
        T.ok(found[old], "the former category is in place: " .. old)
    end

    -- The list is a copy: a shared one would let a module rewrite the registry
    -- of categories for the whole addon.
    keys[1] = "spoiled"
    T.ok(media.FontCategories()[1] ~= "spoiled", "the list of categories is a copy")

    T.ok(ns.Api.API_VERSION >= 11, "the category was exposed by the eleventh version")
end

T.suite("An edit reaches the text of a module's window")

-- The first road: the provider of targets. That is how a module's window
-- hands its labels to the fonts subsystem — the same way the action bars do.
do
    local saved = Fonts.providers[KEY]

    local window = newFrame("DarkenBagsFrame")
    local title = newFont("Fonts\\Native.ttf", 12, "")
    title.GetParent = function() return window end
    local row = newFont("Fonts\\Native.ttf", 12, "")
    row.GetParent = function() return window end

    Fonts.providers[KEY] = { function() return { title, row } end }

    settings({ font = INHERIT, size = 0, outline = INHERIT },
        { font = "Font A", size = 15, outline = INHERIT })
    Fonts:ApplySettings()

    T.eq(title.current[1], "Fonts\\A.ttf", "the module window's header got the font")
    T.eq(title.current[2], 15, "and the size")
    T.eq(row.current[2], 15, "a row of the same window too")

    -- A zero in a category means "take it from the level above", and a global
    -- edit reaches a module's window by the same path: there is no second inheritance.
    settings({ font = "Font A", adjust = 8, outline = INHERIT },
        { font = INHERIT, size = 0, outline = INHERIT })
    Fonts:ApplySettings()
    T.eq(title.current[2], 20, "the global size reaches a module's window")

    -- And the restoration works: "as in the game" is the object's native font
    -- rather than our previous choice.
    settings({ font = INHERIT, size = 0, outline = INHERIT },
        { font = INHERIT, size = 0, outline = INHERIT })
    Fonts:ApplySettings()
    T.eq(title.current[1], "Fonts\\Native.ttf", "an empty choice restored the native font")
    T.eq(title.current[2], 12, "and the native size")

    Fonts.providers[KEY] = saved
end

-- The second road: a replacement on one object, through the contract. It is
-- used by a window that creates a label later than the general pass — that is,
-- by any window built at a press.
do
    local window = newFrame("DarkenItemsFrame")
    local label = newFont("Fonts\\Native.ttf", 12, "")
    label.GetParent = function() return window end

    settings({ font = INHERIT, size = 0, outline = INHERIT },
        { font = "Font A", size = 17, outline = INHERIT })

    T.eq(ns.Api:GetMedia().ApplyFont(KEY, label), true,
        "the module applied the category to its own label")
    T.eq(label.current[1], "Fonts\\A.ttf", "the module window's label got the font")
    T.eq(label.current[2], 17, "and the size")
end

T.suite("And does not reach the settings window")

-- The same minute, the same settings: a module's window changes, the settings
-- window does not. Separately each half looks sound, so they are checked together.
do
    local savedProviders = Fonts.providers[KEY]
    local savedNormal = GameFontNormal

    GameFontNormal = newFont("Fonts\\Native.ttf", 12, "")

    -- The settings window: a library widget named by the library itself, and a
    -- label inside it inheriting the game's standard font object.
    local widget = newFrame("AceGUI30Label12")
    widget.obj = { type = "Label", frame = widget }
    local ourText = newInherited(GameFontNormal, widget)
    widget.GetRegions = function() return ourText end
    fakeDialog.OpenFrames.Darken = {
        frame = newFrame("DarkenConfigWindow", {}, { widget }),
    }

    -- A module's window: ours by authorship but standing in place of a window of the game's.
    local window = newFrame("DarkenBagsFrame")
    local moduleText = newFont("Fonts\\Native.ttf", 12, "")
    moduleText.GetParent = function() return window end

    -- The provider returns both labels — ours and the window's. The selection
    -- of targets is one for every road, and it is obliged to take only the second.
    Fonts.providers[KEY] = { function() return { ourText, moduleText } end }

    settings({ font = "Font A", adjust = 10, outline = INHERIT },
        { font = "Font A", size = 15, outline = INHERIT })
    Fonts:ApplySettings()

    T.eq(moduleText.current[2], 15, "the module window's text took the category's size")
    T.eq(moduleText.current[1], "Fonts\\A.ttf", "and the category's font")

    local path, size = ourText:GetFont()
    T.eq(path, "Fonts\\Native.ttf", "the settings window's label stayed native")
    T.eq(size, 12, "and did not change size — the window does not rebuild itself under your hand")

    -- The global level works in the process: the font object itself was
    -- replaced, and our window's exception is made by breaking the inheritance
    -- rather than by refusing the replacement.
    T.eq(GameFontNormal.current[2], 22, "the global level works")

    -- The per-object road is closed by the same selection: the contract does
    -- not let anybody at our window even on a direct request.
    local label = newInherited(GameFontNormal, widget)
    T.eq(ns.Api:GetMedia().ApplyFont(KEY, label), false,
        "the settings window's label is not accepted as a target even on a direct request")
    T.eq(label.own, nil, "and no font was assigned to it")

    fakeDialog.OpenFrames.Darken = nil
    Fonts.providers[KEY] = savedProviders
    GameFontNormal = savedNormal
end

T.suite("The category's tab speaks of the boundary aloud")

do
    ns.SetLocale("enUS")
    local options = Fonts.BuildOptions()
    local tab = options.args[KEY]

    T.ok(type(tab) == "table", "the category has a tab of its own")
    T.eq(tab.args.font.type, "select", "a font is chosen on it")
    T.eq(tab.args.physics, nil, "the windows' text has no physics: there is nothing to fall")

    -- The settings window's exception, not said aloud, reads as work left
    -- undone: the player sets a large font and does not understand why the
    -- window he sets it in did not change.
    local intro = tab.args.intro.name()
    T.ok(intro:find("settings window", 1, true) ~= nil,
        "the tab explains why the settings window does not change")
    T.ok(intro:find("in place of the game", 1, true) ~= nil,
        "and says which windows the setting concerns")

    -- The note stands only here: on the tabs of the world labels it would be
    -- an answer to a question nobody asked.
    local other = options.args.unitname.args.intro.name()
    T.eq(other:find("settings window", 1, true), nil,
        "the other categories do not carry this note")
end

T.suite("A fresh install does not change a letter")

do
    local entry = Fonts.defaults.categories[KEY]
    T.ok(type(entry) == "table", "the category has a default")
    T.eq(entry.font, INHERIT, "the font is inherited")
    T.eq(entry.size, 0, "the size is zero, meaning \"as in the game\"")
    T.eq(entry.outline, INHERIT, "the outline is inherited")
    T.eq(entry.gravity, nil, "there is no physics in the default")

    local savedProviders = Fonts.providers[KEY]
    local window = newFrame("DarkenBagsFrame")
    local text = newFont("Fonts\\Native.ttf", 12, "")
    text.GetParent = function() return window end
    Fonts.providers[KEY] = { function() return { text } end }

    ns.Addon = { db = { profile = { fonts = {
        skipGlobal = Fonts.defaults.skipGlobal,
        global = Fonts.defaults.global,
        categories = Fonts.defaults.categories,
    } } } }
    Fonts:ApplySettings()

    T.eq(text.current[1], "Fonts\\Native.ttf", "the module window's font is untouched")
    T.eq(text.current[2], 12, "and so is the size")

    Fonts.providers[KEY] = savedProviders
end

ns.Addon = nil
LibStub = savedLibStub
