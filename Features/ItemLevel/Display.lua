local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("itemlevel")

-- The drawing layer: a number over an item's icon.
--
-- The file does not decide which number to show and does not know where the
-- button came from. It can do exactly one thing: create a font string of our
-- own on somebody else's button, show it and hide it.
--
-- Somebody else's button is the key phrase. A bag slot's and an equipment
-- slot's icon belongs to the game, and in the bags also to the core that
-- styles them, or to the bags module that replaces them. So the module
-- touches nothing on a button but its own string, and the string lives in a
-- field carrying our prefix (the contract, the Frames section): an unprefixed
-- name on a foreign object would one day collide with somebody else's.
--
-- Outside the game (in the tests) there is no CreateFontString, and that is
-- not a failure: the string simply is not created, while the whole ledger
-- stays testable.

local Display = {}
ns.Display = Display

-- Where our string lives for somebody else's button: memory about an object
-- that leaves no trace on it.
--
-- Taken from the core (contract version 21), because the rule is shared:
-- writing a field into a game object's table marks the object itself, the
-- taint spreads to the frame and further, and the player sees it in somebody
-- else's file. Looking at a foreign object and painting it is allowed;
-- writing on it is not.
--
-- Asked for while the file is read rather than on every call: the memory has
-- to be one for the module's whole life, and asked for afresh each time it
-- would forget everything. The core may be absent — that is how the tests
-- read the module's pure parts — and then the memory is made on the spot: its
-- construction is simple, and it holds no second rule.
--
-- @return table
local function memory()
    local api = _G and _G.Darken
    if type(api) == "table" and type(api.GetSkin) == "function" then
        local ok, skin = pcall(api.GetSkin, api)
        if ok and type(skin) == "table" and type(skin.Memory) == "function" then
            local made, out = pcall(skin.Memory)
            if made and type(out) == "table" then return out end
        end
    end
    return setmetatable({}, { __mode = "k" })
end

local FIELD = memory()
Display.FIELD = FIELD

--- Call an object's method if it exists.
-- @return any the result, or nil
local function call(object, method, ...)
    if type(object) ~= "table" and type(object) ~= "userdata" then return nil end
    local fn = object[method]
    if type(fn) ~= "function" then return nil end

    local ok, a = pcall(fn, object, ...)
    if not ok then return nil end
    return a
end

--- A fresh ledger of the buttons we have touched.
--
-- Needed so that switching the module off removes the numbers completely.
-- Buttons are not released in this API and a string is not removed from them
-- — it is hidden; but every single one has to be hidden, and walking the
-- whole screen for that is not an option.
-- @return table
function Display.NewRegistry()
    return { list = {}, count = 0 }
end

--- Our string on a button; created when needed.
-- @param registry table the ledger of buttons
-- @param button table somebody else's button
-- @return table|nil
function Display.Text(registry, button)
    if type(button) ~= "table" then return nil end

    local text = FIELD[button]
    if text then return text end

    if type(button.CreateFontString) ~= "function" then return nil end

    local ok, created = pcall(button.CreateFontString, button, nil, "OVERLAY",
        "NumberFontNormal")
    if not ok or created == nil then return nil end

    FIELD[button] = created

    if type(registry) == "table" then
        registry.count = registry.count + 1
        registry.list[registry.count] = button
    end

    return created
end

--- Show a number on a button.
--
-- Every property is assigned every time rather than only when the string is
-- created: the settings change, and a string created before an edit would
-- otherwise stay in its former corner and at its former size until the
-- interface is reloaded.
--
-- @param registry table the ledger of buttons
-- @param button table
-- @param style table { text, r, g, b, point, x, y, size, media, category }
-- @return boolean whether it was drawn
function Display.Show(registry, button, style)
    if type(style) ~= "table" then return false end

    local text = Display.Text(registry, button)
    if not text then return false end

    if style.text == nil or style.text == "" then
        call(text, "Hide")
        return false
    end

    -- The font comes from the core: the face, the outline and the memory of
    -- the original value belong to its fonts subsystem (the contract,
    -- media.ApplyFont). The module has no font list of its own and must
    -- not.
    if style.media and type(style.media.ApplyFont) == "function" then
        pcall(style.media.ApplyFont, style.category, text)
    end

    -- The size is our setting, and only it. The face and the outline are
    -- re-read off the string itself after the core assigned the font: there
    -- is no other way to set the size alone, while substituting a face of our
    -- own would mean a second font-selection mechanism beside the core's.
    local size = tonumber(style.size)
    if size and type(text.GetFont) == "function" then
        local okFont, path, _, flags = pcall(text.GetFont, text)
        if okFont and type(path) == "string" and path ~= "" then
            call(text, "SetFont", path, size, flags)
        end
    end

    call(text, "ClearAllPoints")
    call(text, "SetPoint", style.point or "TOPLEFT", button,
        style.point or "TOPLEFT", style.x or 0, style.y or 0)

    call(text, "SetText", style.text)
    call(text, "SetTextColor", style.r or 1, style.g or 1, style.b or 1)
    call(text, "Show")

    return true
end

--- Hide the number on one button.
-- A string that was never created is not created in order to be hidden.
-- @param button table
-- @return boolean whether there was anything to hide
function Display.Clear(button)
    if type(button) ~= "table" then return false end

    local text = FIELD[button]
    if not text then return false end

    call(text, "SetText", "")
    call(text, "Hide")
    return true
end

--- Hide every number we have ever shown.
--
-- The core disabling the module and the player switching it off in the
-- settings both lead here: a number left on an icon after it was switched off
-- is precisely the mistake the ledger of buttons is kept for.
--
-- @param registry table
-- @return number how many strings were hidden
function Display.HideAll(registry)
    if type(registry) ~= "table" then return 0 end

    local hidden = 0
    for i = 1, registry.count do
        if Display.Clear(registry.list[i]) then hidden = hidden + 1 end
    end

    return hidden
end
