local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- Shortening long names to a nameplate's width.
--
-- Pure arithmetic over a string and not one call into the game: the width
-- arrives as a number, the font's height as a number, the name as a string.
-- So the rule is tested outside the client in every outcome, including the
-- one it was written as a separate file for.
--
-- === Why string.sub will not do ===
--
-- A name arrives from the game in the client's language. A Cyrillic name
-- takes about twice as many bytes as it has letters in UTF-8, and
-- string.sub(name, 1, 12) cuts it in the middle of a letter. A string cut in
-- the middle of a letter is not a short name but a broken question mark in a
-- diamond, and the addon is what looks at fault. So the counting goes by
-- characters rather than by bytes: a UTF-8 character's lead byte is
-- recognised by not lying in the continuation range (0x80..0xBF).
--
-- The game's string functions (strlenutf8) are deliberately not here: they do
-- not exist on all the supported clients, while the rule has to work the same
-- everywhere and be testable without a client.

local Names = {}
ns.Names = Names

-- What marks a cut. Three dots rather than a single ellipsis character: that
-- character is not in every font the player may choose on the Fonts page, and
-- a missing character is drawn as nothing — so the name would look merely
-- truncated, with no sign that it was cut.
local ELLIPSIS = "..."
Names.ELLIPSIS = ELLIPSIS

-- How much narrower an average character is than the font's height. The
-- number is one and lives here: only the engine can measure a string's width
-- for real (FontString:GetStringWidth), and it answers only after the string
-- has been assigned — that is, after a long name has already stretched the
-- nameplate. An upper estimate is cheaper than the truth: one character cut
-- too many is invisible, while a name that ran past the bar's edge is seen at
-- once.
local CHAR_RATIO = 0.5
Names.CHAR_RATIO = CHAR_RATIO

--- How many characters a UTF-8 string holds.
-- Continuation bytes (0x80..0xBF) are not counted: a character is its lead
-- byte.
-- @param text any
-- @return number
function Names.Length(text)
    if type(text) ~= "string" then return 0 end

    local count = 0
    for i = 1, #text do
        local byte = text:byte(i)
        if byte < 128 or byte >= 192 then count = count + 1 end
    end
    return count
end

--- The byte position a character with the given index starts at.
-- Needed by the cut: cutting is allowed only on a character boundary.
-- @param text string
-- @param index number the character's index, counting from one
-- @return number|nil the byte position; nil when there are fewer
--         characters
local function byteOf(text, index)
    if index <= 1 then return 1 end

    local count = 0
    for i = 1, #text do
        local byte = text:byte(i)
        if byte < 128 or byte >= 192 then
            count = count + 1
            if count == index then return i end
        end
    end
    return nil
end
Names.ByteOf = byteOf

--- Cut a name down to a given number of characters.
--
-- The limit counts the cut mark in: a name squeezed to eight characters
-- occupies eight characters on screen, not eight plus three. Otherwise the
-- width setting would mean nothing — on precisely the long names it exists
-- for.
--
-- A limit smaller than the mark itself means "there is no room at all": then
-- the first characters are returned with no mark. An empty string instead of
-- a name is worse than a truncated name: the player sees a bar with no owner.
--
-- @param text any the name
-- @param limit any the limit in characters
-- @return string
function Names.Truncate(text, limit)
    if type(text) ~= "string" then return "" end

    local max = tonumber(limit)
    if not max or max ~= max then return text end
    if max <= 0 then return "" end

    local length = Names.Length(text)
    if length <= max then return text end

    local mark = Names.Length(ELLIPSIS)
    if max <= mark then
        local cut = byteOf(text, max + 1)
        return cut and text:sub(1, cut - 1) or text
    end

    local keep = max - mark
    local cut = byteOf(text, keep + 1)
    if not cut then return text end
    return text:sub(1, cut - 1) .. ELLIPSIS
end

--- How many characters fit into a given width.
-- The font's height is the one the player chose on the Fonts page; the engine
-- does not know a character's width before the string is assigned, so it is
-- estimated from above.
-- @param width any the width in pixels
-- @param fontHeight any the font's height in pixels
-- @return number characters, never fewer than one
function Names.Budget(width, fontHeight)
    local w = tonumber(width)
    local h = tonumber(fontHeight)
    if not w or w ~= w or w <= 0 then return 1 end
    if not h or h ~= h or h <= 0 then return 1 end

    local per = h * CHAR_RATIO
    if per <= 0 then return 1 end

    local count = math.floor(w / per)
    if count < 1 then return 1 end
    return count
end

--- A name fitted to a width.
-- The two rules above joined, and the only thing the display calls.
-- @param text any
-- @param width any
-- @param fontHeight any
-- @return string
function Names.Fit(text, width, fontHeight)
    return Names.Truncate(text, Names.Budget(width, fontHeight))
end
