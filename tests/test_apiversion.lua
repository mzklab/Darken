local helpers = require("helpers")

helpers.installValidator()

-- The contract's growth: how version 5 adds a method and does not break a module of version 1.
--
-- The contract's promise is written as a number: API_MIN_VERSION = 1 means "a
-- module written for the first version works with this core as it worked".
-- One thing stood in the way of keeping that promise: every new method of the
-- descriptor became a name the core took away from everybody at once. A module
-- of version 1 that hung its own Localize on the descriptor (and the contract
-- itself tells one to gather one's state there) fell over with a yellow Lua
-- error in the body of somebody else's file after the core was updated. The
-- defect is not in six names — the defect is that every next version would take new ones.
--
-- The rule is now this: the core's names are locked by the version the module
-- declared. A module gets the whole surface (anything the core can do may be
-- called), but the core forbids writing only those names that existed in its
-- version. A name that appeared later than the declared version stays the
-- module's field: writing it simply shadows a method the module did not know about.
--
-- The check below does not describe today's set of names by hand. It adds a
-- future version's name into the map of versions and demands that an old
-- module survive it: version 5 becomes a check rather than a hope.

--- The core as the public layer sees it.
local function core()
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Frames.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Combat.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/Api.lua", ns)

    local said = {}
    ns.Registry.report = function(text) said[#said + 1] = text end
    ns.Addon = {
        db = { profile = {}, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }

    return ns, said
end

--- Write a field onto the descriptor.
-- @return boolean whether the write went through
-- @return string|nil the refusal's text
local function assign(handle, key, value)
    local ok, err = pcall(function() handle[key] = value end)
    return ok, err
end

--- Read a file of the core's whole.
-- @param path string
-- @return string
local function read(path)
    local file = io.open(path, "r")
    if not file then error(path .. " did not open", 2) end
    local text = file:read("*a")
    file:close()
    return text
end

--- The fields buildHandle carries from the descriptor onto the surface.
--
-- Asked of Core/Api.lua itself rather than rewritten here: a list of names
-- typed by hand would fall behind the core exactly as quietly as the check it
-- is needed for used to fall behind.
-- @return table an array of names
local function copiedFields()
    local src = read("Core/Api.lua")
    local block = src:match("local fields = {(.-)\n    }")
    if not block then error("the fields table was not found in Core/Api.lua", 2) end

    local out = { "name" }  -- name is carried through a local variable
    for key in block:gmatch("([%w_]+)%s*=%s*descriptor%.") do
        out[#out + 1] = key
    end
    table.sort(out)
    return out
end

local COPIED_FIELDS = copiedFields()
T.ok(#COPIED_FIELDS >= 8, "the descriptor's fields were read from the core: " .. #COPIED_FIELDS)

-- A value for every carried field. A name that is not here is a new field of
-- the descriptor: the check is obliged to speak of it rather than pass by.
local FIELD_VALUES = {
    name          = "surface",
    api           = 1,
    defaults      = { sample = true },
    globals       = { sample = true },
    options       = { type = "group", name = "Surface", args = {} },
    OnEnable      = function() end,
    OnDisable     = function() end,
    ApplySettings = function() end,
}

--- A descriptor in which every carried field is filled in.
-- @param name string the module's name
-- @param api number the declared contract version
-- @return table
local function fullDescriptor(name, api)
    local descriptor = {}
    for i = 1, #COPIED_FIELDS do
        local key = COPIED_FIELDS[i]
        local value = FIELD_VALUES[key]
        if value == nil then
            error("a new field of the descriptor, " .. key
                .. ": add a value for it in FIELD_VALUES", 2)
        end
        descriptor[key] = value
    end
    descriptor.name = name
    descriptor.api = api
    return descriptor
end

T.suite("A descriptor's version locks only its own names")

do
    local ns = core()

    T.ok(type(ns.HANDLE_FIELD_VERSIONS) == "table",
        "the map of \"name -> the version it appeared in\" is exposed by the core")
    T.ok(type(ns.ReservedHandleFields) == "function",
        "the set of forbidden names is asked for by version")

    -- The map is obliged to cover the descriptor's whole surface. A method
    -- added with no record of a version would be locked for nobody — and the
    -- very first module would shadow it for itself silently.
    --
    -- The descriptor here is filled in entirely, and that is a condition of the
    -- check rather than tidiness. The surface is walked through pairs, and
    -- pairs does not yield keys with a nil value: a descriptor of name and api
    -- alone left six optional fields empty, and the walk did not see exactly
    -- the group the map was created for ("the optional fields are absent from
    -- most modules" — Core/Api.lua). A check that looks only at the non-empty
    -- is green even when a new optional field was forgotten and left
    -- undeclared.
    local handle = ns.Api:RegisterModule(fullDescriptor("surface", 1))
    local fields = getmetatable(handle).__index

    local undeclared = {}
    for key in pairs(fields) do
        if ns.HANDLE_FIELD_VERSIONS[key] == nil then
            undeclared[#undeclared + 1] = key
        end
    end
    T.eq(#undeclared, 0, "a version is declared for every name of the surface: "
        .. table.concat(undeclared, " | "))

    -- And that walk really did see every field buildHandle carries from the
    -- descriptor. The list of fields was asked of Core/Api.lua itself:
    -- rewritten here by hand it would fall behind the core silently — by the
    -- same means the walk itself stayed silent.
    local unseen = {}
    for i = 1, #COPIED_FIELDS do
        if fields[COPIED_FIELDS[i]] == nil then
            unseen[#unseen + 1] = COPIED_FIELDS[i]
        end
    end
    T.eq(#unseen, 0, "the walk saw every field of the descriptor rather than the non-empty ones alone: "
        .. table.concat(unseen, " | "))

    -- A name's version is a number within the bounds the contract declares: a
    -- name from a version the core does not give would lock the modules for nothing.
    local outOfRange = {}
    for key, version in pairs(ns.HANDLE_FIELD_VERSIONS) do
        if type(version) ~= "number" or version < ns.Api.API_MIN_VERSION
            or version > ns.Api.API_VERSION then
            outOfRange[#outOfRange + 1] = key .. " -> " .. tostring(version)
        end
    end
    T.eq(#outOfRange, 0, "the names' versions lie inside the contract: "
        .. table.concat(outOfRange, " | "))
end

T.suite("The names with a meaning for the core: either the map knows them or the refusal is said aloud")

-- The descriptor's surface is not the only place where a field's name means
-- something to the core. The registry reads fields straight off the module's
-- table: recoverable decides whether to offer the "Try again" button,
-- standDown whether a subsystem was stood aside. Both names lie outside the
-- map of versions, and staying silent about that would be the same defect the map was created for.
--
-- The check asks the core's own files which names they read off a module's
-- table and demands that something be said aloud about each: either it is
-- declared in the map of versions or it is written down below together with
-- the reason it is not there. A new such name goes red here and nowhere else.
do
    local ns = core()

    -- The legitimate exceptions: a name with a meaning for the core that is
    -- deliberately absent from the map. The reason is obliged to be stated rather than assumed.
    local EXEMPT = {
        -- An agreement of the core with its own subsystems rather than with
        -- other people's modules. The public layer deliberately does not carry
        -- it: buildHandle does not copy the descriptor's recoverable, and
        -- another addon's module is therefore always counted as recoverable —
        -- "at worst it will fall over once more and switch itself off by the
        -- same path". The decision is written down in docs/known-issues.md and
        -- checked by tests/test_modulefailure.lua. Taking the name into the map
        -- would mean taking it away from the modules of the declared version,
        -- that is, changing the contract for a field that does not belong to it.
        recoverable = "belongs to the core's subsystems rather than to the modules' contract "
            .. "(docs/known-issues.md, test_modulefailure.lua)",
        -- The marker of a subsystem being stood aside. It is set and cleared by
        -- the core (ns.StandDownSubsystem, ns.ResumeSubsystem) and read by the
        -- core's subsystems at every entry of theirs. It is not addressed to a
        -- module: a module stands another subsystem aside rather than itself,
        -- and does it by the Replaces method, which is in the map.
        standDown = "a marker of a core subsystem, set by the core "
            .. "(ns.StandDownSubsystem)",
    }

    --- The names a file of the core's reads off a module's table.
    -- An access to the local variable module is looked for — that is how the
    -- registry and the public layer name a registered table.
    -- @param path string
    -- @param out table the set of names
    local function collect(path, out)
        for key in read(path):gmatch("module%.([%w_]+)") do out[key] = true end
    end

    local names = {}
    collect("Core/Registry.lua", names)
    collect("Core/Api.lua", names)

    local count = 0
    for _ in pairs(names) do count = count + 1 end
    T.ok(count >= 4, "the names off a module's table were read from the core: " .. count)

    local silent = {}
    for key in pairs(names) do
        if ns.HANDLE_FIELD_VERSIONS[key] == nil and EXEMPT[key] == nil then
            silent[#silent + 1] = key
        end
    end
    table.sort(silent)
    T.eq(#silent, 0, "something is said aloud about every name with a meaning for the core: "
        .. table.concat(silent, " | "))

    -- An exception that has stopped being needed is a check quietly removed:
    -- the name entered the map while the record still permits it not to be there.
    local stale = {}
    for key in pairs(EXEMPT) do
        if ns.HANDLE_FIELD_VERSIONS[key] ~= nil or names[key] == nil then
            stale[#stale + 1] = key
        end
    end
    table.sort(stale)
    T.eq(#stale, 0, "the exceptions did not outlive their occasion: "
        .. table.concat(stale, " | "))
end

T.suite("A module of version 1 survives the names that appeared later")

do
    local ns, said = core()

    -- The names that did not exist in the first version: exactly the ones a
    -- module of version 1 could have created for itself, not knowing about the core.
    local later = {}
    for key, version in pairs(ns.HANDLE_FIELD_VERSIONS) do
        if version > 1 then later[#later + 1] = key end
    end
    table.sort(later)
    T.ok(#later > 0, "the contract has grown since the first version: " .. #later .. " names")

    local old = ns.Api:RegisterModule({ name = "oldtimer", api = 1 })
    T.ok(old ~= nil, "a module for version 1 registers")

    local refused = {}
    for i = 1, #later do
        local ok = assign(old, later[i], function() return later[i] end)
        if not ok then refused[#refused + 1] = later[i] end
    end
    T.eq(#refused, 0,
        "a module of version 1 was refused not one name that appeared later: "
        .. table.concat(refused, " | "))

    -- A written name belongs to the module: it gets its own function rather
    -- than a method of the core's it did not know about.
    if type(old.Localize) == "function" then
        T.eq(old:Localize(), "Localize", "the module calls its own function")
    end

    -- The neighbour meanwhile gets the core's method untouched: the write lives
    -- on its own descriptor rather than in a shared table of fields.
    local fresh = ns.Api:RegisterModule({ name = "newcomer", api = 4 })
    T.eq(fresh:Localize("Bags"), "Bags", "the neighbour's Localize stayed the core's")

    -- The first version's names are locked for a module of the first version
    -- too: replacing name or ApplySettings is the very breakage the door was put up for.
    local okName, nameErr = assign(old, "name", "victim")
    T.eq(okName, false, "a module of version 1 must not write name")
    T.ok(type(nameErr) == "string" and nameErr:find("name", 1, true) ~= nil,
        "the refusal names the name itself")
    T.eq((assign(old, "GetSettings", function() end)), false,
        "a module of version 1 must not write GetSettings")
    T.eq((assign(old, "ApplySettings", function() end)), false,
        "a module of version 1 must not write ApplySettings")

    -- A field of its own that matches no name of the core's is always accepted.
    T.eq((assign(old, "title", "Old Timer")), true, "a field of its own is accepted")
    T.eq(old.title, "Old Timer", "and is read back")

    T.eq(#said, 0, "the core did not complain: " .. table.concat(said, " | "))
end

T.suite("A module of the latest version is locked entirely")

do
    local ns = core()
    local new = ns.Api:RegisterModule({ name = "current", api = ns.Api.API_VERSION })

    local allowed = {}
    for key in pairs(ns.HANDLE_FIELD_VERSIONS) do
        if (assign(new, key, function() end)) then allowed[#allowed + 1] = key end
    end
    table.sort(allowed)
    T.eq(#allowed, 0,
        "not one name of the core's was given to a module of the current version: "
        .. table.concat(allowed, " | "))
end

T.suite("Version 5 adds a method and breaks nobody")

do
    local ns = core()

    local future = ns.Api.API_VERSION + 1

    -- This is what the contract's next version looks like: one new name in the
    -- map. The core is not touched in the process — the rule is checked rather than a future method.
    ns.HANDLE_FIELD_VERSIONS.Telemetry = future

    local reserved = ns.ReservedHandleFields(1)
    T.eq(reserved.Telemetry, nil, "version 5's name is not locked for version 1")
    T.eq(ns.ReservedHandleFields(ns.Api.API_VERSION).Telemetry, nil,
        "nor for a module written before it")
    T.eq(ns.ReservedHandleFields(future).Telemetry, true,
        "while for whoever declares version 5 the name belongs to the core")

    -- Every module alive today — that is, a module of any version the core
    -- accepts — is obliged to survive the new name.
    for version = ns.Api.API_MIN_VERSION, ns.Api.API_VERSION do
        local handle = ns.Api:RegisterModule({
            name = "survivor" .. version,
            api  = version,
        })
        T.ok(handle ~= nil, "a module of version " .. version .. " was registered")
        T.eq((assign(handle, "Telemetry", function() end)), true,
            "version " .. version .. " survives a name added in version "
            .. future)
    end

    -- Declaring a future version is still not allowed: the surface's growth
    -- does not cancel the negotiation about the version.
    local handle, reason = ns.Api:RegisterModule({ name = "tooNew", api = future })
    T.eq(handle, nil, "a module of a future version does not register")
    T.ok(type(reason) == "string" and reason:find("update Darken", 1, true),
        "and the refusal says it is the core that has to be updated")

    ns.HANDLE_FIELD_VERSIONS.Telemetry = nil
end

helpers.removeValidator()
