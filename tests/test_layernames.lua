local helpers = require("helpers")

-- A name taken from the layer and a trip into _G with it.
--
-- WHAT THIS SET IS FOR. The compatibility layer is the only place in the
-- addon that knows other people's names. They leave through the
-- Darken:GetFrameNames door, and since version 18 that door returns the
-- objects themselves as its SECOND answer. The reason is written down in Core/Api.lua in words:
--
--     A module that received a path-name and went into _G with it would get a
--     nil and silently do nothing — that is, a door created against silence
--     would itself become its source.
--
-- A name in a group is sometimes a path into somebody else's frame
-- ("MainActionBar.LeftEndCap" or "C_Container.GetContainerItemInfo"), and
-- `_G[a path]` is a nil. Five of the addon's groups already carry such paths,
-- and fresh builds of the client keep moving globals inside tables: the next
-- group will become one with no warning at all.
--
-- THE RULE HELD HERE is a single one and checkable without running the game:
--
--     A module that reads a group by ONE answer (the names alone) is obliged
--     to read a group that holds no paths. Whoever needs an object takes the
--     second answer; whoever needs the name itself (hooksecurefunc can only
--     subscribe to a global by name) is obliged to make sure the group holds no path-names.
--
-- There was no guard on this at all. tests/test_frameknowledge.lua guards the
-- reverse side — a module that named somebody else's name in itself — and the
-- day a path is added to the "bag-window" group would until now have passed
-- silently: the bag replacement would simply stop finding the windows.
--
-- The modules are what is checked: the door is open to them specifically. The
-- core's subsystems call the layer directly and lie in the same directory as it.

T.suite("the layer's names: one answer means a group with no paths")

local core = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", core)
local Compat = core.Compat

local FLAVORS = { "vanilla", "tbc", "mists" }

--- Whether a group holds a path-name on at least one served client.
-- @param group string
-- @return string|nil the path-name itself, if there is one
local function pathIn(group)
    for i = 1, #FLAVORS do
        local names = Compat.GetFrameNames(FLAVORS[i], group)
        for j = 1, #names do
            if names[j]:find(".", 1, true) then return names[j] end
        end
    end
    return nil
end

--- A file's lines without the comment lines.
-- An example in a comment is not a call, and a guard that counts it as one
-- would catch the explanation instead of the code.
-- @param text string
-- @return table an array of lines
local function codeLines(text)
    local out = {}
    for line in text:gmatch("[^\r\n]+") do
        if not line:match("^%s*%-%-") then out[#out + 1] = line end
    end
    return out
end

--- A file's constants of the form `SOMETHING = "group-name"`.
-- A module almost always keeps a group's name in a constant rather than
-- writing it in the call: resolving by constant is what makes the guard applicable to real code.
-- @param lines table
-- @return table variable name -> group name
local function constants(lines)
    local out = {}
    for i = 1, #lines do
        for name, value in lines[i]:gmatch("([%w_%.]+)%s*=%s*\"([%w%-_]+)\"") do
            local short = name:match("([%w_]+)$") or name
            out[short] = value
        end
    end
    return out
end

--- The approaches to the door in a file, parsed into "how many answers were taken".
--
-- The call's shape is read off the line: to its left there is either one
-- receiver or two. Two receivers mean the names and the objects, and to such
-- a read a path in the group is no threat.
--
-- @param lines table the lines of code
-- @return table an array of { arg, one }
local function reads(lines)
    local out = {}
    for i = 1, #lines do
        local line = lines[i]
        -- A module has one door: Darken:GetFrameNames. Compat.Resolve is
        -- named beside it because it is the same door from inside, and a
        -- module that reached the layer directly is obliged to answer by the
        -- same rule. Other "Resolve"s (Broker.Resolve, Store.Resolve) are not it.
        local call = line:match("GetFrameNames%s*%(([^%)]*)%)")
            or line:match("Compat%.Resolve%s*%(([^%)]*)%)")
        if call and call ~= "" then
            -- The call's last argument is the group's name: at a module's
            -- door it is the only one, at the layer the flavour precedes it.
            local arg = call:match("([^,]+)%s*$") or ""
            arg = arg:gsub("^%s+", ""):gsub("%s+$", "")

            -- How many receivers there are on the left. Two means the objects were taken.
            local left = line:match("^%s*local%s+([^=]+)=")
                or line:match("^%s*([%w_%.%[%]%s,]+)=")
            local receivers = 1
            if left then
                local _, commas = left:gsub(",", "")
                receivers = commas + 1
            end

            out[#out + 1] = { arg = arg, one = receivers < 2 }
        end
    end
    return out
end

do
    local folders = helpers.moduleFolders()
    T.ok(#folders > 0, "the shipped modules were found: " .. #folders)

    local checked, unresolved, wrong = 0, {}, {}

    for f = 1, #folders do
        local files = helpers.moduleSources(folders[f])
        for s = 1, #files do
            local handle = io.open(files[s], "r")
            if handle then
                local lines = codeLines(handle:read("*a"))
                handle:close()

                local known = constants(lines)
                local list = reads(lines)
                for i = 1, #list do
                    if list[i].one then
                        local literal = list[i].arg:match("^\"([%w%-_]+)\"$")
                        local group = literal
                            or known[list[i].arg:match("([%w_]+)$") or ""]
                        local declared = group ~= nil
                            and (Compat.HasGroup("vanilla", group)
                                or Compat.HasGroup("tbc", group)
                                or Compat.HasGroup("mists", group))

                        if group == nil then
                            unresolved[#unresolved + 1] =
                                files[s] .. ": " .. list[i].arg
                        elseif declared then
                            checked = checked + 1
                            local path = pathIn(group)
                            if path then
                                wrong[#wrong + 1] = files[s] .. ": " .. group
                                    .. " -> " .. path
                            end
                        end
                    end
                end
            end
        end
    end

    T.ok(checked >= 1, "one-answer reads parsed: " .. checked)
    table.sort(wrong)
    T.eq(#wrong, 0, "a group read by one answer carries no paths: "
        .. table.concat(wrong, " | "))

    -- What was not parsed is named aloud rather than skipped silently: an
    -- argument the guard could not reduce to a group's name is a hole in the guard itself.
    table.sort(unresolved)
    T.eq(#unresolved, 0, "every argument was reduced to a group's name: "
        .. table.concat(unresolved, " | "))
end

T.suite("the layer's names: the guard catches what it is written for")

do
    -- A positive control. Without it the set above stays green even when the
    -- parse has stopped finding anything — and "nothing was found" and
    -- "everything is in order" are different answers.
    local sample = {
        "local BAG_LINK = \"container-item-link\"",
        "local names = Darken:GetFrameNames(BAG_LINK)",
        "local both, objects = Darken:GetFrameNames(BAG_LINK)",
    }

    local known = constants(sample)
    T.eq(known.BAG_LINK, "container-item-link", "the constant was parsed")

    local list = reads(sample)
    T.eq(#list, 2, "both reads were found")
    T.eq(list[1].one, true, "the one-answer read was recognised")
    T.eq(list[2].one, false, "and the read with objects was not")
    T.eq(list[1].arg, "BAG_LINK", "and the argument was reduced to the constant")

    T.ok(pathIn("container-item-link") ~= nil,
        "the example named a group that really does carry a path")
    T.eq(pathIn("bag-window"), nil, "while the neighbouring group carries no paths")
end
