local helpers = require("helpers")
local coldboot = require("coldboot")

-- Cold boot: the whole addon, the way the client brings it up.
--
-- What no other check does. Each takes exactly the files it needs, in the
-- order that suits it. So a failure living in a seam -- in the TOC order, in
-- a third-party library, in the core calling a module before it has taken
-- its descriptor -- is visible to nobody.
-- Such a failure stays silent until the client: for the player it looks like
-- a yellow Lua line at login, or looks like nothing at all while the subsystem simply does not work.
--
-- What is brought up here. The real libraries from Libs/ in the order of
-- Libs.xml, the core by its own TOC (all four TOCs in turn -- they differ
-- only in the ## Interface line, and they can diverge silently), eight
-- modules from separate folders by their own TOCs, empty saved variables.
-- The login events are the real ones: ADDON_LOADED per addon, then PLAYER_LOGIN.
--
-- WHAT THIS CHECK DOES NOT CATCH. This is not the game, and it does not try
-- to pretend to be.
--   1. The frame engine. The stub answers any capitalised method, so a typo
--      in a frame method name is invisible here.
--   2. Protected code and combat. Neither SecureActionButton, nor taint, nor
--      the ban on editing panels in combat exists outside the client.
--   3. The look. What the addon drew is not visible here at all: only what it
--      touched and with what numbers.
--   4. The event order of a real client beyond PLAYER_LOGIN
--      (PLAYER_ENTERING_WORLD and everything the game tints after us).
--   5. Foreign addons, the player's own profiles, the real WTF file system.
-- The full analysis is in .superpowers/sdd/cold-boot/report.md.

--============================================================================
-- Shared measures taken from the disk
--============================================================================

local FOLDERS = coldboot.moduleFolders()
local TOCS = coldboot.coreTocs()

--- How many core subsystems this TOC lists.
-- The Modules/ files are counted: a core subsystem is one such file, and it
-- has no other list.
-- @param toc string
-- @return number
local function coreSubsystems(toc)
    local files = coldboot.tocFiles(toc)
    local count = 0
    for i = 1, #files do
        if files[i]:find("^Modules/") then count = count + 1 end
    end
    return count
end

--- The registry module names and the names of the failed ones.
-- @param ns table the namespace of the booted core
-- @return table all names, table the names of the disabled ones
local function census(ns)
    local all, failed = {}, {}
    for _, name in ns.Registry:Each() do
        all[#all + 1] = name
        if ns.Registry:IsFailed(name) then failed[#failed + 1] = name end
    end
    table.sort(all)
    table.sort(failed)
    return all, failed
end

--- Everything that went to chat as one line -- so a failure names its own reason.
-- @param list table
-- @return string
local function lines(list)
    return table.concat(list, " | ")
end

--- The chat without the greeting of the first login.
--
-- The greeting (ns.GreetingText, Core/Init.lua) is the only line the addon
-- writes by itself, unprompted: a fresh install darkens the interface by
-- eighty and must say who did it and what opens it. Here almost every boot is
-- a fresh install, and the rule "nobody writes to chat" would stay green in
-- exactly one way: by removing the greeting. So the rule is not weakened but
-- refined -- "nobody but the greeting".
--
-- That the greeting is said exactly once is checked not here but in two
-- separate places: section 11 below, and the second login from its own saved
-- variables (section 5), where the chat must stay silent entirely.
--
-- The greeting is recognised by its own text rather than by the word
-- "/umbra". Formerly the filter discarded any line containing that word --
-- and a real failure names it too: "the page in the game settings could not
-- be added... the settings are opened by the /umbra command"
-- (Core/Init.lua). That is, a breakage message slipped out of seven "nobody
-- writes to chat at login" checks along with the greeting, and slipped out silently.
--
-- Both spellings of the greeting are listed below and compared with
-- ns.GreetingText by a separate check: having diverged, the list would
-- discard nothing from the seven checks -- the greeting would go red itself rather than hide.
local GREETING_MARKS = {
    "that is the one thing a fresh install changes",
    "can be put back from the same place it was changed",
}

--- The lines nobody asked for.
-- @param chat table the lines that went to chat
-- @return table those of them nobody asked for
local function unasked(chat)
    local out = {}
    for i = 1, #chat do
        local greeting = false
        for j = 1, #GREETING_MARKS do
            if chat[i]:find(GREETING_MARKS[j], 1, true) then greeting = true end
        end
        if not greeting then out[#out + 1] = chat[i] end
    end
    return out
end

--- A boot with every client convenience: the hunter class, pet happiness, the
--- Settings table. That way no module legitimately refuses to work, and any
--- line in chat means trouble.
-- @param extra table fields on top of the shared ones
-- @return table the result of the boot
local function bootWhole(extra)
    local opts = {
        petHappiness  = true,
        settingsPanel = true,
        class         = "HUNTER",
    }
    for key, value in pairs(extra) do opts[key] = value end
    return coldboot.boot(opts)
end

T.ok(#FOLDERS >= 5, "the module folders were found on disk: " .. #FOLDERS)
-- There are five flavours, not four: Forever (1.60.1, interface 16001) is a
-- flavour of its own with its own TOC name suffix, _Camelot. Formerly its
-- number stood in Darken_Vanilla.toc, and that was quietly wrong: the
-- Forever client does not open the vanilla TOC at all -- it looks for
-- Darken_Camelot.toc and, not finding it, falls back to the common
-- Darken.toc. It worked only because the file lists in all the TOCs match.
T.ok(#TOCS == 5, "the core has five TOCs, one per client flavour: " .. #TOCS)

--============================================================================
-- 1. The whole addon: every TOC, every interface number declared in it
--============================================================================

T.suite("cold boot: the core and every module")

for _, toc in ipairs(TOCS) do
    local subsystems = coreSubsystems(toc)

    for _, interface in ipairs(coldboot.tocInterfaces(toc)) do
        local where = toc .. " (" .. interface .. ")"
        local r = bootWhole({ toc = toc, interface = interface, modules = true })
        local ns = r.ns
        local all, failed, api, complaints, declared, column, hollow, presets

        if r.coreLoaded then
            all, failed = census(ns)

            -- The settings window schema, on the REAL defaults.
            --
            -- This is stronger than the same check in test_schema: there the
            -- defaults are fakes, and a path diverging from the real profile
            -- is invisible to it. Here the profile is assembled by the core
            -- from what the subsystems themselves declared -- that is exactly the one the player will have.
            if type(ns.Schema) == "table" then
                complaints = ns.Schema.Validate()
                declared = {}
                for _, page in ipairs(ns.Schema.Pages()) do
                    declared[#declared + 1] = page.id
                end
            end

            if type(ns.PRESETS) == "table" and type(ns.Schema) == "table"
            then
                local seen = 0
                for _, item in ipairs(ns.Schema.Items("general")) do
                    for _, preset in ipairs(ns.PRESETS) do
                        if item.label == preset.label then seen = seen + 1 end
                    end
                end
                presets = { want = #ns.PRESETS, got = seen }
            end

            -- The column: how many rows it holds and whether any is empty.
            --
            -- An empty page in the column is a dead end: the player clicked
            -- and got nothing. Such a page is legitimate only as a container
            -- for nested ones, and then it is NOT empty -- its assembled list
            -- includes their rows.
            --
            -- The number of rows matters in itself: the column has no
            -- scrolling, and rows beyond its height are drawn off the edge of
            -- the window. There is nothing to compute the height with here, but a sudden growth in the number of pages shows anyway.
            if type(ns.Window) == "table" then
                local main, aside = ns.Window.Layers(ns.Schema.Pages())
                column = #main + #aside

                hollow = {}
                for _, page in ipairs(main) do
                    if #ns.Window.Plan(page.id) == 0 then
                        hollow[#hollow + 1] = page.id
                    end
                end
            end
            api = {}
            for _, folder in ipairs(FOLDERS) do
                local names = r.modules[folder] and r.modules[folder].names
                if names and names[1] then
                    api[folder] = ns.Registry:Get(names[1]).api
                end
            end
        end
        r.restore()

        T.ok(r.coreLoaded, where .. ": the core was read in full -- "
            .. tostring(r.coreError))

        if r.coreLoaded then
            T.eq(#r.errors, 0, where .. ": nobody failed at login -- "
                .. lines(r.errors))
            T.eq(#unasked(r.chat), 0, where
                .. ": nobody but the greeting wrote to chat at login -- "
                .. lines(unasked(r.chat)))
            T.ok(ns.Compat.IsSupported(r.flavor),
                where .. ": the client flavour is served: " .. tostring(r.flavor))
            T.ok(r.addon ~= nil and type(r.addon.db) == "table",
                where .. ": the settings database was created")

            -- The core subsystems plus one module per folder: not one extra
            -- and not one missing. Both numbers are asked of the disk.
            T.eq(#all, subsystems + #FOLDERS,
                where .. ": the registry holds every subsystem and every module -- "
                    .. lines(all))
            T.eq(#failed, 0, where .. ": not a single module is disabled -- "
                .. lines(failed))

            T.ok(type(ns.Schema) == "table",
                where .. ": the settings schema was created")
            T.ok(type(ns.Window) == "table",
                where .. ": the settings window was created")

            -- The preset buttons are in place.
            --
            -- They are built from the ns.PRESETS list right when the page is
            -- declared, that is they depend on the ORDER of the files in the
            -- TOC. That order was wrong: the pages were declared before the
            -- presets were created, the list was empty, and the three buttons
            -- were not in the window at all. Validate does not complain about
            -- that -- declaring zero rows is legitimate -- and the loss could only be seen by eye.
            if presets ~= nil then
                T.eq(presets.want, presets.got, where
                    .. ": there are as many preset buttons as there are presets")
            end

            if hollow ~= nil then
                T.eq(#hollow, 0, where .. ": the column holds no empty pages -- "
                    .. table.concat(hollow, " | "))
                T.ok(column ~= nil and column > 0 and column <= 16, where
                    .. ": the column fits: " .. tostring(column)
                    .. " pages")
            end

            if complaints ~= nil then
                T.eq(#complaints, 0, where
                    .. ": the schema validates against the real defaults -- "
                    .. table.concat(complaints, " | "))
                T.ok(declared ~= nil and #declared > 0, where
                    .. ": the pages are declared -- " .. #(declared or {}))
            end

            -- The contract version: the one declared by the module in its own
            -- source and the one accepted by the core are the same number.
            for _, folder in ipairs(FOLDERS) do
                local declared = coldboot.declaredApi(folder)
                T.eq(api[folder], declared, where .. ": " .. folder
                    .. " is registered with its own contract version")
            end
        end
    end
end

--============================================================================
-- 2. The core alone: a module need not exist
--============================================================================

T.suite("cold boot: the core without a single module")

for _, toc in ipairs(TOCS) do
    local interface = coldboot.tocInterfaces(toc)[1]
    local subsystems = coreSubsystems(toc)

    local r = bootWhole({ toc = toc, interface = interface, modules = false })
    local all, failed, hasCommand, hasSchema
    if r.coreLoaded then
        all, failed = census(r.ns)

        -- The slash command word and the settings schema are what the player
        -- installs the core for. Without a single module they must be in place.
        --
        -- Formerly the tree was asked of a third-party library; there is no
        -- tree any more, the pages are declared as data, and the schema is asked instead.
        for name in pairs(_G.SlashCmdList or {}) do
            if _G["SLASH_" .. name .. "1"] == "/darken" then hasCommand = true end
        end
        hasSchema = type(r.ns.Schema) == "table"
            and #r.ns.Schema.Pages() > 0
    end
    r.restore()

    T.ok(r.coreLoaded, toc .. ": the core alone was read -- "
        .. tostring(r.coreError))
    if r.coreLoaded then
        T.eq(#r.errors, 0, toc .. ": the core alone broke nobody -- "
            .. lines(r.errors))
        T.eq(#unasked(r.chat), 0, toc
            .. ": the core alone stays silent but for the greeting -- "
            .. lines(unasked(r.chat)))
        T.eq(#all, subsystems, toc .. ": the registry holds exactly the core subsystems -- "
            .. lines(all))
        T.eq(#failed, 0, toc .. ": not a single subsystem disabled itself -- "
            .. lines(failed))
        T.ok(hasCommand, toc .. ": the /umbra command was taken")
        T.ok(hasSchema, toc .. ": the settings schema was created")
    end
end

--============================================================================
-- 3. A client with no frames at all
--============================================================================

-- A client build may know not a single name from the compatibility table:
-- that is what a future client looks like, and a stripped build too. The
-- addon must come up just as quietly -- that is what the compatibility layer was written for.
--
-- Silence is not demanded here, and that is not a concession. A module with
-- nothing to work with on this client must say so in one line and must not
-- register at all -- that is how refusal works in the contract, and that is
-- how the nameplate engine behaves without a single frame. The requirement is
-- different and stricter: nothing failed, nobody was disabled, and whoever spoke up took no place in the registry.
T.suite("cold boot: a client with no frames")

for _, toc in ipairs(TOCS) do
    local interface = coldboot.tocInterfaces(toc)[1]
    local r = bootWhole({
        toc = toc, interface = interface, modules = true, frames = false,
    })
    local all, failed
    if r.coreLoaded then all, failed = census(r.ns) end
    r.restore()

    T.ok(r.coreLoaded, toc .. ": with no frames the core was read -- "
        .. tostring(r.coreError))
    if r.coreLoaded then
        T.eq(#r.errors, 0, toc .. ": with no frames nobody failed -- "
            .. lines(r.errors))
        T.eq(#failed, 0, toc .. ": with no frames not a single module is disabled -- "
            .. lines(failed))

        T.eq(#all, coreSubsystems(toc) + #FOLDERS,
            toc .. ": with no frames the registry contents are unchanged -- " .. lines(all))

        -- A module may speak up here: "there is nothing for me to do on this
        -- client" is a legitimate answer, and the nameplate engine answers
        -- exactly that. What is not allowed is repeating itself. The same line
        -- twice means two owners or two applications of the settings per
        -- login, and the player sees that as rubbish in chat at every login.
        local twice, seen = {}, {}
        for i = 1, #r.chat do
            if seen[r.chat[i]] then twice[#twice + 1] = r.chat[i] end
            seen[r.chat[i]] = true
        end
        T.eq(#twice, 0, toc .. ": nobody repeated themselves in chat -- " .. lines(twice))
        T.ok(#unasked(r.chat) <= #FOLDERS, toc
            .. ": there are no more speakers than modules: "
            .. #unasked(r.chat))
    end
end

--============================================================================
-- 4. A fresh install changes nothing
--============================================================================

-- A rule of the whole project, and nowhere is it stated from beginning to
-- end. Here it is checked from two sides at once:
--   what is left in the saved variables -- there must not be a single choice
--     of the player, only the schema stamps;
--   what the addon touched in the game -- touching is allowed, changing
--     anything is not.
-- There is one caveat and it is stated out loud: the darkening of a fresh
-- install equals eighty (tests/test_darkdefault.lua covers it separately).
T.suite("cold boot: a fresh install changes nothing")

do
    local r = bootWhole({
        toc = "Darken_Vanilla.toc", interface = 11507, modules = true,
    })

    local darkness, handlers, profile
    if r.coreLoaded then
        darkness = r.addon.db.profile.darkness
        darkness = darkness and darkness.amount
        handlers = r.logout()
        profile = r.sv.profiles and r.sv.profiles.Default
    end
    local touched = r.touched
    r.restore()

    T.ok(r.coreLoaded, "fresh install: the core was read")
    T.eq(darkness, 80,
        "the only caveat: the darkening equals eighty")
    T.ok((handlers or 0) > 0, "logging out: a handler responded")

    -- The saved data. A leaf in the profile not called version is a choice
    -- the player never made: the addon wrote it for them.
    local strays = {}
    local function walk(node, path)
        if type(node) ~= "table" then
            if path:match("version$") == nil then
                strays[#strays + 1] = path
            end
            return
        end
        for key, value in pairs(node) do
            walk(value, path == "" and tostring(key)
                or (path .. "." .. tostring(key)))
        end
    end
    walk(profile or {}, "")
    table.sort(strays)
    T.eq(#strays, 0, "the profile of a fresh install holds not a single choice -- "
        .. lines(strays))

    -- What was touched. A number equal to one changes nothing; creating our
    -- own region on a foreign frame does not either. Everything else is an
    -- edit of the game, and a fresh install has no right to it.
    local changes = {}
    for i = 1, #touched do
        local call = touched[i]
        local harmless = call.method:find("^Create") ~= nil
            or ((call.method == "SetScale" or call.method == "SetAlpha")
                and call.args == "1")
        if not harmless then
            changes[#changes + 1] = call.frame .. ":" .. call.method
                .. "(" .. call.args .. ")"
        end
    end
    table.sort(changes)
    T.eq(#changes, 0, "a fresh install changes not a single game frame -- "
        .. lines(changes))
end

--============================================================================
-- 5. The second login: from what the first one saved
--============================================================================

-- The round trip that catches a value which does not survive logging out. It
-- differs from tests/test_settingsloss.lua in that there is not a single fake
-- here: the setting is set by a handler from the live tree, the logout is a
-- real PLAYER_LOGOUT, and the second login is a full re-boot of the addon
-- over the same table.
T.suite("cold boot: the second login from its own saved variables")

do
    local first = bootWhole({
        toc = "Darken_Vanilla.toc", interface = 11507, modules = true,
    })

    local wrote, sv
    if first.coreLoaded then
        -- The handler of the darkening slider -- the very one the settings
        -- window calls. The tree is taken from the core rather than assembled here.
        local amount = first.ns.Darkness.options.args.amount
        amount.set(nil, 42)
        wrote = amount.get(nil)
        first.logout()
        sv = first.sv
    end
    first.restore()

    T.eq(wrote, 42, "first login: the value was chosen and read back")

    local second = bootWhole({
        toc = "Darken_Vanilla.toc", interface = 11507, modules = true,
        saved = sv,
    })
    local read, all, failed
    if second.coreLoaded then
        read = second.ns.Darkness.options.args.amount.get(nil)
        all, failed = census(second.ns)
    end
    second.restore()

    T.ok(second.coreLoaded, "second login: the core was read -- "
        .. tostring(second.coreError))
    T.eq(#second.errors, 0, "second login: nobody failed -- "
        .. lines(second.errors))
    T.eq(#second.chat, 0, "second login: nobody wrote to chat -- "
        .. lines(second.chat))
    T.eq(read, 42, "second login: what the player chose came back the same")
    T.eq(#failed, 0, "second login: not a single module is disabled -- "
        .. lines(failed or {}))
    T.eq(#(all or {}), coreSubsystems("Darken_Vanilla.toc") + #FOLDERS,
        "second login: the registry contents are unchanged")
end

--============================================================================
-- 6. A module is missing
--============================================================================

-- Every module in turn is not installed. The core and its eight neighbours
-- must come up as if the ninth had never existed: a missing addon is not a
-- failure but the ordinary state for almost every player.
T.suite("cold boot: one module is missing")

for _, missing in ipairs(FOLDERS) do
    local rest = {}
    for _, folder in ipairs(FOLDERS) do
        if folder ~= missing then rest[#rest + 1] = folder end
    end

    local r = bootWhole({
        toc = "Darken_Vanilla.toc", interface = 11507, modules = rest,
    })
    local all, failed
    if r.coreLoaded then all, failed = census(r.ns) end
    r.restore()

    T.ok(r.coreLoaded, "without " .. missing .. ": the core was read")
    if r.coreLoaded then
        T.eq(#r.errors + #unasked(r.chat), 0, "without " .. missing
            .. ": neither an error nor a line in chat -- "
            .. lines(r.errors) .. lines(unasked(r.chat)))
        T.eq(#failed, 0, "without " .. missing .. ": the neighbours are intact -- "
            .. lines(failed))
        T.eq(#all, coreSubsystems("Darken_Vanilla.toc") + #rest,
            "without " .. missing .. ": the registry holds exactly the remaining ones")
    end
end

--============================================================================
-- 7. A module fails on enabling
--============================================================================

-- The core promise in the words of its own message: the one that failed is
-- disabled, the rest works. Here it is checked on a full boot rather than on
-- a fake registry: the failure comes from a foreign OnEnable, and it is
-- caught by the very Registry:Protect that stands in the game.
T.suite("cold boot: a module fails on enabling")

do
    local broken = FOLDERS[1]
    local r = bootWhole({
        toc = "Darken_Vanilla.toc", interface = 11507, modules = true,
        breakModule = broken,
    })

    local all, failed, brokenName
    if r.coreLoaded then
        all, failed = census(r.ns)
        brokenName = r.modules[broken] and r.modules[broken].names
            and r.modules[broken].names[1]
    end
    r.restore()

    T.ok(r.coreLoaded, "a failed module: the core came up anyway")
    T.eq(#r.errors, 0, "a failed module: the error did not escape -- "
        .. lines(r.errors))
    T.eq(#unasked(r.chat), 1, "a failed module: exactly one line in chat -- "
        .. lines(unasked(r.chat)))
    T.eq(#failed, 1, "exactly one is disabled -- " .. lines(failed or {}))
    T.eq((failed or {})[1], brokenName, "and it is precisely the one that failed")
    T.eq(#(all or {}), coreSubsystems("Darken_Vanilla.toc") + #FOLDERS,
        "the failed one stays in the registry: it has something to say about itself in the settings")
end
T.suite("cold boot: a naive module")

do
    --- A naively written module, on top of an already booted core.
    -- @param name string the module name
    -- @return table a report of what the module managed to do
    local function naive(name)
        local log = { enabled = 0, applied = 0 }

        -- Here it is, that very variable: the handlers know nothing but it,
        -- and none of them takes the descriptor from self.
        local module

        local function draw()
            log.settings = type(module:GetSettings()) == "table"
            log.named = module.name == name
        end

        module = _G.Darken:RegisterModule({
            name     = name,
            api      = _G.Darken.API_VERSION,
            defaults = { enabled = true },
            OnEnable = function()
                log.enabled = log.enabled + 1
                draw()
            end,
            ApplySettings = function()
                log.applied = log.applied + 1
                draw()
            end,
        })

        log.handle = module
        return log
    end

    local early, late
    local r = bootWhole({
        toc = "Darken_Vanilla.toc", interface = 11507, modules = true,
        beforeLogin = function() early = naive("umbranaiveearly") end,
    })

    -- The second order: the module arrived at a core that is already running.
    -- The frame the core defers its enabling to is pumped by the same pump the
    -- client pumps its own with.
    if r.coreLoaded then
        late = naive("umbranaivelate")
        r.pump()
    end

    local failed
    if r.coreLoaded then _, failed = census(r.ns) end
    r.restore()

    T.ok(r.coreLoaded, "a naive module: the core was read")
    T.eq(#r.errors, 0, "a naive module: nobody failed -- " .. lines(r.errors))
    T.eq(#unasked(r.chat), 0,
        "a naive module: nobody but the greeting wrote to chat -- "
        .. lines(unasked(r.chat)))
    T.eq(#(failed or {}), 0, "a naive module: not a single module is disabled -- "
        .. lines(failed or {}))

    for _, case in ipairs({
        { "arrived before entering the world", early },
        { "arrived at a running core", late },
    }) do
        local what, log = case[1], case[2]
        T.ok(log ~= nil and log.handle ~= nil, what .. ": the descriptor was handed out")
        if log then
            T.eq(log.enabled, 1, what .. ": enabled exactly once")
            T.ok(log.applied >= 1, what .. ": the settings were applied")
            T.eq(log.settings, true,
                what .. ": its own settings were read through the variable")
            T.eq(log.named, true, what .. ": and the descriptor in it is the right one")
        end
    end
end

--============================================================================
-- 11. The greeting at the first login
--============================================================================

-- The only line the addon writes to chat by itself. What is checked is not
-- how it is written but when it is said: once for a fresh install, never for
-- everyone else. A line at every login would be noise, and noise gets
-- switched off along with the addon.
--
-- Both logins are the same boot over the same saved table, that is the check
-- follows the same path the player reaches this place by: installed, logged
-- in, logged out, logged in again.
T.suite("cold boot: the greeting at the first login")

do
    local first = bootWhole({
        toc = "Darken_Vanilla.toc", interface = 11507, modules = true,
    })

    local greetings, sv = {}, nil
    if first.coreLoaded then
        for i = 1, #first.chat do
            if first.chat[i]:find("/darken", 1, true) then
                greetings[#greetings + 1] = first.chat[i]
            end
        end
        first.logout()
        sv = first.sv
    end
    first.restore()

    T.eq(#greetings, 1, "first login: the addon spoke about itself exactly once -- "
        .. lines(greetings))

    -- The command and the number must both stand in the line: without the
    -- command the player does not know what opens the window, and without the number they do not know what exactly changed.
    if greetings[1] then
        T.ok(greetings[1]:find("/darken", 1, true) ~= nil,
            "the greeting names the command")
        -- The number is the same as in the darkening subsystem default (80).
        T.ok(greetings[1]:find("80", 1, true) ~= nil,
            "the greeting names the darkening as a number: " .. greetings[1])
    end

    local second = bootWhole({
        toc = "Darken_Vanilla.toc", interface = 11507, modules = true,
        saved = sv,
    })
    local again = second.coreLoaded and #second.chat or nil
    second.restore()

    T.eq(again, 0, "second login: the greeting is gone")
end

-- The list of greeting marks is compared with the greeting itself. The
-- unasked filter discards from the seven "nobody writes to chat" checks
-- exactly the lines it recognised by this list; a list that fell behind the
-- text would stop recognising the greeting -- and the seven checks would go
-- red on it instead of silently letting a real failure through.
do
    local scene = bootWhole({
        toc = "Darken_Vanilla.toc", interface = 11507,
    })
    local greet, plain
    if scene.coreLoaded then
        greet = scene.ns.GreetingText({ darkness = { amount = 70 } })
        plain = scene.ns.GreetingText(nil)
    end
    scene.restore()

    T.ok(greet ~= nil, "the greeting was assembled")
    for _, text in ipairs({ greet or "", plain or "" }) do
        local known = false
        for i = 1, #GREETING_MARKS do
            if text:find(GREETING_MARKS[i], 1, true) then known = true end
        end
        T.eq(known, true, "the filter recognises this spelling of the greeting: " .. text)
    end

    -- The other side: a failure that names the command is no longer eaten by the filter.
    local refusal = "could not add a page to the game's interface options "
        .. "(boom). The settings open with the /umbra command."
    T.eq(#unasked({ refusal }), 1,
        "while a real failure containing the word /umbra does not drop out of the checks")
end
