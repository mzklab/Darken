local ADDON, ns = ...

-- Registration of the addon's own textures in LibSharedMedia-3.0.
--
-- Why registration happens while this file loads rather than from
-- OnInitialize. Settings pages are declared while their own files load, and a
-- dropdown's values are computed when the list opens. A file of the addon
-- runs before any OnInitialize, so registering at file scope is guaranteed to
-- be in time: by the time anything asks for the statusbar list, the nine
-- textures are already in the registry. The opposite order would give an
-- empty list on the window's first opening — a defect that is not noticed at
-- once.
--
-- The addon ships and registers no fonts. The font registry is non-empty
-- anyway: LibSharedMedia adds the game's own fonts, plus whatever other
-- addons brought.

local Media = {}
ns.Media = Media

-- The path the client looks for the addon's files under. The separator is a
-- backslash: the engine accepts no other.
local ROOT = "Interface\\AddOns\\Darken\\Media\\"

-- The nine statusbar textures shipped with the addon.
--
-- The names are built the same way: the shared "Darken" prefix and the colour
-- in English. The prefix groups them together in a sorted dropdown and says
-- at once whose they are.
--
-- THE NAMES ARE NOT TRANSLATED. They must never be passed through
-- ns.Localize: a texture name is a key in the LibSharedMedia registry, which
-- is shared by every addon in the session, and at the same time a setting's
-- value in SavedVariables. Translating on the fly would mean that players on
-- different client languages store the same choice under different keys, and
-- that changing the language loses the saved texture. The addon's base
-- language is English (spec, 5.4), and these strings belong to it rather than
-- to a locale.
--
-- Renaming one after the fact is not free either: the player's saved choice
-- would stop being found. Any rename has to come with a profile migration
-- (Core/Defaults.lua, ns.Migrations) — that is how the move from the former
-- Russian names to the present English ones was done.
--
-- The order of the entries is the list order when names tie, so it does not
-- matter; it reads as alphabetical by colour.
local TEXTURES = {
    { name = "Darken Blue",   file = "mzk-blue.tga"    },
    { name = "Darken Cyan",   file = "mzk-cyan.tga"    },
    { name = "Darken Dark",   file = "mzk-dark.tga"    },
    { name = "Darken Green",  file = "mzk-green.tga"   },
    { name = "Darken Orange", file = "mzk-orange.tga"  },
    -- BarTexture1 is the only texture of a different size (256x32); the
    -- rest are 711x89. To the player it is simply one more colour.
    { name = "Darken Pink",   file = "BarTexture1.tga" },
    { name = "Darken Purple", file = "mzk.tga"         },
    { name = "Darken Red",    file = "mzk-red.tga"     },
    { name = "Darken Yellow", file = "mzk-yellow.tga"  },
}

--- The texture name -> file path mapping.
-- A pure function: it reads nothing from the game or from the library, so the
-- set's contents are tested outside the client. A new table is returned so
-- that the caller cannot damage the shared list.
-- @return table name -> path
function Media.Textures()
    local out = {}
    for i = 1, #TEXTURES do
        out[TEXTURES[i].name] = ROOT .. TEXTURES[i].file
    end
    return out
end

--- The entries in declaration order, with name and file name separate.
-- Needed by the tests, which check the file on disk, and by any code that
-- cares about the order. A copy, not the shared table.
-- @return table array of { name = string, file = string }
function Media.Entries()
    local out = {}
    for i = 1, #TEXTURES do
        out[i] = { name = TEXTURES[i].name, file = TEXTURES[i].file }
    end
    return out
end

--- Names of the statusbar textures known to this client.
--
-- Why this is separate from Media.Textures. That one knows only our nine,
-- while the player's list needs all of them, including those brought by other
-- addons. The LibSharedMedia registry is shared by the session, and it is the
-- one to ask.
--
-- The library arrives as an argument rather than from LibStub: that makes the
-- function testable outside the game, and its absence an ordinary answer
-- rather than an error. Without the library our nine remain: they are files
-- inside the addon and work with no registry at all.
--
-- A new array is returned: the shared list would let the caller rewrite the
-- texture registry for the whole addon.
-- @param media table|nil a LibSharedMedia-3.0 object, or a compatible one
-- @return table array of names
function Media.BarNames(media)
    local out = {}

    if type(media) == "table" and type(media.List) == "function" then
        local ok, list = pcall(media.List, media, "statusbar")
        if ok and type(list) == "table" then
            for i = 1, #list do
                if type(list[i]) == "string" then out[#out + 1] = list[i] end
            end
        end
    end

    if #out == 0 then
        for i = 1, #TEXTURES do out[i] = TEXTURES[i].name end
    end

    table.sort(out)
    return out
end

--- The file path of a statusbar texture, by its name.
--
-- Our nine first, then the library's registry. That order is deliberate: ours
-- are files inside the addon and are found even when the library is not
-- installed at all, and they cannot be confused with anybody else's — their
-- names start with "Darken".
-- @param media table|nil a LibSharedMedia-3.0 object, or a compatible one
-- @param name any the presumed texture name
-- @return string|nil the file path
function Media.BarPath(media, name)
    if type(name) ~= "string" or name == "" then return nil end

    for i = 1, #TEXTURES do
        if TEXTURES[i].name == name then return ROOT .. TEXTURES[i].file end
    end

    if type(media) ~= "table" then return nil end
    if type(media.IsValid) ~= "function" or type(media.Fetch) ~= "function" then
        return nil
    end

    local asked, valid = pcall(media.IsValid, media, "statusbar", name)
    if not asked or not valid then return nil end

    -- noDefault = true: a name may be known to the registry while no path
    -- stands behind it. Silently substituting somebody else's texture would
    -- be worse than refusing.
    local fetched, path = pcall(media.Fetch, media, "statusbar", name, true)
    if not fetched or type(path) ~= "string" or path == "" then return nil end

    return path
end

-- Registration already happened. A flag rather than a registry check: a
-- second call must do nothing, whatever library object it is given.
local registered = false

--- Register the textures in LibSharedMedia.
-- The library arrives as an argument rather than from LibStub, which makes
-- the function testable outside the game. Its absence is an ordinary answer
-- rather than an error: without it the dropdowns are merely empty, and that
-- must not break loading the addon. The Register call is guarded by pcall:
-- the library is somebody else's, its version may have a different signature,
-- and one texture must not abort the rest.
-- @param media table|nil a LibSharedMedia-3.0 object, or a compatible one
-- @return number how many entries this call added
function Media.Register(media)
    if registered then return 0 end
    if type(media) ~= "table" or type(media.Register) ~= "function" then
        return 0
    end

    local count = 0
    for i = 1, #TEXTURES do
        local entry = TEXTURES[i]
        local ok = pcall(media.Register, media, "statusbar", entry.name,
            ROOT .. entry.file)
        if ok then count = count + 1 end
    end

    registered = true
    return count
end

-- Outside the game (in tests) there is no global LibStub — there is then
-- nothing to register and nowhere to register it, and the file merely defines
-- its functions. LibStub is a table with __call rather than a function, so its
-- presence is checked and the call itself goes through pcall: the `true`
-- second argument asks the library not to complain about a missing
-- LibSharedMedia, but other versions of LibStub may not know that
-- argument.
if LibStub then
    local ok, media = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok then
        Media.Register(media)
    end
end
