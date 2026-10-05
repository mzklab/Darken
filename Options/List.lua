local ADDON, ns = ...

-- List editor: one for every list in the window.
--
-- === What this is, and why there is only one ===
--
-- The addon has four lists and they differ: aura rules, nameplate rules,
-- info-panel cells. All they share is this much — an ordered list of named
-- entries, edited through five actions: add, remove, earlier, later, select
-- for editing.
--
-- Written three times it would diverge three ways: in one place "remove"
-- would leave the neighbour selected, in another it would reset the selection
-- to the top, in a third it would leave the removed entry on screen. Someone
-- who has learned to add an aura rule does not learn it a second time — and
-- that is not convenience, it is the same reasoning that put aura filtering
-- into one file.
--
-- === What is NOT here ===
--
-- The list arithmetic. It is already written and tested by the rules
-- themselves: List, Find, Add, Move, Remove, Rename — keyed by name, not by
-- index. Repeating it here would establish a second ordering that diverges
-- from the first at the next edit.
--
-- So the editor takes a list not as a table but through an ADAPTER: functions
-- it calls, and no assumption about what is inside an entry. Only whoever
-- declared the entry knows what fields it has.
--
-- === What IS here, and why it is tested ===
--
-- One question: who stays selected after an edit. The answer fails silently
-- and painfully — a selection pointing at a removed entry shows the fields of
-- something that no longer exists, and the first edit in them recreates it.
--
-- === Why the editor has no name field of its own ===
--
-- It used to: the editor asked for a name and passed it to Add. The first
-- real list disproved that — aura rules are not created from a name alone,
-- they need spells too, and the New button would never have worked.
--
-- It is not about one field. The name is a field of the entry like any other,
-- and only whoever declared the list knows what fields an entry has. So the
-- editor asks for nothing: it shows the fields of the SELECTED entry, and
-- when nothing is selected, the fields of the draft — the entry being typed.
-- Add then means "create from the draft", and the draft is held by the
-- declaring side too.

local List = {}
ns.ListEditor = List

--============================================================================
-- Pure decisions
--============================================================================

--- Entry names in their order.
--
-- The order IS the precedence: the list is read top to bottom and what stands
-- earlier wins. It is therefore never sorted by anything.
--
-- @param entries table|nil array of entries
-- @return table array of names
function List.Names(entries)
    local out = {}
    if type(entries) ~= "table" then return out end

    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" and type(entry.name) == "string"
            and entry.name ~= "" then
            out[#out + 1] = entry.name
        end
    end
    return out
end

--- An entry's label in the dropdown.
--
-- The number in the label is the precedence said out loud. Without it the
-- order is visible only as one line being above another, and "above" means
-- nothing in a dropdown: nobody knows the list is read top to bottom until
-- they are told.
--
-- @param name any
-- @param index any
-- @return string
function List.Numbered(name, index)
    local said = type(name) == "string" and name or ""
    local number = tonumber(index)
    if number == nil then return said end
    return string.format("%d. %s", number, said)
end

--- Who stays selected when the list has changed.
--
-- What was selected stays selected as long as it exists. That is the main
-- rule: someone moves a rule with the "earlier" button, and a selection that
-- jumps means the next press moves a different rule.
--
-- A vanished selection is replaced by the first entry rather than by nothing:
-- an empty editor over a non-empty list looks broken.
--
-- @param names table|nil names as they are now
-- @param chosen any who was selected
-- @return string|nil
function List.Keep(names, chosen)
    if type(names) ~= "table" or #names == 0 then return nil end

    if type(chosen) == "string" then
        for i = 1, #names do
            if names[i] == chosen then return chosen end
        end
    end

    return names[1]
end

--- Who to select after this entry was removed.
--
-- The neighbour BELOW, not above and not the first. The reason is how removal
-- happens: the list is cleaned top to bottom with several presses of
-- "forget". A selection that slides downward puts the next entry under the
-- next press — which is what was wanted. A selection that jumps to the top
-- forces re-aiming after every press.
--
-- The last entry has no neighbour below, so the one above is taken: otherwise
-- removing the last entry would empty the editor over a non-empty list.
--
-- @param before table|nil names BEFORE the removal
-- @param gone any who was removed
-- @return string|nil
function List.Next(before, gone)
    if type(before) ~= "table" then return nil end

    local at
    for i = 1, #before do
        if before[i] == gone then at = i break end
    end
    if at == nil then return List.Keep(before, nil) end

    if before[at + 1] ~= nil then return before[at + 1] end
    if before[at - 1] ~= nil then return before[at - 1] end
    return nil
end

--- Whether this entry can move in this direction.
--
-- Asked in order to grey out the button, not in order to forbid the move: the
-- list itself forbids it. A greyed-out "earlier" button on the topmost entry
-- answers the question "why does nothing happen"; a live one answers nothing.
--
-- @param names table|nil
-- @param chosen any
-- @param delta any 1 or -1
-- @return boolean
function List.CanMove(names, chosen, delta)
    if type(names) ~= "table" then return false end

    local step = tonumber(delta)
    if step ~= 1 and step ~= -1 then return false end

    for i = 1, #names do
        if names[i] == chosen then
            local target = i + step
            return target >= 1 and target <= #names
        end
    end
    return false
end

--- Whether the adapter is usable.
--
-- A list missing a required function is a list with one action silently
-- broken: the button presses and nothing happens. That has to be reported to
-- whoever declared the list, and reported at build time rather than at the
-- press.
--
-- @param hook any the adapter
-- @return boolean, string|nil what is missing
function List.Ready(hook)
    if type(hook) ~= "table" then return false, "no hook" end

    -- Two are mandatory: list the entries, and supply the selected entry's
    -- fields. Without the first there is nothing to show, without the second
    -- nothing to edit, and either one makes the editor pointless.
    for _, name in ipairs({ "Entries", "Fields" }) do
        if type(hook[name]) ~= "function" then return false, name end
    end

    -- The other three are by capability, and no button is created for what
    -- a list cannot do. The lists themselves taught this, one at a time:
    --
    --   aura and nameplate rules can do everything — the player adds,
    --       removes and reorders them;
    --   panel cells come from the standard registry: addons publish them, so
    --       they cannot be added or removed, only reordered;
    --   nameplate parts are a fixed set: neither added, removed nor
    --       reordered, only edited.
    --
    -- Demanding empty stubs would create a button that presses and does
    -- nothing — precisely the failure a player mistakes for their own
    -- mistake.
    return true, nil
end

--============================================================================
-- Drawing
--============================================================================

local Widgets = ns.Widgets
local Skin = ns.Skin
local Try = Widgets and Widgets.Try or function() end
local M = Skin and Skin.Metrics or {}

--- Translate, if translation is available yet.
-- @param said any
-- @return any
local function say(said)
    if type(ns.Localize) == "function" then return ns.Localize(said) end
    return said
end

--- Build a list editor.
--
-- Called as a builder of kind "widget": the window knows nothing about the
-- list beyond the fact that the row can draw itself. The opening is narrow on
-- purpose — a list entry is not a setting but a record with its own fields,
-- and asking about it through three settings asks three questions about one
-- thing.
--
-- @param parent table frame to draw into
-- @param page table the page, needed by the entry's fields
-- @param item table schema row; item.hook is the adapter to the list
-- @return table|nil
function List.Build(parent, page, item)
    if type(Widgets) ~= "table" then return nil end
    if type(item) ~= "table" then return nil end

    -- An incomplete adapter is the declaring side's mistake, and it is
    -- reported elsewhere: Schema.Validate complains about it, and cold boot
    -- runs that on every client version. Printing it for the player is
    -- pointless — there is nothing they can do — but silently drawing half an
    -- editor is not an option either: a button would press and do nothing.
    local hook = item.hook
    if not List.Ready(hook) then return nil end

    local holder = Widgets.Frame("Frame", parent)
    if holder == nil then return nil end

    -- The selection is window state, not profile state: it is not a choice
    -- that must survive logout but where the player currently stands.
    local chosen = nil

    local parts = {}
    local redraw

    --- Height of one row, asked of the window.
    -- @param row table|nil schema row; the editor's own parts have none
    -- @param made table|nil the constructed frame
    -- @return number
    local function height(row, made)
        if ns.Window ~= nil then return ns.Window.Height(row, made) end
        return M.row
    end

    --- Entry names as they are right now.
    local function names()
        local ok, entries = pcall(hook.Entries)
        if not ok then return {} end
        return List.Names(entries)
    end

    --- Dropdown of entries, numbered in the label.
    local pick = Widgets.Dropdown(holder, say(item.label or "Entry"),
        function(value)
            chosen = value
            redraw()
        end)
    parts[#parts + 1] = pick

    -- "New" means "create from the draft": the draft's fields are shown
    -- below when nothing is selected, and the declaring side holds them.
    --
    -- What was created becomes selected: the entry was created in order to be
    -- filled in, and an extra press between those two intentions expresses
    -- nothing. Add knows the created entry's name and returns it.
    local add
    if type(hook.Add) == "function" then
        add = Widgets.Button(holder, say("New"), function()
            local ok, name = pcall(hook.Add)
            if not ok then return end
            chosen = List.Keep(names(), name)
            redraw()
        end)
        parts[#parts + 1] = add
    end

    local up, down
    if type(hook.Move) == "function" then
        up = Widgets.Button(holder, say("Try Earlier"), function()
            if pcall(hook.Move, chosen, -1) then redraw() end
        end)
        parts[#parts + 1] = up

        down = Widgets.Button(holder, say("Try Later"), function()
            if pcall(hook.Move, chosen, 1) then redraw() end
        end)
        parts[#parts + 1] = down
    end

    local drop
    if type(hook.Remove) == "function" then
        drop = Widgets.Button(holder, say("Forget"), function()
            local before = names()
            local gone = chosen
            if pcall(hook.Remove, gone) then
                chosen = List.Next(before, gone)
                redraw()
            end
        end)
        parts[#parts + 1] = drop
    end

    -- The selected entry's fields are built by whoever declared the list:
    -- only they know what fields an entry has. The editor merely gives them
    -- room.
    local fields = {}
    local rowItems = {}

    --- Repaint the editor for the current list and selection.
    redraw = function()
        local list = names()
        chosen = List.Keep(list, chosen)

        -- Numbered labels: the number is the precedence said out loud.
        local values = {}
        for i = 1, #list do
            values[i] = { key = list[i], text = List.Numbered(list[i], i) }
        end
        if pick ~= nil then
            Try(pick, "umbraItems", values)
            Try(pick, "umbraSet", chosen)
        end

        -- The move buttons grey out where there is nowhere to move: a
        -- greyed-out button answers "why does nothing happen", a live one
        -- answers nothing.
        if up ~= nil then
            Widgets.Disable(up, not List.CanMove(list, chosen, -1))
        end
        if down ~= nil then
            Widgets.Disable(down, not List.CanMove(list, chosen, 1))
        end
        if drop ~= nil then Widgets.Disable(drop, chosen == nil) end

        -- The previous entry's fields are removed before the new ones are
        -- placed: leaving them shows one entry's fields under another's
        -- name.
        for i = 1, #fields do Try(fields[i], "Hide") end
        fields = {}

        -- Fields of the SELECTED entry, or of the draft when nothing is
        -- selected: blank space under an empty list does not tell anyone that
        -- an entry can be created at all.
        rowItems = {}
        if type(hook.Fields) == "function" then
            local ok, rows = pcall(hook.Fields, chosen)
            if ok and type(rows) == "table" then
                for i = 1, #rows do
                    local row = ns.Window and ns.Window.Row
                        and ns.Window.Row(holder, page, rows[i]) or nil
                    if row ~= nil then
                        fields[#fields + 1] = row
                        -- The schema row is kept alongside the frame:
                        -- height is taken from the row's kind, and without it
                        -- a field would be measured at the ordinary height,
                        -- while a dropdown or edit box is twice as tall.
                        rowItems[#fields] = rows[i]
                    end
                end
            end
        end

        -- Layout is the same one the page uses: a second, local copy would
        -- diverge from it at the first change to the spacing.
        local stackable, sizes = {}, {}
        for i = 1, #parts do
            stackable[#stackable + 1] = { kind = "widget" }
            sizes[#stackable] = height({ kind = "widget" },
                parts[i])
        end
        for i = 1, #fields do
            stackable[#stackable + 1] = { kind = "widget" }
            sizes[#stackable] = height(rowItems[i], fields[i])
        end

        local all = {}
        for i = 1, #parts do all[#all + 1] = parts[i] end
        for i = 1, #fields do all[#all + 1] = fields[i] end

        local at, total = {}, 0
        if ns.Window ~= nil then
            at, total = ns.Window.Stack(stackable, sizes)
        end
        for i = 1, #all do
            Try(all[i], "ClearAllPoints")
            Try(all[i], "SetPoint", "TOPLEFT", holder, "TOPLEFT", 0,
                at[i] or 0)
            Try(all[i], "SetPoint", "TOPRIGHT", holder, "TOPRIGHT", 0,
                at[i] or 0)
            Try(all[i], "Show")
        end

        -- The editor must report its own height: the page lays out rows by
        -- it, and a wrong height puts the next setting on top of the entry's
        -- last field.
        Try(holder, "SetHeight", math.max(tonumber(total) or 0, M.row))
    end

    holder.umbraRedraw = redraw
    redraw()
    return holder
end
