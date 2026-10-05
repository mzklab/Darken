local helpers = require("helpers")

helpers.installValidator()

-- The public module contract.
--
-- It is checked more strictly than the rest, and the reason is not the
-- complexity of the code. This is the one layer of the addon that cannot be
-- changed after release: people we cannot reach by editing our own code will
-- lean on it from outside. A mistake here is invisible to the eye -- it
-- arrives weeks later, through someone else's player, as spoiled settings.

--- Assemble the core as the public layer sees it.
-- @return table the namespace
-- @return table the list of what was said to the player
local function core()
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Frames.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/Api.lua", ns)

    local said = {}
    ns.Addon = {
        db = { profile = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }

    return ns, said
end

-- "The field does not exist at all". An ordinary nil cannot record that:
-- pairs over a table with a nil value does not see such an entry, and the field would stay filled in.
local NONE = {}

--- A descriptor with the mandatory fields filled in.
local function descriptor(over)
    local d = { name = "example", api = 1 }
    for key, value in pairs(over or {}) do
        if value == NONE then
            d[key] = nil
        else
            d[key] = value
        end
    end
    return d
end

T.suite("the public object")

do
    local ns = core()
    T.eq(ns.Api.API_VERSION, 23, "the contract version is declared as a number")
    T.eq(ns.Api.API_MIN_VERSION, 1, "the oldest accepted version is declared")

    -- The surface is deliberately small: every name here is a promise forever.
    -- The check stands here so that a public name added by accident demands a
    -- deliberate decision rather than slipping into a release unnoticed.
    --
    -- The whole list is pinned rather than the functions alone: the point of a
    -- snapshot is that it does not change, and the former variant counted only
    -- functions and would not have reacted to a new field (or to a function
    -- that became a field) at all. The type is written beside the name for the same reason.
    local surface = {}
    for key, value in pairs(ns.Api) do
        surface[#surface + 1] = key .. ":" .. type(value)
    end
    table.sort(surface)
    T.eq(table.concat(surface, ","),
        "API_MIN_VERSION:number,API_VERSION:number,"
        .. "GetAuraFilter:function,GetCasefold:function,GetFlavor:function,"
        .. "GetFormat:function,"
        .. "GetFrameNames:function,GetGameFunction:function,"
        .. "GetMedia:function,GetSkin:function,GetUnitColors:function,"
        .. "GetVersion:function,IsTapDenied:function,MoversShown:function,"
        .. "RegisterModule:function,Supports:function,ToggleMovers:function",
        "the surface of the public object: " .. table.concat(surface, ","))

    T.eq(ns.Api:Supports(1), true, "the first version is still accepted")
    T.eq(ns.Api:Supports(2), true, "a prior version is supported")
    T.eq(ns.Api:Supports(3), true, "a prior version is supported")
    T.eq(ns.Api:Supports(4), true, "a prior version is supported")
    T.eq(ns.Api:Supports(5), true, "a prior version is supported")
    T.eq(ns.Api:Supports(6), true, "a prior version is supported")
    T.eq(ns.Api:Supports(7), true, "a prior version is supported")
    T.eq(ns.Api:Supports(8), true, "a prior version is supported")
    T.eq(ns.Api:Supports(9), true, "a prior version is supported")
    T.eq(ns.Api:Supports(10), true, "a prior version is supported")
    T.eq(ns.Api:Supports(11), true, "a prior version is supported")
    T.eq(ns.Api:Supports(12), true, "a prior version is supported")
    T.eq(ns.Api:Supports(13), true, "a prior version is supported")
    T.eq(ns.Api:Supports(14), true, "a prior version is supported")
    T.eq(ns.Api:Supports(15), true, "a prior version is supported")
    T.eq(ns.Api:Supports(16), true, "a prior version is supported")
    T.eq(ns.Api:Supports(17), true, "a prior version is supported")
    T.eq(ns.Api:Supports(18), true, "a prior version is supported")
    T.eq(ns.Api:Supports(19), true, "a prior version is supported")
    T.eq(ns.Api:Supports(20), true, "a prior version is supported")
    T.eq(ns.Api:Supports(21), true, "a prior version is supported")
    T.eq(ns.Api:Supports(22), true, "a prior version is supported")
    T.eq(ns.Api:Supports(23), true, "the current version is supported")
    T.eq(ns.Api:Supports(24), false, "a future version is not supported")
    T.eq(ns.Api:Supports(0), false, "a version below the first is not supported")
    T.eq(ns.Api:Supports("1"), false, "a string does not count as a version")
    T.eq(ns.Api:Supports(nil), false, "a missing version is not supported")
    T.eq(ns.Api:Supports(0 / 0), false, "NaN does not count as a version")

    -- The flavour is handed out by the core so that every module does not
    -- create a client detection of its own: three such detections will diverge from ours silently.
    T.eq(ns.Api:GetFlavor(), nil, "before the core starts the flavour is unknown")
    ns.flavor = "vanilla"
    T.eq(ns.Api:GetFlavor(), "vanilla", "after the start the same flavour is returned")
end

T.suite("the descriptor surface")

do
    local ns = core()
    local handle = ns.Api:RegisterModule(descriptor({ name = "surface" }))

    -- The snapshot is taken from the table of descriptor fields rather than
    -- from pairs(handle): the descriptor itself is empty, its fields live
    -- behind __index (see Core/Api.lua), and pairs over it would show only what the module author added.
    local fields = getmetatable(handle).__index

    local names = {}
    for key, value in pairs(fields) do
        names[#names + 1] = key .. ":" .. type(value)
    end
    table.sort(names)
    T.eq(table.concat(names, ","),
        "Apply:function,Counters:function,"
        .. "GetFrame:function,GetSettings:function,"
        .. "InCombat:function,IsEnabled:function,Localize:function,"
        .. "Migrate:function,"
        .. "OnRepaint:function,Own:function,Print:function,Publish:function,"
        .. "Refresh:function,RegisterCommand:function,"
        .. "RegisterEvent:function,"
        .. "RegisterStrings:function,Releases:function,Replaces:function,"
        .. "Secure:function,"
        .. "UnregisterEvent:function,api:number,name:string",
        "the descriptor surface: " .. table.concat(names, ","))

    -- The list of reserved fields is part of the contract: it is listed in
    -- docs/module-api.md and has no right to diverge from the code. The
    -- document check stands below, in a separate suite: formerly this thought
    -- was written as a comment, nobody read the document, and the divergence
    -- the comment forbade happened silently.
    local reserved = {}
    for key in pairs(ns.RESERVED_HANDLE_FIELDS) do
        reserved[#reserved + 1] = key
    end
    table.sort(reserved)
    T.eq(table.concat(reserved, ","),
        "Apply,ApplySettings,Counters,GetFrame,GetSettings,InCombat,"
        .. "IsEnabled,"
        .. "Localize,Migrate,OnDisable,OnEnable,OnRepaint,Own,"
        .. "Print,Publish,Refresh,"
        .. "RegisterCommand,RegisterEvent,RegisterStrings,"
        .. "Releases,Replaces,"
        .. "Secure,"
        .. "UnregisterEvent,api,defaults,globals,name,options",
        "the reserved descriptor fields: " .. table.concat(reserved, ","))
end

T.suite("the core fields on a descriptor are protected from writing")

do
    local ns = core()
    local handle = ns.Api:RegisterModule(descriptor({
        name = "guarded",
        OnEnable = function() end,
    }))

    -- Putting your own state on the descriptor is allowed and required: the contract says so.
    handle.marks = { 1, 2, 3 }
    handle.count = 7
    T.eq(handle.count, 7, "the own field was written")
    T.eq(#handle.marks, 3, "and so was the own table")

    -- The core fields are not. And specifically by writing rather than by
    -- substitution on reading: the fields lie behind __index, the descriptor
    -- itself is empty, so __newindex fires for "name" too.
    T.err(function() handle.name = "victim" end, "the name cannot be overwritten")
    T.err(function() handle.options = {} end, "the settings section cannot be overwritten")
    T.err(function() handle.OnEnable = nil end, "the enabling cannot be overwritten")
    T.err(function() handle.GetSettings = function() end end,
        "the settings accessor cannot be overwritten")
    T.err(function() handle.defaults = { a = 1 } end,
        "the defaults cannot be overwritten")

    T.eq(handle.name, "guarded", "the name stayed the same")
    T.eq(type(handle.OnEnable), "function", "the enabling is in place")
end

T.suite("reconciling the contract versions")

do
    local ns = core()

    -- Exactly equal: the one case in which a module loads.
    T.eq((ns.CheckApiVersion("m", 1, 1, 1)), true, "equal versions agree")

    -- A module newer than the core: the core is at fault, and what must be said is to update it.
    local ok, err = ns.CheckApiVersion("m", 2, 1, 1)
    T.eq(ok, false, "a module newer than the core is rejected")
    T.ok(err:find("update Darken", 1, true) ~= nil,
        "it says to update the core: " .. tostring(err))
    T.ok(err:find("m", 1, true) ~= nil, "the module name is given")

    -- A module older than the oldest accepted version: the module is at fault.
    local okOld, errOld = ns.CheckApiVersion("m", 1, 3, 2)
    T.eq(okOld, false, "too old a module is rejected")
    T.ok(errOld:find("update the module", 1, true) ~= nil,
        "it says to update the module: " .. tostring(errOld))

    -- Older than the current one but not older than the accepted one: it loads.
    T.eq((ns.CheckApiVersion("m", 2, 3, 1)), true,
        "a version inside the supported range is accepted")

    -- There is no version at all.
    local okNone, errNone = ns.CheckApiVersion("m", nil, 1, 1)
    T.eq(okNone, false, "a module with no declared version is rejected")
    T.ok(errNone:find("does not say", 1, true) ~= nil,
        "it says the version is not declared")
    T.eq((ns.CheckApiVersion("m", "1", 1, 1)), false, "a string does not count as a version")
end
T.suite("the registration rejects")

do
    --- Check a refusal.
    -- @param over table the descriptor fields
    -- @param fragment string what the message must contain
    -- @param msg string
    local function rejects(over, fragment, msg)
        local ns, said = core()
        ns.Api:RegisterModule(descriptor({ name = "taken", api = 1 }))

        local handle, reason
        if over == nil then
            handle, reason = ns.Api:RegisterModule(nil)
        else
            handle, reason = ns.Api:RegisterModule(descriptor(over))
        end

        T.eq(handle, nil, msg .. ": the module is not registered")
        T.ok(type(reason) == "string" and reason ~= "",
            msg .. ": the reason is given")
        if type(reason) == "string" and fragment then
            T.ok(reason:find(fragment, 1, true) ~= nil,
                msg .. ": the reason should contain \"" .. fragment .. "\", got: " .. reason)
        end

        -- The player learns about a foreign module breaking by themselves: the
        -- module author and the sufferer are different people, and silence
        -- would leave the player with an addon that "simply does not work".
        T.eq(#said, 1, msg .. ": the player was told once")
    end

    rejects(nil, "table", "not a table")
    rejects({ name = NONE }, "name", "with no name")
    rejects({ name = "" }, "name", "an empty name")
    rejects({ name = "1abc" }, "name", "a name starting with a digit")
    rejects({ name = "with space" }, "name", "a name with a space")
    rejects({ name = "модуль" }, "name", "Cyrillic in the name")
    rejects({ name = string.rep("a", 33) }, "name", "too long a name")
    rejects({ name = "version" }, "belongs to Darken itself", "a housekeeping profile field")
    rejects({ name = "skinAce" }, "belongs to Darken itself", "a shared core setting")
    rejects({ name = "general" }, "belongs to Darken itself", "the \"General\" section of the tree")
    rejects({ name = "profiles" }, "belongs to Darken itself", "the profiles section")
    rejects({ name = "taken" }, "already registered", "a taken name")
    rejects({ api = NONE }, "does not say", "with no contract version")
    rejects({ api = 99 }, "update Darken", "a version newer than the core")
    rejects({ defaults = "no" }, "defaults", "defaults is not a table")
    rejects({ OnEnable = "no" }, "OnEnable", "OnEnable is not a function")
    rejects({ ApplySettings = 5 }, "ApplySettings", "ApplySettings is not a function")
    rejects({ options = { type = "toggle" } }, "group", "the section is not a group")
    rejects({ options = { type = "group" } }, "group", "the group has no args")
    rejects({ globals = 5 }, "globals", "globals is not a table")
    rejects({ OnDisable = "no" }, "OnDisable", "OnDisable is not a function")

    -- NaN is a number by type, but both range checks give false for it, and the
    -- version would pass straight through: a module with api = 0/0 would thereby
    -- declare any contract version at all.
    rejects({ api = 0 / 0 }, "does not say", "a NaN version")

    -- The handler + method-name-as-string form. AceConfig understands it and
    -- calls t:GetFoo(info) itself, around our wrapper: a failing get would mean
    -- a yellow error over the settings window -- exactly what the document
    -- promises not to allow. It cannot be wrapped in place without rewriting
    -- the foreign handler table, so it is not supported.
    rejects({ options = {
        type = "group", name = "H", handler = {}, args = {},
    } }, "handler", "a handler on the section root")

    rejects({ options = { type = "group", name = "H", args = {
        inner = { type = "group", name = "I", handler = {}, args = {} },
    } } }, "handler", "a handler on a nested node")

    rejects({ options = { type = "group", name = "H", args = {
        flag = { type = "toggle", name = "F", get = "GetFlag" },
    } } }, "GetFlag", "a method name as a string in get")

    rejects({ options = { type = "group", name = "H", args = {
        list = { type = "select", name = "L", values = "ListValues" },
    } } }, "ListValues", "a method name as a string in values")
end

T.suite("there is nothing to validate the settings section with")

do
    -- Formerly the validation was simply skipped and a failure looked like a
    -- success: a section AceConfig does not accept would travel into the tree
    -- and close the whole settings window. A missing library is a broken core
    -- installation, and that must be said outright.
    T.suite("the core styling handed to a module")

do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Skin/Draw.lua", ns)
    helpers.loadAddonFile("Core/Frames.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/Api.lua", ns)

    local skin = ns.Api:GetSkin()
    T.ok(type(skin) == "table", "the styling is handed out as a table of functions")

    local r, g, b, a = skin.Color("panel")
    T.eq(type(r) == "number" and type(g) == "number" and type(b) == "number",
        true, "a palette colour is handed out as three numbers")
    T.eq(a, 1, "the default alpha is one")
    T.eq(skin.Color("no-such-colour"), nil, "an unknown colour name gives nil")

    local names = skin.Colors()
    T.ok(#names > 0, "the colour names are listed: " .. #names)

    -- The table is handed out as a copy: a module given the shared one would
    -- repaint the core along with every neighbour in one write.
    local metrics = skin.Metrics()
    T.eq(metrics.gap, ns.Skin.Metrics.gap, "the spacing scale is the same")
    metrics.gap = 999
    T.eq(ns.Skin.Metrics.gap ~= 999, true, "and is edited only for the module")

    names[1] = "spoiled"
    T.eq(skin.Colors()[1] ~= "spoiled", true,
        "the list of colour names is a copy too")

    -- Drawing: only what the palette knows is accepted. An unknown colour name
    -- must refuse out loud rather than draw a frame with no fill.
    local frame = { textures = {} }
    function frame:CreateTexture()
        local texture = {}
        function texture:SetColorTexture() end
        function texture:SetAllPoints() end
        function texture:ClearAllPoints() end
        function texture:SetPoint() end
        function texture:SetWidth() end
        function texture:SetHeight() end
        self.textures[#self.textures + 1] = texture
        return texture
    end

    T.eq(skin.Backdrop(frame, "panel", "line"), true, "the fill with a border was applied")
    T.eq(skin.Backdrop(frame, "no-such", "line"), false,
        "an unknown fill is rejected")
    T.eq(skin.Backdrop(frame, "panel", "no-such"), false,
        "an unknown border is rejected")
    T.eq(skin.Backdrop(nil, "panel"), false, "with no frame there is nothing to draw")

    T.eq(skin.Outline(frame, "umbraTest", frame, "line"), true,
        "the outline was built")
    T.eq(skin.Outline(frame, "", frame, "line"), false,
        "the outline needs a field name")

    local fontString = { color = nil }
    function fontString:SetTextColor(...) self.color = { ... } end
    T.eq(skin.Text(fontString, "text"), true, "the label was painted")
    T.eq(skin.Text(fontString, "no-such"), false,
        "an unknown label colour is rejected")
end

helpers.removeValidator()

    local ns, said = core()
    local handle, reason = ns.Api:RegisterModule(descriptor({
        name = "unchecked",
        options = { type = "group", name = "U", args = {} },
    }))

    T.eq(handle, nil, "a module with a section is not accepted")
    T.ok(type(reason) == "string"
        and reason:find("AceConfigRegistry", 1, true) ~= nil,
        "the missing library is named: " .. tostring(reason))
    T.eq(#said, 1, "the player was told once")

    -- A module with no section has nothing to validate and no reason to: it passes.
    T.ok(ns.Api:RegisterModule(descriptor({ name = "quiet" })) ~= nil,
        "a module with no section is accepted even without the library")

    helpers.installValidator()
end

T.suite("the core did not start")

do
    -- On an unsupported client the registration formerly succeeded and did so
    -- silently: the module went into the registry, was never enabled, got no
    -- settings and could not even say so. The module author would be looking
    -- for the mistake in their own code.
    local ns, said = core()
    ns.CoreStartupFailed = true

    local handle, reason = ns.Api:RegisterModule(descriptor({ name = "late" }))
    T.eq(handle, nil, "the registration is rejected")
    T.ok(type(reason) == "string" and reason:find("did not start", 1, true) ~= nil,
        "the reason is given: " .. tostring(reason))
    T.eq(#said, 1, "the player was told once")
    T.eq(ns.Registry:Get("late"), nil, "the module did not enter the registry")
end

T.suite("the module settings are isolated")

do
    local ns = core()

    local first  = ns.Api:RegisterModule(descriptor({ name = "first" }))
    local second = ns.Api:RegisterModule(descriptor({ name = "second" }))

    local a = first:GetSettings()
    local b = second:GetSettings()

    T.ok(type(a) == "table", "the first got its own table")
    T.ok(type(b) == "table", "the second got its own table")
    T.ok(a ~= b, "the tables are different")

    a.value = 1
    T.eq(b.value, nil, "a write by one is invisible to the other")
    T.eq(ns.Addon.db.profile.first.value, 1, "the write went into the core profile")
    T.eq(first:GetSettings(), a, "a repeated call gives the same table")

    -- There may be no database: the core did not start on an unsupported
    -- client. Then the settings are nil rather than an empty table a module
    -- would fill into nowhere and silently lose what it wrote.
    ns.Addon.db = nil
    T.eq(second:GetSettings(), nil, "with no database there are no settings")
end

T.suite("by substituting a name a module does not reach its neighbour")

do
    -- The former check asked GetSettings whether the table was the same after
    -- handle.name was substituted, and it was green -- but the hole was
    -- elsewhere. The name from the descriptor was read by the registry (whom to
    -- disable) and by the tree assembly (where to put the section), and a module
    -- that rewrote its name to its neighbour's and then failed disabled the neighbour instead of itself.
    --
    -- Both ends are checked: the write into the field does not go through at
    -- all, and even if it did, the one that failed is the one disabled.
    local ns, said = core()
    ns.Registry.report = function(text) said[#said + 1] = text end

    local victim = ns.Api:RegisterModule(descriptor({
        name = "victim",
        defaults = { mine = true },
        ApplySettings = function(self) self.applied = (self.applied or 0) + 1 end,
    }))
    local raiser = ns.Api:RegisterModule(descriptor({
        name = "raiser",
        ApplySettings = function(self)
            -- Exactly what an author does when "name" looked like a suitable
            -- field for a display name.
            self.name = "victim"
            error("failed after renaming")
        end,
    }))

    T.err(function() raiser.name = "victim" end,
        "a write into name is rejected from outside the module")

    ns.Registry:ApplyAll()

    T.eq(ns.Registry:IsFailed("raiser"), true, "the one that failed is disabled")
    T.eq(ns.Registry:IsFailed("victim"), false, "the neighbour is untouched")
    T.eq(#said, 1, "it was said once")
    T.ok(said[1]:find("raiser", 1, true) ~= nil,
        "the message names the culprit: " .. said[1])

    -- The neighbour stays in the settings tree and in the assembled defaults:
    -- both would be taken from it if the disabling went by the substituted
    -- name.
    T.eq(ns.Registry:CollectDefaults().victim.mine, true,
        "the neighbour defaults are assembled")
    T.eq(ns.Registry:CollectDefaults().raiser, nil,
        "the defaults of the failed one are not assembled")

    -- And the neighbour is still called while the failed one is not.
    ns.Registry:ApplyAll()
    T.eq(victim.applied, 2, "the neighbour applied the settings both times")
    T.eq(#said, 1, "there are no repeated messages")
end

T.suite("the storage sections")

do
    local ns = core()
    ns.Addon.db.global = {}

    local module = ns.Api:RegisterModule(descriptor({ name = "keeper" }))

    -- The profile is the default: the settings must switch along with it.
    local profile = module:GetSettings()
    T.eq(profile, module:GetSettings("profile"), "with no argument, the profile")
    T.eq(ns.Addon.db.profile.keeper, profile, "the table lies in the profile")

    -- The global section is a different lifetime: a list of items across every
    -- character must not be swapped by a change of skin.
    local global = module:GetSettings("global")
    T.ok(type(global) == "table", "the global section was handed out")
    T.ok(global ~= profile, "it is a different table")
    T.eq(ns.Addon.db.global.keeper, global, "and it lies in the global section")

    global.items = 1
    T.eq(profile.items, nil, "what was written into the global section does not leak into the profile")

    -- The character section (version 6): a third lifetime. A setting that must
    -- differ between alts cannot live in a shared profile -- the item database
    -- already got caught by that, where "record this character's bags" was
    -- switched off for everyone at once.
    ns.Addon.db.char = {}
    local own = module:GetSettings("char")
    T.ok(type(own) == "table", "the character section was handed out")
    T.ok(own ~= profile and own ~= global, "and it is a third table")
    T.eq(ns.Addon.db.char.keeper, own, "it lies in the character section")

    own.enabled = false
    T.eq(profile.enabled, nil, "what was written for the character does not leak into the profile")
    T.eq(global.enabled, nil, "nor into the global section")

    -- Logging in as another character: in AceDB that is a different table under db.char.
    ns.Addon.db.char = {}
    T.eq(module:GetSettings("char").enabled, nil,
        "another character has its own answer rather than someone else's")

    -- An unknown section name is not a silent profile. Silence would mean the
    -- module writes the item database into the profile and loses it on a switch.
    -- AceDB has realm and class sections while the contract does not: every
    -- section here is a promise forever.
    local none, why = module:GetSettings("realm")
    T.eq(none, nil, "an unknown section is not handed out")
    T.ok(type(why) == "string" and why:find("realm", 1, true) ~= nil,
        "and is named by name: " .. tostring(why))
end

T.suite("a module with no defaults leaves no rubbish in the database")

do
    -- AceDB clears out of SavedVariables whatever equals the declared default,
    -- an empty table included -- but only if it knows about that table. A
    -- module with no defaults got an empty table from GetSettings around the
    -- declaration, and it stayed in DarkenDB forever.
    local ns = core()

    local injected = {}
    function ns.InjectModuleDefaults(name, defaults, globals)
        injected[name] = { profile = defaults, global = globals }
        return true
    end

    ns.Api:RegisterModule(descriptor({ name = "bare" }))

    T.ok(type(injected.bare) == "table", "the defaults are declared even without defaults")
    T.ok(type(injected.bare.profile) == "table", "the profile section is declared")
    T.eq(next(injected.bare.profile), nil, "and it is empty")
    T.ok(type(injected.bare.global) == "table", "the global section is declared too")
end

T.suite("a late registration carries a module to a live core")

do
    -- A foreign module almost always arrives after the core has created the
    -- database and the settings tree: the game initialises the core on its own
    -- ADDON_LOADED, that is before it reads the files of a dependent addon.
    local ns = core()

    local injected, refreshed = {}, 0
    function ns.InjectModuleDefaults(name, defaults)
        injected[name] = defaults
        return true
    end
    function ns.RefreshOptions()
        refreshed = refreshed + 1
        return true
    end

    local defaults = { size = 2 }
    ns.Api:RegisterModule(descriptor({
        name = "late",
        defaults = defaults,
        options = { type = "group", name = "Late", args = {} },
    }))


    -- A module with no section does not touch the tree: a needless reassembly
    -- would redraw an open settings window for no reason at all.
    ns.Api:RegisterModule(descriptor({ name = "quiet", defaults = { a = 1 } }))
    T.eq(injected.quiet.a, 1, "its defaults are added anyway")
end

T.suite("a module arriving after the enabling is enabled at once")

do
    local ns = core()

    -- The core has already passed entering the world: the registry remembers that.
    ns.Registry:EnableAll()

    local calls = {}
    ns.Api:RegisterModule(descriptor({
        name = "afterLogin",
        OnEnable      = function() calls[#calls + 1] = "enable" end,
        ApplySettings = function() calls[#calls + 1] = "apply" end,
    }))

    T.eq(table.concat(calls, ","), "enable,apply",
        "first the enabling, then applying the settings: " .. table.concat(calls, ","))
end

do
    local ns = core()

    -- Before entering the world it is not enabled: the common pass will enable
    -- it, otherwise OnEnable would be called twice.
    local calls = 0
    ns.Api:RegisterModule(descriptor({
        name = "beforeLogin",
        OnEnable = function() calls = calls + 1 end,
    }))
    T.eq(calls, 0, "before the common enabling the module is not enabled")

    ns.Registry:EnableAll()
    T.eq(calls, 1, "the common pass enabled it exactly once")
end

T.suite("the standard application of the settings")

do
    local ns = core()

    local applied = 0
    local handle = ns.Api:RegisterModule(descriptor({
        name = "refresher",
        ApplySettings = function() applied = applied + 1 end,
    }))

    -- Refresh leads into the same ApplyAll as logging in and switching a
    -- profile: a module must have no application path of its own.
    handle:Refresh()
    T.eq(applied, 1, "Refresh applied the settings")
end

T.suite("the database rejected the module defaults")

do
    -- The module is registered but it will have no settings: it would be
    -- reading nothing and would behave inexplicably. Such a module is disabled
    -- by the same road as a failed one, and with the same single message.
    local ns, said = core()
    ns.Registry.report = function(text) said[#said + 1] = text end

    function ns.InjectModuleDefaults()
        return false, "AceDB: the defaults were rejected"
    end

    local handle, reason = ns.Api:RegisterModule(descriptor({
        name = "rejected",
        defaults = { a = 1 },
    }))

    T.eq(handle, nil, "the registration failed")
    T.ok(type(reason) == "string" and reason:find("AceDB", 1, true) ~= nil,
        "the reason is given: " .. tostring(reason))
    T.eq(ns.Registry:IsFailed("rejected"), true, "the module is disabled")
    T.eq(#said, 1, "it was said once")
end

T.suite("the targeted application of the settings")

do
    -- Refresh goes over the whole addon, and for the nameplate engine, which
    -- redraws itself for every unit that appears, that is the wrong price: it
    -- would create an application path of its own -- exactly what the contract forbids.
    local ns = core()

    local mine, other = 0, 0
    local module = ns.Api:RegisterModule(descriptor({
        name = "one",
        ApplySettings = function() mine = mine + 1 end,
    }))
    ns.Api:RegisterModule(descriptor({
        name = "two",
        ApplySettings = function() other = other + 1 end,
    }))

    module:Apply()
    T.eq(mine, 1, "our own settings were applied")
    T.eq(other, 0, "the neighbour is untouched")

    module:Refresh()
    T.eq(mine, 2, "the common path applied ours too")
    T.eq(other, 1, "and the neighbour's")
end

T.suite("Refresh does not recurse")

do
    -- The contract tells you to call Refresh from a set handler, and a module's
    -- set handler may well turn out to be called from its own ApplySettings.
    -- Without a re-entry guard that is fifteen hundred turns and a stack
    -- overflow -- a yellow error with no name of the culprit.
    local ns = core()

    local calls = 0
    local module
    module = ns.Api:RegisterModule(descriptor({
        name = "looper",
        ApplySettings = function(self)
            calls = calls + 1
            self:Refresh()
            self:Apply()
        end,
    }))

    T.eq(module:Refresh(), true, "the application went through")
    T.eq(calls, 1, "ApplySettings was called exactly once")
    T.eq(ns.Registry:IsFailed("looper"), false, "the module is intact")

    -- The guard is lifted on exit: the next application goes through again.
    T.eq(module:Refresh(), true, "the next application is not blocked")
    T.eq(calls, 2, "and it took place")
end

T.suite("a module learns that it was switched off")

do
    -- The core stopped calling a failed module, but the module kept calling
    -- outward: a hook on a foreign frame, a frame subscription, a timer.
    -- Telling it is the only way to stop that before a reload.
    local ns, said = core()
    ns.Registry.report = function(text) said[#said + 1] = text end

    local told, alive, boom = 0, true, false
    local module = ns.Api:RegisterModule(descriptor({
        name = "aware",
        OnEnable = function() end,
        OnDisable = function(self)
            told = told + 1
            alive = self:IsEnabled()
        end,
        ApplySettings = function()
            if boom then error("broken") end
        end,
    }))

    T.eq(module:IsEnabled(), false, "before the common enabling the module does not work")
    ns.Registry:EnableAll()
    T.eq(module:IsEnabled(), true, "after the enabling it works")

    boom = true
    ns.Registry:ApplyAll()
    T.eq(told, 1, "the disabling was reported once")
    T.eq(alive, false, "and by that moment the module already counts as switched off")
    T.eq(module:IsEnabled(), false, "from then on it is off")

    -- There is no second disabling, so there is no second notification.
    ns.Registry:ApplyAll()
    T.eq(told, 1, "there is no repeated notification")
end

do
    -- A failure inside OnDisable is swallowed: the message about the first
    -- breakage has already been sent, and a second one beside it would only confuse.
    local ns, said = core()
    ns.Registry.report = function(text) said[#said + 1] = text end

    ns.Api:RegisterModule(descriptor({
        name = "rude",
        OnDisable = function() error("and on the way out too") end,
        ApplySettings = function() error("broken") end,
    }))

    ns.Registry:EnableAll()
    T.eq(ns.Registry:IsFailed("rude"), true, "the module is disabled")
    T.eq(#said, 1, "there is still one message")
end

T.suite("a module shows its own object to its neighbours")

do
    -- The showcase was one-way: the core showed, the modules looked. For three
    -- modules in the catalogue that is not enough -- they own frames themselves.
    local ns = core()

    local pouch = ns.Api:RegisterModule(descriptor({ name = "pouch" }))
    local plugin = ns.Api:RegisterModule(descriptor({ name = "plugin" }))

    local seen = {}
    plugin:OnRepaint("pouch.main", function(frame, key)
        seen[#seen + 1] = tostring(key)
    end)

    local frame = { id = "bag" }
    T.eq(pouch:Publish("pouch.main", frame), true, "the object is on display")
    T.eq(plugin:GetFrame("pouch.main"), frame, "the neighbour sees it")
    T.eq(#seen, 1, "the subscriber was notified")

    -- The key must start with the module name, otherwise the very first module
    -- would declare itself "castbar.player" and swap the core object for its neighbours.
    T.eq(pouch:Publish("castbar.player", frame), false, "a foreign key is rejected")
    T.eq(pouch:Publish("pouchandmore.main", frame), false,
        "a match on the start of the string does not count")
    T.eq(pouch:Publish("pouch", frame), true, "the whole module name is an own key")
    T.eq(pouch:Publish(5, frame), false, "a non-string is rejected")
    T.eq(ns.Frames.Get("castbar.player"), nil, "the core object was not swapped")
end

T.suite("a family of modules: registration from a foreign OnEnable")

do
    -- Exactly the shape that is in the queue: a bags core with plug-in modules
    -- on top of it that it registers itself. The "the enabling happened" flag
    -- was raised from the first line of EnableAll, so a newcomer was enabled
    -- immediately through EnableOne, and the live walk of the list reached it
    -- afterwards and called OnEnable a second time: a double subscription to
    -- the events, double frames.
    local ns = core()

    local enabled = {}
    local function count(name) return enabled[name] or 0 end

    ns.Api:RegisterModule(descriptor({
        name = "bagscore",
        OnEnable = function()
            enabled.bagscore = count("bagscore") + 1
            ns.Api:RegisterModule(descriptor({
                name = "bagsplugin",
                OnEnable = function()
                    enabled.bagsplugin = count("bagsplugin") + 1
                end,
            }))
        end,
    }))
    ns.Api:RegisterModule(descriptor({
        name = "after",
        OnEnable = function() enabled.after = count("after") + 1 end,
    }))

    ns.Registry:EnableAll()

    T.eq(count("bagscore"), 1, "the bags core was enabled once")
    T.eq(count("bagsplugin"), 1,
        "the one plugged in from its OnEnable was enabled once rather than twice")
    T.eq(count("after"), 1, "the one standing next in the list was enabled once")

    -- The newcomer is enabled after all rather than deferred to a reload: that
    -- was the whole point of the immediate enabling.
    T.ok(ns.Registry:Get("bagsplugin") ~= nil, "it is in the registry")
    T.eq(ns.Registry:IsEnabled(ns.Registry:Get("bagsplugin")), true,
        "and it works")
end


T.suite("the contract document does not diverge from the code")

-- docs/module-api.md is the only page an outside module author reads before
-- writing their first line. A divergence of that page from the code costs
-- more than a mistake in the code: the code refuses out loud while the
-- document lies silently, and precisely to the person we cannot reach by editing our own file.
--
-- Formerly this thought was written as a comment above the snapshot of the
-- reserved fields -- and it is exactly what was broken: the names in the code
-- grew while the box in the document stayed as it was. A comment nobody looks at is not a defence.
do
    local ns = core()

    local doc = io.open("docs/module-api.md", "r")
    T.ok(doc ~= nil, "the contract document was opened")

    local text = doc and doc:read("*a") or ""
    if doc then doc:close() end

    -- The box of reserved names: the first fenced block after the section
    -- heading.
    local from = text:find("### Reserved fields on the handle", 1, true)
    T.ok(from ~= nil, "the section of reserved fields exists in the document")

    local block = from and text:match("```\n(.-)```", from) or ""
    local documented, listed = {}, {}
    for word in block:gmatch("[%w_]+") do
        if not documented[word] then
            documented[word] = true
            listed[#listed + 1] = word
        end
    end
    T.ok(#listed > 0, "the names in the box were read: " .. #listed)

    -- Both sides of the comparison: a core name not named in the document, and
    -- a name in the document with nothing behind it in the code.
    local undocumented = {}
    for field in pairs(ns.RESERVED_HANDLE_FIELDS) do
        if not documented[field] then undocumented[#undocumented + 1] = field end
    end
    table.sort(undocumented)
    T.eq(#undocumented, 0, "the document names every core name, not named: "
        .. table.concat(undocumented, " | "))

    local invented = {}
    for i = 1, #listed do
        if not ns.RESERVED_HANDLE_FIELDS[listed[i]] then
            invented[#invented + 1] = listed[i]
        end
    end
    T.eq(#invented, 0, "the document invents no core names: "
        .. table.concat(invented, " | "))

    -- The version a name appeared in is part of the document too: the author
    -- decides by it which version to declare. A row of the method table must
    -- carry the same version as the map in the code.
    local wrongVersion = {}
    for field, version in pairs(ns.HANDLE_FIELD_VERSIONS) do
        if version > 1 then
            local row = text:match("\n(|%s*`handle:" .. field .. "[^\n]*)")
            local said = row and row:match("%(version (%d+)%)")
            if tonumber(said) ~= version then
                wrongVersion[#wrongVersion + 1] = field .. ": the document says "
                    .. tostring(said) .. ", the code says " .. tostring(version)
            end
        end
    end
    table.sort(wrongVersion)
    T.eq(#wrongVersion, 0, "the method versions in the document are the same: "
        .. table.concat(wrongVersion, " | "))

    -- The headline "Contract version: **N**" is the first fact a module author
    -- reads, and the only one they decide by which version to declare. Having
    -- fallen behind the code, it silently hides everything the core can already
    -- do: nobody will write api = 15 while the page says 14.
    local headline = text:match("\nContract version:%s*%*%*(%d+)%*%*")
    T.ok(headline ~= nil, "the contract version line was found in the document")
    T.eq(tonumber(headline), ns.Api.API_VERSION,
        "the document headline carries the core version")

    -- And that version has a row of its own in the history table: a version
    -- with no description is the same silence, only one line lower.
    local row = text:match("\n(|%s*" .. tostring(ns.Api.API_VERSION) .. "%s*|[^\n]*)")
    T.ok(row ~= nil, "the current version has a row in the history table")
end

helpers.removeValidator()
