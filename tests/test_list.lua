local helpers = require("helpers")

-- The list editor: the pure part.
--
-- There is no arithmetic of the list here and nothing to check of it here — it
-- belongs to the rules themselves and is checked there. There is one question
-- here: who stays selected after an edit. It breaks silently and painfully: a
-- selection pointing at a record that was taken away shows the fields of one
-- that no longer exists, and the very first edit in them creates it afresh.

local ns = helpers.newNamespace()
helpers.loadAddonFile("Options/List.lua", ns)

local List = ns.ListEditor

--============================================================================
-- The names and the labels
--============================================================================

T.suite("the list: the names go in their own order")

do
    -- The order IS the seniority, and that is why it is not sorted by
    -- anything. A list of rules sorted alphabetically would mean that renaming
    -- a rule changes which of them is senior.
    local entries = {
        { name = "Shields" }, { name = "Alpha" }, { name = "Moo" },
    }
    local names = List.Names(entries)
    T.eq(#names, 3, "all were taken")
    T.eq(names[1], "Shields", "and first comes what was declared first")
    T.eq(names[2], "Alpha", "rather than what is first alphabetically")

    -- A spoiled record in the saved data — they are edited by hand — neither
    -- brings the editor down nor takes an empty row in the list.
    local dirty = List.Names({
        { name = "Good" }, { name = "" }, { name = 42 }, "a string", nil,
        { noName = true },
    })
    T.eq(#dirty, 1, "the nameless and the non-tables were skipped")
    T.eq(dirty[1], "Good", "what was usable was left")

    T.eq(#List.Names(nil), 0, "with no list it is empty")
    T.eq(#List.Names({}), 0, "an empty list is empty")
end

T.suite("the list: the number in a label is the seniority said aloud")

do
    -- Without a number the order is visible only in that one row is above
    -- another, and "above" in a select list means nothing: the player does not
    -- know the list is read from the top down until he has been told.
    T.eq(List.Numbered("Shields", 1), "1. Shields", "the number and the name")
    T.eq(List.Numbered("Shields", 12), "12. Shields", "a two-digit one too")

    T.eq(List.Numbered("Shields", nil), "Shields", "with no number, the name alone")
    T.eq(List.Numbered(nil, 1), "1. ", "with no name the number stays")
    T.eq(List.Numbered(nil, nil), "", "with neither, it is empty")
end

--============================================================================
-- Who stays selected
--============================================================================

T.suite("the list: what was selected stays selected")

do
    local names = { "One", "Two", "Three" }

    -- The main rule. The player moves a rule with the "up" button, and a
    -- selection that jumps in the process means the next press moves a
    -- different rule — that is, the button stops doing what it says.
    T.eq(List.Keep(names, "Two"), "Two", "what is selected is in place, so it stays")
    T.eq(List.Keep({ "Two", "One", "Three" }, "Two"), "Two",
        "and after a move too: it was exactly it that moved")

    -- What vanished is replaced by the first rather than by nothing: an empty
    -- editor with a non-empty list looks like a failure.
    T.eq(List.Keep(names, "Gone"), "One", "what vanished gives the first")
    T.eq(List.Keep(names, nil), "One", "nothing was selected, so the first")

    T.eq(List.Keep({}, "Two"), nil, "the list is empty, so there is nobody to select")
    T.eq(List.Keep(nil, "Two"), nil, "there is no list, so there is nobody to select")
end

T.suite("the list: after a removal the selection slides down")

do
    local before = { "One", "Two", "Three" }

    -- The neighbour BELOW rather than above or the first. The reason lies in
    -- how a list is cleaned: the player presses "remove" several times in a
    -- row, and a selection that slides down puts the next record under the
    -- next press. One that jumps to the beginning makes one aim afresh after every press.
    T.eq(List.Next(before, "One"), "Two", "the first was removed, so the second is selected")
    T.eq(List.Next(before, "Two"), "Three", "the middle one was removed, so the lower one is selected")

    -- The last one has no neighbour below, and then the one above is taken:
    -- otherwise removing the last would mean emptying the editor with a
    -- non-empty list.
    T.eq(List.Next(before, "Three"), "Two",
        "the last was removed, so the previous one is selected")

    T.eq(List.Next({ "Only" }, "Only"), nil,
        "the only one was removed, so there is nobody to select")

    T.eq(List.Next(before, "Gone"), "One",
        "something that was not there was removed, so the selection stays meaningful")
    T.eq(List.Next(nil, "One"), nil, "with no list, nothing")
end

--============================================================================
-- Whether it can be moved
--============================================================================

T.suite("the list: whether it can be moved in this direction")

do
    -- It is asked in order to grey the button out rather than to forbid the
    -- move: the list itself forbids that. A greyed-out "up" button on the very
    -- top record answers the question "why does nothing happen"; a live one
    -- answers nothing.
    local names = { "One", "Two", "Three" }

    T.eq(List.CanMove(names, "Two", -1), true, "the middle one can go up")
    T.eq(List.CanMove(names, "Two", 1), true, "and down")

    T.eq(List.CanMove(names, "One", -1), false, "the top one cannot go up")
    T.eq(List.CanMove(names, "Three", 1), false, "the bottom one cannot go down")

    T.eq(List.CanMove({ "Only" }, "Only", -1), false,
        "the only one does not move anywhere")
    T.eq(List.CanMove({ "Only" }, "Only", 1), false, "neither one way nor the other")

    T.eq(List.CanMove(names, "Gone", -1), false, "an alien name cannot")
    T.eq(List.CanMove(names, "Two", 2), false, "a step over a head cannot")
    T.eq(List.CanMove(names, "Two", 0), false, "a step in place cannot")
    T.eq(List.CanMove(nil, "Two", -1), false, "with no list it cannot")
end

--============================================================================
-- The adapter
--============================================================================

T.suite("the list: an incomplete adapter is spoken of at the assembly")

do
    -- A list missing one of the actions is a list one of whose buttons
    -- silently does not work: it is pressed and nothing happens. That has to
    -- be said to whoever declared the list, and at the assembly rather than at
    -- the press.
    local whole = {
        Entries = function() return {} end,
        Add = function() end,
        Remove = function() end,
        Move = function() end,
        -- Fields is obligatory: without it the editor shows a list there is
        -- nothing to edit with — and that is exactly what it is supposed to be.
        Fields = function() return {} end,
    }
    local ok, missing = List.Ready(whole)
    T.eq(ok, true, "a complete adapter is usable")
    T.eq(missing, nil, "and there is nothing to complain about")

    -- Three are obligatory. Without any of them the editor is meaningless:
    -- nothing to show, nothing to reorder with or nothing to edit with.
    for _, name in ipairs({ "Entries", "Fields" }) do
        local broken = {}
        for key, value in pairs(whole) do broken[key] = value end
        broken[name] = nil

        local fine, gone = List.Ready(broken)
        T.eq(fine, false, "without " .. name .. " the adapter is unusable")
        T.eq(gone, name, "and what is named is exactly " .. name)
    end

    -- Creating and removing, however, is not something every list can do. The
    -- panel's cells come out of a registry: they are not created and not
    -- removed, they are hidden and reordered. Demanding empty stubs of such a
    -- list means creating a button that is pressed to no effect — that is,
    -- exactly the failure the player takes for a mistake of his own.
    for _, name in ipairs({ "Add", "Remove", "Move" }) do
        local without = {}
        for key, value in pairs(whole) do without[key] = value end
        without[name] = nil

        local fine = List.Ready(without)
        T.eq(fine, true, "without " .. name .. " the adapter is usable all the same")
    end

    T.eq(List.Ready(nil), false, "there is no adapter, so it is unusable")
    T.eq(List.Ready("a string"), false, "not a table is unusable")
end
