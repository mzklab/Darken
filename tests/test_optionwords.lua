local helpers = require("helpers")
local localekeys = require("localekeys")

-- The settings window's words.
--
-- About three hundred settings were written one at a time, each by its own
-- author and in its own hour. Not one check had read them as a single text
-- until now, while the settings window is read exactly that way: in a row,
-- from the top down, by somebody else's eyes. Hence four failures, each of
-- which separately looks like a trifle while together they give the feeling that the window was assembled rather than written.
--
-- WHAT IS CHECKED HERE.
--
-- 1. A description that repeats its own label. It costs rows on the screen and
--    teaches nothing: the player read the same thing half a second earlier. An
--    empty description is the same thing, only it looks cheaper.
--
-- 2. One spelling per word. "colour" beside a setting called "Health Bar
--    Color" is not a dialect but two spellings of one word in one window.
--
--
-- 3. One case for the labels. The core writes them in title case with the
--    function words in lower case: "Snap to Grid", "Fade Out of Combat".
--    Before this check two more rules lived in the tree: "Rule To Edit" for
--    the auras and the nameplates and "Rule to edit" for the bags — one and
--    the same button of one and the same rule editor, named in three ways.
--
-- 4. A translation wherever there is English. The completeness of the core's
--    translation is guarded by tests/test_locale_tables.lua and the modules'
--    by their own checks; but they guard only the modules that asked for it.
--    The durability module calls the translation through module:Localize
--    rather than ns.Localize and fell under none of them: its tables are
--    complete by accident rather than by rule. Here the list of modules is
--    asked of the disk, so a new module falls under the rule by itself.
--
-- WHAT THE CHECK DOES NOT CATCH.
--
-- 1. An untruth. "Off by default" with a default of "on" is meaning rather
--    than form: a parse of the source does not know what lies in the defaults.
-- 2. A description that retells the label in other words. Equality of strings
--    is compared rather than meaning.
-- 3. The labels of a dropdown's values ("By Class", "Unhappy Only"): they lie
--    in tables rather than in name fields and do not get here by the parse.
-- 4. English assembled at run time, and a label that arrived as a variable.
-- 5. The quality of the translation itself. The presence of a record is compared rather than its correctness.

T.suite("The settings window's words")

--============================================================================
-- The delivery's files
--============================================================================

-- The list is taken from the TOCs — the core's and every module's found on the
-- disk. A list rewritten by hand would fall behind silently: a file forgotten
-- in it is not checked at all while it looks checked.
local SOURCES = {}
do
    local seen = {}
    local function add(path)
        if not seen[path] then
            seen[path] = true
            SOURCES[#SOURCES + 1] = path
        end
    end

    local toc = io.open("Darken.toc", "r")
    if not toc then error("Darken.toc did not open", 0) end
    for line in toc:lines() do
        local rel = line:match("^([%w_][%w_%.%-\\/]*%.lua)%s*$")
        if rel then add((rel:gsub("\\", "/"))) end
    end
    toc:close()

    local folders = helpers.moduleFolders()
    for i = 1, #folders do
        local files = helpers.moduleSources(folders[i])
        for j = 1, #files do add(files[j]) end
    end
end

T.ok(#SOURCES >= 60, "the delivery's files were gathered out of the TOC: " .. #SOURCES)

--- Read a file whole.
-- @param path string
-- @return string
local function read(path)
    local handle = io.open(path, "r")
    if not handle then error(path .. " did not open", 0) end
    local text = handle:read("*a")
    handle:close()
    return text
end

--============================================================================
-- The parse of the labels and descriptions
--============================================================================

-- A setting's node is parsed line by line rather than as a tree: a tree would
-- have to be assembled by running the file, and not every file can be run
-- outside the game. A node's mark is the type field, a label's mark is a name
-- or desc field at the beginning of a line. A concatenation's continuation is
--
-- taken up to a line that does not end in ".." or "(". The parse is
-- deliberately timid: a label that arrived as a variable does not get here at
-- all. A gap here costs an unchecked line, while a false positive costs a red set on correct code, and the second is worse.

--- Assemble a literal out of concatenated lines: only what is written literally.
-- @param text string the statement's text
-- @return string|nil
local function literalOf(text)
    -- The translation calls and the notes attached to them do not affect the
    -- literal: what is of interest is the text itself, and it is written in quotes.
    local parts, pos = {}, 1
    while true do
        local from, piece = text:find('"', pos, true), nil
        if not from then break end

        local out, j = {}, from + 1
        while j <= #text do
            local c = text:sub(j, j)
            if c == "\\" then
                out[#out + 1] = text:sub(j + 1, j + 1)
                j = j + 2
            elseif c == '"' then
                piece = table.concat(out)
                break
            else
                out[#out + 1] = c
                j = j + 1
            end
        end

        if piece == nil then return nil end
        parts[#parts + 1] = piece
        pos = j + 1
    end

    if #parts == 0 then return nil end
    return table.concat(parts)
end

--- One file's labels and descriptions.
-- @param path string
-- @return table an array of { line, kind, text, nodeType }
local function entries(path)
    local lines = {}
    for line in read(path):gmatch("([^\n]*)\n?") do lines[#lines + 1] = line end

    local out, nodeType = {}, nil
    local i = 1
    while i <= #lines do
        local declared = lines[i]:match('^%s*type%s*=%s*"([%w]+)"')
        if declared then nodeType = declared end

        local kind = lines[i]:match("^%s*(name)%s*=") or lines[i]:match("^%s*(desc)%s*=")
        if kind then
            -- The concatenation continues while the next line begins with ".."
            -- or the current one breaks off at ".." or at an open bracket. One
            -- mark is not enough: an author breaks a line both before the concatenation and after it.
            local buf, j = { lines[i] }, i
            while true do
                local nextLine = lines[j + 1]
                local continues = buf[#buf]:match("%.%.%s*$")
                    or buf[#buf]:match("%(%s*$")
                    or (nextLine ~= nil and nextLine:match("^%s*%.%."))
                if not continues or nextLine == nil then break end
                j = j + 1
                buf[#buf + 1] = nextLine
            end

            local statement = table.concat(buf, " ")
            local text = literalOf(statement)
            if text then
                out[#out + 1] = {
                    line = i, kind = kind, text = text, nodeType = nodeType,
                    -- A setting node's label always goes through the
                    -- translation. A line without it is a subsystem's name, a
                    -- table's field or a wrapper's fallback value: not what the player reads.
                    localized = statement:find("Localize%(") ~= nil,
                }
            end
            i = j
        end

        i = i + 1
    end

    return out
end

-- The parse is checked on samples before it is checked on the addon: a parse
-- that has stopped seeing labels looks green exactly like a clean tree.
do
    local tmp = os.tmpname()
    local handle = io.open(tmp, "w")
    handle:write([[
local options = {
    slider = {
        type = "range",
        name = ns.Localize("Icon Size"),
        desc = ns.Localize("The side of one icon, "
            .. "in pixels."),
    },
    about = {
        type = "description",
        name = ns.Localize("A long piece of prose that is not a label."),
    },
}
]])
    handle:close()

    local sample = entries(tmp)
    os.remove(tmp)

    T.eq(#sample, 3, "the parse found three labels")
    T.eq(sample[1].localized, true, "the translation call was noticed")
    T.eq(sample[1].text, "Icon Size", "the label was read")
    T.eq(sample[1].nodeType, "range", "the label's node kind was recognised")
    T.eq(sample[2].text, "The side of one icon, in pixels.",
        "the description's concatenation was assembled whole")
    T.eq(sample[3].nodeType, "description",
        "the prose of an explanatory node is visible by the node's kind")
end

-- The contract's example is not subject to translation and deliberately has no
-- locales of its own (tests/test_locale_rule.lua): its labels are English right in the code.
local NOT_A_FEATURE = "^UmbraUI_Example/"

local ENTRIES = {}
for i = 1, #SOURCES do
    local list = entries(SOURCES[i])
    for j = 1, #list do
        local entry = list[j]
        entry.path = SOURCES[i]
        -- Only what the player reads in the window counts: a label that passed
        -- through the translation, and the example's labels, which are never translated.
        if entry.localized or entry.path:match(NOT_A_FEATURE) then
            ENTRIES[#ENTRIES + 1] = entry
        end
    end
end

T.ok(#ENTRIES >= 200, "the labels and descriptions were read out: " .. #ENTRIES)

--============================================================================
-- 1. A description repeating its label, and an empty description
--============================================================================

--- Bring a label to the shape two spellings are compared in.
-- @param text string
-- @return string
local function normalize(text)
    return (text:lower():gsub("[^%w]", ""))
end

do
    local repeated, empty = {}, {}
    local lastName = nil

    for i = 1, #ENTRIES do
        local entry = ENTRIES[i]
        if entry.kind == "name" then
            lastName = entry

            -- The prose of an explanatory node lies in the name field rather
            -- than desc, and until now emptiness was checked only for desc.
            -- That is, this check did not see an empty explanation at all —
            -- and in the window it looks exactly the way the author
            -- complained: a paragraph takes up its height and says nothing. Now it is visible too.
            if entry.nodeType == "description"
                and entry.text:match("^%s*$") then
                empty[#empty + 1] = entry.path .. ":" .. entry.line
            end
        else
            if entry.text:match("^%s*$") then
                empty[#empty + 1] = entry.path .. ":" .. entry.line
            elseif lastName ~= nil
                and lastName.path == entry.path
                and normalize(lastName.text) == normalize(entry.text) then
                repeated[#repeated + 1] = string.format("%s:%d «%s»",
                    entry.path, entry.line, entry.text:sub(1, 40))
            end
        end
    end

    T.eq(#repeated, 0, "a description repeats its own label: "
        .. table.concat(repeated, " | "))
    T.eq(#empty, 0, "an empty description: " .. table.concat(empty, " | "))
end

--============================================================================
-- 2. One spelling per word
--============================================================================

-- Word -> the spelling that is accepted. The list is deliberately short: only
-- what has already diverged in the tree at least once gets here. "colour"
-- stood in the descriptions of the darkening and the bags while beside it, in
-- the same window, fifteen settings were called "... Color".
local SPELLING = {
    ["colour"]  = "color",
    ["colours"] = "colors",
}

do
    local wrong = {}
    for i = 1, #ENTRIES do
        local entry = ENTRIES[i]
        local lower = entry.text:lower()
        for bad, good in pairs(SPELLING) do
            if lower:find("%f[%a]" .. bad .. "%f[%A]") then
                wrong[#wrong + 1] = string.format("%s:%d \"%s\" instead of \"%s\"",
                    entry.path, entry.line, bad, good)
            end
        end
    end
    T.eq(#wrong, 0, "two spellings of one word: " .. table.concat(wrong, " | "))
end

--============================================================================
-- 3. One case for the labels
--============================================================================

-- The function words: in the middle of a label they are written in lower case,
-- as the first and the last word with a capital. The rule is the very one the
-- core is written by, and the same one is accepted in the game's own interface.
local SMALL = {}
for word in ("a an the and or but nor of to in on at by for with from as "
    .. "into over"):gmatch("%a+") do
    SMALL[word] = true
end

--- Whether a line among the labels is fit for the case check.
-- The prose of an explanatory node, format strings and multi-line labels are not labels.
-- @param entry table
-- @return boolean
local function isLabel(entry)
    if entry.kind ~= "name" then return false end
    if entry.nodeType == "description" then return false end
    if entry.path:match(NOT_A_FEATURE) then return false end
    if entry.text == "" then return false end
    if entry.text:find("[\n%%]") then return false end
    -- A long line in a name field is the prose of a node whose kind is declared
    -- below the label or not declared at all.
    if #entry.text > 44 then return false end
    return true
end

do
    local wrong = {}
    for i = 1, #ENTRIES do
        local entry = ENTRIES[i]
        if isLabel(entry) then
            local words = {}
            for word in entry.text:gmatch("%S+") do words[#words + 1] = word end

            for w = 1, #words do
                -- Quotes, brackets and commas have nothing to do with the case.
                local word = words[w]:gsub("^[^%w]+", ""):gsub("[^%w]+$", "")
                local first = word:sub(1, 1)

                if word ~= "" and first:match("%a") then
                    local small = SMALL[word:lower()]
                    local middle = w > 1 and w < #words
                    local upper = first:match("%u") ~= nil

                    if middle and small and upper then
                        wrong[#wrong + 1] = string.format(
                            "%s:%d \"%s\": the function word \"%s\" with a capital",
                            entry.path, entry.line, entry.text, word)
                    elseif not (middle and small) and not upper then
                        wrong[#wrong + 1] = string.format(
                            "%s:%d \"%s\": \"%s\" in lower case",
                            entry.path, entry.line, entry.text, word)
                    end
                end
            end
        end
    end

    T.eq(#wrong, 0, "the labels are written in different cases: "
        .. table.concat(wrong, " | "))
end

--============================================================================
-- 4. A translation wherever there is English
--============================================================================

-- A module's keys are read out the same way as the core's but with one
-- correction: a module is entitled to call the translation through its
-- descriptor too (module:Localize, self:Localize), and not one completeness
-- check saw such a call. The conversion to ns.Localize is done on the text
-- rather than in localekeys: the parse is shared with the other checks, and changing it for one case would mean changing them all.
--
-- @param text string
-- @return string
local function asCoreCalls(text)
    return (text:gsub("[%w_]+[:%.]Localize%(", "ns.Localize("))
end

do
    local folders = helpers.moduleFolders()
    T.ok(#folders >= 5, "the modules' folders were asked of the disk: " .. #folders)

    for f = 1, #folders do
        local folder = folders[f]
        local ru = folder .. "/Locale/ruRU.lua"
        local uk = folder .. "/Locale/ukUA.lua"
        local handle = io.open(ru, "r")

        if handle then
            handle:close()

            -- The tables are read as data: there is nowhere to put them but
            -- a namespace of our own, and there is no point bringing a live module up for that.
            local strings = {}
            for _, path in ipairs({ ru, uk }) do
                -- The table is one and the same both in the core's place and
                -- in a part's: a part's file begins with core.Feature("name"),
                -- and without that door it falls over at its first line.
                -- Giving it the same table here is right — ONE part is read,
                -- and there is nobody to overwrite.
                local env = { Locales = {}, Strings = {} }
                env.Feature = function() return env end
                local chunk = assert(loadfile(path))
                setfenv(chunk, setmetatable({}, { __index = _G }))
                chunk("Darken", env)

                local tables = next(env.Locales) ~= nil and env.Locales
                    or env.Strings
                for locale, table_ in pairs(tables) do
                    strings[locale] = table_
                end
            end

            local sources = helpers.moduleSources(folder)
            local wanted, seen = {}, {}
            for i = 1, #sources do
                local text = asCoreCalls(read(sources[i]))
                local keys = localekeys.literal(text)
                for j = 1, #keys do
                    if not seen[keys[j]] then
                        seen[keys[j]] = true
                        wanted[#wanted + 1] = keys[j]
                    end
                end
            end

            T.ok(#wanted >= 8,
                folder .. ": the keys were read out of the sources: " .. #wanted)

            for _, locale in ipairs({ "ruRU", "ukUA" }) do
                local translations = strings[locale]
                T.ok(type(translations) == "table",
                    folder .. ": the table " .. locale .. " was read")

                if type(translations) == "table" then
                    local missing = {}
                    for i = 1, #wanted do
                        if type(translations[wanted[i]]) ~= "string" then
                            missing[#missing + 1] = wanted[i]:sub(1, 40)
                        end
                    end
                    T.eq(#missing, 0, folder .. ", " .. locale
                        .. ": left untranslated: "
                        .. table.concat(missing, " | "))
                end
            end

            -- A record that exists in one language and not in the other is a
            -- translation carried halfway. Neither of the two tables shows
            -- that on its own.
            local onlyRu, onlyUk = {}, {}
            for key in pairs(strings.ruRU or {}) do
                if (strings.ukUA or {})[key] == nil then
                    onlyRu[#onlyRu + 1] = key:sub(1, 40)
                end
            end
            for key in pairs(strings.ukUA or {}) do
                if (strings.ruRU or {})[key] == nil then
                    onlyUk[#onlyUk + 1] = key:sub(1, 40)
                end
            end
            T.eq(#onlyRu, 0, folder .. ": present in Russian only: "
                .. table.concat(onlyRu, " | "))
            T.eq(#onlyUk, 0, folder .. ": present in Ukrainian only: "
                .. table.concat(onlyUk, " | "))
        end
    end
end
