local helpers = require("helpers")

-- What is written about the addon and the addon itself.
--
-- Three files describe what the addon does to the player and to a
-- third-party author: README.md is the repository's front page,
-- docs/curseforge.md the text of the project page, docs/module-api.md the
-- contract. All three were written when the addon was smaller and diverged
-- from it silently: for half a year the project page promised eight of the
-- nine textures and called its own the channel ticks that had long moved out
-- into a separate module, while the README knew three modules out of nine. The failure here could not be quieter — what is written is not run.
--
-- So the lists here are asked of the disk and of the code rather than
-- rewritten into the check: the same device tests/test_moduletoc.lua (the
-- modules' folders) and tests/test_media.lua (the set of textures) live by. A
-- rewritten list would forget a new module at exactly the time the README forgot it.
--
-- The fourth text, docs/known-issues.md, is written not for the player but
-- for whoever comes back to a decision taken. Only one thing is asked of it
-- here — that the files it names exist (at the very end of this file): a
-- reference to a renamed file misleads a reader more surely than its absence.
--
-- What this check CANNOT do. It compares names, numbers and paths — what can
-- be compared as a string. It does not check a description's truthfulness:
-- the phrase "the module shows the time and the stacks" will stay green even
-- when the module stops showing them. In just the same way it cannot see an
-- invention in a text about a subsystem that has neither a folder nor a name in the registry.

T.suite("what is written: the modules, the commands and the numbers")

local function read(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

local README = read("README.md")
local PAGE   = read("docs/curseforge.md")
local APIDOC = read("docs/module-api.md")

T.ok(README ~= nil, "README.md opened")
T.ok(PAGE   ~= nil, "docs/curseforge.md opened")
T.ok(APIDOC ~= nil, "docs/module-api.md opened")

local MODULES = helpers.moduleFolders()
T.ok(#MODULES >= 5, "the modules' folders were found: " .. #MODULES)

--- A part's main file: the file of the same name in its folder.
-- @param folder string the part folder's path from the addon's root
-- @return string|nil the contents
local function mainSource(folder)
    local short = folder:match("([^/]+)$")
    if not short then return nil end
    return read(folder .. "/" .. short .. ".lua")
end

--============================================================================
-- A module is on the disk, so the module is named in what is written
--============================================================================

for _, folder in ipairs(MODULES) do
    -- The README enumerates the parts by their folders' names: by that name
    -- an author finds the directory in the repository and a player understands which part is meant.
    T.ok(README ~= nil and README:find(folder, 1, true) ~= nil,
        "the README names the part " .. folder)
end

-- A part no longer has a title of its own on the project page, and demanding
-- one is not allowed: the page sells one addon. Every part used to be a
-- separate addon with a ## Title of its own, and the page named all eleven.

--============================================================================
-- The command a module takes is named to the player
--============================================================================

-- A slash command is the only way to open a module's window, and unnamed it
-- does not exist for the player as surely as an unwritten one. There are two
-- forms: the contract's handle:RegisterCommand and a SLASH_NAME1 of their own
-- for the modules that created a command themselves.
for _, folder in ipairs(MODULES) do
    local source = mainSource(folder)
    T.ok(source ~= nil, folder .. ": the main file was read")

    local words = {}
    for word in (source or ""):gmatch("RegisterCommand%(\"([%a%d_]+)\"") do
        words[word] = true
    end
    for word in (source or ""):gmatch("SLASH_[%u%d_]+1%s*=%s*\"/([%a%d_]+)\"") do
        words[word] = true
    end

    local named = 0
    for word in pairs(words) do
        named = named + 1
        -- A part has no slash of its own: its word is the second word of the
        -- addon's command ("/dark auras"), and what is written names it the
        -- way it is typed. The player is not obliged to remember six separate commands.
        T.ok(README ~= nil
            and README:find("/dark " .. word, 1, true) ~= nil,
            "the README names the part's command " .. folder .. ": /dark " .. word)
    end

    -- A word need not be created at all: a part lives as a row in the settings
    -- menu, and a slash command of its own is a convenience rather than its
    -- only door. The check demands not a command but that a command that IS named be written down.
    T.ok(named >= 0, folder .. ": the part's commands were read: " .. named)
end

-- The core's commands. Core/Init.lua parses them, and the word there is
-- written down in exactly one way — `cmd == "word"`. The README is obliged to
-- name each of them: a command nothing is written about does not exist for the player.
do
    local init = read("Core/Init.lua")
    T.ok(init ~= nil, "Core/Init.lua was read")

    local seen = {}
    for word in (init or ""):gmatch("cmd == \"([%a]+)\"") do
        if not seen[word] then
            seen[word] = true
            T.ok(README ~= nil
                and README:find("/dark " .. word, 1, true) ~= nil,
                "the README names the core's command /dark " .. word)
        end
    end
    T.ok(next(seen) ~= nil, "the core's commands were found in Core/Init.lua")

    for word in (init or ""):gmatch("RegisterChatCommand%(\"([%a]+)\"") do
        T.ok(README ~= nil and README:find("/" .. word, 1, true) ~= nil,
            "the README names the core command's word: /" .. word)
    end
end

--============================================================================
-- The numbers: the contract's version and the set of our own textures
--============================================================================

-- The contract's version is named twice in the document — in the head and in
-- the section about version negotiation — and both times as a number. The
-- number lives in Core/Api.lua and is checked against it rather than against
-- memory: a document promising the fourteenth version on a fifteenth core lies to exactly the person writing a module.
do
    local api = read("Core/Api.lua")
    T.ok(api ~= nil, "Core/Api.lua was read")

    local current = tonumber((api or ""):match("local API_VERSION%s*=%s*(%d+)"))
    local lowest  = tonumber((api or ""):match("local API_MIN_VERSION%s*=%s*(%d+)"))
    T.ok(current ~= nil, "the contract's version was read out of Core/Api.lua")
    T.ok(lowest  ~= nil, "the contract's lower bound was read out of Core/Api.lua")

    local headline = tonumber((APIDOC or ""):match("Contract version: %*%*(%d+)%*%*"))
    T.eq(headline, current, "the contract's head names the current version")

    local today = tonumber((APIDOC or ""):match("Today `API_VERSION` is\n`(%d+)`"))
        or tonumber((APIDOC or ""):match("Today `API_VERSION` is `(%d+)`"))
    T.eq(today, current, "the section about API_MIN_VERSION names the current version")

    -- And the reverse side: a module cannot be written against a contract the
    -- core does not give. The number is taken from the module itself.
    for _, folder in ipairs(MODULES) do
        local source = mainSource(folder)
        local declared = tonumber((source or ""):match("\nlocal API%s*=%s*(%d+)"))
        T.ok(declared ~= nil, folder .. ": a contract version is declared")
        if declared and current and lowest then
            T.ok(declared >= lowest and declared <= current,
                folder .. ": the declared contract version " .. declared
                .. " lies within " .. lowest .. ".." .. current)
        end
    end
end

-- How many textures of our own. The number is written as a word, and the eight
-- out of nine promised is the very mistake the check is written for: the list
-- of textures lies in Core/Media.lua while the word lies in two documents.
do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Media.lua", ns)
    local count = #ns.Media.Entries()
    T.ok(count > 0, "the set of our own textures was read: " .. count)

    local WORDS = {
        "one", "two", "three", "four", "five", "six",
        "seven", "eight", "nine", "ten", "eleven", "twelve",
    }
    local right = WORDS[count]
    T.ok(right ~= nil, "the number of textures is named as a word: " .. count)

    local docs = {
        ["README.md"] = README,
        ["docs/curseforge.md"] = PAGE,
    }
    for path, text in pairs(docs) do
        local lower = (text or ""):lower()
        local found = lower:find(right .. " textures", 1, true)
            or lower:find(right .. " bar textures", 1, true)
        T.ok(found ~= nil,
            path .. ": the number of our textures named is " .. right)

        for _, word in ipairs(WORDS) do
            if word ~= right then
                local wrong = lower:find(word .. " textures", 1, true)
                    or lower:find(word .. " bar textures", 1, true)
                T.eq(wrong, nil,
                    path .. ": no other number of textures is named, while named is \""
                    .. word .. "»")
            end
        end
    end
end

T.suite("what is written: the note about the known issues")

do
    local NOTES = read("docs/known-issues.md")
    T.ok(NOTES ~= nil, "docs/known-issues.md opened")

    local seen, checked = {}, 0
    for ref in (NOTES or ""):gmatch("`([^`]+)`") do
        local path = ref:match("^([%w_%./%-]+%.lua)$")
            or ref:match("^([%w_%./%-]+%.md)$")
        if path and not seen[path] then
            seen[path] = true
            checked = checked + 1
            T.ok(read(path) ~= nil,
                "known-issues: the file named exists: " .. path)
        end
    end
    T.ok(checked >= 10, "paths named in the note: " .. checked)
end
