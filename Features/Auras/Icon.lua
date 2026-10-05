local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("auras")

-- One aura icon, and the pool of icons.
--
-- The icons are reused: a player carries now two auras, now forty, and
-- creating a frame for every aura that appears would mean creating frames in
-- combat — that is, at the very time creating them costs most. The engine does
-- not release frames at all, so "create it and drop it" means a leak for the
-- whole session here.
--
-- === The file's main rule ===
--
-- An icon that has returned to the pool carries nothing of the previous aura
-- on it. Not "almost nothing" and not "nothing important": a remnant of the
-- previous aura is a foreign picture under a foreign timer, and the player
-- reads it as the truth. So the record is cleared by walking the record itself
-- (Icon.Wipe) rather than by a list of fields: a list of fields forgets a new
-- field at exactly the moment its author forgets it, and a test built on the
-- list would merely confirm itself.
--
-- There are now two tables an icon carries through the pool: the record of the
-- aura and the marks of what was drawn (`frame.drawn`, see Icon.Changed). The
-- second appeared together with repainting by difference, and the rule extends
-- to it in full: it is wiped by the same walk of the keys (Icon.Forget), in
-- the same Icon.Release and on the same line. An icon that kept somebody
-- else's marks is more dangerous than one that kept somebody else's picture:
-- it will compare the new aura with the old one, decide that nothing changed
-- and not repaint at all.
--
-- Walking the record does not reach everything: the icon's size and its
-- border's colour live not in the record's fields but in the frame itself and
-- its textures. So both are named out loud — Icon.Release puts the colour out
-- directly, and the size is written afresh on every placement (Icon.Place)
-- before the icon is shown. A rule for a single aura (Rules.lua) changes
-- exactly those two things and nothing beyond them.
--
-- === About the client ===
--
-- Outside the game there is no CreateFrame, and that is not a failure but the
-- absence of a frame: the whole file is written so that a nil reaches the end
-- without an error and every call on an object is checked for existence. The
-- bags and nameplates modules do exactly the same, and for the same reason —
-- the tests have to pass without a client.

local Icon = {}
ns.Icon = Icon

-- The key of the border's texture set on our icon. With the module's prefix,
-- even though the frame is ours: one day somebody else's key will end up
-- beside it.
local BORDER = "umbraAuraBorder"

-- The border colour of an ordinary icon. A name from the skin's palette
-- rather than a triple of numbers: colours in this addon belong to the skin
-- and are taken from it through the contract.
local BORDER_COLOR = "line"
Icon.BORDER_COLOR = BORDER_COLOR

-- The font category for the timer and the stacks. The same one the counters
-- on the core's action buttons use: a digit on an icon is a digit on an icon,
-- and a category of its own would split two identical texts on screen across
-- two settings.
local FONT_CATEGORY = "hotkey"
Icon.FONT_CATEGORY = FONT_CATEGORY

--- The inset of a label from the icon's edge.
--
-- From the skin's scale of insets (the contract, skin.Metrics().edge) rather
-- than as a number. Two ones used to stand here — one for the timer, one for
-- the stacks — and exactly the same quantity stood as a third and a fourth in
-- the nameplates. Version 12 of the contract introduced the name in the scale;
-- the sign is the side one is pushed away from and the caller supplies it,
-- while the number is one for all four labels.
--
-- The two is the answer to "there is no skin at all" rather than a second
-- record of the quantity: the tests, which have no core beside them, take that
-- path.
-- @param skin table|nil
-- @return number
function Icon.Edge(skin)
    if type(skin) ~= "table" or type(skin.Metrics) ~= "function" then
        return 2
    end
    return tonumber(skin.Metrics().edge) or 2
end

-- The share of the icon a digit's height takes, and the floor in points. The
-- floor is needed because on the smallest icon the share gives three points,
-- that is, nothing.
local FONT_SHARE = 0.38
local FONT_FLOOR = 8

--- The font height on an icon of a given side.
--
-- A pure function and the only place where this decision is made. Lifted out
-- of Icon.Dress under a name because the nameplates engine computes the same
-- thing (the nameplates module's Plate.lua): a digit on a square spell icon is
-- one and the same thing, and it has to grow by one rule. There is no shared
-- door between the two addons — the contract does not expose the rule for the
-- number — so a copy stands there, and a test keeps it from diverging.
--
-- @param size number|nil the icon's side
-- @return number the font height in points
function Icon.FontHeight(size)
    local height = math.floor((tonumber(size) or 0) * FONT_SHARE + 0.5)
    if height < FONT_FLOOR then height = FONT_FLOOR end
    return height
end

--- Paint an icon's border.
--
-- **The module's only place that calls skin.Outline.** Two parties write the
-- border — the icon's birth and the rule for a single aura — and they go
-- through one door. Two writers of a colour diverge silently: one painted, the
-- other did not know and did not repaint, and the icon is left with somebody
-- else's colour until a reload.
--
-- The core's skin builds the border, not us: otherwise our idea of the line
-- colour and the rest of the addon's would diverge at the very first edit. A
-- repeated call reuses the textures already built and only repaints them —
-- that is how skin.Outline itself is made.
--
-- An unknown colour name the contract does not paint at all, and it says so in
-- its answer (docs/module-api.md): the border is then painted in the ordinary
-- colour rather than left invisible. The name comes from the saved variables,
-- where it outlives a change of version too.
--
-- @param frame table|nil the icon
-- @param skin table|nil the core's skin (the contract, Darken:GetSkin)
-- @param color string|nil a colour name from the palette; nil means the
--     ordinary border
-- @return boolean whether it was painted
function Icon.Border(frame, skin, color)
    if type(frame) ~= "table" then return false end
    return Icon.Outline(frame, BORDER, frame.texture, skin, color)
end

--- A one-pixel border around any picture.
--
-- **The module's only place that calls the core's skin for a border.** Both
-- writers go through it: our grid's icon (Icon.Border) and a foreign aura icon
-- on a unit frame (Units.lua). Two writers of one border diverge silently —
-- one painted, the other did not know — so there is one door.
--
-- The textures are stored in the `key` field of the frame they were given to,
-- and that frame **is not required to be the thing the border is built
-- around**. On unit frames that is decisive: the picture is somebody else's
-- and belongs to the core's darkening, while the border's textures are ours
-- and live on our frame. Anchoring to a foreign region is not protected by the
-- engine — what is protected is moving the protected frame itself.
--
-- An unknown colour name the contract does not paint at all, and it says so in
-- its answer (docs/module-api.md): the border is then painted in the ordinary
-- colour rather than left invisible. The name comes from the saved variables,
-- where it outlives a change of version too.
--
-- @param frame table|nil the frame that owns the border's textures
-- @param key string the name of the field for the texture set
-- @param target table|nil the picture the border is built around
-- @param skin table|nil the core's skin (the contract, Darken:GetSkin)
-- @param color string|nil a colour name from the palette; nil means the
--     ordinary border
-- @return boolean whether it was painted
function Icon.Outline(frame, key, target, skin, color)
    if type(frame) ~= "table" or type(skin) ~= "table" then return false end
    if type(skin.Outline) ~= "function" then return false end
    if type(key) ~= "string" or key == "" then return false end
    if type(target) ~= "table" then return false end

    local name = type(color) == "string" and color ~= "" and color or nil

    -- The name is checked before painting, and by the same door that
    -- paints: the contract returns a colour by name, and no answer means a
    -- name the palette does not have. Otherwise the border would be left
    -- unpainted entirely — and the name comes from the saved variables and
    -- outlives a change of the palette's version.
    if name ~= nil and type(skin.Color) == "function"
        and skin.Color(name) == nil then
        name = nil
    end

    return skin.Outline(frame, key, target, name or BORDER_COLOR)
        and true or false
end

--- Show or put out a border that has already been built.
--
-- The skin can build a border and repaint it but cannot take it away: its own
-- windows do not need that — a border there lives as long as the window does.
-- On a reused icon it is needed: the aura is gone, the icon is out, and a
-- border around an empty space reads as an icon that is not there.
--
-- The set is walked with `pairs` rather than by a list of sides: the border has
-- four sides today, and a list of sides here would be a second piece of
-- knowledge about a construction that belongs to the skin.
--
-- @param frame table|nil the frame that owns the border's textures
-- @param key string|nil the name of the field holding the set
-- @param show any whether to show it
-- @return boolean whether the set was found
function Icon.Lit(frame, key, show)
    if type(frame) ~= "table" or type(key) ~= "string" then return false end

    local set = frame[key]
    if type(set) ~= "table" then return false end

    for _, texture in pairs(set) do
        if type(texture) == "table" then
            local method = show and texture.Show or texture.Hide
            if type(method) == "function" then pcall(method, texture) end
        end
    end

    return true
end

--- Build one icon.
-- @param skin table|nil the core's skin (the contract, Darken:GetSkin)
-- @return table|nil
function Icon.Build(skin)
    if type(CreateFrame) ~= "function" then return nil end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()

    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(frame)
    -- The edges of a spell's native picture are the game's own border. They
    -- are trimmed off, or our border becomes the second one.
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.texture = texture

    -- The one-pixel border goes through the single writer of the border's
    -- colour (Icon.Border): the ordinary colour here and a rule's colour at
    -- display time have to travel by one door.
    Icon.Border(frame, skin, nil)

    -- The sweeping shade. The engine draws it itself, without one line of
    -- ours per frame; the timer label is ours and lives separately.
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, frame,
        "CooldownFrameTemplate")
    if ok and type(cooldown) == "table" then
        if type(cooldown.SetAllPoints) == "function" then
            cooldown:SetAllPoints(frame)
        end
        if type(cooldown.SetDrawEdge) == "function" then
            pcall(cooldown.SetDrawEdge, cooldown, false)
        end
        -- The engine must have no digits of its own: we write the timer, and
        -- two labels on one icon are two different truths in one place.
        if type(cooldown.SetHideCountdownNumbers) == "function" then
            pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
        end
        frame.cooldown = cooldown
    end

    local time = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    time:SetJustifyH("CENTER")
    frame.timeText = time

    local count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetJustifyH("RIGHT")
    frame.countText = count

    -- The record of the aura lives on the icon and outlives its returns to
    -- the pool: auras change during a fight, and a fresh table per icon would
    -- cost the player frames.
    frame.record = {}

    -- The marks of what was drawn are a second table just like it, and for
    -- the same reason. Why it is needed is in Icon.Changed's header; what
    -- clears it is in Icon.Forget.
    frame.drawn = {}

    -- The mouse handlers are set once, here, and read the record off the
    -- icon. Not a closure over the aura: a closure would outlive the return to
    -- the pool and show somebody else's description under a new picture. The
    -- setting switches the mouse itself on and off (Mouse.Update) — the
    -- handlers are always set.
    ns.Mouse.Watch(frame)

    return frame
end

--- An empty pool.
-- The builder is accepted from outside so that the pool's bookkeeping can be
-- tested without a client: where there is no CreateFrame an ordinary table
-- serves as an icon, and the whole "nothing from the previous aura" rule is
-- tested as it is.
-- @param build function|nil the icon builder; Icon.Build by default
-- @return table
function Icon.NewPool(build)
    return {
        free  = {},
        built = 0,
        build = type(build) == "function" and build or Icon.Build,
    }
end

--- Take an icon from the pool, or build a new one.
-- @param pool table
-- @param skin table|nil
-- @return table|nil
function Icon.Acquire(pool, skin)
    if type(pool) ~= "table" then return nil end

    local count = #pool.free
    if count > 0 then
        local frame = pool.free[count]
        pool.free[count] = nil
        return frame
    end

    local frame = pool.build(skin)
    if frame then pool.built = pool.built + 1 end
    return frame
end

--- Clear the record of the aura.
--
-- By walking it rather than by a list of fields. A list of fields is a promise
-- to remember every new field, and a forgotten field here means a foreign
-- timer under a foreign picture.
--
-- @param record table|nil
-- @return table|nil the same record
function Icon.Wipe(record)
    if type(record) ~= "table" then return record end
    for key in pairs(record) do record[key] = nil end
    return record
end

--============================================================================
-- The marks of what was drawn
--============================================================================
--
-- An icon now lives on screen longer than one aura: the grid is repainted by
-- difference rather than torn down and assembled afresh (Auras.lua's header,
-- the Repainting section). Which means somebody has to remember what is
-- already written on the icon — otherwise "rewrite only what changed" would
-- mean "rewrite everything", that is, precisely what we are moving away from.
--
-- A separate table, `frame.drawn`, remembers it rather than the record of the
-- aura. The reason is decisive: the record is wiped entirely on every display
-- (Icon.SetAura), and a mark placed in it would not outlive the first change —
-- that is, there would be nothing to compare against at exactly the moment
-- the comparison is needed.
--
-- The pool's rule does not weaken because of this; it holds the same way: the
-- marks are wiped by walking the keys (Icon.Forget) rather than by a list of
-- fields, and they are wiped where the record is wiped — in Icon.Release.

--- An icon's table of marks, created when needed.
--
-- Lazily, because in the tests an ordinary table serves as an icon: the pool's
-- builder is accepted from outside, and demanding fields of it would mean
-- testing our own builder rather than the module.
--
-- @param frame table|nil
-- @return table|nil
function Icon.Marks(frame)
    if type(frame) ~= "table" then return nil end

    local marks = frame.drawn
    if type(marks) ~= "table" then
        marks = {}
        frame.drawn = marks
    end

    return marks
end

--- Compare a set of values with the remembered one and remember the new one.
--
-- **Comparing and remembering are one action, and they cannot be split
-- apart.** Two functions, one of which compares and the other records, would
-- each know one and the same list of fields separately and would diverge at
-- the very first new field: a field forgotten in the comparison means an icon
-- that was not repainted because "nothing changed".
--
-- A set is stored as an array together with its length: a nil in the middle
-- must not be read as the end, and a set of three values must not match a set
-- of five whose first three are the same.
--
-- The set's table is reused rather than created afresh: there are dozens of
-- icons in the grid and several sets per icon, and a fresh table per
-- comparison would be rubbish in exactly the place the pool was created for.
--
-- @param marks table|nil the icon's marks (Icon.Marks)
-- @param key string the set's name
-- @param ... the set's values
-- @return boolean whether any value differed
function Icon.Changed(marks, key, ...)
    if type(marks) ~= "table" then return true end

    local count = select("#", ...)
    local set = marks[key]
    if type(set) ~= "table" then
        set = {}
        marks[key] = set
    end

    local same = (set.n == count)
    for i = 1, count do
        local value = (select(i, ...))
        if same and set[i] ~= value then same = false end
        set[i] = value
    end
    set.n = count

    return not same
end

--- Forget everything that was drawn.
--
-- By walking the keys rather than by a list of sets, and for the same reason
-- the record is wiped by a walk: a list is a promise to remember every new
-- set, and a forgotten set here means an icon that stayed invisible or was not
-- repainted.
--
-- The sets' tables themselves are left empty rather than thrown away: a
-- discarded set is a fresh table per icon taken from the pool, that is,
-- rubbish during a fight.
--
-- @param frame table|nil
-- @return table|nil the same marks
function Icon.Forget(frame)
    local marks = type(frame) == "table" and frame.drawn or nil
    if type(marks) ~= "table" then return nil end

    for _, set in pairs(marks) do
        if type(set) == "table" then Icon.Wipe(set) end
    end

    return marks
end

--- Return an icon to the pool.
--
-- The icon is obliged to leave here without a single trace of the previous
-- aura: unanchored, hidden, with no picture, no labels, no shade and an empty
-- record. The anchor is no detail: a SetPoint left behind holds a reference to
-- the holder, and the hidden icon would travel after it at the next layout.
--
-- @param pool table
-- @param frame table|nil
-- @param skin table|nil the core's skin; needed to put the rule's colour
--     out
function Icon.Release(pool, frame, skin)
    if type(pool) ~= "table" or type(frame) ~= "table" then return end

    if type(frame.ClearAllPoints) == "function" then frame:ClearAllPoints() end
    if type(frame.Hide) == "function" then frame:Hide() end

    if frame.texture and type(frame.texture.SetTexture) == "function" then
        frame.texture:SetTexture(nil)
    end
    if frame.timeText and type(frame.timeText.SetText) == "function" then
        frame.timeText:SetText("")
    end
    if frame.countText and type(frame.countText.SetText) == "function" then
        frame.countText:SetText("")
    end
    if frame.cooldown and type(frame.cooldown.Clear) == "function" then
        pcall(frame.cooldown.Clear, frame.cooldown)
    elseif frame.cooldown and type(frame.cooldown.SetCooldown) == "function" then
        pcall(frame.cooldown.SetCooldown, frame.cooldown, 0, 0)
    end

    -- The secure overlay's aim is as much an inheritance from the previous
    -- aura as the picture and the labels, and it is removed here rather than
    -- at the next display: an icon lying in the pool with somebody else's
    -- index on the button would cancel somebody else's aura. The engine does
    -- not let an attribute be written in combat, so the removal takes the same
    -- path the aim does — through the module's queue under this button's
    -- key.
    ns.Mouse.Forget(frame)

    -- The border colour from the previous aura's rule is as much an
    -- inheritance as the picture and the labels, and it is put out here
    -- directly rather than only by the fact that the display always writes a
    -- colour. Walking the record does not reach it: the colour lives in the
    -- border's textures rather than in the record's fields — so it is named
    -- out loud, as the picture, the labels and the overlay's aim are.
    Icon.Border(frame, skin, nil)

    Icon.Wipe(frame.record)

    -- The marks of what was drawn are as much an inheritance from the
    -- previous aura as the record, and they are wiped here and by the same
    -- walk of the keys. An icon that returned to the pool with its former
    -- marks would compare a new aura with somebody else's and not repaint at
    -- all.
    Icon.Forget(frame)

    pool.free[#pool.free + 1] = frame
end

--- Place an icon on the grid.
-- @param frame table|nil
-- @param holder table|nil the holder frame
-- @param point string the anchor corner
-- @param x number
-- @param y number
-- @param size number
function Icon.Place(frame, holder, point, x, y, size)
    if type(frame) ~= "table" then return end

    if type(frame.SetSize) == "function" then frame:SetSize(size, size) end
    if type(frame.ClearAllPoints) == "function" then frame:ClearAllPoints() end
    if holder ~= nil and type(frame.SetPoint) == "function" then
        frame:SetPoint(point, holder, point, x, y)
    end
end

--- Show one aura on an icon.
--
-- The record on the icon is rewritten in full: first the wipe, then the new
-- fields. Without the wipe a field the new aura does not have (the stacks, the
-- expiry) would be left over from the previous one.
--
-- @param frame table|nil
-- @param aura table the record of the aura
-- @param showTime boolean whether to write the timer
-- @param showStacks boolean whether to write the stacks
function Icon.SetAura(frame, aura, showTime, showStacks)
    if type(frame) ~= "table" or type(aura) ~= "table" then return end

    local record = Icon.Wipe(frame.record)
    if type(record) == "table" then
        record.order   = aura.order
        record.expires = aura.expires
        record.mine    = aura.mine
        record.name    = aura.name
        record.timed   = showTime and true or false
        -- The aura's kind and the spell's id are needed by the mouse: the
        -- game gives the tooltip by the kind and the slot's index, and only a
        -- buff can be cancelled off oneself.
        record.harmful = aura.harmful and true or false
        record.spellId = tonumber(aura.spellId)
    end

    if frame.texture and type(frame.texture.SetTexture) == "function" then
        frame.texture:SetTexture(aura.icon)
    end

    if frame.countText and type(frame.countText.SetText) == "function" then
        frame.countText:SetText(showStacks and ns.Layout.Stacks(aura.count) or "")
    end

    local duration = tonumber(aura.duration) or 0
    local expires  = tonumber(aura.expires) or 0
    if frame.cooldown then
        if duration > 0 and expires > 0
            and type(frame.cooldown.SetCooldown) == "function" then
            pcall(frame.cooldown.SetCooldown, frame.cooldown,
                expires - duration, duration)
        elseif type(frame.cooldown.Clear) == "function" then
            pcall(frame.cooldown.Clear, frame.cooldown)
        elseif type(frame.cooldown.SetCooldown) == "function" then
            pcall(frame.cooldown.SetCooldown, frame.cooldown, 0, 0)
        end
    end

    if type(frame.Show) == "function" then frame:Show() end
end

--- Write the timer on an icon.
-- The module's most frequent call: no tables, no settings, no strings.
-- @param frame table|nil
-- @param text string
function Icon.SetTime(frame, text)
    if type(frame) ~= "table" then return end
    if frame.timeText and type(frame.timeText.SetText) == "function" then
        frame.timeText:SetText(text or "")
    end
end

--- Lay the labels out according to the icon's size.
--
-- The font size is computed from the icon's size rather than set by a setting
-- of its own: two independent quantities give the player the chance to
-- assemble an icon whose timer cannot be read, and then to go looking for
-- where they did it.
--
-- @param frame table|nil
-- @param size number the icon's size
-- @param media table|nil the core's media (the contract, Darken:GetMedia)
-- @param edge number|nil the labels' inset from the edge, from the skin's
--   scale (the contract, skin.Metrics().edge); asked for once for the whole
--   grid
function Icon.Dress(frame, size, media, edge)
    if type(frame) ~= "table" then return end

    local cell = tonumber(size) or ns.Layout.BOUNDS.size.default

    -- The core sets the font (the contract, media.ApplyFont): a second font
    -- choice beside the first would diverge from it silently. The size is then
    -- adjusted to the icon — the core owns the face, not how much room it was
    -- given here.
    local height = Icon.FontHeight(cell)

    local texts = { frame.timeText, frame.countText }
    for i = 1, #texts do
        local text = texts[i]
        if type(text) == "table" then
            if media and type(media.ApplyFont) == "function" then
                pcall(media.ApplyFont, FONT_CATEGORY, text)
            end
            if type(text.GetFont) == "function"
                and type(text.SetFont) == "function" then
                local ok, path, _, flags = pcall(text.GetFont, text)
                if ok and path then pcall(text.SetFont, text, path, height, flags) end
            end
            if type(text.ClearAllPoints) == "function" then text:ClearAllPoints() end
        end
    end

    -- Both labels stand inside the icon rather than under it: a label that
    -- spills over the edge overlaps the next row at any small gap, and the
    -- player gets an unreadable mush in exactly the place they asked for a
    -- dense grid. The timer at the bottom centre, the stacks in the top right
    -- corner — they never meet.
    --
    -- Both are pushed in by one and the same quantity from the skin's scale,
    -- and that is one number rather than two that happen to match: two labels
    -- on one icon standing at different distances from the edge read as one
    -- that has slipped.
    local inset = tonumber(edge) or 2
    if frame.timeText and type(frame.timeText.SetPoint) == "function" then
        frame.timeText:SetPoint("BOTTOM", frame, "BOTTOM", 0, inset)
    end
    if frame.countText and type(frame.countText.SetPoint) == "function" then
        frame.countText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    end
end
