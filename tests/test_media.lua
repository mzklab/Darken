local helpers = require("helpers")

-- The addon's own textures: the set's contents, the names and the registration.
--
-- There is something to check here. A texture's name is a key of the
-- LibSharedMedia registry and a setting's value in SavedVariables: two
-- identical names mean one texture silently vanished from the list, while a
-- path to a file that does not exist gives not an error in the game but an
-- empty bar — a defect noticed last. So the paths are checked against the disk.

T.suite("media: the set of textures")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Media.lua", ns)

local textures = ns.Media.Textures()

local paths, count = {}, 0
local duplicatePath, missingFile, badPrefix = {}, {}, {}

for name, path in pairs(textures) do
    count = count + 1

    if paths[path] then duplicatePath[#duplicatePath + 1] = path end
    paths[path] = true

    if not name:find("^Darken ") then badPrefix[#badPrefix + 1] = name end

    -- In the game a path begins with Interface\AddOns\Darken\; the test
    -- set is run from the addon's root, so the path's tail is what is checked.
    local file = path:match("Media\\(.+)$")
    local handle = file and io.open("Media/" .. file, "rb")
    if handle then
        handle:close()
    else
        missingFile[#missingFile + 1] = tostring(path)
    end
end

-- Nine keys in the "name -> path" table also mean the names did not collide:
-- an identical name would have collapsed two records into one and there would
-- be eight keys. That is checked separately against Entries' length below.
T.eq(count, 9, "there are nine textures in the set")
T.eq(#duplicatePath, 0, "the paths do not repeat: " .. table.concat(duplicatePath, "; "))
T.eq(#missingFile, 0, "every path has a file: " .. table.concat(missingFile, "; "))
T.eq(#badPrefix, 0, "every name carries the shared prefix: " .. table.concat(badPrefix, "; "))

-- Exactly the nine files that lie in Media/. The list is written out here in
-- full deliberately: otherwise a lost record would slip past the count check
-- if somebody added another one along with it.
local expected = {
    ["BarTexture1.tga"] = true,
    ["mzk.tga"]         = true,
    ["mzk-blue.tga"]    = true,
    ["mzk-cyan.tga"]    = true,
    ["mzk-dark.tga"]    = true,
    ["mzk-green.tga"]   = true,
    ["mzk-orange.tga"]  = true,
    ["mzk-red.tga"]     = true,
    ["mzk-yellow.tga"]  = true,
}

local entries = ns.Media.Entries()
T.eq(#entries, 9, "Entries returns those same nine records")
local unexpected = {}
for i = 1, #entries do
    if not expected[entries[i].file] then
        unexpected[#unexpected + 1] = entries[i].file
    end
    expected[entries[i].file] = nil
end
T.eq(#unexpected, 0, "there are no extra files: " .. table.concat(unexpected, "; "))
local leftover = {}
for file in pairs(expected) do leftover[#leftover + 1] = file end
T.eq(#leftover, 0, "not one file was forgotten: " .. table.concat(leftover, "; "))

-- A copy rather than the shared table: having spoiled it, a caller would have spoiled the set.
textures["Darken Purple"] = "rubbish"
T.ok(ns.Media.Textures()["Darken Purple"] ~= "rubbish",
    "Textures returns a copy")

T.suite("media: the registration")

-- The library's absence is an ordinary answer rather than an error: without
-- LibSharedMedia the select lists are simply empty, and bringing the load down over that is not allowed.
T.eq(ns.Media.Register(nil), 0, "with no library nothing is registered")
T.eq(ns.Media.Register({}), 0, "an object with no Register is survived too")

-- A stand-in library: it records everything handed to it.
local fake = { calls = {} }
function fake:Register(mediatype, key, data)
    self.calls[#self.calls + 1] = { mediatype = mediatype, key = key, data = data }
    return true
end

T.eq(ns.Media.Register(fake), 9, "the first call registers nine textures")
T.eq(#fake.calls, 9, "the library received nine records")

-- A repeated call is obliged to add nothing: the media file may be read
-- twice, and the registry must not double because of it.
T.eq(ns.Media.Register(fake), 0, "a repeated call adds nothing")
T.eq(#fake.calls, 9, "there are still nine records")

-- One category for all nine. The addon neither ships nor registers fonts: a
-- third-party font without Cyrillic breaks the Russian client, and there are
-- none of our own yet.
local wrongType, registeredNames = {}, {}
for i = 1, #fake.calls do
    local call = fake.calls[i]
    if call.mediatype ~= "statusbar" then
        wrongType[#wrongType + 1] = tostring(call.mediatype)
    end
    registeredNames[call.key] = call.data
end
T.eq(#wrongType, 0, "everything is registered as statusbar: " .. table.concat(wrongType, "; "))

local mismatched = {}
for name, path in pairs(ns.Media.Textures()) do
    if registeredNames[name] ~= path then
        mismatched[#mismatched + 1] = name
    end
end
T.eq(#mismatched, 0, "the paths that went into the registry are the set's: "
    .. table.concat(mismatched, "; "))

-- A path is obliged to begin with Interface\: LibSharedMedia refuses files
-- outside that folder (RESTRICTED_FILE_ACCESS), and such a texture would
-- silently fail to register.
local outside = {}
for name, path in pairs(ns.Media.Textures()) do
    if not path:lower():find("^interface\\") then
        outside[#outside + 1] = name .. " -> " .. path
    end
end
T.eq(#outside, 0, "every path is inside Interface\\: " .. table.concat(outside, "; "))

T.suite("media: the addon's own look names textures that exist")

-- The set in Core/Defaults.lua stores the textures' names as strings. A typo
-- there gives neither an error nor an empty bar: the choice simply will not
-- be found, and the "our own look" button will silently change nothing.
helpers.loadAddonFile("Core/Defaults.lua", ns)

-- The textures' names do not lie in every field of the set: the colour modes
-- live beside them, and looking for those in the texture registry is
-- meaningless. The fields are enumerated separately
-- (ns.PRESET_TEXTURE_FIELDS). The other presets are checked by the same list in tests/test_presets.lua — where their contents are checked.
for section, fields in pairs(ns.PRESET_TEXTURE_FIELDS) do
    local values = ns.Recommended[section]
    for i = 1, #fields do
        local field = fields[i]
        local name = values and values[field]
        if name ~= nil then
            T.ok(textures[name] ~= nil,
                "the texture \"" .. tostring(name) .. "\" (" .. field .. ") is in the addon's set")
        end
    end
end
