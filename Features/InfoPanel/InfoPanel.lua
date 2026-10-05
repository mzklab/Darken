local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("infopanel")

-- Darken's info panel: a bar of readouts at the top and the bottom of the
-- screen.
--
-- The file glues five parts together and does nothing else: the formatting
-- (Format.lua), the registry of LibDataBroker-standard readouts (Broker.lua),
-- the layout of the cells and the space taken away from the screen
-- (Layout.lua), our own readouts (Sources.lua), the display (Panel.lua).
-- Registration with the core goes through the public contract
-- (docs/module-api.md).
--
-- === The three decisions that matter most here ===
--
-- Our readouts have no privileges. They are published into the same registry
-- as everybody else's, by the same call of the standard, and the panel reads
-- them from there too. There is not one branch of the form "and what if the
-- readout is ours" in this file: a cell is assembled from a registry object's
-- label and text, whoever created it.
--
-- There is no polling. A value is rebuilt on a game event (gold on
-- PLAYER_MONEY, bags on BAG_UPDATE_DELAYED and so on). Three readouts have no
-- event at all — frames, latency and the clock; for them there is one shared
-- tick on the panel's own frame, and on every tick only what has come due and
-- is shown right now is rebuilt. A hidden panel counts nothing: the engine
-- does not call OnUpdate on a hidden frame.
--
-- There is nothing deferred. The panel is our own frame under UIParent,
-- unprotected by the engine, and anything at all may be done to it in combat.
-- The module's only deferred action is moving UIParent itself, because it is
-- the game that forbids moving it in combat, not us (the contract, section
-- 9).
--
-- === Its place on screen ===
--
-- A bar at the top is obliged to shift the interface, or it will cover it. The
-- shift is done the only way that needs no list of foreign frames: UIParent's
-- edge is pushed inwards by the bar's height, and everything that sits inside
-- UIParent follows along by itself. UIParent's native anchors are preserved
-- while this happens, only the offset changes (Layout.Offsets), and when the
-- panel is switched off they are put back as they were.

if type(Darken) ~= "table" or type(Darken.RegisterModule) ~= "function" then
    print("|cffff4040" .. ADDON .. "|r: Darken is not loaded, so this addon "
        .. "does nothing. Install Darken, or disable this addon.")
    return
end

-- The contract version the module is written against. The fourth brings what
-- is needed: the skin (GetSkin), the fonts (GetMedia), events, strings of our
-- own, work deferred to the end of combat and a slash-command word. The fifth
-- and the sixth added work with one's own saved data and a per-character
-- setting — neither is here, and declaring them would mean refusing to load on
-- a core that is enough for the module.
--
-- The eleventh is the dictionary of states (skin.RowColors). A cell menu's row
-- is the same kind of clickable row as a section row in the settings window
-- and a choice-list row in the bags window, and before the dictionary it
-- answered the cursor with nothing. Fixing that with a fill of our own is not
-- allowed: "a hover is lilac at 0.16" belongs to the core, and a second record
-- would diverge from the first silently.
--
-- The twelfth is number writing (Darken:GetFormat). The panel shows
-- experience, reputation and durability — that is, large numbers and
-- percentages — and before this door it wrote them by its own copy of the
-- rule: a health bar wrote 12.4k while the cell below it wrote 12k. One number
-- written two ways on one screen reads as two different addons, so here too
-- there is an honest refusal on an old core rather than a quietly different
-- number.
--
-- The thirteenth is rounding to a whole number (Darken:GetFormat().Round).
-- Exactly one cell needs it — the frame rate, which arrives fractional and is
-- shown whole — and before version 13 the panel wrote it with a body of its
-- own that matched the core's line for line. The panel has no copies of the
-- rule left at all.
--
-- The nineteenth is the Darken:GetGameFunction door: which of the two
-- spellings this client reads the bags by is now decided by the core's
-- compatibility layer. On cores of version 18 and older the door is absent,
-- and the bags cell would show a dash — that is, "there are no bags" instead
-- of "there is nobody to ask"; a refusal at registration is more honest.
local API = 19

-- The module's pure part takes number writing from the core and is not
-- created at all without it (Format.lua). That has to be said in one readable
-- line — before the file runs into the absence by itself.
if type(ns.Format) ~= "table" then
    print("|cffff4040" .. ADDON .. "|r: this addon needs Darken module API "
        .. "version 13, and the installed Darken is older. Update Darken "
        .. "UI, or disable this addon.")
    return
end

local module
local Layout = ns.Layout
local Sources = ns.Sources
local Broker = ns.Broker
local Format = ns.Format
local Panel = ns.Panel

--- Translate one of the module's strings.
-- @param key string|nil the English string that serves as the key
-- @return string
function ns.Localize(key)
    if module ~= nil then return module:Localize(key) end
    if key == nil or key == "" then return "" end
    return key
end

--- The core's media right now.
--
-- Asked for at the same time and for the same reason as the skin: the font
-- lives behind the same door, and a media table remembered while the file was
-- read is the same breach of the rule, merely less visible to the eye.
--
-- @return table|nil
local function currentMedia()
    if type(Darken.GetMedia) ~= "function" then return nil end

    local ok, media = pcall(Darken.GetMedia, Darken)
    if not ok or type(media) ~= "table" then return nil end

    return media
end

--- The core's skin right now.
--
-- Asked for on every application rather than remembered while the file is
-- read. A plain assignment of Darken:GetSkin() used to stand here, and on the
-- current core it made no difference: the door is defined by the moment our
-- files are read, and behind the door is one and the same table. The
-- contract's rule is nevertheless to ask: a remembered skin outlives a change
-- of palette silently, and the bar would stay painted the old way beside a
-- window painted the new way. Both of the modules' windows ask every time; now
-- the panel does too.
--
-- @return table|nil
local function currentSkin()
    if type(Darken.GetSkin) ~= "function" then return nil end

    local ok, skin = pcall(Darken.GetSkin, Darken)
    if not ok or type(skin) ~= "table" then return nil end

    return skin
end

-- The gap between cells. From the core skin's scale of insets rather than as
-- a number: one and the same distance on screen is set by one value for the
-- whole addon. Asked for at the same time as the skin itself, and for the same
-- reason.
-- @param skin table|nil
-- @return number
local function gapOf(skin)
    if type(skin) ~= "table" or type(skin.Metrics) ~= "function" then
        return 12
    end

    local metrics = skin.Metrics()
    return tonumber(metrics.group) or tonumber(metrics.gap) or 12
end

-- The bars. Created when first needed: a switched-off module creates no
-- frames at all.
local bars = {}

-- The registry of readouts and our objects in it.
local broker, published

-- The access table to the game for our readouts.
local env = Sources.Environment(_G)

-- The tick: when the timed readouts were last rebuilt, and how much time has
-- accumulated since the previous tick.
local ticks, accumulated = {}, 0

-- The names of the readouts that are shown right now. The tick needs them:
-- there is no reason to rebuild what cannot be seen.
local shownNames = {}

-- Whether we are drawing right now, and whether we are subscribed to the
-- game's events.
local drawing, listening = false, false

-- What came out of the last repaint. Needed by the report, and by nothing
-- else.
--
-- The panel was fixed blind twice, by the look of the screen, and twice wide
-- of the mark: "there is no bar" looks the same whether not one cell landed on
-- it, or the frame was never built, or it was built, shown and standing above
-- the screen's edge. Those three cases are fixed differently, and they can be
-- told apart only from the inside.
local lastTop, lastBottom = 0, 0

-- The space taken away from the screen, and UIParent's native anchors as they
-- were before we touched them. The anchors are remembered exactly once: after
-- our first shift GetPoint returns ours.
local reservedTop, reservedBottom = 0, 0
local basePoints
local refused = false

-- The state of the screen shift, in a form that can be shown to a person.
--
-- Moving UIParent is the module's only protected operation, and it has never
-- once been carried out in a live client. So what is kept here is not one
-- number but three different ones: how much space was asked for, how much was
-- actually applied, and whether the change is waiting for the end of combat.
-- There used to be one, and it meant "asked for" while it read as "done" —
-- exactly the difference that makes debugging such a thing start with "but
-- everything is right in my settings".
local appliedTop, appliedBottom = 0, 0
local pending = false          -- the change is waiting for the end of combat
local declined                 -- the core refused the deferred work, and why
local expected                 -- the anchors we set last
local mismatch                 -- how the live UIParent differs from them
local blocked = 0              -- engine refusals to protected code during our
                               -- shift
local blockedSaid = false      -- whether the player was told about them
local forced = false           -- recompute the shift afresh even when the
                               -- number is the same

-- The repaint is declared here and called below: the screen shift is
-- sometimes deferred (combat), and when it finally happens the bars have to be
-- moved to their new place. Otherwise a bar would go on standing at the old
-- offset until the next change of a setting.
local redraw

-- The cell selected in the settings. Not a setting: this is the window's
-- state rather than a choice of the player's that has to outlive leaving the
-- game.
local selected

--- The module's settings.
-- @return table|nil
local function Settings()
    return module and module:GetSettings() or nil
end

--- The bar for a side, created when first needed.
-- @param side string
-- @return table|nil
local function bar(side)
    if bars[side] == nil then
        bars[side] = Panel.Build(currentSkin()) or false
    end
    return bars[side] or nil
end

--- A frame's anchors right now, as an array.
-- @param frame table|nil
-- @return table
local function pointsOf(frame)
    local out = {}
    if type(frame) ~= "table" or type(frame.GetPoint) ~= "function" then
        return out
    end

    local count = type(frame.GetNumPoints) == "function"
        and frame:GetNumPoints() or 0
    for i = 1, count do
        local ok, point, relativeTo, relativePoint, x, y =
            pcall(frame.GetPoint, frame, i)
        if ok then out[i] = { point, relativeTo, relativePoint, x, y } end
    end
    return out
end

--- Apply the space taken away from the screen.
--
-- The module's only place where something is deferred to the end of combat,
-- and it is not deferred by our choice: UIParent is protected by the engine,
-- and the game forbids moving a protected frame in combat. The queue key is
-- one for every shift, so ten edits of the height during a fight are applied
-- once — as the last state (the contract, section 9).
-- @param top number
-- @param bottom number
local function reserve(top, bottom)
    if top == reservedTop and bottom == reservedBottom and not forced then
        return
    end
    forced = false

    local parent = _G.UIParent
    if type(parent) ~= "table" or type(parent.SetPoint) ~= "function" then
        return
    end

    if basePoints == nil then
        basePoints = pointsOf(parent)
    end

    local points = Layout.Offsets(basePoints, top, bottom)
    if points == nil then
        -- There is nothing to move: on this client UIParent does not hang
        -- by its top or its bottom. Covering the interface silently would be
        -- worse — we say so once and draw over it.
        if not refused and module then
            refused = true
            module:Print(ns.Localize("this client does not hold UIParent by "
                .. "its top or bottom edge, so the panel cannot take screen "
                .. "space here and draws over the interface instead"))
        end
        return
    end

    reservedTop, reservedBottom = top, bottom
    expected = points

    -- The shift is applied here, and here it checks itself: right after
    -- SetPoint the anchors are read back off the live frame and compared with
    -- what we asked for. In the client that is the only way to learn that a
    -- protected operation did not merely fail to raise but did what was
    -- intended.
    local function apply()
        parent:ClearAllPoints()
        for i = 1, #points do
            local p = points[i]
            parent:SetPoint(p[1], p[2], p[3], p[4], p[5])
        end

        appliedTop, appliedBottom = top, bottom
        pending = false
        mismatch = Layout.Verify(points, pointsOf(parent))

        -- The bars stand at the offset that ACTUALLY HAPPENED, and it has
        -- just changed. There will be no second shift from here: reserve sees
        -- the same numbers and turns back on its very first line.
        if type(redraw) == "function" then redraw() end
    end

    local ran, why = module:Secure(parent, "reserve", apply)
    if not ran then
        -- Deferred (combat) or rejected (the module was disabled by the
        -- core). The difference is visible in the report: the first will go
        -- through by itself, the second never will.
        pending = true
        declined = why
    else
        declined = nil
    end
end

--- The cell strings of one bar.
-- This is where our readouts' equality with other people's holds: both kinds
-- are registry objects, and one function assembles them.
-- @param names table array of names
-- @return table array of strings
local function objectFor(name)
    if type(broker) ~= "table" then return nil end
    if type(broker.GetDataObjectByName) ~= "function" then return nil end

    local ok, found = pcall(broker.GetDataObjectByName, broker, name)
    if ok then return found end
    return nil
end

local function textsFor(names)
    local out = {}
    for i = 1, #names do
        local label, text = Broker.Text(objectFor(names[i]))
        out[#out + 1] = { name = names[i], text = Format.Cell(label, text) }
    end
    return out
end

--- Rebuild the values of those of our readouts that are due.
-- @param entries table array of descriptions
local function refresh(entries)
    local settings = Settings()
    for i = 1, #entries do
        local entry = entries[i]
        Sources.Update(entry, published and published[entry.key] or nil,
            env, settings)
    end
end

--- The tick.
--
-- One for the whole module, and no more often than once a second. What exactly
-- to rebuild is decided by Sources.Due: a readout with a period of five
-- seconds is rebuilt once every five seconds rather than on every tick, and
-- only when it can be seen.
-- @param elapsed number
local function tick(elapsed)
    accumulated = accumulated + (tonumber(elapsed) or 0)
    if accumulated < 1 then return end
    accumulated = 0

    local now = type(GetTime) == "function" and GetTime() or os.time()
    local due = Sources.Due(Sources.Timed(), ticks, now, shownNames)
    if #due == 0 then return end

    for i = 1, #due do Sources.Mark(ticks, due[i].key, now) end
    refresh(due)
end

--- Whether the tick is needed, and which frame it must live on.
-- @param topShown boolean
-- @param bottomShown boolean
local function drive(topShown, bottomShown)
    local needed = false
    for _, entry in ipairs(Sources.Timed()) do
        if shownNames[Sources.Name(entry.key)] then needed = true end
    end

    -- The script lives on the bar that is shown. A hidden bar does not call
    -- it by itself, but it still has to be removed from it: otherwise, after
    -- the cells moved, the tick would be left on two frames at once.
    local host = (topShown and bar("top")) or (bottomShown and bar("bottom")) or nil
    for _, side in ipairs({ "top", "bottom" }) do
        local frame = bars[side] or nil
        if frame and frame ~= host then Panel.Drive(frame, nil) end
    end

    if host and needed then
        Panel.Drive(host, tick)
    elseif host then
        Panel.Drive(host, nil)
    end
end

-- The mouse on a cell.
--
-- There is exactly one division here, and it is not about whose readout it is
-- but about whose mouse button it is. The left one belongs to the standard: if
-- the readout has its own OnClick, that is called and only that. The right one
-- opens the panel's menu, and opens it the same way for every cell; the
-- readout's own action is not lost in the process — it stands as the first row
-- of that same menu (ns.Cells.Menu).
--
-- Not one of the three branches asks whether the readout is ours: there is
-- nobody to ask, the cell's name comes from the shared registry and the object
-- comes from there as well.
local mouse = {
    Click = function(name, button, cell)
        if type(name) ~= "string" then return end

        local object = objectFor(name)
        if button ~= "RightButton" then
            ns.Cells.Click(object, cell, button)
            return
        end

        local settings = Settings()
        local names = Broker.Names(broker)
        local entries = ns.Cells.Menu(name, settings,
            Layout.Arrange(names, settings and settings.order),
            ns.Cells.Offers(object))

        -- The tooltip goes away: under an open menu it stands over the
        -- rows.
        Panel.Untooltip()
        local pick = function(entry)
            if entry.kind == "own" then
                ns.Cells.Click(object, cell, "RightButton")
                return
            end
            if ns.Cells.Apply(entry, name, settings, Broker.Names(broker)) then
                module:Apply()
            end
        end

        Panel.Menu(entries, cell, name, currentSkin(), currentMedia(), pick)
    end,

    Enter = function(name, cell)
        if type(name) ~= "string" then return end
        local object = objectFor(name)
        Panel.Tooltip(ns.Cells.Tooltip(object, Broker.Text(object)), cell)
    end,

    Leave = function(name, cell)
        if type(name) ~= "string" then return end
        -- First the standard's leave, then our tooltip: a readout that drew
        -- its own has to get the chance to remove it itself.
        ns.Cells.Leave(objectFor(name), cell)
        Panel.Untooltip()
    end,
}

--- Repaint the whole panel.
-- Called on a change of the settings, on a readout appearing in the registry
-- and on a change of anybody else's value. Inside there is only the layout and
-- the placement of the rows: nobody computes a value here.
function redraw()
    if not drawing then return end

    local settings = Settings()
    if not settings then return end

    local names = Broker.Names(broker)
    local visible = Layout.Visible(names, settings.order, settings.hidden)
    local top, bottom = Layout.Split(visible, settings.sides,
        settings.defaultSide, { top = settings.top, bottom = settings.bottom })

    shownNames = {}
    for _, name in ipairs(top) do shownNames[name] = true end
    for _, name in ipairs(bottom) do shownNames[name] = true end

    -- A menu open on a cell that is no longer on the bar is closed: its rows
    -- would lead to a name that can no longer be seen in the panel.
    if Panel.menuOf and not shownNames[Panel.menuOf] then Panel.CloseMenu() end

    local height = Layout.Clamp("height", settings.height)
    local reserveTop, reserveBottom =
        Layout.Reserve(#top, #bottom, height, settings.push)
    reserve(reserveTop, reserveBottom)

    -- Nothing about where the bar stands follows from here any more.
    --
    -- It used to: the bar was placed at an offset from UIParent's edge, by
    -- exactly as much as that edge had been lowered. That holds while the edge
    -- stays where it was put — and it does not stay: the game recomputes
    -- UIParent's layout itself and rolls our shift back silently. The author's
    -- report showed precisely that, and the bar hung above the top of the
    -- screen, that is, nowhere.
    --
    -- Now the bar stands at the SCREEN's edge (Panel.Place), and the space
    -- taken away answers for one thing only: whether the bar rides over the
    -- interface or stands in the ribbon it freed. If nothing was taken away,
    -- it is visible all the same.

    lastTop, lastBottom = #top, #bottom

    local topFrame = #top > 0 and bar("top") or bars.top or nil
    local bottomFrame = #bottom > 0 and bar("bottom") or bars.bottom or nil

    -- The skin is asked for once per repaint and handed to both bars: two
    -- questions in a row would return one and the same thing, and painting the
    -- top and the bottom by two different answers is out of the question.
    local skin = currentSkin()
    local media = currentMedia()
    local gap = gapOf(skin)

    local opacity = settings.opacity

    if topFrame then
        Panel.Opacity(topFrame, opacity)
        Panel.Place(topFrame, "top", height)
        Panel.SetCells(topFrame, textsFor(top), media, skin, gap, mouse)
        Panel.Show(topFrame, #top > 0)
    end
    if bottomFrame then
        Panel.Opacity(bottomFrame, opacity)
        Panel.Place(bottomFrame, "bottom", height)
        Panel.SetCells(bottomFrame, textsFor(bottom), media, skin, gap, mouse)
        Panel.Show(bottomFrame, #bottom > 0)
    end

    drive(#top > 0, #bottom > 0)
end

--- Start drawing: subscribe to the events, publish our own readouts.
local function start()
    if drawing then return end
    drawing = true

    broker = Broker.Acquire(_G.LibStub, broker)
    published = Sources.Publish(broker)

    -- A foreign readout that has appeared or changed its value repaints the
    -- panel. That is the whole of the work with other people's addons: a
    -- subscription to the standard, and not one line about any particular
    -- addon.
    Broker.Subscribe(broker, module, Broker.CHANGED, function() redraw() end)
    Broker.Subscribe(broker, module, Broker.CREATED, function() redraw() end)

    if not listening then
        listening = true
        for _, event in ipairs(Sources.Events()) do
            module:RegisterEvent(event, function(name)
                refresh(Sources.For(name))
            end)
        end

        -- A change of resolution or of scale rearranges UIParent, and the
        -- space taken away has to be taken again. There are two events
        -- because on different clients it is now one, now the other that
        -- arrives.
        --
        -- The shift is recomputed forcibly here. The bar's height does not
        -- change with the resolution, that is, it is "as much as was asked
        -- for" — and without this flag the repaint would decide there was
        -- nothing to do, while the anchors on UIParent are by then somebody
        -- else's. The panel would go on standing and the space under it would
        -- be lost until the first edit of a setting.
        module:RegisterEvent("DISPLAY_SIZE_CHANGED", function()
            forced = true
            redraw()
        end)
        module:RegisterEvent("UI_SCALE_CHANGED", function()
            forced = true
            redraw()
        end)

        -- Entering the world, and for the same reason as the darkening.
        --
        -- The core applies the settings once, when the profile comes up,
        -- while PLAYER_ENTERING_WORLD arrives AFTER that — and behind it the
        -- game rebuilds the interface afresh: it recomputes UIParent's
        -- layout, returns its edges to their places, raises the windows. A
        -- bar placed before that went on standing while the space it had
        -- taken away was gone, and the panel behaved as though it did not
        -- exist.
        --
        -- From the armchair it looks like "it did not work on load but worked
        -- after any edit of the settings": an edit goes through this same
        -- repaint, only with the interface already finished. That is exactly
        -- what the author sent in.
        --
        -- The shift is recomputed forcibly: the number did not change, and
        -- without the flag the repaint would decide there was nothing to
        -- do.
        module:RegisterEvent("PLAYER_ENTERING_WORLD", function()
            forced = true
            redraw()
        end)

        -- The engine's refusal to protected code. Moving UIParent from
        -- unsafe code is a known source of such refusals, and there is no way
        -- to test it outside the client: taint does not exist there. So the
        -- module does not prove it is absent but recognises it when it
        -- arrives, and names the player a switch.
        local function noticeBlocked(_, who, what)
            if not Layout.Blame(who, ADDON, "Darken",
                (reservedTop + reservedBottom) > 0) then
                return
            end

            blocked = blocked + 1
            if blockedSaid then return end
            blockedSaid = true
            module:Print(string.format(ns.Localize("the game refused a "
                .. "protected action (%s) while the panel was holding screen "
                .. "space. If this keeps happening, turn off the setting "
                .. "that moves the interface out of the way, and the panel "
                .. "will draw over the interface instead."), tostring(what)))
        end

        module:RegisterEvent("ADDON_ACTION_BLOCKED", noticeBlocked)
        module:RegisterEvent("ADDON_ACTION_FORBIDDEN", noticeBlocked)
    end

    -- The first values are assembled here: the events will come later,
    -- while the panel is obliged to show numbers at once.
    refresh(Sources.LIST)
end

--- Stop drawing: give the screen back and hide the bars.
local function stop()
    if not drawing then return end
    drawing = false

    if listening then
        listening = false
        for _, event in ipairs(Sources.Events()) do
            module:UnregisterEvent(event)
        end
        module:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        module:UnregisterEvent("UI_SCALE_CHANGED")
        module:UnregisterEvent("PLAYER_ENTERING_WORLD")
        module:UnregisterEvent("ADDON_ACTION_BLOCKED")
        module:UnregisterEvent("ADDON_ACTION_FORBIDDEN")
    end

    shownNames = {}
    Panel.CloseMenu()
    reserve(0, 0)

    for _, side in ipairs({ "top", "bottom" }) do
        local frame = bars[side] or nil
        if frame then
            Panel.Drive(frame, nil)
            Panel.Show(frame, false)
        end
    end
end

--- The report on the screen space.
--
-- Written for one thing: moving UIParent has never once been carried out in a
-- live client, and when it is, the author must have a way of seeing what
-- exactly happened — in words rather than by the look of the screen. By the
-- look of it, "the panel stands and there is emptiness under it" and "the
-- panel stands and the shift is waiting for the fight to end" are the same,
-- and the first takes a week to fix.
--
-- The report names three different numbers (asked for, applied, waiting),
-- compares UIParent's live anchors with those the panel set last, and counts
-- the engine's refusals to protected code. None of that can be learnt outside
-- the game — which is why it is printed rather than tested.
-- @return table array of lines
function ns.Check()
    local settings = Settings()
    local lines = {}

    lines[#lines + 1] = (settings and settings.enabled)
        and ns.Localize("the panel is on")
        or ns.Localize("the panel is off")

    lines[#lines + 1] = (settings and settings.push)
        and ns.Localize("moving the interface out of the way is on")
        or ns.Localize("moving the interface out of the way is off")

    lines[#lines + 1] = string.format(ns.Localize(
        "asked for %d above and %d below"), reservedTop, reservedBottom)
    lines[#lines + 1] = string.format(ns.Localize(
        "applied %d above and %d below"), appliedTop, appliedBottom)

    if pending then
        lines[#lines + 1] = declined
            and string.format(ns.Localize("the change was refused: %s"),
                tostring(declined))
            or ns.Localize("the change is waiting for combat to end")
    end

    if refused then
        lines[#lines + 1] = ns.Localize("this client does not hold UIParent "
            .. "by its top or bottom edge, so nothing was moved")
    end

    -- The comparison is made against the live frame rather than a recorded
    -- answer: between our shift and this minute anybody at all could have
    -- touched UIParent, and that is precisely what has to be seen.
    if expected then
        local drift = Layout.Verify(expected, pointsOf(_G.UIParent))
        if drift then
            lines[#lines + 1] = string.format(ns.Localize(
                "UIParent is not where the panel left it: %s"), drift)
        else
            lines[#lines + 1] = ns.Localize(
                "UIParent is exactly where the panel left it")
        end
    end

    if mismatch then
        lines[#lines + 1] = string.format(ns.Localize(
            "the last move did not take: %s"), tostring(mismatch))
    end

    if blocked > 0 then
        lines[#lines + 1] = string.format(ns.Localize("the game refused a "
            .. "protected action %d times while the panel held screen space"),
            blocked)
    end

    local shown = 0
    for _ in pairs(shownNames) do shown = shown + 1 end
    lines[#lines + 1] = string.format(ns.Localize(
        "cells shown: %d of %d in the registry"), shown,
        #Broker.Names(broker))

    -- Next comes the state of the bars themselves. Three different "there is
    -- no bar" cases look the same from the armchair, and only this tells them
    -- apart.
    lines[#lines + 1] = (drawing and ns.Localize("the panel is drawing")
        or ns.Localize("the panel is not drawing"))

    lines[#lines + 1] = string.format(ns.Localize(
        "cells on the bars: %d above, %d below"), lastTop, lastBottom)

    for _, side in ipairs({ "top", "bottom" }) do
        local frame = bars[side]
        if frame == nil then
            lines[#lines + 1] = string.format(ns.Localize(
                "the %s bar was never built"), side)
        elseif frame == false then
            lines[#lines + 1] = string.format(ns.Localize(
                "the %s bar could not be built"), side)
        else
            local visible = type(frame.IsShown) == "function"
                and frame:IsShown() or false
            local height = type(frame.GetHeight) == "function"
                and frame:GetHeight() or 0
            local width = type(frame.GetWidth) == "function"
                and frame:GetWidth() or 0
            local alpha = type(frame.GetAlpha) == "function"
                and frame:GetAlpha() or 0

            -- The opacity is printed as a fraction rather than a
            -- percentage: turning fractions into percentages is the core's
            -- skill (Format.Percent), and a second such skill here would
            -- diverge from it on the rounding.
            lines[#lines + 1] = string.format(ns.Localize(
                "the %s bar: %s, %d by %d, opacity %.2f"), side,
                visible and ns.Localize("shown") or ns.Localize("hidden"),
                width, height, tonumber(alpha) or 0)

            local points = pointsOf(frame)
            if #points == 0 then
                lines[#lines + 1] = string.format(ns.Localize(
                    "the %s bar is anchored to nothing"), side)
            else
                for i = 1, #points do
                    local point = points[i]
                    lines[#lines + 1] = string.format(ns.Localize(
                        "the %s bar: %s at %d, %d"), side,
                        tostring(point[1]), tonumber(point[4]) or 0,
                        tonumber(point[5]) or 0)
                end
            end
        end
    end

    return lines
end

--- The cell names for the settings dropdown.
-- Assembled at the moment the list is opened: the registry is shared for the
-- session, and another addon may have created a readout after we loaded.
-- @return table name -> label
local function cellValues()
    local settings = Settings()
    local names = Broker.Names(broker)
    local arranged = Layout.Arrange(names, settings and settings.order)

    local out = {}
    for i = 1, #arranged do
        local name = arranged[i]
        -- The number in the label is not the order in the profile but the
        -- place in the row: the player rearranges the cells and has to see
        -- that they were rearranged.
        out[name] = i .. ". " .. name
    end
    return out
end

--- The selected cell, if it still exists.
-- @return string|nil
local function currentCell()
    local settings = Settings()
    local arranged = Layout.Arrange(Broker.Names(broker),
        settings and settings.order)

    for i = 1, #arranged do
        if arranged[i] == selected then return selected end
    end

    selected = arranged[1]
    return selected
end

--- Move the selected cell.
-- @param delta number
local function moveCell(delta)
    local settings = Settings()
    local name = currentCell()
    if not settings or not name then return end

    settings.order = Layout.Move(Broker.Names(broker), settings.order,
        name, delta)
    module:Apply()
end

local options = {
    type = "group",
    name = function() return ns.Localize("Darken Information Panel") end,
    args = {
        about = {
            type = "description",
            order = 1,
            width = "full",
            name = function() return ns.Localize("A bar of metrics at the "
                .. "edge of the screen: gold, durability, bag space, latency, "
                .. "frames, the clock, experience and reputation. It shows "
                .. "everything published to the LibDataBroker standard, so "
                .. "metrics from other addons you have installed appear here "
                .. "on the same footing as ours. Off by default - a fresh "
                .. "install changes nothing.") end,
        },
        enabled = {
            type = "toggle",
            order = 2,
            width = "full",
            name = function() return ns.Localize("Show the Panel") end,
            -- The panel is two bars, and without this line the player
            -- reads three switches in a row without knowing how they are
            -- connected.
            desc = function() return ns.Localize("The panel is two bars - "
                .. "one at the top of the screen, one at the bottom - and "
                .. "the two switches below say which of them are drawn. Off "
                .. "by default; with both bars off nothing is drawn "
                .. "either.") end,
            get = function()
                local settings = Settings()
                return settings and settings.enabled or false
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.enabled = value and true or false
                module:Apply()
            end,
        },
        top = {
            type = "toggle",
            order = 3,
            name = function() return ns.Localize("Top Bar") end,
            get = function()
                local settings = Settings()
                return settings and settings.top or false
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.top = value and true or false
                module:Apply()
            end,
        },
        bottom = {
            type = "toggle",
            order = 4,
            name = function() return ns.Localize("Bottom Bar") end,
            get = function()
                local settings = Settings()
                return settings and settings.bottom or false
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.bottom = value and true or false
                module:Apply()
            end,
        },
        cells = {
            type = "group",
            order = 5,
            inline = true,
            name = function() return ns.Localize("Cells") end,
            args = {
                hint = {
                    type = "description",
                    order = 0,
                    width = "full",
                    name = function() return ns.Localize("The same three "
                        .. "things are on the bar itself: right-click a cell "
                        .. "to hide it, move it or send it to the other bar. "
                        .. "Left-click belongs to the metric - it does "
                        .. "whatever the addon that published it does, and "
                        .. "that is the same for ours and for other addons'.") end,
                },
                cell = {
                    type = "select",
                    order = 1,
                    width = "full",
                    name = function() return ns.Localize("Cell") end,
                    desc = function() return ns.Localize("Every metric in the "
                        .. "list comes from the same place - ours and other "
                        .. "addons' alike. The number is its place in the "
                        .. "row.") end,
                    values = cellValues,
                    get = function() return currentCell() end,
                    set = function(_, value) selected = value end,
                },
                shown = {
                    type = "toggle",
                    order = 2,
                    name = function() return ns.Localize("Show This Cell") end,
                    get = function()
                        local settings = Settings()
                        local name = currentCell()
                        if not settings or not name then return false end
                        return not (settings.hidden and settings.hidden[name])
                    end,
                    set = function(_, value)
                        local settings = Settings()
                        local name = currentCell()
                        if not settings or not name then return end
                        settings.hidden = settings.hidden or {}
                        settings.hidden[name] = (not value) and true or nil
                        module:Apply()
                    end,
                },
                side = {
                    type = "select",
                    order = 3,
                    name = function() return ns.Localize("Which Bar") end,
                    values = function()
                        return {
                            top = ns.Localize("Top"),
                            bottom = ns.Localize("Bottom"),
                        }
                    end,
                    get = function()
                        local settings = Settings()
                        local name = currentCell()
                        if not settings or not name then return "top" end
                        local side = settings.sides and settings.sides[name]
                        return Layout.SIDES[side] and side
                            or settings.defaultSide or "top"
                    end,
                    set = function(_, value)
                        local settings = Settings()
                        local name = currentCell()
                        if not settings or not name then return end
                        if not Layout.SIDES[value] then return end
                        settings.sides = settings.sides or {}
                        settings.sides[name] = value
                        module:Apply()
                    end,
                },
                earlier = {
                    type = "execute",
                    order = 4,
                    name = function() return ns.Localize("Move Earlier") end,
                    func = function() moveCell(-1) end,
                },
                later = {
                    type = "execute",
                    order = 5,
                    name = function() return ns.Localize("Move Later") end,
                    func = function() moveCell(1) end,
                },
            },
        },
        look = {
            type = "group",
            order = 6,
            inline = true,
            name = function() return ns.Localize("Bar and Formats") end,
            args = {
                height = {
                    type = "range",
                    order = 1,
                    name = function() return ns.Localize("Bar Height") end,
                    min = Layout.BOUNDS.height.min,
                    max = Layout.BOUNDS.height.max,
                    step = 1,
                    get = function()
                        local settings = Settings()
                        return settings and settings.height
                    end,
                    set = function(_, value)
                        local settings = Settings()
                        if not settings then return end
                        settings.height = value
                        module:Apply()
                    end,
                },
                push = {
                    type = "toggle",
                    order = 2,
                    width = "full",
                    name = function() return ns.Localize("Move the Interface "
                        .. "Out of the Way") end,
                    desc = function() return ns.Localize("On, the bar takes "
                        .. "its height away from the rest of the interface, "
                        .. "which moves in by that much and stays fully "
                        .. "visible. Off, the bar draws over whatever is "
                        .. "underneath it.") end,
                    get = function()
                        local settings = Settings()
                        return settings and settings.push or false
                    end,
                    set = function(_, value)
                        local settings = Settings()
                        if not settings then return end
                        settings.push = value and true or false
                        module:Apply()
                    end,
                },
                clock12 = {
                    type = "toggle",
                    order = 3,
                    name = function() return ns.Localize("12-Hour Clock") end,
                    get = function()
                        local settings = Settings()
                        return settings and settings.clock12 or false
                    end,
                    set = function(_, value)
                        local settings = Settings()
                        if not settings then return end
                        settings.clock12 = value and true or false
                        module:Apply()
                    end,
                },
                clockSeconds = {
                    type = "toggle",
                    order = 4,
                    name = function() return ns.Localize("Show Seconds") end,
                    get = function()
                        local settings = Settings()
                        return settings and settings.clockSeconds or false
                    end,
                    set = function(_, value)
                        local settings = Settings()
                        if not settings then return end
                        settings.clockSeconds = value and true or false
                        module:Apply()
                    end,
                },
                xpMode = {
                    type = "select",
                    order = 5,
                    name = function() return ns.Localize("Experience Shown As") end,
                    values = function()
                        return {
                            current = ns.Localize("Current and Maximum"),
                            percent = ns.Localize("Percent"),
                            remaining = ns.Localize("Remaining"),
                        }
                    end,
                    get = function()
                        local settings = Settings()
                        return settings and settings.xpMode or "current"
                    end,
                    set = function(_, value)
                        local settings = Settings()
                        if not settings or not Format.XP_MODES[value] then return end
                        settings.xpMode = value
                        module:Apply()
                    end,
                },
                repMode = {
                    type = "select",
                    order = 6,
                    name = function() return ns.Localize("Reputation Shown As") end,
                    values = function()
                        return {
                            current = ns.Localize("Current and Maximum"),
                            percent = ns.Localize("Percent"),
                        }
                    end,
                    get = function()
                        local settings = Settings()
                        return settings and settings.repMode or "current"
                    end,
                    set = function(_, value)
                        local settings = Settings()
                        if not settings then return end
                        if value ~= "current" and value ~= "percent" then return end
                        settings.repMode = value
                        module:Apply()
                    end,
                },
            },
        },
    },
}

local handle, reason = Darken:RegisterModule({
    name = "umbrainfo",
    api  = API,

    -- The defaults: the panel is off. A fresh install changes nothing on
    -- screen, and everything else here is the state the panel will be in when
    -- it is first switched on: the top bar, every cell shown, the interface
    -- shift on.
    defaults = {
        enabled = false,
        top = true,
        bottom = false,
        height = Layout.BOUNDS.height.default,
        push = true,
        defaultSide = "top",
        opacity = Layout.BOUNDS.opacity.default,
        order = {},
        hidden = {},
        sides = {},
        clock12 = false,
        clockSeconds = false,
        xpMode = "current",
        repMode = "current",
    },

    options = options,

    OnEnable = function(self)
        module = module or self

        -- The game's container functions are asked of the core here: while
        -- the file is read the core has not yet determined the client, and
        -- the door would answer with emptiness forever. Once, rather than
        -- once per bag.
        env.BindGame()

        self:RegisterCommand("info", function(rest)
            -- The word "check" prints the report on the screen space and
            -- changes nothing. It has to be read in the client, because only
            -- there does the UIParent shift happen at all.
            if type(rest) == "string" and rest:match("^%s*check%s*$") then
                for _, line in ipairs(ns.Check()) do self:Print(line) end
                return
            end

            local settings = self:GetSettings()
            if not settings then return end
            settings.enabled = not settings.enabled
            self:Apply()
            self:Print(settings.enabled
                and ns.Localize("information panel on")
                or  ns.Localize("information panel off"))
        end)
    end,

    ApplySettings = function(self)
        module = module or self

        local settings = self:GetSettings()
        if not settings then return end

        if not settings.enabled then
            stop()
            return
        end

        start()

        -- The real library may have appeared after us — as an addon loaded
        -- on demand. Our readouts then move into it, and other people's
        -- become visible without a reload of the interface.
        local moved
        broker, moved = Broker.Acquire(_G.LibStub, broker)
        if moved then published = Sources.Publish(broker) end

        refresh(Sources.LIST)
        redraw()
    end,

    OnDisable = function()
        -- A disabled module is obliged to give the screen back as it was and
        -- to stop drawing: the core removes the game-event subscriptions,
        -- while the tick and the space taken away are ours.
        stop()

        -- The menu's name is taken out of the shared Escape list regardless
        -- of whether we drew anything at all: the game's list outlives the
        -- module being switched off, and a name left in it is our rubbish in
        -- somebody else's table until the interface is reloaded.
        Panel.CloseMenu()
        Panel.Dismissable(false)
    end,
})

if not handle then return end

module = handle

for locale, strings in pairs(ns.Strings or {}) do
    module:RegisterStrings(locale, strings)
end

--============================================================================
-- The settings page, declared as data
--============================================================================

-- The list of cells is declared as a widget: a cell is not a setting but a
-- row of the registry that the player hides, moves and sends to the other bar.
-- As three separate settings it would scatter into three questions about one
-- thing. The loophole is deliberately narrow: the window still does not know
-- what is inside.

if type(core.Schema) == "table" then
    local Schema = core.Schema
    local PAGE = "umbrainfo"

    Schema.Page(PAGE, {
        title = "Information Panel",
        order = 11,
        section = "umbrainfo",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show the Panel",
        path = { "enabled" },
        apply = "umbrainfo",
        hint = "A bar of metrics at the edge of the screen. It draws at the "
            .. "screen edge and takes the space it needs from the interface "
            .. "below it.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Top Bar",
        path = { "top" },
        apply = "umbrainfo",
        hint = "Use the bar along the top of the screen.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Bottom Bar",
        path = { "bottom" },
        apply = "umbrainfo",
        hint = "Use the bar along the bottom of the screen. Switching it on "
            .. "is not enough by itself: a bar draws the cells that sit on "
            .. "it, and every cell starts on the bar chosen below. Send "
            .. "cells to it one at a time in the list further down, or "
            .. "change that choice to move them all at once.",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Cells Go To",
        path = { "defaultSide" },
        apply = "umbrainfo",
        hint = "Which bar a cell uses when you have not sent it to one "
            .. "yourself. Changing this moves every cell you have not "
            .. "placed by hand.",
        values = function()
            return {
                { key = "top", text = ns.Localize("Top") },
                { key = "bottom", text = ns.Localize("Bottom") },
            }
        end,
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Opacity",
        path = { "opacity" },
        min = Layout.BOUNDS.opacity.min,
        max = Layout.BOUNDS.opacity.max,
        step = 1,
        apply = "umbrainfo",
        hint = "How solid the bar is. It never goes all the way to "
            .. "invisible: a bar you cannot see is a bar that is switched "
            .. "off, and that is the checkbox above.",
    })

    Schema.Add(PAGE, { kind = "header", label = "Cells" })

    Schema.Add(PAGE, {
        kind = "note",
        hint = "Hiding, moving and sending a cell to the other bar can also "
            .. "be done on the bar itself, by right-clicking the cell. "
            .. "Left-click belongs to the metric - it does whatever the "
            .. "addon that published it does, and that is the same for ours "
            .. "and for other addons'. A hidden cell is the one thing the "
            .. "bar cannot undo: it is not on the bar to be clicked.",
    })

    --========================================================================
    -- The list of cells
    --========================================================================

    -- Hiding, moving and sending to the other bar can also be done on the
    -- bar itself, by right-clicking a cell. It is repeated here for one
    -- reason: a HIDDEN cell cannot be reached by a right click — it is not on
    -- the bar. Without the list in the window, "hide" would be a one-way
    -- door.
    --
    -- Cells cannot be created or taken away, and those buttons are not here at
    -- all: the readouts come from the standard's registry, and addons publish
    -- them, not the player. An "Add" button that does nothing is the kind of
    -- failure a player takes for a mistake of their own.

    if type(core.ListEditor) == "table" then
        --- The cells in their current order, as records for the editor.
        local function entries()
            local settings = Settings()
            local arranged = Layout.Arrange(Broker.Names(broker),
                settings and settings.order)

            local out = {}
            for i = 1, #arranged do out[i] = { name = arranged[i] } end
            return out
        end

        Schema.Add(PAGE, {
            kind = "widget",
            label = "Cell",
            build = core.ListEditor.Build,
            hook = {
                Entries = entries,

                -- Move it. Layout.Move computes the order and returns it as
                -- a new array — the caller is obliged to store it, and that
                -- is here.
                Move = function(name, delta)
                    local settings = Settings()
                    if not settings or type(name) ~= "string" then return end

                    settings.order = Layout.Move(Broker.Names(broker),
                        settings.order, name, delta)
                    if module ~= nil then module:Apply() end
                end,

                Fields = function(chosen)
                    if chosen == nil then return {} end

                    local rows = {}

                    rows[#rows + 1] = {
                        kind = "toggle",
                        label = "Show This Cell",
                        apply = "none",
                        hint = "A hidden cell cannot be brought back from "
                            .. "the bar itself - it is not on it. This is "
                            .. "the way back.",
                        get = function()
                            local settings = Settings()
                            if not settings then return false end
                            return not (settings.hidden
                                and settings.hidden[chosen])
                        end,
                        set = function(value)
                            local settings = Settings()
                            if not settings then return end
                            settings.hidden = settings.hidden or {}
                            -- nil rather than false: hidden ones are a
                            -- handful, and storing "not hidden" for every
                            -- shown one means writing the whole registry into
                            -- the saved variables.
                            settings.hidden[chosen] =
                                (not value) and true or nil
                            if module ~= nil then module:Apply() end
                        end,
                    }

                    rows[#rows + 1] = {
                        kind = "select",
                        label = "Which Bar",
                        apply = "none",
                        hint = "Which of the two bars this cell sits on. A "
                            .. "cell sent to a bar that is switched off is "
                            .. "not drawn at all.",
                        values = function()
                            return {
                                { key = "top", text = ns.Localize("Top") },
                                { key = "bottom",
                                  text = ns.Localize("Bottom") },
                            }
                        end,
                        get = function()
                            local settings = Settings()
                            if not settings then return "top" end
                            local side = settings.sides
                                and settings.sides[chosen]
                            if Layout.SIDES[side] then return side end
                            return settings.defaultSide or "top"
                        end,
                        set = function(value)
                            local settings = Settings()
                            if not settings or not Layout.SIDES[value] then
                                return
                            end
                            settings.sides = settings.sides or {}
                            settings.sides[chosen] = value
                            if module ~= nil then module:Apply() end
                        end,
                    }

                    return rows
                end,
            },
        })
    end

    Schema.Add(PAGE, { kind = "header", label = "Bar and Formats" })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Bar Height",
        path = { "height" },
        min = Layout.BOUNDS.height.min,
        max = Layout.BOUNDS.height.max,
        step = 1,
        apply = "umbrainfo",
        hint = "How tall the bar is.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Move the Interface Out of the Way",
        path = { "push" },
        apply = "umbrainfo",
        hint = "Take the bar's height away from the screen so nothing "
            .. "hides under it. On a client that does not let the addon "
            .. "move the interface, the bar draws over it instead and says "
            .. "so.",
    })

    -- How experience and reputation are written. Two settings rather than
    -- one: experience has three forms, reputation two — "how much is left"
    -- means nothing for reputation, because it is not earned towards the next
    -- level but towards the next standing, and that is a different number.
    Schema.Add(PAGE, {
        kind = "select",
        label = "Experience Shown As",
        path = { "xpMode" },
        apply = "umbrainfo",
        values = function()
            return {
                { key = "current",
                  text = ns.Localize("Current and Maximum") },
                { key = "percent", text = ns.Localize("Percent") },
                { key = "remaining", text = ns.Localize("Remaining") },
            }
        end,
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Reputation Shown As",
        path = { "repMode" },
        apply = "umbrainfo",
        values = function()
            return {
                { key = "current",
                  text = ns.Localize("Current and Maximum") },
                { key = "percent", text = ns.Localize("Percent") },
            }
        end,
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "12-Hour Clock",
        path = { "clock12" },
        apply = "umbrainfo",
        hint = "Write the time as twelve hours instead of twenty-four.",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show Seconds",
        path = { "clockSeconds" },
        apply = "umbrainfo",
        hint = "Write seconds in the clock cell.",
    })
end
