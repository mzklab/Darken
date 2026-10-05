local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("infopanel")

-- The info panel's layout rules: which cells are visible, in what order,
-- which bar they sit on, and how much screen space the panel takes away.
--
-- There is not one call into the game here either. In come the readout names
-- from the registry and what the player chose in the settings; out come lists
-- and numbers.
--
-- === Why the order is stored as names rather than as numbers ===
--
-- The set of readouts changes between sessions: the player installs and
-- removes addons, and yesterday's third cell may not exist at all today. A
-- number in such a set means different things on different days, while a name
-- means one and the same thing. So the profile holds a list of names, and it
-- is not required to be complete: a name that is not in it goes to the end
-- alphabetically, and a name that is no longer in the registry is silently
-- skipped.

local Layout = {}
ns.Layout = Layout

-- The bounds of the numeric settings. In one place: the same number is
-- needed by the default, by the slider in the settings, and by the clamping of
-- a value coming out of SavedVariables.
local BOUNDS = {
    height = { min = 10, max = 40, default = 18 },

    -- The bar's opacity. The floor is not zero: a bar that cannot be seen
    -- at all is a bar that is switched off, and it is switched off by the
    -- checkbox above. A slider that reaches "gone" gives a second way to do
    -- the same thing, and the player then goes looking for why the panel
    -- disappeared.
    opacity = { min = 20, max = 100, default = 100 },
}
Layout.BOUNDS = BOUNDS

-- The sides of the screen. Words rather than numbers: the value goes into
-- the profile.
local SIDES = { top = true, bottom = true }
Layout.SIDES = SIDES

--- Clamp a setting's value to its bounds.
-- @param key string the bound's name
-- @param value any the value from the profile
-- @return number
function Layout.Clamp(key, value)
    local bound = BOUNDS[key]
    if not bound then return 0 end

    if type(value) ~= "number" or value ~= value then return bound.default end
    if value < bound.min then return bound.min end
    if value > bound.max then return bound.max end
    return value
end

--- The full order of the cells: first the ones the player arranged, then the
--- rest.
--
-- Hidden cells are not thrown out of here: this is the order of the whole set,
-- not the list of what is shown. Otherwise a cell that was hidden and shown
-- again would lose its place in the row.
-- @param names table|nil array of names from the registry
-- @param order table|nil array of names from the profile
-- @return table array of names
function Layout.Arrange(names, order)
    local known, seen = {}, {}
    for _, name in ipairs(type(names) == "table" and names or {}) do
        if type(name) == "string" and not known[name] then
            known[name] = true
        end
    end

    local out = {}
    for _, name in ipairs(type(order) == "table" and order or {}) do
        if type(name) == "string" and known[name] and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end

    -- The remainder goes alphabetically rather than in the registry's walk
    -- order: a table walk in Lua has no order, and the row of cells would
    -- rearrange itself between runs.
    local rest = {}
    for name in pairs(known) do
        if not seen[name] then rest[#rest + 1] = name end
    end
    table.sort(rest)

    for _, name in ipairs(rest) do out[#out + 1] = name end
    return out
end

--- The visible cells, in their order.
-- @param names table|nil array of names from the registry
-- @param order table|nil array of names from the profile
-- @param hidden table|nil set of name -> true
-- @return table array of names
function Layout.Visible(names, order, hidden)
    local arranged = Layout.Arrange(names, order)
    if type(hidden) ~= "table" then return arranged end

    local out = {}
    for _, name in ipairs(arranged) do
        if not hidden[name] then out[#out + 1] = name end
    end
    return out
end

--- Move one cell a step forward or back.
-- The new full order is returned — the one that goes into the profile.
-- @param names table|nil array of names from the registry
-- @param order table|nil array of names from the profile
-- @param name string the name being moved
-- @param delta number -1 or 1
-- @return table the new order
function Layout.Move(names, order, name, delta)
    local arranged = Layout.Arrange(names, order)
    if type(name) ~= "string" then return arranged end
    if delta ~= 1 and delta ~= -1 then return arranged end

    local at
    for i = 1, #arranged do
        if arranged[i] == name then at = i break end
    end
    if not at then return arranged end

    local to = at + delta
    if to < 1 or to > #arranged then return arranged end

    arranged[at], arranged[to] = arranged[to], arranged[at]
    return arranged
end

--- Deal the visible cells out between the two bars.
-- @param visible table|nil array of names in their order
-- @param sides table|nil set of name -> top or bottom
-- @param default string|nil the side for cells that were never given one
-- @param bars table|nil { top = boolean, bottom = boolean } which bars are on
-- @return table the top bar
-- @return table the bottom bar
function Layout.Split(visible, sides, default, bars)
    if not SIDES[default] then default = "top" end

    local topOn = type(bars) ~= "table" or bars.top ~= false
    local bottomOn = type(bars) == "table" and bars.bottom == true

    local top, bottom = {}, {}
    for _, name in ipairs(type(visible) == "table" and visible or {}) do
        local side = type(sides) == "table" and sides[name] or nil
        if not SIDES[side] then side = default end

        -- A cell whose bar is switched off does not vanish but moves to the
        -- bar that is on: otherwise a player who switched the bottom bar off
        -- would lose half their readouts and not understand where they
        -- went.
        if side == "top" and not topOn then side = "bottom" end
        if side == "bottom" and not bottomOn then side = "top" end

        if side == "top" and topOn then
            top[#top + 1] = name
        elseif side == "bottom" and bottomOn then
            bottom[#bottom + 1] = name
        end
    end

    return top, bottom
end

--- How much screen space the panel takes away at the top and at the bottom.
--
-- A bar without a single cell takes no space: an empty black ribbon across the
-- screen is the worst thing that can be done with space that was taken away.
-- @param topCells number|nil how many cells are on the top bar
-- @param bottomCells number|nil how many are on the bottom one
-- @param height any the bar's height from the profile
-- @param push any whether to move the interface
-- @return number at the top
-- @return number at the bottom
function Layout.Reserve(topCells, bottomCells, height, push)
    if not push then return 0, 0 end

    local size = Layout.Clamp("height", height)
    local top = (type(topCells) == "number" and topCells > 0) and size or 0
    local bottom = (type(bottomCells) == "number" and bottomCells > 0) and size or 0
    return top, bottom
end

--- UIParent's anchors with the edges moved in.
--
-- Screen space is taken away by lowering UIParent's top edge and raising its
-- bottom one: everything that sits inside UIParent follows along by itself,
-- and not one separate list of "who to move" is needed.
--
-- The native anchors are preserved in full — only the vertical offset changes.
-- Rewriting them into anchors of our own (top-left of the screen, bottom-right
-- of the screen) would mean memorising today's construction of a foreign frame
-- and diverging from it at the very first patch.
-- @param points table|nil array of the native anchors { point, relative to,
--     relative point, x, y }
-- @param top number how much to take away at the top
-- @param bottom number how much to take away at the bottom
-- @return table|nil the new anchors; nil when there is nothing to move
function Layout.Offsets(points, top, bottom)
    if type(points) ~= "table" or #points == 0 then return nil end

    local out, moved = {}, false
    for i = 1, #points do
        local p = points[i]
        if type(p) ~= "table" or type(p[1]) ~= "string" then return nil end

        local anchor = p[1]:upper()
        local dy = 0
        if anchor:find("TOP", 1, true) then
            dy = -(tonumber(top) or 0)
        elseif anchor:find("BOTTOM", 1, true) then
            dy = tonumber(bottom) or 0
        end
        if dy ~= 0 then moved = true end

        out[i] = { p[1], p[2], p[3], tonumber(p[4]) or 0,
            (tonumber(p[5]) or 0) + dy }
    end

    -- Not one anchor holding the top or the bottom: UIParent hangs some
    -- other way on this client, and moving it blind is not allowed. An empty
    -- answer here is more honest than anchors of our own laid over somebody
    -- else's.
    if not moved and ((tonumber(top) or 0) ~= 0 or (tonumber(bottom) or 0) ~= 0) then
        return nil
    end

    return out
end

--- Whether what stands on UIParent matches what the panel put there.
--
-- Moving UIParent is the module's only protected operation, and it has never
-- once reached a live client. So there is something to compare here: the set of
-- anchors the panel asked for, and the set that is on the frame now. If they
-- diverged, then either the game rearranged UIParent itself (a resolution
-- change) or another addon moved it, and our "put it back as it was" would
-- write over somebody else's work.
--
-- The comparison neither keeps quiet nor repairs: it names the first
-- divergence in words, because a person in the chat frame will be reading it,
-- not code.
-- @param expected table|nil the anchors the panel put there
-- @param actual table|nil the anchors that are there now
-- @return string|nil nil when everything matched
function Layout.Verify(expected, actual)
    if type(expected) ~= "table" then return nil end
    if type(actual) ~= "table" then
        return "UIParent has no anchors at all"
    end

    if #expected ~= #actual then
        return "anchors: " .. #actual .. " instead of " .. #expected
    end

    for i = 1, #expected do
        local want, have = expected[i], actual[i]
        if type(have) ~= "table" then
            return "anchor " .. i .. " is gone"
        end

        if want[1] ~= have[1] then
            return tostring(have[1]) .. " instead of " .. tostring(want[1])
        end
        if want[2] ~= have[2] then
            return tostring(want[1]) .. " hangs on something else"
        end
        if want[3] ~= have[3] then
            return tostring(want[1]) .. " hangs by " .. tostring(have[3])
                .. " instead of " .. tostring(want[3])
        end

        local wx, hx = tonumber(want[4]) or 0, tonumber(have[4]) or 0
        local wy, hy = tonumber(want[5]) or 0, tonumber(have[5]) or 0
        if wx ~= hx or wy ~= hy then
            return tostring(want[1]) .. " at " .. hx .. "," .. hy
                .. " instead of " .. wx .. "," .. wy
        end
    end

    return nil
end

--- Whether the engine's refusal to protected code is addressed to us.
--
-- ADDON_ACTION_BLOCKED names the addon whose code the engine would not let
-- through. Moving UIParent from unsafe code is a known source of such
-- refusals, and there is no way at all to test this outside the client: taint
-- does not exist there. All that can be done in advance is to recognise our
-- own refusal when it arrives, and not to claim somebody else's.
--
-- A refusal counts as ours only while screen space is taken away: a panel that
-- moved nothing has nothing to do with somebody else's taint, and an
-- unwarranted accusation aimed at ourselves would send the player off to fix
-- the wrong thing.
-- @param blamed any the addon's name from the event
-- @param mine string|nil the name of our folder
-- @param core string|nil the name of the core's folder
-- @param reserving boolean whether screen space is taken away right now
-- @return boolean
function Layout.Blame(blamed, mine, core, reserving)
    if not reserving then return false end
    if type(blamed) ~= "string" or blamed == "" then return false end
    return blamed == mine or blamed == core
end
