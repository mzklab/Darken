local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("nameplates")

-- Our own nameplate: the health bar, the name, the level and the target's
-- highlight.
--
-- This is a thin shell over the rules in Colors.lua, Geometry.lua and
-- Engine.lua. Everything of its own here is calls into the engine; everything
-- that is decided is decided there and tested outside the game.
--
-- === Whose frame it is, and why exactly this way ===
--
-- Our frame is a child of UIParent rather than a child of the game's
-- nameplate, and that is the file's main decision. A child of a protected
-- frame is protected itself, which means creating it, showing it and placing
-- it are forbidden by the engine in combat. Deferring those to the end of
-- combat (the contract, handle:Secure) is not an option here: nameplates
-- appear in combat precisely, and "we will show them after the fight" means a
-- fight with no nameplates at all. Our own frame under UIParent is never
-- protected, so there is not one deferred action in this file — and none must
-- appear.
--
-- The frame follows the game's nameplate by an anchor (a SetPoint to it)
-- rather than by polling: the game moves the nameplate about the screen
-- itself, and what is anchored to it travels along without one frame of work
-- from us. There is neither an OnUpdate nor a timer here.
--
-- === What we touch on the foreign frame ===
--
-- Exactly one thing: the opacity of the native chrome. Alpha is not a method
-- the engine protects, so it is set at once, in combat too. A Hide() would be
-- more honest to look at, but it is forbidden in combat, and a deferred Hide
-- is the most dangerous of all: the queue will run after the fight, when the
-- game has already handed this very frame to another creature, and somebody
-- else's nameplate would be hidden.
--
-- The remembered alpha value lies in the attachment's record rather than in a
-- field on the foreign frame. So a game nameplate that returned to the pool
-- carries not one field of ours on it — not a single one.

local Plate = {}
ns.Plate = Plate

-- The inset of a label from the edge of whatever it stands on.
--
-- From the skin's scale of insets (the contract, skin.Metrics().edge) rather
-- than as a number. Before contract version 12 this name did not exist in the
-- scale, and one and the same quantity stood here as three numbers: 2 for the
-- cast bar's label, -1 for the level and -1 for the stack counter on an aura
-- icon. The sign is the side one is pushed away from rather than a different
-- quantity, so the number is one for all three and the caller supplies the
-- minus.
--
-- Asked for at the same time as the skin itself — the same way the gap is
-- (gapOf in NamePlates.lua).
--
-- The two is the answer to "there is no skin at all" rather than a second
-- record of the quantity: the tests, which have no core beside them, take that
-- path.
--
-- Exposed under a name (Plate.Edge) because the placement in NamePlates.lua
-- asks for it too: a second helper just like it beside this one would be the
-- very copy all this work moves away from.
-- @param skin table|nil
-- @return number
function Plate.Edge(skin)
    if type(skin) ~= "table" or type(skin.Metrics) ~= "function" then
        return 2
    end
    return tonumber(skin.Metrics().edge) or 2
end

-- The fields the engine keeps a unit frame in inside a nameplate. Candidates:
-- different builds name the field differently, and whatever is absent is
-- skipped.
local PLATE_FIELDS = { "UnitFrame", "unitFrame" }

-- The native bar texture. Not "nothing": a status bar without a texture has
-- no fill at all, and a label saying "as in the game" would mean an empty
-- space. This is the file the game draws its own bars with.
local NATIVE_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
Plate.NATIVE_BAR = NATIVE_BAR

-- The font category for the name and the level. The same one unit names use
-- in the core: a creature's name is a unit's name, and a category of its own
-- would split two identical texts on screen across two settings.
local FONT_CATEGORY = "unitname"

--- Memory about an object that leaves no trace on it.
--
-- Where the texture set of the target's highlight is kept
-- (TARGET_OUTLINE below). Side memory rather than a field, even though the
-- frame is ours, because the rule is shared: writing a field into a game
-- object's table marks the object itself, the mark spreads to the frame and
-- further, and the player sees it in somebody else's file. Looking at a
-- foreign object and painting it is allowed; writing on it is not.
--
-- Asked for while the file is read rather than on every call: the memory has
-- to be one for the module's whole life, and asked for afresh each time it
-- would forget everything. The core may be absent — that is how the tests read
-- the module's pure parts — and then the memory is made on the spot: its
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

local TARGET_OUTLINE = memory()

--- The unit frame inside a game nameplate.
-- No field at all means the frame is the nameplate itself: some builds keep
-- the bars directly on it.
-- @param plate table|nil
-- @return table|nil
function Plate.UnitFrameOf(plate)
    if type(plate) ~= "table" then return nil end

    for i = 1, #PLATE_FIELDS do
        local frame = plate[PLATE_FIELDS[i]]
        if type(frame) == "table" then return frame end
    end

    return plate
end

--- An empty pool.
-- @return table
function Plate.NewPool()
    return { free = {}, built = 0 }
end

--- Build one nameplate of ours.
--
-- Outside the game there is no CreateFrame, and that is not a failure but the
-- absence of a frame: the whole file is written so that a nil reaches the end
-- without an error. The bags module's window does exactly the same, and for
-- the same reason — the tests have to pass without a client.
--
-- @param skin table|nil the core's skin (the contract, Darken:GetSkin)
-- @return table|nil
function Plate.Build(skin)
    if type(CreateFrame) ~= "function" then return nil end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture(NATIVE_BAR)
    frame.bar = bar

    -- The bar's backdrop: our colour, our border. Both are taken from the
    -- core's skin through the contract rather than declared here — otherwise
    -- our idea of the panel colour and the rest of the addon's would diverge
    -- at the very first edit.
    if type(skin) == "table" and type(skin.Backdrop) == "function" then
        skin.Backdrop(frame, "ink", "line")
    end

    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetJustifyH("LEFT")
    frame.nameText = name

    local level = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    level:SetJustifyH("RIGHT")
    frame.levelText = level

    -- The target's highlight: a one-pixel border around the bar, built by the
    -- same skin function all our borders are. It is built once per frame and
    -- after that only shown and hidden — rebuilding it on every change of
    -- target would create textures in combat.
    if type(skin) == "table" and type(skin.Outline) == "function" then
        skin.Outline(frame, TARGET_OUTLINE, bar, "lilac")
    end
    Plate.ShowTarget(frame, false)

    -- The attachment's record lives on the frame and outlives its returns to
    -- the pool: attaching happens in combat for every creature that appears,
    -- and a table there would cost the player frames.
    frame.record = {}

    return frame
end

--- Take a frame from the pool, or build a new one.
-- @param pool table
-- @param skin table|nil
-- @return table|nil
function Plate.Acquire(pool, skin)
    if type(pool) ~= "table" then return nil end

    local count = #pool.free
    if count > 0 then
        local frame = pool.free[count]
        pool.free[count] = nil
        return frame
    end

    local frame = Plate.Build(skin)
    if frame then pool.built = pool.built + 1 end
    return frame
end

-- The buffers for walking the children and the regions during a return to
-- the pool. Two rather than one: the regions are collected inside the walk of
-- the children, and a shared buffer would overwrite the list of children at
-- the very first child. Both live at file level and are reused — a return to
-- the pool happens for every creature that leaves, that is, in combat.
local kids = {}
local regions = {}

--- Spread the engine's multi-value answer into a reused array.
-- Without a table constructor: a return to the pool happens in combat, and a
-- table there would cost the player frames.
-- @param out table the array for the answer
-- @return number how many objects
local function gather(out, ...)
    local count = select("#", ...)
    for i = 1, count do out[i] = select(i, ...) end
    for i = count + 1, #out do out[i] = nil end
    return count
end

--- Clear an object's labels: every font string of its.
-- @param object table|nil
local function blank(object)
    if type(object) ~= "table" then return end
    if type(object.GetRegions) ~= "function" then return end

    local ok, count = pcall(gather, regions, object:GetRegions())
    if not ok then return end

    for i = 1, count do
        local region = regions[i]
        if type(region) == "table" and type(region.SetText) == "function" then
            pcall(region.SetText, region, "")
        end
    end
end

--- Return a frame to the pool.
--
-- The frame is obliged to leave here without a single trace of the previous
-- unit: unanchored from the foreign nameplate, hidden, with an empty bar and
-- empty labels. The anchor is no detail: a SetPoint left behind holds a
-- reference to a game nameplate that is about to fall to another creature, and
-- our hidden frame would travel after it.
--
-- === Why the clearing goes by a walk rather than by a list of fields ===
--
-- The same promise Engine.Wipe keeps for the attachment's record, and it is
-- kept the same way. A list of "hide the cast bar, hide the quest icon, hide
-- the aura icons" would diverge from the display silently: an element added
-- tomorrow would stay visible on a creature that never applied it. So the
-- display's rule reads, and is tested, like this:
--
--   **everything that depends on the unit is a separate child frame**,
--   and the return to the pool hides every child by a walk, without knowing
--   their names.
--
-- The cast bar, the quest icon and every aura icon are children of our frame.
-- The labels inside them are put out by the same walk, over the regions. On
-- the frame itself exactly three things depend on the unit, and all three are
-- put out directly: the health bar, the target's highlight border and the
-- scale. None of them can be a child frame, and that is the only lawful
-- exception to the rule above.
--
-- @param pool table
-- @param frame table|nil
function Plate.Release(pool, frame)
    if type(pool) ~= "table" or type(frame) ~= "table" then return end

    if type(frame.ClearAllPoints) == "function" then frame:ClearAllPoints() end
    if type(frame.Hide) == "function" then frame:Hide() end

    if type(frame.GetChildren) == "function" then
        local ok, count = pcall(gather, kids, frame:GetChildren())
        if ok then
            for i = 1, count do
                local child = kids[i]
                if type(child) == "table" then
                    if type(child.Hide) == "function" then
                        pcall(child.Hide, child)
                    end
                    if type(child.SetValue) == "function" then
                        pcall(child.SetValue, child, 0)
                    end
                    blank(child)
                end
                kids[i] = nil
            end
        end
    end

    -- The cast bar's animation has to stop rather than play out on a frame
    -- that has already fallen to another creature: the engine runs it itself,
    -- and a hidden frame does not stop it.
    Plate.StopCast(frame)

    blank(frame)
    Plate.ShowTarget(frame, false)

    -- The scale is the third thing on the frame itself that depends on the
    -- unit: a rule for a single creature sets it. It cannot be a child frame
    -- — the nameplate itself is what is scaled — so it is reset directly, on
    -- equal terms with the health bar and the target's highlight border. To
    -- one rather than to the former setting: a frame taken from the pool
    -- passes through Layout afresh, and the common scale reaches it from
    -- there. Without this line a creature with no rule would get the size of
    -- whoever occupied the frame before it.
    Plate.SetScale(frame, 1)

    ns.Engine.Wipe(frame.record)

    pool.free[#pool.free + 1] = frame
end

--- Show or hide the target's highlight.
-- @param frame table|nil
-- @param shown boolean
function Plate.ShowTarget(frame, shown)
    if type(frame) ~= "table" then return end

    local set = TARGET_OUTLINE[frame]
    if type(set) ~= "table" then return end

    for _, texture in pairs(set) do
        if type(texture) == "table" and type(texture.SetShown) == "function" then
            texture:SetShown(shown and true or false)
        elseif type(texture) == "table" then
            if shown then texture:Show() else texture:Hide() end
        end
    end
end

--- Set a nameplate's scale.
--
-- The only place in the whole module where our frame's scale changes, and that
-- is not decoration but the same one-owner rule the colour lives by: two
-- parties now write the scale — the common setting (through Layout) and a rule
-- for a single unit (through the display) — and two separate SetScale calls
-- would mean a nameplate whose size depends on whose event arrived later. A
-- pure function does the multiplication (ns.Rules.Apply); a finished number
-- arrives here.
--
-- Rubbish instead of a number means one rather than a Lua error: the value
-- comes from SavedVariables, and a zero or a negative would mean an invisible
-- nameplate the player will be able neither to see nor to fix.
--
-- @param frame table|nil
-- @param scale any
function Plate.SetScale(frame, scale)
    if type(frame) ~= "table" then return end
    if type(frame.SetScale) ~= "function" then return end

    local value = tonumber(scale)
    if not value or value ~= value or value <= 0 then value = 1 end

    frame:SetScale(value)
end

-- The measurements the parts' positions are computed from. One table per
-- file, rewritten in place: the placement happens for every creature that
-- appears, that is, in combat, and a table there would cost the player frames.
-- There is no tangle: Layout and LayoutExtras do not call each other and are
-- not called from inside the decision about positions.
local geom = {}

--- Fill the measurements afresh.
-- Every field is written every time, nils included: a value left over from
-- the previous call is a part placed by another nameplate's measurements.
-- @return table the same table
local function measure(plate, width, height, gap, edge, auraSize)
    geom.plate  = plate
    geom.width  = tonumber(width) or 0
    geom.height = tonumber(height) or 0
    geom.gap    = tonumber(gap) or 2
    if geom.gap < 0 then geom.gap = 0 end
    geom.edge   = tonumber(edge) or 2
    geom.size   = tonumber(auraSize) or 0
    geom.step   = geom.size + geom.gap
    return geom
end

--- What a part is anchored to.
-- @param frame table
-- @param rel string|nil
-- @return table|nil
local function anchorOf(frame, rel)
    if rel == "bar" then return frame.bar end
    if rel == "plate" then return geom.plate end
    return frame
end

--- The part itself.
-- The aura icons are the only part in the plural, and their index arrives
-- separately: the layout plan is one for every nameplate, while an icon's
-- index is its own on each.
-- @param frame table
-- @param part string
-- @param index number|nil
-- @return table|nil
local function partOf(frame, part, index)
    if part == "plate" then return frame end
    if part == "bar"   then return frame.bar end
    if part == "name"  then return frame.nameText end
    if part == "level" then return frame.levelText end
    if part == "cast"  then return frame.cast end
    if part == "quest" then return frame.quest end
    if part == "auras" then
        local list = frame.auras
        return type(list) == "table" and list[index or 1] or nil
    end
    return nil
end

--- Put one part of a nameplate in its place.
--
-- **The only place in the whole module where a nameplate part's anchor
-- changes.** The same one-owner rule the colour lives by (Colors.Bar decides,
-- Plate.SetColor writes) and the scale (Plate.SetScale writes): one pure
-- function decides the position (ns.Arrange.Spec), one line here writes it.
-- Two places moving the parts would give a nameplate whose look depends on
-- whose placement ran last — and they would diverge exactly as silently as the
-- colour and the scale diverged before each of them got a single owner.
--
-- Anchoring is not display: it puts a hidden part in its place too, and a part
-- switched on later ends up where it is expected without a second placement.
--
-- @param frame table|nil
-- @param part string the part's name
-- @param plan table|nil the layout plan (ns.Arrange.Compile)
-- @param index number|nil the aura icon's index
function Plate.Place(frame, part, plan, index)
    if type(frame) ~= "table" then return end

    local object = partOf(frame, part, index)
    if type(object) ~= "table" then return end
    if type(object.ClearAllPoints) ~= "function" then return end
    if type(object.SetPoint) ~= "function" then return end

    local rel, point, relPoint, x, y = ns.Arrange.Spec(plan, part, geom, index)
    if point == nil then return end

    local anchor = anchorOf(frame, rel)

    object:ClearAllPoints()
    -- There may be no game nameplate at all: outside the client there are no
    -- frames, and inside it the placement also happens before the attachment.
    -- The part stays unanchored — that is a state rather than an error.
    if type(anchor) ~= "table" then return end

    object:SetPoint(point, anchor, relPoint, x, y)
end

--- Lay the frame out by the settings and anchor it to the game's nameplate.
--
-- The placement itself is no longer written here: ns.Arrange decides where
-- each part stands and Plate.Place writes it. What stayed here is the
-- measurements — what the positions do not have and cannot have.
--
-- @param frame table|nil
-- @param plate table|nil the game's nameplate
-- @param width number
-- @param height number
-- @param scale number
-- @param gap number the gap from the skin's scale of insets
-- @param edge number|nil the labels' inset from the edge, from the same scale
-- @param plan table|nil the layout plan; nil means the defaults, that is, the
--   very look the nameplate had before the layout existed
function Plate.Layout(frame, plate, width, height, scale, gap, edge, plan)
    if type(frame) ~= "table" then return end

    local total, nameHeight, offset = ns.Geometry.Layout(width, height, gap)
    measure(plate, width, height, offset, edge, nil)

    if type(frame.SetSize) == "function" then frame:SetSize(width, total) end
    Plate.SetScale(frame, scale)

    Plate.Place(frame, "plate", plan)
    Plate.Place(frame, "bar", plan)
    Plate.Place(frame, "name", plan)
    Plate.Place(frame, "level", plan)

    local bar = frame.bar
    if bar and type(bar.SetSize) == "function" then
        bar:SetSize(width, height)
    end

    local name = frame.nameText
    if name and type(name.SetHeight) == "function" then
        name:SetHeight(nameHeight)
    end

    local level = frame.levelText
    if level and type(level.SetHeight) == "function" then
        level:SetHeight(nameHeight)
    end
end

--- Set the bar's texture.
-- @param frame table|nil
-- @param path string|nil nil means the game's native texture
function Plate.SetTexture(frame, path)
    local bar = type(frame) == "table" and frame.bar or nil
    if not bar or type(bar.SetStatusBarTexture) ~= "function" then return end

    pcall(bar.SetStatusBarTexture, bar, path or NATIVE_BAR)
end

--- Apply the core's font to the labels.
-- The font is not chosen here: the rule for choosing it, the list of fonts and
-- the memory of the original value belong to the core's fonts subsystem, and
-- the contract exposes the application alone
-- (Darken:GetMedia().ApplyFont). A second font choice beside the first would
-- mean labels that do not obey the common setting.
-- @param frame table|nil
-- @param media table|nil the core's media
function Plate.ApplyFont(frame, media)
    if type(frame) ~= "table" then return end
    if type(media) ~= "table" or type(media.ApplyFont) ~= "function" then
        return
    end

    media.ApplyFont(FONT_CATEGORY, frame.nameText)
    media.ApplyFont(FONT_CATEGORY, frame.levelText)
end

--- Repaint the bar and the name.
-- Not one table: the colour arrives as three numbers out of a pure rule.
-- @param frame table|nil
-- @param r number
-- @param g number
-- @param b number
function Plate.SetColor(frame, r, g, b)
    if type(frame) ~= "table" then return end

    local bar = frame.bar
    if bar and type(bar.SetStatusBarColor) == "function" then
        bar:SetStatusBarColor(r, g, b)
    end

    local name = frame.nameText
    if name and type(name.SetTextColor) == "function" then
        name:SetTextColor(r, g, b)
    end
end

--- Fill the health bar.
-- The module's hottest path: called for every change of health of every
-- creature on screen. There is not one table here, not one read of the
-- settings and not one string.
-- @param frame table|nil
-- @param current any
-- @param maximum any
function Plate.SetHealth(frame, current, maximum)
    local bar = type(frame) == "table" and frame.bar or nil
    if not bar or type(bar.SetValue) ~= "function" then return end

    bar:SetValue(ns.Geometry.Fill(current, maximum))
end

--- The name and level labels.
-- @param frame table|nil
-- @param name string|nil
-- @param level any
function Plate.SetLabels(frame, name, level)
    if type(frame) ~= "table" then return end

    if frame.nameText and type(frame.nameText.SetText) == "function" then
        frame.nameText:SetText(name or "")
    end

    if frame.levelText and type(frame.levelText.SetText) == "function" then
        -- A level the game does not know is returned as -1: showing a -1 on
        -- a nameplate is not allowed, while hiding the label is.
        local number = tonumber(level)
        if number and number > 0 then
            frame.levelText:SetText(tostring(number))
        else
            frame.levelText:SetText("")
        end
    end
end

--- Hide the nameplate's native chrome, or give it back.
--
-- Alpha rather than Hide: see the explanation in the file's header. The value
-- that was there before us arrives and leaves as an argument — we leave
-- nothing on the foreign frame.
-- @param plate table|nil the game's nameplate
-- @param alpha number|nil nil means "hide"; a number means restore it
-- @return number|nil the former alpha value, if we hid it
function Plate.Native(plate, alpha)
    local frame = Plate.UnitFrameOf(plate)
    if type(frame) ~= "table" then return nil end
    if type(frame.SetAlpha) ~= "function" then return nil end

    if alpha ~= nil then
        pcall(frame.SetAlpha, frame, alpha)
        return nil
    end

    local previous
    if type(frame.GetAlpha) == "function" then
        local ok, value = pcall(frame.GetAlpha, frame)
        if ok and type(value) == "number" then previous = value end
    end

    pcall(frame.SetAlpha, frame, 0)
    return previous or 1
end

-- === The second increment: the cast bar, the auras, the quest icon ===
--
-- Each of the three is a separate child frame, and that is not a taste in
-- layout but the very promise from Plate.Release's header: the return to the
-- pool hides the children by a walk, without knowing their names, and an
-- element added tomorrow is already put out today.
--
-- They are built not when the frame is assembled but at their first display: a
-- player whose auras and cast bar are switched off (and they are off for
-- everybody who has just installed it) pays for their frames not at all —
-- neither in memory nor in time.

-- Where the cast bar border's texture set is kept.
local CAST_OUTLINE = memory()

-- Where an aura icon border's texture set is kept.
local AURA_OUTLINE = memory()

-- The font category for a spell's name. The same one the unit's name uses:
-- both labels stand on one nameplate, and different categories would split
-- their look.
local CAST_FONT = "unitname"

-- The font category for an aura's stack count. The same one the counters on
-- the core's action buttons use: a digit on an icon is a digit on an icon.
local AURA_FONT = "hotkey"

-- The share of the icon the stack digit's height takes, and the floor in
-- points. The same two numbers the compact auras use (the auras module's
-- Icon.lua, Icon.FontHeight), and that is not a coincidence but a
-- reconciliation: a digit on a square spell icon is one and the same thing,
-- and in two places on screen it has to grow by one rule. The size used not to
-- be computed here at all — the digit kept the height the font category gave
-- it, and on a small icon it spilled over the edge while on a large one it was
-- lost.
--
-- A copy rather than a call: the nameplates engine and the compact auras are
-- two separate addons, they have no shared door (the contract does not expose
-- the rule for the number), and the module has no right to look into somebody
-- else's folder. A test that compares the two heights against each other keeps
-- the copy from diverging.
local AURA_FONT_SHARE = 0.38
local AURA_FONT_FLOOR = 8

--- The font height of the stack count on an icon of a given side.
-- A pure function: the rule is tested outside the client.
-- @param size number|nil the icon's side
-- @return number the font height in points
function Plate.AuraFontHeight(size)
    local height = math.floor((tonumber(size) or 0) * AURA_FONT_SHARE + 0.5)
    if height < AURA_FONT_FLOOR then height = AURA_FONT_FLOOR end
    return height
end

--- Create the cast bar, if it does not exist yet.
--
-- The fill is a texture rather than a StatusBar, and that is a decision for
-- the whole file: the engine runs the bar's motion as a scale animation (see
-- Cast.lua's header), and there is nothing to scale a status bar's fill with —
-- it belongs to the status bar.
--
-- @param frame table|nil
-- @param skin table|nil
-- @return table|nil
function Plate.Cast(frame, skin)
    if type(frame) ~= "table" then return nil end
    if frame.cast ~= nil then return frame.cast end
    if type(CreateFrame) ~= "function" then return nil end

    local cast = CreateFrame("Frame", nil, frame)
    cast:Hide()

    if type(skin) == "table" and type(skin.Backdrop) == "function" then
        skin.Backdrop(cast, "ink", "line")
    end

    local fill = cast:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", cast, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", cast, "BOTTOMLEFT", 0, 0)
    cast.fill = fill

    local castEdge = Plate.Edge(skin)
    local label = cast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cast, "LEFT", castEdge, 0)
    label:SetPoint("RIGHT", cast, "RIGHT", -castEdge, 0)
    label:SetJustifyH("LEFT")
    cast.label = label

    if type(skin) == "table" and type(skin.Outline) == "function" then
        skin.Outline(cast, CAST_OUTLINE, fill, "line")
    end

    -- The motion's animation. The engine runs it, and that is the only
    -- reason the cast bar has neither an OnUpdate nor a timer. We know of no
    -- client without animations, but the absence is checked rather than
    -- assumed: without it the bar stands at the fraction it had on the event,
    -- which looks worse but breaks nothing.
    local ok, group = pcall(fill.CreateAnimationGroup, fill)
    if ok and type(group) == "table" then
        local okAnim, anim = pcall(group.CreateAnimation, group, "Scale")
        if okAnim and type(anim) == "table" then
            pcall(anim.SetOrigin, anim, "LEFT", 0, 0)
            cast.run = group
            cast.anim = anim

            if type(group.SetScript) == "function" then
                pcall(group.SetScript, group, "OnFinished", function()
                    if type(cast.Hide) == "function" then cast:Hide() end
                end)
            end
        end
    end

    frame.cast = cast
    return cast
end

--- Stop and hide the cast bar.
-- @param frame table|nil
function Plate.StopCast(frame)
    local cast = type(frame) == "table" and frame.cast or nil
    if type(cast) ~= "table" then return end

    if type(cast.run) == "table" and type(cast.run.Stop) == "function" then
        pcall(cast.run.Stop, cast.run)
    end
    if type(cast.fill) == "table" and type(cast.fill.SetScale) == "function" then
        pcall(cast.fill.SetScale, cast.fill, 1)
    end
    if type(cast.Hide) == "function" then cast:Hide() end
end

--- Start the cast bar.
--
-- Every number has already been computed by a pure rule (Cast.Progress): here
-- there are only calls into the engine. No time, no division, no tables.
--
-- @param frame table|nil
-- @param from number the fraction to start from
-- @param to number the fraction to finish at
-- @param seconds number how long to travel
-- @param name string|nil the spell's name
-- @param r number|nil the fill's colour
-- @param g number|nil
-- @param b number|nil
function Plate.StartCast(frame, from, to, seconds, name, r, g, b)
    local cast = type(frame) == "table" and frame.cast or nil
    if type(cast) ~= "table" then return end

    local fill = cast.fill
    if type(fill) == "table" and r then
        if type(fill.SetColorTexture) == "function" then
            pcall(fill.SetColorTexture, fill, r, g, b, 1)
        elseif type(fill.SetVertexColor) == "function" then
            pcall(fill.SetVertexColor, fill, r, g, b)
        end
    end

    if type(cast.label) == "table" and type(cast.label.SetText) == "function" then
        cast.label:SetText(name or "")
    end

    local anim, group = cast.anim, cast.run
    if type(anim) == "table" and type(group) == "table" then
        if type(group.Stop) == "function" then pcall(group.Stop, group) end
        if type(fill) == "table" and type(fill.SetScale) == "function" then
            pcall(fill.SetScale, fill, 1)
        end

        -- The engine's method name has changed over time; whichever exists
        -- is taken. Both attempts are guarded: an unfamiliar method is absent
        -- rather than "a Lua error in combat".
        local setFrom = anim.SetScaleFrom or anim.SetFromScale
        local setTo   = anim.SetScaleTo   or anim.SetToScale
        if type(setFrom) == "function" then pcall(setFrom, anim, from, 1) end
        if type(setTo) == "function" then pcall(setTo, anim, to, 1) end
        if type(anim.SetDuration) == "function" then
            pcall(anim.SetDuration, anim, seconds)
        end
        if type(group.Play) == "function" then pcall(group.Play, group) end
    elseif type(fill) == "table" and type(fill.SetScale) == "function" then
        -- Without animations the bar stands at the fraction there is now and
        -- stays until the next event. We will not poll the time for the sake
        -- of the motion.
        pcall(fill.SetScale, fill, from)
    end

    if type(cast.Show) == "function" then cast:Show() end
end

--- Create the aura icon at position index, if it does not exist yet.
-- @param frame table|nil
-- @param index number
-- @param skin table|nil
-- @return table|nil
function Plate.Aura(frame, index, skin)
    if type(frame) ~= "table" then return nil end

    local list = frame.auras
    if type(list) ~= "table" then
        list = {}
        frame.auras = list
    end

    local icon = list[index]
    if icon ~= nil then return icon end
    if type(CreateFrame) ~= "function" then return nil end

    icon = CreateFrame("Frame", nil, frame)
    icon:Hide()

    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(icon)
    -- The edges of a spell's native picture are the game's own border. They
    -- are trimmed off, or our border becomes the second one.
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.texture = texture

    if type(skin) == "table" and type(skin.Outline) == "function" then
        skin.Outline(icon, AURA_OUTLINE, texture, "line")
    end

    -- The engine draws the sweeping shade itself, without one line of ours
    -- per frame. That is the answer to "how does the icon show the time left
    -- if we do not poll": the engine's own code draws what is left, and Lua
    -- wakes only on UNIT_AURA.
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, icon,
        "CooldownFrameTemplate")
    if ok and type(cooldown) == "table" then
        if type(cooldown.SetAllPoints) == "function" then
            cooldown:SetAllPoints(icon)
        end
        if type(cooldown.SetDrawEdge) == "function" then
            pcall(cooldown.SetDrawEdge, cooldown, false)
        end
        if type(cooldown.SetHideCountdownNumbers) == "function" then
            pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
        end
        icon.cooldown = cooldown
    end

    -- The stack count: the same corner, the same font object and the same
    -- inset the compact auras use (the auras module's Icon.lua). The inset is
    -- now genuinely the same rather than an equal number: both sides take it
    -- from the skin's scale (Metrics.edge). It used to stand in the bottom
    -- right corner and one point OUTSIDE the icon, in the ordinary text's
    -- face — that is, the digit on an aura icon was written in two places on
    -- screen in two different ways and in two different corners. The top right
    -- corner was chosen for the same reason it was there: the time label lives
    -- at the bottom centre, and two numbers in one corner would overlap.
    local iconEdge = Plate.Edge(skin)
    local count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -iconEdge, -iconEdge)
    count:SetJustifyH("RIGHT")
    icon.count = count

    list[index] = icon
    return icon
end

--- Show one aura on the icon at position index.
-- @param frame table|nil
-- @param index number
-- @param skin table|nil
-- @param texture any the path to the spell's picture
-- @param stacks any the number of stacks
-- @param duration any the duration
-- @param expires any the moment it ends
function Plate.SetAura(frame, index, skin, texture, stacks, duration, expires)
    local icon = Plate.Aura(frame, index, skin)
    if type(icon) ~= "table" then return end

    if type(icon.texture) == "table"
        and type(icon.texture.SetTexture) == "function" then
        pcall(icon.texture.SetTexture, icon.texture, texture)
    end

    if type(icon.count) == "table" and type(icon.count.SetText) == "function" then
        local number = tonumber(stacks)
        icon.count:SetText(number and number > 1 and tostring(number) or "")
    end

    local cooldown = icon.cooldown
    if type(cooldown) == "table" and type(cooldown.SetCooldown) == "function" then
        local length = tonumber(duration)
        local ends   = tonumber(expires)
        if length and ends and length > 0 and ends > 0 then
            pcall(cooldown.SetCooldown, cooldown, ends - length, length)
        elseif type(cooldown.Clear) == "function" then
            pcall(cooldown.Clear, cooldown)
        end
    end

    if type(icon.Show) == "function" then icon:Show() end
end

--- Hide the aura icons from position index onwards.
-- A walk over our own list of icons rather than over the screen: there are
-- only a handful of icons on one nameplate, and never more than the limit.
-- @param frame table|nil
-- @param index number
function Plate.HideAuras(frame, index)
    if type(frame) ~= "table" then return end

    local list = frame.auras
    if type(list) ~= "table" then return end

    for i = index, #list do
        local icon = list[i]
        if type(icon) == "table" and type(icon.Hide) == "function" then
            icon:Hide()
        end
    end
end

--- Fit the stack digit to its own icon's side.
--
-- The core owns the face (the font category), while how much room it was given
-- is decided by the icon: the roles are divided exactly the same way in the
-- compact auras (Icon.Dress). Called right after the font is assigned and only
-- from there: the assignment sets its own size, and a fit made before it would
-- be overwritten.
--
-- The side is taken off the icon itself (the placement writes it,
-- Plate.LayoutExtras) rather than arriving as an argument: the font is applied
-- also when there was no placement — on an edit of the font settings — and a
-- copy of the size kept beside it would diverge from the icon's real side
-- silently.
--
-- @param icon table|nil the aura icon
-- @return boolean whether the label was touched
function Plate.DressAura(icon)
    if type(icon) ~= "table" then return false end

    local count = icon.count
    if type(count) ~= "table" then return false end
    if type(count.GetFont) ~= "function"
        or type(count.SetFont) ~= "function" then
        return false
    end

    local side = tonumber(icon.side)
    if side == nil and type(icon.GetWidth) == "function" then
        local okWidth, width = pcall(icon.GetWidth, icon)
        if okWidth then side = tonumber(width) end
    end
    if side == nil then return false end

    local ok, path, _, flags = pcall(count.GetFont, count)
    if not ok or not path then return false end

    return (pcall(count.SetFont, count, path,
        Plate.AuraFontHeight(side), flags))
end

--- Create the quest icon, if it does not exist yet.
--
-- The picture is a fill in a colour from the skin's palette rather than a file
-- of the game's: the name of a foreign resource lives in the compatibility
-- layer, and we have no drop-shaped texture of our own. A small lilac mark
-- reads exactly as it should and will outlive any patch.
-- @param frame table|nil
-- @param skin table|nil
-- @return table|nil
function Plate.Quest(frame, skin)
    if type(frame) ~= "table" then return nil end
    if frame.quest ~= nil then return frame.quest end
    if type(CreateFrame) ~= "function" then return nil end

    local mark = CreateFrame("Frame", nil, frame)
    mark:Hide()

    local texture = mark:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(mark)
    if type(skin) == "table" and type(skin.Color) == "function" then
        local r, g, b = skin.Color("lilac")
        if r and type(texture.SetColorTexture) == "function" then
            texture:SetColorTexture(r, g, b, 1)
        end
    end
    mark.texture = texture

    frame.quest = mark
    return mark
end

--- Show or hide the quest icon.
-- @param frame table|nil
-- @param shown any
-- @param skin table|nil
function Plate.ShowQuest(frame, shown, skin)
    if type(frame) ~= "table" then return end

    if not shown then
        local mark = frame.quest
        if type(mark) == "table" and type(mark.Hide) == "function" then
            mark:Hide()
        end
        return
    end

    local mark = Plate.Quest(frame, skin)
    if type(mark) == "table" and type(mark.Show) == "function" then
        mark:Show()
    end
end

--- Lay out the cast bar, the aura icons and the quest icon.
--
-- Separate from Plate.Layout: the frame's own size does not depend on them —
-- it is anchored to the game's nameplate by its centre, while these three hang
-- outside it. Called in exactly the same places as Layout: on the attachment
-- and on an edit of the settings.
--
-- Where exactly they hang is decided by ns.Arrange and written by Plate.Place
-- — the same one-owner rule as in Layout.
--
-- @param frame table|nil
-- @param skin table|nil
-- @param width number the bar's width
-- @param height number the bar's height
-- @param gap number the gap
-- @param castHeight number|nil the cast bar's height; nil means the cast bar
--     is off
-- @param auraSize number|nil an icon's side; nil means the auras are off
-- @param auraLimit number|nil how many icons to create
-- @param plan table|nil the layout plan (ns.Arrange.Compile)
-- @param questOn any whether the quest icon is on in the settings
function Plate.LayoutExtras(frame, skin, width, height, gap, castHeight,
        auraSize, auraLimit, plan, questOn)
    if type(frame) ~= "table" then return end

    measure(nil, width, height, gap, nil, auraSize)

    if castHeight then
        local cast = Plate.Cast(frame, skin)
        if type(cast) == "table" and type(cast.SetSize) == "function" then
            Plate.Place(frame, "cast", plan)
            cast:SetSize(width, castHeight)
            if type(cast.fill) == "table"
                and type(cast.fill.SetWidth) == "function" then
                cast.fill:SetWidth(width)
            end
        end
    end

    if auraSize and auraLimit then
        for i = 1, auraLimit do
            local icon = Plate.Aura(frame, i, skin)
            if type(icon) == "table" and type(icon.SetSize) == "function" then
                Plate.Place(frame, "auras", plan, i)
                icon:SetSize(auraSize, auraSize)
                -- The icon's side is remembered on the icon itself: the
                -- stack digit's height is computed from it. The fit happens
                -- both here and right after the font is assigned
                -- (Plate.ApplyExtraFonts): the assignment sets the category's
                -- size and overwrites ours, and it may or may not happen —
                -- the media contract may be absent at that moment entirely,
                -- and the digit still has to match the icon.
                icon.side = auraSize
                Plate.DressAura(icon)
            end
        end
    end

    -- The quest icon is created here rather than at its first display, and
    -- for the same reason the cast bar is created here: an icon created by the
    -- display would be left unanchored until the first edit of the settings —
    -- the display happens after the placement — that is, on a creature that
    -- had just appeared it would hang in the middle of the nameplate. An icon
    -- that is switched off is still not created at all.
    local mark = questOn and Plate.Quest(frame, skin) or frame.quest
    if type(mark) == "table" and type(mark.SetSize) == "function" then
        local side = height
        if side < 6 then side = 6 end
        Plate.Place(frame, "quest", plan)
        mark:SetSize(side, side)
    end
end

--- Bring the frame back to the "ready to be shown" state.
--
-- The return to the pool hides every child by a walk, and the health bar is a
-- child too. So a frame taken from the pool has to bring it back itself:
-- otherwise a creature would get a nameplate with a name and no bar, and that
-- would look exactly like a broken bar.
-- @param frame table|nil
function Plate.Ready(frame)
    if type(frame) ~= "table" then return end

    local bar = frame.bar
    if type(bar) == "table" and type(bar.Show) == "function" then bar:Show() end
end

--- Apply the core's font to the cast bar's and the aura icons' labels.
-- Separate from Plate.ApplyFont for the same reason these elements are built
-- lazily: a cast bar that is switched off has no label at all.
--
-- Right after the font is assigned, the stack digit is fitted to its own
-- icon's side (Plate.DressAura): the face is the core's, the height comes from
-- the icon.
-- @param frame table|nil
-- @param media table|nil
function Plate.ApplyExtraFonts(frame, media)
    if type(frame) ~= "table" then return end
    if type(media) ~= "table" or type(media.ApplyFont) ~= "function" then
        return
    end

    local cast = frame.cast
    if type(cast) == "table" then media.ApplyFont(CAST_FONT, cast.label) end

    local list = frame.auras
    if type(list) == "table" then
        for i = 1, #list do
            local icon = list[i]
            if type(icon) == "table" then
                media.ApplyFont(AURA_FONT, icon.count)
                Plate.DressAura(icon)
            end
        end
    end
end

--- The name font's height in points.
-- The shortening needs it: how many characters fit into the width depends on
-- which font the player chose. Asked of the label itself rather than kept by
-- us: a stored copy would diverge from the font settings silently.
-- @param frame table|nil
-- @return number|nil
function Plate.NameHeight(frame)
    local name = type(frame) == "table" and frame.nameText or nil
    if type(name) ~= "table" or type(name.GetFont) ~= "function" then
        return nil
    end

    local ok, _, size = pcall(name.GetFont, name)
    if ok then return tonumber(size) end
    return nil
end
