-- The tests' helper functions.
-- The WoW client passes two arguments to every file of an addon: the addon's
-- name and the shared namespace table. Outside the game that has to be
-- reproduced by hand, or the line `local ADDON, ns = ...` gets a nil and the
-- file falls over.

local helpers = {}

-- What the set of checks opened at all. The table is one for the whole run:
-- run.lua reads every check file in one Lua state, and require caches this
-- file, so what is gathered here is the union over the whole set. It is read by
-- tests/test_moduleload.lua — the one place where it is visible that nobody
-- loads a file of a module. Without such accounting an unloaded file stays
-- silent: the checks are green because nobody asked about it.
helpers.loaded = {}

function helpers.loadAddonFile(path, ns)
    local said = (path:gsub("\\", "/"))
    helpers.loaded[said] = true

    local chunk, err = loadfile(path)
    if not chunk then error("could not load " .. path .. ": " .. tostring(err), 2) end
    chunk("Darken", ns)

    -- A part's names are visible on the table passed in as well.
    --
    -- In the game a part of the addon lives on a table of its own
    -- (Core/Feature.lua): seven parts on one table would overwrite each other
    -- silently. A check, however, reads the files of ONE part at a time, there
    -- is nobody to overwrite here, and asking for its names through
    -- ns.features.auras.Layout would mean making every check know the key of
    -- the part it has already named by the file's path.
    --
    -- References are put there, not copies: these are the same tables, and an
    -- edit through either of the two names is visible to both. A name already
    -- taken is not overridden — the core the check substituted in advance
    -- matters more.
    local folder = said:match("^Features/([^/]+)/")
    local own = folder and ns.features and ns.features[folder:lower()]
    if type(own) == "table" then
        for key, value in pairs(own) do
            if ns[key] == nil then ns[key] = value end
        end
    end

    return ns
end

--============================================================================
-- A module as a separate addon: what to load and in what order
--============================================================================

--- The modules' folders, asked of the disk.
--
-- By the same means the TOC check asks for them: a list rewritten by hand falls
-- behind the repository silently, and a new module is not checked at all.
-- @return table an array of folder names in alphabetical order
function helpers.moduleFolders()
    -- The disk is asked rather than a list in the check: a list typed by hand
    -- falls behind the repository silently, and a new part is not checked at
    -- all.
    local pipe = io.popen('dir /b /ad "Features" 2>nul')
    if pipe then pipe:close() end

    local out = {}
    local names = io.popen('dir /b /ad "Features" 2>nul')
    if not names then return out end

    for line in names:lines() do
        local name = line:gsub("%s+$", "")
        if name ~= "" then out[#out + 1] = "Features/" .. name end
    end
    names:close()

    table.sort(out)
    return out
end

--- A module's files in load order, asked of its TOC.
--
-- The list is taken from the module itself rather than rewritten into the
-- check. While it was being rewritten everything was the other way round: a new
-- file of a module meant editing five check files, and that is why the bag rule
-- never became a file of its own — a list in the checks decided how the source
-- was built. The TOC is the very place the game takes the files from, and there
-- must be no other list.
-- @param folder string the module folder's name (also the addon's name)
-- @return table an array of paths relative to the module's folder, with forward
--   slashes
function helpers.moduleFiles(folder)
    -- The list is taken from the addon's TOC — the same place the game takes
    -- it from. The checks have no second list of their own and must not have
    -- one: a file forgotten in the TOC the game does not load, and a check
    -- going by a list of its own would not notice that.
    local prefix = folder:gsub("/", "\\") .. "\\"
    local out = {}

    local handle = io.open("Darken.toc", "r")
    if not handle then error("Darken.toc did not open", 2) end

    for line in handle:lines() do
        local said = line:gsub("%s+$", ""):gsub("^%s+", "")
        if said:sub(1, #prefix) == prefix then
            out[#out + 1] = said:sub(#prefix + 1):gsub("\\", "/")
        end
    end
    handle:close()

    if #out == 0 then
        error("the TOC holds no files of the part " .. tostring(folder), 2)
    end

    return out
end

--- A module's sources: everything out of its TOC except the locale files.
--
-- They are needed by the checks of the translation's completeness: a key there
-- is read out of the places ns.Localize is called, while the locales themselves
-- are not call sites but the answers to them. The list is taken from the TOC for
-- the same reason as everywhere here: written out by hand, it will fall behind
-- the module silently, and a new file with an English label will reach the
-- player untranslated — a failure not visible in a single check.
-- @param folder string the module folder's name
-- @return table an array of paths from the repository's root, in TOC order
function helpers.moduleSources(folder)
    local files = helpers.moduleFiles(folder)
    local out = {}
    for i = 1, #files do
        if not files[i]:find("^Locale/") then
            out[#out + 1] = folder .. "/" .. files[i]
        end
    end
    return out
end

--- The file a module registers itself in the core with.
-- Its name is one and the same in every module: the folder without the addon's
-- prefix. There are two prefixes while the modules have not moved out into
-- addons of their own.
-- @param folder string
-- @return string a path relative to the module's folder
function helpers.moduleEntry(folder)
    return (folder:match("([^/]+)$") or folder) .. ".lua"
end

--- A part's key from its folder's name.
--
-- The same one the part takes for itself: the files of Features/Auras call
-- core.Feature("auras"). The key is derived from the folder rather than
-- enumerated beside it: a list typed by hand falls behind the folders
-- silently.
--
-- @param folder string
-- @return string
local function FeatureKey(folder)
    return (folder:match("([^/]+)$") or folder):lower()
end

--- Load a module's files in the order of its TOC.
--
-- The order here is not a convenience but a condition: a module's files lean on
-- one another in exactly the order the TOC enumerates them, and any other order
-- falls over as though the module itself were broken.
--
-- @param folder string the module folder's name
-- @param ns table|nil the namespace; nil means create a fresh one
-- @param opts table|nil
--   opts.withRegistration = false — do not load the registering file: it
--     requires the core, and the checks of a pure part do not need it;
--   opts.skip = { ["Window.lua"] = "why" } — a refusal of a file by name. The
--     refusal names what is not loaded rather than what is: a new file of a
--     module gets into the check by itself, and the default here is "load".
-- @return table the module's namespace
function helpers.loadModule(folder, ns, opts)
    opts = opts or {}
    ns = ns or helpers.newNamespace()

    local files = helpers.moduleFiles(folder)
    local entry = helpers.moduleEntry(folder)
    local skip = opts.skip or {}

    local listed = {}
    local sawEntry = false

    for i = 1, #files do
        local rel = files[i]
        listed[rel] = true
        if rel == entry then sawEntry = true end

        local drop = skip[rel] ~= nil
            or (rel == entry and opts.withRegistration == false)
        if not drop then
            helpers.loadAddonFile(folder .. "/" .. rel, ns)
        end
    end

    if not sawEntry then
        error(folder .. ": the TOC holds no registering file " .. entry, 2)
    end

    -- A refusal of a file the module no longer holds is a refusal quietly
    -- lost: the file was renamed while the check still thinks it skips it, and
    -- what it really skips is nothing.
    for rel in pairs(skip) do
        if not listed[rel] then
            error(folder .. ": a skip is named for a file the TOC does not "
                .. "hold: " .. rel, 2)
        end
    end

    -- A part's names are visible on the shared table as well.
    --
    -- In the game a part lives on a table of its own (Core/Feature.lua): seven
    -- parts on one table would overwrite each other silently. A check, however,
    -- loads EXACTLY one part at a time, there is nobody to overwrite here,
    -- while asking for its names through ns.features.auras.Layout would mean
    -- making every check know the key of the part it has already named by its
    -- folder.
    --
    -- So the part's names are put onto the table passed in as well — as
    -- references, not copies: these are the same tables, and an edit through
    -- either of the two names is visible to both. A name already taken is not
    -- overridden: the core the check substituted in advance matters more.
    local own = ns.features and ns.features[FeatureKey(folder)]
    if type(own) == "table" then
        for key, value in pairs(own) do
            if ns[key] == nil then ns[key] = value end
        end
    end

    return ns
end

--- What the WHITE channel becomes at such a darkening multiplier.
--
-- The darkening of a bright texture is a double one. First the brightness
-- ceiling brings it down to a half-tone — otherwise the gryphons, the main bar
-- and the conversation's parchment stay twice as light as everything around
-- them at any position of the slider (Darkness.Ceiling, Darkness.Levelled).
-- Then the multiplier does the rest.
--
-- The ceiling itself depends on the strength: at the native look it equals one
-- and touches nothing, at a full darkening a half. Hence the formula.
--
-- The numbers here are our own rather than borrowed from the addon by calling
-- its own function: a check that computes what it expects with the same code it
-- checks proves only that the code equals itself.
--
-- @param factor number the area's darkening multiplier
-- @return number the expected value of a white texture's channel
function helpers.whiteAt(factor)
    return factor * (0.5 + 0.5 * factor)
end

-- A fresh namespace for every test: no state leaks between files.
function helpers.newNamespace()
    local ns = {}

    -- A namespace of its own for every part — the same one the core gives
    -- (Core/Feature.lua). A check of a pure part loads its files without the
    -- core, and without this door the very first file would fall over on a call
    -- that does not exist.
    ns.features = {}
    function ns.Feature(key)
        if type(key) ~= "string" or key == "" then
            error("a part of the addon is obliged to name itself", 2)
        end
        local own = ns.features[key]
        if own == nil then
            own = {}
            ns.features[key] = own
        end
        return own
    end

    return ns
end

-- The shared aura filter and the case folding belong to the core
-- (Core/AuraFilter.lua, Core/Casefold.lua), and the modules' files take them
-- through the contract. In the checks a module's files are read without the
-- core, so the door has to be opened before they are read, and it is opened
-- with the core's real files: a fake beside them would check a copy instead of
-- what the player sees.
--
-- The core's doors the modules' files use while reading themselves:
-- Darken:GetAuraFilter() (contract 7), Darken:GetCasefold() (contract 9) and
-- Darken:GetFormat() (contract 12). All of them are opened with the core's real
-- files and with one and the same global, because in the game the global is one
-- too: two fake Darkens in a row would overwrite each other and take away from
-- a module what the previous one opened.
--
-- Core/Compat.lua is opened here as well and for the same reason: the modules'
-- files ask the core for a group's game function (Darken:GetGameFunction,
-- contract 19) — that is how it is decided which of two spellings this client
-- reads the bags by. A fake beside it would check a copy of the layer instead
-- of the layer itself.
local CORE_FILES = { "Core/Casefold.lua", "Core/AuraFilter.lua",
    "Core/Format.lua", "Core/Compat.lua" }

-- The flavour the layer behind this door answers on behalf of. The groups of
-- game functions are declared identically for all three clients, so the choice
-- affects nothing; what matters is that it was made: without ns.flavor the layer
-- refuses to resolve anything at all, and it refuses by failing.
local DOOR_FLAVOR = "vanilla"

--- Open the core's door for a module's files read outside the game.
-- @return table the object behind the Darken global
-- @return function restore the global as it was
function helpers.installCore()
    local previous = _G.Darken

    -- The real core is already in place — we take it and touch nothing:
    -- replacing the global here would take the registration itself away from
    -- the module's files.
    if type(previous) == "table"
        and type(previous.GetAuraFilter) == "function"
        and type(previous.GetCasefold) == "function"
        and type(previous.GetGameFunction) == "function"
        and type(previous:GetAuraFilter()) == "table"
        and type(previous:GetCasefold()) == "table" then
        return previous, function() end
    end

    local core = helpers.newNamespace()
    for i = 1, #CORE_FILES do helpers.loadAddonFile(CORE_FILES[i], core) end
    core.flavor = DOOR_FLAVOR

    _G.Darken = {
        GetAuraFilter = function() return core.AuraFilter end,
        GetCasefold   = function() return core.Casefold end,
        GetFormat     = function() return core.Format end,

        -- The same door as in Core/Api.lua and in the same words: the layer
        -- is the real one, and the wrapper only repeats the guard against
        -- failure.
        GetGameFunction = function(_, group, shape)
            local ok, fn, found, path = pcall(
                core.Compat.ResolveFunction, group, shape)
            if not ok or type(fn) ~= "function" then return nil end
            return fn, found, path
        end,
    }

    return _G.Darken, function() _G.Darken = previous end
end

--- A door to the game's functions over an invented client.
--
-- Needed by the checks that build a client as a table rather than by editing
-- _G: a module asks the core for a game function, and the core in the game
-- looks into _G. The layer here is the real one (Compat.FindFunction is a pure
-- function, the dictionary arrives as an argument); only the dictionary is
-- fake.
--
-- @param globals table a dictionary of name -> object: the invented client
-- @param flavor string|nil the flavour; by default the same as the core door's
-- @return function a door of the form door(group, shape) -> function, shape,
--   path
function helpers.gameDoor(globals, flavor)
    local core = helpers.newNamespace()
    helpers.loadAddonFile("Core/Compat.lua", core)

    return function(group, shape)
        return core.Compat.FindFunction(globals, flavor or DOOR_FLAVOR,
            group, shape)
    end
end

--- The core's aura filter behind an opened door.
--
-- What is returned is the filter itself — it is also what proves a module took
-- the core's rather than creating one of its own — and a function restoring the
-- global to its former state.
-- @return table the core's aura filter
-- @return function restore the global as it was
function helpers.installAuraFilter()
    local door, restore = helpers.installCore()
    return door:GetAuraFilter(), restore
end

--- The core's number formatting behind an opened door.
--
-- By the same means and for the same reason: the bar labels and the info
-- panel's cells write a large number and a percentage by one rule of the core's
-- (Core/Format.lua), and the only way to check that no copy has appeared beside
-- it is with the real one.
-- @return table the core's number formatting
-- @return function restore the global as it was
function helpers.installFormat()
    local door, restore = helpers.installCore()
    return door:GetFormat(), restore
end

--- The core's case folding behind an opened door.
--
-- By the same means and for the same reason: the search in the bags and the
-- item database's query language fold case with the core's table
-- (Core/Casefold.lua), and the only way to check that no copy has appeared
-- beside it is with the real one.
-- @return table the core's case folding
-- @return function restore the global as it was
function helpers.installCasefold()
    local door, restore = helpers.installCore()
    return door:GetCasefold(), restore
end

-- The public layer refuses a module with a settings section when there is
-- nothing to validate that section with: AceConfigRegistry-3.0 is obliged to be
-- present in an installation, and "the validation was skipped" is the worst
-- possible answer. Outside the game there is no LibStub global, so the check
-- files that register modules with a section need a stand-in for it.
--
-- The stand-in accepts any tree deliberately: the library's real rules are
-- checked where the library is the real one (tests/test_acevalidate.lua), while
-- here all that is needed is to pass through the door. LibStub is a table with
-- a __call metamethod, and the fake repeats that build: a check of "what if it
-- is a function" once cost one silently non-working subsystem.
function helpers.installValidator()
    local registry = { ValidateOptionsTable = function() return true end }
    local libs = { ["AceConfigRegistry-3.0"] = registry }

    _G.LibStub = setmetatable({}, {
        __call = function(_, name) return libs[name] end,
    })

    return registry
end

-- Removed at the end of a file: the next set must not see the stand-in, while
-- tests/test_acevalidate.lua loads the real LibStub over an empty place.
function helpers.removeValidator()
    _G.LibStub = nil
end

return helpers
