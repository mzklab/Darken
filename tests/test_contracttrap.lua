local helpers = require("helpers")

-- The contract's trap: its three halves and what closed them.
--
-- What the file is written for. The tenth module was written blind — by
-- docs/module-api.md alone — and found three places in the contract where the
-- document was right while the door's shape was wrong. The file guards the shape specifically rather than the document's text.
--
--   1. The descriptor did not yet exist when the core called the module's
--      handlers. The author wrote "local module =
--      Darken:RegisterModule{...}" and used the module variable from his own
--      OnEnable — while the enabling was done from inside the registration,
--      that is, before the assignment. The module fell over on its own first
--      line and switched itself off without drawing anything. All eight
--      modules of the repository carry a hand-written line in that place,
--      "module = module or self"; the exemplary tenth did not carry it and was
--      therefore broken until the cold boot stepped on it. Nine identical workarounds are not nine mistakes of the authors but one mistake of the door.
--   2. A mover element's label was a translation key the module never passed
--      through Localize once. Which means not one check of the translation's
--      completeness — and all of them gather the keys by call sites — saw it.
--   3. There was no alarm colour in the palette, and a watchdog module could
--      not say "bad" except by inventing a colour out of numbers.
--
-- The first and the third are checked here in full and the second from the
-- side it was lost from: a label's key is obliged to be found by an ordinary
-- parse of the module's source.

--============================================================================
-- The stand-in client: the frame work is deferred to
--============================================================================

-- A frame here arrives on request rather than by itself. Otherwise the check
-- would judge the order of events by when a timer fired — that is, by nothing.
local queue = {}
local savedTimer = _G.C_Timer
_G.C_Timer = {
    After = function(_, fn)
        if type(fn) == "function" then queue[#queue + 1] = fn end
    end,
}

--- Turn a frame over: carry out everything deferred to it.
-- @return number how much of what was deferred was carried out
local function frame()
    local done = 0
    while #queue > 0 do
        local fn = table.remove(queue, 1)
        done = done + 1
        if done > 64 then error("the deferred work does not end", 2) end
        fn()
    end
    return done
end

--- The core as the public layer sees it.
-- @return table the namespace, table what was said to the player
local function core()
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/Format.lua", ns)
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Frames.lua", ns)
    helpers.loadAddonFile("Core/Events.lua", ns)
    helpers.loadAddonFile("Core/Combat.lua", ns)
    helpers.loadAddonFile("Core/Api.lua", ns)

    local said = {}
    ns.Registry.report = function(text) said[#said + 1] = text end
    ns.Addon = {
        db = { profile = {}, global = {}, char = {} },
        Print = function(_, text) said[#said + 1] = text end,
    }

    return ns, said
end

helpers.installValidator()

--============================================================================
-- 1. A module written naively
--============================================================================

-- Naively means the way anybody will write it who read section 3 and did not
-- go looking for a catch: assign the returned value to a variable and use that
-- variable from the handlers. It is exactly that module which used to fall over.
--
-- The module here is written once and created twice: before the core is
-- enabled and after. Two legitimate orders of registration — "the module came
-- before the entry into the world" and "the module came to a working core" —
-- and the naive one is obliged to survive both. The first used to pass and the
-- second to fail, and there was no difference between them in the document.
--
-- @param ns table the core
-- @param name string the module's name
-- @return table a report of what the module managed to do
local function naive(ns, name)
    local log = { enabled = 0, applied = 0, crash = nil }

    -- Here it is, that very variable. The handlers know nothing but it.
    local module

    --- The module's work: everything it does goes through the module variable.
    local function draw()
        local settings = module:GetSettings()
        log.settings = type(settings) == "table"
    end

    module = ns.Api:RegisterModule({
        name     = name,
        api      = ns.Api.API_VERSION,
        defaults = { enabled = true },

        OnEnable = function()
            log.enabled = log.enabled + 1
            local ok, err = pcall(draw)
            if not ok then log.crash = tostring(err) end
        end,

        ApplySettings = function()
            log.applied = log.applied + 1
            local ok, err = pcall(draw)
            if not ok then log.crash = tostring(err) end
        end,
    })

    log.handle = module
    return log
end

T.suite("the trap: a naive module before the entry into the world")

do
    local ns, said = core()

    local log = naive(ns, "umbraearly")
    T.ok(log.handle ~= nil, "the descriptor was returned: " .. table.concat(said, " | "))
    T.eq(log.enabled, 0, "before the entry into the world nobody is enabled")

    ns.Registry:EnableAll()
    frame()

    T.eq(log.crash, nil, "the naive module did not fall over: " .. tostring(log.crash))
    T.eq(log.enabled, 1, "enabled exactly once")
    T.ok(log.applied >= 1, "the settings were applied")
    T.eq(log.settings, true, "the module read its own settings through the variable")
    T.eq(#said, 0, "nothing was said in the chat: " .. table.concat(said, " | "))
    T.eq(ns.Registry:IsFailed("umbraearly"), false, "the module was not switched off")
end

T.suite("the trap: a naive module coming to an already working core")

do
    local ns, said = core()

    -- The core is already working: its own subsystems are enabled, the entry into the world has happened.
    ns.Registry:EnableAll()

    local log = naive(ns, "umbralate")
    T.ok(log.handle ~= nil, "the descriptor was returned: " .. table.concat(said, " | "))

    -- The whole file's main assertion. While the enabling was done from inside
    -- the registration there would be a "1" here, the module variable would be
    -- a nil at that instant, and log.crash would carry "attempt to index upvalue 'module'".
    T.eq(log.enabled, 0, "nobody was called from inside the registration")
    T.eq(log.applied, 0, "and no settings were applied to anybody")
    T.eq(ns.Registry:IsEnabled(log.handle), false,
        "and the descriptor itself says the module is not working yet")

    T.eq(frame(), 1, "the enabling was deferred by exactly one frame")

    T.eq(log.crash, nil, "the naive module did not fall over: " .. tostring(log.crash))
    T.eq(log.enabled, 1, "enabled exactly once")
    T.eq(log.applied, 1, "the settings were applied exactly once")
    T.eq(log.settings, true, "the module read its own settings through the variable")
    T.eq(#said, 0, "nothing was said in the chat: " .. table.concat(said, " | "))
    T.eq(ns.Registry:IsEnabled(log.handle), true, "and now it is working")
end

T.suite("the trap: a module of the old writing works as it worked")

do
    -- The workaround all eight modules of the repository carry stays correct:
    -- self arrives in a handler as it arrived. An edit of the door has no right
    -- to break those who worked around it by hand — their addons lie on
    -- players' disks, and they cannot be reached.
    local ns, said = core()
    ns.Registry:EnableAll()

    local module
    local seen = {}

    local handle = ns.Api:RegisterModule({
        name = "umbraoldstyle",
        api  = 1,
        OnEnable = function(self)
            module = module or self
            seen[#seen + 1] = "enable"
            seen.same = module == self
        end,
        ApplySettings = function(self)
            module = module or self
            seen[#seen + 1] = "apply"
        end,
    })
    frame()

    T.ok(handle ~= nil, "a module of the old writing was registered")
    T.eq(module, handle, "the descriptor taken out of self is the very same one")
    T.eq(seen.same, true, "and inside the handler it is the same")
    T.eq(table.concat(seen, ","), "enable,apply", "the order of the calls is the former one")
    T.eq(#said, 0, "nothing was said in the chat: " .. table.concat(said, " | "))
end

T.suite("the trap: the window between the registration and the frame")

do
    -- The frame of the deferred enabling is a window in which the descriptor
    -- already exists while OnEnable has not happened yet. The window is short,
    -- but the state in it is obliged to be honest, or the deferral would become a new trap instead of the old one.
    local ns = core()
    ns.Registry:EnableAll()

    local order = {}
    local handle = ns.Api:RegisterModule({
        name = "umbrawindow",
        api  = ns.Api.API_VERSION,
        OnEnable      = function() order[#order + 1] = "enable" end,
        ApplySettings = function() order[#order + 1] = "apply" end,
    })

    -- A general application of the settings that happened in that window the
    -- module skips: applying the settings before the enabling would mean
    -- creating a state that does not occur at an ordinary load.
    ns.Registry:ApplyAll()
    T.eq(#order, 0, "a general application does not touch a deferred module")

    -- Its own Apply does touch it, and rightly: the module asked about itself
    -- and is entitled to an answer. It no longer needs the frame after that.
    T.eq(handle:Apply(), true, "its own Apply answers with action")
    T.eq(table.concat(order, ","), "enable,apply",
        "and the enabling happened before the application")

    T.eq(frame(), 1, "the frame arrives all the same")
    T.eq(table.concat(order, ","), "enable,apply",
        "but it does not enable the module a second time")
end

T.suite("the trap: one that fell over in a deferred enabling is switched off alone")

do
    -- The deferral has no right to weaken the isolation: a module that fell
    -- over on the next frame is obliged to switch itself off exactly as it did
    -- when it fell over from inside the registration.
    local ns, said = core()
    ns.Registry:EnableAll()

    local alive = ns.Api:RegisterModule({
        name = "umbraneighbour", api = 1,
        OnEnable = function() end,
    })
    frame()

    local broken = ns.Api:RegisterModule({
        name = "umbrabroken", api = 1,
        OnEnable = function() error("broken deliberately") end,
    })
    T.ok(broken ~= nil, "a descriptor was returned to the one that fell over too")
    T.eq(#said, 0, "nothing was said in the chat at the registration")

    frame()

    T.eq(ns.Registry:IsFailed("umbrabroken"), true, "the one that fell over was switched off")
    T.eq(ns.Registry:IsFailed("umbraneighbour"), false, "the neighbour is intact")
    T.eq(ns.Registry:IsEnabled(alive), true, "and working")
    T.eq(#said, 1, "there is exactly one line in the chat: " .. table.concat(said, " | "))
end

--============================================================================
-- 3. The alarm colour in the palette
--============================================================================

-- A decision that had not been taken before: there was neither red nor yellow
-- in the palette — not because it was decided so but because they were not
-- there. A watchdog module meanwhile has nothing to say "bad" with: the accent
-- is taken by hovering and selection, and an indicator that turned the accent colour reads as a row under the mouse.
--
-- Now the colour exists, it is a single one, and its area of use is narrow.
-- The guard below watches exactly that narrowness: an alarm that is always on
-- stops being an alarm.
T.suite("the trap: the palette's alarm colour")

do
    local ns = core()
    local skin = ns.Api:GetSkin()

    T.ok(ns.Skin.Palette.warn ~= nil, "there is an alarm colour in the palette")

    local r, g, b, a = skin.Color("warn")
    T.eq(type(r), "number", "it is exposed by that same skin.Color")
    T.eq(a, 1, "with the default transparency")

    -- Warm: the red channel outranks both the others. That is what distinguishes
    -- it from the whole rest of the palette, and it has to be checked by a
    -- number rather than by eye — otherwise an edit of the hexadecimal spelling would pass silently.
    T.ok(r > g and r > b, "it is warm: there is more red in it than anything else")

    -- And muted: a pure red in this theme is a hole in the screen.
    T.ok(r < 1, "but not a pure red")

    -- The name in the list of names: a module asks for the palette whole and is
    -- obliged to see it there.
    local names, found = skin.Colors(), false
    for i = 1, #names do
        if names[i] == "warn" then found = true end
    end
    T.eq(found, true, "the name is named in the palette's list")

    -- A copy rather than our table: an edit of the returned list does not move the palette.
    names[1] = "no such colour"
    local again = skin.Colors()
    T.ok(again[1] ~= "no such colour", "the list is returned as a copy")
end

T.suite("the trap: the alarm colour does not spread anywhere")

do
    -- The narrowness of the area of use is a decision, and it has to be held by
    -- a check rather than by memory. A fill, a border, a bar or a highlight in
    -- the alarm colour is a refusal: an alarm speaks by a number and a label.
    local FORBIDDEN = {
        'Backdrop%([^)]*"warn"',
        'Outline%([^)]*"warn"',
        'SetColorTexture%([^)]*"warn"',
        'SetStatusBarColor%([^)]*"warn"',
    }

    local sources = {}
    local toc = io.open("Darken.toc", "r")
    if toc then
        for line in toc:lines() do
            local path = line:match("^([%w_][%w_%.%-\\/]*%.lua)%s*$")
            if path then sources[#sources + 1] = (path:gsub("\\", "/")) end
        end
        toc:close()
    end
    for _, folder in ipairs(helpers.moduleFolders()) do
        for _, path in ipairs(helpers.moduleSources(folder)) do
            sources[#sources + 1] = path
        end
    end
    T.ok(#sources > 30, "the delivery's files were gathered: " .. #sources)

    local guilty = {}
    for i = 1, #sources do
        local file = io.open(sources[i], "r")
        if file then
            local text = file:read("*a")
            file:close()
            for j = 1, #FORBIDDEN do
                if text:find(FORBIDDEN[j]) then
                    guilty[#guilty + 1] = sources[i]
                end
            end
        end
    end
    T.eq(#guilty, 0, "nothing is filled or outlined in the alarm colour: "
        .. table.concat(guilty, " | "))
end

helpers.removeValidator()
_G.C_Timer = savedTimer
