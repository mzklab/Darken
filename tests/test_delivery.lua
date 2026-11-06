local helpers = require("helpers")

-- What the archive must hold.
--
-- A player reported that he could not open the settings at all:
--
--   Darken/Darken_Camelot.toc:27 Error loading Darken/Options/List.lua
--
-- The file was not in the archive. The TOC lists the folders the addon is
-- made of, the packaging script lists the folders it takes, and the two had
-- drifted: Options and Widgets - the settings window and everything it is
-- drawn with - were in the first and not in the second. Every build
-- published went out without a settings window, and nothing said so: the
-- script prints what it took, and what it never heard of it cannot print.
--
-- So the two lists are compared here, where a check can fail before a player
-- does the checking for us.

T.suite("the delivery: every file the TOC loads is packaged")

--- The folders the packaging script takes.
-- @return table set of folder names
local function packagedFolders()
    local handle = io.open("tools/package.ps1", "r")
    if not handle then error("tools/package.ps1 did not open", 0) end
    local text = handle:read("*a")
    handle:close()

    local list = text:match("%$folders%s*=%s*@%((.-)%)")
    T.ok(list ~= nil, "the script's list of folders was read")

    local folders = {}
    if list then
        for name in list:gmatch("'([^']+)'") do folders[name] = true end
    end
    return folders
end

--- The files one TOC asks the game to load.
-- @param path string
-- @return table array of paths with forward slashes
local function tocFiles(path)
    local handle = io.open(path, "r")
    if not handle then error(path .. " did not open", 0) end

    local files = {}
    for line in handle:lines() do
        local entry = line:match("^([%w_][%w_%.%-\\/]*%.lua)%s*$")
            or line:match("^([%w_][%w_%.%-\\/]*%.xml)%s*$")
        if entry then files[#files + 1] = entry:gsub("\\", "/") end
    end
    handle:close()
    return files
end

local TOCS = {
    "Darken.toc", "Darken_Vanilla.toc", "Darken_Camelot.toc",
    "Darken_TBC.toc", "Darken_Mists.toc",
}

local folders = packagedFolders()
T.ok(next(folders) ~= nil, "the script takes at least one folder")

local missing, absent = {}, {}
local seen = {}
for i = 1, #TOCS do
    local files = tocFiles(TOCS[i])
    T.ok(#files > 0, TOCS[i] .. " lists files to load: " .. #files)

    for j = 1, #files do
        local file = files[j]
        if not seen[file] then
            seen[file] = true

            -- On disk at all.
            local handle = io.open(file, "r")
            if handle then handle:close() else absent[#absent + 1] = file end

            -- And inside a folder the archive takes. A file at the root is
            -- taken by name and is checked below instead.
            local folder = file:match("^([^/]+)/")
            if folder ~= nil and not folders[folder] then
                missing[#missing + 1] = file
            end
        end
    end
end

T.eq(#absent, 0, "every file the TOCs load exists: "
    .. table.concat(absent, " | "))
T.eq(#missing, 0, "and every one of them is in a packaged folder: "
    .. table.concat(missing, " | "))
