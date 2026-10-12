local ADDON, ns = ...

-- Fonts: two levels, as section 5.2 of the specification describes.
--
-- The global level is the replacement of the game's standard font objects. One
-- SetFont call on an object such as GameFontNormal changes the text everywhere
-- that object is inherited: windows, tooltips, the quest log, system messages.
-- So one move of replacement covers almost the whole interface — and for the
-- same reason it touches other addons that use the same objects. Hence the
-- switch "do not touch the global fonts".
--
-- The targeted level is four categories: unit names, bar values, hotkeys and
-- button counts, floating combat text. Each has a set of targets of its own
-- and the right to override the global choice.
--
-- In the window these two levels are laid out across tabs: the first is the
-- global one, then one tab per element, and each element has a font, a size
-- and an outline of its own. The page used to be a scroll with one "font size"
-- for the whole interface at its head: it silently commanded every element at
-- once, and where that was written down — nowhere. So every tab has a line
-- saying what is in effect now and where it came from (Fonts.Origin):
-- inheritance has to be visible to the eye rather than only in the sources.
--
-- The inheritance is real rather than copied. By default a category stores not
-- the global font's value but the marker "I inherit" (the string __inherit for
-- the lists, a zero for the size). A copy of the value would diverge from the
-- global setting at its very first edit: the player would change the font
-- globally while the categories stayed with the old one, overriding nothing
-- explicitly. The same marker works at the top level too: a global "I inherit"
-- means "leave the object its own font", that is, the game's native look. So a
-- fresh profile changes not one letter until the player asks.
--
-- Reversibility. The lesson of the dimming subsystem: a switch has to switch
-- off. At the first touch of a font object its own font, size and flags are
-- remembered for it, and every computation goes from what was remembered
-- rather than from what is current. So "do not touch the global fonts"
-- restores the native fonts at once, without a reload of the interface.

local Fonts = {
    name = "fonts",
}
ns.Fonts = Fonts

local counters = ns.Counters or {}
ns.Counters = counters

-- Claimed while the file is read, so that "this subsystem did nothing"
-- cannot be mistaken for "this subsystem is not in the build".
counters.yielded = counters.yielded or 0

-- The marker for "no value is set, I take the level above". A string rather
-- than a nil: it is visible as a row of its own in a dropdown, it is readable
-- in SavedVariables and it does not vanish when AceDB strips the defaults. It
-- cannot coincide with a real font's name: the names in LibSharedMedia are
-- human ones.
local INHERIT = "__inherit"
Fonts.INHERIT = INHERIT

-- Where a font object's original font, size and flags are kept. Side memory,
-- because the object is somebody else's.
local BASE = ns.Skin.FontBase

-- The game's standard font objects. The list holds candidates rather than
-- facts: some of the names do not exist on every supported client, and the
-- check for existence happens at the moment of application. A name that does
-- not exist is silently skipped, as is a group of frames that does not exist
-- on the client.
--
-- The categories' objects (bar values, hotkeys, combat text) are deliberately
-- absent from this list: otherwise the switch "do not touch the global fonts"
-- would also remove the targeted overrides, which it has nothing to do
-- with.
local GLOBAL_OBJECTS = {
    "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge",
    "GameFontNormalHuge", "GameFontHighlight", "GameFontHighlightSmall",
    "GameFontHighlightLarge", "GameFontDisable", "GameFontDisableSmall",
    "GameFontDisableLarge", "GameFontGreen", "GameFontGreenSmall",
    "GameFontRed", "GameFontRedSmall", "GameFontWhite", "GameFontBlack",
    "GameFontDarkGraySmall",
    "SystemFont_Tiny", "SystemFont_Small", "SystemFont_Small2",
    "SystemFont_Med1", "SystemFont_Med2", "SystemFont_Med3",
    "SystemFont_Large", "SystemFont_Huge1",
    "SystemFont_Shadow_Small", "SystemFont_Shadow_Med1",
    "SystemFont_Shadow_Med2", "SystemFont_Shadow_Med3",
    "SystemFont_Shadow_Large", "SystemFont_Shadow_Huge1",
    "SystemFont_Shadow_Huge2", "SystemFont_Shadow_Outline_Small",
    "SystemFont_OutlineThick_Huge2",
    "QuestFont", "QuestFontNormalSmall", "QuestTitleFont",
    "ChatFontNormal", "ChatFontSmall",
    "GameTooltipText", "GameTooltipTextSmall", "GameTooltipHeaderText",
    "Tooltip_Med", "Tooltip_Small",
    "MailTextFontNormal", "ZoneTextFont", "SubZoneTextFont",
    "PVPInfoTextFont", "ErrorFont",
    "NumberFontNormal", "NumberFontNormalLarge",
    "NumberFontNormalHuge", "NumberFontNormalYellow",
}

-- The font objects the chat is written with.
--
-- They stand in the list above as well: with no chat addon they are the
-- game's chat and get the player's font like everything else. They are named
-- here only so that they can be taken back out again, below.
local CHAT_OBJECTS = {
    ChatFontNormal = true,
    ChatFontSmall  = true,
}

-- The addons that own the chat.
--
-- A list of names, and the cost of a list of names is written here plainly
-- because this file argues against them elsewhere: an addon that owns the
-- chat and is not named here gets our font anyway, and neither its author
-- nor the player has any way of telling why. The author chose this knowingly
-- over the alternative, which was a tab of its own and a switch the player
-- would have had to find.
--
-- The entry it was written for is the first one. Prat does not set a font on
-- the chat at all: it calls the game's FCF_SetChatWindowFontSize, which
-- reads the frame's CURRENT font and writes it back with Prat's size - so
-- our font object leaks into the chat through Prat's own hands, and the
-- player sees his chat addon's settings being overruled by ours.
--
-- The report names the counter beside it, so a chat still in our font has an
-- answer: the owner was not recognised, and the name belongs on this list.
local CHAT_OWNERS = {
    "Prat-3.0", "Chatter", "Glass", "BasicChatMods", "ElvUI",
}

--- Which of the chat's owners is loaded, if any.
--
-- A pure function over the client's answer: the question "is this addon
-- loaded" arrives as a function, so the rule is tested without a client.
--
-- Loaded rather than installed, and the difference matters: an addon the
-- player disabled is still on disk and owns nothing.
--
-- @param loaded function the client's "is this addon loaded"
-- @return string|nil the name of the owner
function Fonts.ChatOwner(loaded)
    if type(loaded) ~= "function" then return nil end

    for i = 1, #CHAT_OWNERS do
        local name = CHAT_OWNERS[i]
        local ok, yes = pcall(loaded, name)
        if ok and yes then return name end
    end

    return nil
end

-- The owner found this session, false for "nobody", nil for "not asked yet".
local chatOwner = nil

--- The chat's owner on this client, asked once per session.
--
-- Addons do not load in the middle of a session, while the fonts are applied
-- at every edit of every setting - and the question costs one call per name.
--
-- Not knowing is not remembered: before the client is determined the layer
-- refuses, and an answer of "we do not know yet" kept for the session would
-- hand the chat to nobody for ever.
--
-- @return string|nil
function Fonts.ChatTaken()
    if chatOwner ~= nil then return chatOwner or nil end

    if type(ns.Compat) ~= "table"
        or type(ns.Compat.ResolveFunction) ~= "function" then
        return nil
    end

    local got, loaded = pcall(ns.Compat.ResolveFunction, "addon-loaded")
    if not got or type(loaded) ~= "function" then return nil end

    chatOwner = Fonts.ChatOwner(loaded) or false
    return chatOwner or nil
end

--- Forget who owns the chat.
-- Needed by the tests: a session there is one file, and its second case
-- would arrive with the previous one's answer.
function Fonts.ForgetChat()
    chatOwner = nil
end

-- The categories of the targeted settings.
--
-- globals are the names of the game's font objects that belong to the
-- category. units are the paths to the font strings inside the frames of the
-- unitframe group the compatibility layer returns. The field names are not
-- invented: they are the very fields the engine itself uses (name, healthbar,
-- manabar, TextString), and each is checked for existence before being
-- touched.
--
-- A category for which not one target was found on this client silently does
-- nothing. That is exactly the same rule the groups of frames in the dimming
-- subsystem live by.
local CATEGORIES = {
    {
        key = "unitname",
        label = "Unit Names",
        globals = {},
        units = { "name" },
    },
    {
        key = "barvalue",
        label = "Bar Values",
        globals = { "TextStatusBarText", "TextStatusBarTextSmall",
                    "TextStatusBarTextLarge" },
        units = { "healthbar.TextString", "manabar.TextString" },
    },
    {
        key = "hotkey",
        label = "Hotkeys and Counts",
        globals = { "NumberFontNormalSmallGray", "NumberFontNormalSmallGrey",
                    "NumberFontNormalSmall" },
        units = {},
    },
    {
        key = "combattext",
        label = "Floating Combat Text",
        globals = { "CombatTextFont", "CombatTextFontOutline" },
        units = {},
        -- The marker for "this category commands the world labels": the
        -- numbers that float up over the units themselves. A font object does
        -- not draw them — the three-dimensional text engine does, and it has
        -- a font and a physics of its own; see WorldTextFont and PHYSICS
        -- below. A marker rather than a check of the key by name: the rule has
        -- to hold after the category is renamed too.
        worldText = true,
    },
    {
        -- The text of our own windows: the bags window, the item database
        -- window and every next one the addon puts in place of a window of
        -- the game's.
        --
        -- Why a fifth category was needed at all. The previous four are every
        -- one of them about labels over the world: a name above a unit, a
        -- number on a bar, a hotkey, a damage figure. The text of our own
        -- windows is not among them, and so both windows did not call the
        -- replacement at all and lived on GameFontNormal: the player's choice
        -- of font reached the nameplates and did not reach two windows of the
        -- addon. Substituting unitname there would have meant saying that a
        -- window's heading is a unit's name, and the very first edit of the
        -- unit names would have travelled across the windows.
        --
        -- globals and units are empty, and that is not a placeholder. There is
        -- no font object of the game's that would belong to our windows — the
        -- windows are ours and the labels in them are ours; the targets come
        -- from the windows themselves, through a supplier
        -- (Fonts.AddTargets) and one at a time (Fonts.ApplyCategory through
        -- Darken:GetMedia). A category without targets silently does nothing —
        -- the same rule a category whose objects do not exist on this client
        -- lives by.
        --
        -- The boundary of "our window" runs by purpose rather than by
        -- authorship, and it is drawn once — in the selection of targets
        -- (accept = usable and not Fonts.IsOurs). A window the addon draws in
        -- place of a window of the game's is the subject of the setting and a
        -- target. The settings window is the tool the player moves that
        -- setting with, and it does not become a target, no matter where its
        -- label was passed in from. No second check was created for this: the
        -- door is one, and this category goes through it along with everybody
        -- else.
        key = "windowtext",
        label = "Addon Window Text",
        globals = {},
        units = {},
        -- The marker for "this category is about our own windows". The
        -- settings section also attaches the explanation of the boundary by
        -- it: without that, the exclusion of the settings window reads as an
        -- oversight. A marker rather than a comparison of the key by name —
        -- for the same reason as with worldText: the rule has to hold after
        -- the category is renamed too.
        ownWindows = true,
    },
}
Fonts.CATEGORIES = CATEGORIES

-- The physics of the floating combat text.
--
-- The addon writes no engine of its own for the numbers and creates no
-- abstraction of its own over them: the game exposes the behaviour of the
-- world labels through console variables, and the setting is those variables.
-- The gravity sets how fast a figure falls; the ramp duration, how long it
-- stays on screen.
--
-- Where the variables' names and the rule about a full logout are known from:
-- NiceDamage (Reloaded), MIT licence, Copyright (c) 2026 Rodi Scheele. Not one
-- line of code was taken from it — what was taken is knowledge: the names
-- WorldTextGravity and WorldTextRampDuration, the variant with the _v2
-- suffix, the DAMAGE_TEXT_FONT variable and the fact that it is read once per
-- entry into the world.
--
-- The names with the _v2 suffix appeared on later clients and do not exist
-- everywhere. A missing variable is silently skipped — the same rule by which
-- a font object that does not exist on this client is skipped.
--
-- min and max are the bounds of what makes sense rather than the slider's
-- bounds. The slider starts at zero, and a zero on it means "as in the game"
-- rather than a number: anything at all reaches the profile, values from
-- future versions and from somebody's edits of SavedVariables included, and
-- one pure function brings them to order.
local PHYSICS = {
    {
        key   = "gravity",
        cvars = { "WorldTextGravity", "WorldTextGravity_v2" },
        min   = 0.5,
        max   = 10,
    },
    {
        key   = "duration",
        cvars = { "WorldTextRampDuration", "WorldTextRampDuration_v2" },
        min   = 0.1,
        max   = 3,
    },
}
Fonts.PHYSICS = PHYSICS

local PHYSICS_BY_KEY = {}
for i = 1, #PHYSICS do PHYSICS_BY_KEY[PHYSICS[i].key] = PHYSICS[i] end

--- A slider's value into a console variable's value.
--
-- A pure function and the physics' only arithmetic. A nil on the way out means
-- "the player set nothing": the caller is obliged to leave the engine its own
-- value rather than write a zero. Zero, rubbish and a negative read the same —
-- as "not set": the zero is labelled that way on the slider, while the rest
-- cannot be produced with it and comes only from SavedVariables. What was set
-- but went beyond the bounds of sense is clamped to the bound: there is no
-- reason to lose the player's instruction over one unit too many.
--
-- @param key string|nil the physics setting's key
-- @param value any the value from the profile
-- @return string|nil the string for SetCVar
function Fonts.PhysicsValue(key, value)
    local spec = type(key) == "string" and PHYSICS_BY_KEY[key] or nil
    if not spec then return nil end

    local number = tonumber(value)
    if not number or number <= 0 then return nil end

    if number < spec.min then number = spec.min end
    if number > spec.max then number = spec.max end

    return string.format("%.2f", number)
end

--- Apply the physics to the engine's console variables.
--
-- The reversibility is the same as the fonts': "as in the game" is not "skip"
-- but restoring the variable's own default, which the engine knows itself
-- (GetCVarDefault). Skipping would leave the figures falling our way forever,
-- and the label "as in the game" would be lying.
--
-- No write happens while the value already matches the wanted one. So a fresh
-- profile touches not one variable: there is nothing set in it, and the
-- default is already there.
--
-- The client's functions are passed as an argument rather than taken from _G
-- directly: that way the subsystem is tested outside the game, and their
-- absence is an ordinary answer rather than an error.
--
-- @param entry table|nil the combat text category's settings
-- @param api table|nil { Get, Set, Default }; the client's functions by
--     default
-- @return number how many variables were written
function Fonts.ApplyPhysics(entry, api)
    if type(api) ~= "table" then
        api = { Get = GetCVar, Set = SetCVar, Default = GetCVarDefault }
    end
    if type(api.Get) ~= "function" or type(api.Set) ~= "function" then
        return 0
    end

    local written = 0
    for i = 1, #PHYSICS do
        local spec = PHYSICS[i]
        local chosen = Fonts.PhysicsValue(spec.key,
            type(entry) == "table" and entry[spec.key] or nil)

        for j = 1, #spec.cvars do
            local name = spec.cvars[j]

            local want = chosen
            if not want and type(api.Default) == "function" then
                local okDefault, value = pcall(api.Default, name)
                if okDefault and type(value) == "string" and value ~= "" then
                    want = value
                end
            end

            if want then
                -- An empty answer means the variable does not exist on this
                -- client: there is nowhere to write, and that is not an
                -- error.
                local okGet, current = pcall(api.Get, name)
                if okGet and type(current) == "string" and current ~= ""
                    and tonumber(current) ~= tonumber(want) then
                    if pcall(api.Set, name, want) then
                        written = written + 1
                    end
                end
            end
        end
    end

    return written
end

-- The font of the world labels.
--
-- The three-dimensional text engine reads the path to the file out of the
-- game's global variable DAMAGE_TEXT_FONT, and reads it once — on entering
-- the world. It cannot replace the base font on the fly, so a new font is
-- visible only after a full logout to the character selection; a reload of the
-- interface does not help. The size, the outline, the gravity and the duration
-- change at once.
--
-- The original value is remembered at the first touch — by the same rule as
-- the font object's remembered base: otherwise "restore the native one" would
-- restore not the native one but our previous choice.
--
-- If the variable does not exist on the client, the subsystem does not create
-- it: creating somebody else's global variable out of nothing would mean
-- littering the shared namespace for the sake of something nobody will read
-- anyway.
local worldTextBase

-- What we last wrote into that variable.
--
-- === Why the writes are counted ===
--
-- A write into a global variable of the GAME's taints it: every piece of the
-- game's code that reads it afterwards runs tainted, and anything at all
-- further along its work may break because of that. The three-dimensional
-- combat text reads this variable — the text that appears when the player
-- casts.
--
-- It used to be written here on EVERY application of the settings: on entering
-- the world, on changing the profile, on every movement of a slider, on every
-- rearrangement of the bars. The taint was applied afresh constantly.
--
-- And all of it in vain. The engine reads the variable once — on entering the
-- world (see the explanation above) — and a second write in the same session
-- changes nothing at all. That is, there was a price and not the slightest use
-- in the repeats.
--
-- Now we write only when the value really is different. A fresh install does
-- not write at all: there is no chosen font in it, and writing the native
-- value over itself is a write with no difference, that is, pure taint.
local worldTextWrote

--- Set the font of the world labels.
-- @param path string|nil the path to the file; nil restores the native one
-- @return boolean whether such a variable exists on this client
local function WorldTextFont(path)
    if worldTextBase == nil then
        local current = _G.DAMAGE_TEXT_FONT
        worldTextBase = type(current) == "string" and current ~= ""
            and current or false
    end
    if not worldTextBase then return false end

    local wanted = path or worldTextBase

    -- Compared against what is in the variable now rather than only against
    -- our memory: somebody else may have changed it, and then our write is
    -- work rather than a repeat.
    local current = _G.DAMAGE_TEXT_FONT
    if worldTextWrote == wanted and current == wanted then return true end

    if current ~= wanted then _G.DAMAGE_TEXT_FONT = wanted end
    worldTextWrote = wanted

    return true
end
Fonts.WorldTextFont = WorldTextFont

-- The outlines. The key is stored in the settings, the value is the string of
-- flags for SetFont. An empty string means "no outline": that is exactly what
-- the engine expects, while a nil would mean "leave it as it was" and would
-- read quite differently.
local OUTLINE_FLAGS = {
    NONE         = "",
    OUTLINE      = "OUTLINE",
    THICKOUTLINE = "THICKOUTLINE",
    MONOCHROME   = "OUTLINE, MONOCHROME",
}

local OUTLINE_LABELS = {
    NONE         = "No Outline",
    OUTLINE      = "Thin Outline",
    THICKOUTLINE = "Thick Outline",
    MONOCHROME   = "Outline Without Antialiasing",
}

--- The string of SetFont flags for a setting's key.
-- A pure function. A nil on the way out means "not set": the caller is obliged
-- to leave the object its own flags rather than to set "no outline".
-- @param outline string|nil the setting's key
-- @return string|nil the string of flags
function Fonts.Flags(outline)
    if type(outline) ~= "string" then return nil end
    return OUTLINE_FLAGS[outline]
end

--- Pick a string value if one is set.
-- An empty string and the inheritance marker both count as "not set".
local function pickString(value)
    if type(value) ~= "string" then return nil end
    if value == "" or value == INHERIT then return nil end
    return value
end

--- Pick a size if one is set. Zero and rubbish count as "not set": the
-- setting comes from SavedVariables, into which anything at all finds its way
-- over the years.
local function pickSize(value)
    local size = tonumber(value)
    if not size or size <= 0 then return nil end
    return size
end

-- The adjustment's bounds. Wider than these the setting stops being an
-- adjustment: -10 eats the game's smallest label entirely, +20 turns a caption
-- into a heading.
local ADJUST_MIN, ADJUST_MAX = -10, 20
Fonts.ADJUST_MIN, Fonts.ADJUST_MAX = ADJUST_MIN, ADJUST_MAX

--- Pick the adjustment to the size if one is set.
--
-- A zero here means "as in the game" rather than "not set": an adjustment and
-- a zero mean one and the same thing, and there is no point telling them
-- apart. A negative value is legitimate — that is what sets an adjustment
-- apart from a size.
--
-- A value outside the bounds is clamped rather than discarded: anything at all
-- reaches SavedVariables, and "a font of size -40" the player would see as a
-- vanished interface without one hint why.
local function pickAdjust(value)
    local shift = tonumber(value)
    if not shift or shift == 0 then return 0 end
    if shift < ADJUST_MIN then return ADJUST_MIN end
    if shift > ADJUST_MAX then return ADJUST_MAX end
    return shift
end

--- Which font, size and outline are in effect for a category.
--
-- The subsystem's only arithmetic and the whole point of the two levels. Each
-- of the three fields falls through the levels independently: a category may
-- override the font and leave the size alone. An unknown category (or a nil
-- instead of a key) gives the global values — that is a normal answer rather
-- than an error: that way the function also answers the question "what is in
-- effect globally".
--
-- A nil in any field means "not set at any level": the caller leaves the
-- object its own value, that is, the game's native look.
--
-- @param global table|nil the global settings { font, size, outline }
-- @param categories table|nil the table of categories
-- @param key string|nil the category's key
-- @return string|nil the font's name
-- @return number|nil the size
-- @return string|nil the outline's key
function Fonts.Resolve(global, categories, key)
    local top = type(global) == "table" and global or {}

    local own
    if key ~= nil and type(categories) == "table" then
        local entry = categories[key]
        if type(entry) == "table" then own = entry end
    end
    own = own or {}

    local font    = pickString(own.font)    or pickString(top.font)
    local size    = pickSize(own.size)
    local outline = pickString(own.outline) or pickString(top.outline)

    return font, size, outline, pickAdjust(top.adjust)
end

-- Where the value in effect came from: "set here", "came from the global
-- level", "not set anywhere".
--
-- Why it exists at all. The two levels were visible only in the code: a zero
-- stood on an element's tab while the letters' size was not zero, and there
-- was nowhere to learn where it came from. Hence the complaint about the
-- page's former look — the global slider silently commanded everything. The
-- answer to "why does it say exactly this here" has to be in the window
-- itself rather than in the sources.
local OWN  = "own"
local TOP  = "global"
local NONE = "none"
Fonts.OWN, Fonts.TOP, Fonts.NONE = OWN, TOP, NONE

--- The level one field came from.
-- @param ownValue any the value of the level being asked about
-- @param topValue any the global level's value
-- @param pick function the level's coercing function (pickString or pickSize)
-- @param fromTop string what to call a value from the global level
local function originOf(ownValue, topValue, pick, fromTop)
    if pick(ownValue) ~= nil then return OWN end
    if pick(topValue) ~= nil then return fromTop end
    return NONE
end

--- Where a category's font, size and outline come from.
--
-- There is no arithmetic of its own: the same levels, the same order and the
-- same coercing functions as Fonts.Resolve. Two different parsers would
-- diverge silently, and the caption in the window would start lying — worse
-- than its absence.
--
-- The answer is given relative to the level that was asked about. A nil key
-- means the question is about the global level itself, and then a global value
-- is "set here" rather than "came from above": there is nothing above it.
--
-- @param global table|nil the global settings
-- @param categories table|nil the table of categories
-- @param key string|nil the category's key
-- @return string, string, string one of OWN, TOP, NONE per field
function Fonts.Origin(global, categories, key)
    local top = type(global) == "table" and global or {}

    local own
    if key ~= nil and type(categories) == "table" then
        local entry = categories[key]
        if type(entry) == "table" then own = entry end
    end
    own = own or {}

    local fromTop = (key ~= nil) and TOP or OWN

    -- The size is the only field with no global level: the global row sets
    -- an adjustment rather than a size, and "came from above" cannot be said
    -- about it. So the answer is only "set here" or "nowhere".
    return originOf(own.font,    top.font,    pickString, fromTop),
           originOf(own.size,    nil,         pickSize,   fromTop),
           originOf(own.outline, top.outline, pickString, fromTop)
end

--- The path to a font's file, if LibSharedMedia knows the name.
-- It repeats ns.Skin.MediaTexture's construction: the library is passed as an
-- argument, so the function is tested outside the game and its absence is an
-- ordinary nil answer rather than an error. The calls are guarded by pcall:
-- the library is somebody else's, and its version may have a different
-- signature.
-- @param media table|nil a LibSharedMedia-3.0 object or a compatible one
-- @param name any the supposed name of the font
-- @return string|nil the path to the file
function Fonts.MediaFont(media, name)
    if type(media) ~= "table" then return nil end
    if type(name) ~= "string" or name == "" or name == INHERIT then return nil end
    if type(media.IsValid) ~= "function" or type(media.Fetch) ~= "function" then
        return nil
    end

    local asked, valid = pcall(media.IsValid, media, "font", name)
    if not asked or not valid then return nil end

    -- noDefault = true: the name may be known while there turns out to be no
    -- path behind it.
    local fetched, path = pcall(media.Fetch, media, "font", name, true)
    if not fetched or type(path) ~= "string" or path == "" then return nil end

    return path
end

--- Whether an object is suitable for font work.
-- The game's font objects and font strings both know GetFont and SetFont
-- equally, so the subsystem does not tell them apart — and it is tested on a
-- stand-in object with those two methods.
local function usable(object)
    return type(object) == "table"
        and type(object.GetFont) == "function"
        and type(object.SetFont) == "function"
end

--- Remember an object's original font and return what was remembered.
-- Read exactly once — while the value has not yet been touched by us. After
-- that the record does not change, however many times the player edits the
-- setting: otherwise "a return to the native one" would restore not the native
-- one but our previous choice. Exactly the same scheme the dimming subsystem
-- uses for the native colour.
-- @param object table a font object or a font string
-- @return table|nil { path, size, flags }
local function Base(object)
    local stored = BASE[object]
    if stored then return stored end

    local ok, path, size, flags = pcall(object.GetFont, object)
    if not ok or type(path) ~= "string" then return nil end

    stored = { path, tonumber(size) or 0, flags or "" }
    BASE[object] = stored
    return stored
end

--- Set a font on an object.
-- A nil in any of the three arguments means "leave it as it was": the
-- remembered original value is taken. That way a partial override (a font
-- without a size) does not turn the size into a zero.
--
-- The size is chosen out of two different answers, and the order between them
-- is the whole point of the two levels:
--
--   1. The size set on an element's tab is a number, and it is what is set.
--      "Let the target's name be 16" means 16 rather than "16 plus something
--      else".
--   2. The adjustment is a shift from an element's native size. It is the
--      common level, and that is why it does not wipe out the difference
--      between a heading and a small caption: one and the same amount is added
--      to both rather than assigned.
--
-- Why not one common size. It was here, and here is how it ended: a slider at
-- 10 meant "ten everywhere", and the chat frame, the tooltips and the quest
-- log became one height, noticeably smaller than the game's. The player
-- meanwhile was asking for "as in the game, only bigger", and the former
-- setting could not express such a request at all.
--
-- @param object table an object with GetFont and SetFont
-- @param path string|nil the path to the font's file
-- @param size number|nil the size set on the element's tab
-- @param flags string|nil the string of outline flags
-- @param adjust number|nil the adjustment to the native size
-- @return boolean whether it was applied
function Fonts.Apply(object, path, size, flags, adjust)
    if not usable(object) then return false end

    local base = Base(object)
    if not base then return false end

    local wanted = size
    if wanted == nil then
        local native = tonumber(base[2]) or 0
        local shift  = tonumber(adjust) or 0
        -- A native size of zero means "no font has been assigned to this
        -- object yet", and there is nothing to add to it: an adjustment from
        -- the unknown is an invention.
        if native > 0 and shift ~= 0 then
            wanted = native + shift
            if wanted < 1 then wanted = 1 end
        end
    end

    local ok = pcall(object.SetFont, object,
        path or base[1], wanted or base[2], flags or base[3])
    return ok and true or false
end

--- Restore an object's original font.
-- What was remembered is not erased: the player may switch the replacement off
-- and on again any number of times, and each time one and the same thing has
-- to count as native. An object we have never touched has nothing to restore —
-- and needs none.
-- @param object table an object with GetFont and SetFont
-- @return boolean whether there was anything to restore
function Fonts.Restore(object)
    if not usable(object) then return false end

    local base = BASE[object]
    if not base then return false end

    local ok = pcall(object.SetFont, object, base[1], base[2], base[3])
    return ok and true or false
end

-- The addon's own window is outside the scope of the font settings.
--
-- Why. The font settings exist so that the player can restyle the game's
-- interface. Our settings window is the tool they do it with, and a tool that
-- rebuilds itself while it is being configured is uncontrollable: the slider
-- travels out from under the cursor, and a size convenient for the game may
-- make our window unreadable — and there would be nothing to come back with
-- but feeling one's way. So the exception is built into the selection of
-- targets rather than appended at the end as a special case: a target
-- belonging to our window does not become a target anywhere or for any level.
--
-- Where the boundary runs — by a frame's purpose rather than by its
-- authorship. The settings window is excluded: both our tree of sections and
-- the library's widgets it is assembled from. Everything the addon draws in
-- place of the game's interface — the bags window, the nameplates, the unit
-- frames, the action bars — stays within the scope: that is exactly what the
-- player is restyling, and the nameplates and the action bars have long had
-- target suppliers registered for it. A window of the game's that we only
-- tint (the character sheet) stays the game's all the more.

-- The name prefixes of the library's frames that have no obj field (the
-- shared AceGUI tooltip). The addon's own prefix is deliberately absent here:
-- both the bags window and the mover's overlay are named with it, while the
-- scope of the font settings ends at the settings window rather than at our
-- authorship.
local OURS_PREFIXES = { "AceGUI", "AceConfigDialog" }

-- How far to climb the chain of parents. A label lies inside a widget, a
-- widget inside a container, and the marker stands on any of them. The limit
-- is needed against a looped parent in somebody else's build: the walk has to
-- end.
local OURS_DEPTH = 8

--- An object method's string answer, if the method exists and did not
--- raise.
local function stringFrom(object, method)
    local fn = object[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object)
    if not ok then return nil end
    return ns.Skin.Textual(value)
end

--- Whether the frame itself carries the marker "this is the settings
--- window".
local function marked(frame)
    -- The library's field. AceGUI puts an obj reference to the widget
    -- itself onto each of its frames, and that widget has a type and a frame
    -- of its own. The marker is taken from the library's construction rather
    -- than from a name, because the library names its widgets itself
    -- (AceGUI30Button1 and the like), and the rule "the name begins with the
    -- addon's prefix" does not catch our own window at all. The same
    -- exception in the dimming subsystem broke on exactly this.
    local obj = frame.obj
    if type(obj) == "table" and type(obj.type) == "string"
        and obj.frame ~= nil then
        return true
    end

    -- The styling layer's marks: what it stripped and repainted in our
    -- palette receives them, that is, the settings window's widgets
    -- (Skin/Draw.lua, Skin/Containers.lua, Skin/Dropdown.lua).
    if frame.umbraStripped or frame.umbraSkinned then return true end

    local name = stringFrom(frame, "GetName")
    if name then
        for i = 1, #OURS_PREFIXES do
            local prefix = OURS_PREFIXES[i]
            if name:sub(1, #prefix) == prefix then return true end
        end
    end

    return false
end

--- Whether an object belongs to our settings window.
--
-- Asked both of the object itself and of its whole chain of parents: the
-- marker stands on the widget's frame, while the target of the replacement is
-- sometimes a font string lying inside it, which has no markers of its own and
-- cannot have any.
--
-- A font object of the game's (GameFontNormal and the rest) has no parent at
-- all — the walk ends at its very first step, and the answer is negative. That
-- matters: the objects themselves have to be replaced, or the global level
-- would stop working. The break of inheritance for our window is made
-- separately, below.
--
-- @param object table|nil a font object, a font string or a frame
-- @return boolean
function Fonts.IsOurs(object)
    if type(object) ~= "table" then return false end

    local node, steps = object, 0
    while type(node) == "table" and steps < OURS_DEPTH do
        if marked(node) then return true end

        local up = node.GetParent
        if type(up) ~= "function" then return false end
        local ok, parent = pcall(up, node)
        if not ok then return false end

        node = parent
        steps = steps + 1
    end

    return false
end

--- Whether an object is suitable as a target of the replacement.
--
-- The only place where a target is accepted. All three paths of selection use
-- it: the global level, a category's targets, and the replacement of a font on
-- one object from outside (Fonts.ApplyCategory). The check stands here rather
-- than in Fonts.Apply: Apply is the mechanism, and it is also what restores
-- the native font to our window, while the rule decides whom to replace.
local function accept(object)
    return usable(object) and not Fonts.IsOurs(object)
end

--- Fetch a nested field by a path such as "healthbar.TextString".
-- A pure function: parsing a path must not depend on the game. Any break in
-- the path gives a nil — a frame from another build simply has no such field,
-- and that is not an error.
-- @param root table|nil the root object
-- @param path string a dotted path
-- @return any|nil
function Fonts.Field(root, path)
    if type(root) ~= "table" or type(path) ~= "string" or path == "" then
        return nil
    end

    local node = root
    for part in string.gmatch(path, "[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

-- The default settings.
--
-- The replacement of the global fonts is on (skipGlobal = false), but the
-- global choice itself is empty: the font and the outline are inherited, the
-- size is zero. That is, a fresh profile changes not one letter until the
-- player chooses a font — the same rule by which the dimming slider stands at
-- zero.
--
-- The categories store the inheritance marker rather than a copy of the global
-- values: a copy would diverge from the global setting at its very first
-- edit.
local function defaultCategories()
    local out = {}
    for i = 1, #CATEGORIES do
        local entry = {
            font    = INHERIT,
            size    = 0,
            outline = INHERIT,
        }
        -- The physics belongs to the world labels' category alone, and its
        -- default is the same "as in the game" zero: a fresh profile moves
        -- not one console variable.
        if CATEGORIES[i].worldText then
            for j = 1, #PHYSICS do entry[PHYSICS[j].key] = 0 end
        end
        out[CATEGORIES[i].key] = entry
    end
    return out
end

Fonts.defaults = {
    -- "Do not touch the global fonts". Off by default: the replacement is
    -- allowed.
    skipGlobal = false,
    -- An adjustment rather than a size: a zero means "every element keeps
    -- its own size from the game", and that is why a fresh profile changes not
    -- one letter.
    global     = { font = INHERIT, adjust = 0, outline = INHERIT },
    categories = defaultCategories(),
}

--- The subsystem's settings from the profile.
-- @return table|nil
local function Settings()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    if not profile then return nil end
    return profile[Fonts.name]
end

--- The fonts library. Its absence is an ordinary nil answer rather than an
--- error.
-- LibStub is a table with a __call metamethod rather than a function, so the
-- call goes through pcall: somebody else's version might not know the second
-- argument that means "do not complain about an absence".
-- @return table|nil
local function Media()
    if not LibStub then return nil end
    local ok, media = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok and type(media) == "table" then return media end
    return nil
end
Fonts.Media = Media

-- Target suppliers from other subsystems: [category key] = array of
-- functions.
--
-- What they are for. The labels on the action bars' buttons are the same
-- hotkeys and counts that already exist as a category here, but the buttons'
-- names belong to the bars subsystem: it lays them out, hides them and styles
-- them. A second font-replacement mechanism in that subsystem would be a
-- second owner of one action — with a list of fonts of its own, a memory of
-- the native value of its own and an order of application of its own. So the
-- font stays here while the list of objects comes from where it actually
-- lives.
Fonts.providers = {}

--- Add a target supplier to a category.
-- Called by a subsystem while its file loads. The function is called every
-- time the settings are applied: the list of objects is assembled at the
-- moment of application rather than remembered — the client's frames may not
-- exist yet by the time the file loads.
-- @param key string the category's key
-- @param provider function a function that returns an array of objects
-- @return boolean whether it was accepted
function Fonts.AddTargets(key, provider)
    if type(key) ~= "string" or key == "" then return false end
    if type(provider) ~= "function" then return false end

    local list = Fonts.providers[key]
    if list == nil then
        list = {}
        Fonts.providers[key] = list
    end
    list[#list + 1] = provider
    return true
end

--- A category's targets on this client.
-- The font objects are taken from _G by name, the font strings out of the
-- frames the compatibility layer returned. Both are candidates: whatever is
-- absent is silently skipped.
-- @param category table a CATEGORIES record
-- @return table array of objects
local function CategoryTargets(category)
    local out = {}

    for i = 1, #category.globals do
        local object = _G[category.globals[i]]
        if accept(object) then out[#out + 1] = object end
    end

    if #category.units > 0 then
        local names = ns.Compat.Resolve("unitframe")
        for i = 1, #names do
            local frame = _G[names[i]]
            for j = 1, #category.units do
                local object = Fonts.Field(frame, category.units[j])
                if accept(object) then out[#out + 1] = object end
            end
        end
    end

    -- The other subsystems' suppliers. Each call is guarded: a supplier that
    -- raises must not cancel the font replacement on the category's remaining
    -- targets.
    local providers = Fonts.providers[category.key]
    if providers then
        for i = 1, #providers do
            local ok, extra = pcall(providers[i])
            if ok and type(extra) == "table" then
                for j = 1, #extra do
                    if accept(extra[j]) then out[#out + 1] = extra[j] end
                end
            end
        end
    end

    return out
end

--- A category's font under the current settings.
--
-- One place where a category turns into the triple "file, size, flags". Both
-- paths use it: the common pass over the targets (ApplySettings) and the
-- replacement of a font on one object (ApplyCategory).
--
-- @param key string the category's key
-- @return string|nil, number|nil, string|nil, number
local function categoryFont(key)
    local settings = Settings()
    if not settings then return nil, nil, nil, 0 end

    local font, size, outline, adjust =
        Fonts.Resolve(settings.global, settings.categories, key)
    return Fonts.MediaFont(Media(), font), size, Fonts.Flags(outline), adjust
end

--- Replace the font on one object by a category's rules.
--
-- Why a separate entrance. The game creates and dismantles nameplates
-- constantly, and the name's font string on a nameplate that has just appeared
-- did not exist at the moment of the common pass. Waiting for the next edit of
-- the settings is not an option: until then the name would stand in somebody
-- else's font.
--
-- This is not a second replacement mechanism: the rule for choosing the font
-- is the same (categoryFont), the memory of the original value is the same
-- (Fonts.Apply), and the font's owner is still one — this subsystem.
--
-- @param key string the category's key
-- @param object table|nil the font object
-- @return boolean whether it was applied
function Fonts.ApplyCategory(key, object)
    -- The selection of a target, even of one, follows the same rule: an
    -- object of our settings window does not become a target, no matter where
    -- it was passed in from.
    if type(key) ~= "string" or not accept(object) then return false end

    local path, size, flags, adjust = categoryFont(key)
    return Fonts.Apply(object, path, size, flags, adjust)
end

-- Breaking the inheritance in our window.
--
-- The selection of targets alone is not enough, and that is the main point
-- here. An AceGUI widget carries no font of its own: a standard font object of
-- the game's is assigned to it, and the labels take their font from that. The
-- replacement of such an object is the global level, it has to work, and our
-- window changed along with everything else while reaching not one list of
-- targets. Hence the author's complaint: they moved the size slider, and the
-- window they were moving it in grew along with the game.
--
-- So the labels of our window are assigned a font of their own — exactly the
-- one that stood on the font object before our first touch of it (the
-- remembered base). Not "the current one": by the moment of the pass our own
-- choice is already on the object, and remembering that would freeze the
-- labels in somebody else's look. After the assignment the label no longer
-- inherits from the object, and further edits of the global level do not reach
-- it at all.
--
-- A label that has no font object, or whose object we never touched, is not
-- touched here either: its font does not belong to us, and it is itself what
-- counts as native for it.

-- How deep to descend the window's tree. There is no nesting deeper than
-- AceGUI's widgets, while the limit is needed against a looped tree: the walk
-- has to end.
local PIN_DEPTH = 10

--- Collect a method's varargs into an array.
local function gather(method, object)
    return { method(object) }
end

-- What a font string itself is to wear: the font that belongs to it.
--
-- This is the very class of defect the record was created for. A pin is a
-- snapshot, and it held exactly until the next time a font object was assigned
-- to the label: the library does that when it hands a widget out of its pool
-- and when it draws a paragraph, and the engine does it itself, giving a
-- button and a tree row the object for the highlight under the cursor. After
-- any such assignment the label inherited the replaced object again, and the
-- pinning had to be redone — in every such place separately, one at a time,
-- and every new place arrived as a complaint from the author.
--
-- So a pin is now not a value assigned once but an intent recorded on the
-- label itself: "your font is this one". A repeated pinning reads what was
-- recorded and restores it, from wherever it was knocked off and however many
-- times that happened. Side memory, because the object is somebody else's.
local KEEP = ns.Skin.Memory()

--- Assign a font to a label and make sure it really took.
--
-- SetFont returns FALSE if the font's file did not load, and the label is then
-- left with no font at all: it stops drawing while keeping its former height.
-- A guarded call does not catch such a failure — it answers "it did not raise"
-- rather than "it is done", and the difference between those two answers was
-- enough here to turn the explanatory paragraphs in the settings window into
-- empty strips. The author saw it as a hole in the layout: a block's border,
-- fifty empty pixels beneath it, and only then the first setting.
--
-- So SetFont's answer is read, and beyond that the label is asked again: after
-- a failure it has no font at all, and GetFont answers with emptiness.
--
-- @param text table the font string
-- @param kept table { path, size, flags }
-- @return boolean whether the font took
local function applied(text, kept)
    -- What the label lived by before us. Needed so that there is somewhere to
    -- return to: a failed SetFont leaves the label with no font at all, and
    -- "we did not touch it" and "we put it out" are different things.
    local object
    if type(text.GetFontObject) == "function" then
        local fine, had = pcall(text.GetFontObject, text)
        if fine then object = had end
    end

    local ok, took = pcall(text.SetFont, text, kept[1], kept[2], kept[3])
    local good = ok and took ~= false

    if good and type(text.GetFont) == "function" then
        local fine, path = pcall(text.GetFont, text)
        if fine and (path == nil or path == "") then good = false end
    end

    if good then return true end

    -- The font did not take. The label is returned to the object the library
    -- gave it: somebody else's, but visible. A mute label is worse than an
    -- unpinned one — an unpinned one will merely travel with the player's
    -- settings, while a mute one will show nothing and take up its place on
    -- the page all the same.
    if object ~= nil and type(text.SetFontObject) == "function" then
        pcall(text.SetFontObject, text, object)
    end

    return false
end

--- Assign a font to a label and remember it for that label.
--
-- The only place where our window's font is assigned. Fonts.PinText restores
-- what was recorded afterwards, which is why the column of sections, with a
-- size of its own, does not argue with the pass over the window: the pass
-- restores its own size to it rather than the font object's.
--
-- @param text table the font string
-- @param path string the path to the font's file
-- @param size number|nil the size
-- @param flags string|nil the string of outline flags
-- @return boolean whether it was assigned
function Fonts.KeepFont(text, path, size, flags)
    if not usable(text) then return false end
    if type(path) ~= "string" or path == "" then return false end

    local kept = { path, tonumber(size) or 0, flags or "" }
    if not applied(text, kept) then return false end

    KEEP[text] = kept
    return true
end

--- Pin one label to the font that belongs to it.
--
-- The recorded intent comes first of all: a label the styling has already
-- assigned its own font to has to stay with it.
--
-- Next comes the native font of its font object. It is taken through Base
-- rather than through the stored record: before the first replacement there is
-- no record on the object yet, and the former pinning silently did nothing in
-- that case. That was the quietest of the paths — a widget born before the
-- player first touched the fonts went into the pool unpinned and came back
-- into the window already wearing somebody else's font. The native value can
-- be remembered without replacing anything: before a replacement the current
-- value is the native one.
--
-- @param text table the font string
-- @return boolean whether it was pinned
local function pin(text)
    if not usable(text) then return false end

    local kept = KEEP[text]
    if kept then
        if applied(text, kept) then return true end

        -- The pin did not take: the font we remember does not exist on this
        -- client. The label stays with the object the library gave it —
        -- somebody else's, but visible. The memory of the pin is discarded,
        -- or the next pass would repeat the same failure and put the label out
        -- again.
        KEEP[text] = nil
        return false
    end

    if type(text.GetFontObject) ~= "function" then return false end

    local ok, object = pcall(text.GetFontObject, text)
    if not ok or not usable(object) then return false end

    local base = Base(object)
    if not base then return false end

    return Fonts.KeepFont(text, base[1], base[2], base[3])
end

--- Pin one label, if it belongs to our settings window.
--
-- The door outwards, and the same boundary stands in it as in the selection of
-- targets: our window is a tool, and its label is pinned; a window the addon
-- draws in place of a window of the game's is the subject of the setting, and
-- its label is not touched at all. The styling layer uses it (ns.Skin.Text),
-- and that layer paints both with one call.
--
-- @param text table|nil the font string
-- @return boolean whether it was pinned
function Fonts.PinText(text)
    if not usable(text) then return false end
    if not Fonts.IsOurs(text) then return false end
    return pin(text)
end

--- Walk the window and pin its labels.
-- A function of its own with the root as an argument: that way the walk is
-- tested outside the game, the same way the dimming subsystem's walk is.
-- @param root table|nil the window's root frame
-- @param depth number|nil the current depth
-- @return number how many labels were pinned
function Fonts.PinWindow(root, depth)
    if type(root) ~= "table" then return 0 end
    depth = depth or 0

    local count = 0

    if pin(root) then count = count + 1 end

    if type(root.GetRegions) == "function" then
        local ok, regions = pcall(gather, root.GetRegions, root)
        if ok then
            for i = 1, #regions do
                if pin(regions[i]) then count = count + 1 end
            end
        end
    end

    if depth < PIN_DEPTH and type(root.GetChildren) == "function" then
        local ok, children = pcall(gather, root.GetChildren, root)
        if ok then
            for i = 1, #children do
                count = count + Fonts.PinWindow(children[i], depth + 1)
            end
        end
    end

    return count
end

--- The roots of our settings window, if it is built right now.
--
-- Asked of the library rather than remembered in a field of our own:
-- AceConfigDialog builds and dismantles the window, and a second ledger of the
-- same window would diverge from it silently. The absence of the library, the
-- absence of the tables and a closed window are ordinary answers rather than
-- errors: the player may change a font from the game's own interface options
-- while our window is not on screen at all.
-- @return table array of frames
local function OwnWindows()
    local out = {}
    if not LibStub then return out end

    local ok, dialog = pcall(LibStub, "AceConfigDialog-3.0", true)
    if not ok or type(dialog) ~= "table" then return out end

    -- The window opened by the slash command and the page embedded in the
    -- game's options: the library keeps them in two different tables, and both
    -- are about us.
    local holders = { dialog.OpenFrames, dialog.BlizOptions }
    for i = 1, #holders do
        local holder = holders[i]
        if type(holder) == "table" then
            local widget = holder[ADDON]
            local frame = type(widget) == "table" and widget.frame or nil
            if type(frame) == "table" then out[#out + 1] = frame end
        end
    end

    return out
end

--- Apply the settings.
-- The only path of application: entering the game, changing the profile and
-- editing any setting all lead here.
--
-- The order matters: the global level first, the categories afterwards. A
-- category whose targets overlapped with the global list overrides it
-- precisely by being applied last. The lists do not overlap at the moment,
-- deliberately, but the rule has to hold after something is added to them.
--
-- Not one of the operations here is protected by the engine: SetFont changes
-- the look rather than a frame's position or visibility. So the fonts have no
-- queue of deferred changes and must not have one — it would make the setting
-- sluggish for no reason.
function Fonts:ApplySettings()
    local settings = Settings()
    if not settings then return end

    local media = Media()

    -- The global level.
    local font, size, outline, adjust =
        Fonts.Resolve(settings.global, nil, nil)
    local path  = Fonts.MediaFont(media, font)
    local flags = Fonts.Flags(outline)

    -- Whose chat this is. Asked once, outside the loop: the answer is the
    -- same for both of the chat's objects and does not change while the
    -- player is logged in.
    local taken = Fonts.ChatTaken()

    for i = 1, #GLOBAL_OBJECTS do
        local name = GLOBAL_OBJECTS[i]
        local object = _G[name]
        if accept(object) then
            if taken and CHAT_OBJECTS[name] then
                -- The chat belongs to another addon: ours comes off it.
                --
                -- Restored rather than skipped, for the reason the switch
                -- below is a restoration rather than a skip: a skip would
                -- leave our font on the object for ever, and the chat addon
                -- reads that object to build its own.
                if Fonts.Restore(object) then
                    counters.yielded = counters.yielded + 1
                end
            elseif settings.skipGlobal then
                -- A restoration specifically rather than a skip. A skip
                -- would leave the interface with our font forever, and the
                -- switch would switch nothing off — the very defect for whose
                -- sake an excluded group in the dimming subsystem receives a
                -- factor of 1.
                Fonts.Restore(object)
            else
                Fonts.Apply(object, path, size, flags, adjust)
            end
        end
    end

    -- The second half of the same selection of targets: the labels of our
    -- settings window, which the replacement would reach through inheritance,
    -- bypassing any list. It comes right after the global level: by this
    -- minute every object's native font has been remembered, and there is
    -- something to pin with.
    local windows = OwnWindows()
    for i = 1, #windows do
        Fonts.PinWindow(windows[i])
    end

    -- The targeted level. The switch for the global replacement has nothing
    -- to do with it: that switch is about the game's standard objects rather
    -- than about the categories the player chose.
    for i = 1, #CATEGORIES do
        local category = CATEGORIES[i]
        local cPath, cSize, cFlags, cAdjust = categoryFont(category.key)

        local targets = CategoryTargets(category)
        for j = 1, #targets do
            Fonts.Apply(targets[j], cPath, cSize, cFlags, cAdjust)
        end

        -- The world labels. They have no font objects, so the font goes
        -- into the engine's variable and the physics into the console
        -- variables. Both actions take the same single path as everything
        -- else.
        if category.worldText then
            WorldTextFont(cPath)
            local entry = settings.categories
                and settings.categories[category.key]
            Fonts.ApplyPhysics(entry)
        end
    end
end

--- Return the font settings to the game's values.
--
-- The way back. There are six settings per tab and six tabs here, and it is
-- easy to end up in a state one cannot reassemble one setting at a time: the
-- author put it as "the fonts have all gone wrong somehow". Returning one
-- setting at a time requires remembering what was changed where, and nobody
-- remembers that.
--
-- Exactly the state a fresh install sees is restored, and it is taken from
-- Fonts.defaults rather than retyped here a second time: two lists of defaults
-- would diverge at the first edit of either, and "as in the game" would stop
-- meaning "as in the game". The categories are assembled afresh
-- (defaultCategories) rather than assigned by reference: the defaults table is
-- shared across the whole addon, and a profile that took it by reference would
-- be editing it from the inside.
--
-- Only the fonts are touched. This is not a reset of the profile: the dimming,
-- the bags and everything else stay as they stood.
--
-- The restoration is applied by the same single path as any edit, and so it
-- gives the game its fonts back at once, without a reload of the interface.
--
-- @return boolean whether there was anything to restore
function Fonts.ResetSettings()
    local settings = Settings()
    if not settings then return false end

    settings.skipGlobal = Fonts.defaults.skipGlobal
    settings.global = {
        font    = Fonts.defaults.global.font,
        adjust  = Fonts.defaults.global.adjust,
        outline = Fonts.defaults.global.outline,
    }
    settings.categories = defaultCategories()

    Fonts:ApplySettings()
    return true
end

--- Enabling the subsystem.
-- Deliberately empty: right after OnEnable the registry calls ApplyAll, and
-- the settings will be applied by the same single path as on any edit.
function Fonts:OnEnable()
end

--- The list of fonts from LibSharedMedia.
-- Assembled at the moment the list is opened rather than when the tree is
-- built: addons add fonts of their own whenever they like after we load. The
-- first row is "no value set" — without it the choice would be a one-way
-- road.
-- @param inheritLabel string the label of the "no value set" row
-- @return function the values function for AceConfig
local function FontValues(inheritLabel)
    return function()
        local values = { [INHERIT] = ns.Localize(inheritLabel) }

        local media = Media()
        if not media or type(media.List) ~= "function" then return values end

        local ok, list = pcall(media.List, media, "font")
        if not ok or type(list) ~= "table" then return values end

        for i = 1, #list do
            values[list[i]] = list[i]
        end
        return values
    end
end

--- The list of outlines, with the same "no value set" row first.
local function OutlineValues(inheritLabel)
    return function()
        local values = { [INHERIT] = ns.Localize(inheritLabel) }
        for key, label in pairs(OUTLINE_LABELS) do
            values[key] = ns.Localize(label)
        end
        return values
    end
end

-- The glyphs are mentioned plainly and in every choice of font: a font
-- without glyphs for the client's language turns text into empty boxes, and
-- nothing about a name in the list shows that.
--
-- The key is stored as a string of its own rather than glued to the text of a
-- label: the English string itself serves as the translation's key, and gluing
-- before the ns.Localize call would produce a separate key for every
-- description the warning landed in. So it is translated on its own and glued
-- to a description already translated.
local GLYPH_WARNING_KEY =
    "Note: a font without glyphs for your client language shows text as " ..
    "empty boxes. LibSharedMedia cannot check glyphs, so such a font " ..
    "sits in the list next to the rest. If text disappears after you " ..
    "pick one, put the previous font back - no interface reload needed."

--- The warning about glyphs, glued to a setting's description.
-- @return string
local function GlyphWarning()
    return "\n\n" .. ns.Localize(GLYPH_WARNING_KEY)
end

-- The full logout is mentioned plainly in the description of the world
-- labels' font.
--
-- Without that note the setting looks broken: the player changes the font, the
-- numbers over the units stay as they were even after a reload of the
-- interface, and one conclusion suggests itself — the addon does not work. The
-- cause is not in the addon: the three-dimensional text engine reads the
-- font's file once, on entering the world. So it says here both what does not
-- work at once and what does — otherwise the note would be read as "log out
-- again for every trifle".
--
-- The key is a string of its own for the same reason the warning about
-- glyphs is: the English string itself serves as the translation's key, and
-- gluing before the ns.Localize call would produce a separate key for every
-- description.
local LOGOUT_NOTE_KEY =
    "Note: the numbers floating over units are drawn by the world text " ..
    "engine, which reads the font file once, at login. A new font " ..
    "therefore shows up only after a full logout to character select - " ..
    "an interface reload is not enough. Size, outline, gravity and " ..
    "duration apply at once."

--- The note about the full logout, glued to a setting's description.
-- @return string
local function LogoutNote()
    return "\n\n" .. ns.Localize(LOGOUT_NOTE_KEY)
end

-- Our own window is mentioned plainly on the global tab.
--
-- Without that line the exception looks like an oversight: the player sets a
-- large font, the whole interface receives it and the settings window does
-- not, and one conclusion suggests itself. The cause is that this is the tool
-- they are working with right now, and that has to be said in the same place
-- where they choose the size.
--
-- The key is a string of its own for the same reason the warning about glyphs
-- is: the English string itself serves as the translation's key.
local OWN_WINDOW_KEY =
    "Darken's own settings window stays out of all of this on purpose: " ..
    "it is the tool you are changing the font with, and a window that " ..
    "resizes under your hands while you drag the slider is hard to steer " ..
    "and hard to get back. Everything else follows what you set here - " ..
    "the game's interface, and the windows Darken puts in its place, " ..
    "the bags window and the nameplates among them."

-- The boundary of "our window" is stated plainly on the own-text tab.
--
-- Without that line the tab reads as a promise it does not keep: the player
-- chooses a font for "the addon's window text", the settings window — also a
-- window of the addon's — does not change, and one conclusion suggests itself.
-- The cause is that the boundary runs by purpose rather than by authorship,
-- and that has to be said in the same place where the player chooses the font.
--
-- The key is a string of its own for the same reason the warning about glyphs
-- is: the English string itself serves as the translation's key.
local WINDOW_TEXT_KEY =
    "This covers the windows Darken draws in place of the game's own - " ..
    "the bags window and the item database among them. The settings " ..
    "window you are reading this in is not one of them: it is the tool, " ..
    "not the thing being set, and a window that reshapes itself while you " ..
    "adjust it is hard to steer. A window of a module picks this up when " ..
    "the module asks the core for it, so an older module may still be on " ..
    "the game's own font."

--- The note about the boundary, glued to the own-text tab.
-- @return string
local function WindowNote()
    return "\n\n" .. ns.Localize(WINDOW_TEXT_KEY)
end

--- The get/set handlers for one field of the global level.
-- @param field string the field's name
-- @return function, function
local function globalHandlers(field)
    return function()
        local settings = Settings()
        return settings and settings.global and settings.global[field]
    end,
    function(_, value)
        local settings = Settings()
        if not settings then return end
        settings.global = settings.global or {}
        settings.global[field] = value
        Fonts:ApplySettings()
    end
end

--- The get/set handlers for one field of a category.
-- @param key string the category's key
-- @param field string the field's name
-- @return function, function
local function categoryHandlers(key, field)
    return function()
        local settings = Settings()
        local categories = settings and settings.categories
        local entry = categories and categories[key]
        return entry and entry[field]
    end,
    function(_, value)
        local settings = Settings()
        if not settings then return end
        settings.categories = settings.categories or {}
        settings.categories[key] = settings.categories[key] or {}
        settings.categories[key][field] = value
        Fonts:ApplySettings()
    end
end

--- The global replacement is off — the global fields are inactive.
local function globalDisabled()
    local settings = Settings()
    return settings ~= nil and settings.skipGlobal == true
end

--- One field of the value in effect, in human words.
-- @param value any the value in effect (nil means not set)
-- @param from string Fonts.Origin's answer for that field
-- @return string
local function effectPiece(value, from)
    if from == NONE or value == nil then
        return ns.Localize("game's own")
    end
    if from == OWN then
        return string.format("%s (%s)",
            tostring(value), ns.Localize("set on this tab"))
    end
    return string.format("%s (%s)",
        tostring(value), ns.Localize("from the Global tab"))
end

--- The "what is in effect now" line for a tab.
--
-- Computed on every repaint of the window rather than when the tree is built:
-- the value changes right under the player's hand, and a frozen caption would
-- be a lie. Computed by the same Fonts.Resolve and Fonts.Origin the
-- application uses — there is no second rule of inheritance in the addon.
--
-- @param key string|nil the category's key; nil means the global level itself
-- @return string
local function EffectLine(key)
    local settings = Settings()
    local top  = settings and settings.global
    local cats = settings and settings.categories

    local font, size, outline, adjust = Fonts.Resolve(top, cats, key)
    local fFrom, sFrom, oFrom = Fonts.Origin(top, cats, key)

    -- The size is named one of two ways, and there is no lie between them:
    -- either a number stands on the tab, or an adjustment from the native size
    -- is in effect, and then that is what is said — "the game's own +2" rather
    -- than "2".
    local sizeText, sizeFrom = size, sFrom
    if size == nil then
        sizeFrom = NONE
        if adjust ~= 0 then
            sizeText = string.format(
                ns.Localize("game's own %+d"), adjust)
            sizeFrom = TOP
        end
    end

    -- The outline's key is shown by a human label. An unfamiliar key (an
    -- edit of SavedVariables by hand, a setting from a future version) is
    -- shown as it is: there is nothing to lie about it with.
    local outlineText
    if outline then
        local label = OUTLINE_LABELS[outline]
        outlineText = label and ns.Localize(label) or outline
    end

    return string.format(
        ns.Localize("In effect now - font: %s, size: %s, outline: %s."),
        effectPiece(font, fFrom),
        effectPiece(sizeText, sizeFrom),
        effectPiece(outlineText, oFrom))
end
Fonts.EffectLine = EffectLine

--- The global level's tab.
-- The switch "do not touch the global fonts" is here as well: it is about the
-- replacement of the game's standard font objects, that is, about exactly this
-- tab, and it stands first — it is also the retreat button when the chosen
-- font turns out to lack the needed glyphs.
-- @return table the tab's args
local function GlobalTab()
    local args = {}

    args.intro = {
        type = "description",
        order = 1,
        width = "full",
        name = function()
            return ns.Localize("Every other tab starts from what you " ..
                "choose here: a tab left on \"Same as Global\" follows " ..
                "this font and this outline, every element moves by the " ..
                "size adjustment below, and a tab that sets its own " ..
                "value wins over it. So one choice here is the short way " ..
                "to one font everywhere, and the tabs are for the " ..
                "elements that need something else.")
                .. "\n\n" .. ns.Localize(OWN_WINDOW_KEY)
                .. "\n\n" .. EffectLine(nil)
        end,
    }

    args.skipGlobal = {
        type = "toggle",
        order = 2,
        width = "full",
        name = ns.Localize("Leave Global Fonts Alone"),
        desc = ns.Localize("Replacing the standard font objects of " ..
            "the game changes text across the whole interface, the " ..
            "windows of other addons included. Checking this restores " ..
            "the game's own fonts at once, without an interface " ..
            "reload. Per-category overrides are not affected: they " ..
            "keep working."),
        get = function()
            local settings = Settings()
            return settings ~= nil and settings.skipGlobal == true
        end,
        set = function(_, value)
            local settings = Settings()
            if not settings then return end
            settings.skipGlobal = value and true or false
            Fonts:ApplySettings()
        end,
    }

    local getFont, setFont = globalHandlers("font")
    args.font = {
        type = "select",
        order = 3,
        width = "full",
        name = ns.Localize("Interface Font"),
        desc = ns.Localize("The font applied to the whole interface at " ..
            "once: windows, tooltips, the quest log, system messages. The " ..
            "list comes from LibSharedMedia, so it holds both the game's " ..
            "own fonts and everything other addons brought along.")
            .. GlyphWarning(),
        values = FontValues("Game's Own Font"),
        disabled = globalDisabled,
        get = getFont,
        set = setFont,
    }

    local getAdjust, setAdjust = globalHandlers("adjust")
    args.adjust = {
        type = "range",
        order = 4,
        -- zeroLabel: a zero on this slider means "as in the game" rather
        -- than "zero pixels". A bare zero in the value field reads the
        -- opposite way — as a broken setting. The label sits beside the
        -- setting, in the same arg table: the slider's styling reads it from
        -- there (Skin/Widgets.lua) and translates nothing itself.
        arg = { zeroLabel = ns.Localize("Game's Own") },
        width = "full",
        name = ns.Localize("Font Size Adjustment"),
        desc = ns.Localize("Bigger or smaller than the game draws it, by " ..
            "this many points. Zero is the game's own sizes. Every " ..
            "element keeps the size the game gave it and moves by the " ..
            "same step, so a heading stays bigger than a small label - " ..
            "which is exactly what one size for the whole interface used " ..
            "to destroy. A single element that needs an exact size gets " ..
            "it on its own tab, and that number wins over this one."),
        min = Fonts.ADJUST_MIN, max = Fonts.ADJUST_MAX, step = 1,
        disabled = globalDisabled,
        get = getAdjust,
        set = setAdjust,
    }

    local getOutline, setOutline = globalHandlers("outline")
    args.outline = {
        type = "select",
        order = 5,
        width = "full",
        name = ns.Localize("Outline"),
        desc = ns.Localize("The stroke around letters. \"Game's Own " ..
            "Outline\" leaves every element the outline it started with."),
        values = OutlineValues("Game's Own Outline"),
        disabled = globalDisabled,
        get = getOutline,
        set = setOutline,
    }

    -- The way back. It stands on the global tab because it restores not
    -- that tab alone but every font at once, and the place for "everything at
    -- once" is here, where the choice that affects everything at once
    -- stands.
    --
    -- Without a confirmation. A confirmation is needed where something cannot
    -- be undone, while here it can be undone by the same click on any
    -- setting: not one of them is lost forever, and the only thing that can be
    -- lost is one's own selection — and that only until the next selection. An
    -- unnecessary question on a reversible action teaches one to answer "yes"
    -- without reading, and the first real warning afterwards flies past.
    args.reset = {
        type = "execute",
        order = 6,
        width = "full",
        name = ns.Localize("Back to the Game's Own Fonts"),
        desc = ns.Localize("Puts every font setting back the way a fresh " ..
            "install has it: the font, size and outline here, every tab's " ..
            "own override, and the switch above. Nothing but the fonts is " ..
            "touched, and the game's own text comes back at once, without " ..
            "an interface reload."),
        func = function() Fonts.ResetSettings() end,
    }

    return args
end

--- The tab of one element.
-- @param category table a CATEGORIES record
-- @return table the tab's args
local function CategoryTab(category)
    local key = category.key
    local cGetFont, cSetFont = categoryHandlers(key, "font")
    local cGetSize, cSetSize = categoryHandlers(key, "size")
    local cGetOut,  cSetOut  = categoryHandlers(key, "outline")

    local args = {}

    args.intro = {
        type = "description",
        order = 1,
        width = "full",
        name = function()
            return ns.Localize("What you set here wins over the Global " ..
                "tab for this element alone. \"Same as Global\" means " ..
                "the field follows the Global tab instead and keeps " ..
                "following it as you change it there; a size of zero " ..
                "means this element keeps the size the game gave it, " ..
                "moved by the adjustment on the Global tab.")
                .. (category.ownWindows and WindowNote() or "")
                .. "\n\n" .. EffectLine(key)
        end,
    }

    args.font = {
        type = "select",
        order = 2,
        width = "full",
        name = ns.Localize("Font"),
        desc = ns.Localize("\"Same as Global\" means the " ..
            "category takes its font from the setting above " ..
            "and follows its changes from then on.")
            .. GlyphWarning()
            .. (category.worldText and LogoutNote() or ""),
        values = FontValues("Same as Global"),
        get = cGetFont,
        set = cSetFont,
    }

    -- The size is of the simple level, unlike the font and the outline. It
    -- is what the tabs were created for: the "font size" used to stand as one
    -- for the whole interface, and hiding its per-element replacement in an
    -- advanced mode would mean removing the setting rather than moving it.
    args.size = {
        type = "range",
        order = 3,
        arg = {
            zeroLabel = ns.Localize("Game's Own"),
        },
        width = "full",
        name = ns.Localize("Size"),
        desc = ns.Localize("An exact size for this element alone, in " ..
            "points, and it wins over the adjustment on the Global tab. " ..
            "Zero means the element keeps the size the game gave it and " ..
            "follows that adjustment instead."),
        min = 0, max = 32, step = 1,
        get = cGetSize,
        set = cSetSize,
    }

    args.outline = {
        type = "select",
        order = 4,
        width = "full",
        name = ns.Localize("Outline"),
        desc = ns.Localize("\"Same as Global\" means the outline is " ..
            "taken from the level above."),
        values = OutlineValues("Same as Global"),
        get = cGetOut,
        set = cSetOut,
    }

    -- The physics belongs to the world labels alone. There is nothing to
    -- fall for unit names and bar values, and a slider there would be a
    -- setting that does nothing. As a group of its own inside the tab: these
    -- are not a font's properties but the numbers' behaviour, and in one list
    -- with the font they would read as parts of it.
    if category.worldText then
        local pGetGrav, pSetGrav = categoryHandlers(key, "gravity")
        local pGetDur,  pSetDur  = categoryHandlers(key, "duration")

        args.physics = {
            type = "group",
            order = 5,
            inline = true,
            name = ns.Localize("Movement of the Numbers"),
            args = {
                gravity = {
                    type = "range",
                    order = 1,
                    arg = {
                        zeroLabel = ns.Localize("Game's Own"),
                    },
                    width = "full",
                    name = ns.Localize("Gravity"),
                    desc = ns.Localize("How fast the numbers fall after " ..
                        "they pop up. Zero leaves the game its own pull, " ..
                        "and the game's own value is 0.5: bigger numbers " ..
                        "drop faster, smaller ones let the numbers hang. " ..
                        "Takes effect at once, without a reload."),
                    min = 0, max = 10, step = 0.5,
                    get = pGetGrav,
                    set = pSetGrav,
                },
                duration = {
                    type = "range",
                    order = 2,
                    arg = {
                        zeroLabel = ns.Localize("Game's Own"),
                    },
                    width = "full",
                    name = ns.Localize("Duration"),
                    desc = ns.Localize("How long the numbers stay on " ..
                        "screen. Zero leaves the game its own timing, " ..
                        "and the game's own value is 1.0. Takes effect " ..
                        "at once, without a reload."),
                    min = 0, max = 3, step = 0.1,
                    get = pGetDur,
                    set = pSetDur,
                },
            },
        }
    end

    return args
end

--- Build the settings section.
--
-- The page is a row of tabs (childGroups = "tab"): one tab per element, and
-- the global level's tab first. The page used to be a single scroll with one
-- "font size" for the whole interface at its head; the per-element settings
-- lay below, and the connection between them and the slider above was written
-- nowhere in the window.
--
-- The stored shape of the settings is untouched in the process: the profile
-- still holds fonts.global and fonts.categories under the same keys. The
-- settings tree was rebuilt rather than the data — which is why there is no
-- migration here either: a global size the player already chose stays in place
-- and goes on being in effect.
--
-- A function of its own rather than a table at file level: the section is
-- built only when LibSharedMedia is present, and it suits the tests to build
-- it and check it with AceConfig's real validator.
-- @return table a fragment of the AceConfig tree
function Fonts.BuildOptions()
    local args = {
        global = {
            type = "group",
            order = 1,
            name = ns.Localize("Global"),
            args = GlobalTab(),
        },
    }

    -- The elements' tabs, in the order of CATEGORIES. Each corresponds to
    -- something the engine really reaches (CategoryTargets): an invented tab
    -- would be a setting that changes nothing.
    for i = 1, #CATEGORIES do
        local category = CATEGORIES[i]
        args[category.key] = {
            type = "group",
            order = 10 + i,
            name = ns.Localize(category.label),
            args = CategoryTab(category),
        }
    end

    return {
        type = "group",
        childGroups = "tab",
        name = ns.Localize("Fonts"),
        args = args,
    }
end

-- The settings section appears only when LibSharedMedia is present: there
-- would be nothing to choose a font from, and a list of one row saying "the
-- native font" would betray expectations. The module itself registers in any
-- case — its settings may already lie in the profile, and losing them because
-- a library is absent is not allowed.
if Media() then
    Fonts.options = Fonts.BuildOptions()
end

--============================================================================
-- The settings page, declared as data
--============================================================================

-- The fonts page is the first with tabs, and a tab is declared as a page of
-- its own with a parent field. The same way as in the column: a page knows
-- whose it is rather than the window knowing that there can be more pages
-- inside a page.
--
-- There are as many tabs as categories, plus the common one. Writing them out
-- one at a time would mean creating a second list of categories beside the
-- first — and it would diverge from it when a category was added,
-- silently.

if type(ns.Schema) == "table" then
    local Schema = ns.Schema

    Schema.Page("fonts", {
        title = "Fonts",
        order = 4,
        section = "fonts",
    })

    Schema.Add("fonts", {
        kind = "note",
        hint = "Every other tab starts from what you choose here: a tab "
            .. "left on \"Same as Global\" follows this font and this "
            .. "outline, every element moves by the size adjustment below, "
            .. "and a tab that sets its own value wins over it.",
    })

    -- What is in effect now. The line is computed: the value changes right
    -- under the player's hand, and one written once would be a lie a second
    -- later.
    --
    -- It exists because the settings here are ADJUSTMENTS, and a zero in them
    -- means "do not change". A page on which there is not one real number says
    -- nothing about that: the author asked three times why everything was
    -- zeroes.
    Schema.Add("fonts", {
        kind = "note",
        hint = function() return Fonts.EffectLine(nil) end,
    })

    Schema.Add("fonts", {
        kind = "toggle",
        label = "Leave Global Fonts Alone",
        path = { "skipGlobal" },
        apply = "fonts",
        hint = "Do not touch the game's own font objects at all. Everything "
            .. "the addon draws itself still follows the settings here.",
    })

    Schema.Add("fonts", {
        kind = "select",
        label = "Interface Font",
        path = { "global", "font" },
        disabled = globalDisabled,
        apply = "fonts",
        hint = "The font the whole interface uses. The first entry leaves "
            .. "the game's own font in place.",
        values = FontValues("Game's Own Font"),
    })

    Schema.Add("fonts", {
        kind = "slider",
        label = "Font Size Adjustment",
        path = { "global", "adjust" },
        disabled = globalDisabled,
        min = -10, max = 20, step = 1,
        apply = "fonts",
        hint = "A correction, not a size: zero means every element keeps "
            .. "the size the game gives it, so a fresh profile changes not "
            .. "a single letter.",
    })

    Schema.Add("fonts", {
        kind = "select",
        label = "Outline",
        path = { "global", "outline" },
        disabled = globalDisabled,
        apply = "fonts",
        hint = "The outline around every letter. Thin reads better on a "
            .. "bright world, none reads better on a dark interface.",
        values = function()
            return {
                { key = INHERIT, text = ns.Localize("Game's Own Outline") },
                { key = "NONE", text = ns.Localize("No Outline") },
                { key = "OUTLINE", text = ns.Localize("Thin Outline") },
                { key = "THICKOUTLINE", text = ns.Localize("Thick Outline") },
            }
        end,
    })

    -- A tab per category. The same list the fonts are applied by.
    for i = 1, #CATEGORIES do
        local entry = CATEGORIES[i]
        local id = "fonts." .. entry.key

        Schema.Page(id, {
            title = entry.label,
            order = 4 + i / 100,
            section = "fonts",
            parent = "fonts",
        })

        -- What is in effect on this tab now. A line of its own per category
        -- rather than one shared: their inheritance differs, and a shared line
        -- would tell the truth about one of them at best.
        local own = entry.key
        Schema.Add(id, {
            kind = "note",
            hint = function() return Fonts.EffectLine(own) end,
        })

        Schema.Add(id, {
            kind = "select",
            label = "Font",
            path = { "categories", entry.key, "font" },
            apply = "fonts",
            hint = "The font for this group of elements. The first entry "
                .. "follows the global tab.",
            values = FontValues("Same as Global"),
        })

        Schema.Add(id, {
            kind = "slider",
            label = "Size",
            path = { "categories", entry.key, "size" },
            min = 0, max = 32, step = 1,
            apply = "fonts",
            -- A zero here is not a size but "the same as everybody": a font
            -- of zero height does not exist, and a bare zero in the field
            -- reads as a failure.
            zero = "Same as Global",
            hint = "A size of its own for this group. Zero follows the "
                .. "global tab and the size adjustment on it.",
        })

        Schema.Add(id, {
            kind = "select",
            label = "Outline",
            path = { "categories", entry.key, "outline" },
            apply = "fonts",
            hint = "The outline for this group. The first entry follows "
                .. "the global tab.",
            values = function()
                return {
                    { key = INHERIT, text = ns.Localize("Same as Global") },
                    { key = "NONE", text = ns.Localize("No Outline") },
                    { key = "OUTLINE", text = ns.Localize("Thin Outline") },
                    { key = "THICKOUTLINE",
                      text = ns.Localize("Thick Outline") },
                }
            end,
        })
    end
end

ns.Registry:Register(Fonts)
