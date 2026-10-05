-- Reading the translation keys out of the sources.
--
-- A file of its own because two use it: the check of the core's translation
-- completeness (tests/test_locale_tables.lua) and the same check for the bag
-- module (tests/test_bagsmodule.lua). Two copies of one parse would diverge
-- at the very first edit, and they would diverge silently — a translation
-- check that has stopped seeing half the keys looks green.

local keys = {}

--- Read a file whole.
function keys.read(path)
    local handle = io.open(path, "r")
    if not handle then error(path .. " did not open", 0) end
    local text = handle:read("*a")
    handle:close()
    return text
end

--- Parse a Lua string literal in double quotes, starting at position i.
-- @return string|nil the contents, number the position past the closing quote
local function readString(text, i)
    if text:sub(i, i) ~= '"' then return nil, i end

    local out, j = {}, i + 1
    while j <= #text do
        local c = text:sub(j, j)
        if c == "\\" then
            local escaped = text:sub(j + 1, j + 1)
            if escaped == "n" then out[#out + 1] = "\n"
            elseif escaped == "t" then out[#out + 1] = "\t"
            else out[#out + 1] = escaped end
            j = j + 2
        elseif c == '"' then
            return table.concat(out), j + 1
        else
            out[#out + 1] = c
            j = j + 1
        end
    end

    return nil, i
end

--- Gather the translation keys out of a file's text.
-- Only ns.Localize's literal arguments are taken: a string or a
-- concatenation of strings with "..". An argument that is a variable (labels
-- out of tables such as CATEGORIES) will not get here — such keys are checked separately, below.
-- @return table an array of keys
--- The translation keys out of one file.
--
-- There are TWO places the keys live in, and the second appeared with the window's move.
--
-- The first is a call of ns.Localize(...): that is how a label is translated
-- where it is shown.
--
-- The second is the schema's fields: label, hint and title are declared as
-- English strings right in a page's description, and the window translates
-- them at the drawing. There is no ns.Localize call beside them and must not
-- be: a schema file is read before the core hands out the dictionary.
--
-- Not knowing the second, the parse counted translated labels as
-- "translations with no call site" and demanded they be deleted. Deleted,
-- they would have become English in the game — silently.
--
-- @param text string
-- @return table an array of keys
function keys.literal(text)
    local keys = {}

    -- The schema's fields. A field name with an equals sign is looked for,
    -- and the string after it is read by the same parse as a call's: labels
    -- longer than a source line are written with "..", and without the
    -- concatenation only the first piece would reach the dictionary.
    for _, field in ipairs({ "label", "hint", "title" }) do
        local at = 1
        while true do
            local from, to = text:find("%f[%w]" .. field .. "%s*=%s*", at)
            if not from then break end
            at = to + 1

            local i = to + 1
            local parts = {}
            while true do
                while text:sub(i, i):match("%s") do i = i + 1 end
                local piece, nextI = readString(text, i)
                if piece == nil then parts = nil break end
                parts[#parts + 1] = piece
                i = nextI
                while text:sub(i, i):match("%s") do i = i + 1 end
                if text:sub(i, i + 1) == ".." then i = i + 2 else break end
            end

            if parts and #parts > 0 then
                keys[#keys + 1] = table.concat(parts)
            end
        end
    end

    local pos = 1
    while true do
        local from, to = text:find("ns%.Localize%(", pos)
        if not from then break end
        pos = to + 1

        local i = to + 1
        local parts = {}
        while true do
            -- skip whitespace and newlines
            while text:sub(i, i):match("%s") do i = i + 1 end

            local piece, nextI = readString(text, i)
            if piece == nil then parts = nil break end
            parts[#parts + 1] = piece
            i = nextI

            while text:sub(i, i):match("%s") do i = i + 1 end
            if text:sub(i, i + 1) == ".." then
                i = i + 2
            else
                break
            end
        end

        if parts and #parts > 0 then
            keys[#keys + 1] = table.concat(parts)
        end
    end
    return keys
end

return keys
