local helpers = require("helpers")

-- The fonts: the addon's own window is outside the settings' reach.
--
-- The defect this set is written for: the author changed the global font
-- size on the "Fonts" page, and the settings window itself changed along with
-- the game's interface — the very window he was moving the slider in. A
-- setting that rebuilds the tool right under your hand is ungovernable: the
-- slider drives out from under the cursor, and a size convenient for the game
-- may make our window unreadable with nothing left to get back with.
--
-- So both paths by which the replacement reached our window are checked.
--
--   1. The list of targets. Another subsystem's provider returns font
--      strings, and the label of a widget of our own may be among them.
--   2. Inheritance. AceGUI's widgets carry no font of their own: they
--      inherit the game's standard font object, and replacing that object
--      changes them by itself, without entering any list of targets. That is
--      the very path the defect reached the author by.
--
-- Both cases are named global frames named by the library rather than by us:
-- the rule "the name begins with Darken" does not catch them, and the same
-- exception in the darkness subsystem broke on exactly that.

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

-- The library keeps the settings window with itself:
-- AceConfigDialog.OpenFrames by the addon's name. The fonts subsystem asks
-- it the same way it asks the font library — through LibStub and guarded.
local fakeDialog = { OpenFrames = {}, BlizOptions = {} }

LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return fakeMedia end
    if name == "AceConfigDialog-3.0" then return fakeDialog end
    return nil
end

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Modules/Fonts.lua", ns)

local Fonts = ns.Fonts
local INHERIT = Fonts.INHERIT

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

--- A font string inheriting a font object.
-- Until a font of its own has been assigned to it, it answers with what
-- stands on the object — that is how inheritance works in the engine.
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

local function newFrame(name, regions, children)
    return {
        GetName = function() return name end,
        GetRegions = function() return unpack(regions or {}) end,
        GetChildren = function() return unpack(children or {}) end,
    }
end

T.suite("the fonts: our own window is out of reach")

-- The recognition. Not one of our names takes part in it: the widgets of our
-- window are named by the library.
do
    local widget = newFrame("AceGUI30Label7")
    widget.obj = { type = "Label", frame = widget }
    T.eq(Fonts.IsOurs(widget), true, "a library widget is recognised by obj")

    local text = newInherited(newFont("Fonts\\Native.ttf", 12, ""), widget)
    T.eq(Fonts.IsOurs(text), true,
        "a widget's label is recognised by its parent rather than by its name")

    local tip = newFrame("AceGUITooltip")
    T.eq(Fonts.IsOurs(tip), true, "a library frame with no obj is recognised by name")

    local painted = newFrame("SomeFrame")
    painted.umbraStripped = true
    T.eq(Fonts.IsOurs(painted), true, "a frame we stripped is recognised by its marker")

    -- The game's font object: neither markers nor a parent.
    T.eq(Fonts.IsOurs(newFont("Fonts\\Native.ttf", 12, "")), false,
        "the game's font object is not ours")

    -- Our own bag window is ours by authorship, but it stands in place of the
    -- game's window, and the font settings are obliged to reach it.
    local bags = newFrame("DarkenBagsFrame")
    T.eq(Fonts.IsOurs(bags), false,
        "the bag window stays within the settings' reach")

    T.eq(Fonts.IsOurs(nil), false, "a nil instead of an object")
    T.eq(Fonts.IsOurs("a string"), false, "a string instead of an object")
end

-- The first path: the list of targets. The provider returns both the game's
-- label and our widget's label — only the first must be taken.
do
    local savedProviders = Fonts.providers.hotkey
    local gameText = newFont("Fonts\\Native.ttf", 10, "")

    local widget = newFrame("AceGUI30Button3")
    widget.obj = { type = "Button", frame = widget }
    local ourText = newInherited(newFont("Fonts\\Native.ttf", 12, ""), widget)

    Fonts.providers.hotkey = { function() return { gameText, ourText } end }

    ns.Addon = { db = { profile = { fonts = {
        skipGlobal = false,
        global = { font = "Font A", adjust = 8, outline = INHERIT },
        categories = {},
    } } } }
    Fonts:ApplySettings()

    T.eq(gameText.current[1], "Fonts\\A.ttf", "the game's label got the font")
    T.eq(gameText.current[2], 18, "and the size: the native 10 plus the adjustment of 8")
    T.eq(ourText.own, nil, "no font was assigned to our widget's label")

    Fonts.providers.hotkey = savedProviders
end

-- The second path, the very one. Our widget's label is in no list of targets:
-- it inherits GameFontNormal, and replacing that is the whole point of the
-- global level. Which means the inheritance is obliged to be broken.
do
    local savedNormal, savedHighlight = GameFontNormal, GameFontHighlight

    GameFontNormal = newFont("Fonts\\Native.ttf", 12, "")
    GameFontHighlight = newFont("Fonts\\Native.ttf", 12, "")

    -- The settings window: a library widget with a label inside.
    local label = newFrame("AceGUI30Label1")
    label.obj = { type = "Label", frame = label }
    local ourText = newInherited(GameFontNormal, label)
    label.GetRegions = function() return ourText end

    -- A window of the game's: its label inherits the font object too, and
    -- its inheritance must not be broken — it is the setting's very target.
    local gameFrame = newFrame("SomeGameFrame")
    local gameText = newInherited(GameFontHighlight, gameFrame)
    gameFrame.GetRegions = function() return gameText end

    local window = newFrame("DarkenConfigWindow", {}, { label })
    fakeDialog.OpenFrames.Darken = { frame = window }

    ns.Addon = { db = { profile = { fonts = {
        skipGlobal = false,
        global = { font = "Font A", adjust = 8, outline = INHERIT },
        categories = {},
    } } } }
    Fonts:ApplySettings()

    T.eq(GameFontNormal.current[1], "Fonts\\A.ttf",
        "the game's font object was replaced — the global level works")
    T.eq(GameFontNormal.current[2], 20, "and the size on it is the new one")

    local path, size = gameText:GetFont()
    T.eq(path, "Fonts\\A.ttf", "the game window's label got the new font")
    T.eq(size, 20, "and the new size")

    local ourPath, ourSize = ourText:GetFont()
    T.eq(ourPath, "Fonts\\Native.ttf",
        "our window's label was left with the native font")
    T.eq(ourSize, 12, "and with the native size — the window does not change size")

    fakeDialog.OpenFrames.Darken = nil
    GameFontNormal, GameFontHighlight = savedNormal, savedHighlight
end

-- There is no window, so there is no pass, and that is not an error: the
-- player may change the font from the game's interface options with our window closed.
do
    ns.Addon = { db = { profile = { fonts = {
        skipGlobal = false,
        global = { font = INHERIT, adjust = 0, outline = INHERIT },
        categories = {},
    } } } }
    local ok = pcall(function() Fonts:ApplySettings() end)
    T.ok(ok, "a closed settings window does not bring the application down")
end

ns.Addon = nil
LibStub = savedLibStub
