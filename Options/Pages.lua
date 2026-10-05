local ADDON, ns = ...

-- The core's own settings pages, declared as data.
--
-- === What belongs here and what does not ===
--
-- Here are the pages the core itself owns: General and everything about the
-- addon as such. Subsystem pages are declared by the subsystems, next to
-- their own code: a dimming setting and the dimming code are edited together,
-- and splitting them across files means editing in two places.
--
-- === Why the texts were carried over verbatim ===
--
-- The migration changes the window, not the words. Every paragraph here is
-- already written, already translated into two languages and already explains
-- exactly what it should; rewriting them at the same time would mix two
-- different changes and lose both translations.

local Schema = ns.Schema

--============================================================================
-- General
--============================================================================

Schema.Page("general", {
    title = "General",
    order = 2,
})

Schema.Add("general", {
    kind = "note",
    hint = "Darken repaints the game's own interface dark and hands you "
        .. "the parts Blizzard leaves alone. Nothing here is one way: the "
        .. "first entry in every list is the game's own look, and the one "
        .. "setting a fresh install changes by itself is the interface "
        .. "darkness, at sixty-four of a hundred. Type /darken in chat to "
        .. "open this window again.",
})

Schema.Add("general", {
    kind = "header",
    label = "Looks",
})

Schema.Add("general", {
    kind = "note",
    hint = "A look is a batch of this addon's own settings applied at once. "
        .. "It touches only the settings it names below: everything else "
        .. "stays as you left it. Nothing is locked in - each of these "
        .. "settings keeps its own list in its own section, and the game's "
        .. "own look is the first entry in every one of them.",
})

-- Preset buttons are generated from the list rather than written out one by
-- one: the list lives in Core/Presets.lua, and a preset added there has to
-- appear in the window by itself.
do
    local presets = type(ns.PRESETS) == "table" and ns.PRESETS or {}
    for i = 1, #presets do
        local preset = presets[i]
        Schema.Add("general", {
            kind = "action",
            label = preset.label,
            hint = preset.desc,
            apply = "none",
            run = function()
                local db = ns.Addon and ns.Addon.db
                if type(db) ~= "table" then return end
                if type(ns.ApplyPreset) ~= "function" then return end

                -- A preset touches settings of several subsystems at once,
                -- so it is applied to all of them rather than to one named
                -- subsystem.
                if ns.ApplyPreset(db.profile, preset)
                    and type(ns.Registry) == "table" then
                    pcall(ns.Registry.ApplyAll, ns.Registry)
                end
            end,
        })
    end
end

Schema.Add("general", {
    kind = "header",
    label = "Accent Color",
})

Schema.Add("general", {
    kind = "select",
    label = "Accent Color",
    path = { "accent" },
    apply = "none",
    hint = "The one color the dark theme uses to say look here: section "
        .. "headings, the tick in a checkbox, the filled part of a slider, "
        .. "the scrollbar, the chosen row and whatever the mouse is over. "
        .. "Everything else - the blacks, the lines, the text - stays as it "
        .. "is. Parts already drawn keep the old color until /reload.",
    values = function()
        local out = {}
        local sets = ns.Skin and ns.Skin.ACCENTS or {}
        for key in pairs(sets) do
            out[#out + 1] = { key = key, text = ns.Localize(key) }
        end
        table.sort(out, function(a, b) return a.key < b.key end)
        return out
    end,
})

-- There is deliberately no "Minimap Button" heading here: the nesting
-- inserts one from the nested page's title. Declared by hand as well, it
-- produced a second identical heading with a blank strip between them.
--
-- The minimap button is declared as its own page because it lives in a
-- DIFFERENT store: the button's position and visibility are account-wide, no
-- matter how many profiles exist. That page has no column entry — it nests
-- into General through the `parent` field.
Schema.Page("launcher", {
    title = "Minimap Button",
    order = 2.5,
    section = "launcher",
    store = "global",
    parent = "general",
})

Schema.Add("launcher", {
    kind = "toggle",
    label = "Button on the Minimap",
    path = { "shown" },
    apply = "launcher",
    hint = "A button on the edge of the minimap that opens and closes this "
        .. "window. Drag it around the minimap to move it.",
})

Schema.Add("general", {
    kind = "header",
    label = "This Copy",
})

Schema.Add("general", {
    kind = "toggle",
    label = "Skin Settings Windows",
    path = { "skinAce" },
    apply = "none",
    hint = "Paint the settings windows of other addons that use the same "
        .. "library this one does. Needs /reload either way.",
})
