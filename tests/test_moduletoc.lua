local helpers = require("helpers")
-- The TOC of the addon's parts: the thing without which a part does not load,
-- and this is the only place it is checked.
--
-- Why the check is needed exactly here. The whole rest of the set of checks
-- reads the parts' files directly (helpers.loadAddonFile) and is therefore
-- green regardless of what is written in the TOC. In the game it is the other
-- way round: a file not enumerated in the TOC is not read at all. That is,
-- before this check there was no connection at all between "every check passed" and "the part works in the game".
--
-- What changed here. Every part used to be a separate addon: a folder of its
-- own in Interface\AddOns\ (a directory junction put it there), a TOC of its
-- own, a row of its own in the list on the character select screen. There were
-- eleven rows, and the player saw eleven addons where there is one.
-- Now the parts lie inside the addon (the Features folder), are loaded by its
-- own TOC and are visible to the player as rows in the settings menu. So what
-- is checked is not "every part has a correct TOC" but "every file of every
-- part is enumerated in the addon's TOC, and nothing extra is there".

T.suite("the TOC of the addon's parts")

local MODULES = helpers.moduleFolders()
T.ok(#MODULES >= 5, "the parts' folders were found: " .. #MODULES)

local function read(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

--- A TOC field's value: a line of the form "## Name: value".
-- @param text string the TOC's contents
-- @param name string the field's name without the hashes
-- @return string|nil
local function field(text, name)
    -- An end of line is not required: a field that turns out to be the file's
    -- last line with no newline is read by the game, and the check is obliged
    -- to read it the same way. Trailing whitespace is trimmed separately.
    local value = text:match("##%s*" .. name .. ":%s*([^\r\n]*)")
    if not value then return nil end
    return (value:gsub("%s+$", ""))
end

--- The file paths enumerated in the TOC, in load order.
-- @param text string
-- @return table a list of paths with forward slashes
local function files(text)
    local list = {}
    for line in text:gmatch("[^\r\n]+") do
        local path = line:match("^%s*([%w_][%w_%.%-\\/]*%.lua)%s*$")
        if path then list[#list + 1] = path:gsub("\\", "/") end
    end
    return list
end

--- The .lua files lying in a folder, as paths relative to it.
-- The list is asked of the disk rather than rewritten here by hand: a
-- rewritten one would forget a new file at exactly the time the TOC forgot it,
-- and the check "everything is enumerated" would confirm itself.
-- @param folder string the folder's path from the addon's root
-- @return table|nil a list of paths with forward slashes
local function diskFiles(folder)
    local windows = folder:gsub("/", "\\")
    local pipe = io.popen('dir /b /s "' .. windows .. '\\*.lua" 2>nul')
    if not pipe then return nil end
    local list = {}
    local tail = "/" .. folder .. "/"
    for line in pipe:lines() do
        local said = line:gsub("\\", "/")
        local at = said:find(tail, 1, true)
        if at then list[#list + 1] = said:sub(at + #tail) end
    end
    pipe:close()
    return list
end

local coreToc = read("Darken.toc")
T.ok(coreToc ~= nil, "the addon's TOC opened")
local coreInterface = coreToc and field(coreToc, "Interface")
T.ok(coreInterface ~= nil and coreInterface:find(",") ~= nil,
    "the addon's TOC holds a ## Interface with several clients: "
    .. tostring(coreInterface))

local listedAll = files(coreToc or "")
T.ok(#listedAll > 0, "files are enumerated in the addon's TOC")

local order = {}
for index, path in ipairs(listedAll) do order[path] = index end

-- The door the parts take their own namespace through is obliged to be open
-- before their first file: a part read earlier than it falls over at its very
-- first line — on a call that does not yet exist.
local feature = order["Core/Feature.lua"]
T.ok(feature ~= nil, "Core/Feature.lua is enumerated in the TOC")

for _, folder in ipairs(MODULES) do
    local listed = {}
    local first, last
    for index, path in ipairs(listedAll) do
        if path:sub(1, #folder + 1) == folder .. "/" then
            local rel = path:sub(#folder + 2)
            listed[rel:lower()] = true
            first = first or index
            last = index
        end
    end

    T.ok(first ~= nil, folder .. ": the part's files are enumerated in the addon's TOC")

    if first then
        T.ok(feature ~= nil and feature < first,
            folder .. ": the parts' namespace is opened before its files")

        -- One part's files go consecutively in the TOC. A broken order is not
        -- untidiness against beauty: a part's files lean on one another, and
        -- a foreign file wedged between them is read in the middle of a part
        -- that is not yet built.
        local strangers = 0
        for index = first, last do
            local path = listedAll[index]
            if path:sub(1, #folder + 1) ~= folder .. "/" then
                strangers = strangers + 1
            end
        end
        T.eq(strangers, 0, folder .. ": there are no foreign files between the part's files")
    end

    -- An enumerated file may be absent from the disk: a typo in a path leaves
    -- a part without a piece of code, and the game stays silent about it.
    for rel in pairs(listed) do
        T.ok(read(folder .. "/" .. rel) ~= nil,
            folder .. ": the file out of the TOC is on the disk: " .. rel)
    end

    -- And the other way round: a file of a part forgotten in the TOC simply does not load in the game.
    local disk = diskFiles(folder)
    -- An empty walk is not "there are no extra files" but "it could not be
    -- looked at". The difference is visible only if it is named: a silently
    -- empty list would turn the check into nothing.
    T.ok(disk ~= nil and #disk > 0,
        folder .. ": the part's files on the disk were enumerated: "
        .. tostring(disk and #disk))
    for _, rel in ipairs(disk or {}) do
        T.ok(listed[rel:lower()] == true,
            folder .. ": the part's file is enumerated in the TOC: " .. rel)
    end

    -- A part has no TOC of its own and must not have one: a TOC makes a folder
    -- an addon, and an addon a row in the list on the character select screen.
    -- It is precisely those rows the parts moved inside to escape.
    local name = folder:match("([^/]+)$") or folder
    T.eq(read(folder .. "/" .. name .. ".toc"), nil,
        folder .. ": the part has no TOC of its own")
end

T.suite("the catalogue of parts: the spec and the folders on the disk")

-- The catalogue of parts lives in the spec (the section "6a. The modules'
-- catalogue"), and it is the only list. The queue of work (docs/backlog.md)
-- does not repeat it, and that decision is written down in the queue itself.
--
-- Why the check is needed. The list was once already repeated by half: the
-- queue named three modules, the spec eight, and nobody saw the five
-- unwritten ones. The failure was quiet precisely because the short list was
-- read first and looked complete. Comparing the numbers is the cheapest guard
-- against repetition: a part the spec speaks of while the folder is absent becomes a red line here.
do
    local spec = read("docs/superpowers/specs/2026-09-23-umbraui-design.md")
    T.ok(spec ~= nil, "the spec opened")

    local catalogue = spec and spec:match("\n## 6a%..-\n(.-)\n## 7%.") or ""
    T.ok(#catalogue > 0, "the catalogue section in the spec was found")

    -- "Further modules" is not a part but an invitation to write the next one.
    local named = {}
    for heading in catalogue:gmatch("\n### ([^\n]+)") do
        -- The spec is kept in Russian; this heading is its own wording.
        if not heading:find("Дальнейшие") then named[#named + 1] = heading end
    end

    T.eq(#MODULES, #named, "every part of the catalogue has a folder of its own. In the spec: "
        .. table.concat(named, " | ") .. "; on the disk: "
        .. table.concat(MODULES, " | "))

    -- And the queue of work really does not repeat the catalogue: it is
    -- obliged to refer to the spec rather than to enumerate the parts afresh.
    local queue = read("docs/backlog.md")
    T.ok(queue ~= nil, "the queue of work opened")
    T.ok(queue ~= nil and queue:find("6a", 1, true) ~= nil,
        "the queue of work refers to the catalogue in the spec rather than repeating it")
end

T.suite("the catalogue of parts: the archive's build")

-- The list of directories that get into the archive is written by hand
-- outside Lua (tools/package.ps1). A folder forgotten in it leaves the
-- delivery silently: the addon installs and does not work — exactly as if its
-- files had been forgotten in the TOC.
do
    local text = read("tools/package.ps1")
    T.ok(text ~= nil, "tools/package.ps1 opened")

    T.ok((text or ""):find("'Features'", 1, true) ~= nil,
        "tools/package.ps1 puts the parts' folder into the archive")

    -- There are no directory junctions any more: they were put there by
    -- tools/deploy-modules.ps1 for the separate module addons, and no separate addons are left.
    T.eq(read("tools/deploy-modules.ps1"), nil,
        "no directory junctions for the parts are left")
end
