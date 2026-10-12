local helpers = require("helpers")

-- Fonts: inheritance, reversibility and application by category.
--
-- There are two main subjects. The first is the inheritance rule: it is the
-- only arithmetic of the subsystem and the only place where one can be wrong
-- silently (a category "inherits" something other than what the player
-- thinks, and that shows only by eye in the client). The second is
-- reversibility: the "do not touch the global fonts" switch must restore the
-- native look without a reload, otherwise the "a switch that switches nothing off" defect repeats.

-- A fake font library. The module builds its settings section only when the
-- library is present, so the stub is installed before the module file is loaded.
local savedLibStub = LibStub

local fakeMedia = {
    List = function(_, kind)
        if kind == "font" then return { "Font A", "Font B" } end
        return {}
    end,
    IsValid = function(_, kind, name)
        return kind == "font" and (name == "Font A" or name == "Font B")
    end,
    Fetch = function(_, kind, name)
        if kind ~= "font" then return nil end
        if name == "Font A" then return "Fonts\\A.ttf" end
        if name == "Font B" then return "Fonts\\B.ttf" end
        return nil
    end,
}

LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return fakeMedia end
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

T.suite("fonts: inheritance")

-- The global level only: there are no categories at all.
--
-- There is no size at this level at all, and that is the main difference of
-- the model. What is set globally is an adjustment -- a shift from the native
-- size of every element -- not a size: one size for the whole interface made
-- a heading and a small label the same height, and the player saw "the fonts went wrong".
do
    local global = { font = "Font A", adjust = 2, outline = "OUTLINE" }
    local font, size, outline, adjust = Fonts.Resolve(global, nil, nil)
    T.eq(font, "Font A", "the global font with no categories")
    T.eq(size, nil, "there is no size at the global level")
    T.eq(adjust, 2, "an adjustment instead")
    T.eq(outline, "OUTLINE", "the global outline with no categories")
end

-- A full override by a category.
do
    local global = { font = "Font A", size = 14, outline = "OUTLINE" }
    local categories = {
        unitname = { font = "Font B", size = 20, outline = "THICKOUTLINE" },
    }
    local font, size, outline = Fonts.Resolve(global, categories, "unitname")
    T.eq(font, "Font B", "the category overrides the font")
    T.eq(size, 20, "the category overrides the size")
    T.eq(outline, "THICKOUTLINE", "the category overrides the outline")
end

-- A partial override: its own font, an inherited outline, no size.
-- It is for this case that inheritance is per-field rather than all or nothing.
do
    local global = { font = "Font A", adjust = 3, outline = "OUTLINE" }
    local categories = {
        unitname = { font = "Font B", size = 0, outline = INHERIT },
    }
    local font, size, outline, adjust =
        Fonts.Resolve(global, categories, "unitname")
    T.eq(font, "Font B", "partial: its own font")
    T.eq(size, nil, "a zero size inherits nothing: there is nothing to inherit")
    T.eq(adjust, 3, "while the adjustment applies, and the element shifts by it")
    T.eq(outline, "OUTLINE", "partial: the outline is inherited")
end

-- The reverse partial: its own size, the global font. An own size is a
-- number, and the adjustment does not move it: "let it be 9" means 9.
do
    local global = { font = "Font A", adjust = 4, outline = INHERIT }
    local categories = { barvalue = { font = INHERIT, size = 9 } }
    local font, size, outline, adjust =
        Fonts.Resolve(global, categories, "barvalue")
    T.eq(font, "Font A", "reverse partial: the font is inherited")
    T.eq(size, 9, "reverse partial: its own size")
    T.eq(adjust, 4, "the adjustment is still reported")
    T.eq(outline, nil, "the outline is set at no level -- nil")
end

-- An unknown category answers with the global choice: that is a normal
-- answer, not an error.
do
    local global = { font = "Font A", adjust = 1, outline = "OUTLINE" }
    local categories = { unitname = { font = "Font B" } }
    local font, size, outline, adjust =
        Fonts.Resolve(global, categories, "no-such")
    T.eq(font, "Font A", "an unknown category takes the global font")
    T.eq(size, nil, "it has no size of its own")
    T.eq(adjust, 1, "and it shifts by the shared adjustment")
    T.eq(outline, "OUTLINE", "an unknown category takes the global outline")
end

-- Nothing is set anywhere: all three fields are empty, and the caller will
-- leave the object its own font.
do
    local font, size, outline, adjust = Fonts.Resolve(
        { font = INHERIT, adjust = 0, outline = INHERIT }, {}, "unitname")
    T.eq(font, nil, "an empty global font gives nil")
    T.eq(size, nil, "a zero size gives nil")
    T.eq(adjust, 0, "a zero adjustment is zero, not nil: there simply is no shift")
    T.eq(outline, nil, "an empty outline gives nil")
end

-- Garbage from SavedVariables must not break the resolution.
do
    local font, size, outline = Fonts.Resolve("garbage", "garbage", "unitname")
    T.eq(font, nil, "garbage instead of settings: no font")
    T.eq(size, nil, "garbage instead of settings: no size")
    T.eq(outline, nil, "garbage instead of settings: no outline")

    local f2, _, _, a2 = Fonts.Resolve({ font = 42, adjust = "3" }, nil, nil)
    T.eq(f2, nil, "a number instead of a font name is discarded")
    T.eq(a2, 3, "a numeric string adjustment is coerced to a number")

    -- A negative adjustment is legitimate -- that is how it differs from a
    -- size -- while an out-of-range one is clamped: the player would see "a
    -- font of size -40" as a vanished interface with not a single hint why.
    local _, _, _, a3 = Fonts.Resolve({ adjust = -5 }, nil, nil)
    T.eq(a3, -5, "a negative adjustment is legitimate: it means \"smaller\"")

    local _, _, _, a4 = Fonts.Resolve({ adjust = -900 }, nil, nil)
    T.eq(a4, Fonts.ADJUST_MIN, "an out-of-range adjustment is clamped to the bound")

    local _, _, _, a5 = Fonts.Resolve({ adjust = 900 }, nil, nil)
    T.eq(a5, Fonts.ADJUST_MAX, "and from the other side too")
end

T.suite("fonts: the inheritance is real, not a copy")

-- The key requirement: by default a category stores the inheritance marker
-- rather than a copy of the global value. A copy would diverge from the
-- global setting on its very first edit.
for i = 1, #Fonts.CATEGORIES do
    local key = Fonts.CATEGORIES[i].key
    local entry = Fonts.defaults.categories[key]
    T.eq(type(entry), "table", "the category " .. key .. " has defaults")
    T.eq(entry.font, INHERIT, "the category " .. key .. " inherits the font")
    T.eq(entry.size, 0, "the category " .. key .. " inherits the size")
    T.eq(entry.outline, INHERIT, "the category " .. key .. " inherits the outline")
end

-- An edit of the global choice is visible to the categories at once, with no edit of the categories.
do
    local global = { font = INHERIT, adjust = 0, outline = INHERIT }
    local categories = Fonts.defaults.categories
    T.eq(Fonts.Resolve(global, categories, "unitname"), nil,
        "while no global font is chosen the category is empty")
    global.font = "Font A"
    T.eq(Fonts.Resolve(global, categories, "unitname"), "Font A",
        "a new global font is immediately visible to the category")
end

T.suite("fonts: outlines and the library")

T.eq(Fonts.Flags("NONE"), "", "\"no outline\" is an empty flag string")
T.eq(Fonts.Flags("OUTLINE"), "OUTLINE", "a thin outline")
T.eq(Fonts.Flags("THICKOUTLINE"), "THICKOUTLINE", "a thick outline")
T.eq(Fonts.Flags(nil), nil, "unset gives nil, not \"no outline\"")
T.eq(Fonts.Flags(INHERIT), nil, "the inheritance marker gives nil")
T.eq(Fonts.Flags("invention"), nil, "an unknown key gives nil")

T.eq(Fonts.MediaFont(fakeMedia, "Font A"), "Fonts\\A.ttf", "a known name gives a path")
T.eq(Fonts.MediaFont(fakeMedia, "No such font"), nil, "an unknown name gives nil")
T.eq(Fonts.MediaFont(fakeMedia, INHERIT), nil, "the inheritance marker is not a font name")
T.eq(Fonts.MediaFont(nil, "Font A"), nil, "without the library, nil rather than an error")
T.eq(Fonts.MediaFont({}, "Font A"), nil, "a library with no methods gives nil")

T.suite("fonts: the path to a nested field")

do
    local frame = { healthbar = { TextString = "target" }, name = "name" }
    T.eq(Fonts.Field(frame, "name"), "name", "a first-level field")
    T.eq(Fonts.Field(frame, "healthbar.TextString"), "target", "a field through a dot")
    T.eq(Fonts.Field(frame, "manabar.TextString"), nil, "a broken path gives nil")
    T.eq(Fonts.Field(frame, "name.Text"), nil, "a path through a string gives nil")
    T.eq(Fonts.Field(nil, "name"), nil, "no object gives nil")
    T.eq(Fonts.Field(frame, ""), nil, "an empty path gives nil")
end

T.suite("fonts: reversibility")

--- A fake font object: exactly the two methods the subsystem uses. Both the
-- game font objects and the font strings handle them identically, so the
-- subsystem does not tell them apart.
local function newFont(path, size, flags)
    local object = { current = { path, size, flags } }
    function object:GetFont()
        return self.current[1], self.current[2], self.current[3]
    end
    function object:SetFont(p, s, f)
        self.current = { p, s, f }
        return true
    end
    return object
end

do
    local object = newFont("Fonts\\Native.ttf", 12, "")

    T.ok(Fonts.Apply(object, "Fonts\\A.ttf", 16, "OUTLINE"), "the font was applied")
    T.eq(object.current[1], "Fonts\\A.ttf", "the path was replaced")
    T.eq(object.current[2], 16, "the size was replaced")
    T.eq(object.current[3], "OUTLINE", "the outline was replaced")

    T.ok(Fonts.Restore(object), "the restore worked")
    T.eq(object.current[1], "Fonts\\Native.ttf", "the native path came back")
    T.eq(object.current[2], 12, "the native size came back")
    T.eq(object.current[3], "", "the native outline came back")
end

-- Repeated overriding does not "accumulate": what counts as native is always
-- what was there before the first touch.
do
    local object = newFont("Fonts\\Native.ttf", 12, "")
    for i = 1, 20 do
        Fonts.Apply(object, "Fonts\\A.ttf", 10 + i, "OUTLINE")
        Fonts.Restore(object)
        Fonts.Apply(object, "Fonts\\B.ttf", 30 - i, "THICKOUTLINE")
    end
    Fonts.Restore(object)
    T.eq(object.current[1], "Fonts\\Native.ttf", "after twenty edits, the native path")
    T.eq(object.current[2], 12, "after twenty edits, the native size")
    T.eq(object.current[3], "", "after twenty edits, the native outline")
end

-- A partial application: nil means "leave as it was", not "reset to zero".
do
    local object = newFont("Fonts\\Native.ttf", 12, "OUTLINE")
    Fonts.Apply(object, "Fonts\\A.ttf", nil, nil)
    T.eq(object.current[1], "Fonts\\A.ttf", "the path was replaced")
    T.eq(object.current[2], 12, "the size stayed native")
    T.eq(object.current[3], "OUTLINE", "the outline stayed native")
end

-- An object never touched has nothing to restore.
do
    local object = newFont("Fonts\\Native.ttf", 12, "")
    T.eq(Fonts.Restore(object), false, "an untouched object has nothing to restore")
    T.eq(object.current[1], "Fonts\\Native.ttf", "and it is untouched")
end

-- Unsuitable objects do not break the subsystem.
T.eq(Fonts.Apply(nil, "x", 1, ""), false, "nil instead of an object")
T.eq(Fonts.Apply({}, "x", 1, ""), false, "an object with no methods")
T.eq(Fonts.Restore("a string"), false, "a string instead of an object")

T.suite("fonts: applying the settings")

-- The global objects and frames are created in _G: that is exactly where the subsystem looks for them.
local FAKE_GLOBALS = {
    "GameFontNormal", "GameFontHighlight", "TextStatusBarText",
    "PlayerFrame", "TargetFrame",
}
local savedGlobals = {}
for i = 1, #FAKE_GLOBALS do savedGlobals[i] = _G[FAKE_GLOBALS[i]] end

local function setupWorld()
    GameFontNormal    = newFont("Fonts\\Native.ttf", 12, "")
    GameFontHighlight = newFont("Fonts\\Native.ttf", 12, "")
    TextStatusBarText = newFont("Fonts\\Native.ttf", 10, "OUTLINE")
    PlayerFrame = {
        name = newFont("Fonts\\Native.ttf", 11, ""),
        healthbar = { TextString = newFont("Fonts\\Native.ttf", 10, "") },
    }
    TargetFrame = { name = newFont("Fonts\\Native.ttf", 11, "") }
end

ns.flavor = "vanilla"

local function withSettings(settings)
    ns.Addon = { db = { profile = { fonts = settings } } }
end

-- The global override: one choice changes the text everywhere.
--
-- And the main property of the adjustment: the difference between elements
-- is preserved. The fake objects have different native sizes -- 12, 11 and
-- 10 -- and after an adjustment of +4 they must stay different. The former
-- single size would have made them all equal, and that is exactly what the
-- player saw as "the fonts went wrong": chat, tooltips and the quest log all one height, noticeably smaller than the game ones.
do
    setupWorld()
    withSettings({
        skipGlobal = false,
        global = { font = "Font A", adjust = 4, outline = "OUTLINE" },
        categories = {},
    })
    Fonts:ApplySettings()

    T.eq(GameFontNormal.current[1], "Fonts\\A.ttf", "the global font was applied to GameFontNormal")
    T.eq(GameFontNormal.current[2], 16, "and the size is shifted: a native 12 plus 4")
    T.eq(GameFontHighlight.current[1], "Fonts\\A.ttf", "and to the second object")

    -- A category with no override inherits the global choice -- so its
    -- targets get exactly the same font.
    T.eq(PlayerFrame.name.current[1], "Fonts\\A.ttf",
        "the unit name inherits the global font")
    T.eq(TargetFrame.name.current[2], 15, "and is shifted from its own native 11")
    T.eq(TextStatusBarText.current[2], 14, "while the bar value is shifted from its own 10")
    T.ok(GameFontNormal.current[2] ~= TargetFrame.name.current[2],
        "the difference between elements remained: the adjustment shifts rather than levels")
    T.eq(TextStatusBarText.current[1], "Fonts\\A.ttf",
        "the bar values inherit the global font")
end

-- A targeted override beats the global one.
do
    setupWorld()
    withSettings({
        skipGlobal = false,
        global = { font = "Font A", adjust = 4, outline = "OUTLINE" },
        categories = {
            unitname = { font = "Font B", size = 0, outline = INHERIT },
        },
    })
    Fonts:ApplySettings()

    T.eq(GameFontNormal.current[1], "Fonts\\A.ttf", "the global one stayed global")
    T.eq(PlayerFrame.name.current[1], "Fonts\\B.ttf", "the unit name was overridden")
    T.eq(PlayerFrame.name.current[2], 15,
        "zero size: the name is shifted by the adjustment from its own native 11")
    T.eq(PlayerFrame.name.current[3], "OUTLINE", "the outline of the name was inherited")
    T.eq(TextStatusBarText.current[1], "Fonts\\A.ttf",
        "another category is not affected by the override")
end

-- The "do not touch the global fonts" switch restores the native look -- at
-- once, with no reload, and does not touch the targeted categories.
do
    setupWorld()
    local settings = {
        skipGlobal = false,
        global = { font = "Font A", adjust = 4, outline = "OUTLINE" },
        categories = {
            unitname = { font = "Font B", size = 18, outline = "NONE" },
        },
    }
    withSettings(settings)
    Fonts:ApplySettings()
    T.eq(GameFontNormal.current[1], "Fonts\\A.ttf", "before switching off the font is ours")

    settings.skipGlobal = true
    Fonts:ApplySettings()
    T.eq(GameFontNormal.current[1], "Fonts\\Native.ttf", "the native font came back")
    T.eq(GameFontNormal.current[2], 12, "and the native size")
    T.eq(PlayerFrame.name.current[1], "Fonts\\B.ttf",
        "the targeted setting keeps working")

    settings.skipGlobal = false
    Fonts:ApplySettings()
    T.eq(GameFontNormal.current[1], "Fonts\\A.ttf", "and it switches on again")
end

-- A fresh profile changes not a single letter: the defaults set nothing.
do
    setupWorld()
    withSettings({
        skipGlobal = Fonts.defaults.skipGlobal,
        global     = { font = INHERIT, adjust = 0, outline = INHERIT },
        categories = Fonts.defaults.categories,
    })
    Fonts:ApplySettings()
    T.eq(GameFontNormal.current[1], "Fonts\\Native.ttf", "the defaults do not touch the font")
    T.eq(GameFontNormal.current[2], 12, "the defaults do not touch the size")
    T.eq(PlayerFrame.name.current[1], "Fonts\\Native.ttf", "nor the unit name")
end

-- Without a profile the subsystem silently does nothing.
do
    setupWorld()
    ns.Addon = nil
    Fonts:ApplySettings()
    T.eq(GameFontNormal.current[1], "Fonts\\Native.ttf", "without a profile nothing is touched")
end

T.suite("fonts: the settings section")

do
    local options = Fonts.BuildOptions()
    T.eq(type(options), "table", "the section was assembled")
    T.eq(options.childGroups, "tab", "the page is a row of tabs")

    -- One tab per element, with the global one first. The keys of the element
    -- tabs are the same as the category keys: a tab with no matching category
    -- would be a setting the engine cannot reach.
    T.eq(options.args.global.type, "group", "the global level tab is in place")
    for i = 1, #Fonts.CATEGORIES do
        local key = Fonts.CATEGORIES[i].key
        T.eq(options.args[key].type, "group",
            "the tab of element " .. key .. " is in place")
    end

    local globalTab = options.args.global.args
    T.eq(globalTab.skipGlobal.type, "toggle",
        "the global override switch stayed on the global tab")

    -- A spec requirement: the glyphs are mentioned outright in the font
    -- selection description. The base language is English, so the English
    -- text is checked; on the Russian client Locale/ruRU.lua replaces it,
    -- where the same thing is said about Cyrillic.
    T.ok(globalTab.font.desc:find("glyphs") ~= nil,
        "the global font description warns about glyphs")
    for i = 1, #Fonts.CATEGORIES do
        local key = Fonts.CATEGORIES[i].key
        T.ok(options.args[key].args.font.desc:find("glyphs") ~= nil,
            "the font description of category " .. key .. " warns about glyphs")
    end

    -- The first row of the font list is "value not set": without it the
    -- choice would be a one-way road.
    local values = globalTab.font.values()
    T.ok(values[INHERIT] ~= nil, "the global list has a \"native font\" row")
    T.eq(values["Font A"], "Font A", "the library fonts made it into the list")

    local catValues = options.args.unitname.args.font.values()
    T.ok(catValues[INHERIT] ~= nil, "the category list has an \"as the global one\" row")

    local outlines = globalTab.outline.values()
    T.ok(outlines[INHERIT] ~= nil, "the outline list has an inheritance row")
    T.ok(outlines.OUTLINE ~= nil, "and the outlines themselves")
end

-- The settings handlers write into the profile and apply at once.
do
    setupWorld()
    local settings = {
        skipGlobal = false,
        global = { font = INHERIT, adjust = 0, outline = INHERIT },
        categories = { unitname = { font = INHERIT, size = 0, outline = INHERIT } },
    }
    withSettings(settings)

    local options = Fonts.BuildOptions()
    local globalTab = options.args.global.args
    globalTab.font.set(nil, "Font A")
    T.eq(settings.global.font, "Font A", "the font choice went into the profile")
    T.eq(GameFontNormal.current[1], "Fonts\\A.ttf", "and was applied immediately")
    T.eq(globalTab.font.get(), "Font A", "get returns what was chosen")

    T.eq(globalTab.font.disabled(), false,
        "while the override is on the fields are active")
    globalTab.skipGlobal.set(nil, true)
    T.eq(globalTab.font.disabled(), true,
        "with the override off the global fields are inactive")
    T.eq(GameFontNormal.current[1], "Fonts\\Native.ttf", "and the font came back")

    options.args.unitname.args.size.set(nil, 18)
    T.eq(settings.categories.unitname.size, 18, "the category size went into the profile")
    T.eq(PlayerFrame.name.current[2], 18, "and was applied to the unit name")
    T.eq(options.args.unitname.args.size.get(), 18, "the category get returns what was chosen")
end

T.suite("fonts: the chat is left to the addon that owns it")

-- A player's report: Darken keeps overruling Prat's chat font and size.
-- Prat does not set a font on the chat at all - it calls the game's
-- FCF_SetChatWindowFontSize, which reads the frame's CURRENT font and writes
-- it back with Prat's size. So our chat font object leaked into the chat
-- through Prat's own hands, and every application of any Darken setting did
-- it again.
do
    -- The question is pure: whether an addon is loaded arrives as a function.
    T.eq(Fonts.ChatOwner(function(name) return name == "Prat-3.0" end),
        "Prat-3.0", "the owner of the chat is found by name")
    T.eq(Fonts.ChatOwner(function() return false end), nil,
        "with none of them loaded the chat is ours")
    T.eq(Fonts.ChatOwner(nil), nil,
        "and with no way to ask, nobody owns it")

    -- Installed is not loaded: an addon the player switched off owns nothing
    -- and must not take the chat away from us.
    local asked = {}
    Fonts.ChatOwner(function(name) asked[#asked + 1] = name return false end)
    T.ok(#asked > 0, "every name was put to the client: " .. #asked)
end

do
    setupWorld()
    _G.ChatFontNormal = newFont("Fonts\\Native.ttf", 13, "")
    _G.ChatFontSmall  = newFont("Fonts\\Native.ttf", 11, "")

    -- The stub answers one question and passes the rest through: the
    -- category targets are resolved by the same layer.
    local savedCompat = ns.Compat
    local function withLoaded(answer)
        ns.Compat = {
            Resolve = savedCompat and savedCompat.Resolve,
            ResolveFunction = function() return answer end,
        }
        Fonts.ForgetChat()
    end

    withLoaded(function(name) return name == "Prat-3.0" end)

    withSettings({
        skipGlobal = false,
        global = { font = "Font A", adjust = 4, outline = "OUTLINE" },
        categories = {},
    })
    Fonts:ApplySettings()

    T.eq(GameFontNormal.current[1], "Fonts\\A.ttf",
        "the rest of the interface still gets the player's font")
    T.eq(_G.ChatFontNormal.current[1], "Fonts\\Native.ttf",
        "and the chat keeps the font it had")
    T.eq(_G.ChatFontNormal.current[2], 13,
        "its size as well, unshifted by the adjustment")
    T.eq(_G.ChatFontSmall.current[1], "Fonts\\Native.ttf",
        "both of the chat's objects")

    -- With nobody owning the chat it is ours like everything else: the
    -- standing down is for an owner, not a permanent exemption.
    withLoaded(function() return false end)
    Fonts:ApplySettings()

    T.eq(_G.ChatFontNormal.current[1], "Fonts\\A.ttf",
        "with no chat addon the chat takes the player's font")
    T.eq(_G.ChatFontNormal.current[2], 17, "shifted from its own native 13")

    Fonts.ForgetChat()
    ns.Compat = savedCompat
    _G.ChatFontNormal, _G.ChatFontSmall = nil, nil
end

-- Restore the globals: the next file of the suite must not see the stubs.
for i = 1, #FAKE_GLOBALS do _G[FAKE_GLOBALS[i]] = savedGlobals[i] end
LibStub = savedLibStub
