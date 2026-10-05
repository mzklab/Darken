local helpers = require("helpers")

-- A file of a module not one check reads.
--
-- This refusal mirrors the one tests/test_moduletoc.lua guards. There it is a
-- file forgotten in the TOC: it is on the disk but the game does not load it.
-- Here it is a file forgotten by the set of checks: the game loads it while
-- nobody tries to check what it does. Both troubles are quiet ones, and the
-- second is quieter than the first: the first at least breaks the module in
-- the game, while the second breaks nothing ever — a piece of code simply reaches the player unchecked.
--
-- Where the answer comes from. helpers.loadAddonFile gathers every path read
-- into helpers.loaded, while run.lua reads every check file in one Lua state
-- and require caches helpers — which means that by this point helpers.loaded
-- holds the union over the whole set. Hence the requirement about the order:
-- the file is obliged to stand last in run.lua. Standing earlier it would see
-- half the set and go red on honestly checked files — which is why it is
-- appended to the end of the list rather than inserted in the middle.
--
-- Why a refusal rather than a list of names. A list of "ought to be looked
-- at" was already here in another shape: the page of demonstration widgets
-- fell behind in exactly that way, and that is precisely why its guard was
-- rewritten into a refusal. A file named aloud but not breaking the build
-- reads as "later", and "later" never comes for unchecked code. So here there
-- is a red line. A legitimate case is not locked out: it is written into
-- EXEMPT together with its reason — and the record itself is watched so as not to outlive its occasion.

T.suite("the modules' files: what the set of checks loads")

--- The modules' folders, asked of the disk.
-- By the same means as in tests/test_moduletoc.lua: a list of names typed by
-- hand would forget a new module first thing.
-- @return table an array of folder names
local function moduleFolders()
    -- Through the helpers rather than a walk of our own: the rule "a folder
    -- with no TOC is not a module" is one for the whole set, and a second walk
    -- here would diverge from it silently — on an empty directory left over from a module that moved out.
    return helpers.moduleFolders()
end

-- The legitimate exceptions: a file of a module the set deliberately does not read.
-- The key is the path exactly as it lies in the module's TOC; the value is
-- the reason, and the reason is obliged to be stated rather than assumed.
--
-- It is empty here for a reason: today every file of every module gets into
-- the checks. The very first record here is an occasion to ask why a file is
-- not checked rather than a mark saying "dealt with".
local EXEMPT = {
}

local folders = moduleFolders()
T.ok(#folders >= 5, "the modules' folders were found: " .. #folders)

local checked = 0

for _, folder in ipairs(folders) do
    local files = helpers.moduleFiles(folder)
    T.ok(#files > 0, folder .. ": the module's files are enumerated in the TOC")

    for _, rel in ipairs(files) do
        local path = folder .. "/" .. rel
        local excuse = EXEMPT[path]

        if excuse then
            -- An exception that has stopped being needed is a check quietly
            -- removed: the file has long been read while the record still
            -- permits it not to be, and the next file like it will hide behind it.
            T.eq(helpers.loaded[path], nil,
                "the exception outlived its occasion, the file is already loaded: " .. path
                .. " (" .. excuse .. ")")
        else
            T.eq(helpers.loaded[path], true,
                "at least one check reads this file of the module: " .. path)
            checked = checked + 1
        end
    end
end

-- Zero read is not "all is well" but "it could not be looked at": an empty
-- helpers.loaded or an empty list of folders would give green on an empty place.
T.ok(checked >= 40, "files of modules under check: " .. checked)

-- And the other way round: a path written into the exceptions is obliged to
-- exist in the TOC. A typo in it is an exception that excludes nothing, and a
-- guard that stays silent about it.
do
    local known = {}
    for _, folder in ipairs(folders) do
        for _, rel in ipairs(helpers.moduleFiles(folder)) do
            known[folder .. "/" .. rel] = true
        end
    end

    local strays = {}
    for path in pairs(EXEMPT) do
        if not known[path] then strays[#strays + 1] = path end
    end
    table.sort(strays)

    T.eq(#strays, 0, "the exceptions are named for files that exist; extra ones: "
        .. table.concat(strays, " | "))
end

--============================================================================
-- The same about the core
--============================================================================

T.suite("the core's files: what the set of checks loads")

-- The core's trouble is the same, and the occasion to ask is that same TOC.
-- There is one difference: the core has a file that is not read outside the
-- game and cannot be, which is why the exceptions here are not empty.

--- The core's files in load order, asked of Darken.toc.
-- @return table
local function coreFiles()
    local handle = io.open("Darken.toc", "r")
    if not handle then error("Darken.toc did not open", 0) end

    local list = {}
    for line in handle:lines() do
        local rel = line:match("^%s*([%w_][%w_%.%-\\/]*%.lua)%s*$")
        if rel then list[#list + 1] = (rel:gsub("\\", "/")) end
    end
    handle:close()
    return list
end

-- Empty, and that is a change. Core/Init.lua used to stand here with the
-- reason "it assembles the addon with the real Ace libraries and the game":
-- outside the client it was considered uncheckable, because reading it with
-- stand-ins would mean checking the stand-ins. The answer was found not in
-- stand-ins but in the libraries: they are the real ones, taken out of Libs/
-- in the order of Libs.xml, and the addon is brought up by them entirely (tests/test_coldboot.lua). The exception outlived its occasion and was removed.
local CORE_EXEMPT = {
}

do
    local files = coreFiles()
    T.ok(#files >= 20, "the core's files are enumerated in the TOC: " .. #files)

    local seen = 0
    for _, path in ipairs(files) do
        local excuse = CORE_EXEMPT[path]
        if excuse then
            T.eq(helpers.loaded[path], nil,
                "the exception outlived its occasion, the file is already loaded: " .. path
                .. " (" .. excuse .. ")")
        else
            T.eq(helpers.loaded[path], true,
                "at least one check reads this file of the core: " .. path)
            seen = seen + 1
        end
    end

    T.ok(seen >= 20, "files of the core under check: " .. seen)

    local known = {}
    for _, path in ipairs(files) do known[path] = true end
    local strays = {}
    for path in pairs(CORE_EXEMPT) do
        if not known[path] then strays[#strays + 1] = path end
    end
    table.sort(strays)
    T.eq(#strays, 0, "the core's exceptions are named for files that exist; extra ones: "
        .. table.concat(strays, " | "))
end
