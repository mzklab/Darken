local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("auras")

-- Auras on unit frames: the auras of the target, the focus and the group.
--
-- === How this place differs from the rest of the module ===
--
-- Everything the module has done so far, it did on its own frames. The
-- player's auras are not protected by the engine, the grid's icons are our own
-- children of UIParent, and the only foreign object was the game's own buff
-- frame, which the module moves away reversibly. Here it is not so: the
-- target's aura icons are part of foreign frames, they are protected
-- (protectedness is inherited downwards from the unit frame), the game
-- rearranges them on its own schedule, and the core already reaches those same
-- frames.
--
-- === Replace or dress: dressing was chosen, and here is why ===
--
-- The module would be able to replace these icons with a grid of its own: the
-- grid, the pool, the filter, the rules and the mouse are already written. But
-- replacing them would mean taking away from the game something it rearranges
-- constantly and in the middle of a fight, on frames it protects — and then
-- answering for the aura layout on every member of the group at every change
-- of its composition. The price of a mistake there is not "it looks wrong" but
-- "the target's auras cannot be seen", and that shows up not here but in
-- combat.
--
-- Dressing leaves the game its layout in full. We do not move, re-parent or
-- resize a single icon of its — that is, we perform not one operation the
-- engine protects — and we add exactly two things:
--
--   1. **the filter**: an aura the player hid on themselves they will not see
--      on the target either. That is the main point: a filter that means
--      different things in two places is worse than none;
--   2. **the border**: the same one pixel of the same palette colour our own
--      icons have, and for an aura under a rule, that rule's colour.
--
-- === Who owns what ===
--
-- These icons have owners, and they have to be named explicitly, or we become
-- the second owner:
--
--   * the core's Modules/UnitFrames.lua owns a unit frame's bars, the name's
--     colour and the scale. It does not touch the auras at all — not one
--     line;
--   * the core's Modules/Fonts.lua owns the fonts of the game's frames. So
--     **this file writes not one font**: the stack digit on the target's icon
--     belongs to the core, and a second writer of the font would diverge from
--     it silently;
--   * the core's Modules/Darkness.lua owns the colour of the unit frames'
--     chrome textures — it walks their descendants and remembers each
--     texture's native colour in a field of its own. So **this file paints not
--     one foreign texture**: a texture we had repainted would travel to the
--     darkening with a false "native" colour, and returning the slider would
--     return the wrong thing.
--
-- Hence the border's construction: its textures are created **on our own
-- frame** and are merely anchored to the foreign icon. The darkening does not
-- walk our frame (it is in none of its groups), we do not touch foreign
-- textures, and no shared objects are left between the two subsystems at all.
--
-- We own exactly three things, and all three are reversible:
--
--   * an icon's opacity (remembered in the ALPHA side memory below);
--   * whether an icon takes the mouse (the MOUSE side memory);
--   * the set of border textures on our frame.
--
-- === About combat ===
--
-- There is not one deferred action here, and that is not forgetfulness. The
-- engine protects position, size, visibility, parent, scale and attributes
-- (docs/module-api.md §9). Opacity and taking the mouse are not on that list,
-- and we build the border on our own unprotected frame. So an aura has to be
-- hidden **by opacity rather than by Hide** — and that is not a way around the
-- prohibition but the only way not to freeze the filter for the whole length
-- of a fight: a deferred Hide would mean a hidden aura hanging on the target
-- until the fight ended, that is, at exactly the time the player is looking at
-- the target.
--
-- Opacity goes in a pair with taking the mouse: an invisible icon that catches
-- the mouse would show a tooltip about something that is not on screen.
--
-- === Names ===
--
-- There is not one list of foreign names of our own here. Both the unit frames
-- and the aura icons themselves come from the core (`Darken:GetFrameNames`,
-- the unitframe, raidframe-member and unitframe-auras groups): the only place
-- in the addon allowed to know foreign names is the compatibility layer.
--
-- The walk by construction nevertheless stayed, and stayed deliberately — as
-- the second path rather than the first. An aura icon is recognised by how it
-- is built: a descendant of a unit frame that has a child of the Cooldown type
-- and at least one texture. That path finds icons that cannot be found by name
-- at all: on the compact party and raid frames the game creates them on the
-- fly, and nobody gives them global names.
--
-- The order between the two paths is stated: names first, construction
-- second, and only those unit frames from which not one name arrived are
-- walked by construction. A client on which not one of the named names exists
-- behaves exactly as the module behaved before the group was supported — that
-- is, entirely by the walk by construction.

local Units = {}
ns.Units = Units

--- Memory about an object that leaves no trace on it.
--
-- Where a foreign icon's opacity from before our interference is kept (ALPHA
-- below), and where its mouse setting is kept (MOUSE). The meaning is the same
-- as that of the core darkening's native-colour memory — always compute from
-- what was remembered rather than from what is current. Without it a double
-- "hide" would remember our own opacity as the native one, and the return
-- would stop returning anything.
--
-- Taken from the core (contract version 21), because the rule is shared:
-- writing a field into a game object's table marks the object itself, the mark
-- spreads to the frame and further, and the player sees it in somebody else's
-- file. Looking at a foreign object and painting it is allowed; writing on it
-- is not.
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

local ALPHA = memory()

-- Whether the icon took the mouse before our interference. The meaning is
-- exactly the same.
local MOUSE = memory()

-- The prefix of the key for the border's texture set on our frame. Each icon
-- has a key of its own for the whole session: a set that fell to another icon
-- would bring it somebody else's colour.
--
-- As a string rather than side memory, and that is not an oversight: the frame
-- here is our own, and an extra field does its own frame no harm. Side memory
-- is needed where the object is somebody else's (ALPHA and MOUSE above, which
-- sit on the game's icons).
local EDGE = "umbraUnitEdge"

-- How far to climb from an icon found by name in search of its unit frame. As
-- far as the walk searches downwards, plus the icon itself: an icon lying
-- deeper than the walk can search does not belong to us anyway.
local OWNER_DEPTH = 4

-- How deep to search for icons under a unit frame. Three is the frame, its
-- children and their children: in different builds the aura icons sit now
-- directly on the unit frame, now on its contents. A ceiling rather than a
-- guess: a walk without a limit on a foreign frame is a walk of the whole
-- interface.
local MAX_DEPTH = 3

-- How many icons the module agrees to keep. The ceiling insures against a
-- client under whose unit frame there is more than we expect: the cost of a
-- pass is linear in the number of icons, and its limit has to be named.
local MAX_BUTTONS = 160

-- The kinds of aura, in the order they are asked for. The order settles the
-- dispute when a buff and a debuff under one index have the same picture: the
-- buff outranks, and that is a decision rather than an accident of the order
-- in a table.
local KINDS = { "HELPFUL", "HARMFUL" }

--- An object's type, asked of the object itself.
-- Outside the game the method does not exist, and that is not a failure: the
-- type is then unknown, and the decisions that need it answer no.
-- @param object table|nil
-- @return string|nil
local function kindOf(object)
    if type(object) ~= "table" then return nil end
    if type(object.GetObjectType) ~= "function" then return nil end
    local ok, value = pcall(object.GetObjectType, object)
    if not ok or type(value) ~= "string" then return nil end
    return value
end

--- Collect the answer of a method without arguments into an array.
-- @param method function
-- @param object table
-- @return table
local function gather(method, object)
    return { method(object) }
end

--- An object's children as an array. A foreign object is entitled to be able
--- to do nothing.
-- @param object table
-- @return table
local function childrenOf(object)
    if type(object.GetChildren) ~= "function" then return {} end
    local ok, list = pcall(gather, object.GetChildren, object)
    if not ok then return {} end
    return list
end

--- An object's regions as an array.
-- @param object table
-- @return table
local function regionsOf(object)
    if type(object.GetRegions) ~= "function" then return {} end
    local ok, list = pcall(gather, object.GetRegions, object)
    if not ok then return {} end
    return list
end

--- Whether this is an aura icon.
--
-- The decision is made by construction rather than by name: an aura icon has a
-- child of the Cooldown type (which the game draws the sweeping shade with)
-- and at least one texture (the spell's picture itself). Neither a portrait,
-- nor a cast bar, nor a unit frame's button is built that way.
--
-- This is a guess in exactly the same sense in which any name in the
-- compatibility layer is a guess: an object that did not match it simply does
-- not fall to us, and the module silently does nothing with it.
--
-- @param object table|nil
-- @return boolean
function Units.IsAuraButton(object)
    if type(object) ~= "table" then return false end

    local hasTexture = false
    local regions = regionsOf(object)
    for i = 1, #regions do
        if kindOf(regions[i]) == "Texture" then hasTexture = true break end
    end
    if not hasTexture then return false end

    local children = childrenOf(object)
    for i = 1, #children do
        if kindOf(children[i]) == "Cooldown" then return true end
    end

    return false
end

--- Find the aura icons under one frame.
--
-- A walk inwards down to MAX_DEPTH. An icon that was found is not walked
-- inside: under it lies its own Cooldown rather than a second icon.
--
-- @param root table|nil a game frame
-- @param out table the array for the answer
-- @param depth number|nil the current depth; not passed in from outside
-- @return table the same array
function Units.Collect(root, out, depth)
    if type(root) ~= "table" then return out end
    if #out >= MAX_BUTTONS then return out end

    depth = tonumber(depth) or 0
    if depth > MAX_DEPTH then return out end

    if depth > 0 and Units.IsAuraButton(root) then
        out[#out + 1] = root
        return out
    end

    if depth >= MAX_DEPTH then return out end

    local children = childrenOf(root)
    for i = 1, #children do
        Units.Collect(children[i], out, depth + 1)
    end

    return out
end

--- Which unit a frame belongs to.
--
-- Asked of the frame itself: first the field the game creates it with, then
-- the secure template's attribute. The engine does not protect reading an
-- attribute — what is protected is writing one.
--
-- @param frame table|nil
-- @return string|nil
function Units.UnitOf(frame)
    if type(frame) ~= "table" then return nil end

    if type(frame.unit) == "string" and frame.unit ~= "" then
        return frame.unit
    end

    if type(frame.GetAttribute) == "function" then
        local ok, value = pcall(frame.GetAttribute, frame, "unit")
        if ok and type(value) == "string" and value ~= "" then return value end
    end

    return nil
end

--- An empty ledger.
--
-- `keys` deliberately outlives a scan: the key of the border's texture set is
-- fixed to an icon for the whole session. Handed to another icon, it would
-- bring it the previous one's colour — the very defect the pool of icons is
-- written against.
--
-- @return table
function Units.NewState()
    return {
        buttons = {},   -- array of { frame, unit }
        units   = {},   -- unit -> true: the events are filtered by these
        keys    = {},   -- icon -> the key of its texture set
        painted = {},   -- key -> the colour name the border is painted in now
        anchored = {},  -- key -> the texture the border stands around
        held    = {},   -- icon -> true: this icon carries our state
        next    = 0,
    }
end

--- Whose icon this is: climb from it to a unit frame we know.
--
-- Asked of the objects themselves rather than of a name. An icon's name would
-- say whose it is — a target buff's name carries the word for the target — but
-- parsing a foreign name would mean creating a second piece of knowledge about
-- a foreign construction right here: the name came from the core and belongs
-- to the core, while the unit is still asked of the frame.
--
-- @param button table an icon found by name
-- @param frames table the array of unit frames we know
-- @return table|nil the unit frame the icon belongs to
local function ownerOf(button, frames)
    local cursor = button

    for _ = 1, OWNER_DEPTH do
        if type(cursor) ~= "table" then return nil end

        for i = 1, #frames do
            if frames[i] == cursor then return cursor end
        end

        if type(cursor.GetParent) ~= "function" then return nil end
        local ok, parent = pcall(cursor.GetParent, cursor)
        if not ok then return nil end
        cursor = parent
    end

    return nil
end

--- Find the aura icons on every unit frame afresh.
--
-- Afresh, because frames appear later: there was no focus and the player set
-- one; a fifth member joined the group. The scan is cheap and happens on a
-- change of target, of focus and of composition rather than on a change of
-- auras.
--
-- Two paths, and the order between them is stated. First the icons that came
-- from the core by name: a name an object corresponds to on this client is the
-- cheapest and the most honest way to recognise a foreign icon. Then the walk
-- by construction, and only over those unit frames from which not one name
-- arrived: the icons on the compact party frames are created by the game on
-- the fly and are given no names at all, while a client without these names
-- entirely has to work the way it worked before the group was supported.
--
-- An icon that disappeared from the scan does not carry our state away with
-- it: first every former one is released, then the current ones are
-- collected.
--
-- @param state table
-- @param frames table array of game frames
-- @param named table|nil array of icons the core found by name
-- @return number how many icons were found
function Units.Scan(state, frames, named)
    if type(state) ~= "table" then return 0 end

    for i = #state.buttons, 1, -1 do state.buttons[i] = nil end
    for unit in pairs(state.units) do state.units[unit] = nil end

    if type(frames) ~= "table" then return 0 end

    -- The unit frames whose icons already arrived by name: walking them by
    -- construction would mean taking one and the same icon onto the ledger
    -- twice.
    local covered = {}

    if type(named) == "table" then
        local seen = {}
        for i = 1, #named do
            local button = named[i]
            if type(button) == "table" and not seen[button]
                and #state.buttons < MAX_BUTTONS then
                local owner = ownerOf(button, frames)
                local unit = owner and Units.UnitOf(owner) or nil
                if unit ~= nil then
                    seen[button] = true
                    covered[owner] = true
                    state.units[unit] = true
                    state.buttons[#state.buttons + 1] = {
                        frame = button,
                        unit  = unit,
                    }
                end
            end
        end
    end

    local found = {}
    for i = 1, #frames do
        local frame = frames[i]
        local unit = not covered[frame] and Units.UnitOf(frame) or nil
        if unit ~= nil then
            for j = #found, 1, -1 do found[j] = nil end
            Units.Collect(frame, found, 0)

            if #found > 0 then
                state.units[unit] = true
                for j = 1, #found do
                    if #state.buttons >= MAX_BUTTONS then break end
                    state.buttons[#state.buttons + 1] = {
                        frame = found[j],
                        unit  = unit,
                    }
                end
            end
        end
    end

    return #state.buttons
end

--- The key of the border's texture set for this icon.
-- @param state table
-- @param button table
-- @return string
local function keyFor(state, button)
    local key = state.keys[button]
    if key == nil then
        state.next = state.next + 1
        key = EDGE .. state.next
        state.keys[button] = key
    end
    return key
end

--- Whether the icon carries this picture, and in which texture exactly.
--
-- This is what recognising an aura amounts to: the index is asked of the icon
-- (`GetID`), while the kind — buff or debuff — is not asked at all, because a
-- foreign icon says nothing about it. Instead of a guess there is a check: the
-- aura at that index is either drawn on this icon or it is not.
--
-- The picture's texture is found along the way — the one the border will stand
-- around. So no second rule of "which of the icon's textures is the main one"
-- is created: the main one is the one carrying the aura's picture.
--
-- @param button table|nil
-- @param icon any the aura's picture from the game (a file id or a path)
-- @return table|nil the texture carrying that picture
function Units.Carries(button, icon)
    if type(button) ~= "table" or icon == nil then return nil end

    local regions = regionsOf(button)
    for i = 1, #regions do
        local region = regions[i]
        if kindOf(region) == "Texture" and type(region.GetTexture) == "function" then
            local ok, value = pcall(region.GetTexture, region)
            if ok and value ~= nil and value == icon then return region end
        end
    end

    return nil
end

--- The aura's index, written on the icon by the game itself.
-- @param button table
-- @return number|nil
local function idOf(button)
    if type(button.GetID) ~= "function" then return nil end
    local ok, value = pcall(button.GetID, button)
    if not ok then return nil end
    local id = tonumber(value)
    if id == nil or id < 1 then return nil end
    return id
end

--- Which aura is on this icon right now.
--
-- Answers `nil` when it could not be recognised, and that is the right answer
-- rather than a refusal: an unrecognised icon is left exactly as the game drew
-- it. A filter that hid something unknown is the worst possible outcome.
--
-- @param button table|nil
-- @param unit string|nil
-- @param query function (unit, index, filter) -> a table about the aura, or
--     nil
-- @return table|nil the information about the aura
-- @return table|nil the texture carrying its picture
function Units.Identify(button, unit, query)
    if type(button) ~= "table" or type(unit) ~= "string" then return nil end
    if type(query) ~= "function" then return nil end

    local index = idOf(button)
    if index == nil then return nil end

    for i = 1, #KINDS do
        local ok, aura = pcall(query, unit, index, KINDS[i])
        if ok and type(aura) == "table" then
            local region = Units.Carries(button, aura.icon)
            if region ~= nil then
                aura.harmful = (KINDS[i] == "HARMFUL")
                return aura, region
            end
        end
    end

    return nil
end

--- Hide a foreign icon, remembering what it was like.
--
-- By opacity rather than by `Hide`: the engine does not allow `Hide` on a
-- protected icon in combat, and deferring it would mean freezing the filter
-- for the whole fight. The details are in the file's header.
--
-- @param state table
-- @param button table|nil
-- @return boolean whether it was hidden now
function Units.Conceal(state, button)
    if type(state) ~= "table" or type(button) ~= "table" then return false end
    if ALPHA[button] ~= nil then return false end

    local alpha = 1
    if type(button.GetAlpha) == "function" then
        local ok, value = pcall(button.GetAlpha, button)
        if ok then alpha = tonumber(value) or 1 end
    end

    local mouse = true
    if type(button.IsMouseEnabled) == "function" then
        local ok, value = pcall(button.IsMouseEnabled, button)
        if ok then mouse = value and true or false end
    end

    ALPHA[button] = alpha
    MOUSE[button] = mouse
    state.held[button] = true

    if type(button.SetAlpha) == "function" then pcall(button.SetAlpha, button, 0) end
    if type(button.EnableMouse) == "function" then
        pcall(button.EnableMouse, button, false)
    end

    return true
end

--- Give a foreign icon back what it was like before us.
--
-- The return is computed from what was remembered rather than from what is
-- current, and it clears both entries after itself: an entry left behind would
-- mean a second "hide" remembering our own opacity as the native one.
--
-- @param state table
-- @param button table|nil
-- @return boolean whether it was given back now
function Units.Reveal(state, button)
    if type(state) ~= "table" or type(button) ~= "table" then return false end
    if ALPHA[button] == nil then return false end

    if type(button.SetAlpha) == "function" then
        pcall(button.SetAlpha, button, ALPHA[button])
    end
    if type(button.EnableMouse) == "function" then
        pcall(button.EnableMouse, button, MOUSE[button] and true or false)
    end

    ALPHA[button] = nil
    MOUSE[button] = nil
    state.held[button] = nil

    return true
end

--- Whether the foreign icon is shown right now.
-- @param button table
-- @return boolean
local function shown(button)
    if type(button.IsShown) ~= "function" then return false end
    local ok, value = pcall(button.IsShown, button)
    return ok and value and true or false
end

--- Put the border around an icon out and forget what it was painted with.
-- @param state table
-- @param layer table|nil our frame, where the borders' textures live
-- @param key string
local function unpaint(state, layer, key)
    if state.painted[key] == nil and state.anchored[key] == nil then return end
    state.painted[key] = nil
    state.anchored[key] = nil
    ns.Icon.Lit(layer, key, false)
end

--- Walk every icon and decide about each one.
--
-- The only place where a decision about a foreign icon is made, and it stands
-- in exactly the same order as the decision about one of our own: **the filter
-- first, the rule second**. The rule is asked inside the "the filter let it
-- through" branch — and the precedence is thereby declared the same way it is
-- in `Auras.Read`: there is nowhere else to ask it.
--
-- The border is repainted only when the colour or the icon under it has
-- changed: eighty icons at nine calls into the engine on every change of auras
-- would cost the player frames for the very same appearance.
--
-- @param state table
-- @param layer table|nil our frame for the borders' textures
-- @param skin table|nil the core's skin
-- @param plan table|nil the filter's plan
-- @param rules table|nil the rules' plan
-- @param query function reading an aura from the game
-- @return number how many icons are shown
-- @return number how many are hidden
function Units.Apply(state, layer, skin, plan, rules, query)
    if type(state) ~= "table" then return 0, 0 end

    local visible, hidden = 0, 0
    local ruled = ns.Rules.Any(rules)
    local needsKey = ns.Filter.NeedsKey(plan)
        or (ruled and ns.Rules.NeedsKey(rules))

    for i = 1, #state.buttons do
        local entry = state.buttons[i]
        local button = entry.frame
        local key = keyFor(state, button)

        local aura, region
        if shown(button) then
            aura, region = Units.Identify(button, entry.unit, query)
        end

        if aura == nil then
            -- The icon is not on screen, or it could not be recognised.
            -- Both cases mean one thing: nothing of ours must be left on
            -- it.
            Units.Reveal(state, button)
            unpaint(state, layer, key)
        else
            local nameKey = needsKey and ns.Filter.Key(aura.name) or nil
            local id = tonumber(aura.spellId)
            local mine = (aura.sourceUnit == "player")

            if ns.Filter.Allows(plan, nameKey, id, mine, aura.harmful) then
                Units.Reveal(state, button)
                visible = visible + 1

                -- The only call of a rule on this path, and it stands after
                -- the filter. A rule gives **the border's colour only**
                -- here: an icon's size is the engine-protected geometry of
                -- somebody else's layout, and an ending sound on the target
                -- would mean "you changed target" rather than "the aura
                -- ended".
                local rule = ruled and ns.Rules.For(rules, nameKey, id) or nil
                local color = ns.Rules.Color(rule, ns.Icon.BORDER_COLOR)

                if state.painted[key] ~= color or state.anchored[key] ~= region then
                    ns.Icon.Outline(layer, key, region, skin, color)
                    state.painted[key] = color
                    state.anchored[key] = region
                end
                ns.Icon.Lit(layer, key, true)
            else
                Units.Conceal(state, button)
                unpaint(state, layer, key)
                hidden = hidden + 1
            end
        end
    end

    return visible, hidden
end

--- Let go of everything foreign.
--
-- Called when the setting is switched off, when the module is switched off and
-- when it fails: a module that is switched off is obliged to leave nothing
-- alive on foreign frames.
--
-- Goes by the `held` ledger rather than by the current scan: an icon that
-- disappeared from the client after we hid it has to be given back — otherwise
-- it stays transparent until a reload, with nobody to say so.
--
-- @param state table
-- @param layer table|nil
-- @return number how many icons were given back
function Units.Forget(state, layer)
    if type(state) ~= "table" then return 0 end

    local returned = 0
    for button in pairs(state.held) do
        if Units.Reveal(state, button) then returned = returned + 1 end
    end

    for key in pairs(state.painted) do
        state.painted[key] = nil
        state.anchored[key] = nil
        ns.Icon.Lit(layer, key, false)
    end
    for key in pairs(state.anchored) do
        state.anchored[key] = nil
        ns.Icon.Lit(layer, key, false)
    end

    for i = #state.buttons, 1, -1 do state.buttons[i] = nil end
    for unit in pairs(state.units) do state.units[unit] = nil end

    return returned
end

--- Whether we are watching this unit.
-- The aura-change event arrives for every unit around, and waking for somebody
-- else's would mean paying for a scan for nothing.
-- @param state table
-- @param unit any
-- @return boolean
function Units.Watches(state, unit)
    if type(state) ~= "table" or type(unit) ~= "string" then return false end
    return state.units[unit] and true or false
end

Units.ALPHA = ALPHA
Units.MOUSE = MOUSE
Units.MAX_DEPTH = MAX_DEPTH
Units.OWNER_DEPTH = OWNER_DEPTH
Units.MAX_BUTTONS = MAX_BUTTONS
