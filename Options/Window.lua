local ADDON, ns = ...

-- The settings window: page column, content area, search.
--
-- === Pure code and drawing code ===
--
-- Everything that decides is pure and testable: which pages survive the
-- search text, what order they stand in, which belong to the column's first
-- group and which to the second. Everything that draws is below that and is
-- verified by eye, because frames cannot be created outside the client.
--
-- The boundary is deliberate. In the previous window, decisions were spread
-- through wrappers around library handlers: there was nowhere to test them,
-- and they broke silently.

local Window = {}
ns.Window = Window

local Skin = ns.Skin
local Schema = ns.Schema
local Widgets = ns.Widgets
local M = Skin.Metrics

local Try = Widgets and Widgets.Try or function() end

-- Window size. The column is wide enough for the longest page title: a
-- clipped title reads as a bug rather than as a shortage of space.
local WIDE, HIGH = 820, 620
local COLUMN = 180

-- Strip reserved for the close button: button height plus insets, computed
-- rather than written as a round number. It used to be 28 while the button
-- needs M.row plus a bottom inset, and the missing pixels were taken from
-- the page, overlapping the last setting.
local FOOTER = M.row + M.inset * 2

-- Buttons per row. Three: more and the labels stop fitting, fewer and the
-- row stops reading as a row.
local PER_ROW = 3

-- The addon mark in the header.
--
-- Shorter than the header rather than equal to it: a mark filling the header
-- touches both edges and reads as a patch. The width follows the file's
-- aspect ratio (256 by 64, four to one); a stretched mark looks worse than
-- no mark.
local LOGO = "Interface" .. string.char(92) .. "AddOns" .. string.char(92)
    .. "Darken" .. string.char(92) .. "Media" .. string.char(92)
    .. "branding" .. string.char(92) .. "darken-title-256"
local LOGO_HIGH = M.header - M.gap
local LOGO_WIDE = LOGO_HIGH * 4

--============================================================================
-- Pure decisions
--============================================================================

--- Normalise a string for comparison.
--
-- Case and surrounding space are removed: someone typing " Font " expects to
-- find "Fonts". Case folding comes from the core, which handles Cyrillic;
-- string.lower in this client only handles Latin.
--
-- @param said any
-- @return string
function Window.Fold(said)
    if type(said) ~= "string" then return "" end

    local trimmed = said:match("^%s*(.-)%s*$") or said
    if ns.Casefold and type(ns.Casefold.Fold) == "function" then
        local ok, folded = pcall(ns.Casefold.Fold, trimmed)
        if ok and type(folded) == "string" then return folded end
    end
    return trimmed:lower()
end

--- Whether a row matches the search text.
--
-- Both the label and the hint are searched: people remember a word from what
-- a setting does rather than its name. An empty query matches everything —
-- a search that hides everything when the box is empty turns the window into
-- a blank page, and an empty box is what opening it shows.
--
-- @param item table|nil
-- @param query string|nil query, already folded
-- @return boolean
function Window.Matches(item, query)
    if type(query) ~= "string" or query == "" then return true end
    if type(item) ~= "table" then return false end

    local label = Window.Fold(item.label)
    if label ~= "" and label:find(query, 1, true) then return true end

    -- A hint may be a function. Fold on a function returns an empty
    -- string, and the row would stop matching words from its own hint.
    local hint = Window.Fold(type(item.hint) == "function"
        and Window.Says(item.hint) or item.hint)
    if hint ~= "" and hint:find(query, 1, true) then return true end

    return false
end

--- Pages the column shows for this query.
--
-- A page survives if its own title matches, or if any of its rows do. The
-- first case matters because someone searching "profiles" expects the whole
-- page, not a setting that happens to contain the word.
--
-- @param pages table array of pages
-- @param said any the search text
-- @return table array of pages
function Window.Filter(pages, said)
    local query = Window.Fold(said)
    local out = {}

    for _, page in ipairs(type(pages) == "table" and pages or {}) do
        local keep = query == ""

        if not keep then
            local title = Window.Fold(ns.Localize and ns.Localize(page.title)
                or page.title)
            keep = title ~= "" and title:find(query, 1, true) and true or false
        end

        -- The assembled page, not only its own rows: nested pages put
        -- their rows here, and a word from a font category setting has to
        -- find "Fonts" because the category has no column entry of its
        -- own.
        if not keep then
            for _, item in ipairs(Window.Plan(page.id)) do
                if Window.Matches(item, query) then keep = true break end
            end
        end

        if keep then out[#out + 1] = page end
    end

    return out
end

--- Split pages into the column's two groups.
--
-- The first group is about the game, the second about the addon itself. They
-- are separated by tone rather than by a border: a border around half the
-- list is one more line in a window already carrying enough of them.
--
-- @param pages table
-- @return table, table first group, second group
function Window.Layers(pages)
    local main, aside = {}, {}
    for _, page in ipairs(type(pages) == "table" and pages or {}) do
        -- Nested pages get no column entry: their rows live on the parent
        -- page, and a second route to them would place one setting in two
        -- places. The `parent` field existed from the start but was read by
        -- nobody until this was added, so the column listed twenty entries
        -- instead of twelve and the last ones fell past its edge.
        if page.parent == nil then
            if page.aside then aside[#aside + 1] = page
            else main[#main + 1] = page end
        end
    end
    return main, aside
end

--- Which page to show when the current one left the list.
--
-- It leaves because of the search: a word is typed that the open page does
-- not contain. Jumping to an arbitrary page on each keystroke is wrong — the
-- player is still typing — but showing a page that is no longer in the
-- column is also wrong. The rule: keep the current page if it survived,
-- otherwise the first, otherwise nothing.
--
-- @param pages table pages already filtered
-- @param current any id of the open page
-- @return string|nil
function Window.Choose(pages, current)
    local list = type(pages) == "table" and pages or {}
    if #list == 0 then return nil end

    for _, page in ipairs(list) do
        if page.id == current then return current end
    end

    return list[1].id
end

--============================================================================
-- Drawing
--============================================================================

local frame

--- Build the window shell.
--
-- The shell is everything independent of the pages: header with the close
-- button, search box, column, content area, footer. Pages are filled in
-- separately and re-laid out on every repaint.
--
-- @return table|nil
function Window.Build()
    if frame then return frame end
    if type(Widgets) ~= "table" then return nil end

    local root = Widgets.Frame("Frame", _G.UIParent)
    if root == nil then return nil end

    Try(root, "SetSize", WIDE, HIGH)
    Try(root, "SetPoint", "CENTER", _G.UIParent, "CENTER", 0, 0)
    Try(root, "SetFrameStrata", "DIALOG")
    Try(root, "SetToplevel", true)
    Try(root, "EnableMouse", true)
    Try(root, "SetMovable", true)
    Try(root, "SetClampedToScreen", true)
    Widgets.Dress(root, "ink", "line")

    -- Header: the drag handle, carrying the mark and the close button.
    local head = Widgets.Frame("Frame", root)
    if head then
        Try(head, "SetHeight", M.header)
        Try(head, "SetPoint", "TOPLEFT", root, "TOPLEFT", M.hair, -M.hair)
        Try(head, "SetPoint", "TOPRIGHT", root, "TOPRIGHT", -M.hair, -M.hair)
        Try(head, "EnableMouse", true)
        Try(head, "RegisterForDrag", "LeftButton")
        Try(head, "SetScript", "OnDragStart", function()
            Try(root, "StartMoving")
        end)
        Try(head, "SetScript", "OnDragStop", function()
            Try(root, "StopMovingOrSizing")
        end)

        -- The addon is identified by its mark, not by its name in text.
        -- The mark already appears on the minimap button and in the addon
        -- list; text in one place out of three gives one thing two
        -- identities.
        local title = Try(head, "CreateTexture", nil, "ARTWORK")
        if type(title) == "table" then
            Try(title, "SetTexture", LOGO)
            Try(title, "SetSize", LOGO_WIDE, LOGO_HIGH)
            Try(title, "SetPoint", "LEFT", head, "LEFT", M.group, 0)
        end

        -- Text is the fallback: the texture may fail to load, and a header
        -- with no identity reads as somebody else's window.
        if type(title) ~= "table" then
            title = Widgets.Text(head, "lilac")
            if title then
                Try(title, "SetPoint", "LEFT", head, "LEFT", M.inset, 0)
                Try(title, "SetText", ADDON)
            end
        end
        head.title = title

        -- The close glyph is a multiplication sign, not the letter x: a
        -- letter is centred on its character cell rather than on itself, and
        -- sat left of centre.
        local close = Widgets.Button(head, "\195\151", function()
            Window.Hide()
        end, M.field)
        if close then
            Try(close, "ClearAllPoints")
            Try(close, "SetPoint", "RIGHT", head, "RIGHT", -M.inset, 0)
            Try(close, "SetHeight", M.field)
        end
        head.close = close
    end
    root.head = head

    -- Seam under the header: it divides the window rather than enclosing
    -- part of it.
    local seam = Try(root, "CreateTexture", nil, "ARTWORK")
    if type(seam) == "table" then
        Try(seam, "SetColorTexture", Skin.Get("line"))
        Try(seam, "SetHeight", M.hair)
        Try(seam, "SetPoint", "TOPLEFT", head or root, "BOTTOMLEFT", 0, 0)
        Try(seam, "SetPoint", "TOPRIGHT", head or root, "BOTTOMRIGHT", 0, 0)
    end

    -- Page column: header to footer, the full height of the window.
    --
    -- The search box used to sit above it, so the column started lower. A
    -- list cropped from above by an unrelated field reads as a continuation
    -- of that field, and it had less room while a whole page stood empty
    -- beside it.
    local column = Widgets.Frame("Frame", root)
    if column then
        Try(column, "SetWidth", COLUMN)
        Try(column, "SetPoint", "TOPLEFT", root, "TOPLEFT", M.inset,
            -(M.header + M.inset))
        Try(column, "SetPoint", "BOTTOM", root, "BOTTOM", 0, FOOTER)

        -- The background belongs to the whole column, not to each row.
        -- Rows end where the pages end, leaving a bare gap down to the
        -- second group, and the list read as two pieces with something lost
        -- between them.
        Widgets.Dress(column, "panelAlt", "line")
    end
    root.column = column

    -- The search box sits on the right, above the page: it searches the
    -- settings, which are on the right, not the list on the left.
    local search = Widgets.EditBox(root, nil,
        function(said) Window.Seek(said) end)
    if search then
        -- Responds to every keystroke rather than to Enter: the player
        -- types and watches what remains; there is nothing to confirm.
        if search.box then
            Try(search.box, "SetScript", "OnTextChanged", function(self)
                Window.Seek(Try(self, "GetText") or "")
            end)
        end
        Try(search, "ClearAllPoints")
        Try(search, "SetPoint", "TOPLEFT", column or root, "TOPRIGHT",
            M.inset, 0)
        Try(search, "SetPoint", "TOPRIGHT", root, "TOPRIGHT", -M.inset,
            -(M.header + M.inset))
    end
    root.search = search

    -- Content: a scrollable area right of the column, below the search.
    local page = Widgets.Frame("Frame", root)
    if page then
        Try(page, "SetPoint", "TOPLEFT", search or column, "BOTTOMLEFT",
            search and 0 or M.inset, -M.gap)
        Try(page, "SetPoint", "BOTTOMRIGHT", root, "BOTTOMRIGHT", -M.inset,
            FOOTER)
        Widgets.Dress(page, "panelAlt", "line")
    end
    root.page = page

    local scroll = Widgets.Scroll(page)
    if scroll then
        Try(scroll, "SetPoint", "TOPLEFT", page, "TOPLEFT", M.rail, -M.rail)
        Try(scroll, "SetPoint", "BOTTOMRIGHT", page, "BOTTOMRIGHT", -M.rail,
            M.rail)
    end
    root.scroll = scroll

    -- Footer: the close button at the right edge.
    local done = Widgets.Button(root,
        ns.Localize and ns.Localize("Close") or "Close", function()
            Window.Hide()
        end)
    if done then
        Try(done, "ClearAllPoints")
        Try(done, "SetPoint", "BOTTOMRIGHT", root, "BOTTOMRIGHT", -M.inset,
            M.inset)
    end
    root.done = done

    Try(root, "Hide")
    frame = root
    return frame
end

--- Show the window.
function Window.Show()
    local root = Window.Build()
    if root == nil then return end

    -- Repaint here rather than at build time: a page depends on the
    -- profile, and the profile can change between two openings.
    Window.Repaint()
    Try(root, "Show")
end

--- Hide the window.
function Window.Hide()
    if frame then
        Widgets.CloseList()
        Try(frame, "Hide")
    end
end

--- Whether the window is open.
-- @return boolean
function Window.IsShown()
    if frame == nil then return false end
    return Try(frame, "IsShown") and true or false
end

--- Toggle the window.
-- @return boolean whether it is shown now
function Window.Toggle()
    if Window.IsShown() then
        Window.Hide()
        return false
    end
    Window.Show()
    return true
end

--============================================================================
-- Filling a page
--============================================================================

--- Resolve a field that may be either a value or a predicate.
--
-- A row is declared as data, but two of its properties depend on OTHER
-- settings: "only mine" has nothing to narrow once all buffs are hidden,
-- and the paragraph about an empty screen is pointless until the screen is
-- empty. Such a property cannot be a value written at file scope; it can
-- only be asked at the moment the row is drawn.
--
-- A predicate that raises counts as false, deliberately. Of the two silent
-- failures — a row shown once too often, and a row gone from sight — the
-- first is visible and will be asked about; the second looks as though the
-- setting never existed.
--
-- @param field any value, predicate or nil
-- @return boolean
local function asked(field)
    if type(field) == "function" then
        local ok, said = pcall(field)
        return (ok and said) and true or false
    end
    return field and true or false
end

--- Whether the row is hidden right now.
-- @param item table|nil
-- @return boolean
function Window.Hidden(item)
    if type(item) ~= "table" then return false end
    return asked(item.hidden)
end

--- Whether the row is disabled right now.
--
-- A disabled row STAYS on the page: by being visible and inert it answers
-- "why does this change nothing right now", which a missing row does not
-- answer at all. Rows are hidden only where they describe a combination of
-- settings that does not currently hold.
--
-- @param item table|nil
-- @return boolean
function Window.Dimmed(item)
    if type(item) ~= "table" then return false end
    return asked(item.disabled)
end

-- An assembled page: its own rows plus the rows of its nested pages.
--
-- === Why nesting exists ===
--
-- One checkbox does not earn a column entry: an entry opened once and never
-- again is one more question about where to go. So the minimap button nests
-- under General, item level and durability under Gear, and the five font
-- categories under Fonts.
--
-- A nested page remains a page: it keeps its own profile section — the
-- minimap button's is a different store entirely, one per account — and that
-- is the only reason it is a page rather than a heading.
--
-- === Why a heading is inserted ===
--
-- Without one the rows of five font categories merge into a list of fifteen
-- fields with nothing to tell them apart: Font, Size, Outline, then Font,
-- Size, Outline again. The heading carries the nested page's title.
--
-- That heading is not declared in the schema; it is derived from the
-- nesting. It is therefore built ONCE per page and cached: a fresh table on
-- every repaint would grow the row cache on every keystroke in the search
-- box, because rows are keyed by their schema table.
local PLANS = {}
local PLANS_ERA = nil

--- Every row of a page, nested pages included.
-- @param pageId any
-- @return table array of schema rows
function Window.Plan(pageId)
    if type(pageId) ~= "string" then return {} end

    -- The schema was redeclared, so anything assembled from it is stale.
    -- Detected by generation rather than by an explicit invalidation call,
    -- which is eventually forgotten and leaves the window showing pages from
    -- a previous schema.
    local now = Schema.Era and Schema.Era() or 1
    if PLANS_ERA ~= now then
        PLANS, PLANS_ERA = {}, now
    end

    if PLANS[pageId] ~= nil then return PLANS[pageId] end

    local out = {}
    for _, item in ipairs(Schema.Items(pageId)) do out[#out + 1] = item end

    for _, child in ipairs(Schema.Children(pageId)) do
        local items = Schema.Items(child.id)
        if #items > 0 then
            out[#out + 1] = {
                kind = "header",
                label = child.title,
                -- Which page a row belongs to matters for reading and
                -- writing: it uses the NESTED page's section, not the
                -- parent's.
                umbraPage = child.id,
            }
            for _, item in ipairs(items) do
                out[#out + 1] = item
                -- Owner marker. Without it the minimap button row would
                -- write to the profile, while its value lives in the
                -- account-wide store.
                item.umbraPage = child.id
            end
        end
    end

    PLANS[pageId] = out
    return out
end

--- Discard assembled pages. For tests only.
function Window.Forget()
    PLANS = {}
end

--- Which page a row reads and writes through.
-- @param page table the page currently open
-- @param item table
-- @return table the page whose section the row uses
function Window.Owner(page, item)
    if type(item) == "table" and type(item.umbraPage) == "string" then
        local own = Schema.Of(item.umbraPage)
        if own ~= nil then return own end
    end
    return page
end

--- Whether an assembled page holds conditional rows.
--
-- Nested pages are asked too: their rows appear on the same page, and a
-- hidden row of a nested page must hide the same way.
--
-- @param pageId any
-- @return boolean
function Window.Marked(pageId)
    if Schema.Conditional(pageId) then return true end
    for _, child in ipairs(Schema.Children(pageId)) do
        if Schema.Conditional(child.id) then return true end
    end
    return false
end

--- Which rows of a page to show for this query.
--
-- Pure, and therefore testable. One rule, and it is not obvious: with a
-- NON-empty query, headings and paragraphs disappear along with the settings
-- they introduce.
--
-- Otherwise searching a word leaves a page in the column carrying five
-- headings in a row and no settings beneath them. A heading exists to divide
-- a list, and there it has nothing to divide.
--
-- @param pageId any
-- @param said any the search text
-- @return table array of rows
function Window.Rows(pageId, said)
    local query = Window.Fold(said)
    local all = Window.Plan(pageId)

    -- Nothing to search and nothing that can hide: return the list as is.
    -- This is the common case — a page without conditional rows, opened with
    -- an empty search box.
    if query == "" and not Window.Marked(pageId) then return all end

    local out = {}
    for _, item in ipairs(all) do
        -- Hidden rows are dropped before the search: a row that is not on
        -- the page should not be found by a word from it.
        if not Window.Hidden(item) then
            local decor = item.kind == "header" or item.kind == "note"
                or item.kind == "tabs"
            if query == "" or (not decor and Window.Matches(item, query)) then
                out[#out + 1] = item
            end
        end
    end
    return out
end

--============================================================================
-- Vertical layout
--============================================================================

--- Where each row lands, and the total height of the list.
--
-- Pure arithmetic, separated out because it fails silently. An off-by-one in
-- a gap raises nothing: rows simply overlap or drift apart, and a wrong
-- total height means the scroll never reaches the last setting — it is
-- off-screen, which reads as the setting not existing.
--
-- === Headings get a larger gap above them ===
--
-- A heading exists to divide the list, and it divides by having more space
-- above it than between neighbouring rows. With an equal gap it reads as one
-- more row, merely bolder, and stops dividing.
--
-- The FIRST heading gets no extra space: it has nothing above it to divide
-- from, and a blank strip at the top of a page reads as a cropped image.
--
-- @param rows table|nil rows, for their kinds
-- @param sizes table|nil height of each row, in the same order
-- @return table offsets downward from the top, one per row, non-positive
-- @return number total height
function Window.Stack(rows, sizes)
    local out, total = {}, 0
    if type(rows) ~= "table" or type(sizes) ~= "table" then return out, 0 end

    for i = 1, #rows do
        local height = tonumber(sizes[i]) or M.row

        if i > 1 then
            -- Gap between rows; wider before a heading.
            local gap = M.gap
            if type(rows[i]) == "table" and rows[i].kind == "header" then
                gap = M.group
            end
            total = total + gap
        end

        -- Downward from the top edge, which the engine expresses as a
        -- negative offset.
        out[i] = -total
        total = total + height
    end

    return out, total
end

--- Height of a row of this kind.
--
-- A number per kind, rather than asking the frame. A frame answers with what
-- it KNOWS, and a frame with neither a size nor both anchors honestly
-- answers zero; a zero-height row lands on the next one. The number is known
-- before anything is drawn.
--
-- The spacing is part of the number: eight pixels, not two. At two the rows
-- touched, and a mouse off by one pixel hit the neighbouring setting — which
-- matters because a checkbox toggles silently.
--
-- @param kind any row kind
-- @return number
function Window.Tall(kind)
    -- Paragraphs and custom widgets are measured; this is their
    -- fallback.
    if kind == "note" then return M.row * 3 end
    if kind == "widget" then return M.row * 6 end

    -- A heading needs space above it: that space is how it divides.
    if kind == "header" then return M.row + 14 end

    -- Everything else is one row. Dropdown, slider and edit box keep their
    -- label on the LEFT rather than above: a label above costs twice the
    -- height and gains nothing, and on a page of twenty settings that is
    -- forty rows instead of twenty.
    return M.row + 8
end

-- Kinds whose height is not known in advance: a paragraph wraps to however
-- many lines the width allows, and a custom widget is as tall as its list is
-- long. A fixed number for these diverges from the truth silently, so rows
-- either overlap or leave a gap.
local MEASURED = { note = true, widget = true }

--- Height a row actually occupies.
--
-- Known kinds answer with their number and do not ask the frame; there is
-- nothing to measure. The rest ask the frame and fall back to the number if
-- it has no answer: a zero height would merge two rows into one.
--
-- @param item table|nil schema row
-- @param made table|nil the constructed frame
-- @return number
function Window.Height(item, made)
    local kind = type(item) == "table" and item.kind or nil
    local fixed = Window.Tall(kind)

    if not MEASURED[kind] or type(made) ~= "table" then return fixed end

    local got = tonumber(Try(made, "GetHeight"))
    if got == nil or got <= 1 then return fixed end

    -- Four pixels above the measured height is the gap to the next row.
    -- For the other kinds that gap is already inside their number.
    return got + 4
end

--- Read a row's value.
-- @param page table
-- @param item table
-- @return any
function Window.Value(page, item)
    if type(item) ~= "table" then return nil end
    if type(item.get) == "function" then
        local ok, got = pcall(item.get)
        if ok then return got end
        return nil
    end
    return Schema.Read(Schema.Ground(page), item.path)
end

--- Apply whatever the row asks to be applied.
--
-- "none" is a choice and does nothing. A subsystem name asks the core to
-- call that subsystem's Apply; whether it can run now is the core's decision
-- — some work is deferred during combat — and not this file's concern.
--
-- @param item table
local function applied(item)
    if type(item) ~= "table" then return end
    if item.apply == nil or item.apply == "none" then return end

    local registry = ns.Registry
    if type(registry) ~= "table" then return end

    local module = registry:Get(item.apply)
    if module == nil then return end

    pcall(registry.ApplyOne, registry, module)
end

--- Write a row's value and apply it.
-- @param page table
-- @param item table
-- @param value any
-- @return boolean whether it wrote
function Window.Store(page, item, value)
    if type(item) ~= "table" then return false end

    local wrote
    if type(item.set) == "function" then
        wrote = pcall(item.set, value)
    else
        wrote = Schema.Write(Schema.Ground(page), item.path, value)
    end

    if wrote then applied(item) end
    return wrote and true or false
end

--- Construct the widget for one row.
-- @param parent table
-- @param page table
-- @param item table
-- @return table|nil
local function widgetFor(parent, page, item)
    local said = ns.Localize and ns.Localize(item.label) or item.label

    if item.kind == "header" then
        local header = Widgets.Header(parent)
        if header and header.text then Try(header.text, "SetText", said) end
        return header
    end

    if item.kind == "note" then
        local holder = Widgets.Frame("Frame", parent)
        if holder == nil then return nil end

        local text = Widgets.Hint(holder)
        if text then Try(text, "SetText", Window.Says(item.hint)) end
        holder.text = text

        --- Recompute the height from how many lines the text wrapped to.
        --
        -- A separate step rather than a one-off at build time. At build time
        -- there is no width — the layout supplies it through anchors — so a
        -- height computed then answers for a width of zero. Paragraphs
        -- overflowed their block border because of this.
        holder.umbraFit = function(self)
            if self.text == nil then return end

            -- The font string is given an explicit width, not only
            -- anchors. Two anchors do set a width, but the engine resolves
            -- it on its own schedule, and the height is needed immediately:
            -- until then the string reports a single line, so a
            -- three-line paragraph overlapped the next row.
            local wide = tonumber(Try(self, "GetWidth"))
            if wide ~= nil and wide > M.rail * 2 then
                Try(self.text, "SetWidth", wide - M.rail * 2)
            end

            local high = Widgets.Measure(self.text)
            Try(self, "SetHeight", math.max(high, M.row))
        end

        return holder
    end

    if item.kind == "toggle" then
        local box = Widgets.CheckBox(parent, said, function(on)
            Window.Store(page, item, on)
        end)
        if box then box:umbraSet(Window.Value(page, item) and true or false) end
        return box
    end

    if item.kind == "slider" then
        local slider = Widgets.Slider(parent, said, item.min, item.max,
            item.step, function(got)
                Window.Store(page, item, got)
            end)
        if slider then
            -- Show a mark instead of the minimum, if the row asked.
            if item.zero ~= nil then
                slider.umbraZero = ns.Localize and ns.Localize(item.zero)
                    or item.zero
            end
            slider:umbraSet(tonumber(Window.Value(page, item)) or item.min)
        end
        return slider
    end

    if item.kind == "select" then
        local drop = Widgets.Dropdown(parent, said, function(key)
            Window.Store(page, item, key)
        end)
        if drop then
            drop:umbraItems(Window.Choices(item))
            drop:umbraSet(Window.Value(page, item))
        end
        return drop
    end

    if item.kind == "text" then
        local box = Widgets.EditBox(parent, said, function(got)
            Window.Store(page, item, got)
        end)
        if box then box:umbraSet(Window.Value(page, item)) end
        return box
    end

    if item.kind == "action" then
        local holder = Widgets.Frame("Frame", parent)
        if holder == nil then return nil end
        Try(holder, "SetHeight", M.row)

        local button = Widgets.Button(holder, said, function()
            if type(item.run) == "function" then pcall(item.run) end
            applied(item)
        end)
        if button then
            Try(button, "ClearAllPoints")
            Try(button, "SetPoint", "LEFT", holder, "LEFT", M.rail, 0)
        end
        return holder
    end

    -- Colour: a swatch to click and a label beside it.
    --
    -- The addon has no colour picker of its own and needs none: the game's
    -- ColorPickerFrame is the one players use for every other colour in the
    -- interface.
    --
    -- The value is stored as r, g, b fields rather than an array, matching
    -- what the previous window wrote. Rewriting saved variables for the sake
    -- of the storage shape would discard colours players already chose.
    if item.kind == "color" then
        local holder = Widgets.Frame("Frame", parent)
        if holder == nil then return nil end
        Try(holder, "SetHeight", M.row)

        local label = Widgets.Text(holder, "text")
        if label then
            Try(label, "SetPoint", "LEFT", holder, "LEFT",
                M.field + M.gap, 0)
            Try(label, "SetText", said)
        end

        local swatch = Widgets.Button(holder, "", nil, M.field)
        if swatch ~= nil then
            Try(swatch, "ClearAllPoints")
            Try(swatch, "SetPoint", "LEFT", holder, "LEFT", 0, 0)
            Try(swatch, "SetHeight", M.field)
        end

        local ink = swatch and Try(swatch, "CreateTexture", nil, "OVERLAY")

        --- Paint the swatch with the stored colour.
        local function shown()
            local got = Window.Value(page, item)
            local r, g, b = 1, 1, 1
            if type(got) == "table" then
                r = tonumber(got.r) or 1
                g = tonumber(got.g) or 1
                b = tonumber(got.b) or 1
            end
            if type(ink) == "table" then
                Try(ink, "SetPoint", "TOPLEFT", swatch, "TOPLEFT", M.hair,
                    -M.hair)
                Try(ink, "SetPoint", "BOTTOMRIGHT", swatch, "BOTTOMRIGHT",
                    -M.hair, M.hair)
                Try(ink, "SetColorTexture", r, g, b, 1)
            end
            return r, g, b
        end

        shown()

        if swatch ~= nil then
            Try(swatch, "SetScript", "OnClick", function()
                local picker = _G.ColorPickerFrame
                if type(picker) ~= "table" then return end

                local r, g, b = shown()

                --- Store the picked colour and show it.
                local function took(chosen)
                    local nr, ng, nb = r, g, b
                    if type(chosen) == "table"
                        and type(chosen.GetColorRGB) == "function" then
                        nr, ng, nb = chosen:GetColorRGB()
                    elseif type(_G.ColorPickerFrame) == "table"
                        and type(_G.ColorPickerFrame.GetColorRGB)
                            == "function" then
                        nr, ng, nb = _G.ColorPickerFrame:GetColorRGB()
                    end
                    Window.Store(page, item, { r = nr, g = ng, b = nb })
                    shown()
                end

                -- Cancel restores the previous colour: someone pressing
                -- cancel asked for no change, not for white.
                local function back()
                    Window.Store(page, item, { r = r, g = g, b = b })
                    shown()
                end

                -- Newer clients take one descriptor table, older ones take
                -- fields. Chosen by what exists, not by build number.
                if type(picker.SetupColorPickerAndShow) == "function" then
                    pcall(picker.SetupColorPickerAndShow, picker, {
                        r = r, g = g, b = b,
                        swatchFunc = took,
                        cancelFunc = back,
                        opacity = false,
                    })
                    return
                end

                picker.func = took
                picker.swatchFunc = took
                picker.cancelFunc = back
                picker.opacityFunc = nil
                picker.hasOpacity = false
                picker.previousValues = { r = r, g = g, b = b }
                Try(picker, "SetColorRGB", r, g, b)
                Try(picker, "Hide")
                Try(picker, "Show")
            end)
        end

        holder.control = swatch
        return holder
    end

    -- A row of tabs inside a page.
    --
    -- A tab stores nothing: it says WHAT IS CURRENTLY SHOWN, which is window
    -- state rather than profile state. The chosen tab is not saved, and the
    -- first one is shown when the window opens again.
    --
    -- The tab contents are declared by whoever declared the row: the fonts
    -- module knows its categories, the window does not.
    if item.kind == "tabs" then
        local holder = Widgets.Frame("Frame", parent)
        if holder == nil then return nil end
        Try(holder, "SetHeight", M.row)

        local tabs = {}
        local chosen = nil

        --- Mark which tab is selected.
        local function mark()
            for key, button in pairs(tabs) do
                Widgets.Disable(button, key == chosen)
            end
        end

        local values = {}
        if type(item.values) == "function" then
            local ok, got = pcall(item.values)
            if ok and type(got) == "table" then values = got end
        end

        local offset = 0
        for i = 1, #values do
            local entry = values[i]
            local key = type(entry) == "table" and entry.key or nil
            local text = type(entry) == "table" and entry.text or nil

            if key ~= nil then
                local button = Widgets.Button(holder,
                    ns.Localize and ns.Localize(text or key) or text,
                    function()
                        chosen = key
                        mark()
                        if type(item.pick) == "function" then
                            pcall(item.pick, key)
                        end
                        Window.Repaint()
                    end)

                if button ~= nil then
                    Try(button, "ClearAllPoints")
                    Try(button, "SetPoint", "LEFT", holder, "LEFT", offset, 0)
                    offset = offset + M.header + M.rail
                    tabs[key] = button
                    if chosen == nil then chosen = key end
                end
            end
        end

        mark()
        holder.umbraTabs = tabs
        return holder
    end

    if item.kind == "widget" and type(item.build) == "function" then
        local ok, made = pcall(item.build, parent, page, item)
        if ok then return made end
    end

    return nil
end

--- A settings row, ready to show.
--
-- One thing happens on top of construction: a disabled row is greyed out.
-- That is done here rather than at construction because it is not permanent
-- — turning off "hide all buffs" must bring "only mine" back to life — so it
-- has to be asked on every repaint.
--
-- @param parent table
-- @param page table
-- @param item table
-- @return table|nil
function Window.Row(parent, page, item)
    if type(item) ~= "table" then return nil end

    local made = widgetFor(parent, page, item)
    if made == nil then return nil end

    -- What gets greyed out is what gets clicked. Headings and paragraphs
    -- have nothing clickable, and Widgets.Disable finds nothing on them.
    Widgets.Disable(made.control or made, Window.Dimmed(item))
    return made
end

Window.For = widgetFor

--============================================================================
-- Repaint: column and page
--============================================================================

-- === Why rows are built once rather than on every repaint ===
--
-- The engine cannot destroy a frame: one created lives until logout.
-- Rebuilding the page on every keystroke in the search box would create a
-- fresh set of rows per keystroke and leave the previous sets alive — a leak
-- that grows precisely while the player is searching.
--
-- So rows are built on the first visit to a page and afterwards only moved
-- and hidden. This is sound: the schema does not change after load, because
-- subsystems declare their pages while their files are read and none adds
-- rows later.
--
-- === What is NOT decided here ===
--
-- Nothing. Which pages survive is Filter, which group they belong to is
-- Layers, which one opens is Choose, which rows show is Rows, where each row
-- lands is Stack. All of those are pure and separately tested. This section
-- only displays, deliberately: a decision buried in drawing code has nowhere
-- to be tested.

-- Rows already built, keyed by page id.
local made = {}

-- Column buttons, keyed by page id.
local tabs = {}

local current = nil
local query = ""

--- Build a page's rows, once.
-- @param pageId string
-- @return table one frame per schema row
local function rowsOf(pageId)
    if made[pageId] ~= nil then return made[pageId] end

    local page = Schema.Of(pageId)
    local holder = frame and frame.scroll and frame.scroll.content
    if page == nil or holder == nil then return {} end

    local out = {}
    for i, item in ipairs(Window.Plan(pageId)) do
        -- Built on behalf of its OWN page: a nested page's row reads and
        -- writes through that page's section. The minimap button's store is
        -- different entirely — one per account — so built on behalf of the
        -- parent it would write to the profile.
        --
        -- Construction is fenced deliberately. A row that raised used to
        -- take the WHOLE page with it: the error escaped the loop and the
        -- player saw blank space where eighteen settings belonged. Now one
        -- row fails, the rest draw, and the failure is recorded by name.
        local row, why = nil, nil
        local fine, got = pcall(Window.Row, holder,
            Window.Owner(page, item), item)
        if fine then row = got else why = got end
        if why ~= nil then
            Window.broken = Window.broken or {}
            Window.broken[#Window.broken + 1] = tostring(pageId) .. "/"
                .. tostring(item.label or item.kind) .. ": " .. tostring(why)
        end
        if row ~= nil then
            Try(row, "SetPoint", "LEFT", holder, "LEFT", 0, 0)
            Try(row, "SetPoint", "RIGHT", holder, "RIGHT", 0, 0)
            Try(row, "Hide")
        end
        out[i] = row
    end

    made[pageId] = out
    return out
end

--- Where each block of settings starts and ends.
--
-- A block is a heading and everything under it up to the next heading. The
-- border around that grouping is what divides the page: without it thirty
-- consecutive rows read as one list in which headings are merely bolder
-- rows.
--
-- Rows before the first heading are not in a block: they concern the whole
-- page rather than a part of it, and a border would enclose the
-- introduction.
--
-- @param items table|nil rows AS CURRENTLY SHOWN
-- @return table array of { first, last }
function Window.Blocks(items)
    local out = {}
    if type(items) ~= "table" then return out end

    local open
    for i = 1, #items do
        local kind = type(items[i]) == "table" and items[i].kind or nil
        if kind == "header" then
            if open ~= nil and (i - 1) > open then
                out[#out + 1] = { first = open, last = i - 1 }
            end
            open = i
        end
    end

    -- The last heading is closed by the end of the page, but only if
    -- something follows it. A heading with no content gets no border.
    if open ~= nil and #items > open then
        out[#out + 1] = { first = open, last = #items }
    end

    return out
end

-- Pool of block borders. Not create-and-discard: the page's contents change
-- on every keystroke in the search box, and a frame cannot be destroyed,
-- only hidden.
local boxes = {}

--- The block border with this index.
-- @param index number
-- @return table|nil
local function blockOf(index)
    if boxes[index] ~= nil then return boxes[index] end

    local holder = frame and frame.scroll and frame.scroll.content
    if holder == nil then return nil end

    local box = Widgets.Frame("Frame", holder)
    if box == nil then return nil end

    -- The border sits BELOW the rows it encloses: a child frame defaults to
    -- a level above its parent, so a border created after the rows would
    -- cover them — a slider under glass cannot be dragged.
    local level = tonumber(Try(holder, "GetFrameLevel"))
    if level ~= nil then
        Try(box, "SetFrameLevel", math.max(0, level))
    end

    Widgets.Dress(box, "panel", "line")
    boxes[index] = box
    return box
end

--- A row's list of values, normalised to one shape.
--
-- It arrives in two shapes: an array of { key, text } pairs, and a map of
-- key -> label. The latter is what the AceConfig tree used to hand over, and
-- rewriting every page over it is pointless: normalising in one place is
-- cheaper than correcting twenty.
--
-- A map is sorted by label; an array is left as declared. An array's order is
-- deliberate — the game's own texture is listed first — while a map has no
-- order at all, and unsorted it would be "different sometimes".
--
-- @param item table|nil
-- @return table array of { key, text }
function Window.Choices(item)
    local values = type(item) == "table" and item.values or nil
    if type(values) == "function" then
        local ok, got = pcall(values)
        values = ok and got or nil
    end

    local out = {}
    if type(values) ~= "table" then return out end

    if values[1] ~= nil then
        for i = 1, #values do out[i] = values[i] end
        return out
    end

    for key, text in pairs(values) do
        out[#out + 1] = { key = key, text = text }
    end
    table.sort(out, function(a, b)
        return tostring(a.text) < tostring(b.text)
    end)
    return out
end

--- A row's words: translated, and computed where needed.
--
-- A hint may be COMPUTED rather than written. That is needed where it
-- describes not the setting but what is in effect right now: "font default,
-- size default +2, outline thin". Such a line changes under the player's
-- hand, and written once it would be a lie a second later.
--
-- The previous window showed these and the migration lost them. The author
-- asked three times why everything read zero: the zeroes were genuine — they
-- are offsets, and zero means "leave unchanged" — but a page without a single
-- real number says nothing about that.
--
-- @param said any string or a function returning one
-- @return string
function Window.Says(said)
    if type(said) == "function" then
        local ok, got = pcall(said)
        said = ok and got or ""
    end

    if type(said) ~= "string" then return "" end
    if type(ns.Localize) == "function" then return ns.Localize(said) end
    return said
end

--- Which rows share one line.
--
-- Consecutive buttons occupy a single line rather than one line each. Stacked
-- vertically they state the same thing separately: three presets are one
-- question with three answers, while three consecutive rows read as three
-- different questions.
--
-- ONLY buttons share a line, and only consecutive ones: a checkbox between
-- two buttons breaks the group, because it is about something else.
--
-- @param items table|nil rows as currently shown
-- @param most number|nil how many per line, three by default
-- @return table per row index: { of = line, at = position within it }
function Window.Ranks(items, most)
    local out = {}
    if type(items) ~= "table" then return out end

    local cap = tonumber(most)
    if cap == nil or cap < 1 then cap = 3 end

    local rank
    for i = 1, #items do
        local kind = type(items[i]) == "table" and items[i].kind or nil
        if kind == "action" then
            if rank == nil or #rank >= cap then rank = {} end
            rank[#rank + 1] = i
            out[i] = { of = rank, at = #rank }
        else
            rank = nil
        end
    end

    return out
end

--- Lay out the open page.
--
-- === The order of operations here is the only correct one ===
--
-- Anchor the row, THEN measure it, then move down. Anchoring left and right
-- is what gives the row its width, and until then a paragraph does not know
-- how many lines it wraps to. Measured earlier, we get the height for a width
-- of zero and the rows overlap.
local function paintPage()
    local holder = frame and frame.scroll and frame.scroll.content
    if holder == nil or current == nil then return end

    -- Rows of the PREVIOUS page are hidden first.
    --
    -- Rows are kept per page and outlive leaving it: the engine cannot
    -- destroy a frame, so once built they remain. Not hiding them leaves one
    -- page on top of another, which is exactly what was visible: the General
    -- labels over the unit frames.
    for pageId, built in pairs(made) do
        if pageId ~= current then
            for i = 1, #built do Try(built[i], "Hide") end
        end
    end

    local all = Window.Plan(current)
    local rows = rowsOf(current)

    -- What to show is asked of Rows rather than decided here.
    local keep = {}
    for _, item in ipairs(Window.Rows(current, query)) do keep[item] = true end

    local line = {}
    for i = 1, #all do
        local row = rows[i]
        if keep[all[i]] and row ~= nil then
            line[#line + 1] = { item = all[i], row = row }
        elseif row ~= nil then
            Try(row, "Hide")
        end
    end

    -- Blocks are computed from what is VISIBLE now rather than from what is
    -- declared: a heading left without content by the search must not get a
    -- border.
    local shape = {}
    for i = 1, #line do shape[i] = line[i].item end
    local blocks = Window.Blocks(shape)

    local opens, closes, inside = {}, {}, {}
    for b = 1, #blocks do
        opens[blocks[b].first] = b
        closes[blocks[b].last] = b
        for i = blocks[b].first, blocks[b].last do inside[i] = b end
    end

    -- Consecutive buttons share a LINE rather than stacking.
    --
    -- Stacked they take one line each while stating the same thing: three
    -- presets are one question with three answers, and three consecutive rows
    -- read as three different questions. They are equal in width for the same
    -- reason: unequal widths among equivalent answers hint that one of them is
    -- the main one.
    local shape2 = {}
    for i = 1, #line do shape2[i] = line[i].item end
    local ranks = Window.Ranks(shape2, PER_ROW)
    for i = 1, #line do
        line[i].rank = ranks[i] and ranks[i].of or nil
        line[i].place = ranks[i] and ranks[i].at or nil
    end

    local at = 0
    local tops = {}

    for i = 1, #line do
        local row = line[i].row

        if opens[i] then
            at = at + M.gap
            tops[opens[i]] = at
            at = at + M.rail
        end

        -- Block content is inset from its edges, or the border cuts into
        -- the labels.
        local pad = inside[i] and M.inset or 0

        Try(row, "ClearAllPoints")

        local rank = line[i].rank
        if rank ~= nil and #rank > 1 then
            -- Share of the width per button, gaps included. Computed from
            -- the number of buttons IN THIS line rather than from PER_ROW:
            -- the last line may be short, and a lone button stretched to a
            -- third of the width looks cropped.
            local wide = tonumber(Try(holder, "GetWidth")) or 0
            local room = wide - pad * 2 - M.gap * (#rank - 1)
            local each = room / #rank
            local shift = pad + (line[i].place - 1) * (each + M.gap)

            Try(row, "SetPoint", "TOPLEFT", holder, "TOPLEFT", shift, -at)
            Try(row, "SetWidth", each > 1 and each or 1)
        else
            Try(row, "SetPoint", "TOPLEFT", holder, "TOPLEFT", pad, -at)
            Try(row, "SetPoint", "TOPRIGHT", holder, "TOPRIGHT", -pad, -at)
        end

        -- The disabled state is asked here rather than at construction:
        -- turning off "hide all buffs" must bring "only mine" back to
        -- life.
        Widgets.Disable(row.control or row, Window.Dimmed(line[i].item))
        Try(row, "Show")

        -- The refit belongs HERE, between anchoring and measuring, and that
        -- order is the only correct one. Anchoring left and right has just
        -- given the row its width; until then a paragraph does not know how
        -- many lines it wraps to, and a height computed earlier answers for a
        -- width of zero.
        if type(row.umbraFit) == "function" then
            pcall(row.umbraFit, row)
        end

        -- Height is added ONCE per line: buttons sharing a line occupy one
        -- line, not three.
        local last = line[i].rank == nil
            or line[i].place == #line[i].rank
        if last then
            at = at + Window.Height(line[i].item, row)
        end

        if closes[i] then
            at = at + M.rail
            local box = blockOf(closes[i])
            if box ~= nil then
                Try(box, "ClearAllPoints")
                Try(box, "SetPoint", "TOPLEFT", holder, "TOPLEFT", 0,
                    -tops[closes[i]])
                Try(box, "SetPoint", "TOPRIGHT", holder, "TOPRIGHT", 0,
                    -tops[closes[i]])
                Try(box, "SetHeight", at - tops[closes[i]])
                Try(box, "Show")
            end
        end
    end

    -- Borders this page did not need are hidden: the pool is shared by the
    -- whole window, and one left over from the previous page hangs empty.
    for b = #blocks + 1, #boxes do Try(boxes[b], "Hide") end

    if frame.scroll and type(frame.scroll.umbraExtend) == "function" then
        frame.scroll:umbraExtend(at)
    end
end

--- The column entry for this page.
--
-- A list row, not a bordered button: a border around each of twelve rows
-- turns the column into twelve separate objects to choose between, whereas
-- this is a list to walk down.
--
-- @param page table
-- @return table|nil
local function tabFor(page)
    if tabs[page.id] ~= nil then return tabs[page.id] end

    local column = frame and frame.column
    if column == nil then return nil end

    local button = Widgets.Frame("Button", column)
    if button == nil then return nil end

    Try(button, "SetHeight", M.row)

    local label = Widgets.Text(button, "textDim")
    if label then
        Try(label, "ClearAllPoints")
        Try(label, "SetPoint", "LEFT", button, "LEFT", M.gap, 0)
        Try(label, "SetJustifyH", "LEFT")
        Try(label, "SetText", ns.Localize and ns.Localize(page.title)
            or page.title)
    end
    button.label = label

    -- Marker for the open page: a bar at the left edge.
    --
    -- Not the label's colour. Colour reads poorly here: across twelve rows a
    -- half-tone difference has to be hunted for by comparing rows pairwise,
    -- which is exactly the work a list is supposed to remove. A difference in
    -- SHAPE is seen at once and works for a player who cannot tell the colours
    -- apart.
    local mark = Try(button, "CreateTexture", nil, "ARTWORK")
    if type(mark) == "table" then
        Try(mark, "SetPoint", "LEFT", button, "LEFT", 0, 0)
        Try(mark, "SetSize", M.edge, M.row - M.gap)
        Try(mark, "SetColorTexture", Skin.Get("lilac"))
        Try(mark, "Hide")
    end
    button.mark = mark

    -- A row lightens under the mouse and while open; at rest it has no
    -- background of its own — the column provides it.
    Try(button, "SetScript", "OnEnter", function(self)
        if current ~= page.id then Widgets.Dress(self, "line", nil) end
    end)
    Try(button, "SetScript", "OnLeave", function(self)
        if current ~= page.id then Widgets.Bare(self) end
    end)
    Try(button, "SetScript", "OnClick", function()
        current = page.id
        Window.Repaint()
    end)

    tabs[page.id] = button
    return button
end

--- Lay out the page column.
local function paintColumn()
    local column = frame and frame.column
    if column == nil then return end

    local main, aside = Window.Layers(Window.Filter(Schema.Pages(), query))

    -- The open page is chosen from what the COLUMN shows rather than from
    -- everything the filter kept. The filter also returns nested pages — the
    -- word may have matched inside one — but a nested page cannot be opened:
    -- its rows live on the parent page and it has no column entry.
    local shown = {}
    for i = 1, #main do shown[#shown + 1] = main[i] end
    for i = 1, #aside do shown[#shown + 1] = aside[i] end
    current = Window.Choose(shown, current)

    for _, button in pairs(tabs) do Try(button, "Hide") end

    --- Place a list consecutively from one edge.
    -- @param list table
    -- @param anchor string TOP or BOTTOM
    -- @param sign number downward (-1) or upward (1)
    local function layer(list, anchor, sign)
        local offset = 0
        for i = 1, #list do
            local page = list[i]
            local button = tabFor(page)

            if button ~= nil then
                Try(button, "ClearAllPoints")
                Try(button, "SetPoint", anchor .. "LEFT", column,
                    anchor .. "LEFT", 0, sign * offset)
                Try(button, "SetPoint", anchor .. "RIGHT", column,
                    anchor .. "RIGHT", 0, sign * offset)

                local open = current == page.id
                if open then Widgets.Dress(button, "panel", nil)
                else Widgets.Bare(button) end
                Skin.Text(button.label, open and "text" or "textDim")
                if button.mark then
                    if open then Try(button.mark, "Show")
                    else Try(button.mark, "Hide") end
                end

                Try(button, "Show")
                offset = offset + M.row
            end
        end
    end

    -- One list, not two. Profiles come last — they are about the addon
    -- rather than the game, and the final position says so by itself. Pinned
    -- to the bottom of the column they were separated from the list by a
    -- strip of emptiness, and the list read as two pieces.
    local all = {}
    for i = 1, #main do all[#all + 1] = main[i] end
    for i = 1, #aside do all[#all + 1] = aside[i] end
    layer(all, "TOP", -1)
end


--- Repaint the window for the current query and open page.
function Window.Repaint()
    if frame == nil then return end
    paintColumn()
    paintPage()

    -- The shadow is stripped again on every repaint: the fonts subsystem
    -- reapplies its font to the strings, and that brings the shadow back.
    -- Stripped once at build time, it reappeared.
    if type(Widgets.Unshadow) == "function" then Widgets.Unshadow() end
end

--- Set the search text.
-- @param said any
function Window.Seek(said)
    query = type(said) == "string" and said or ""
    Window.Repaint()
end

--- Which page is open. For tests and debugging.
-- @return string|nil
function Window.Open()
    return current
end
