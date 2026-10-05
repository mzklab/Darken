local helpers = require("helpers")

-- The visibility of the settings tree's nodes (Config/Visibility.lua).
--
-- There is one rule here: a section in which not one node is visible right
-- now is not shown at all. It is checked on an invented tree, because what is
-- checked is the rule itself; on the real tree it is checked by
-- tests/test_optionpages.lua.
--
-- This file used to guard the "Simple / Everything" display mode. That mode
-- is gone — the author asked for it to be removed, saying he had no use for
-- the Simple switch and always wanted to see every setting — and not one
-- check of it is left: a rule that does not exist cannot be broken.

T.suite("ns.HideEmptySections: an empty shell is not shown")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Config/Visibility.lua", ns)

--- Whether a node is visible right now.
local function visible(option)
    local hidden = option.hidden
    if hidden == nil then return true end
    if type(hidden) == "function" then return not hidden() end
    return not hidden
end

local tree = {
    type = "group",
    args = {
        plain = { type = "toggle" },
        note  = { type = "description", name = "n" },
        -- A section that does not exist in this client: its own predicate is
        -- obliged to survive the pass and keep the section hidden.
        absent = {
            type = "group",
            hidden = function() return true end,
            args = { a = { type = "toggle" } },
        },
        live = {
            type = "group",
            args = { a = { type = "toggle" }, b = { type = "toggle" } },
        },
        -- A section all of whose contents are hidden by their own predicates.
        hollow = {
            type = "group",
            args = { a = { type = "toggle", hidden = function() return true end } },
        },
    },
}

T.eq(ns.HideEmptySections(tree), tree, "the tree is edited in place")

local args = tree.args

T.eq(visible(args.plain), true, "a setting is not touched at all")
T.eq(visible(args.note), true, "nor is a description")
T.eq(visible(args.live), true, "a section with visible contents is visible")
T.eq(visible(args.absent), false, "somebody else's predicate keeps the section hidden")
T.eq(visible(args.hollow), false, "a section with no visible contents is hidden")

-- A repeated assembly of the tree must not hang a second predicate over the
-- first: the modules' sections are file-level tables, and what gets into the
-- tree is they themselves rather than copies.
local wrapped = args.hollow.hidden
ns.HideEmptySections(tree)
T.eq(args.hollow.hidden, wrapped, "a repeated pass does not wrap a node twice")
T.eq(visible(args.absent), false, "nor does it change somebody else's predicate's behaviour")

-- The emptiness is computed in depth: a section all of whose subsections are
-- hidden is the same empty shell. The contents are walked before the section itself.
do
    local outer = {
        type = "group",
        args = {
            section = {
                type = "group",
                args = {
                    units = {
                        type = "group",
                        hidden = function() return true end,
                        args = { a = { type = "range" } },
                    },
                },
            },
            alive = {
                type = "group",
                args = {
                    units = {
                        type = "group",
                        args = { a = { type = "range" } },
                    },
                },
            },
            -- A section of one description does not count as a shell: the
            -- player has something to read, and there is no point hiding text.
            text = {
                type = "group",
                args = { note = { type = "description", name = "n" } },
            },
        },
    }
    ns.HideEmptySections(outer)

    T.eq(visible(outer.args.section), false,
        "a section all of whose contents are hidden is not shown")
    T.eq(visible(outer.args.alive), true, "a section with a live subsection is visible")
    T.eq(visible(outer.args.text), true, "a section of one description is visible")
end

T.suite("ns.HiddenWithoutGroups: the label goes away along with the subsections")

do
    local box = { type = "group", args = {} }
    local predicate = ns.HiddenWithoutGroups(box)

    T.eq(predicate(), true, "in a container with no subsections the label is hidden")

    box.args.child = { type = "group", args = {} }
    T.eq(predicate(), false, "with a subsection it is visible")

    box.args.child.hidden = function() return true end
    T.eq(predicate(), true, "a hidden subsection does not count as a subsection")
end

T.suite("ns.CommitFocusedEdit: what was typed is saved rather than lost")

T.eq(ns.CommitFocusedEdit(nil), false, "with no AceGUI there is nothing to do")
T.eq(ns.CommitFocusedEdit({}), false, "with no widget in focus there is nothing to do")

-- A widget that is not one of those that accept text: it must not be touched.
T.eq(ns.CommitFocusedEdit({
    FocusedWidget = { Fire = function() end },
}), false, "a widget with no edit box is skipped")

do
    local fired, cleared = {}, false
    local widget = {
        editbox = { GetText = function() return "half typed" end },
        Fire = function(_, event, value)
            fired[#fired + 1] = { event = event, value = value }
        end,
    }
    local gui = {
        FocusedWidget = widget,
        ClearFocus = function() cleared = true end,
    }

    T.eq(ns.CommitFocusedEdit(gui), true, "what was typed was confirmed")
    T.eq(#fired, 1, "the event was sent once")
    T.eq(fired[1].event, "OnEnterPressed", "by the same event as Enter")
    T.eq(fired[1].value, "half typed", "with the text that was typed")
    T.eq(cleared, true, "the focus was cleared after the confirmation")
end

T.suite("the settings window is rebuilt")

-- This function once did not work at all, and silently. It began with a check
-- of type(LibStub) == "function", while LibStub is a table with a __call
-- metamethod: the check was always false and broke the function off at its
-- first line. From the outside that looked like "a module's section appears
-- only after closing and a new /umbra", and it was found by chance. The same
-- mistake can come back just as quietly, so what is checked is not the
-- condition's shape but that the call reaches the library.
do
    local savedLibStub = _G.LibStub

    -- With no LibStub there is nothing to rebuild and no reason to fall over
    -- either: outside the game and on a bare client the library simply is not there.
    _G.LibStub = nil
    T.ok(pcall(ns.NotifyConfigChanged), "with no LibStub the call passes silently")

    local notified, committed = {}, 0
    local libs = {
        ["AceConfigRegistry-3.0"] = {
            NotifyChange = function(_, app) notified[#notified + 1] = app end,
        },
        ["AceGUI-3.0"] = {
            FocusedWidget = {
                Fire = function() committed = committed + 1 end,
                editbox = { GetText = function() return "what was typed" end },
            },
            ClearFocus = function() end,
        },
    }

    -- The fake repeats the real one's build: a table called through __call.
    -- That very build is what the former check did not survive.
    _G.LibStub = setmetatable({}, {
        __call = function(_, name) return libs[name] end,
    })

    ns.NotifyConfigChanged()

    T.eq(#notified, 1, "the library was notified exactly once")
    T.eq(notified[1], "Darken", "and notified about our tree's name")
    T.eq(committed, 1, "what was typed into the edit box was confirmed before the redrawing")

    _G.LibStub = savedLibStub
end
