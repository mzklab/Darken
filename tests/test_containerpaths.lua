local helpers = require("helpers")

-- The names of the container functions moved into the compatibility layer, and
-- everything the move was made for is checked here.
--
-- WHY IT WAS NEEDED. Five modules — the bag window, the item database, the
-- item level, the info panel and the pet food tooltip — each decided for
-- itself which of two spellings this client reads the bags by: the C_Container
-- table or the globals. Five forks about one difference between clients are
-- five second lists of other people's names, and they are dangerous for the
-- same reason as all the others: having diverged from the client, such a list
-- does not complain but silently stops reading anything.
--
-- WHAT EXACTLY DIFFERS and what does not. The container functions differ: the
-- early line keeps them as globals, the later one gathered them into a table
-- and removed the globals. GetItemInfo and its neighbours do not differ — the
-- global exists on all three served clients — and that is why they are not in
-- the layer and will not be: the layer is about the differences between our clients rather than a directory of the game's API.
--
-- WHAT IS CHECKED HERE:
--   * a client with the new spelling only, with the old one only, and with neither;
--   * the difference in signatures: the two spellings of
--     GetContainerItemInfo answer differently, and calling "the wrong one" is not allowed;
--   * reading a bag does not resolve a name per slot.

T.suite("the containers: the layer declares both spellings")

local layer = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", layer)
local Compat = layer.Compat

local FLAVORS = { "vanilla", "tbc", "mists" }

local GROUPS = {
    "container-slots", "container-item", "container-free-slots",
    "container-item-link", "container-pickup",
}

do
    for i = 1, #FLAVORS do
        for j = 1, #GROUPS do
            local names = Compat.GetFrameNames(FLAVORS[i], GROUPS[j])
            T.eq(#names, 2, FLAVORS[i] .. ": " .. GROUPS[j]
                .. " is declared with two spellings")
            T.ok(names[1]:find("^C_Container%."),
                GROUPS[j] .. ": the table spelling comes first")
            T.ok(not names[2]:find("%."),
                GROUPS[j] .. ": the global one second")
        end
    end

    -- The group is declared for all three clients rather than for the ones the
    -- author thinks hold the table: a guess about a client IS the version check
    -- the layer saves us from.
    for j = 1, #GROUPS do
        for i = 1, #FLAVORS do
            T.eq(Compat.HasGroup(FLAVORS[i], GROUPS[j]), true,
                FLAVORS[i] .. ": " .. GROUPS[j] .. " was not skipped")
        end
    end
end

T.suite("the containers: the answer's shape is declared beside the path")

do
    T.eq(Compat.PathShape("C_Container.GetContainerItemInfo"), "record",
        "the table spelling answers with a record")
    T.eq(Compat.PathShape("GetContainerItemInfo"), "values",
        "the global one with a flat list of values")
    T.eq(Compat.PathShape("GetContainerNumSlots"), "plain",
        "for the number of slots there is no difference")
    T.eq(Compat.PathShape(nil), "plain", "and for nonsense the answer is the same")

    T.eq(Compat.GroupMixesShapes("vanilla", "container-item"), true,
        "container-item is a group with differing signatures")
    T.eq(Compat.GroupMixesShapes("vanilla", "container-slots"), false,
        "while container-slots answers identically by both spellings")
end

T.suite("the containers: three clients and not one build number")

-- Three invented clients. The decision is made by what the client holds rather
-- than by the build number, and that is visible here: the dictionary IS the whole client.
local RECORD = { itemID = 6948, itemName = "Hearthstone", stackCount = 1,
    quality = 4, iconFileID = 134414, isLocked = false,
    hyperlink = "|Hitem:6948|h[Hearthstone]|h" }

local function modernClient()
    return {
        C_Container = {
            GetContainerNumSlots = function(id) return id == 0 and 2 or 0 end,
            GetContainerNumFreeSlots = function(id) return 1, 0 end,
            GetContainerItemInfo = function(id, slot)
                if id == 0 and slot == 1 then return RECORD end
                return nil
            end,
            GetContainerItemLink = function() return RECORD.hyperlink end,
            PickupContainerItem = function() end,
        },
        GetItemInfo = function()
            return "Hearthstone", nil, nil, 1, nil, "Miscellaneous", "Junk"
        end,
    }
end

local function classicClient()
    return {
        GetContainerNumSlots = function(id) return id == 0 and 2 or 0 end,
        GetContainerNumFreeSlots = function(id) return 1, 0 end,
        GetContainerItemInfo = function(id, slot)
            if id == 0 and slot == 1 then
                return RECORD.iconFileID, RECORD.stackCount, false,
                    RECORD.quality, false, false, RECORD.hyperlink,
                    false, false, RECORD.itemID
            end
            return nil
        end,
        GetContainerItemLink = function() return RECORD.hyperlink end,
        PickupContainerItem = function() end,
        GetItemInfo = function()
            return "Hearthstone", nil, nil, 1, nil, "Miscellaneous", "Junk"
        end,
    }
end

local function barrenClient()
    return { GetItemInfo = function() return nil end }
end

do
    local modern = Compat.FindFunction(modernClient(), "vanilla",
        "container-slots")
    T.eq(type(modern), "function", "the new spelling was found")
    T.eq(select(3, Compat.FindFunction(modernClient(), "vanilla",
        "container-slots")), "C_Container.GetContainerNumSlots",
        "and named by its full path")

    local classic, shape, path = Compat.FindFunction(classicClient(),
        "vanilla", "container-slots")
    T.eq(type(classic), "function", "the old spelling was found")
    T.eq(path, "GetContainerNumSlots", "and named as a global")
    T.eq(shape, "plain", "its answer shape is the common one")

    T.eq(Compat.FindFunction(barrenClient(), "vanilla", "container-slots"),
        nil, "a client with neither spelling returns nothing rather than an error")

    -- A non-function of the same name does not pass for a function: anything
    -- at all may lie at a group's path, and the kind is asked about here.
    T.eq(Compat.FindFunction({ GetContainerNumSlots = 17 }, "vanilla",
        "container-slots"), nil, "a number does not count as a function")
end

T.suite("the containers: the shape is asked for rather than announced")

do
    -- The main guard: for a group whose two spellings answer differently, a
    -- question with no word about the shape gives nothing. Otherwise "calling
    -- the wrong one" would stay possible and silent.
    T.eq(Compat.FindFunction(modernClient(), "vanilla", "container-item"),
        nil, "with no word about the shape a mixed group stays silent")

    local record, shape = Compat.FindFunction(modernClient(), "vanilla",
        "container-item", "record")
    T.eq(type(record), "function", "the record was asked for and received")
    T.eq(shape, "record", "and the shape is named")
    T.eq(Compat.FindFunction(modernClient(), "vanilla", "container-item",
        "values"), nil,
        "while this client has no flat list at all")

    local values = Compat.FindFunction(classicClient(), "vanilla",
        "container-item", "values")
    T.eq(type(values), "function", "on the old client it is the other way round")
    T.eq(Compat.FindFunction(classicClient(), "vanilla", "container-item",
        "record"), nil, "and it does not return a record")

    -- The signatures really do differ, and that is visible in the answers themselves.
    T.eq(type(record(0, 1)), "table", "the new spelling returns a table")
    local icon, count = values(0, 1)
    T.eq(icon, RECORD.iconFileID, "the old one returns the values in order")
    T.eq(count, RECORD.stackCount, "and the second of them is the number in the stack")
end

T.suite("the containers: the core's door stays silent before the client is determined")

do
    -- The same caveat as GetFrameNames': the game's functions have to be
    -- resolved in OnEnable rather than in a file's body. The door answers with
    -- nothing rather than by failing: an exception would be raised out of another addon's file.
    local core = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", core)
    helpers.loadAddonFile("Core/Registry.lua", core)
    helpers.loadAddonFile("Core/Defaults.lua", core)
    helpers.loadAddonFile("Core/Locale.lua", core)
    helpers.loadAddonFile("Core/Frames.lua", core)
    helpers.loadAddonFile("Core/Events.lua", core)
    helpers.loadAddonFile("Core/Combat.lua", core)
    helpers.loadAddonFile("Core/Casefold.lua", core)
    helpers.loadAddonFile("Core/Api.lua", core)

    -- The client is forgotten deliberately. The layer determines the build
    -- itself, at read time (Core/Compat.lua, the end of the file): the addon's
    -- parts are read before ADDON_LOADED and ask it right there. What is
    -- checked here is something else — the door's answer while the build is
    -- NOT known — and that ignorance has to be arranged rather than hoped for from a stand-in client.
    core.flavor = nil

    T.eq(core.Api:GetGameFunction("container-slots"), nil,
        "before the client is determined there is no answer")

    core.flavor = "vanilla"

    -- A clean table: the group has two spellings, and the later one
    -- (C_Container), if it was left in the globals by a neighbouring set of
    -- checks, would be found first. What is checked here is the early one, and
    -- the client is obliged to be an early one entirely.
    local savedTable = _G.C_Container
    _G.C_Container = nil

    local saved = _G.GetContainerNumSlots
    _G.GetContainerNumSlots = function() return 16 end

    local fn, shape, path = core.Api:GetGameFunction("container-slots")
    T.eq(type(fn), "function", "after the client is determined the function arrives")
    T.eq(shape, "plain", "together with the answer's shape")
    T.eq(path, "GetContainerNumSlots", "and the path it was found by")

    T.eq(core.Api:GetGameFunction("container-item"), nil,
        "and through the public door a mixed group with no word stays silent")
    T.eq(core.Api:GetGameFunction(""), nil, "an empty group name is not a group")

    _G.GetContainerNumSlots = saved
    _G.C_Container = savedTable
end
T.suite("the containers: the pet food tooltip on three clients")


T.suite("the containers: the bags cell in the info panel")

do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Features/InfoPanel/Sources.lua", ns)

    local modern = modernClient()
    modern.NUM_BAG_SLOTS = 0
    local free, total = ns.Sources.Environment(modern,
        helpers.gameDoor(modern)).BagSpace()
    T.eq(total, 2, "the new spelling: slots in all")
    T.eq(free, 1, "and free ones")

    local classic = classicClient()
    classic.NUM_BAG_SLOTS = 0
    local freeOld, totalOld = ns.Sources.Environment(classic,
        helpers.gameDoor(classic)).BagSpace()
    T.eq(totalOld, total, "the old spelling answers the same")
    T.eq(freeOld, free, "and with as many free ones")

    local barren = barrenClient()
    barren.NUM_BAG_SLOTS = 0
    local nothingFree, nothingTotal = ns.Sources.Environment(barren,
        helpers.gameDoor(barren)).BagSpace()
    T.eq(nothingTotal, nil, "with neither spelling the cell stays silent")
    T.eq(nothingFree, nil, "with a dash rather than a zero: a zero would mean \"no room\"")
end

-- The item level is not here, and that is not an omission. Its file registers
-- itself in the core from its first line and is not read on its own at all, so
-- its reading of a link in a bag slot (the "container-item-link" group) is
-- checked where the core is the real one: tests/test_itemlevel.lua brings up a
-- client that has only one of the two spellings, and the number over the item in the bag appears.

T.suite("the containers: the report answers about an empty group")

do
    -- The only way the author will ever learn that a client reads the bags by a
    -- third means. The verdict here is "a loss" rather than "there is nothing
    -- to judge by": the bags exist on every served client, and an empty group
    -- means a mistake of ours rather than a truth about the client.
    local report = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", report)
    helpers.loadAddonFile("Core/Report.lua", report)

    local built = report.Report.Build("vanilla", barrenClient(), {},
        report.Compat)

    for i = 1, #GROUPS do
        local entry = built.groups[GROUPS[i]]
        T.ok(entry ~= nil, GROUPS[i] .. ": the group is named in the report")
        if entry then
            T.eq(entry.verdict, report.Report.MISSING,
                GROUPS[i] .. ": an empty group is named as a loss")
            T.eq(entry.later, nil,
                GROUPS[i] .. ": and is not softened with \"there is nothing to judge by\"")
        end
    end

    local whole = report.Report.Build("vanilla", modernClient(), {},
        report.Compat)
    for i = 1, #GROUPS do
        T.eq(whole.groups[GROUPS[i]].verdict, report.Report.OK,
            GROUPS[i] .. ": one spelling found is enough for \"intact\"")
    end

    -- The table spellings stand in the watch list by name: the probe walks the
    -- dictionary of globals and will never see a field inside C_Container, so
    -- the report can answer about them.
    local watch = report.Compat.Watchlist()
    local byPath = {}
    for i = 1, #watch do byPath[watch[i].path] = true end

    local missing = {}
    for i = 1, #GROUPS do
        local names = report.Compat.GetFrameNames("vanilla", GROUPS[i])
        for j = 1, #names do
            if names[j]:find("^C_Container%.") and not byPath[names[j]] then
                missing[#missing + 1] = names[j]
            end
        end
    end
    T.eq(#missing, 0, "every table spelling is named in the list: "
        .. table.concat(missing, " | "))
end
