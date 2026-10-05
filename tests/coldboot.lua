-- A cold boot of the addon: the same thing the client does at login.
--
-- Why this file exists. Every subsystem is checked separately, but the addon
-- as a whole has never been brought up outside the client: the core by its
-- own TOC, nine modules by theirs, the real libraries from Libs/, empty
-- saved variables -- and all of it in the order the game reads the files in.
-- No subsystem check can see a failure of such a boot: it loads exactly the
-- files it needs, in exactly the order that suits it.
--
-- Here the file list is never written by hand. The core comes from its own
-- TOC, a module from its own, the libraries from Libs/Libs.xml. A list
-- copied into a check falls behind the repository silently, and that has
-- already happened in this project (see tests/helpers.lua).
--
-- An honest boundary. This is not the game. There is no frame engine here,
-- no protected code, no combat and no event order of a real client. The
-- frame stub answers any method -- which means a typo in a frame method name
-- is invisible here and visible only in the client. What the harness catches
-- and what it does not is listed in .superpowers/sdd/cold-boot/report.md.

local helpers = require("helpers")

local coldboot = {}

--============================================================================
-- What to load: we ask the disk, not ourselves
--============================================================================

--- The .lua files listed in a TOC, in TOC order.
-- @param path string the path to the TOC file
-- @return table an array of paths with forward slashes
function coldboot.tocFiles(path)
    local handle = io.open(path, "r")
    if not handle then error("could not open " .. path, 2) end

    local list = {}
    for line in handle:lines() do
        local rel = line:match("^%s*([%w_][%w_%.%-\\/]*%.lua)%s*$")
        if rel then list[#list + 1] = (rel:gsub("\\", "/")) end
    end
    handle:close()

    if #list == 0 then
        error(path .. " lists not a single file", 2)
    end
    return list
end

--- The interface numbers from the "## Interface:" line of this TOC.
-- @param path string
-- @return table an array of numbers in declaration order
function coldboot.tocInterfaces(path)
    local handle = io.open(path, "r")
    if not handle then error("could not open " .. path, 2) end

    local out = {}
    for line in handle:lines() do
        local list = line:match("^%s*##%s*Interface%s*:%s*(.+)$")
        if list then
            for number in list:gmatch("%d+") do
                out[#out + 1] = tonumber(number)
            end
            break
        end
    end
    handle:close()

    if #out == 0 then
        error(path .. " has no ## Interface: line", 2)
    end
    return out
end

--- The core TOC files, asked of the disk.
-- There are four, and that is no coincidence: the client of every flavour gets its own.
-- @return table an array of file names in alphabetical order
function coldboot.coreTocs()
    local pipe = io.popen('dir /b "Darken*.toc" 2>nul')
    if not pipe then return {} end

    local out = {}
    for line in pipe:lines() do
        local name = line:gsub("%s+$", "")
        if name ~= "" then out[#out + 1] = name end
    end
    pipe:close()
    table.sort(out)
    return out
end

--- The library files in the order of Libs/Libs.xml, descending through Include.
--
-- The order here is a requirement, not a convenience: AceAddon requires
-- CallbackHandler to be loaded already, AceConfig requires AceGUI, and any
-- other order fails as if a library were broken.
-- @param path string|nil the path to the xml (Libs/Libs.xml by default)
-- @return table an array of .lua paths
function coldboot.libFiles(path)
    path = path or "Libs/Libs.xml"

    local handle = io.open(path, "r")
    if not handle then error("could not open " .. path, 2) end
    local text = handle:read("*a")
    handle:close()

    -- A commented-out Include is a file the game does not load. Reading it
    -- as live, the harness would fail on a missing file and would call that a
    -- failure of the addon (which is what happened on the first run:
    -- AceConfigDropdown is commented out and is not on disk).
    text = text:gsub("<!%-%-.-%-%->", "")

    local dir = path:match("^(.*)/[^/]+$") or "."
    local out = {}

    for tag, file in text:gmatch("<(%a+)%s+file%s*=%s*\"([^\"]+)\"") do
        local rel = (file:gsub("\\", "/"))
        local full = dir .. "/" .. rel
        if tag == "Script" then
            out[#out + 1] = full
        elseif tag == "Include" then
            local nested = coldboot.libFiles(full)
            for i = 1, #nested do out[#out + 1] = nested[i] end
        end
    end

    if #out == 0 then
        error(path .. " yielded not a single file", 2)
    end
    return out
end

--- The module folders, asked of the disk. The same ones the game sees.
-- @return table an array of folder names in alphabetical order
function coldboot.moduleFolders()
    return helpers.moduleFolders()
end

--- The contract version a module declares in its own source.
--
-- It is read from the module file rather than copied here: a list of
-- versions in a check is a second declaration of the contract, and it diverges silently.
-- @param folder string the module folder name
-- @return number|nil
function coldboot.declaredApi(folder)
    local path = folder .. "/" .. helpers.moduleEntry(folder)
    local handle = io.open(path, "r")
    if not handle then return nil end

    local found
    for line in handle:lines() do
        local value = line:match("^local%s+API%s*=%s*(%d+)%s*$")
        if value then
            found = tonumber(value)
            break
        end
    end
    handle:close()
    return found
end

--============================================================================
-- The client stub
--============================================================================

-- An object that has every method and whose every method returns another such object.
-- The design is taken from tests/test_acedialog.lua for the same reason: the
-- addon and library code walks chains like
-- button:GetNormalTexture():SetTexCoord(...), and a stub returning nil would cut the load short at the first such line.
--
-- The price is stated out loud: a typo in a frame method name is invisible
-- here. That is a boundary of the harness rather than an oversight -- there
-- is nothing to reproduce the frame engine with outside the client, and a
-- fake "with a list of allowed methods" would be checking our list rather than the game.
local function widget(name)
    local self

    -- The dummy returned by chains like GetNormalTexture():SetTexCoord().
    -- One per stub, created lazily: formerly every such call gave birth to a
    -- new object with a couple of dozen closures, and a combat frame in the
    -- cost measurement consisted of stub garbage rather than of the addon's work.
    local empty
    local function void()
        if empty == nil then empty = widget(nil) end
        return empty
    end

    self = setmetatable({
        stubName = name,
        events = {},
        scripts = {},
    }, {
        __index = function(t, key)
            if key == "GetName" then return function() return name end end

            -- We answer only to engine method names: they are all capitalised
            -- (SetPoint, GetWidth, CreateTexture). A data field is written in
            -- lower case (frame.unit, options.width), and returning a
            -- function for one is not allowed: on the very first run three
            -- subsystems fell over on `base.width`, where base was not our
            -- table but the stub. The failure was invented yet looked real.
            if type(key) ~= "string" or not key:match("^%u") then
                return nil
            end

            -- Touching a game frame is the whole reason the tally exists
            -- here. A fresh install must change nothing, and the only way to
            -- say that about the whole addon at once is to count what it
            -- touched. Reads (Get/Is/Has) do not count: they change nothing.
            --
            --
            -- Only game frames are counted. The addon and the libraries
            -- create and edit their own frames as much as they like -- that
            -- IS their work; a tally without that distinction would show
            -- AceGUI widgets and would show nothing useful.
            -- The kind of a name is decided once per name, not per call. The
            local reads = key:match("^Get") or key:match("^Is")
                or key:match("^Has")

            local method = function(_, ...)
                local sink = coldboot.touched
                local game = coldboot.gameFrames
                if sink and name and not reads and game and game[name] then
                    local args = {}
                    for i = 1, select("#", ...) do
                        args[i] = tostring((select(i, ...)))
                    end
                    sink[#sink + 1] = {
                        frame = name, method = key,
                        args = table.concat(args, ","),
                    }
                end
                return void()
            end

            -- method is put straight into the table: otherwise __index would
            -- be called on every access and would create the closure anew.
            -- The cold boot does not care; the cost measurement does.
            rawset(t, key, method)
            return method
        end,
    })

    self.RegisterEvent = function(_, event) self.events[event] = true end
    self.UnregisterEvent = function(_, event) self.events[event] = nil end
    self.UnregisterAllEvents = function() self.events = {} end
    self.SetScript = function(_, key, fn) self.scripts[key] = fn end
    self.GetScript = function(_, key) return self.scripts[key] end
    self.HookScript = function(_, key, fn) self.scripts[key] = fn end
    self.IsEventRegistered = function(_, event) return self.events[event] end
    self.GetWidth = function() return 1920 end
    self.GetHeight = function() return 1080 end
    self.GetEffectiveScale = function() return 1 end
    self.GetScale = function() return 1 end
    -- The fake frame is shown.
    --
    -- Formerly it answered "hidden", and that did not matter while nobody
    -- asked. Now the darkening asks: it does not walk hidden things at all
    -- (they are invisible yet cost the same). A stub answering "hidden"
    -- turned the whole fake scene into an empty room.
    self.IsShown = function() return true end
    self.IsVisible = function() return true end
    self.IsProtected = function() return false end
    self.IsForbidden = function() return false end
    self.GetObjectType = function() return "Frame" end
    self.GetNumPoints = function() return 0 end
    self.GetPoint = function() return nil end
    self.GetText = function() return "" end
    self.GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end
    -- The stub deliberately has no parent: a "climb while there is a parent"
    -- loop would never end on an infinite chain.
    self.GetParent = function() return nil end
    self.GetChildren = function() return end
    self.GetRegions = function() return end
    self.AddMessage = function(_, text)
        local sink = coldboot.chat
        if sink then sink[#sink + 1] = tostring(text) end
    end

    return self
end

coldboot.widget = widget

-- The names of the client globals the stub creates. The list is explicit: a
-- nil in the snapshot table is indistinguishable from a missing key, and a
-- pairs walk would leave the stub to the next check file.
local CLIENT_GLOBALS = {
    "CreateFrame", "UIParent", "WorldFrame", "DEFAULT_CHAT_FRAME",
    "geterrorhandler", "hooksecurefunc", "securecall", "securecallfunction",
    "issecurevariable", "InCombatLockdown", "IsLoggedIn", "GetTime",
    "GetBuildInfo", "GetLocale", "GetRealmName", "GetCurrentRegionName",
    "GetCurrentRegion", "UnitName", "UnitClass", "UnitRace",
    "UnitFactionGroup", "UnitLevel", "UnitExists", "UnitGUID",
    "UnitAffectingCombat", "UnitIsUnit", "UnitHealth", "UnitHealthMax",
    "UnitPower", "UnitPowerMax", "UnitPowerType", "strlenutf8", "wipe",
    "strsplit", "strtrim", "strjoin", "strmatch", "strfind", "strlower",
    "strupper", "strrep", "strbyte", "strchar", "strconcat", "tinsert",
    "tremove", "tContains", "max", "min", "abs", "floor", "ceil", "format",
    "date", "time", "GetAddOnMetadata", "C_AddOns", "C_Timer", "C_CVar",
    "GetCVar", "SetCVar", "GetCVarBool", "SlashCmdList", "hash_SlashCmdList",
    "ShowUIPanel", "HideUIPanel", "InterfaceOptions_AddCategory", "Settings",
    "LibStub", "Darken", "DarkenDB", "Enum", "CopyTable", "Mixin",
    "GetPetHappiness", "GetContainerNumSlots", "C_Container", "GetItemInfo",
    "C_GameRules",
    "C_Item", "GetSpellInfo", "C_Spell", "GetNumShapeshiftForms",
    "GetScreenWidth", "GetScreenHeight", "IsAddOnLoaded", "print",
}
coldboot.CLIENT_GLOBALS = CLIENT_GLOBALS

--- Take a snapshot of the client globals so they can be put back later.
-- @return table
function coldboot.saveGlobals()
    local saved = { tableWipe = table.wipe }
    for i = 1, #CLIENT_GLOBALS do
        saved[CLIENT_GLOBALS[i]] = _G[CLIENT_GLOBALS[i]]
    end
    return saved
end

--- Restore the globals as they were.
-- @param saved table the snapshot from coldboot.saveGlobals
function coldboot.restoreGlobals(saved)
    for i = 1, #CLIENT_GLOBALS do
        _G[CLIENT_GLOBALS[i]] = saved[CLIENT_GLOBALS[i]]
    end
    -- table.wipe lives not in _G but in the table table, and is not restored
    -- by the common pass: forgotten, it would stay for the next check file.
    table.wipe = saved.tableWipe
end

--- Create the client globals anew for one load.
-- @param opts table
--   opts.interface number the interface number GetBuildInfo returns
--   opts.locale string|nil the client language
--   opts.class string|nil the player class token
--   opts.chat table where to collect the lines that went to chat
--   opts.errors table where to collect what geterrorhandler caught
--   opts.frames table|nil the names of the game frames that exist
-- @return table the AceAddon frame (the one ADDON_LOADED hangs on)
local function installClient(opts)
    local chat, errors = opts.chat, opts.errors
    coldboot.chat = chat
    coldboot.touched = opts.touched

    -- The set of game frame names: the tally uses it to tell a foreign frame
    -- from ours. Empty means "this client has no game frames" -- and then
    -- there is nothing to touch.
    local gameFrames = {}
    if opts.frames then
        for i = 1, #opts.frames do gameFrames[opts.frames[i]] = true end
    end
    coldboot.gameFrames = gameFrames

    for i = 1, #CLIENT_GLOBALS do _G[CLIENT_GLOBALS[i]] = nil end

    local created = {}

    -- Work deferred to the next frame. A queue stub rather than a no-op, and
    -- the difference is substantive: the core defers through C_Timer.After(0)
    -- the enabling of a module that arrived at an already running addon
    -- (Core/Registry.lua, EnableLater), and a stub dropping the call on the
    -- floor would be checking a world with no frames, that is a world the player does not have.
    --
    -- A frame does not arrive by itself here: whoever boots the addon pumps
    -- it (result.pump). That way the event order stays the subject of the
    -- check rather than a side effect of when exactly a timer fired.
    local timers = {}

    _G.CreateFrame = function(_, name)
        local frame = widget(name)
        created[#created + 1] = frame
        if name then _G[name] = frame end
        return frame
    end

    _G.UIParent = widget("UIParent")
    _G.WorldFrame = widget("WorldFrame")
    _G.DEFAULT_CHAT_FRAME = widget("ChatFrame1")

    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        chat[#chat + 1] = table.concat(parts, " ")
    end

    _G.geterrorhandler = function()
        return function(err)
            errors[#errors + 1] = tostring(err)
        end
    end

    _G.hooksecurefunc = function(target, key, fn)
        if type(target) == "string" then target, key, fn = _G, target, key end
        local previous = target[key]
        if type(previous) ~= "function" then return end
        target[key] = function(...)
            local results = { previous(...) }
            pcall(fn, ...)
            return unpack(results)
        end
    end
    _G.securecall = function(fn, ...)
        if type(fn) == "string" then fn = _G[fn] end
        return fn(...)
    end
    _G.securecallfunction = function(fn, ...) return fn(...) end
    _G.issecurevariable = function() return false end

    _G.InCombatLockdown = function() return false end
    _G.IsLoggedIn = function() return false end
    _G.GetTime = function() return 1000 end

    local interface = opts.interface
    _G.GetBuildInfo = function()
        return "1.15.7", "69977", "Jan 1 2026", interface
    end
    _G.GetLocale = function() return opts.locale or "enUS" end
    _G.GetRealmName = function() return "Test Realm" end
    _G.GetCurrentRegionName = function() return "EU" end
    _G.GetCurrentRegion = function() return 3 end

    _G.UnitName = function() return "Tester" end
    _G.UnitClass = function()
        local token = opts.class or "HUNTER"
        return token, token
    end
    _G.UnitRace = function() return "Human", "Human" end
    _G.UnitFactionGroup = function() return "Alliance" end
    _G.UnitLevel = function() return 60 end
    _G.UnitExists = function() return false end
    _G.UnitGUID = function() return "Player-0-0000" end
    _G.UnitAffectingCombat = function() return false end
    _G.UnitIsUnit = function() return false end
    _G.UnitHealth = function() return 100 end
    _G.UnitHealthMax = function() return 100 end
    _G.UnitPower = function() return 100 end
    _G.UnitPowerMax = function() return 100 end
    _G.UnitPowerType = function() return 0, "MANA" end

    _G.strlenutf8 = function(text) return #text end
    _G.wipe = function(t)
        for key in pairs(t) do t[key] = nil end
        return t
    end
    table.wipe = _G.wipe
    _G.strsplit = function(sep, text)
        local out = {}
        for part in tostring(text):gmatch("[^" .. sep .. "]+") do
            out[#out + 1] = part
        end
        return unpack(out)
    end
    _G.strtrim = function(text) return (tostring(text):gsub("^%s+", "")
        :gsub("%s+$", "")) end
    _G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    _G.strmatch = string.match
    _G.strfind = string.find
    _G.strlower = string.lower
    _G.strupper = string.upper
    _G.strrep = string.rep
    _G.strbyte = string.byte
    _G.strchar = string.char
    _G.strconcat = function(...) return table.concat({ ... }) end
    _G.tinsert = table.insert
    _G.tremove = table.remove
    _G.tContains = function(list, value)
        for i = 1, #list do if list[i] == value then return true end end
        return false
    end
    _G.max, _G.min, _G.abs = math.max, math.min, math.abs
    _G.floor, _G.ceil = math.floor, math.ceil
    _G.format = string.format
    _G.date, _G.time = os.date, os.time

    _G.GetAddOnMetadata = function() return nil end
    _G.C_AddOns = {
        GetAddOnMetadata = function() return nil end,
        IsAddOnLoaded = function() return false end,
    }
    _G.IsAddOnLoaded = function() return false end
    _G.C_Timer = {
        After = function(_, fn)
            if type(fn) == "function" then timers[#timers + 1] = fn end
        end,
        NewTimer = function() return widget(nil) end,
        NewTicker = function() return widget(nil) end,
    }
    _G.C_CVar = { GetCVar = function() return nil end, SetCVar = function() end }
    _G.GetCVar = function() return nil end
    _G.SetCVar = function() end
    _G.GetCVarBool = function() return false end
    _G.SlashCmdList = {}
    _G.hash_SlashCmdList = {}
    _G.ShowUIPanel = function() end
    _G.HideUIPanel = function() end
    -- Classic 1.16 (interface 16001) asks the world rules right inside
    -- AceDB: without that pair the library load fails before the addon even
    -- starts. The client has them; outside the client they must be created,
    -- or the harness would declare its own incompleteness a library failure.
    _G.Enum = {
        GameRule = { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 },
    }
    _G.C_GameRules = { IsGameRuleActive = function() return false end }
    _G.CopyTable = function(source)
        local out = {}
        for key, value in pairs(source) do
            out[key] = type(value) == "table" and _G.CopyTable(value) or value
        end
        return out
    end
    _G.Mixin = function(target, ...)
        for i = 1, select("#", ...) do
            for key, value in pairs((select(i, ...))) do target[key] = value end
        end
        return target
    end
    _G.GetScreenWidth = function() return 1920 end
    _G.GetScreenHeight = function() return 1080 end
    _G.GetContainerNumSlots = function() return 0 end
    _G.C_Container = {
        GetContainerNumSlots = function() return 0 end,
        GetContainerItemInfo = function() return nil end,
        GetContainerItemLink = function() return nil end,
    }
    _G.GetItemInfo = function() return nil end
    _G.C_Item = { GetItemInfo = function() return nil end }
    _G.GetSpellInfo = function() return nil end
    _G.C_Spell = { GetSpellInfo = function() return nil end }
    _G.GetNumShapeshiftForms = function() return 0 end

    -- Pet happiness does not exist on every client, and the feeding module
    -- refuses to register where the function is absent. That is its own
    -- rule, and the harness does not interfere: the function is created
    -- exactly when it is asked for.
    if opts.petHappiness then
        _G.GetPetHappiness = function() return 3, 1, 1 end
    end

    -- The page in the game settings. Its table does not exist on TBC Classic,
    -- and Core/Init.lua survives that out loud -- the stub gives both sides.
    if opts.settingsPanel then
        _G.Settings = {
            RegisterCanvasLayoutCategory = function()
                return { ID = 1 }
            end,
            RegisterAddOnCategory = function() end,
        }
    end
    _G.InterfaceOptions_AddCategory = function() end

    -- The game frames. Their names are taken from the compatibility layer
    -- rather than written here: a list of names in a check would diverge from
    -- the list in Core/Compat.lua just as silently as the file lists did.
    if opts.frames then
        for i = 1, #opts.frames do
            local name = opts.frames[i]
            if _G[name] == nil then _G[name] = widget(name) end
        end
    end

    return created, timers
end

--- The game frame names for a flavour: asked of the compatibility layer itself.
-- @param flavor string
-- @return table an array of names
function coldboot.frameNames(flavor)
    local probe = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", probe)

    local seen, out = {}, {}
    local groups = probe.Compat.Groups(flavor)
    for i = 1, #groups do
        local names = probe.Compat.GetFrameNames(flavor, groups[i])
        for j = 1, #names do
            if not seen[names[j]] then
                seen[names[j]] = true
                out[#out + 1] = names[j]
            end
        end
    end
    table.sort(out)
    return out
end

--============================================================================
-- The boot itself
--============================================================================

--- Boot the addon the way the client does.
--
-- @param opts table
--   opts.toc string the core TOC file name (required)
--   opts.interface number the client interface number (required)
--   opts.saved table|nil the contents of DarkenDB from SavedVariables; nil means empty
--   opts.modules boolean|table whether to load the modules from separate
--     folders; a table means "only these folders"
--   opts.frames boolean whether to create the game frames (yes by default)
--   opts.class string|nil the player class token
--   opts.petHappiness boolean|nil whether the client has pet happiness
--   opts.settingsPanel boolean|nil whether the Settings table exists
--   opts.client function|nil a finishing touch for the client stub: called
--     with result after the globals are created and before the libraries are read
--   opts.breakModule string|nil the folder of the module whose OnEnable is
--     replaced by a failing one -- that is how it is checked that a neighbour survives a failure
-- @return table the result of the boot
function coldboot.boot(opts)
    assert(type(opts) == "table", "coldboot.boot: parameters are required")
    assert(type(opts.toc) == "string", "coldboot.boot: a toc is required")
    assert(type(opts.interface) == "number", "coldboot.boot: an interface is required")

    local result = {
        chat = {},
        errors = {},
        touched = {},
        modules = {},
        sv = opts.saved or {},
        toc = opts.toc,
        interface = opts.interface,
    }

    local probe = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", probe)
    result.flavor = probe.Compat.DetectFlavor(opts.interface)

    local frames = nil
    if opts.frames ~= false then
        frames = coldboot.frameNames(result.flavor)
    end

    local saved = coldboot.saveGlobals()

    -- What was in the globals before the boot. The addon and the libraries
    -- create dozens of them (frames by name, slash command words, the
    -- libraries themselves), and leaving them to the next check file would
    -- mean checking it in a world where the addon is already up. The boot must clean up after itself completely.
    local before = {}
    for key in pairs(_G) do before[key] = true end

    result.restore = function()
        local strays = {}
        for key in pairs(_G) do
            if not before[key] then strays[#strays + 1] = key end
        end
        for i = 1, #strays do _G[strays[i]] = nil end
        coldboot.restoreGlobals(saved)
        coldboot.chat, coldboot.touched = nil, nil
        coldboot.gameFrames = nil
    end

    local created, timers = installClient({
        interface     = opts.interface,
        locale        = opts.locale,
        class         = opts.class,
        chat          = result.chat,
        errors        = result.errors,
        touched       = result.touched,
        frames        = frames,
        petHappiness  = opts.petHappiness,
        settingsPanel = opts.settingsPanel,
    })

    result.created = created

    --- Pump the frames the addon deferred work to.
    --
    -- The client does it by itself and every frame; here the caller does it,
    -- deliberately: the cold boot checks the event order, and the order must
    -- be visible in the text of the check rather than depend on a clock.
    --
    -- It pumps until empty, but not forever: work that defers itself would
    -- burn frames silently in the client, and here it must be named a failure
    -- rather than hang the suite.
    -- @return number how much deferred work ran
    result.pump = function()
        local done = 0
        while #timers > 0 do
            -- The queue is edited in place: the C_Timer.After closure holds
            -- exactly this table, and replacing it with a new one would mean
            -- losing everything deferred afterwards.
            local fn = table.remove(timers, 1)
            done = done + 1
            if done > 256 then
                error("the deferred work never ends: 256 calls in a row", 2)
            end

            local ok, err = pcall(fn)
            if not ok then result.errors[#result.errors + 1] = tostring(err) end
        end
        return done
    end

    -- Finishing the client stub into the client the caller needs. Called here
    -- and only here: after the globals are created and before the first
    -- library file is read, that is at the one moment when an edit to a
    -- global is still visible to the whole addon. The cost measurement needs
    -- it: there the client must hand out real data (thirty nameplates, auras
    -- on the party, a cast in progress) rather than emptiness.
    if type(opts.client) == "function" then opts.client(result) end

    --- Logging out: the same event and the same handlers as in the client.
    -- Everything subscribed to it is called (AceDB subscribes its own frame)
    -- rather than a retelling of the library body in our own words: a
    -- retelling would diverge from the library on its first update.
    -- @return number how many handlers responded
    result.logout = function()
        local called = 0
        for i = 1, #created do
            local frame = created[i]
            if frame.events["PLAYER_LOGOUT"] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame, "PLAYER_LOGOUT")
                called = called + 1
            end
        end
        return called
    end

    _G.DarkenDB = result.sv

    -- The libraries: the whole of Libs/Libs.xml, in its order.
    local libs = coldboot.libFiles()
    local okLibs, libErr = pcall(function()
        for i = 1, #libs do dofile(libs[i]) end
    end)
    if not okLibs then
        result.restore()
        error("the libraries did not come up: " .. tostring(libErr), 2)
    end

    -- The core: every file of its own TOC, in TOC order.
    --
    -- The parts of the addon (the Features folder) are listed in the same TOC
    -- and are read by the same read: in the game this is one addon, and a
    -- part has no ADDON_LOADED event of its own. Formerly every part was a
    -- separate addon and the boot read it separately; leaving that as it was
    -- would mean reading it TWICE -- the second time the registry answers
    -- "the name is taken", and that is exactly what it answered.
    --
    -- The files of a part are deferred in exactly two cases: it was not asked
    -- for at all (opts.modules), or it was asked to arrive after entering the
    -- world (opts.lateModules). Both are about order, not about what a part
    -- is.
    local ns = helpers.newNamespace()
    result.ns = ns

    local wanted = nil
    if opts.modules == nil or opts.modules == false then
        wanted = {}
    elseif type(opts.modules) == "table" then
        wanted = {}
        for i = 1, #opts.modules do wanted[opts.modules[i]] = true end
    end

    --- Which part a TOC file belongs to.
    -- @param path string the file path from the addon root
    -- @return string|nil the folder of the part
    local function featureOf(path)
        return path:match("^(Features/[^/]+)/")
    end

    local core, late, lateOrder = {}, {}, {}
    for _, path in ipairs(coldboot.tocFiles(opts.toc)) do
        local folder = featureOf(path)
        if folder == nil then
            core[#core + 1] = path
        elseif wanted ~= nil and not wanted[folder] then
            -- The part does not exist in this build at all.
        elseif opts.lateModules then
            if late[folder] == nil then
                late[folder] = {}
                lateOrder[#lateOrder + 1] = folder
            end
            late[folder][#late[folder] + 1] = path
        else
            core[#core + 1] = path
        end
    end

    --- Read a file and notice what it declared to the registry.
    --
    -- Which registry name belongs to which part is a question with no answer
    -- from outside: a part declares its name itself, and a "folder -> name"
    -- table in a check would be a third declaration of the same thing. So the
    -- name is not guessed but noticed: whatever appeared in the registry while
    -- the files of this folder were read is what this folder declared.
    --
    -- @param path string the file path from the addon root
    -- @param folder string|nil the folder of the part, if the file belongs to one
    local function readFile(path, folder)
        if folder == nil then
            helpers.loadAddonFile(path, ns)
            return
        end

        local registry = ns.Registry
        local before = {}
        if registry then
            for _, name in registry:Each() do before[name] = true end
        end

        local own = result.modules[folder]
        if own == nil then
            own = { loaded = true, names = {} }
            result.modules[folder] = own
        end

        -- A part that breaks on enabling: what is replaced is not our code
        -- but what the part hands to the core. It is precisely its OnEnable
        -- that must be broken -- the core promises to survive its failure.
        local breaking = opts.breakModule == folder
            and path:sub(-#helpers.moduleEntry(folder)) == helpers.moduleEntry(folder)

        local realRegister
        if breaking and type(_G.Darken) == "table" then
            realRegister = _G.Darken.RegisterModule
            _G.Darken.RegisterModule = function(api, descriptor)
                if descriptor == nil then api, descriptor = _G.Darken, api end
                descriptor.OnEnable = function()
                    error(folder .. ": a failure on enabling, deliberately")
                end
                return realRegister(api, descriptor)
            end
        end

        local okFile, fileErr = pcall(helpers.loadAddonFile, path, ns)

        if realRegister then _G.Darken.RegisterModule = realRegister end

        if not okFile then
            own.loaded = false
            own.err = tostring(fileErr)
        end

        if registry then
            for _, name in registry:Each() do
                if not before[name] then own.names[#own.names + 1] = name end
            end
        end

        -- The part's own namespace is the same one its files work on: the
        -- checks read that rather than the shared table of the addon.
        local key = (folder:match("([^/]+)$") or folder):lower()
        own.ns = (ns.features and ns.features[key]) or ns
    end

    local okCore, coreErr = pcall(function()
        for i = 1, #core do
            -- Libs.xml does not appear in the TOC file list (only .lua does),
            -- so no separate filtering is needed.
            readFile(core[i], featureOf(core[i]))
        end
    end)
    result.coreLoaded = okCore
    result.coreError = not okCore and tostring(coreErr) or nil
    if not okCore then
        result.restore()
        return result
    end

    local frame = LibStub("AceAddon-3.0").frame
    result.aceFrame = frame
    local fire = frame:GetScript("OnEvent")
    result.fire = function(event, arg1) fire(frame, event, arg1) end

    -- The order here is the subject of the check itself, and it is taken from
    -- the client rather than from convenience. The game first reads the files
    -- of all addons, sends each its own ADDON_LOADED, and only then, when the
    -- world already exists, PLAYER_LOGIN. Before PLAYER_LOGIN IsLoggedIn()
    -- answers "no", and AceAddon therefore initialises the addon without enabling it.
    --
    -- The order "enable the core, then bring the modules" is a different case
    -- (a module arrived at a running core), and it is checked separately:
    -- opts.lateModules.
    result.fire("ADDON_LOADED", "Darken")
    result.addon = ns.Addon

    -- The parts asked to arrive after entering the world. The contract
    -- promises this path (Api:RegisterModule defers the enabling to a frame),
    -- and it has a trouble of its own: by that moment the core has already
    -- tinted its frames. For our own parts this does not happen in the game
    -- -- they lie in the same TOC as the core -- but the promise was given to foreign modules, and it is checked on our own.
    local function loadLate(folder)
        local files = late[folder]
        for i = 1, #files do readFile(files[i], folder) end
        result.fire("ADDON_LOADED", folder)
    end

    -- The last thing that can be done before entering the world. It is needed
    -- for the same reason as opts.lateModules: both legitimate registration
    -- orders are checked, and this one is "the module is already here while the core has enabled nobody yet".
    if type(opts.beforeLogin) == "function" then opts.beforeLogin(result) end

    -- Entering the world.
    _G.IsLoggedIn = function() return true end
    result.fire("PLAYER_LOGIN")
    result.pump()

    -- A part that arrived at an already running core.
    for i = 1, #lateOrder do loadLate(lateOrder[i]) end

    -- The frame the core deferred the enabling of the late arrivals to.
    -- Without it the check would be judging a world in which frames do not exist.
    result.pump()

    return result
end

return coldboot
