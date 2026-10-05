local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("infopanel")

-- Displaying the info panel: two bars and the cells on them.
--
-- Everything that is decided here was decided in Layout.lua and tested outside
-- the client. This file only calls the engine, and it is written so that
-- outside the game it reaches its end without an error: there is no
-- CreateFrame there, and its absence here is not a failure but the absence of
-- a frame.
--
-- === Whose frame this is ===
--
-- Our own, a child of UIParent, with no secure templates and no attributes.
-- The engine does not protect it, which means it has no combat restrictions at
-- all: there is not one deferred action in this file and there must not be. A
-- deferred repaint would mean a panel frozen for exactly the length of a
-- fight — that is, at the very time one looks at the latency and the frame
-- rate.
--
-- === Its place on screen ===
--
-- NOTE: the paragraph below describes how the bar used to be placed. It now
-- hangs off the edge of the SCREEN (WorldFrame) — see Panel.Place, which says
-- why the old placement was abandoned.
--
-- The bar used to stand not at the screen's edge but at UIParent's edge,
-- offset outwards by exactly the height the module took away from the screen
-- (see InfoPanel.lua, UIParent's insets). The main property followed from
-- that: with the interface shift on, the bar stood inside the ribbon taken
-- away from the screen and covered nothing; with it off, it stood at the
-- screen's edge over everything, and that was the player's visible choice
-- rather than an accident.
--
-- === The clock's tick ===
--
-- The module's only OnUpdate lives here, on the top bar's frame, and it is set
-- only when the panel carries at least one readout that has no event (frames,
-- latency, the clock). The frame is hidden — the engine does not call
-- OnUpdate; the bar is switched off — the script is removed entirely. There is
-- no polling of all the cells in either case: Sources.Due decides what exactly
-- to rebuild.

local Panel = {}
ns.Panel = Panel

-- The bar's font category. The same one the numbers on the core's bars use:
-- the panel carries the same numbers, and a category of its own would split
-- identical text across two settings.
local FONT_CATEGORY = "barvalue"

-- The font category of a cell's menu. A menu is not a bar: it is a small
-- window with the panel fill, a border, rows of the metrics.row height and the
-- dictionary of states — that is, exactly what the bag and item-database
-- windows are built from. Both of those ask for windowtext, and the menu is
-- obliged to ask for the same one: otherwise a player who changed the font of
-- our windows will see it everywhere except in one dropdown.
local MENU_FONT_CATEGORY = "windowtext"

-- The name of a cell's menu frame. A global name is needed for exactly one
-- thing: the list of frames Escape closes (UISpecialFrames) holds names, not
-- objects. A menu without a name cannot be closed by the key at all.
local MENU_NAME = "DarkenInfoPanelMenuFrame"

--- Build one bar.
-- @param skin table|nil the core's skin (the contract, Darken:GetSkin)
-- @return table|nil
function Panel.Build(skin)
    if type(CreateFrame) ~= "function" then return nil end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    frame:SetFrameStrata("LOW")

    if type(skin) == "table" and type(skin.Backdrop) == "function" then
        skin.Backdrop(frame, "ink", "line")
    end

    -- The row of cells is assembled in a frame of its own and centred on the
    -- bar as a whole. That way the row does not jump about the screen when
    -- one cell has grown longer.
    local row = CreateFrame("Frame", nil, frame)
    row:SetPoint("CENTER", frame, "CENTER", 0, 0)
    row:SetHeight(1)
    row:SetWidth(1)
    frame.row = row
    frame.cells = {}

    return frame
end

--- The screen edge the bars hang off.
--
-- WorldFrame rather than UIParent. The difference is that UIParent is moved by
-- us — we lower its top edge to take away room for the bar — while nobody
-- moves WorldFrame: it is the screen.
--
-- This frame does not exist outside the client, and then UIParent is taken
-- instead: without the game there is no layout either, while the placement
-- still has to be tested against something.
-- @return table|nil
function Panel.Root()
    local world = _G.WorldFrame
    if type(world) == "table" and type(world.GetWidth) == "function" then
        return world
    end
    return _G.UIParent
end

--- Put the bar in its place: flush against the screen's edge.
--
-- The bar used to stand at an offset from UIParent's edge — by as much as that
-- edge had been lowered — and together they came out at the screen's former
-- edge. That holds exactly as long as the edge stays where we put it.
--
-- It does not stay. The game recomputes UIParent's layout itself (a change of
-- form, a vehicle, entering a dungeon, its own layout manager), and our shift
-- is rolled back silently. The author's report showed precisely that: an
-- applied 18 above, and right after it a complaint that UIParent is not where
-- the panel left it, TOPLEFT at 0,-0 instead of 0,-18. The bar had been built,
-- shown, was 2133 by 18 and opaque — and hung eighteen pixels above the top of
-- the screen.
--
-- So the bar's place is no longer measured from somebody else's edge. The bar
-- stands at the SCREEN's edge, and a rollback has nothing to damage it with:
-- if no room was taken away, the bar draws over the interface, exactly as the
-- refusal's wording promises, but it is visible.
--
-- @param frame table|nil
-- @param side string top or bottom
-- @param height number the bar's height
function Panel.Place(frame, side, height)
    if type(frame) ~= "table" or type(frame.SetPoint) ~= "function" then
        return
    end

    frame:ClearAllPoints()
    frame:SetHeight(height)

    local root = Panel.Root()
    if side == "bottom" then
        frame:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    else
        frame:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
        frame:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    end
end

--- A safe call of a frame's method.
-- Outside the client half the methods are absent, and a missing method here is
-- not a failure but the absence of a frame.
-- @param object table|nil
-- @param method string
-- @param ... any
-- @return any
local function call(object, method, ...)
    if type(object) ~= "table" then return nil end

    local fn = object[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, object, ...)
    if not ok then return nil end
    return value
end

--- Set the bar's opacity.
--
-- The whole bar's rather than its backdrop's: the cells are read through the
-- background along with it. A transparent background under opaque letters
-- looks not quieter but broken — the letters hang in mid-air.
--
-- @param frame table|nil
-- @param percent any 20..100
function Panel.Opacity(frame, percent)
    if type(frame) ~= "table" then return end

    local want = tonumber(percent)
    if want == nil or want ~= want then want = 100 end
    if want < 20 then want = 20 end
    if want > 100 then want = 100 end

    call(frame, "SetAlpha", want / 100)
end

--- Fill a menu row according to the core's dictionary of states, or remove
--- the fill.
--
-- The dictionary of states (the contract, version 11) is the same rule a
-- section row in the settings window and a choice-list row in the bags window
-- answer by. There is no fill of our own here and there must not be: a hover
-- being lilac at 0.16 is written down in the core once, and a second record
-- would diverge from the first silently, by a tenth of an alpha.
--
-- A core older than version 11 does not give the dictionary — then the row
-- stays unfilled, exactly as it was.
--
-- @param skin table|nil the core's skin
-- @param row table|nil the row's button
-- @param state string|nil "hover"; everything else means no fill
local function paintRow(skin, row, state)
    if type(skin) ~= "table" or type(row) ~= "table" then return end

    local fill = row.umbraFill
    if fill == nil then
        fill = call(row, "CreateTexture", nil, "BACKGROUND")
        if type(fill) ~= "table" then return end
        call(fill, "SetAllPoints", row)
        row.umbraFill = fill
    end

    local name, alpha
    if type(skin.RowColors) == "function" then
        name, alpha = skin.RowColors(state)
    end

    if name == nil or type(skin.Color) ~= "function" then
        call(fill, "Hide")
        return
    end

    call(fill, "SetColorTexture", skin.Color(name, alpha))
    call(fill, "Show")
end

--- The cell at position i, created when first needed.
--
-- A cell is a button with a label inside it rather than a bare label: a label
-- does not take the mouse, while the click and the hover belong to the readout
-- itself (LibDataBroker describes OnClick, OnEnter, OnLeave and
-- OnTooltipShow). The button is one and the same for our readout and for
-- somebody else's — this file does not know which is which, and has nowhere to
-- find out.
--
-- A pool rather than recreation: the cells change on every edit of the
-- settings, while neither frames nor text objects are ever released in the
-- game.
-- @param frame table
-- @param index number
-- @return table|nil
local function cellAt(frame, index)
    local cells = frame.cells
    if cells[index] then return cells[index] end

    local row = frame.row
    if type(row) ~= "table" or type(CreateFrame) ~= "function" then
        return nil
    end

    local button = CreateFrame("Button", nil, row)
    if type(button) ~= "table" then return nil end

    call(button, "RegisterForClicks", "LeftButtonUp", "RightButtonUp")
    call(button, "EnableMouse", true)

    local text = call(button, "CreateFontString", nil, "OVERLAY",
        "GameFontNormalSmall")
    if type(text) == "table" then
        call(text, "SetJustifyH", "CENTER")
        call(text, "SetPoint", "CENTER", button, "CENTER", 0, 0)
        button.label = text
    end

    -- The handlers are set once for the button's whole life and ask the
    -- button itself for the cell's name: the name changes on every repaint,
    -- and a closure that remembered yesterday's name would open the menu of
    -- the wrong cell.
    call(button, "SetScript", "OnClick", function(self, mouse)
        local mine = frame.mouse
        if type(mine) == "table" and type(mine.Click) == "function" then
            mine.Click(self.cellName, mouse, self)
        end
    end)
    call(button, "SetScript", "OnEnter", function(self)
        local mine = frame.mouse
        if type(mine) == "table" and type(mine.Enter) == "function" then
            mine.Enter(self.cellName, self)
        end
    end)
    call(button, "SetScript", "OnLeave", function(self)
        local mine = frame.mouse
        if type(mine) == "table" and type(mine.Leave) == "function" then
            mine.Leave(self.cellName, self)
        end
    end)

    cells[index] = button
    return button
end

--- Show the cells on the bar.
-- @param frame table|nil
-- @param cells table array of { name = the name in the registry, text = the
--     string }
-- @param media table|nil the core's media (the contract, Darken:GetMedia)
-- @param skin table|nil the core's skin
-- @param gap number the gap between cells
-- @param mouse table|nil the handlers { Click, Enter, Leave }
function Panel.SetCells(frame, cells, media, skin, gap, mouse)
    if type(frame) ~= "table" or type(frame.cells) ~= "table" then return end

    cells = type(cells) == "table" and cells or {}
    gap = tonumber(gap) or 12
    frame.mouse = mouse

    local width = 0
    local previous

    for i = 1, #cells do
        local entry = cells[i]
        local cell = cellAt(frame, i)
        if cell and type(entry) == "table" then
            cell.cellName = entry.name

            local label = cell.label
            call(label, "SetText", entry.text)

            if type(media) == "table" and type(media.ApplyFont) == "function" then
                media.ApplyFont(FONT_CATEGORY, label)
            end
            if type(skin) == "table" and type(skin.Text) == "function" then
                skin.Text(label, "text")
            end

            local own = tonumber(call(label, "GetStringWidth")) or 0
            call(cell, "SetSize", own > 0 and own or 1,
                tonumber(call(frame, "GetHeight")) or 18)

            call(cell, "ClearAllPoints")
            if previous then
                call(cell, "SetPoint", "LEFT", previous, "RIGHT", gap, 0)
            else
                call(cell, "SetPoint", "LEFT", frame.row, "LEFT", 0, 0)
            end
            call(cell, "Show")

            width = width + own
            if previous then width = width + gap end

            previous = cell
        end
    end

    -- Surplus cells are hidden rather than removed: the set of cells
    -- changes, while frames are never released in the game.
    for i = #cells + 1, #frame.cells do
        local cell = frame.cells[i]
        if cell then
            cell.cellName = nil
            call(cell, "Hide")
        end
    end

    local row = frame.row
    if type(row) == "table" and type(row.SetWidth) == "function" then
        row:SetWidth(width > 0 and width or 1)
    end
end

--- Show or hide the bar.
-- @param frame table|nil
-- @param shown boolean
function Panel.Show(frame, shown)
    if type(frame) ~= "table" then return end

    if shown then
        if type(frame.Show) == "function" then frame:Show() end
    else
        if type(frame.Hide) == "function" then frame:Hide() end
    end
end

--- Set or remove the clock's tick.
--
-- The script is set on the bar's frame, and that is the main point here: the
-- engine does not walk a hidden frame, so a switched-off panel counts nothing
-- all by itself, without a single check of "are we shown".
-- @param frame table|nil
-- @param fn function|nil the handler (elapsed), or nil to remove it
function Panel.Drive(frame, fn)
    if type(frame) ~= "table" or type(frame.SetScript) ~= "function" then
        return
    end

    if type(fn) ~= "function" then
        frame:SetScript("OnUpdate", nil)
        return
    end

    frame:SetScript("OnUpdate", function(_, elapsed) fn(elapsed) end)
end

--- Show a cell's tooltip.
--
-- The intent arrives finished (ns.Cells.Tooltip), and all that is left here is
-- to carry it out. The "the readout draws it itself" branch is the main one:
-- an addon with a tooltip of its own, built its own way, draws it itself from
-- our bar too.
-- @param plan table|nil
-- @param cell table|nil the cell's frame
function Panel.Tooltip(plan, cell)
    if type(plan) ~= "table" then return end

    if plan.kind == "own" then
        pcall(plan.fn, cell)
        return
    end

    local tooltip = _G.GameTooltip
    if type(tooltip) ~= "table" then return end

    call(tooltip, "SetOwner", cell, "ANCHOR_NONE")
    call(tooltip, "ClearLines")
    call(tooltip, "ClearAllPoints")

    -- The tooltip stands from the cell inwards: downwards for the top bar,
    -- upwards for the bottom one. It has nowhere to go outwards — the edge is
    -- there.
    local below = true
    if type(cell) == "table" and type(cell.GetTop) == "function" then
        local top = tonumber(call(cell, "GetTop"))
        local screen = tonumber(call(_G.UIParent, "GetHeight"))
        if top and screen and top < screen / 2 then below = false end
    end
    if below then
        call(tooltip, "SetPoint", "TOP", cell, "BOTTOM", 0, -4)
    else
        call(tooltip, "SetPoint", "BOTTOM", cell, "TOP", 0, 4)
    end

    if plan.kind == "fill" then
        pcall(plan.fn, tooltip)
    elseif plan.kind == "text" then
        call(tooltip, "AddLine", plan.text)
    else
        if plan.label then call(tooltip, "AddLine", plan.label) end
        if plan.text then call(tooltip, "AddLine", plan.text) end
    end

    call(tooltip, "Show")
end

--- Take the tooltip away.
-- It is always hidden, whatever drew it: a readout that drew its own hides it
-- by its own OnLeave, and our branch does so by this line.
function Panel.Untooltip()
    local tooltip = _G.GameTooltip
    if type(tooltip) == "table" then call(tooltip, "Hide") end
end

--- Close a cell's menu.
function Panel.CloseMenu()
    -- The menu's own OnHide removes the catcher and the memory of whose menu
    -- it is: the menu can also be closed past this door — Escape calls Hide
    -- directly, and a screen-wide catcher left behind after it would eat every
    -- click the player makes.
    if Panel.menu then call(Panel.menu, "Hide") end
    if Panel.catcher then call(Panel.catcher, "Hide") end
    Panel.menuOf = nil
end

--- Enter the menu into the list of frames Escape closes, or take it out.
--
-- A menu is not a window, and it has no close button and must not have one: it
-- is closed by a click past it, by a second click on the same cell, and by
-- choosing a row. Escape was added to those three because the player presses
-- it on anything that pops up over the screen, and "nothing happened" reads as
-- a failure.
--
-- The cost is the same as for the modules' windows: the list is shared across
-- the whole interface, the names in it outlive the module being switched off,
-- and taking our name out is our job.
--
-- @param on boolean|nil true to enter it, false to take it out
-- @return boolean whether there was anything to change (the game's list is
--     present)
function Panel.Dismissable(on)
    local list = _G.UISpecialFrames
    if type(list) ~= "table" then return false end

    if on == false then
        for i = #list, 1, -1 do
            if list[i] == MENU_NAME then table.remove(list, i) end
        end
        return true
    end

    for i = 1, #list do
        if list[i] == MENU_NAME then return true end
    end

    list[#list + 1] = MENU_NAME
    return true
end

--- The menu row at position i.
-- @param index number
-- @return table|nil
local function rowAt(index)
    local rows = Panel.menuRows
    local menu = Panel.menu
    if not rows or not menu then return nil end
    if rows[index] then return rows[index] end

    local button = CreateFrame("Button", nil, menu)
    if type(button) ~= "table" then return nil end

    local label = call(button, "CreateFontString", nil, "OVERLAY",
        "GameFontNormal")
    if type(label) == "table" then
        call(label, "SetPoint", "LEFT", button, "LEFT", 0, 0)
        call(label, "SetJustifyH", "LEFT")
        button.label = label
    end

    rows[index] = button
    return button
end

--- Open a cell's menu.
--
-- The menu is our own frame under UIParent, protected by nothing: it opens in
-- combat as it does outside it, and there is nothing to defer here.
--
-- A screen-wide catcher stands beside the menu: a click past the menu closes
-- it. Without it the only way to close the menu would be to choose something
-- in it.
--
-- @param entries table|nil the rows (ns.Cells.Menu)
-- @param cell table|nil the frame of the cell whose menu is open
-- @param name string the cell's name
-- @param skin table|nil the core's skin
-- @param media table|nil the core's media
-- @param pick function the choice handler: pick(entry)
function Panel.Menu(entries, cell, name, skin, media, pick)
    if type(entries) ~= "table" or #entries == 0 then return end
    if type(CreateFrame) ~= "function" then return end

    -- A second click on the same cell closes the menu: a player who opened
    -- it by mistake closes it by the same movement that opened it.
    if Panel.menu and call(Panel.menu, "IsShown") and Panel.menuOf == name then
        Panel.CloseMenu()
        return
    end

    if not Panel.catcher then
        local catcher = CreateFrame("Button", nil, _G.UIParent)
        if type(catcher) == "table" then
            call(catcher, "SetAllPoints", _G.UIParent)
            call(catcher, "SetFrameStrata", "FULLSCREEN_DIALOG")
            call(catcher, "RegisterForClicks", "AnyUp")
            call(catcher, "SetScript", "OnClick", function()
                Panel.CloseMenu()
            end)
            call(catcher, "Hide")
            Panel.catcher = catcher
        end
    end

    if not Panel.menu then
        -- With a name rather than anonymous as it used to be: the Escape
        -- list needs the name.
        local menu = CreateFrame("Frame", MENU_NAME, _G.UIParent)
        if type(menu) ~= "table" then return end
        Panel.menu = menu
        Panel.menuRows = {}
        call(menu, "SetFrameStrata", "FULLSCREEN_DIALOG")
        call(menu, "EnableMouse", true)
        -- The catcher goes away together with the menu, by whatever means
        -- it was closed.
        call(menu, "SetScript", "OnHide", function()
            if Panel.catcher then call(Panel.catcher, "Hide") end
            Panel.menuOf = nil
        end)
        call(menu, "Hide")
        Panel.Dismissable(true)
    end

    local menu = Panel.menu
    -- The inset of the contents from the border and the height of a
    -- clickable row are names from the core's scale rather than numbers or
    -- arithmetic over neighbouring names. A menu row is the same kind of
    -- clickable row as a choice-list row in the bags window and a section row
    -- in the settings window, and the height of all three has to be one: as
    -- three different ones it read as three different addons.
    local inset, rowHeight = 12, 26
    if type(skin) == "table" and type(skin.Metrics) == "function" then
        local metrics = skin.Metrics()
        inset = tonumber(metrics.inset) or inset
        rowHeight = tonumber(metrics.row) or rowHeight
    end

    local width = 0
    for i = 1, #entries do
        local entry = entries[i]
        local row = rowAt(i)
        if row then
            local label = row.label
            call(label, "SetText", entry.label)
            if type(media) == "table" and type(media.ApplyFont) == "function" then
                media.ApplyFont(MENU_FONT_CATEGORY, label)
            end
            -- A row that currently has nowhere to lead stays in place and
            -- dims: a row that disappears shifts its neighbours under a hand
            -- already raised.
            if type(skin) == "table" and type(skin.Text) == "function" then
                skin.Text(label, entry.enabled == false and "textDim" or "text")
            end

            local own = tonumber(call(label, "GetStringWidth")) or 0
            if own > width then width = own end

            call(row, "SetHeight", rowHeight)
            -- Under the cursor a row answers with a wash from the core's
            -- dictionary of states. Before that the menu answered a hover
            -- with nothing at all: a clickable row that does not answer the
            -- cursor reads as a caption rather than as a choice.
            paintRow(skin, row, nil)
            call(row, "SetScript", "OnEnter", function(self)
                paintRow(skin, self, "hover")
            end)
            call(row, "SetScript", "OnLeave", function(self)
                paintRow(skin, self, nil)
            end)
            call(row, "ClearAllPoints")
            call(row, "SetPoint", "TOPLEFT", menu, "TOPLEFT", inset,
                -(inset + (i - 1) * rowHeight))
            call(row, "SetScript", "OnClick", function()
                Panel.CloseMenu()
                if entry.enabled ~= false and type(pick) == "function" then
                    pick(entry)
                end
            end)
            call(row, "Show")
        end
    end

    for i = #entries + 1, #(Panel.menuRows or {}) do
        call(Panel.menuRows[i], "Hide")
    end

    for i = 1, #entries do
        local row = Panel.menuRows[i]
        if row then call(row, "SetWidth", width > 0 and width or 1) end
    end

    call(menu, "SetSize", width + inset * 2, #entries * rowHeight + inset * 2)
    call(menu, "ClearAllPoints")

    -- The menu grows from the cell inwards — the same way the tooltip does,
    -- and for the same reason.
    local below = true
    local top = tonumber(call(cell, "GetTop"))
    local screen = tonumber(call(_G.UIParent, "GetHeight"))
    if top and screen and top < screen / 2 then below = false end
    if below then
        call(menu, "SetPoint", "TOP", cell, "BOTTOM", 0, -2)
    else
        call(menu, "SetPoint", "BOTTOM", cell, "TOP", 0, 2)
    end

    if type(skin) == "table" and type(skin.Backdrop) == "function" then
        skin.Backdrop(menu, "panel", "line")
    end

    Panel.menuOf = name
    if Panel.catcher then call(Panel.catcher, "Show") end
    call(menu, "Show")
end
