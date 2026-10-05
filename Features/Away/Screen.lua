-- The drawing layer: the away canvas across the whole screen.
--
-- Here there are only calls into the engine and into the core's contract. Not
-- one decision about whether to show the screen is made here — Rules.lua makes
-- those, and makes them outside the client, where they can be tested.

local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Missed would collide
-- silently.
local ns = core.Feature("away")

local Screen = {}
ns.Screen = Screen

-- A frame name of our own rather than somebody else's: the Darken prefix
-- says whose it is.
local FRAME_NAME = "DarkenAwayScreen"

-- The canvas's density when there are no settings yet (called before the
-- profile). The player sets it as a number: everybody's idea of "nearly
-- black" differs, and arguing about it with a slider is cheaper than with
-- words.
local DENSITY = 0.97

-- The size of the model's window. A square, because the character stands at
-- full height in it and turns about itself: a rectangle would clip it as it
-- turned.
local MODEL_SIZE = 320

-- How much larger than the window's font each line is.
--
-- Why this exists. The font for all six lines is asked of the core —
-- otherwise the screen would diverge from the windows at the very first change
-- of font — but it was asked for under ONE category, and the name's large
-- template was overwritten by the window's small font. The card came out set
-- all at one size, and the author said so plainly: the text sizes and the rest
-- could be bigger.
--
-- A multiplier rather than a size of our own as a number: the player changes
-- the window's font, and the card has to follow it, keeping the difference
-- between the name and a caption.
local SCALE = {
    name   = 2.2,
    who    = 1.2,
    where  = 1.2,
    timer  = 1.5,
    missed = 1.2,
    clock  = 1.2,
}

-- The model's movement. A number from the engine's list of animations: 69 is
-- the dance.
--
-- There is no choice here, and that is the author's decision: better to keep
-- the dance. A list of three movements was written and then removed — a
-- setting nobody will ever touch costs a row in the window and gives nothing.
--
-- "Looking around" does not exist as a separate number at all: it is a
-- variation of the same idle stance, and putting an invented number here would
-- mean a motionless model with not one word about why.
local DANCE = 69

--- The core's skin, asked for at the place where painting happens.
-- One remembered once would outlive a change of palette silently: the screen
-- would stay painted the old way beside windows painted the new way.
-- @return table|nil
local function skin()
    local addon = _G.Darken
    if type(addon) ~= "table" or type(addon.GetSkin) ~= "function" then
        return nil
    end
    return addon:GetSkin()
end

--- The core's fonts and textures, asked for in the same place and for the
--- same reason.
-- @return table|nil
local function media()
    local addon = _G.Darken
    if type(addon) ~= "table" or type(addon.GetMedia) ~= "function" then
        return nil
    end
    return addon:GetMedia()
end

--- A safe call of an object's method.
-- Outside the client half the methods are absent, and inside the client some
-- of them are not present on every flavour. A missing method here is not a
-- failure.
-- @param object table|nil
-- @param name string
-- @return any
local function call(object, name, ...)
    if type(object) ~= "table" then return nil end
    local method = object[name]
    if type(method) ~= "function" then return nil end

    -- SEVERAL values are returned, and that is not a reserve for the
    -- future. GetFont gives three — the path, the size and the outline — and
    -- a helper returning only the first silently dropped the size: the
    -- scaling of the lines was not applied at all, neither here nor in the
    -- client. Caught by our own test rather than in the game.
    local ok, a, b, c, d = pcall(method, object, ...)
    if not ok then return nil end
    return a, b, c, d
end

--- Create a line of text on the canvas.
-- @param frame table
-- @param template string the name of a font object of the game's
-- @return table|nil
local function line(frame, template)
    -- The game's font object is named at creation, and that is not
    -- decoration but a condition of working at all: a string without a font
    -- makes SetText raise ("Font not set"), and raises not immediately but
    -- the first time the text arrives before the font.
    local text = call(frame, "CreateFontString", nil, "OVERLAY", template)
    if type(text) ~= "table" then return nil end
    call(text, "SetJustifyH", "CENTER")
    return text
end

--- Create the canvas. A second call gives back the same one.
--
-- The canvas is not created before the player first goes away: a module that
-- is switched off has no right to leave anything on screen, not even an empty
-- frame.
--
-- The canvas stands OVER the interface rather than instead of it. Hiding
-- UIParent — which half the other addons do — is not allowed here: an absence
-- also ends when the player is hit, and in combat UIParent is protected by the
-- engine, so we would no longer be able to show it again. The player would be
-- left with an empty screen until the interface was reloaded.
--
-- @return table|nil the frame; nil when there is no engine
function Screen.Build()
    if Screen.frame then return Screen.frame end
    if type(_G.CreateFrame) ~= "function" then return nil end

    local frame = _G.CreateFrame("Frame", FRAME_NAME, _G.UIParent)
    if type(frame) ~= "table" then return nil end

    call(frame, "Hide")
    call(frame, "SetFrameStrata", "FULLSCREEN_DIALOG")
    call(frame, "SetAllPoints", _G.UIParent)

    -- The mouse is caught so that a stray click on the black does not land
    -- on a button underneath. Letting it through is not an option: the canvas
    -- covers the whole screen, and being transparent to the mouse it would
    -- mean an interface being clicked blind.
    call(frame, "EnableMouse", true)

    local ink = call(frame, "CreateTexture", nil, "BACKGROUND")
    if type(ink) == "table" then
        call(ink, "SetAllPoints", frame)
        Screen.ink = ink
        Screen.Density(DENSITY)
    end

    local model = _G.CreateFrame("PlayerModel", nil, frame)
    if type(model) == "table" then
        call(model, "SetSize", MODEL_SIZE, MODEL_SIZE)
        call(model, "SetPoint", "CENTER", frame, "CENTER", 0, 140)
    else
        -- A flavour without PlayerModel is not a failure: the card reads
        -- in full without a portrait, and there is no reason to assemble it
        -- differently.
        model = nil
    end

    local name   = line(frame, "GameFontNormalHuge")
    local who    = line(frame, "GameFontHighlight")
    local where  = line(frame, "GameFontHighlight")
    local timer  = line(frame, "GameFontNormalLarge")
    local missed = line(frame, "GameFontHighlight")
    local clock  = line(frame, "GameFontHighlight")

    -- The card is assembled top to bottom as a single chain: a caption that
    -- was not created on this client does not break it — the next one hangs
    -- off the last one that exists.
    local previous, gap = model, -24
    for _, text in ipairs({ name, who, where, timer, missed }) do
        call(text, "SetPoint", "TOP", previous or frame,
            previous and "BOTTOM" or "CENTER", 0, gap)
        previous, gap = text, -10
    end

    if clock then
        call(clock, "SetPoint", "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 20)
        call(clock, "SetJustifyH", "RIGHT")
    end

    Screen.frame = frame
    Screen.model = model
    Screen.animation = nil
    Screen.lines = { name = name, who = who, where = where,
        timer = timer, missed = missed, clock = clock }

    return frame
end

--- Set the canvas's density.
--
-- Separate from building it: the canvas is built once while the slider is
-- moved as often as one likes, and there is no reason to rebuild it for
-- that.
-- @param density any a fraction from zero to one
function Screen.Density(density)
    local ink = Screen.ink
    if type(ink) ~= "table" then return end

    local alpha = tonumber(density) or DENSITY
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end

    if type(ink.SetColorTexture) == "function" then
        call(ink, "SetColorTexture", 0, 0, 0, alpha)
    else
        -- Old flavours do not know SetColorTexture: there the same colour
        -- is set with a white fill and a vertex colour.
        call(ink, "SetTexture", 1, 1, 1)
        call(ink, "SetVertexColor", 0, 0, 0, alpha)
    end
end

--- Write on the canvas what it was handed.
--
-- There is not one decision here: what to show has already been decided, and
-- finished strings arrive. An empty string hides its own caption rather than
-- leaving an empty space: a card without a guild must not have a hole where
-- the guild would be.
--
-- @param card table|nil { name, who, where, timer, missed, clock }
function Screen.Paint(card)
    local lines = Screen.lines
    if type(lines) ~= "table" then return end

    card = type(card) == "table" and card or {}

    local face, files = skin(), media()

    for key, text in pairs(lines) do
        local value = card[key]
        call(text, "SetText", value or "")
        if type(value) == "string" and value ~= "" then
            call(text, "Show")
        else
            call(text, "Hide")
        end

        -- The font and the colour are asked of the core rather than written
        -- here: otherwise the screen would diverge from the windows at the
        -- very first change of font.
        if files and type(files.ApplyFont) == "function" then
            files.ApplyFont("windowtext", text)
        end

        -- The scale is then applied on top of the core's answer. Otherwise
        -- the window's font overwrites the name's large template, and the
        -- card comes out set all at one size — which is exactly what the
        -- author saw.
        --
        -- What is multiplied is the REMEMBERED size rather than the current
        -- one. Painting happens once a second, and a multiplier laid over its
        -- own previous answer would grow the name to the size of the screen
        -- in half a minute. For now that is covered by the core returning the
        -- size to its own before every painting — but a thing like this must
        -- not rest on somebody else's behaviour.
        local face_, size, flags = call(text, "GetFont")
        if face_ and tonumber(size) then
            if not text.umbraBase then text.umbraBase = size end
            call(text, "SetFont", face_,
                text.umbraBase * (SCALE[key] or 1), flags)
        end

        if face and type(face.Text) == "function" then
            face.Text(text, key == "name" and "text" or "muted")
        end
    end

    -- The model is deliberately absent here.
    --
    -- Painting used to call SetUnit on it — and by that it put the movement
    -- out: SetUnit reloads the model and returns it to the idle stance.
    -- Painting happens once a second (the timer), which means the dance was
    -- cancelled a frame after it was set, and the model stood still. The
    -- author said so plainly: no change visible.
    --
    -- The model lives separately and is touched only in Screen.Animate.
end

--- Set the model's movement.
--
-- Separate from painting, and that is not a convenience: SetUnit reloads the
-- model and returns it to the idle stance, while painting happens once a
-- second. Movement set from there would be cancelled a frame after it was
-- set.
--
-- The same movement is not set twice in a row: the dance would start over on
-- every round.
function Screen.Animate()
    local model = Screen.model
    if type(model) ~= "table" then return end

    if Screen.animation == DANCE then return end
    Screen.animation = DANCE

    call(model, "SetUnit", "player")
    call(model, "SetAnimation", DANCE)
end

--- Set what to do on a mouse click.
--
-- A click on the canvas removes it. It is needed because the canvas CATCHES
-- the mouse — otherwise a stray click on the black would land on a button
-- underneath — which means the game does not see the click and does not clear
-- the absence by it: without this the screen could only be removed from the
-- keyboard.
--
-- @param onWave function|nil
function Screen.OnWave(onWave)
    local frame = Screen.Build()
    if frame == nil then return end

    call(frame, "SetScript", "OnMouseDown", function()
        if type(onWave) == "function" then pcall(onWave) end
    end)
end

--- Show or hide the canvas.
-- @param shown any
function Screen.SetShown(shown)
    local frame = Screen.frame
    if not frame then return end
    if shown then call(frame, "Show") else call(frame, "Hide") end
end

--- Whether the canvas is visible right now.
-- @return boolean
function Screen.IsShown()
    local frame = Screen.frame
    if not frame then return false end
    return call(frame, "IsShown") and true or false
end
