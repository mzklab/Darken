-- The drawing layer: the durability block on screen.
--
-- Here there are only calls into the engine and into the core's contract. Not
-- one decision about what to show is here — Rules.lua takes those, and takes
-- them outside the client, where they can be tested.

local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("durability")

local Block = {}
ns.Block = Block

-- A frame name of our own rather than somebody else's: the Darken prefix
-- says whose it is, and the game's own close-on-escape list finds it by that
-- prefix should it ever be needed.
local FRAME_NAME = "DarkenDurabilityBlock"

--- The core's styling, asked for at the point of painting.
-- Remembered once, it would outlive a change of palette silently: the block
-- would stay painted the old way beside windows painted the new one.
-- @return table|nil
local function skin()
    local core = _G.Darken
    if type(core) ~= "table" or type(core.GetSkin) ~= "function" then
        return nil
    end
    return core:GetSkin()
end

--- The core's textures and fonts, asked for in the same place and for the
--- same reason.
-- @return table|nil
local function media()
    local core = _G.Darken
    if type(core) ~= "table" or type(core.GetMedia) ~= "function" then
        return nil
    end
    return core:GetMedia()
end

--- Create the block's frame. A second call returns the same one.
--
-- The frame is not created before the player switched the readout on: a
-- switched-off module has no right to leave anything on screen, not even an
-- empty frame with no size.
-- @return table|nil the frame; nil when there is no engine
function Block.Build()
    if Block.frame then return Block.frame end
    if type(_G.CreateFrame) ~= "function" then return nil end

    local frame = _G.CreateFrame("Frame", FRAME_NAME, _G.UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    -- The game's font object is named at creation, and that is not
    -- decoration but a condition of working. A font string with no font
    -- assigned yet raises on SetText — "Font not set" — and raises not at
    -- once but the first time text arrives before a font. That is what
    -- happened here: the font was set together with the colour, and the block
    -- does not always get a colour, so in the quiet state the label ended up
    -- without one.
    --
    -- A named object gives a font straight away and does not interfere with
    -- the addon's settings: those replace the font on the object itself, and
    -- the label follows them as before.
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", frame, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")

    Block.frame, Block.label = frame, label
    return frame
end

--- Paint the block and write a line in it.
-- @param text string|nil
-- @param tint string|nil a palette colour's name
-- @return boolean whether it was painted
function Block.Paint(text, tint)
    local frame, label = Block.frame, Block.label
    if not frame or not label then return false end

    local face = skin()
    if face then
        local metrics = face.Metrics()
        -- The size is asked of the scale rather than written as a number:
        -- an edit to the scale must move the block along with everything
        -- else.
        frame:SetSize(metrics.row * 5, metrics.row)
        face.Backdrop(frame, "panel", "line")
        if tint then face.Text(label, tint) end
    end

    local files = media()
    if files then
        -- The label was created after the core had walked its own: the
        -- fonts pass did not catch it, so it has to be asked for here.
        files.ApplyFont("windowtext", label)
    end

    label:SetText(text or "")
    return face ~= nil
end

--- Show or hide the block.
-- @param shown boolean
function Block.SetShown(shown)
    local frame = Block.frame
    if not frame then return end
    if shown then frame:Show() else frame:Hide() end
end
