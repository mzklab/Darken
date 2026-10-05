local ADDON, ns = ...

-- Settings declared as data.
--
-- === Why this replaced the AceConfig tree ===
--
-- An AceConfig tree is a table of get/set closures, one pair per field. That
-- shape cannot be checked: a typo in a field name produces a slider that
-- moves and changes nothing, discoverable only by dragging it in the game
-- and looking for an effect.
--
-- Data can be walked. Schema.Validate catches in one pass what otherwise
-- surfaces one defect at a time over months:
--
--   * a mistyped profile field, so the path leads nowhere;
--   * a label written past the translation layer, so the window shows
--     English inside a translated client;
--   * nothing applying the change, so it takes effect only after a reload;
--   * slider bounds that are unusable, an empty value list, an unknown kind.
--
-- None of these raise an error, and none are visible to behaviour tests.
--
-- === What is not here ===
--
-- Drawing. The schema knows nothing of frames or widgets: it states WHAT is
-- configurable and where the value lives. How it looks belongs to the
-- window.

local Schema = {}
ns.Schema = Schema

--============================================================================
-- Vocabulary
--============================================================================

-- Row kinds.
local KINDS = {
    toggle = true,   -- checkbox
    slider = true,   -- slider with a number box
    select = true,   -- dropdown
    text   = true,   -- edit box
    color  = true,   -- colour swatch

    -- A button that does something. It has no profile field: "restore the
    -- game's fonts" and "apply this look" store nothing.
    action = true,

    -- A section heading: label and rule. It says how to read the page, not
    -- what to change on it, so it stores nothing.
    header = true,

    -- An explanatory paragraph. Needed where the labels alone do not explain
    -- the page; an explanation of a SINGLE setting belongs in its hint.
    note = true,

    -- A row of tabs within a page. Stores nothing, like a heading.
    tabs = true,

    -- A row that builds itself. Used where a widget is not enough: the aura
    -- rule editor, the info panel cell list. The opening is deliberately
    -- narrow — the window still does not know what is inside and treats the
    -- row like any other.
    widget = true,
}
Schema.KINDS = KINDS

-- Kinds that store no value.
local STORES_NOT = {
    action = true, header = true, note = true, tabs = true, widget = true,
}

--- Whether this kind stores a value in the profile.
-- @param kind any
-- @return boolean
function Schema.Stores(kind)
    if not KINDS[kind] then return false end
    return not STORES_NOT[kind]
end

local pages = {}
local items = {}

--============================================================================
-- Declaration
--============================================================================

--- Declare a settings page.
--
-- Order comes from a number, not from declaration order: files load in TOC
-- order, and tying the window's layout to that would reshuffle the window
-- whenever a TOC line moves.
--
-- `section` is the subsystem whose profile section holds the page's values.
-- Paths are relative to it: section = "darkness" with path = { "amount" }
-- means profile.darkness.amount. This is the core's storage layout; the
-- schema does not change it.
--
-- `store` selects the storage: "profile" (default) is per profile, "global"
-- is one per account. The second is for things unrelated to gameplay — the
-- minimap button has one position however many profiles exist.
--
-- `aside` puts the page in the column's second group: pages about the addon
-- itself rather than the game (profiles). Drawn less prominently.
--
-- @param id string
-- @param info table|nil { title, order, section, store, aside, parent }
-- @return boolean whether it was declared
function Schema.Page(id, info)
    if type(id) ~= "string" or id == "" then return false end
    if pages[id] then return false end

    info = type(info) == "table" and info or {}

    pages[id] = {
        id      = id,
        title   = info.title or id,
        order   = tonumber(info.order) or 100,
        section = info.section,
        store   = info.store == "global" and "global" or "profile",
        aside   = info.aside and true or false,
        parent  = info.parent,
    }
    items[id] = {}
    return true
end

--- Add a row to a page.
-- @param pageId string
-- @param item table
-- @return boolean
function Schema.Add(pageId, item)
    if type(item) ~= "table" then return false end
    if type(pageId) ~= "string" or items[pageId] == nil then return false end

    local list = items[pageId]
    list[#list + 1] = item

    -- Mark the page as holding a row that can hide itself. Recorded at
    -- declaration rather than discovered on each repaint: there are only a
    -- handful of conditional rows in the addon, and the window would ask
    -- this question on every keystroke in the search box.
    if item.hidden ~= nil then
        local page = pages[pageId]
        if page ~= nil then page.conditional = true end
    end

    return true
end

--- Whether the page holds a row that can hide itself.
-- @param pageId any
-- @return boolean
function Schema.Conditional(pageId)
    if type(pageId) ~= "string" then return false end
    local page = pages[pageId]
    return (page ~= nil and page.conditional) and true or false
end

--- Pages ordered by their number, then by id.
--
-- The tie-break by id keeps the order stable across sessions: two pages with
-- the same number must not swap places, or the column differs run to run.
-- @return table array of pages
function Schema.Pages()
    local out = {}
    for _, page in pairs(pages) do out[#out + 1] = page end

    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return out
end

--- Pages nested inside this one.
--
-- Ordered like any other pages. This matters: the font category pages are
-- numbered consecutively (4.01, 4.02 and so on), and their order within the
-- parent page must match.
--
-- @param pageId any
-- @return table array of pages
function Schema.Children(pageId)
    local out = {}
    if type(pageId) ~= "string" then return out end

    for _, page in ipairs(Schema.Pages()) do
        if page.parent == pageId then out[#out + 1] = page end
    end
    return out
end

--- A page by id.
-- @param id any
-- @return table|nil
function Schema.Of(id)
    if type(id) ~= "string" then return nil end
    return pages[id]
end

--- A page's rows, in declaration order.
-- @param pageId any
-- @return table
function Schema.Items(pageId)
    if type(pageId) ~= "string" then return {} end
    return items[pageId] or {}
end

-- Declaration generation. Incremented by Schema.Forget so that anything
-- which CACHED a derivation of the schema can tell its cache is stale. A
-- cache cleared by an explicit call is eventually forgotten, and then it
-- serves pages from a previous schema without saying so.
local era = 1

--- The current generation.
-- @return number
function Schema.Era()
    return era
end

--- Discard everything declared. For tests only.
function Schema.Forget()
    pages, items = {}, {}
    era = era + 1
end

--============================================================================
-- Reading and writing
--============================================================================

--- The profile section a page's paths are relative to.
-- @param page table|nil
-- @return table|nil
function Schema.Ground(page)
    if type(page) ~= "table" then return nil end

    local addon = ns.Addon
    if type(addon) ~= "table" or type(addon.db) ~= "table" then return nil end

    local where = addon.db[page.store or "profile"]
    if type(where) ~= "table" then return nil end

    if page.section == nil then return where end
    local part = where[page.section]
    return type(part) == "table" and part or nil
end

--- Read a value at a path.
-- @param where table|nil
-- @param path table|nil array of keys
-- @return any
function Schema.Read(where, path)
    if type(where) ~= "table" or type(path) ~= "table" then return nil end

    local at = where
    for i = 1, #path do
        if type(at) ~= "table" then return nil end
        at = at[path[i]]
    end
    return at
end

--- Write a value at a path.
--
-- Nothing is created: neither intermediate tables nor the leaf. A path that
-- does not exist is a typo, and creating it silently would hide that typo
-- for good — the setting would write, read back and affect nothing.
--
-- The LEAF is checked too, not only the intermediate steps. The guard
-- originally covered intermediates only, so a single-step path let typos
-- through; the project's own test caught it.
--
-- A missing field here really means missing: AceDB answers reads with the
-- defaults, so any field declared in defaults reads non-nil before the first
-- write. Only undeclared fields read nil.
--
-- @param where table|nil
-- @param path table|nil
-- @param value any
-- @return boolean whether it wrote
function Schema.Write(where, path, value)
    if type(where) ~= "table" or type(path) ~= "table" or #path == 0 then
        return false
    end

    local at = where
    for i = 1, #path - 1 do
        at = at[path[i]]
        if type(at) ~= "table" then return false end
    end

    local leaf = path[#path]
    if at[leaf] == nil then return false end

    at[leaf] = value
    return true
end

--============================================================================
-- Validation
--============================================================================

--- Whether a path reaches a field in the defaults.
-- @param ground table|nil
-- @param path table|nil
-- @return boolean, any the key it stopped at
local function reaches(ground, path)
    if type(path) ~= "table" or #path == 0 then return false, "(empty)" end
    if type(ground) ~= "table" then return true, nil end

    local at = ground
    for i = 1, #path do
        if type(at) ~= "table" then return false, path[i] end
        if at[path[i]] == nil then return false, path[i] end
        at = at[path[i]]
    end
    return true, nil
end

--- The defaults a page's paths are checked against.
-- @param page table
-- @return table|nil
local function defaultsOf(page)
    local addon = ns.Addon
    if type(addon) ~= "table" or type(addon.defaults) ~= "table" then
        return nil
    end

    local where = addon.defaults[page.store or "profile"]
    if type(where) ~= "table" then return nil end

    if page.section == nil then return where end
    local part = where[page.section]
    return type(part) == "table" and part or nil
end

--- Validate everything declared.
--
-- Returns a list of complaints rather than raising: the window must open
-- even with complaints, or one typo in one setting costs the player the
-- whole addon. The complaints are printed to chat once at load.
--
-- @return table array of strings; empty means no problems
function Schema.Validate()
    local out = {}
    local function complain(text) out[#out + 1] = text end

    for _, page in ipairs(Schema.Pages()) do
        if type(page.title) ~= "string" or page.title == "" then
            complain("page " .. tostring(page.id) .. ": no title")
        end

        local ground = defaultsOf(page)
        if page.section ~= nil and ground == nil then
            complain("page " .. tostring(page.id)
                .. ": no defaults section '" .. tostring(page.section) .. "'")
        end

        for _, item in ipairs(Schema.Items(page.id)) do
            local where = tostring(page.id) .. "/"
                .. tostring(item.label
                    or (type(item.path) == "table" and item.path[#item.path])
                    or "?")

            if not KINDS[item.kind] then
                complain(where .. ": unknown kind '"
                    .. tostring(item.kind) .. "'")
            end

            -- A label is a translation key, so it is an English string.
            -- Kinds that have no label are not asked for one.
            if item.kind ~= "note" and item.kind ~= "widget" then
                if type(item.label) ~= "string" or item.label == "" then
                    complain(where .. ": no label")
                end
            end

            -- A list row must supply a complete hook. Missing an action
            -- leaves a button in the editor that clicks and does nothing,
            -- which players read as a mistake of their own.
            if item.kind == "widget" and item.hook ~= nil then
                local fine, gone = true, nil
                if type(ns.ListEditor) == "table"
                    and type(ns.ListEditor.Ready) == "function" then
                    fine, gone = ns.ListEditor.Ready(item.hook)
                end
                if not fine then
                    complain(where .. ": list hook has no '"
                        .. tostring(gone) .. "'")
                end
            end

            if Schema.Stores(item.kind) then
                -- Custom get/set is legitimate where the value is derived
                -- from the profile rather than stored in it. Both must be
                -- present: one without the other gives a setting that either
                -- shows without writing or writes without showing.
                -- A custom getter must RETURN. One that raises is
                -- swallowed by the window's pcall and looks like an empty
                -- setting: a slider at zero, a dropdown with no row. The
                -- dimming page did exactly that — its getters called
                -- Darkness:GetSettings(), which core subsystems do not have,
                -- leaving eleven dropdowns blank.
                if type(item.get) == "function" then
                    local fine = pcall(item.get)
                    if not fine then
                        complain(where .. ": its getter errors")
                    end
                end

                if item.get or item.set then
                    if type(item.get) ~= "function" then
                        complain(where .. ": has a setter but no getter")
                    end
                    if type(item.set) ~= "function" then
                        complain(where .. ": has a getter but no setter")
                    end
                end

                -- The path is checked whenever it exists, including
                -- alongside a custom getter. It used to be skipped in that
                -- case, so a path pointing into another section said
                -- nothing: the bag border checkbox had a path into the
                -- dimming section while its setter wrote to the bags
                -- section. The window was unaffected, since it uses the
                -- getter, but anyone reading the file believed the path.
                if item.path ~= nil then
                    local ok, broke = reaches(ground, item.path)
                    if not ok then
                        complain(where .. ": defaults have no field '"
                            .. tostring(broke) .. "'")
                    end
                end

                -- Neither a path nor a getter: a setting that stores
                -- nothing although its kind must store something.
                if item.path == nil and item.get == nil
                    and item.set == nil then
                    complain(where .. ": stores nothing")
                end
            end

            if item.kind == "slider" then
                local low, high = tonumber(item.min), tonumber(item.max)
                if not low or not high or low >= high then
                    complain(where .. ": slider bounds are no good ("
                        .. tostring(item.min) .. ".."
                        .. tostring(item.max) .. ")")
                end
                if item.step ~= nil and not tonumber(item.step) then
                    complain(where .. ": slider step is not a number")
                end
            end

            if item.kind == "select" then
                if type(item.values) ~= "function"
                    and type(item.values) ~= "table" then
                    complain(where .. ": select has no values")
                end
            end

            if item.kind == "action" and type(item.run) ~= "function" then
                complain(where .. ": action has nothing to run")
            end

            -- Apply target. "none" is a choice and is written out: a row
            -- with no apply field is indistinguishable from one where it was
            -- forgotten, and that one only takes effect after a reload.
            if Schema.Stores(item.kind) or item.kind == "action" then
                if item.apply == nil then
                    complain(where .. ": does not say what to apply")
                elseif item.apply ~= "none"
                    and type(item.apply) ~= "string" then
                    complain(where .. ": apply is not a subsystem name")
                end
            end
        end
    end

    return out
end
