-- Parsing a source file into tokens: string literals apart from comments.
--
-- A file of its own for the same reason as tests/localekeys.lua: the parser
-- is used by the check of the language rule (tests/test_locale_rule.lua), and
-- it is obliged to be checkable itself — a parser that has stopped seeing
-- half the literals looks green.
--
-- The parser's main property: a comment is not a string.
-- "--" to the end of a line and "--[[ ... ]]" are skipped entirely, so
-- comments never get into the output at all. That is not a guess by the look
-- of the text but a parse: what counts as a string is what the game counts as
-- a string.

local C = {}

-- Cyrillic in UTF-8 occupies D0 80..BF and D1 80..BF (the Russian Ё/ё and the
-- Ukrainian І/і, Ї/ї, Є/є, Ґ/ґ fall in there too).
--- Whether a string holds any Cyrillic.
function C.hasCyrillic(s)
    return type(s) == "string" and s:find("[\208\209][\128-\191]") ~= nil
end

--- Read a file whole.
function C.read(path)
    local handle = io.open(path, "r")
    if not handle then error(path .. " did not open", 0) end
    local text = handle:read("*a")
    handle:close()
    return text
end

local function countLines(text, from, to)
    local count = 0
    for _ in text:sub(from, to):gmatch("\n") do count = count + 1 end
    return count
end

--- Parse a text into tokens.
-- Returns an array of records {kind, text, line}, where kind is "name",
-- "string" or "punct". Numbers and whitespace are omitted: not one rule asks
-- about them. Comments are never returned.
function C.tokens(text)
    local out = {}
    local i, n, line = 1, #text, 1

    while i <= n do
        local c = text:sub(i, i)

        if c == "\n" then
            line = line + 1
            i = i + 1
        elseif c == " " or c == "\t" or c == "\r" then
            i = i + 1
        elseif c == "-" and text:sub(i + 1, i + 1) == "-" then
            local eqs = text:match("^%[(=*)%[", i + 2)
            if eqs then
                local _, e = text:find("]" .. eqs .. "]", i + 2, true)
                e = e or n
                line = line + countLines(text, i, e)
                i = e + 1
            else
                i = text:find("\n", i) or (n + 1)
            end
        elseif c == "[" and text:match("^%[(=*)%[", i) then
            local eqs = text:match("^%[(=*)%[", i)
            local from = i + 2 + #eqs
            local s, e = text:find("]" .. eqs .. "]", from, true)
            out[#out + 1] = {
                kind = "string",
                text = text:sub(from, (s or (n + 1)) - 1),
                line = line,
            }
            e = e or n
            line = line + countLines(text, i, e)
            i = e + 1
        elseif c == '"' or c == "'" then
            local quote, j, buf, startLine = c, i + 1, {}, line
            local closed = false
            while j <= n do
                local d = text:sub(j, j)
                if d == "\\" then
                    local esc = text:sub(j + 1, j + 1)
                    if esc == "n" then buf[#buf + 1] = "\n"
                    elseif esc == "t" then buf[#buf + 1] = "\t"
                    elseif esc == "\n" then buf[#buf + 1] = "\n"; line = line + 1
                    else buf[#buf + 1] = esc end
                    j = j + 2
                elseif d == quote then
                    closed = true
                    j = j + 1
                    break
                elseif d == "\n" then
                    -- An unclosed string: the parse will go askew from here
                    -- on, and staying silent about that is not allowed.
                    break
                else
                    buf[#buf + 1] = d
                    j = j + 1
                end
            end
            if not closed then
                error(string.format(
                    "unclosed string literal, line %d", startLine), 0)
            end
            out[#out + 1] = {
                kind = "string", text = table.concat(buf), line = startLine,
            }
            i = j
        elseif c:match("[%a_]") then
            local j = i
            while j <= n and text:sub(j, j):match("[%w_]") do j = j + 1 end
            out[#out + 1] = { kind = "name", text = text:sub(i, j - 1), line = line }
            i = j
        elseif c:match("%d") then
            local j = i
            while j <= n and text:sub(j, j):match("[%w%.]") do j = j + 1 end
            i = j
        else
            out[#out + 1] = { kind = "punct", text = c, line = line }
            i = i + 1
        end
    end

    return out
end

--- The name of the callee before an opening bracket.
-- Assembled backwards over the tokens: "ns.Skin.Report", "self:Print",
-- "error". A call of the form "f()()" has no name — a nil is returned.
local function calleeBefore(tokens, index)
    local parts = {}
    local k = index - 1
    if not (tokens[k] and tokens[k].kind == "name") then return nil end

    while k >= 1 do
        local token = tokens[k]
        if token.kind == "name" then
            table.insert(parts, 1, token.text)
            local sep = tokens[k - 1]
            if sep and sep.kind == "punct" and (sep.text == "." or sep.text == ":")
                and tokens[k - 2] and tokens[k - 2].kind == "name" then
                table.insert(parts, 1, sep.text)
                k = k - 2
            else
                break
            end
        else
            break
        end
    end

    return table.concat(parts)
end

--- The string literals with the list of the calls enclosing them.
-- Returns an array of {text, line, calls}, where calls is an array of call
-- names from the outer to the inner: for string.format(ns.Localize("x"))
-- inside self:Print(...) that is {"self:Print", "string.format", "ns.Localize"}.
function C.literals(text)
    local tokens = C.tokens(text)
    local stack, out = {}, {}

    for index = 1, #tokens do
        local token = tokens[index]
        if token.kind == "punct" then
            if token.text == "(" then
                stack[#stack + 1] = calleeBefore(tokens, index) or false
            elseif token.text == "{" or token.text == "[" then
                stack[#stack + 1] = false
            elseif token.text == ")" or token.text == "}" or token.text == "]" then
                if #stack > 0 then stack[#stack] = nil end
            end
        elseif token.kind == "string" then
            local calls = {}
            for i = 1, #stack do
                if stack[i] then calls[#calls + 1] = stack[i] end
            end
            out[#out + 1] = { text = token.text, line = token.line, calls = calls }
        end
    end

    return out
end

--- Whether a literal is called inside a call of that name.
-- The name's tail is compared whole: "Print" matches "self:Print" and
-- "module:Print" but not "Println".
function C.within(entry, names)
    for i = 1, #entry.calls do
        local call = entry.calls[i]
        for j = 1, #names do
            local name = names[j]
            if call == name or call:sub(-#name - 1) == ":" .. name
                or call:sub(-#name - 1) == "." .. name then
                return true
            end
        end
    end
    return false
end

return C
