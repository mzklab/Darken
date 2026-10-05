local ADDON, ns = ...

local AceAddon  = LibStub("AceAddon-3.0")

-- The saved variable's name from the TOC. Two parties take it from here:
-- creating the database, and the raw migrations, which read that same table
-- before the database exists.
local SV_NAME = "DarkenDB"


local Addon = AceAddon:NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0")
ns.Addon = Addon

function Addon:OnInitialize()
    -- The flavour is determined once at load and never recomputed.
    local _, _, _, toc = GetBuildInfo()
    ns.flavor = ns.Compat.DetectFlavor(toc)

    if not ns.Compat.IsSupported(ns.flavor) then
        self:Print(string.format(ns.Localize(
            "this client is not supported (flavor: %s, interface: %s). "
                .. "The addon did not start."),
            tostring(ns.flavor), tostring(toc)))
        self:SetEnabledState(false)

        -- A marker for the public layer. Without it a third-party module's
        -- registration would succeed silently: the module would enter the
        -- registry, never be enabled, receive no settings and have no way to
        -- say so — handle:Print would go nowhere along with the core. Such a
        -- registration is now refused with a reason (Core/Api.lua).
        ns.CoreStartupFailed = true
        return
    end

    -- Settings: the shared database plus the modules' sections.
    --
    -- An impostor name used to break loading: an error raised right here.
    -- That was right for exactly as long as we wrote every module — our own
    -- typo has to be visible immediately. With modules in separate folders
    -- the same exception would mean a third-party module with an unfortunate
    -- name leaves the player without a core: OnInitialize would abort, and
    -- with it neither the settings database nor the /darken command would
    -- appear. So the refusal is now addressed — the module is disabled and
    -- says so, while the core carries on.
    --
    -- The check has not weakened: a third-party module never reaches this
    -- point, its name is rejected earlier, in Core/Api.lua. What remains here
    -- is the second line of defence, in case such a module got into the
    -- registry by some path anyway.
    --
    -- There are two sections: profile switches along with the profile, global
    -- lives for the whole account. The second exists for data whose lifetime
    -- a profile gets wrong: a list of items across every character must not
    -- be swapped out when the look changes. The core has no global settings
    -- of its own yet, and its half of the table is empty.
    -- The assembly lives in Core/Defaults.lua and knows nothing about the
    -- game or about AceDB: it is that table which decides which setting
    -- survives logout and which does not, and it must be checked outside the
    -- client (tests/test_settingsloss.lua).
    local defaults = ns.BuildDefaults(ns.Registry)

    -- The defaults table stays with the addon: a module registered later
    -- (and third-party modules arrive precisely later) adds its own section
    -- to it and redeclares the defaults to the live database.
    self.defaults = defaults

    -- The raw migrations run before the database is created, and there is
    -- nowhere else for them.
    --
    -- At load AceDB spreads the defaults across the profile (copyDefaults),
    -- and after that a missing key in the saved file is indistinguishable
    -- from a default just placed. A migration that needs to know "the player
    -- did not choose this" has nothing left to look at — see ns.RawMigrations
    -- in Core/Defaults.lua.
    --
    -- The saved variable's name is the same for both calls: were they to
    -- diverge, they would create a migration that edits the wrong table, and
    -- does so silently.
    -- Whether this is the first login. Asked here and only here: after
    -- AceDB:New the saved table already exists, and there will be nothing
    -- left to tell a fresh installation from a second login by — the same
    -- ordering ns.RawMigrations lives by one line below.
    --
    -- The marker is the absence of the profiles section in SavedVariables. A
    -- fresh installation has no saved file at all (_G[SV_NAME] is nil), but
    -- nil alone cannot be relied on: other code and the tests give an empty
    -- table, which is the same fresh installation. A profile, once created,
    -- never disappears from the saved file — MigrateProfile writes `version`
    -- into it as a raw entry and removeDefaults does not touch that — so a
    -- second login answers "no" even for someone who never touched a single
    -- setting.
    local stored = _G[SV_NAME]
    self.firstRun = type(stored) ~= "table"
        or type(stored.profiles) ~= "table"

    ns.MigrateStoredProfiles(_G[SV_NAME], ns.RawMigrations, ns.DB_VERSION)

    self.db = LibStub("AceDB-3.0"):New(SV_NAME, defaults, true)

    ns.MigrateProfile(self.db.profile, ns.Migrations, ns.DB_VERSION)

    -- The frame-name directory collects itself, once per client build. There
    -- is a command for it, but asking the player to type it means getting
    -- data from nobody except those who read the documentation.
    self:CollectFrameNames()

    -- The palette's accent comes BEFORE any widget is styled: the styling
    -- reads the palette at the moment it colours a widget, and the first
    -- window opened before the colour changed would stay lilac forever —
    -- widgets are coloured once.
    ns.Skin.SetAccent(self.db.profile.accent)

    -- A profile switch leads into the same application path as everything
    -- else.
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileUpdate")
    self.db.RegisterCallback(self, "OnProfileCopied",  "OnProfileUpdate")
    self.db.RegisterCallback(self, "OnProfileReset",   "OnProfileUpdate")

    -- The commands are registered before the settings deliberately. AceAddon
    -- calls OnInitialize through safecall: any error below aborts the
    -- function, and had the commands come last the addon would be left with
    -- no /darken at all.
    -- Three spellings of one command. "dark" is what it is called in
    -- conversation, "darken" is the addon's full name, and "dk" is for those
    -- who type fast.
    self:RegisterChatCommand("dark",   "HandleCommand")
    self:RegisterChatCommand("darken", "HandleCommand")
    self:RegisterChatCommand("dk",     "HandleCommand")

    -- The page in the game's options holds a button rather than a tree.
    --
    -- The author: there should be a button here that opens our UI; there is
    -- no need to draw it inside, there is too little room. And the room there
    -- really does belong to somebody else: a strip of the game's own window,
    -- shared with its own list of categories, while our window is built for
    -- its own width and its own page column.
    --
    -- The page is built by Options/Bliz.lua with a frame of its own. The doors
    -- into the game's options differ between clients, and what is not there
    -- is not called: the page may be absent entirely, and that is not a
    -- failure — the settings open with a command.
    local okBliz, blizErr = pcall(function()
        if type(ns.Bliz) == "table" then ns.Bliz.Add() end
    end)
    if not okBliz then
        self:Print(string.format(ns.Localize(
            "could not add a page to the game's interface options (%s). "
                .. "The settings open with the /darken command."),
            tostring(blizErr)))
    end
end

-- The cap on names per pattern and per kind of name. It exists for the size
-- of the saved file rather than for speed: in a modern build the pattern
-- "Bar" yields over six hundred names, and all of them would travel to disk.
--
-- The number is harmless precisely because the truncation now happens after
-- the sort and is recorded in a field of its own (Core/Scan.lua,
-- Scan.Collect): a truncated list is the first SCAN_LIMIT names
-- alphabetically, and the directory says itself that it was truncated and how
-- many names there really were.
local SCAN_LIMIT = 200

-- Collecting the frame-name directory. Called by itself at login: asking the
-- player to type a command means getting data from nobody except those who
-- read the documentation. The command remains, but as a manual repeat rather
-- than as a precondition.
function Addon:CollectFrameNames(force)
    if not self.db then return end

    local build = GetBuildInfo and select(2, GetBuildInfo()) or nil
    if not force and not ns.Scan.NeedsCollect(self.db.global.scan, build) then
        return
    end

    local collected, total = ns.Scan.Collect(_G, ns.Scan.PATTERNS, SCAN_LIMIT)
    self.db.global.scan = {
        -- The flavour lives in ns.flavor and nowhere else (OnInitialize
        -- above sets it). This used to read ns.Compat.flavor — a field nobody
        -- ever filled in — and the saved file held nil where the client's
        -- flavour belonged.
        flavor  = ns.flavor,
        build   = build,
        version = GetBuildInfo and (GetBuildInfo()) or nil,
        found   = collected.frames,

        -- Game function names go in a field of their own rather than mixed
        -- in with the frames: the compatibility layer declares both, but
        -- declares them as different groups, and a mixed list would answer
        -- the wrong question.
        functions = collected.functions,

        -- What the cap was and what was truncated. Until this field
        -- existed, a truncated list was indistinguishable from a complete
        -- one: the reader could only count and check whether there were
        -- exactly two hundred names. A pattern's key here means "the list is
        -- incomplete, and this is how many names there really were"; no key
        -- means the list is complete, and the absence of a name from it means
        -- the name is absent from the client.
        limit   = collected.limit,
        cut     = collected.cut,
    }
    return total
end

--- The line the addon greets the player with on their first login.
--
-- Why it exists. Installing changes exactly one thing — dimming set to
-- sixty-four — and changes it silently: the player logs in, sees a darkened
-- interface and knows neither who did it nor what opens it. The project page
-- and the README name the command, but not everyone reads them and not
-- before logging in, while inside the game the addon has so far said not a
-- word about itself.
--
-- Said once, on a fresh installation, and never again: a line in chat on
-- every login is noise, and noise gets switched off along with the addon.
--
-- The number is taken from the profile rather than written out here: the
-- line must name what the player actually has rather than what stood when
-- the text was written. The dimming section may be absent from the build —
-- then no number is named.
--
-- A pure function: it prints nothing and knows nothing about the game.
-- @param profile table|nil the settings profile
-- @return string the greeting
function ns.GreetingText(profile)
    local darkness = type(profile) == "table" and profile["darkness"] or nil
    local amount = type(darkness) == "table" and tonumber(darkness["amount"])

    if amount then
        return string.format(ns.Localize("the interface is dimmed to %d of "
            .. "100 - that is the one thing a fresh install changes. Type "
            .. "/darken for the settings, where the Interface Darkness slider goes back "
            .. "to zero in one drag."), amount)
    end

    return ns.Localize("type /darken for the settings. Everything the addon "
        .. "changes can be put back from the same place it was changed.")
end

function Addon:OnEnable()
    -- Initialisation did not happen (an unsupported client) — leave the
    -- modules alone.
    if not self.db then return end

    -- The greeting goes here rather than in OnInitialize: OnInitialize runs
    -- on ADDON_LOADED, while the chat window is still being redrawn, and the
    -- line is lost in it. OnEnable is called on PLAYER_LOGIN — the event
    -- after which the player sees the screen.
    if self.firstRun then
        self.firstRun = nil
        self:Print(ns.GreetingText(self.db.profile))
    end

    -- Enabling goes through the registry rather than a loop here. The loop
    -- used to call module:OnEnable() directly, and an exception in one module
    -- aborted the enabling of everyone listed after it. The registry calls
    -- each module under protection: one that raises is disabled, its
    -- neighbours are enabled.
    ns.Registry:EnableAll()
end

--- Add a module's settings to the live database.
-- Needed by modules in separate folders: they register after the database has
-- been created, and their section is not in the declared defaults. AceDB can
-- redeclare defaults on a running database — that is what is used here,
-- rather than writing values into the profile by hand. The difference shows
-- at logout: values equal to the default are cleaned out of SavedVariables by
-- AceDB, while hand-written ones would stay there forever as litter.
-- @param name string the module's name
-- @param moduleDefaults table its defaults in the profile
-- @param moduleGlobals table|nil its defaults in the global section
-- @return boolean whether it succeeded
-- @return string|nil the error text if the library rejected the defaults; nil
--         means "there is no database yet", which is not an error: the
--         defaults will be collected by OnInitialize's pass over the
--         registry
function ns.InjectModuleDefaults(name, moduleDefaults, moduleGlobals)
    local addon = ns.Addon
    if type(addon) ~= "table" then return false end
    if type(addon.db) ~= "table" or type(addon.defaults) ~= "table" then
        return false
    end
    if type(name) ~= "string" or type(moduleDefaults) ~= "table" then
        return false
    end

    -- The defaults table's global section may not exist: it is assembled by
    -- this file, but a stand-in table from the tests is not.
    local globals = addon.defaults.global
    if type(globals) ~= "table" then
        globals = {}
        addon.defaults.global = globals
    end

    local hadProfile = addon.defaults.profile[name]
    local hadGlobal  = globals[name]

    addon.defaults.profile[name] = moduleDefaults
    if type(moduleGlobals) == "table" then
        globals[name] = moduleGlobals
    end

    -- AceDB itself may reject a third-party module's defaults. Breaking that
    -- addon's loading over it is not allowed, and neither is staying silent:
    -- a module without defaults would read empty settings and behave
    -- inexplicably. So the error is returned upwards and the module is
    -- disabled like any other that failed.
    local ok, err = pcall(addon.db.RegisterDefaults, addon.db, addon.defaults)
    if not ok then
        addon.defaults.profile[name] = hadProfile
        globals[name] = hadGlobal
        return false, tostring(err)
    end

    return true
end

-- There is no rebuilding of the settings tree any more: there is no tree.
-- The pages are declared as data and the window repaints itself — a module
-- that arrived late added its rows to the same schema, and the next repaint
-- shows them.

-- The profile changed: re-read the settings by the same path as at login.
function Addon:OnProfileUpdate()
    ns.MigrateProfile(self.db.profile, ns.Migrations, ns.DB_VERSION)
    ns.Registry:ApplyAll()
end

-- The window's size is no longer set here: our own window sets it itself
-- (Options/Window), and sets it from the room available rather than from a
-- round number. The library used to assign it, and assigned it
-- unconditionally — taking away whatever the player had stretched with the
-- mouse.

--- Open the settings window.
function Addon:OpenConfig()
    if type(ns.Window) ~= "table" then return end
    ns.Window.Show()
end

--- Whether the settings window is open right now.
-- Asked of the window rather than remembered in a field of our own: the
-- window knows whether it is shown, and a second record of the same fact
-- would diverge from it silently — a window closed with its close button
-- would still count as open.
-- @return boolean
function Addon:ConfigOpen()
    if type(ns.Window) ~= "table" then return false end
    return ns.Window.IsShown()
end

--- Open the settings window, or close it if it is open.
--
-- The button is a toggle and must behave as one: clicking the minimap icon
-- while the window is open has to close it. It used to call the open path
-- again, that is, do nothing, and the author put it plainly: one click opens
-- it, and if it is open a click should close it.
function Addon:ToggleConfig()
    if type(ns.Window) ~= "table" then return end
    ns.Window.Toggle()
end

-- Command dispatch. Parsing the text lives in ns.ParseCommand
-- (Core/Command.lua); only the choice of action remains here. With no
-- arguments: open the settings.
function Addon:HandleCommand(input)
    local cmd, rest = ns.ParseCommand(input)

    if cmd == "widgets" then
        -- A display of our own widgets: one of every kind.
        --
        -- A tool kept from the settings window's migration. A widget cannot
        -- be created without a client, and everything it draws is checked by
        -- eye — and it has to be looked at before a thousand rows of the
        -- window rest on those widgets.
        if type(ns.Widgets) ~= "table"
            or type(ns.Widgets.Toggle) ~= "function" then
            self:Print(ns.Localize("this build has no widget demo"))
            return
        end

        local shown = ns.Widgets.Toggle()
        self:Print(shown and ns.Localize("widget demo is open")
            or ns.Localize("widget demo is closed"))
        return
    end

    if cmd == "window" then
        -- The settings window, opened by a word of its own.
        --
        -- The word is a habit left from the migration: /darken opens this
        -- same window and there is no second one any more. It had its own
        -- word rather than replacing /darken deliberately: /darken was the
        -- only entrance to the settings, and switching it to a window nobody
        -- had yet seen in a client would have left the player without any
        -- settings at all had it failed to open. It can go once the habit
        -- does.
        if type(ns.Window) ~= "table"
            or type(ns.Window.Toggle) ~= "function" then
            self:Print(ns.Localize("this build has no new settings window"))
            return
        end

        local shown = ns.Window.Toggle()
        self:Print(shown and ns.Localize("new settings window is open")
            or ns.Localize("new settings window is closed"))
        return
    end

    if cmd == "demo" then
        -- The demo section may already have been removed (a release build)
        -- — then there is nothing to toggle, and that has to be said rather
        -- than passed over in silence.
        if type(ns.ToggleDemo) ~= "function" then
            self:Print(ns.Localize("this build has no demo section"))
            return
        end
        local shown = ns.ToggleDemo()

        -- A row's conditions are re-read on a repaint rather than
        -- continuously. Without a notification the open window would stay as
        -- it was, and the section would appear or disappear only after
        -- closing it and typing /darken again. The repaint goes through one
        -- path (ns.NotifyConfigChanged).
        ns.NotifyConfigChanged()

        self:Print(shown and ns.Localize("the demo section is on")
                          or ns.Localize("the demo section is off"))
        return
    end

    if cmd == "report" then
        -- The report does not assemble itself, neither at login nor on an
        -- event: a fresh installation changes nothing, and there is no reason
        -- to touch a live client unasked. It is assembled only here, reads,
        -- and touches nothing.
        if not self.db then
            self:Print(ns.Localize("the settings database is not ready yet"))
            return
        end

        local facts = ns.Report.ClientFacts(_G)
        local report = ns.Report.Build(ns.flavor, _G, facts)

        -- The previous report is taken before it is overwritten: it is the
        -- only thing that can say which build produced the answer stored here
        -- until now. A fresh installation finds nothing here, and there will
        -- be no line about it.
        local previous = self.db.global.report

        -- Stored in the global section rather than in the profile: this is a
        -- property of the client rather than the player's choice, and it does
        -- not change when the profile does.
        self.db.global.report = report

        local lines = ns.Report.Lines(report, nil, previous)
        for i = 1, #lines do self:Print(lines[i]) end
        return
    end

    if cmd == "probe" then
        -- Why this command exists.
        --
        -- A window that stayed light looks the same under any of six causes:
        -- the pass never reached it, the engine forbade touching the object,
        -- the frame is protected, the type is skipped entirely, the texture
        -- was judged to be content, the depth ran out. The author sends a
        -- screenshot and the words "not dimmed", and until now the answer to
        -- that was a guess — and a guess is corrected by rewriting the rule,
        -- that is, by breaking what worked.
        --
        -- The probe uses the same traversal and the same questions as the
        -- dimming itself (Modules/Darkness.lua, Darkness.Probe). It colours
        -- nothing and remembers nothing.
        local darkness = ns.Registry and ns.Registry:Get("darkness")
        if type(darkness) ~= "table"
            or type(ns.Darkness) ~= "table"
            or type(ns.Darkness.Probe) ~= "function" then
            self:Print(ns.Localize("the dimming subsystem is not loaded"))
            return
        end

        -- A name is optional: the window the player means is the one they
        -- have just opened, and the watcher for window openings remembered
        -- it.
        local frame, where
        if rest == "" then
            frame = ns.Darkness.lastWindow
            where = ns.Localize("the window opened last")
            if type(frame) ~= "table" then
                self:Print(ns.Localize(
                    "open the window first, then type /dark probe - or name "
                        .. "the frame: /dark probe <frame name>"))
                return
            end
        elseif rest == "text" then
            -- A word about the explanatory paragraphs, written for one
            -- occasion.
            --
            -- All thirty-eight explanations in the settings window were not
            -- drawn at all. Measured from the screenshot: in the strip under
            -- the heading there were zero pixels brighter than the
            -- background and not one half-tone — so this was not a dark
            -- colour but the absence of glyphs. From outside that has exactly
            -- four causes — no text, no font, zero opacity, the string
            -- hidden — and not one of them can be told from the look of the
            -- screen.
            --
            -- So the window itself is asked. The command changes nothing.
            local lines = ns.ProbeWindowText and ns.ProbeWindowText() or nil
            if type(lines) ~= "table" or #lines == 0 then
                self:Print(ns.Localize(
                    "open the settings window first, then type /dark probe "
                        .. "text"))
                return
            end
            for i = 1, #lines do self:Print(lines[i]) end
            return
        elseif rest == "mouse" then
            -- Whatever the cursor is pointing at right now.
            --
            -- Why this word exists. The player is not obliged to know a
            -- frame's name, and "the window opened last" answers about the
            -- whole window — a hundred textures at once. When ONE panel
            -- stayed light in the middle of a dark window, it is that panel
            -- that has to be asked about, and the only way to point at it is
            -- with the cursor.
            --
            -- The call's name differs between builds, so both are tried and
            -- through a guarded call: on a client with neither, the word
            -- simply answers that there is nothing to point at.
            local focus
            if type(_G.GetMouseFoci) == "function" then
                local ok, list = pcall(_G.GetMouseFoci)
                if ok and type(list) == "table" then focus = list[1] end
            end
            if focus == nil and type(_G.GetMouseFocus) == "function" then
                local ok, found = pcall(_G.GetMouseFocus)
                if ok then focus = found end
            end

            frame = focus
            where = ns.Localize("what the cursor points at")

            if type(frame) ~= "table" then
                self:Print(ns.Localize(
                    "point the cursor at it first, then type /dark probe "
                        .. "mouse"))
                return
            end
        else
            frame = _G[rest]
            where = rest
            if type(frame) ~= "table" then
                self:Print(string.format(
                    ns.Localize("there is no frame named '%s'"), rest))
                return
            end
        end

        local records, tally = ns.Darkness.Probe(frame)
        local lines = ns.Darkness.ProbeLines(records, tally, 20)

        self:Print(string.format(
            ns.Localize("dimming probe of %s:"), tostring(where)))
        for i = 1, #lines do self:Print(lines[i]) end

        -- The full list goes to a file: there can be hundreds of lines, and
        -- copying them out of chat by hand is work we would have created for
        -- the player ourselves.
        if self.db then
            self.db.global.darkprobe = {
                frame   = tostring(where),
                tally   = tally,
                records = records,
            }
            self:Print(ns.Localize(
                "log out - the whole list will land in DarkenDB.lua, under "
                    .. "global.darkprobe"))
        end
        return
    end

    if cmd == "scan" then
        if rest == "" then
            self:Print(ns.Localize(
                "usage: /darken scan <part of a frame name>"))
            self:Print(ns.Localize(
                "or /darken scan all - collect everything into the saved "
                    .. "variables file"))
            return
        end

        -- "all" collects the whole directory and puts it in the global
        -- section. Chat will not do for that: there are hundreds of names,
        -- and copying them by hand is work we would have created for the
        -- player ourselves. After logout the result is in DarkenDB.lua and is
        -- read from disk.
        if rest:lower() == "all" then
            local total = self:CollectFrameNames(true)
            if not total then
                self:Print(ns.Localize("the settings database is not ready yet"))
                return
            end
            self:Print(string.format(
                ns.Localize("collected %d names over %d patterns"),
                total, #ns.Scan.PATTERNS))

            -- The truncation is stated out loud here too, not only in the
            -- file. The previous scan kept quiet about it, and fourteen
            -- patterns out of twenty-five turned out to be inconclusive —
            -- which could only be worked out afterwards, by counting whether
            -- each list held exactly two hundred names.
            local scan = self.db.global.scan
            local capped = 0
            if type(scan) == "table" and type(scan.cut) == "table" then
                for _ in pairs(scan.cut) do capped = capped + 1 end
            end
            if capped > 0 then
                self:Print(string.format(ns.Localize(
                    "%d patterns hit the cap of %d names - their lists are "
                        .. "the first %d by name, and scan.cut says how many "
                        .. "there really were"),
                    capped, SCAN_LIMIT, SCAN_LIMIT))
            end

            self:Print(ns.Localize(
                "log out - the result will land in DarkenDB.lua"))
            return
        end
        local found = ns.Scan.Find(rest, _G, 60)
        self:Print(string.format(
            ns.Localize("found %d for the pattern '%s':"), #found, rest))

        -- Chat is no place for sixty lines in a row: the first twenty are
        -- printed and the rest reported as a number. The search's own limit
        -- is unchanged; narrowing the pattern is the player's decision.
        local shown = math.min(#found, 20)
        for i = 1, shown do
            self:Print("  " .. found[i])
        end
        if #found > shown then
            self:Print("  " .. string.format(
                ns.Localize("... and %d more - narrow the pattern"),
                #found - shown))
        end
        return
    end

    -- A part's word. Looked up after the core's own: the core yields a word
    -- to a part only when it does not answer to it itself, which is why
    -- "report" cannot be taken away by a third-party module silently.
    if ns.RunModuleCommand(cmd, rest) then return end

    self:OpenConfig()
end
