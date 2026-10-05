local helpers = require("helpers")
local localekeys = require("localekeys")

helpers.installValidator()

-- The info panel from a separate folder (Features/InfoPanel).
--
-- It is checked by the same code the game will load it with, and falls into
-- five parts: formatting the values (where the mistakes live), the cell
-- layout and the space taken from the screen, the LibDataBroker data source
-- registry, our own sources together with their schedules, and the registration in the core.
--
-- Checked separately is the thing the module is written this way for: a
-- foreign source and our own travel to the line on screen by one and the same
-- road, and there is no "ah, but this one is ours" branch on it.
--
-- The drawing (Panel.lua) enters here exactly as far as it works without a
-- client: outside the game there is no CreateFrame, and the file is written so
-- that this is an absent frame rather than a breakage.

local MODULE = "Features/InfoPanel"

-- The module takes its number formatting from the core while reading its own
-- Format.lua (Darken:GetFormat, contract 12). The door is opened by the real
-- core file -- a fake beside it would be checking a copy instead of what the player sees.
local coreFormat, restoreCore = helpers.installFormat()


--- Load the module files into a fresh namespace.
-- The file list and the order are taken from the module TOC rather than copied here.
-- @param withRegistration boolean whether to load InfoPanel.lua (it registers itself)
-- @return table
local function moduleNamespace(withRegistration)
    local ns = helpers.newNamespace()
    return helpers.loadModule(MODULE, ns, { withRegistration = withRegistration })
end

local ns = moduleNamespace(false)

T.suite("info panel: formatting the values")

do
    local F = ns.Format

    -- Gold. A leading zero denomination is not shown, a trailing one is:
    -- "12g 0s 5c" reads as an amount, "12g 5c" as a parsing mistake.
    T.eq(F.Money(123456), "12g 34s 56c", "the coins are split by denomination")
    T.eq(F.Money(1200005), "120g 0s 5c", "zero silver stays in place")
    T.eq(F.Money(105), "1s 5c", "with no gold there is no gold")
    T.eq(F.Money(7), "7c", "below a silver, copper only")
    T.eq(F.Money(0), "0c", "zero is zero rather than an empty cell")
    T.eq(F.Money(-105), "-1s 5c", "a debt (such things come from foreign sources)")

    -- The letters come from the client: in a non-English one they differ.
    T.eq(F.Money(10000, { gold = "з", silver = "с", copper = "м" }),
        "1з 0с 0м", "the denomination letters come from the client")

    -- Anything can come from SavedVariables and from the game.
    T.eq(F.Money(nil), F.NONE, "no number gives a dash")
    T.eq(F.Money("a lot"), F.NONE, "a string gives a dash")
    T.eq(F.Money(0 / 0), F.NONE, "NaN gives a dash")

    -- Percentages and durability.
    T.eq(F.Percent(1, 2), "50%", "a half is a half")
    T.eq(F.Percent(1, 0), F.NONE, "there is nothing to divide by zero")
    T.eq(F.Percent(0, 100), "0%", "zero percent is a value rather than nothing")
    T.eq(F.Ratio(2, 3), 67, "rounding up at .67")

    -- The lowest rather than the average: the player needs to know what will break first.
    T.eq(F.Durability({ { current = 100, maximum = 100 },
        { current = 10, maximum = 100 } }), 10, "the most worn item is taken")
    T.eq(F.Durability({}), nil, "with no equipment there is no durability")
    T.eq(F.Durability({ { current = 5, maximum = 0 } }), nil,
        "an item with no durability does not count")
    T.eq(F.Durability("garbage"), nil, "a non-table gives nothing either")

    -- Bags.
    T.eq(F.Bags(24, 80), "24/80", "free out of total")
    T.eq(F.Bags(24, nil), "24", "with no total the free count remains")
    T.eq(F.Bags(nil, 80), F.NONE, "with no free count there is nothing to show")

    -- Latency: two numbers, because there are two of them.
    T.eq(F.Latency(40, 55), "40/55 ms", "the home and the world latency")
    T.eq(F.Latency(40, 40), "40 ms", "equal ones are not doubled")
    T.eq(F.Latency(40, nil), "40 ms", "an old client returns one number")
    T.eq(F.Latency(nil, nil), F.NONE, "no numbers give a dash")

    T.eq(F.Fps(59.6), "60 fps", "the frames are rounded")
    T.eq(F.Fps(nil), F.NONE, "no frames give a dash")

    -- The clock. Midnight and noon are the two cases people get wrong.
    T.eq(F.Clock(9, 7, 3), "09:07", "hours and minutes with a leading zero")
    T.eq(F.Clock(9, 7, 3, false, true), "09:07:03", "seconds on request")
    T.eq(F.Clock(0, 5, 0, true), "12:05 AM", "midnight is 12 AM")
    T.eq(F.Clock(12, 5, 0, true), "12:05 PM", "noon is 12 PM")
    T.eq(F.Clock(13, 5, 0, true), "01:05 PM", "one in the afternoon is 1 PM")
    T.eq(F.Clock(23, 5, 0), "23:05", "the day runs to 23")
    T.eq(F.Clock(nil, 5), F.NONE, "with no hour there is no time")

    -- Experience: three display kinds and the rested bonus for all three.
    T.eq(F.Experience(500, 2000, nil, "current"), "500/2.0k", "the current value and the limit")
    T.eq(F.Experience(500, 2000, nil, "percent"), "25%", "the percentage")
    T.eq(F.Experience(500, 2000, nil, "remaining"), "1.5k", "the remainder")
    T.eq(F.Experience(500, 2000, 200, "percent"), "25% +10%",
        "the rested bonus is appended as a separate value")
    T.eq(F.Experience(500, 2000, nil, "garbage"), "500/2.0k",
        "an unknown kind means the default kind")
    T.eq(F.Experience(500, 0), F.NONE, "at the level cap there is no experience")

    -- Reputation.
    T.eq(F.Reputation("Exodar", "Friendly", 500, 1000, "percent"),
        "Exodar: 50%", "the percentage for the faction")
    T.eq(F.Reputation("Exodar", "Friendly", 500, 1000),
        "Exodar: 500/1.0k", "earned out of needed")
    T.eq(F.Reputation("Exodar", "Friendly", nil, nil),
        "Exodar: Friendly", "with no numbers the standing remains")
    T.eq(F.Reputation(nil), F.NONE, "with no watched faction, a dash")

    -- Abbreviations of large numbers.
    T.eq(F.Short(999), "999", "a small number is not abbreviated")
    T.eq(F.Short(1500), "1.5k", "thousands")
    T.eq(F.Short(15000), "15.0k", "tens of thousands, just as on the bars")
    T.eq(F.Short(2500000), "2.5m", "millions")
    T.eq(F.Short(999999), "1.0m",
        "almost a million is written as a million rather than \"1000.0k\"")

    -- The cell line. The same one for our sources and for foreign ones.
    T.eq(F.Cell("Gold", "12g"), "Gold: 12g", "the label and the value")
    T.eq(F.Cell(nil, "12g"), "12g", "with no label the value remains")
    T.eq(F.Cell("Gold", nil), "Gold", "with no value the label remains")
    T.eq(F.Cell(nil, nil), F.NONE, "neither of them gives a dash")
end

T.suite("info panel: the order and layout of the cells")

do
    local L = ns.Layout

    local names = { "Broker_Clock", "Darken gold", "AAA_Foreign" }

    -- There is no order from the profile: everything alphabetical, and the
    -- order is the same from run to run. Table iteration in Lua has no order,
    -- and without sorting the row would rearrange itself.
    local arranged = L.Arrange(names, nil)
    T.eq(arranged[1], "AAA_Foreign", "with no choice by the player, alphabetical")
    T.eq(arranged[3], "Darken gold", "and our source is in the common row")

    -- What the player chose comes first, the rest follows alphabetically.
    arranged = L.Arrange(names, { "Darken gold" })
    T.eq(arranged[1], "Darken gold", "what the player arranged comes first")
    T.eq(arranged[2], "AAA_Foreign", "the rest follows alphabetically")

    -- A name no longer in the registry (the addon was removed) is skipped silently.
    arranged = L.Arrange(names, { "Departed", "Darken gold" })
    T.eq(#arranged, 3, "a vanished name takes no place")
    T.eq(arranged[1], "Darken gold", "and does not shift the others")

    -- A hidden cell disappears from the display but not from the order.
    local visible = L.Visible(names, { "Darken gold" }, { AAA_Foreign = true })
    T.eq(#visible, 2, "a hidden cell is not shown")
    T.eq(visible[2], "Broker_Clock", "the order of the rest does not change")

    local order = L.Arrange(names, nil)
    T.eq(order[1] .. "|" .. order[2], "AAA_Foreign|Broker_Clock", "the original row")

    local moved = L.Move(names, nil, "Broker_Clock", -1)
    T.eq(moved[1], "Broker_Clock", "the cell was moved further left")
    T.eq(moved[2], "AAA_Foreign", "its neighbour took its place")

    moved = L.Move(names, nil, "AAA_Foreign", -1)
    T.eq(moved[1], "AAA_Foreign", "from the edge there is nowhere to move")

    moved = L.Move(names, nil, "no such", 1)
    T.eq(#moved, 3, "an unknown name does not break the order")

    -- Two strips.
    local top, bottom = L.Split(order, { AAA_Foreign = "bottom" }, "top",
        { top = true, bottom = true })
    T.eq(#top, 2, "two cells remained on the top strip")
    T.eq(bottom[1], "AAA_Foreign", "the chosen cell moved to the bottom")

    -- A disabled strip does not eat its cells: they move to the one that is
    -- enabled. Otherwise the player would lose half their sources silently.
    top, bottom = L.Split(order, { AAA_Foreign = "bottom" }, "top",
        { top = true, bottom = false })
    T.eq(#top, 3, "with the bottom one off everything moves to the top")
    T.eq(#bottom, 0, "and nothing is left at the bottom")

    -- Both off: nothing is shown, and that is not an error.
    top, bottom = L.Split(order, nil, "top", { top = false, bottom = false })
    T.eq(#top + #bottom, 0, "both strips off: there are no cells")

    -- The space taken from the screen.
    T.eq(select(1, L.Reserve(3, 0, 18, true)), 18, "a strip takes its own height")
    T.eq(select(2, L.Reserve(3, 0, 18, true)), 0, "an empty strip takes nothing")
    T.eq(select(1, L.Reserve(3, 2, 18, false)), 0, "with no offset nothing is taken")
    T.eq(select(1, L.Reserve(3, 0, "garbage", true)), L.BOUNDS.height.default,
        "a height from SavedVariables is clamped to the default")
    T.eq(L.Clamp("height", 1000), L.BOUNDS.height.max, "too tall is clamped")

    -- The UIParent anchors. The native ones are preserved entirely, only the offset changes.
    local base = {
        { "TOPLEFT", nil, "TOPLEFT", 0, 0 },
        { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 },
    }
    local points = L.Offsets(base, 18, 0)
    T.eq(points[1][5], -18, "the top edge moved down by the strip height")
    T.eq(points[1][1], "TOPLEFT", "the anchor itself stayed native")
    T.eq(points[2][5], 0, "the bottom edge is untouched")

    points = L.Offsets(base, 0, 18)
    T.eq(points[2][5], 18, "the bottom edge moved up")

    points = L.Offsets(base, 0, 0)
    T.eq(points[1][5], 0, "zero space restores the native anchors")

    -- A UIParent held by its centre: it must not be moved blindly.
    T.eq(L.Offsets({ { "CENTER", nil, "CENTER", 0, 0 } }, 18, 0), nil,
        "with no anchor to the top or the bottom there is nothing to offset")
    T.eq(L.Offsets({}, 18, 0), nil, "with no anchors at all, nothing either")
end

T.suite("info panel: the data source registry")

do
    local B = ns.Broker
    local shim = B.NewShim()

    local heard = {}
    B.Subscribe(shim, "a check", B.CHANGED, function(_, name, key, value)
        heard[#heard + 1] = name .. "." .. key .. "=" .. tostring(value)
    end)

    local created = {}
    B.Subscribe(shim, "a check", B.CREATED, function(_, name)
        created[#created + 1] = name
    end)

    local object = shim:NewDataObject("A foreign source",
        { type = "data source", label = "Foreign", text = "1" })
    T.eq(created[1], "A foreign source", "the appearance of the source was reported")

    -- A write into a source is broadcast to the subscribers. That IS the
    -- replacement for polling: the panel learns of a new value rather than asking for it on a timer.
    object.text = "2"
    T.eq(heard[1], "A foreign source.text=2", "the value change was broadcast")

    -- A repeated write of the same value stays silent: otherwise the panel
    -- would redraw on every event of a foreign addon, even with nothing new to show.
    object.text = "2"
    T.eq(#heard, 1, "the same value is not broadcast a second time")

    T.eq(shim:GetDataObjectByName("A foreign source"), object,
        "the source is found by name")
    T.eq(shim:NewDataObject("A foreign source"), object,
        "the same name a second time does not create a second object")

    -- What exactly is shown.
    T.eq(B.Displayable(object), true, "a source with text is shown")
    T.eq(B.Displayable(shim:NewDataObject("A launcher button",
        { type = "launcher", icon = "some icon" })), false,
        "a launcher with no text is not shown")
    T.eq(B.Displayable(nil), false, "nothing is not shown")

    local label, text = B.Text(object)
    T.eq(label, "Foreign", "the label is read")
    T.eq(text, "2", "the value is read")

    -- The second kind of the standard: a number with a value and a suffix.
    local numeric = shim:NewDataObject("A counter",
        { type = "data source", value = 42, suffix = " kg" })
    label, text = B.Text(numeric)
    T.eq(text, "42 kg", "a value with a suffix reads as text")
    T.eq(B.Displayable(numeric), true, "and such a source is shown")

    -- The name list is alphabetical and without what there is nothing to show.
    local names = B.Names(shim)
    T.eq(#names, 2, "the launcher did not make it into the list")
    T.eq(names[1], "A counter", "the names are sorted")
    T.eq(B.Names(nil)[1], nil, "with no registry the list is empty")
end

T.suite("info panel: moving onto the real library")

do
    local B = ns.Broker

    -- There is no real library: the sources are published into our own replacement.
    local first = B.Acquire(nil, nil)
    T.eq(first.shim, true, "with no library a replacement is created")
    first:NewDataObject("Darken gold",
        { type = "data source", label = "Gold", text = "12g" })

    -- The library appeared later (a load-on-demand addon). Our sources move
    -- into it, otherwise they would stay apart from the foreign ones.
    local real = B.NewShim()
    real.shim = nil
    local libstub = setmetatable({}, { __call = function(_, name)
        if name == B.LIB then return real end
        return nil
    end })

    local second, moved = B.Acquire(libstub, first)
    T.eq(second, real, "now we work with the real library")
    T.eq(moved, true, "the move happened")

    local object = real:GetDataObjectByName("Darken gold")
    T.ok(object ~= nil, "our source ended up in the real library")
    local label, text = B.Text(object)
    T.eq(text, "12g", "together with its value")

    -- There is nowhere to move a second time.
    local third, again = B.Acquire(libstub, second)
    T.eq(third, real, "the registry is the same")
    T.eq(again, false, "and there is no second move")

    -- A library that does not answer the standard calls does not count as a
    -- library: the check is by the existence of the calls rather than by name.
    local broken = setmetatable({}, { __call = function() return { } end })
    T.eq(B.Resolve(broken), nil, "a foreign table with no standard calls is rejected")
    T.eq(B.Resolve(nil), nil, "with no LibStub there is no library")
end

T.suite("info panel: our sources and their schedules")

do
    local S = ns.Sources
    local F = ns.Format

    -- The whole path "the game returned a number -- the player saw a line" is
    -- under the check: the access table is built from a set of globals, and here that set is a fake.
    local fake = {
        GetMoney = function() return 123456 end,
        GOLD_AMOUNT_SYMBOL = "g", SILVER_AMOUNT_SYMBOL = "s",
        COPPER_AMOUNT_SYMBOL = "c",
        GetInventoryItemDurability = function(slot)
            if slot == 1 then return 50, 100 end
            if slot == 2 then return 90, 100 end
            return nil
        end,
        NUM_BAG_SLOTS = 1,
        GetContainerNumSlots = function() return 16 end,
        GetContainerNumFreeSlots = function() return 3 end,
        GetNetStats = function() return 0, 0, 40, 55 end,
        GetFramerate = function() return 61.2 end,
        date = function() return { hour = 13, min = 5, sec = 9 } end,
        UnitXP = function() return 500 end,
        UnitXPMax = function() return 2000 end,
        GetXPExhaustion = function() return nil end,
        GetWatchedFactionInfo = function()
            return "Exodar", 5, 3000, 9000, 6000
        end,
    }

    -- The panel asks the core for the game container functions rather than
    -- taking them from the set of globals: which of the two spellings the
    -- client uses for bag work is decided by the compatibility layer. The door
    -- here is that same real layer, only over an invented client (helpers.gameDoor).
    local env = S.Environment(fake, helpers.gameDoor(fake))
    local settings = { xpMode = "percent", clock12 = true }

    local values = {}
    for _, entry in ipairs(S.LIST) do
        values[entry.key] = entry.Value(env, settings)
    end

    T.eq(values.gold, "12g 34s 56c", "the gold was assembled from the game")
    T.eq(values.durability, "50%", "the durability is by the most worn item")
    T.eq(values.bags, "6/32", "the bags are summed over every container")
    T.eq(values.latency, "40/55 ms", "the latency of both kinds")
    T.eq(values.fps, "61 fps", "the frames")
    T.eq(values.clock, "01:05 PM", "the clock in the chosen form")
    T.eq(values.experience, "25%", "the experience in the chosen form")
    T.eq(values.reputation, "Exodar: 3.0k/6.0k", "the reputation from the standing threshold")

    -- A client without half of these calls (and such clients exist) gives
    -- dashes rather than a Lua error.
    local bare = S.Environment({}, helpers.gameDoor({}))
    for _, entry in ipairs(S.LIST) do
        local ok, value = pcall(entry.Value, bare, nil)
        T.eq(ok and value, F.NONE, entry.key .. ": an empty client gives a dash")
    end

    -- The events. A source has either events or a schedule, but not both at
    -- once: a schedule over an event would be polling.
    for _, entry in ipairs(S.LIST) do
        local both = entry.events ~= nil and entry.period ~= nil
        T.eq(both, false, entry.key .. ": events and a schedule do not come together")
        T.ok(entry.events ~= nil or entry.period ~= nil,
            entry.key .. ": the source is updated by something")
    end

    local events = S.Events()
    T.ok(#events >= 7, "events collected: " .. #events)
    local seen = {}
    for _, name in ipairs(events) do
        T.eq(seen[name], nil, "the event " .. name .. " is named once")
        seen[name] = true
    end
    T.eq(#S.For("PLAYER_MONEY"), 1, "PLAYER_MONEY rebuilds one source")
    T.eq(S.For("PLAYER_MONEY")[1].key, "gold", "and that is the gold")
    T.eq(#S.For("NO SUCH EVENT"), 0, "a foreign event rebuilds nothing")

    -- The clock tick. The frames once a second, the latency once in five: the
    -- game itself recomputes it once in thirty, and there is no reason to ask more often.
    local timed = S.Timed()
    T.eq(#timed, 3, "three have a schedule: the frames, the latency and the clock")

    local state = {}
    local wanted = {}
    for _, entry in ipairs(timed) do wanted[S.Name(entry.key)] = true end

    local due = S.Due(timed, state, 100, wanted)
    T.eq(#due, 3, "the first time everything is rebuilt")
    for _, entry in ipairs(due) do S.Mark(state, entry.key, 100) end

    due = S.Due(timed, state, 101, wanted)
    T.eq(#due, 2, "a second later, only the frames and the clock")

    due = S.Due(timed, state, 100.5, wanted)
    T.eq(#due, 0, "half a second rebuilds nothing")

    due = S.Due(timed, state, 106, wanted)
    T.eq(#due, 3, "after five seconds the latency arrives too")

    -- And the main thing: what is not visible is not computed at all.
    due = S.Due(timed, {}, 200, { [S.Name("fps")] = true })
    T.eq(#due, 1, "hidden cells are not rebuilt")
    T.eq(due[1].key, "fps", "while a shown one is rebuilt")
end

T.suite("info panel: our source is indistinguishable from a foreign one")

do
    local B = ns.Broker
    local S = ns.Sources
    local F = ns.Format

    local broker = B.NewShim()

    -- A foreign addon publishes its source straight into the registry -- the
    -- way it actually does, knowing nothing about us.
    broker:NewDataObject("AAA Foreign", {
        type = "data source", label = "Gold", text = "12g 34s 56c",
    })

    -- Ours is published by the same standard call.
    local published = S.Publish(broker)
    T.ok(published.gold ~= nil, "our source is published")

    local env = S.Environment({ GetMoney = function() return 123456 end })
    S.Update(S.LIST[1], published.gold, env, nil)

    -- Both are read by one function and give one line. That IS the equality:
    -- not "we show foreign ones too" but "ours cannot be told from a foreign one".
    local ourLabel, ourText = B.Text(broker:GetDataObjectByName(S.Name("gold")))
    local theirLabel, theirText = B.Text(broker:GetDataObjectByName("AAA Foreign"))
    T.eq(F.Cell(ourLabel, ourText), F.Cell(theirLabel, theirText),
        "the cell line is one and the same")

    -- In the cell list they stand side by side and are sorted by the common
    -- rule: the foreign source takes first place because that is how the
    -- alphabet worked out rather than because somebody yielded to anybody.
    local arranged = ns.Layout.Arrange(B.Names(broker), nil)
    T.eq(arranged[1], "AAA Foreign", "the foreign source comes first")
    T.eq(arranged[2], S.Name("bags"), "ours follow, by the same rule")

    -- A panel with not a single source of ours works fully: the road from the
    -- registry to the line knows nothing about us.
    local foreignOnly = B.NewShim()
    foreignOnly:NewDataObject("A single foreign one", { text = "5" })
    local names = B.Names(foreignOnly)
    T.eq(#names, 1, "a panel of foreign sources only assembles")
    T.eq(F.Cell(B.Text(foreignOnly:GetDataObjectByName(names[1]))), "5",
        "and shows their value")

    -- And the same rule in the sources: the drawing layer knows neither the
    -- prefix of our names nor a list of our sources. The check is textual
    -- because an "ah, but this one is ours" branch appears not in the design but in an edit six months later.
    local panel = localekeys.read("Features/InfoPanel/Panel.lua")
    T.eq(panel:find("Darken ", 1, true), nil,
        "the drawing layer does not know the prefix of our names")
    T.eq(panel:find("ns.Sources", 1, true), nil,
        "and never calls our sources once")
end

T.suite("info panel: translation completeness")

do
    -- The module sources are taken from its TOC rather than listed here.
    local SOURCES = helpers.moduleSources(MODULE)

    local wanted, seen = {}, {}
    for _, file in ipairs(SOURCES) do
        for _, key in ipairs(localekeys.literal(localekeys.read(file))) do
            if not seen[key] then
                seen[key] = true
                wanted[#wanted + 1] = key
            end
        end
    end
    T.ok(#wanted >= 30, "the keys were read out of the module sources: " .. #wanted)

    local nonAscii = {}
    for i = 1, #wanted do
        if wanted[i]:find("[\128-\255]") then
            nonAscii[#nonAscii + 1] = wanted[i]
        end
    end
    T.eq(#nonAscii, 0, "every key is English: " .. table.concat(nonAscii, " | "))

    for _, locale in ipairs({ "ruRU", "ukUA" }) do
        local translations = ns.Strings[locale]
        T.ok(type(translations) == "table", locale .. ": the table exists")

        local missing = {}
        for i = 1, #wanted do
            if type(translations[wanted[i]]) ~= "string" then
                missing[#missing + 1] = wanted[i]
            end
        end
        T.eq(#missing, 0, locale .. ": left untranslated: "
            .. table.concat(missing, " | "))

        local orphan = {}
        for key in pairs(translations) do
            if not seen[key] then orphan[#orphan + 1] = key end
        end
        T.eq(#orphan, 0, locale .. ": translations with no call site: "
            .. table.concat(orphan, " | "))
    end
end

T.suite("info panel: registering in the core and the space on screen")

do
    local saved = { Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        UIParent = _G.UIParent, LibStub = _G.LibStub }

    local core = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", core)
    helpers.loadAddonFile("Core/Registry.lua", core)
    helpers.loadAddonFile("Core/Defaults.lua", core)
    helpers.loadAddonFile("Core/Command.lua", core)
    helpers.loadAddonFile("Core/Locale.lua", core)
    helpers.loadAddonFile("Core/Skin.lua", core)
    helpers.loadAddonFile("Skin/Draw.lua", core)
    helpers.loadAddonFile("Core/Frames.lua", core)
    helpers.loadAddonFile("Core/Events.lua", core)
    helpers.loadAddonFile("Core/Combat.lua", core)
    helpers.loadAddonFile("Core/Casefold.lua", core)
    helpers.loadAddonFile("Core/Format.lua", core)
    helpers.loadAddonFile("Core/Api.lua", core)
    helpers.loadAddonFile("Core/Media.lua", core)

    local said = {}
    core.Registry.report = function(text) said[#said + 1] = text end

    local profile = { umbrainfo = { enabled = false, top = true, bottom = false,
        height = 18, push = true, defaultSide = "top",
        order = {}, hidden = {}, sides = {},
        clock12 = false, clockSeconds = false,
        xpMode = "current", repMode = "current" } }

    core.Addon = {
        db = { profile = profile, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }
    core.flavor = "mists"

    _G.SlashCmdList = {}

    -- A fake UIParent: the same calls the module takes space from the screen
    -- with. Without it the offset arithmetic would be checked but not the fact
    -- that it reaches the frame.
    local anchors = {
        { "TOPLEFT", nil, "TOPLEFT", 0, 0 },
        { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 },
    }
    _G.UIParent = {
        IsProtected = function() return true end,
        GetNumPoints = function() return #anchors end,
        GetPoint = function(_, i)
            local p = anchors[i]
            return p[1], p[2], p[3], p[4], p[5]
        end,
        ClearAllPoints = function() anchors = {} end,
        SetPoint = function(_, point, relativeTo, relativePoint, x, y)
            anchors[#anchors + 1] = { point, relativeTo, relativePoint, x, y }
        end,
    }

    local panelNs = moduleNamespace(true)
    local handle = core.Registry:Get("umbrainfo")
    T.ok(handle ~= nil, "the module is registered")

    if handle then
        core.Registry:EnableAll()

        -- A disabled panel is subscribed to no game event and does not touch
        -- the screen: a fresh install changes nothing.
        T.eq(core.Events.Count("PLAYER_MONEY"), 0,
            "a disabled panel listens to no events")
        T.eq(anchors[1][5], 0, "and takes no space from the screen")

        -- Enabling with no interface reload.
        local settings = handle:GetSettings()
        settings.enabled = true
        handle:Apply()

        T.eq(core.Events.Count("PLAYER_MONEY"), 1,
            "an enabled panel listens to the gold event")
        T.eq(core.Events.Count("BAG_UPDATE_DELAYED"), 1, "and the bag event")

        -- Entering the world. The core applies the settings once, when the
        -- profile comes up, and this event arrives AFTER -- and behind it the
        -- game rebuilds the interface anew. A strip placed before it stayed
        -- standing while the taken space vanished: "it did not work at load,
        -- and after any settings edit it did".
        T.eq(core.Events.Count("PLAYER_ENTERING_WORLD"), 1,
            "and entering the world, after which the interface is rebuilt anew")

        -- The space is taken: the top edge of UIParent moved down by the strip height.
        local top
        for _, p in ipairs(anchors) do
            if p[1] == "TOPLEFT" then top = p[5] end
        end
        T.eq(top, -18, "the top edge of the screen is lowered by the strip height")

        -- The values assembled and lie in the registry -- in the same place as the foreign ones.
        local names = panelNs.Broker.Names(panelNs.Broker.Acquire(nil, nil))
        T.ok(names ~= nil, "the registry answers")

        -- The cell order can be rearranged, and that shows in the profile.
        local order = panelNs.Layout.Arrange(
            { panelNs.Sources.Name("gold"), panelNs.Sources.Name("clock") }, nil)
        T.eq(order[1], panelNs.Sources.Name("clock"), "the clock stands before the gold")

        -- Disabling with no reload: the subscriptions are removed, the screen is restored.
        settings.enabled = false
        handle:Apply()

        T.eq(core.Events.Count("PLAYER_MONEY"), 0,
            "a disabled panel stopped listening to events")
        T.eq(core.Events.Count("PLAYER_ENTERING_WORLD"), 0,
            "and to entering the world too: a left subscription would call a dead module")

        local restored
        for _, p in ipairs(anchors) do
            if p[1] == "TOPLEFT" then restored = p[5] end
        end
        T.eq(restored, 0, "the space on screen was restored as it was")

        -- The slash word is taken.
        T.ok(_G.SlashCmdList ~= nil, "the command list is in place")

        -- The module has no saved variable of its own and cannot have one: its
        -- data lives in the core database under its name.
        T.ok(profile.umbrainfo ~= nil, "the settings live in the core profile")
        T.eq(profile.umbrainfo.version, nil,
            "there is no schema version in the module settings")
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.UIParent = saved.UIParent
end

T.suite("info panel: the strip stands at the screen edge, not at the UIParent edge")

-- Formerly the strip stood at an offset from the UIParent edge -- the same one
-- that edge had been lowered by -- and together they gave the former screen
-- edge. That holds exactly as long as the edge stays where it was put.
--
-- It does not stay. Lowering it does not always succeed (in combat UIParent is
-- protected, and in some clients it is held by neither the top nor the
-- bottom), and even a successful offset is rolled back by the game itself as
-- it recomputes the layout. The author's report showed the second outright:
-- "applied 18 above" followed by "UIParent is not where the panel left it:
-- TOPLEFT at 0,-0 instead of 0,-18". The strip meanwhile was built, shown,
-- 2133 by 18 and opaque -- and hung eighteen pixels above the top of the screen.
--
-- So the strip is anchored to WorldFrame: nobody moves it, and it IS the
-- screen. What is checked here is that the anchoring goes exactly to it and
-- with no offset -- even when UIParent is offset.
do
    local saved = { Darken = _G.Darken, SlashCmdList = _G.SlashCmdList,
        UIParent = _G.UIParent, CreateFrame = _G.CreateFrame,
        WorldFrame = _G.WorldFrame }

    local core = helpers.newNamespace()
    for _, file in ipairs({ "Core/Compat.lua", "Core/Registry.lua",
        "Core/Defaults.lua", "Core/Command.lua", "Core/Locale.lua",
        "Core/Skin.lua", "Skin/Draw.lua", "Core/Frames.lua", "Core/Events.lua",
        "Core/Combat.lua", "Core/Casefold.lua", "Core/Format.lua",
        "Core/Api.lua", "Core/Media.lua" }) do
        helpers.loadAddonFile(file, core)
    end

    local said = {}
    core.Registry.report = function(text) said[#said + 1] = text end

    local profile = { umbrainfo = { enabled = false, top = true, bottom = false,
        height = 18, push = true, defaultSide = "top",
        order = {}, hidden = {}, sides = {},
        clock12 = false, clockSeconds = false,
        xpMode = "current", repMode = "current" } }

    core.Addon = {
        db = { profile = profile, global = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }
    core.flavor = "mists"
    _G.SlashCmdList = {}

    -- A UIParent held by its centre: not a single anchor to the top or the
    -- bottom, and it must not be moved blindly. The strip no longer cares, and
    -- that is exactly what is checked here.
    local anchors = { { "CENTER", nil, "CENTER", 0, 0 } }
    _G.UIParent = {
        IsProtected = function() return true end,
        GetNumPoints = function() return #anchors end,
        GetPoint = function(_, i)
            local p = anchors[i]
            return p[1], p[2], p[3], p[4], p[5]
        end,
        ClearAllPoints = function() anchors = {} end,
        SetPoint = function(_, point, relativeTo, relativePoint, x, y)
            anchors[#anchors + 1] = { point, relativeTo, relativePoint, x, y }
        end,
    }

    -- Fake frames: exactly the strip anchors and whether it is shown are
    -- needed. Everything else answers with an empty call -- this is not a
    -- client, and there is no reason to pretend to be one here.
    local built = {}
    local noop = function() end
    local fake
    fake = function(kind)
        local frame = { points = {}, shown = false }
        frame.SetPoint = function(self, point, relativeTo, _, x, y)
            self.points[#self.points + 1] = { point, x, y, relativeTo }
        end
        frame.ClearAllPoints = function(self) self.points = {} end
        frame.Show = function(self) self.shown = true end
        frame.Hide = function(self) self.shown = false end
        -- The texture and the string must be objects: the core styling creates
        -- them and accesses them by field right away.
        frame.CreateTexture = function() return fake("Texture") end
        frame.CreateFontString = function() return fake("FontString") end
        -- Only methods answer with an empty call: in the engine they are capitalised.
        -- A field that does not exist must stay empty -- otherwise the core
        -- styling would get a function where it expects an object.
        setmetatable(frame, { __index = function(_, key)
            if type(key) == "string" and key:match("^%u") then return noop end
        end })
        if kind == "Frame" then built[#built + 1] = frame end
        return frame
    end
    _G.CreateFrame = function(kind) return fake(kind) end

    -- The screen the strip anchors to. Nobody moves it, and that is exactly
    -- why the strip holds on to it rather than to UIParent.
    _G.WorldFrame = fake("Frame")

    moduleNamespace(true)
    local handle = core.Registry:Get("umbrainfo")
    T.ok(handle ~= nil, "the module is registered")

    if handle then
        core.Registry:EnableAll()

        local settings = handle:GetSettings()
        settings.enabled = true
        handle:Apply()

        -- There was no offset: the screen edge is where it was.
        T.eq(anchors[1][1], "CENTER", "UIParent stayed on its own anchor")

        -- The strip is the one of the created frames that was given the top
        -- edge of the screen: it is not the only thing creating frames.
        local strip
        for _, frame in ipairs(built) do
            for _, p in ipairs(frame.points) do
                if p[1] == "TOPLEFT" then strip = frame end
            end
        end
        T.ok(strip ~= nil, "the strip was built and put in place")

        if strip then
            T.eq(strip.shown, true, "the strip is shown")

            local top, anchoredTo
            for _, p in ipairs(strip.points) do
                if p[1] == "TOPLEFT" then top, anchoredTo = p[3], p[4] end
            end
            T.eq(top, 0, "and stands flush with the edge, with no offset")
            T.eq(anchoredTo, _G.WorldFrame,
                "anchored to the screen rather than to the movable UIParent edge")
        end
    end

    for key, value in pairs(saved) do _G[key] = value end
    _G.UIParent, _G.CreateFrame = saved.UIParent, saved.CreateFrame
end

-- The file list of a part and its place in the addon TOC are checked by one
-- suite for every part -- tests/test_moduletoc.lua. Formerly that check stood
-- here: the part had a TOC of its own and answered for it itself.

helpers.removeValidator()