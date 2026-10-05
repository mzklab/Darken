local ADDON, ns = ...

-- Parsing of a slash command's text. A separate file because this is pure
-- logic: the spec (section 8) does not allow parsing inside an event handler
-- — there is no way to test such code. The handler in Core/Init.lua only
-- dispatches.

--- Split a command's arguments into a subcommand and the remainder.
-- Leading and trailing spaces are dropped, and extra spaces between the
-- subcommand and the remainder are collapsed. A missing part is an empty
-- string rather than nil, so the caller does not have to check the type.
-- @param input string|nil the text after /darken
-- @return string the subcommand ("" when there is none)
-- @return string the remainder ("" when there is none)
function ns.ParseCommand(input)
    if type(input) ~= "string" then return "", "" end

    -- Trim the edges: "  scan  Player  " and "scan Player" are the same.
    local trimmed = string.match(input, "^%s*(.-)%s*$")
    if trimmed == "" then return "", "" end

    local cmd, rest = string.match(trimmed, "^(%S+)%s*(.-)$")
    return cmd or "", rest or ""
end

-- Slash commands of modules.
--
-- Why this lives in the core. The contract said nothing about commands, and
-- both modules written against it rolled their own: SLASH_NAME1 = "/word"
-- plus an entry in SlashCmdList. That works by itself but promises nothing.
-- Two modules claiming one word silently displace each other — the one whose
-- file was read second wins, and the player gets a different command from the
-- one they typed. The handler then calls the engine directly, bypassing the
-- registry's protection: a command that raises becomes a yellow Lua line
-- naming "Darken" rather than the module.
--
-- So the core issues the word: it alone sees everyone who already claimed
-- one, and it wraps the handler in the same protection as OnEnable and
-- ApplySettings.

-- Words claimed by the core itself (Core/Init.lua).
--
-- The former "umbra" and "um" were left over from a name the addon does not
-- have: it is called Darken. A player types the word in chat and looks for it
-- by the addon's name rather than by the repository's history; the author
-- asked about it directly — why are the commands still umbra?
local CORE_WORDS = {
    -- Names of the command itself.
    dark = true, darken = true, dk = true,
    -- And its own words: a part claiming "report" would take the client
    -- report away from the player.
    demo = true, probe = true, report = true, scan = true,
}

-- Who claimed which word: [word] = module name. It exists so that the second
-- claimant is refused and told the first one's name instead of silently
-- displacing it.
ns.CommandWords = {}

-- What to do for a word: [word] = handler. A part's word is run as the
-- second word of one command ("/dark auras"), so they have to be kept
-- somewhere: they no longer have a chat command of their own.
local COMMANDS = {}

-- A command word: Latin letters and digits, starting with a letter. The rule
-- is the module name's, and for the same reason: the word is typed by hand in
-- chat, where Cyrillic depends on the keyboard layout.
local WORD_PATTERN = "^%a[%w]*$"
local WORD_LIMIT   = 24

--- Check a command word before it goes to the engine.
-- A pure function: the claimed words arrive as one table and the client's
-- globals as another, so the rule is tested outside the client in every
-- outcome.
-- @param word any the presumed word, without the slash
-- @param taken table|nil [word] = name of the module that claimed it
-- @param globals table|nil the client's globals, for a foreign SlashCmdList
-- @return boolean
-- @return string|nil the reason for refusal
function ns.CheckCommandWord(word, taken, globals)
    if type(word) ~= "string" or word == "" or #word > WORD_LIMIT
        or not word:match(WORD_PATTERN) then
        return false, ns.Localize("a slash command needs a word made of Latin "
            .. "letters and digits and starting with a letter")
    end

    local lower = word:lower()

    if CORE_WORDS[lower] then
        return false, string.format(ns.Localize(
            "the command \"/%s\" belongs to Darken itself"), lower)
    end

    local owner = type(taken) == "table" and taken[lower] or nil
    if owner ~= nil then
        return false, string.format(ns.Localize(
            "the command \"/%s\" is already taken by module \"%s\""),
            lower, tostring(owner))
    end

    -- Another addon may have claimed this word before us. Displacing it
    -- silently is not allowed: the player types a familiar command and gets
    -- something else, and in their eyes the culprit is whatever was installed
    -- last.
    local list = type(globals) == "table" and globals.SlashCmdList or nil
    if type(list) == "table" and list[lower:upper()] ~= nil then
        return false, string.format(ns.Localize(
            "the command \"/%s\" is already registered by another addon"),
            lower)
    end

    return true
end

--- Claim a slash command on a module's behalf.
--
-- The handler is called through the registry, that is, under the same
-- protection as everything else foreign: a command that raises disables its
-- own module in one line and brings down neither the core nor its neighbours.
-- A disabled module does not run the command — it says so and stays quiet
-- afterwards.
--
-- The key in SlashCmdList is the word in upper case with the core's prefix:
-- without the prefix two addons sharing a word would collide inside a foreign
-- table, which our bookkeeping cannot reach.
-- @param name string the module's name
-- @param word string the word, without the slash
-- @param fn function the handler; called with the remainder of the text
-- @return boolean whether the command was accepted
-- @return string|nil the reason for refusal
function ns.RegisterModuleCommand(name, word, fn)
    if type(name) ~= "string" or name == "" then return false end
    if type(fn) ~= "function" then
        return false, ns.Localize("a slash command needs a function to call")
    end

    local ok, reason = ns.CheckCommandWord(word, ns.CommandWords, _G)
    if not ok then return false, reason end

    local lower = word:lower()

    -- The word gets no chat command of its own, and that is the author's
    -- decision: "more often dark auras, dark info, dark ilvl, dark pet and
    -- etc."
    --
    -- Each part used to claim a slash of its own — /darkauras, /darkinfo,
    -- /darkilvl — and the player had to remember six words instead of one.
    -- Now the word comes second: "/dark auras". It is looked up where the
    -- core's own words are looked up (report, scan, probe), and therefore
    -- cannot collide with them silently: the word check sees both sets.
    COMMANDS[lower] = function(input)
        -- A disabled part does not run its word, and that is said out
        -- loud. Silence is the worst answer here: the word was typed, nothing
        -- happened, and there is nothing to understand why from. A part is
        -- disabled in two ways — by its own failure and by the core's
        -- decision — and both look the same from outside.
        if ns.Registry:IsFailed(name) then
            local addon = ns.Addon
            if type(addon) == "table" and type(addon.Print) == "function" then
                addon:Print(string.format(ns.Localize(
                    "\"%s\" is switched off right now, so /dark %s does "
                        .. "nothing. Its section in the settings window says "
                        .. "why and offers to try again."), name, lower))
            end
            return
        end

        ns.Registry:Protect(name, "command." .. lower, fn, input)
    end

    ns.CommandWords[lower] = name
    return true
end

--- Run a part's word, if there is one.
--
-- Called by the core's command parsing (Core/Init.lua) after none of its own
-- words matched. A "no such word" answer is not an error here: in that case
-- the core opens the settings window, as it always has.
--
-- @param word any the command's second word
-- @param rest any the remainder of the text
-- @return boolean whether it was run
function ns.RunModuleCommand(word, rest)
    if type(word) ~= "string" or word == "" then return false end

    local run = COMMANDS[word:lower()]
    if run == nil then return false end

    run(rest or "")
    return true
end
