local helpers = require("helpers")

-- Foreign frame names live in one place -- and that is checked, not promised.
--
-- The compatibility layer (Core/Compat.lua) is declared the only place in
-- the addon that knows Blizzard frame names. Until now that promise rested
-- on attentiveness: three modules managed to create their own candidate
-- lists, and every time it was written down honestly -- and every time the list stayed a second one.
--
-- Why a second list is dangerous precisely here. It does not diverge loudly.
-- A name the client does not have is filtered out by the existence filter --
-- and where the core keeps working after a name change, a module with its
-- own old list silently stops doing anything at all. No error, no line in
-- chat: the numbers simply do not appear, the grid simply is not moved. This
-- is invisible in the client, so this check is the only guard.
--
-- It guards one rule: a string that looks like a foreign frame name may
-- occur only in Core/Compat.lua.

T.suite("foreign frame names: the compatibility layer only")

local core = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", core)
local Compat = core.Compat

-- The clients the addon serves. The list is short and known to the
-- compatibility layer; there is no way to ask the layer itself for it, and
-- inventing a function for a check means growing surface for a check.
local FLAVORS = { "vanilla", "tbc", "mists" }

--- Every name known to the compatibility layer, as a set.
-- @return table name -> true
-- @return table group -> true
local function knownNames()
    local names, groups = {}, {}
    for i = 1, #FLAVORS do
        local flavor = FLAVORS[i]
        local list = Compat.Groups(flavor)
        for j = 1, #list do
            groups[list[j]] = true
            local inGroup = Compat.GetFrameNames(flavor, list[j])
            for k = 1, #inGroup do names[inGroup[k]] = true end
        end
    end
    return names, groups
end

local KNOWN, GROUPS = knownNames()

T.ok(next(KNOWN) ~= nil, "the compatibility layer knows at least one name")

--- The .lua files matching a mask, as paths from the repository root.
-- The list is asked of the disk rather than written here by hand: a
-- hand-written one would fail to see a new file exactly when a second list
-- of foreign names appeared in that new file.
-- @param pattern string the mask for dir
-- @return table an array of paths
local function luaFiles(pattern)
    local pipe = io.popen('dir /b /s "' .. pattern .. '" 2>nul')
    if not pipe then return {} end

    local out = {}
    for line in pipe:lines() do
        local path = line:gsub("\\", "/")
        if path:find("%.lua$") then out[#out + 1] = path end
    end
    pipe:close()
    return out
end

--- The module folders, asked of the disk.
--
-- Asked, specifically: a list written here by hand would not notice a new
-- module -- that is, it would stop guarding exactly where a guard is needed.
-- A mask with a wildcard in the folder name (dir /s "Darken_*\*.lua") does
-- not work in cmd and silently returns nothing, so the folders are asked for separately.
-- @return table an array of folder names
local function moduleFolders()
    -- Through the helpers: the rule "a folder with no TOC is not a module"
    -- and the knowledge of the two prefixes are shared by the whole suite.
    return helpers.moduleFolders()
end

--- Every file of the addon: the core and all the modules.
-- @return table an array of paths
local function sourceFiles()
    local out = {}
    local masks = {
        [[Core\*.lua]], [[Modules\*.lua]], [[Config\*.lua]],
        [[Skin\*.lua]], [[Locale\*.lua]],
    }

    local folders = moduleFolders()
    for i = 1, #folders do
        masks[#masks + 1] = folders[i] .. [[\*.lua]]
    end

    for i = 1, #masks do
        local found = luaFiles(masks[i])
        for j = 1, #found do out[#out + 1] = found[j] end
    end
    return out
end

local MODULE_FOLDERS = moduleFolders()
T.ok(#MODULE_FOLDERS >= 5, "the module folders were found: " .. #MODULE_FOLDERS)

local FILES = sourceFiles()
T.ok(#FILES > 60, "the addon files were found: " .. #FILES)

-- The only place foreign frame names belong to.
local HOME = "Core/Compat.lua"

-- Words that look like a frame name but are not a frame.
--
-- "CreateFrame" is the engine function used to create your own frames;
-- "UnitFrame" is a field name on a game nameplate, not a global. The list is
-- deliberately short: every entry here is a hole in the guard, and one is worth adding only with an explanation.
-- Words whose shape resembles a foreign frame name without being one.
--
-- CreateFrame and UnitFrame are parts of the names of our own calls and types.
--
-- ScrollFrame is an AceGUI WIDGET TYPE, not a game frame. The library names
-- its widgets with words, and some of those words end in Frame: it has
-- SimpleGroup, InlineGroup and ScrollFrame. Asking the library for them is
-- ordinary work with a library, not a second list of game names, and there
-- is nothing to guard: should this word diverge from the library, it will
-- answer with an error out loud rather than stay silent the way a diverged frame list does.
local NOT_A_FRAME = {
    CreateFrame = true,
    UnitFrame   = true,
    ScrollFrame = true,
}

-- Exemptions are by place, not by word.
--
-- The only one today: "GameTooltip" in the pet feeding module. That is not
-- a foreign frame name but a widget type in CreateFrame: the module creates
-- its own tooltip to read item text and gives it its own name. The match is
-- exact, because the game named its widget type the same as its frame.
--
-- The exemption is recorded together with the file rather than as a general
-- word list: an "anywhere" permission would open the door to exactly what
-- this check guards against -- a module hiding the game tooltip by name.
local EXCEPTIONS = {
    ["Features/PetFeed/Source.lua"] = { GameTooltip = true },

    -- "ColorPickerFrame" in the styling of the colour picker window.
    --
    -- The guard guards against a second candidate list: the names a module
    -- walks the game interface by must lie in one place, because a diverged
    -- list does not complain but silently stops doing anything.
    --
    -- This is neither a list nor a walk. This is one window opened not by the
    -- addon but by the settings library: a click on a colour swatch shows
    -- ColorPickerFrame, and we have no way to reach it other than by name --
    -- the object does not lie in any field we can reach.
    --
    -- The name does not belong to the compatibility layer by meaning either:
    -- all it knows are the frame groups the addon darkens and moves, and the
    -- colour picker belongs to none of them and must not.
    -- Putting it there would mean creating a "darken the colour picker"
    -- setting nobody asked for.
    --
    -- The cost of a wrong name is different too: a list diverged from the
    -- client is silent, while this is a native golden window in the middle of
    -- a dark one, that is exactly what the author complained about. That is visible at first glance.
    ["Skin/Picker.lua"] = { ColorPickerFrame = true },
}

--- Whether a string looks like a foreign frame name.
--
-- Two rules. The first is a name the compatibility layer already knows: its
-- repetition anywhere else IS that second list. The second is the shape of
-- the name: "SomethingFrame", "SomethingFrame12", "SomethingSlot". It
-- catches a list the core does not have at all yet -- and that is exactly how all three previous ones appeared.
--
-- Our own name (with the Darken prefix) is not a Blizzard frame: a module is
-- free to name its own windows as it likes.
-- @param literal string
-- @return string|nil what exactly the string is guilty of
local function looksForeign(literal)
    if literal == "" then return nil end
    if NOT_A_FRAME[literal] then return nil end
    if literal:find("^Darken") then return nil end

    if KNOWN[literal] then return "a name from the compatibility layer" end

    if literal:match("^%u[%w_]*Frame%d*$")
        or literal:match("^%u[%w_]*Slot%d*$") then
        return "looks like a foreign frame name"
    end

    -- A path into a foreign object -- "MainActionBar.LeftEndCap". That is the
    -- third form of a foreign name, and it is dangerous for exactly the same
    -- reason: a path diverged from the client does not complain but silently
    -- finds nothing. Formerly this form did not exist at all, and the
    -- knowledge of foreign frame fields lay in the subsystem as a list like
    -- { "LeftEndCap", "RightEndCap" } -- a second knowledge outside the layer that the guard did not see.
    --
    -- Every step is required to be capitalised: that is how a path differs
    -- from a file name ("BarTexture1.tga") and from a number with a dot,
    -- while the game fields and tables are all capitalised -- LeftEndCap, EndCaps, C_PetInfo.GetPetHappiness.
    -- A lower-case field will slip past the guard; that is a named hole, not
    -- an oversight, and closing it at the price of false positives on paths
    -- to textures is not worth it.
    if literal:match("^%u[%w_]*%.%u[%w_]*$")
        or literal:match("^%u[%w_]*%.%u[%w_]*%.%u[%w_]*$") then
        return "looks like a path into a foreign object"
    end

    return nil
end

-- The guard must catch what it was created for, and that is checked right
-- here: a rule that stopped firing looks exactly like a clean repository.
--
T.ok(looksForeign("MainActionBar.LeftEndCap") ~= nil,
    "a path into a foreign object is caught")
T.ok(looksForeign("C_PetInfo.GetPetHappiness") ~= nil,
    "a path into a game table is caught")
T.ok(looksForeign("BarTexture1.tga") == nil, "a file name does not count as a path")
T.ok(looksForeign("DarkenBarFrame") == nil, "our own name does not count as foreign")

-- The fourth form of a foreign name: a path written not as one string but as
-- two strings side by side -- { "C_PetInfo", "GetPetHappiness" }.
--
-- That is exactly how the pet feeding module carried its names, and the
-- guard did not see them: there is no dot in the literal, and neither word
-- on its own looks like a frame name. This form appeared not out of laziness
-- but out of necessity: while the layer could name only globals, there was
-- no way to express a field inside a table. Now there is, and the pair became the same second list as everything else here.
--
-- The rule is deliberately narrow: a pair is caught when the layer has
-- already given that path a name -- by one of its groups or by its watch
-- list. That is what was promised: the hole is closed by moving names into
-- the layer rather than by softening the rule, because as soon as a name
-- enters the layer, both spellings -- the string and the pair -- become offences by themselves.
--
-- And so it went. The container function names -- { "C_Container",
-- "GetContainerNumSlots" } and four neighbours -- were a named hole of this
-- rule: five modules carried them as pairs, and they did not belong to the layer.
-- Now they do (the groups "container-slots", "container-item",
-- "container-free-slots", "container-item-link", "container-pickup"), and
-- the guard catches them in both forms without changing anything in itself.
--
-- WHAT DELIBERATELY STAYS OUTSIDE, and it is still named:
--
--   * a pair the layer never gave a name to. Catching it by shape alone
--     ("capital, dot, capital") would mean declaring an offence of any two
--     neighbouring capitalised strings -- including { "Meat", "Fish" } and
--     the keys of our own tables. A second list the layer does not know yet
--     is caught not here but by reading the place itself;
--   * a lower-case field ("frame.leftCap"): see the caveat above;
--   * the item lookup names (GetItemInfo and neighbours) in the modules.
--     They stand there legitimately: they do not differ between the served
--     clients, and the layer is about differences; putting everything a
--     module calls into it would turn it into a game API reference.
local LAYER_PATHS = {}
for name in pairs(KNOWN) do LAYER_PATHS[name] = true end
do
    local watch = Compat.Watchlist()
    T.ok(#watch > 0, "the watch list of the layer was read")
    for i = 1, #watch do LAYER_PATHS[watch[i].path] = true end
end

--- Whether a pair of neighbouring literals is an offence.
-- @param first string
-- @param second string
-- @return string|nil what exactly
local function looksForeignPair(first, second)
    if LAYER_PATHS[first .. "." .. second] then
        return "a path written as a pair of strings"
    end
    return nil
end

-- A pair of neighbouring literals adding up to a layer path is a foreign
-- name written around the layer. A live path from the watch list is used.
T.ok(looksForeignPair("C_Container", "GetContainerNumSlots") ~= nil,
    "a path written as a pair of strings is caught")
T.ok(looksForeignPair("C_Container", "GetContainerItemInfo") ~= nil,
    "and so is a second pair of the same kind")

-- What this work was done for: a pair that used to be a named hole is now
-- caught by itself -- the rule is untouched and the name moved into the layer.
T.ok(looksForeignPair("C_Container", "GetContainerNumSlots") ~= nil,
    "the container function pair is caught")
T.ok(looksForeignPair("C_Container", "GetContainerItemInfo") ~= nil,
    "and the second one, whose two spellings answer differently")
T.ok(looksForeign("C_Container.PickupContainerItem") ~= nil,
    "the same function written as a string is an offence too")
T.ok(looksForeign("GetContainerNumSlots") ~= nil,
    "and so is a bare name from a group: the layer knows it itself")

--- Pairs of neighbouring literals: "A", "B".
-- @param text string
-- @return table an array of { first, second } pairs
local function literalPairs(text)
    local out = {}
    for first, second in text:gmatch('"([^"\n]*)"%s*,%s*"([^"\n]*)"') do
        out[#out + 1] = { first, second }
    end
    return out
end

--- The double-quoted string literals of a file.
-- @param text string
-- @return table an array of strings
local function literals(text)
    local out = {}
    for literal in text:gmatch('"([^"\n]*)"') do out[#out + 1] = literal end
    return out
end

local function read(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

do
    local offences = {}
    local homeSeen = false

    for i = 1, #FILES do
        local path = FILES[i]
        -- The path from the disk is absolute; the tail from the repository root is taken.
        -- The path is shortened to something recognisable. A file of a part
        -- has three recognisable path components: Features, the part name and
        -- the file name -- two are not enough, because "Filter.lua" exists both for the auras and for the nameplates.
        local short = path:match("Features/[^/]+/[^/]+%.lua$")
            or path:match("[^/]+/[^/]+%.lua$") or path
        if short == HOME then homeSeen = true end

        local text = read(path)
        if text and short ~= HOME then
            local seen = {}
            local allowed = EXCEPTIONS[short] or {}
            local list = literals(text)
            for j = 1, #list do
                local why = not allowed[list[j]] and looksForeign(list[j])
                if why and not seen[list[j]] then
                    seen[list[j]] = true
                    offences[#offences + 1] = short .. ": \"" .. list[j]
                        .. "\" — " .. why
                end
            end

            local pairsFound = literalPairs(text)
            for j = 1, #pairsFound do
                local first, second = pairsFound[j][1], pairsFound[j][2]
                local joined = first .. "." .. second
                local why = not allowed[joined]
                    and looksForeignPair(first, second)
                if why and not seen[joined] then
                    seen[joined] = true
                    offences[#offences + 1] = short .. ": \"" .. first
                        .. "\", \"" .. second .. "\" — " .. why
                end
            end
        end
    end

    table.sort(offences)
    T.ok(homeSeen, "the compatibility layer itself is in the walk")
    T.eq(#offences, 0, "there are no foreign names outside " .. HOME .. ", found: "
        .. table.concat(offences, " | "))
end

T.suite("frame names: a module does not call its neighbour by a global name")

do
    -- The second way around the contract is not a list of Blizzard names but
    -- the frame name of a neighbouring module. It looks more harmless (the
    -- name is ours, after all) and costs the same: such access has no witness
    -- of the redraw, and a neighbour that renames its window breaks the other module silently.
    --
    -- The rule is simple and checkable: a name of the form "Darken...Frame..."
    -- may occur only in the folder that creates that frame.
    local owners = {}   -- name -> { folder = true }

    for i = 1, #FILES do
        local path = FILES[i]
        local folder = path:match("([^/]+)/[^/]+%.lua$")
            or path:match("([^/]+)/[^/]+/[^/]+%.lua$")
        local text = read(path)

        if folder and text then
            -- The locale folder of a module belongs to its own module.
            local owner = path:match("(Darken_[%w_]+)/") or folder

            local list = literals(text)
            for j = 1, #list do
                local literal = list[j]
                if literal:match("^Darken[%w_]*Frame[%w_]*$") then
                    local byName = owners[literal]
                    if not byName then
                        byName = {}
                        owners[literal] = byName
                    end
                    byName[owner] = true
                end
            end
        end
    end

    local shared = {}
    for name, folders in pairs(owners) do
        local list = {}
        for folder in pairs(folders) do list[#list + 1] = folder end
        if #list > 1 then
            table.sort(list)
            shared[#shared + 1] = name .. ": " .. table.concat(list, ", ")
        end
    end
    table.sort(shared)

    T.eq(#shared, 0, "no module frame name is named in a foreign folder: "
        .. table.concat(shared, " | "))
end

T.suite("frame groups: the new ones exist for every client")

do
    -- The groups created for the three modules that formerly carried their
    -- own lists. What is checked is what they rely on: the group exists for
    -- every client and is non-empty. An empty group would mean a silently
    -- non-working module -- the same failure as a diverged list.
    local NEW = {
        "auras", "equipment-slots", "equipment-slots-inspect", "inspect-window",
    }

    for i = 1, #FLAVORS do
        for j = 1, #NEW do
            T.eq(Compat.HasGroup(FLAVORS[i], NEW[j]), true,
                FLAVORS[i] .. ": the group " .. NEW[j] .. " is declared")
        end
    end

    T.eq(#Compat.GetFrameNames("vanilla", "equipment-slots"), 19,
        "there are nineteen equipment slots")
    T.eq(Compat.GetFrameNames("vanilla", "equipment-slots")[1],
        "CharacterHeadSlot", "and the button name is assembled from the window prefix")
    T.eq(Compat.GetFrameNames("mists", "equipment-slots-inspect")[1],
        "InspectHeadSlot", "the inspect window is the same button with a different prefix")

    -- A copy is returned: spoiling the answer, a module spoils nobody's list.
    local copy = Compat.GetFrameNames("tbc", "auras")
    copy[1] = "SPOILED"
    T.eq(Compat.GetFrameNames("tbc", "auras")[1] ~= "SPOILED", true,
        "the answer is a copy, not the shared table")

    -- A client with no such windows at all. That is exactly why the names are
    -- declared as candidates: an empty list reaches the module, and the module does nothing.
    for j = 1, #NEW do
        local names = Compat.GetFrameNames("vanilla", NEW[j])
        T.eq(#Compat.FilterExisting(names, {}), 0,
            NEW[j] .. ": on a client without these frames no names remain")
    end

    -- And conversely: whatever the client does have arrives in full.
    T.eq(#Compat.FilterExisting(Compat.GetFrameNames("mists", "auras"),
        { BuffFrame = {}, DebuffFrame = {} }), 2,
        "while what does exist reaches the module")
end

T.suite("frame groups: the contract document names every one")

do
    -- The groups are part of the public promise: a foreign module author uses
    -- this list to decide whether the core has what they need or whether to
    -- write their own list. A group declared in the code and not named in the
    -- document is an invitation to create a second list, that is exactly the
    -- defect being fixed here.
    local text = read("docs/module-api.md")
    T.ok(text ~= nil, "the contract document was opened")

    local missing = {}
    for group in pairs(GROUPS) do
        if not (text or ""):find("`" .. group .. "`", 1, true) then
            missing[#missing + 1] = group
        end
    end
    table.sort(missing)

    T.eq(#missing, 0, "the document names every group, not named: "
        .. table.concat(missing, " | "))
end
