local helpers = require("helpers")

-- Settings as data: declaration and validation.
--
-- The schema exists for this check. An AceConfig tree is a table with a pair
-- of functions per field, and a typo in a field name gives a slider that
-- moves and changes nothing. The only way to learn about it was to drag it
-- in game and see whether anything changed.
--
-- What is checked here is that Validate catches every refusal BY NAME. A
-- check that "the complaint list is non-empty" would be useless: it would
-- pass even when the complaint is the wrong one.

local ns = helpers.newNamespace()
helpers.loadAddonFile("Options/Schema.lua", ns)

local Schema = ns.Schema

--- Whether any complaint mentions this.
-- @param list table
-- @param part string a fragment of the complaint text
-- @return boolean
local function said(list, part)
    for i = 1, #list do
        if tostring(list[i]):find(part, 1, true) then return true end
    end
    return false
end

--- Start from a clean slate and lay down the defaults.
-- @param defaults table|nil the profile section of the defaults
local function fresh(defaults)
    Schema.Forget()
    ns.Addon = {
        db = { profile = defaults or {} },
        defaults = { profile = defaults or {} },
    }
end

--============================================================================
-- Declaration
--============================================================================

T.suite("schema: declaring pages")

do
    fresh()

    T.eq(Schema.Page("general", { title = "General", order = 2 }), true,
        "the page is declared")
    T.eq(Schema.Page("general", {}), false, "a second time under the same name, no")
    T.eq(Schema.Page("", {}), false, "an empty name, no")
    T.eq(Schema.Page(nil, {}), false, "with no name, no")

    T.ok(Schema.Of("general") ~= nil, "the page is found by name")
    T.eq(Schema.Of("nosuch"), nil, "an unknown name gives nothing")
    T.eq(Schema.Of(nil), nil, "an empty name gives nothing")
end

T.suite("schema: page order is set by a number, not by declaration order")

-- Files load in TOC order, and tying the look of the window to it means
-- changing the window whenever a TOC line is moved.
do
    fresh()
    Schema.Page("third", { order = 30 })
    Schema.Page("first", { order = 10 })
    Schema.Page("second", { order = 20 })

    local list = Schema.Pages()
    T.eq(#list, 3, "all three are in place")
    T.eq(list[1].id, "first", "first comes the one with the smaller number")
    T.eq(list[2].id, "second", "second comes the next one")
    T.eq(list[3].id, "third", "and so on")

    -- Equal numbers must not change the order from run to run: pair
    -- iteration in Lua promises no order, and the column would be "sometimes different".
    fresh()
    Schema.Page("bbb", { order = 10 })
    Schema.Page("aaa", { order = 10 })
    local tied = Schema.Pages()
    T.eq(tied[1].id, "aaa", "on equal numbers, by name")
    T.eq(tied[2].id, "bbb", "and it does not depend on declaration order")
end

--============================================================================
-- Reading and writing
--============================================================================

T.suite("schema: reading and writing by path")

do
    local store = { darkness = { amount = 64, mode = { bags = "native" } } }

    T.eq(Schema.Read(store, { "darkness", "amount" }), 64, "a two-step path")
    T.eq(Schema.Read(store, { "darkness", "mode", "bags" }), "native",
        "a three-step path")
    T.eq(Schema.Read(store, { "darkness", "nosuch" }), nil,
        "an unknown key gives nothing")
    T.eq(Schema.Read(store, { "amount", "deeper" }), nil,
        "a path through a non-table gives nothing, not an error")
    T.eq(Schema.Read(nil, { "amount" }), nil, "with no store, nothing")
    T.eq(Schema.Read(store, nil), nil, "with no path, nothing")

    T.eq(Schema.Write(store, { "darkness", "amount" }, 80), true, "it was written")
    T.eq(store.darkness.amount, 80, "and the value is the right one")

    T.eq(Schema.Write(store, { "darkness", "mode", "bags" }, "dark"), true,
        "written deeper down")
    T.eq(store.darkness.mode.bags, "dark", "and there too")

    -- Intermediate tables are not created. A path absent from the defaults is
    -- a typo, and creating it silently would hide that typo forever: the
    -- setting gets written, gets read, and affects nothing.
    T.eq(Schema.Write(store, { "nosuch", "deeper" }, 1), false,
        "a path through something non-existent is not created")
    T.eq(store["nosuch"], nil, "and nothing appeared")

    T.eq(Schema.Write(store, {}, 1), false, "an empty path, no")
    T.eq(Schema.Write(nil, { "a" }, 1), false, "with no store, no")
end

--============================================================================
-- Validation
--============================================================================

T.suite("schema: Validate catches every refusal by name")

do
    fresh({ darkness = { amount = 64 } })
    Schema.Page("dark", { title = "Interface Darkness", section = "darkness" })

    -- An unknown kind.
    Schema.Add("dark", { kind = "wiggle", label = "Wiggle", apply = "none" })

    -- A typo in a field name: the slider moves, nothing changes.
    Schema.Add("dark", { kind = "slider", label = "Strength",
        path = { "amont" }, min = 0, max = 100, apply = "darkness" })

    -- No label.
    Schema.Add("dark", { kind = "toggle", path = { "amount" },
        apply = "none" })

    -- Bad slider bounds.
    Schema.Add("dark", { kind = "slider", label = "Backwards",
        path = { "amount" }, min = 100, max = 0, apply = "none" })

    -- A select with no values.
    Schema.Add("dark", { kind = "select", label = "Mode",
        path = { "amount" }, apply = "none" })

    -- A button with nothing to do.
    Schema.Add("dark", { kind = "action", label = "Do it", apply = "none" })

    -- A getter with no setter.
    Schema.Add("dark", { kind = "toggle", label = "Half",
        get = function() end, apply = "none" })

    -- Nothing said about what to apply.
    Schema.Add("dark", { kind = "toggle", label = "Mute",
        path = { "amount" } })

    local out = Schema.Validate()

    T.ok(said(out, "unknown kind 'wiggle'"), "the unknown kind is named")
    T.ok(said(out, "defaults have no field 'amont'"),
        "the typo in the field name is named")
    T.ok(said(out, "no label"), "the missing label is named")
    T.ok(said(out, "slider bounds are no good"), "the slider bounds are named")
    T.ok(said(out, "select has no values"), "the empty select is named")
    T.ok(said(out, "action has nothing to run"), "the empty button is named")
    T.ok(said(out, "has a getter but no setter"), "the half pair is named")
    T.ok(said(out, "does not say what to apply"),
        "the forgotten application is named")
end

T.suite("schema: a healthy declaration passes clean")

-- The other side: a check that always complains is just as useless as a
-- check that is always silent.
do
    fresh({ darkness = { amount = 64, desaturate = true, mode = {} } })
    Schema.Page("dark", { title = "Interface Darkness", section = "darkness",
        order = 3 })

    Schema.Add("dark", { kind = "header", label = "Strength" })
    Schema.Add("dark", { kind = "note" })
    Schema.Add("dark", { kind = "slider", label = "Strength",
        path = { "amount" }, min = 0, max = 100, step = 1,
        apply = "darkness" })
    Schema.Add("dark", { kind = "toggle", label = "Grey Out the Artwork",
        path = { "desaturate" }, apply = "darkness" })
    Schema.Add("dark", { kind = "select", label = "Mode",
        path = { "mode" }, values = function() return {} end,
        apply = "darkness" })
    Schema.Add("dark", { kind = "action", label = "Reset",
        run = function() end, apply = "none" })
    Schema.Add("dark", { kind = "toggle", label = "Derived",
        get = function() end, set = function() end, apply = "none" })

    local out = Schema.Validate()
    T.eq(#out, 0, "there are no complaints: " .. table.concat(out, " | "))
end

T.suite("schema: a page with no defaults is named")

-- A section declared as a page but absent from the defaults is a setting
-- with nowhere to be stored. Staying silent about it is not allowed: it will
-- be shown and forgotten on every relog.
do
    fresh({ darkness = {} })
    Schema.Page("ghost", { title = "Ghost", section = "nosuch" })

    local out = Schema.Validate()
    T.ok(said(out, "no defaults section"), "the section with no defaults is named")
end

T.suite("schema: a failing getter is named")

-- A failing custom getter is swallowed by a pcall in the window and looks
-- like an EMPTY setting: a slider at zero, a select without a single row.
-- The player reads that as "the setting does not work", not as "the
--
-- declaration is wrong". That is what happened to the darkening: the getter
-- called Darkness:GetSettings(), a method the core subsystem does not have
-- at all, and eleven selects on the page stood empty.
do
    Schema.Forget()
    Schema.Page("dark", { title = "Dark", section = "darkness" })
    ns.Addon = {
        db = { profile = { darkness = { amount = 64 } } },
        defaults = { profile = { darkness = { amount = 64 } } },
    }

    Schema.Add("dark", { kind = "slider", label = "Strength",
        min = 0, max = 100, apply = "none",
        get = function() error("no such method") end,
        set = function() end })

    local out = Schema.Validate()
    T.eq(#out, 1, "exactly one complaint")
    T.ok(out[1] ~= nil and out[1]:find("getter", 1, true) ~= nil,
        "and it is about the getter: " .. tostring(out[1]))

    -- A healthy getter raises no complaints.
    Schema.Forget()
    Schema.Page("dark", { title = "Dark", section = "darkness" })
    Schema.Add("dark", { kind = "slider", label = "Strength",
        min = 0, max = 100, apply = "none",
        get = function() return 64 end, set = function() end })
    T.eq(#Schema.Validate(), 0, "a healthy getter passes")
end

T.suite("schema: a list editor with a missing action is named")

-- An adapter missing one of its actions is a button that gets pressed and
-- does nothing. The player takes that for their own mistake: they press
-- "up", the rule does not move, and they blame themselves, not the addon.
--
-- The complaint belongs here rather than in the editor, because it is a
-- mistake of WHOEVER DECLARED the list -- so it must be said during
-- declaration validation, which the cold boot runs, not on a click in the client.
do
    helpers.loadAddonFile("Options/List.lua", ns)

    Schema.Forget()
    Schema.Page("rules", { title = "Rules" })

    local whole = {
        Entries = function() return {} end,
        Add = function() end,
        Remove = function() end,
        Move = function() end,
        Fields = function() return {} end,
    }

    Schema.Add("rules", { kind = "widget", hook = whole })
    T.eq(#Schema.Validate(), 0, "a complete adapter raises no complaints")

    Schema.Forget()
    Schema.Page("rules", { title = "Rules" })
    local lame = {}
    for key, value in pairs(whole) do lame[key] = value end
    lame.Fields = nil
    Schema.Add("rules", { kind = "widget", hook = lame })

    local out = Schema.Validate()
    T.eq(#out, 1, "an incomplete one gives exactly one complaint")
    T.ok(out[1] ~= nil and out[1]:find("Fields", 1, true) ~= nil,
        "and it names the missing action: " .. tostring(out[1]))

    -- The "widget" kind without an adapter is legitimate: not every custom
    -- row is a list, and demanding five functions from all of them means banning the rest.
    Schema.Forget()
    Schema.Page("rules", { title = "Rules" })
    Schema.Add("rules", { kind = "widget", build = function() end })
    T.eq(#Schema.Validate(), 0, "a custom row without a list raises no complaints")
end

T.suite("schema: which kinds store something")

do
    T.eq(Schema.Stores("toggle"), true, "a checkbox stores")
    T.eq(Schema.Stores("slider"), true, "a slider stores")
    T.eq(Schema.Stores("select"), true, "a select stores")
    T.eq(Schema.Stores("text"), true, "a text box stores")
    T.eq(Schema.Stores("color"), true, "a colour stores")

    T.eq(Schema.Stores("action"), false, "a button does not store")
    T.eq(Schema.Stores("header"), false, "a heading does not store")
    T.eq(Schema.Stores("note"), false, "a paragraph does not store")
    T.eq(Schema.Stores("tabs"), false, "a tab row does not store")
    T.eq(Schema.Stores("widget"), false, "a custom control does not store")

    T.eq(Schema.Stores("nosuch"), false, "an unknown kind does not store")
    T.eq(Schema.Stores(nil), false, "an empty kind does not store")
end

--============================================================================
-- Core pages
--============================================================================

T.suite("schema: the declared core pages validate clean")

-- The most valuable check of this file: not "Validate can complain" but
-- "there is nothing to complain about in our own declaration".
--
-- It catches what is otherwise caught only in game: a setting path absent
-- from the defaults, a forgotten application, a select with no values. Every
-- such mistake looks like a working setting that does nothing.
do
    local real = helpers.newNamespace()
    helpers.loadAddonFile("Core/Casefold.lua", real)
    helpers.loadAddonFile("Core/Skin.lua", real)
    helpers.loadAddonFile("Core/Registry.lua", real)
    helpers.loadAddonFile("Core/Locale.lua", real)
    helpers.loadAddonFile("Core/Defaults.lua", real)
    helpers.loadAddonFile("Core/Presets.lua", real)
    helpers.loadAddonFile("Options/Schema.lua", real)
    helpers.loadAddonFile("Options/List.lua", real)

    -- The order is the same as in game: first the subsystems and the pages
    -- are declared, and only then are the defaults assembled. Assembled
    -- earlier, they know not a single subsystem section -- which is exactly
    -- what the check said when the order was reversed.
    helpers.loadAddonFile("Core/Compat.lua", real)
    helpers.loadAddonFile("Modules/Darkness.lua", real)
    helpers.loadAddonFile("Core/Media.lua", real)
    helpers.loadAddonFile("Modules/Fonts.lua", real)
    helpers.loadAddonFile("Core/Events.lua", real)
    helpers.loadAddonFile("Core/Combat.lua", real)
    helpers.loadAddonFile("Modules/UnitFrames.lua", real)
    helpers.loadAddonFile("Modules/NamePlates.lua", real)
    helpers.loadAddonFile("Core/Format.lua", real)
    helpers.loadAddonFile("Core/AuraFilter.lua", real)
    helpers.loadAddonFile("Modules/Texts.lua", real)
    helpers.loadAddonFile("Modules/Bags.lua", real)
    helpers.loadAddonFile("Modules/Icons.lua", real)

    -- And the parts of the addon. The page is declared by the registering
    -- file, so that file is loaded too -- which means a core is needed for it
    --
    -- to hand itself to. The fake core behaves like the real one in two
    -- things, and both are necessary. It HANDS OUT a handle: a part that did
    -- not get one leaves its file before declaring the page, and the check
    -- would silently validate nothing. And it remembers the part defaults:
    -- without them Validate would say "no defaults section" about every page
    -- of the part -- that is, complain about a missing registration, not about the schema.
    local savedCore = _G.Darken
    local partDefaults = {}
    _G.Darken = {
        -- The core doors handed out are the REAL ones, not fakes. A part that
        -- did not get its door leaves its file before declaring the page and
        -- says not a word about it: the info panel disappeared exactly that
        -- way when the stub did not hand out GetFormat.
        GetFormat = function() return real.Format end,
        GetAuraFilter = function() return real.AuraFilter end,
        GetCasefold = function() return real.Casefold end,
        GetMedia = function() return real.Media end,
        GetSkin = function() return real.Skin end,
        GetFrameNames = function() return {} end,
        GetGameFunction = function() return nil end,
        RegisterModule = function(_, descriptor)
            if type(descriptor) == "table" and type(descriptor.name) == "string"
            then
                partDefaults[descriptor.name] = descriptor.defaults or {}
            end
            return {
                GetSettings = function() return {} end,
                RegisterStrings = function() end,
                RegisterEvent = function() end,
                RegisterCommand = function() end,
                Localize = function(_, key) return key end,
                Print = function() end,
                Apply = function() end,
            }
        end,
    }

    helpers.loadAddonFile("Core/Feature.lua", real)
    helpers.loadAddonFile("Features/Away/Missed.lua", real)
    helpers.loadAddonFile("Features/Away/Rules.lua", real)
    helpers.loadAddonFile("Features/Away/Screen.lua", real)
    helpers.loadAddonFile("Features/Away/Away.lua", real)
    helpers.loadAddonFile("Features/Durability/Rules.lua", real)
    helpers.loadAddonFile("Features/Durability/Block.lua", real)
    helpers.loadAddonFile("Features/Durability/Durability.lua", real)
    helpers.loadAddonFile("Features/ItemLevel/Level.lua", real)
    helpers.loadAddonFile("Features/ItemLevel/Pending.lua", real)
    helpers.loadAddonFile("Features/ItemLevel/Display.lua", real)
    helpers.loadAddonFile("Features/ItemLevel/ItemLevel.lua", real)
    helpers.loadAddonFile("Features/Auras/Layout.lua", real)
    helpers.loadAddonFile("Features/Auras/Filter.lua", real)
    helpers.loadAddonFile("Features/Auras/Sort.lua", real)
    helpers.loadAddonFile("Features/Auras/Grid.lua", real)
    helpers.loadAddonFile("Features/Auras/Mouse.lua", real)
    helpers.loadAddonFile("Features/Auras/Rules.lua", real)
    helpers.loadAddonFile("Features/Auras/Icon.lua", real)
    helpers.loadAddonFile("Features/Auras/Units.lua", real)
    helpers.loadAddonFile("Features/Auras/Auras.lua", real)
    helpers.loadAddonFile("Features/NamePlates/Colors.lua", real)
    helpers.loadAddonFile("Features/NamePlates/Geometry.lua", real)
    helpers.loadAddonFile("Features/NamePlates/Names.lua", real)
    helpers.loadAddonFile("Features/NamePlates/Filter.lua", real)
    helpers.loadAddonFile("Features/NamePlates/Cast.lua", real)
    helpers.loadAddonFile("Features/NamePlates/Rules.lua", real)
    helpers.loadAddonFile("Features/NamePlates/Arrange.lua", real)
    helpers.loadAddonFile("Features/NamePlates/Engine.lua", real)
    helpers.loadAddonFile("Features/NamePlates/Plate.lua", real)
    helpers.loadAddonFile("Features/NamePlates/NamePlates.lua", real)
    helpers.loadAddonFile("Features/InfoPanel/Format.lua", real)
    helpers.loadAddonFile("Features/InfoPanel/Broker.lua", real)
    helpers.loadAddonFile("Features/InfoPanel/Layout.lua", real)
    helpers.loadAddonFile("Features/InfoPanel/Cells.lua", real)
    helpers.loadAddonFile("Features/InfoPanel/Sources.lua", real)
    helpers.loadAddonFile("Features/InfoPanel/Panel.lua", real)
    helpers.loadAddonFile("Features/InfoPanel/InfoPanel.lua", real)

    _G.Darken = savedCore
    helpers.loadAddonFile("Options/Pages.lua", real)
    helpers.loadAddonFile("Options/Profiles.lua", real)

    -- The defaults taken are the same ones the core puts into the database:
    -- copying them here would mean validating the schema against a fiction.
    local defaults = real.BuildDefaults(real.Registry)
    T.eq(type(defaults), "table", "the core defaults are assembled")

    -- The minimap button lives in the shared settings, declared by the button
    -- module. It is not here, so the section is laid down by hand --
    -- otherwise the check would speak of a missing module, not of the schema.
    defaults.global.launcher = defaults.global.launcher
        or { shown = true, angle = 0 }

    for name, own in pairs(partDefaults) do
        defaults.profile[name] = own
    end

    real.Addon = {
        db = { profile = {}, global = {} },
        defaults = defaults,
    }

    local pages = real.Schema.Pages()
    T.ok(#pages > 0, "the core pages are declared: " .. #pages)

    -- By name, not only by count. A page declaration is wrapped in an "is
    -- there a schema at all" check, and a subsystem that stopped creating one
    -- stays silent: Validate does not complain about what is absent. This
    -- list is the guard that would catch such silence.
    do
        local seen = {}
        for _, page in ipairs(pages) do seen[page.id] = true end
        for _, id in ipairs({
            "general", "launcher", "profiles",
            "darkness", "fonts",
            "umbraafk", "umbradurability", "umbrailevel", "umbrainfo",
            "umbraauras", "umbraplates", "unitframes", "nameplates",
        }) do
            T.ok(seen[id] == true, "the page is declared: " .. id)
        end
    end

    for _, page in ipairs(pages) do
        T.ok(type(page.title) == "string" and page.title ~= "",
            "the page is named: " .. tostring(page.id))
        T.ok(type(page.order) == "number",
            "the page has a place in the column: " .. tostring(page.id))
    end

    -- Conditions are not lost in a move.
    --
    -- This guard was created after a real loss: three global font fields were
    -- greyed out when the global override was off, and group frame sizes when
    -- "set the size" was off, and after the move to our own schema nothing
    -- was greyed out at all. There was no check for it, because the window
    -- opened and looked whole: a greyed-out state is invisible until you turn
    -- off the thing it depends on.
    --
    -- The presence of the field is checked, not its answer: the answer depends
    -- on the profile, while what can be lost is the field.
    do
        local function rowOf(pageId, label)
            for _, item in ipairs(real.Schema.Items(pageId)) do
                if item.label == label then return item end
            end
            return nil
        end

        for _, want in ipairs({
            { "fonts", "Interface Font", "disabled" },
            { "fonts", "Font Size Adjustment", "disabled" },
            { "fonts", "Outline", "disabled" },
            { "unitframes", "Group Frame Width", "disabled" },
            { "unitframes", "Group Frame Height", "disabled" },
            { "unitframes", "Group Frame Scale", "disabled" },
            { "unitframes", "Set the Size of Group Frames", "hidden" },
            { "unitframes", "Group Frame Width", "hidden" },
            { "umbraauras", "Show Only Buffs You Cast", "disabled" },
        }) do
            local pageId, label, field = want[1], want[2], want[3]
            local row = rowOf(pageId, label)
            T.ok(row ~= nil, "the row is in place: " .. pageId .. "/" .. label)
            if row ~= nil then
                T.ok(type(row[field]) == "function",
                    "the condition is in place: " .. pageId .. "/" .. label
                    .. " (" .. field .. ")")
            end
        end

        -- List editors: the editor is declared and its adapter is complete.
        --
        -- The guard above watches the PAGES, and a list declared outside them
        -- would go unnoticed: the page itself is in place. And slipping
        -- outside is easy -- the block is wrapped in an "is there an editor at all" check.
        for _, want in ipairs({
            { "umbraauras", "Rule to Edit" },
            { "umbraplates", "Rule to Edit" },
            { "umbrainfo", "Cell" },
            { "umbraplates", "Part to Place" },
        }) do
            local pageId, label = want[1], want[2]
            local row = rowOf(pageId, label)
            T.ok(row ~= nil, "the list is declared: " .. pageId .. "/" .. label)
            if row ~= nil then
                T.eq(row.kind, "widget", "and it is of its own kind")
                local fine, gone = real.ListEditor.Ready(row.hook)
                T.ok(fine, "the adapter is complete: " .. tostring(gone))
            end
        end

        for _, want in ipairs({
        }) do
            local pageId, label, field = want[1], want[2], want[3]
            local row = rowOf(pageId, label)
            T.ok(row ~= nil, "the row is in place: " .. pageId .. "/" .. label)
            if row ~= nil then
                T.ok(type(row[field]) == "function",
                    "the condition is in place: " .. pageId .. "/" .. label
                    .. " (" .. field .. ")")
            end
        end
    end

    -- And the main thing: there is nothing to complain about in our own declaration.
    local out = real.Schema.Validate()
    T.eq(#out, 0, "the core pages validate: "
        .. table.concat(out, " | "))
end
