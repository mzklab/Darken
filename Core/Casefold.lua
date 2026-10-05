local ADDON, ns = ...

-- Letter case: one mapping table for the whole addon. Folding for comparison
-- (Fold, Key) and capitals for display (Upper). The core exposes this through
-- Darken:GetCasefold() (contract version 10, docs/module-api.md).
--
-- === Why this lives in the core ===
--
-- string.lower in Lua 5.1 folds byte by byte and knows only ASCII. The game
-- hands over names in UTF-8, where a Cyrillic letter takes two bytes, and the
-- byte-wise lower does not touch them at all. Everyone who plays on a Russian
-- client has seen the consequence: typing "хлеб" does not find "Хлеб" — and
-- that is not "no match" but "there would be a match had you typed a capital
-- letter", about which the search box says nothing.
--
-- Three subsystems hit this separately and wrote the same caveat in three
-- places: the bags' search box and the item database's query language (both
-- addons have since been removed) and the shared aura filter
-- (Core/AuraFilter.lua). Three copies of one limitation are the very shape
-- this project has already reconciled twice (frame names, aura filtering).
-- Reconciled a third time.
--
-- === Which alphabets, and why these ===
--
-- Not "all of Unicode", but exactly the letters that occur in names on the
-- clients the addon supports:
--
--   Cyrillic (U+0400..U+045F) — the Russian client, for whose sake all of
--       this was started. The range is taken whole rather than as "the 33
--       Russian letters": it also holds the Ukrainian і, ї, є (U+0406,
--       U+0407, U+0404), the Belarusian ў and the Serbian њ, љ. The author
--       writes in Ukrainian, and "Ігор" must be found by typing "ігор";
--   the Ukrainian Ґ (U+0490) — the only Ukrainian letter outside that range,
--       and therefore named on a line of its own;
--   Latin letters with diacritics (U+00C0..U+00DE) — the German, French,
--       Spanish, Italian and Portuguese clients. Ä, É, Ç, Ñ, Õ are ordinary
--       letters in item names on those clients.
--
-- What is deliberately absent:
--
--   Latin Extended-A (U+0100..U+017F) — Polish, Czech, Hungarian, Romanian.
--       The game has no client in those languages: there is no reason to pay
--       a table for a language the game never shipped in;
--   the Turkish İ (U+0130) and ı (U+0131) — the classic trap. There is no
--       Turkish client, and the "correct" Turkish mapping would fold the
--       Latin I into ı and break search for everybody else: "I" and "i" are
--       one letter on ten clients out of eleven. Both Turkish letters fold to
--       nothing and stay themselves;
--   ß (U+00DF) — it is lower case already. Folding it to "ss" is not
--       allowed: that changes the string's length and makes "Straße" and
--       "Strasse" one word, which the game does not do;
--   the Korean and Chinese clients — their scripts have no case at all, so
--       there is nothing to fold;
--   × (U+00D7) and ÷ (U+00F7) — the multiplication and division signs, which
--       sit inside the Latin range. The "add 0x20" arithmetic would turn one
--       into the other silently; here × is excluded from the range by
--       name.
--
-- === Why a table rather than arithmetic ===
--
-- The table is built by arithmetic once at load time — two loops over the
-- ranges and two lines for the exceptions — while folding is a lookup in the
-- finished map. That way an error in a range boundary is visible where it was
-- made rather than in every letter on screen, and the exception (×) is
-- written on one line rather than as a branch on the hot path.
--
-- === What this does not do ===
--
-- It does not change what is stored. Folding is for comparison: an item's
-- name is kept as the game gave it, and what the player typed as they typed
-- it. No subsystem writes a folded string into SavedVariables or onto the
-- screen.
--
-- === Why capitals live here too ===
--
-- Settings headings were shown in capitals, and before contract 10 they had
-- byte arithmetic of their own in the styling layer. The work differs —
-- folding is for comparison, raising is for display — but the knowledge is
-- the same: which letters belong to which alphabet and where they sit. That
-- knowledge is already written here, and written a second time it diverges
-- silently: that copy knew the Russian а-я and ё and knew neither the
-- Ukrainian і, ї, є, ґ nor the Latin letters with diacritics, so "Профілі"
-- was displayed as "ПРОФІЛІ" — every letter capital except the author's own.
--
-- So the capitals table is derived by inverting this one rather than by a
-- second set of loops over the same ranges: an alphabet added lands in both
-- directions at once, and there is nowhere for them to diverge.
--
-- === How raising case is not the mirror of folding ===
--
-- Inverting the table gives the right answer not because "case is
-- reversible", but because everything irreversible was excluded from the
-- table in advance. Checked letter by letter:
--
--   ß (U+00DF) — absent here, and absent from the inverted table too. For
--       folding the reason was "it is lower case already"; for raising the
--       reason is stronger and specific to this direction: ß raises to "SS",
--       that is, to two letters, and the string's length changes. A heading
--       that grew by a letter is a line break in a block's label;
--   İ (U+0130) and ı (U+0131) — both absent here as well, but the trap is
--       mirrored. Folding feared the "I -> ı" rule; raising fears "i -> İ".
--       There is no Turkish client, and it would break for everybody else;
--   ÷ (U+00F7) — the mirror of ×. In the table × is not a value but an
--       excluded key, so in the inverted table ÷ is not a key and subtracting
--       0x20 does not touch it. One exception, written once, working in both
--       directions;
--   ÿ (U+00FF) — the only letter raising adds to the exception list on its
--       own. Its capital is Ÿ (U+0178), which is Latin Extended-A, absent
--       here on purpose. Folding Ÿ is not needed (its lower case ÿ is lower
--       case already) while raising it would be — but adding the pair would
--       mean admitting one character from a block excluded entirely, and the
--       next such character would be added without thinking. The addon has no
--       labels of its own in French (Locale/ruRU.lua, Locale/ukUA.lua and the
--       English strings in the code), so there is nowhere for ÿ to enter a
--       heading from; it stays itself, and that is stated here rather than
--       discovered by eye.

local Casefold = {}
ns.Casefold = Casefold

--- A character with code 0x80..0x7FF, as two UTF-8 bytes.
-- @param code number
-- @return string
local function two(code)
    return string.char(192 + math.floor(code / 64), 128 + code % 64)
end

-- The upper -> lower mapping; both sides UTF-8, both two bytes.
local MAP = {}

--- Record a pair in the table.
-- @param upper number code of the upper-case letter
-- @param lower number code of the lower-case letter
local function couple(upper, lower)
    MAP[two(upper)] = two(lower)
end

-- Cyrillic, first half: Ѐ..Џ -> ѐ..џ. This holds Ё (U+0401), and with it the
-- Ukrainian Є (U+0404), І (U+0406) and Ї (U+0407).
for code = 0x0400, 0x040F do couple(code, code + 0x50) end

-- Cyrillic, second half: А..Я -> а..я.
for code = 0x0410, 0x042F do couple(code, code + 0x20) end

-- Ґ -> ґ. The only Ukrainian letter outside the range above.
couple(0x0490, 0x0491)

-- Latin letters with diacritics: À..Þ -> à..þ. × (U+00D7) is the
-- multiplication sign rather than a letter, and adding 0x20 would turn it
-- into ÷.
for code = 0x00C0, 0x00DE do
    if code ~= 0x00D7 then couple(code, code + 0x20) end
end

-- The lower -> upper mapping: the same table read the other way. A second
-- set of loops over the same ranges is deliberately absent — it would be the
-- very copy all of this was reconciled to remove.
--
-- The inversion is unambiguous: different upper-case letters answer to
-- different lower-case ones, because both halves of Cyrillic and the Latin
-- range are shifted by a constant step, and the single exception (×) was
-- excluded before anything was written. There are no irreversible pairs in
-- the table — ß, İ, ı and ÿ never entered it (see the header).
local UPPER = {}
for upper, lower in pairs(MAP) do UPPER[lower] = upper end

-- The pattern for a two-byte letter. The set of lead bytes is derived from
-- the table itself rather than written out beside it: otherwise a range added
-- with a new lead byte would silently stop folding, with nothing to notice it
-- by.
--
-- The table arrives as an argument rather than being read from the closure:
-- the upper- and lower-case sets have different lead bytes (upper-case
-- Cyrillic uses 0xD0 and 0xD2, lower-case 0xD0, 0xD1 and 0xD2), and one
-- pattern for both tables would let р-я through in one direction and not in
-- the other.
--
-- The lead byte of a two-byte sequence is always above 0xBF while a
-- continuation byte always lies in 0x80..0xBF, so this pattern cannot start a
-- match in the middle of a three- or four-byte character: our lead bytes do
-- not occur there.
-- @param map table a table whose keys are two-byte letters
-- @return string
local function pattern(map)
    local seen, leads = {}, {}
    for letter in pairs(map) do
        local lead = letter:sub(1, 1)
        if not seen[lead] then
            seen[lead] = true
            leads[#leads + 1] = lead
        end
    end
    table.sort(leads)
    return "[" .. table.concat(leads) .. "][\128-\191]"
end

local LETTERS  = pattern(MAP)
local CAPITALS = pattern(UPPER)

-- Whether a string holds any byte outside ASCII. A name on an English client
-- is pure ASCII, and for it the whole job ends at string.lower: a pattern
-- search is cheaper than a gsub, which would allocate a buffer for a new
-- string.
local HIGH = "[\128-\255]"

-- === The fold cache ===
--
-- Folding sits on the search path: the player types a letter and the module
-- compares what was typed against every name at once — across ten characters
-- with full bags that is 1800 names per keystroke. Measured: a byte-wise
-- string.lower over 1800 names takes 0.04 ms, honest folding 0.29 ms on Latin
-- and 0.59 ms on Cyrillic. The whole previous search cost 0.15-0.38 ms, so
-- folding on every comparison would double the price of a keystroke — and on
-- the aura path it is called in combat.
--
-- The answer is the one the bags module already uses for the typed query:
-- fold once, compare as often as you like. A query is typed once, and an
-- item's name does not change between two keystrokes — nor do the names of
-- 1800 items. So folded strings are remembered here, in one place for the
-- whole addon: both the search and the aura filter ask the same map.
--
-- The map is bounded. There are thousands of distinct names in a live saved
-- file, but a typed query is a string too, and every keystroke yields a new
-- one: without a bound the map would grow all session. On reaching the bound
-- it is rebuilt from scratch rather than evicting one entry at a time:
-- tracking which entry is oldest would have to happen on every fold, that is,
-- on the hot path, for the sake of a rare case. The price of the reset is one
-- keystroke at the old cost.
--
-- The cache is not storage: it lives for the session, never reaches
-- SavedVariables and rewrites nothing. A folded string is for comparison,
-- and only that.
local CACHE = {}
local CACHED = 0
local CACHE_LIMIT = 4096

--- Fold a string's case for comparison.
--
-- Two passes, both cheap: string.lower deals with ASCII Latin (that is C,
-- byte by byte), after which the map folds the two-byte letters. The order is
-- deliberate: ASCII is not in the table, and one pass would handle either one
-- or the other.
--
-- A string already folded passes through unchanged: lower-case letters are
-- values in the table, not keys. Folding twice is the same as folding once.
--
-- The answer is remembered (see "The fold cache" above): the second time the
-- same string costs a map lookup rather than a scan. This is exactly the
-- "fold once, compare many times" the cost was measured for.
--
-- @param text any
-- @return string|nil the folded string; nil if this is not a string
function Casefold.Fold(text)
    if type(text) ~= "string" then return nil end

    local known = CACHE[text]
    if known ~= nil then return known end

    local folded = text:lower()
    if folded:find(HIGH) ~= nil then
        folded = folded:gsub(LETTERS, MAP)
    end

    if CACHED >= CACHE_LIMIT then
        CACHE = {}
        CACHED = 0
    end
    CACHE[text] = folded
    CACHED = CACHED + 1

    return folded
end

--- A comparison key: trim the edges and fold the case.
--
-- An empty string, and a string of nothing but spaces, give nil — that is,
-- "nothing to compare". The difference matters everywhere the key comes from
-- an edit box: an empty string as a query would mean "show everything whose
-- name contains the empty string", that is, everything at once, and telling
-- "nothing typed yet" from "typed something that matches everything" would
-- become impossible.
--
-- @param text any
-- @return string|nil
function Casefold.Key(text)
    if type(text) ~= "string" then return nil end

    local trimmed = text:match("^%s*(.-)%s*$")
    if trimmed == "" then return nil end

    return Casefold.Fold(trimmed)
end

--- Raise a string's case for display.
--
-- Two passes in the same order and for the same reason as in Fold:
-- string.upper deals with ASCII (that is C, byte by byte), after which the
-- map raises the two-byte letters. A string already in capitals passes
-- through unchanged: here the lower-case letters are the keys and the
-- capitals the values, so a second call finds nothing.
--
-- A non-string is returned as itself rather than as nil, and this is the one
-- place where raising behaves differently from folding. The difference is not
-- cosmetic: raising sits on the display path, where a label decides by
-- emptiness and by nil where things are placed. Substituting anything for nil
-- moves the layout. Fold answers the opposite way for an equally honest
-- reason: "nothing to compare" must differ from "compare against the empty
-- string".
--
-- There is deliberately no cache here. Folding is called on every keystroke
-- across all 1800 names at once; raising is called on a widget's heading when
-- the widget is shown — dozens of strings a session, and a map for them would
-- cost more than the work itself.
--
-- @param text any
-- @return any the raised string; anything that is not a string, as it came
function Casefold.Upper(text)
    if type(text) ~= "string" then return text end

    local raised = text:upper()
    if raised:find(HIGH) ~= nil then
        raised = raised:gsub(CAPITALS, UPPER)
    end

    return raised
end
