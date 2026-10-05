local ADDON, ns = ...

-- The visibility of the settings tree's nodes: empty shells and the window's
-- redrawing.
--
-- The addon has not one line of display code of its own. All there is here is
-- the hidden predicate, which AceConfigDialog computes at every drawing without
-- our help.
--
-- One rule is left here: a section in which not one node is visible right now
-- is not shown at all. An empty row in the left column promises contents that
-- are not behind it — and a section's reason to be empty is a real one and not
-- ours: the element it governs may be absent from this client, and then all its
-- nodes are hidden by their own predicates.
--
-- A "Simple / Everything" display mode used to live here as well: the settings
-- carried an arg.level marker, and the simple mode took everything marked
-- "advanced" off the tree. That mode is gone. The author said about it
-- outright that he had no use for the Simple switch and always wanted to see
-- every setting — and he said it not out of taste but having been burnt twice
-- in one hour: he looked for the action bars' padding and did not find it, then
-- opened a section and saw one list in it instead of a page. A setting you
-- cannot find is no better than one that is not there, and the division into
-- two kinds gave precisely that. There is not one level marker left in the
-- tree.

-- The node types that are not a setting. A description and a header are text,
-- a group is a container.
local NOT_A_SETTING = {
    group       = true,
    description = true,
    header      = true,
}

-- The same enumeration exposed. The search (Config/Search.lua) decides "is this
-- a setting" by the same rule, and a second such list would diverge from this
-- one silently: a new node type would be added to one of the two.
ns.NOT_A_SETTING = NOT_A_SETTING

-- The predicates this file has placed. A table with weak keys: it exists for
-- exactly one purpose, not to wrap one node twice when the tree is rebuilt (the
-- modules' sections are file-level tables, and BuildBaseOptions lays those out
-- across the tree rather than copies of them). The marker lives here rather
-- than as a field on the node: AceConfigRegistry checks every node against a
-- list of known fields, and an extra field would bring the window's opening
-- down.
local installed = setmetatable({}, { __mode = "k" })

-- The same list exposed. There are two rules of visibility in the addon — the
-- empty shell and the search (Config/Search.lua) — and they are hung one over
-- the other: the shell first, then the search. On a rebuild of the tree the
-- first is obliged to recognise its own work inside the search's wrapper, or
-- the wrappers would pile up at every arrival of a module. So the list is a
-- shared one: "we placed this predicate" is one question for both.
ns.HiddenPredicates = installed

--- Whether a node is hidden right now.
-- AceConfig's hidden field comes as a value, as a function and as the name of a
-- handler's method. The addon does not use a method by name, and calling
-- somebody else's handler from here is not allowed: such a node counts as
-- visible.
-- @param option table a node of the tree
-- @return boolean
local function IsHidden(option, ...)
    local hidden = option.hidden
    if hidden == nil then return false end
    if type(hidden) == "function" then return hidden(...) and true or false end
    if type(hidden) == "string" then return false end
    return hidden and true or false
end

--- Whether a section holds at least one node visible right now — any node.
-- A description counts too: a section in which an explanatory label is left
-- shows the player something, while an empty shell shows nothing.
-- @param group table a node of the tree of type group
-- @return boolean
local function AnyVisible(group, ...)
    for _, option in pairs(group.args or {}) do
        if type(option) == "table" and type(option.type) == "string" then
            if not IsHidden(option, ...) then return true end
        end
    end
    return false
end

--- The predicate "not one visible subsection is left in the section".
--
-- Needed by the explanatory label that lies in the container section itself. A
-- description is always visible, and a container all of whose subsections have
-- hidden themselves would show that label alone — a promise of contents that
-- are not behind it. With this predicate the label goes away along with the
-- contents, and an empty shell hides itself by the general rule
-- (HideEmptyGroup below) rather than by a separate exception for containers.
--
-- Only subsections are counted. The description itself does not fall into the
-- walk, so a recursion of "the description asks the section, the section asks
-- the description" cannot happen here.
-- @param group table the node of type group the description lies in
-- @return function a predicate for the hidden field
function ns.HiddenWithoutGroups(group)
    return function(...)
        for _, option in pairs(group.args or {}) do
            if type(option) == "table" and option.type == "group"
                and not IsHidden(option, ...) then
                return false
            end
        end
        return true
    end
end

--- Wrap a section's hidden predicate in the rule "do not show an empty shell".
--
-- A section empties for a real reason and not ours: there is not one element it
-- governs in this client, and all its nodes are hidden by their own predicates.
-- That ends in a row in the left column with nothing behind it. So the
-- emptiness is computed as a fact, by walking the contents, rather than derived
-- from any marker.
-- @param group table a node of the tree of type group
-- @param existing function|boolean|string|nil the hidden field's former value
-- @return function the new predicate
local function HideEmptyGroup(group, existing)
    if existing == true then return existing end

    local previous = type(existing) == "function" and existing or nil

    local predicate = function(...)
        if previous and previous(...) then return true end
        return not AnyVisible(group, ...)
    end

    installed[predicate] = true
    return predicate
end

--- Hang the rule "an empty shell is not shown" across the tree.
-- The tree is edited in place and returned: the caller does not have to think
-- about whether what it has is a copy or the original.
--
-- A section's contents are processed before the section itself: a section
-- computes its emptiness from the visibility of its nodes, and before the walk
-- goes deeper that is not yet the right answer.
-- @param node table a node of the tree of type group
-- @return table the same node
function ns.HideEmptySections(node)
    for _, option in pairs(node.args or {}) do
        if type(option) == "table" and option.type == "group" then
            ns.HideEmptySections(option)
            if not installed[option.hidden] then
                option.hidden = HideEmptyGroup(option, option.hidden)
            end
        end
    end

    return node
end

--- Save what has been typed into the edit box that currently has focus.
--
-- A redrawing of the window recreates the widgets, and text typed but not
-- confirmed would vanish along with the old box. So before the redrawing it is
-- confirmed by the same path Enter would confirm it: AceGUI keeps a reference to
-- the widget in focus, and its own event is sent to it. What was typed is not
-- lost in the process but saved — which is stronger than "it survived in the
-- box".
-- @param gui table|nil the AceGUI-3.0 table (nil means there is nothing to do)
-- @return boolean whether there was anything to confirm
function ns.CommitFocusedEdit(gui)
    if type(gui) ~= "table" then return false end

    local widget = gui.FocusedWidget
    if type(widget) ~= "table" or type(widget.Fire) ~= "function" then
        return false
    end

    local box = widget.editbox
    if type(box) ~= "table" or type(box.GetText) ~= "function" then
        return false
    end

    local ok, text = pcall(box.GetText, box)
    if not ok then return false end

    widget:Fire("OnEnterPressed", text)

    if type(gui.ClearFocus) == "function" then
        pcall(gui.ClearFocus, gui)
    end

    return true
end

--- Rebuild the settings window from scratch.
--
-- Why this exists on top of an ordinary redrawing. The styling is laid onto a
-- widget once: we paint it at creation and take nothing back off. So a change
-- of accent colour repainted only what the window created after it — while
-- everything already built stayed as it was until a reload. From the outside
-- that is the very "the colour is not applied in full", and the author sent in
-- exactly that screenshot.
--
-- A rebuild solves it entirely and cheaply: AceGUI releases the widgets when it
-- closes and creates them afresh when it opens, that is, each of them passes
-- through the styling once more and takes the new colour.
--
-- The page that was open is lost in the process — the window opens on the first
-- one. That is a known price and a small one: the colour is changed on
-- "General", which is where the chooser stands.
--
-- @return boolean whether it was rebuilt
function ns.RebuildConfigWindow()
    if LibStub == nil then return false end

    local dialog = LibStub("AceConfigDialog-3.0", true)
    if dialog == nil or type(dialog.Open) ~= "function" then return false end

    -- There is no point dealing with a closed window: its next opening will
    -- create the widgets afresh anyway.
    local open = dialog.OpenFrames and dialog.OpenFrames[ADDON] or nil
    if open == nil then return false end

    ns.CommitFocusedEdit(LibStub("AceGUI-3.0", true))

    if type(dialog.Close) == "function" then pcall(dialog.Close, dialog, ADDON) end
    pcall(dialog.Open, dialog, ADDON)
    return true
end

--- Rebuild the open settings window.
-- The hidden predicates are computed at a redrawing rather than constantly:
-- without a notification an open window would stay as it was until the next
-- /darken. What was typed into the edit box is confirmed before the redrawing
-- rather than after it: afterwards there would be nothing left to confirm.
function ns.NotifyConfigChanged()
    -- Our own window rather than somebody else's library: it is redrawn
    -- entirely, and the conditional rows are asked about afresh at every
    -- redrawing.
    if type(ns.Window) == "table" and type(ns.Window.Repaint) == "function"
    then
        pcall(ns.Window.Repaint)
        return
    end

    if LibStub == nil then return end

    ns.CommitFocusedEdit(LibStub("AceGUI-3.0", true))

    local registry = LibStub("AceConfigRegistry-3.0", true)
    if registry and type(registry.NotifyChange) == "function" then
        registry:NotifyChange(ADDON)
    end
end

--============================================================================
-- The probe of the explanatory paragraphs
--============================================================================

-- How many paragraphs to print. There are thirty-eight of them in the window,
-- and the first few are enough for an answer: the cause is one for all of them,
-- or it is not one cause.
local PROBE_LIMIT = 3

-- How deep to search. The settings window is a tree of fifteen-odd levels, and
-- a paragraph lies no deeper than a section's page.
local PROBE_DEPTH = 12

--- Whether this is a long label, that is, an explanatory paragraph.
-- A setting's label is two or three words; a paragraph is a sentence or longer.
-- The boundary is deliberately crude: a label has no exact mark, and the task
-- here is a single one — to tell a paragraph from a header.
-- @param text string
-- @return boolean
local function paragraph(text)
    return type(text) == "string" and #text > 40
end

--- Gather the state of the open settings window's paragraphs.
--
-- Answers the question the look of the screen cannot answer: why the
-- explanations are not visible. There are exactly four causes — there is no
-- text, there is no font, the transparency is at zero, the string is hidden —
-- and each is printed as a number.
--
-- The window is asked of the library rather than remembered in a field of our
-- own: it is built and taken apart by AceConfigDialog, and a second accounting
-- of the same window would diverge from it silently.
--
-- @return table|nil an array of lines; nil means there is no window
function ns.ProbeWindowText()
    if type(_G.LibStub) ~= "function" and type(_G.LibStub) ~= "table" then
        return nil
    end

    local ok, dialog = pcall(_G.LibStub, "AceConfigDialog-3.0", true)
    if not ok or type(dialog) ~= "table" then return nil end
    if type(dialog.OpenFrames) ~= "table" then return nil end

    local root
    for _, holder in pairs(dialog.OpenFrames) do
        if type(holder) == "table" and type(holder.frame) == "table" then
            root = holder.frame
            break
        end
    end
    if root == nil then return nil end

    local lines, seen = {}, 0

    local function look(frame, depth)
        if seen >= PROBE_LIMIT then return end
        if type(frame) ~= "table" or depth > PROBE_DEPTH then return end

        if type(frame.GetRegions) == "function" then
            local fine, regions = pcall(function()
                return { frame:GetRegions() }
            end)
            if fine then
                for i = 1, #regions do
                    local region = regions[i]
                    if seen >= PROBE_LIMIT then break end
                    if type(region) == "table"
                        and type(region.GetObjectType) == "function"
                        and region:GetObjectType() == "FontString" then

                        local text = region.GetText and region:GetText() or nil
                        if paragraph(text) then
                            seen = seen + 1

                            local path, size = nil, nil
                            if type(region.GetFont) == "function" then
                                local good, a, b = pcall(region.GetFont, region)
                                if good then path, size = a, b end
                            end

                            -- The colour is a fifth cause, and after the
                            -- first probe the only one left: the text, the
                            -- font, the transparency and the showing turned out
                            -- to be in order. A label in the background's
                            -- colour gives exactly what is seen in the
                            -- screenshot: a flat band with no half-tones.
                            local cr, cg, cb = -1, -1, -1
                            if type(region.GetTextColor) == "function" then
                                local fine, a, b2, c = pcall(
                                    region.GetTextColor, region)
                                if fine then cr, cg, cb = a, b2, c end
                            end

                            -- And the layer: a label can be in place but
                            -- under an opaque backing.
                            local layer = "?"
                            if type(region.GetDrawLayer) == "function" then
                                local fine, got = pcall(
                                    region.GetDrawLayer, region)
                                if fine and got then layer = tostring(got) end
                            end

                            local alpha = region.GetAlpha
                                and region:GetAlpha() or -1
                            local shown = region.IsShown
                                and region:IsShown() or false

                            -- Shown and visible are different things, and
                            -- that difference cost me two wrong guesses.
                            -- IsShown answers for the string's OWN marker;
                            -- meanwhile the parent may be hidden or
                            -- transparent, and the string will honestly say
                            -- "shown" without being drawn.
                            local visible = region.IsVisible
                                and region:IsVisible() or false

                            local up = region.GetParent
                                and region:GetParent() or nil
                            local upAlpha, upVisible = -1, false
                            local upLeft, upTop, upPins = nil, nil, -1
                            local upWide, upHigh = -1, -1
                            if type(up) == "table" then
                                if type(up.GetAlpha) == "function" then
                                    upAlpha = up:GetAlpha()
                                end
                                if type(up.IsVisible) == "function" then
                                    upVisible = up:IsVisible()
                                end
                                -- The owner's place and size: by them it is
                                -- visible where the chain of anchors breaks.
                                -- The string has no place but the owner does —
                                -- then we broke it, in a rearrangement of our
                                -- own. Nobody has one — then the widget's
                                -- frame was never placed by the layout at
                                -- all.
                                if type(up.GetLeft) == "function" then
                                    upLeft = up:GetLeft()
                                end
                                if type(up.GetTop) == "function" then
                                    upTop = up:GetTop()
                                end
                                if type(up.GetNumPoints) == "function" then
                                    upPins = up:GetNumPoints()
                                end
                                if type(up.GetWidth) == "function" then
                                    upWide = up:GetWidth()
                                end
                                if type(up.GetHeight) == "function" then
                                    upHigh = up:GetHeight()
                                end
                            end
                            local wide = region.GetWidth
                                and region:GetWidth() or -1

                            -- A string has TWO heights, and they are easy to
                            -- confuse. GetStringHeight is how much room the
                            -- text needs; GetHeight is how much it was given.
                            -- The text is clipped by the second, and a zero
                            -- second with a healthy first gives exactly what is
                            -- on the screen: the room is taken, there are no
                            -- letters. In the previous probe I printed only the
                            -- first.
                            local high = region.GetStringHeight
                                and region:GetStringHeight() or -1
                            local room = region.GetHeight
                                and region:GetHeight() or -1

                            -- And how many anchors the string has: a string
                            -- without them stands in its owner's bottom left
                            -- corner rather than where it is expected.
                            local pins = region.GetNumPoints
                                and region:GetNumPoints() or -1

                            lines[#lines + 1] = string.format(
                                "%d: %s, %s %s, %s %.2f, %s %d, "
                                    .. "%s %d x %d, %s %.2f %.2f %.2f, %s %s",
                                seen,
                                string.format(ns.Localize("letters %d"), #text),
                                ns.Localize("font"),
                                tostring(path) .. " " .. tostring(size),
                                ns.Localize("opacity"), alpha,
                                ns.Localize("shown"), shown and 1 or 0,
                                ns.Localize("size"), wide, high,
                                ns.Localize("color"), cr, cg, cb,
                                ns.Localize("layer"), layer)

                            -- Where the string stands on the screen.
                            --
                            -- The last unchecked fact. The engine says the
                            -- string is visible, the colour is light, the owner
                            -- is intact, the layer is the top one — and it is
                            -- not on the screen. Which means it is drawn
                            -- somewhere other than where it is looked for:
                            -- pushed past the scroll frame's edge, gone below
                            -- the window's bottom, or standing in somebody
                            -- else's corner.
                            local left = region.GetLeft and region:GetLeft()
                            local top = region.GetTop and region:GetTop()

                            -- And the text's beginning: the probe may have
                            -- found strings other than the ones on the page —
                            -- widgets released into a pool live nearby and look
                            -- the same.
                            local head = text:sub(1, 24):gsub("%s+", " ")

                            lines[#lines] = lines[#lines] .. string.format(
                                ", %s %d, %s %.2f / %d, %s %d, %s %d, "
                                    .. "%s %d,%d, [%s]",
                                ns.Localize("visible"), visible and 1 or 0,
                                ns.Localize("owner"), upAlpha,
                                upVisible and 1 or 0,
                                ns.Localize("room"), room,
                                ns.Localize("anchors"), pins,
                                ns.Localize("at"),
                                tonumber(left) or -1, tonumber(top) or -1,
                                head)

                            -- The whole chain of owners up to the first that
                            -- has a place.
                            --
                            -- Neither the string nor its frame has a position,
                            -- although the frame has two anchors. Which means
                            -- the break is higher up, and what has to be asked
                            -- is not one link but the whole chain: the link at
                            -- which a place appears is the boundary between
                            -- "placed" and "hanging on nothing".
                            local chain, step = {}, up
                            for _ = 1, 6 do
                                if type(step) ~= "table" then break end

                                local kind = "?"
                                if type(step.GetObjectType) == "function" then
                                    local fine, got = pcall(
                                        step.GetObjectType, step)
                                    if fine and got then kind = tostring(got) end
                                end

                                local said = "-"
                                if type(step.GetName) == "function" then
                                    local fine, got = pcall(step.GetName, step)
                                    if fine and got then said = tostring(got) end
                                end

                                local place = "-"
                                if type(step.GetLeft) == "function" then
                                    local fine, got = pcall(step.GetLeft, step)
                                    if fine and got then
                                        place = string.format("%d", got)
                                    end
                                end

                                local pins = -1
                                if type(step.GetNumPoints) == "function" then
                                    local fine, got = pcall(
                                        step.GetNumPoints, step)
                                    if fine and got then pins = got end
                                end

                                chain[#chain + 1] = string.format(
                                    "%s/%s %s/%d", kind, said, place, pins)

                                if type(step.GetParent) ~= "function" then
                                    break
                                end
                                local fine, above = pcall(step.GetParent, step)
                                if not fine then break end
                                step = above
                            end

                            lines[#lines + 1] = "   "
                                .. table.concat(chain, " < ")

                            -- WHAT the paragraph's frame is anchored to.
                            --
                            -- The last question. It has two anchors, the owner
                            -- stands in place, and the frame itself has no
                            -- place — which means it is anchored not to the
                            -- owner but to something that has no place either.
                            -- AceGUI's layout can hook an element onto the
                            -- previous one, and then one unplaced neighbour
                            -- carries off everybody behind it.
                            if type(up) == "table"
                                and type(up.GetPoint) == "function" then
                                local pinned = {}
                                for k = 1, (upPins > 0 and upPins or 0) do
                                    local fine, point, to, theirs, dx, dy =
                                        pcall(up.GetPoint, up, k)
                                    if fine then
                                        local kind, place = "nil", "-"
                                        if type(to) == "table" then
                                            if type(to.GetObjectType)
                                                == "function" then
                                                local g, got = pcall(
                                                    to.GetObjectType, to)
                                                if g and got then
                                                    kind = tostring(got)
                                                end
                                            end
                                            if type(to.GetLeft) == "function"
                                            then
                                                local g, got = pcall(
                                                    to.GetLeft, to)
                                                if g and got then
                                                    place = string.format(
                                                        "%d", got)
                                                end
                                            end
                                            if to == up:GetParent() then
                                                kind = kind .. "=parent"
                                            end
                                        end
                                        pinned[#pinned + 1] = string.format(
                                            "%s->%s/%s %s %d,%d",
                                            tostring(point), kind, place,
                                            tostring(theirs),
                                            tonumber(dx) or 0,
                                            tonumber(dy) or 0)
                                    end
                                end
                                lines[#lines + 1] = "   "
                                    .. table.concat(pinned, " | ")
                            end
                        end
                    end
                end
            end
        end

        if type(frame.GetChildren) == "function" then
            local fine, children = pcall(function()
                return { frame:GetChildren() }
            end)
            if fine then
                for i = 1, #children do look(children[i], depth + 1) end
            end
        end
    end

    look(root, 0)

    if #lines == 0 then
        lines[1] = ns.Localize("no explanatory paragraph found in the window")
    end
    return lines
end
