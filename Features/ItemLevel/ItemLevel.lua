local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("itemlevel")

-- An item's level over its icon: in the character window, in the inspection
-- of somebody else's character, and in the bags.
--
-- The file glues three parts together and does nothing else: the rules
-- (Level.lua), the ledger of deferred repaints (Pending.lua), the display
-- (Display.lua). The module is not part of the core — it lives in a folder of
-- its own and speaks to the core only through the public contract
-- (docs/module-api.md).
--
-- === The three rules that must not be broken here ===
--
-- The information does not arrive at once. The first question about an unknown
-- item returns zero, and that is not "it has no level" but "I do not know
-- yet". Such a place becomes a deferred repaint (Pending) and is drawn on the
-- GET_ITEM_INFO_RECEIVED event. There are no empty slots in the module that
-- nobody will remember — that is written in the specification as a paragraph
-- of its own, because a mistake here looks accidental and cannot be found from
-- a bug report.
--
-- The client decides whether it means anything, not the build number. On
-- vanilla and TBC an item's level decides nothing, and the settings section is
-- hidden there. Level.Meaningful makes the decision by the presence of game
-- objects — the same principle the core's compatibility layer lives by.
--
-- The icon already has an owner. The core styles a bag slot, and the bags
-- module replaces it entirely; the equipment slots belong to the game. The
-- module touches nothing on a foreign button but its own font string in a
-- field carrying its own prefix, and takes nothing away from anybody — which
-- is why there is no handle:Replaces here and must not be.

-- The core is not taken on trust even through the TOC's dependency line: the
-- behaviour of "## Dependencies" on classic clients is unconfirmed, and the
-- core's absence has to give one readable line rather than a Lua error.
if type(Darken) ~= "table" or type(Darken.RegisterModule) ~= "function" then
    print("|cffff4040" .. ADDON .. "|r: Darken is not loaded, so this addon "
        .. "does nothing. Install Darken, or disable this addon.")
    return
end

-- The contract version the module is written against. The twelfth: event
-- subscriptions and strings of one's own appeared in the third, the core's
-- fonts (GetMedia) and a slash-command word in the fourth, and the edge name
-- in the scale of insets in the twelfth. The module has no saved data of its
-- own, every setting lies in the profile; the declaration was raised not for
-- their sake but for the name without which there is nowhere to take the
-- number's inset from. The declaration is the refusal: a core of versions 4 to
-- 11 will not register the module and will say so in words, instead of
-- silently putting the number flush against the icon's border.
--
-- The nineteenth is the Darken:GetGameFunction door: which of the two
-- spellings this client calls reading a bag slot's link by (C_Container or a
-- global) is now decided by the core's compatibility layer. On cores of
-- version 18 and older the door is absent, and the numbers over the items in
-- the bags would not appear at all — silently; a refusal at registration is
-- more honest.
local API = 19

local module

--- Translate one of the module's strings.
-- The dictionary and the choice of language belong to the core (the contract,
-- the section on one's own strings). The wrapper exists because the file is
-- read before the core hands over the descriptor.
-- @param key string|nil the English string that serves as the key
-- @return string
function ns.Localize(key)
    if module ~= nil then return module:Localize(key) end
    if key == nil or key == "" then return "" end
    return key
end

--- The core's skin right now.
--
-- Asked for on every application rather than remembered while the file is
-- read. A plain assignment of Darken:GetSkin() used to stand here, and on the
-- current core it made no difference: the door is defined by the moment our
-- files are read, and behind the door is one and the same table. The
-- contract's rule is nevertheless to ask: a remembered skin outlives a change
-- of palette silently, and the number on a slot would stay painted the old way
-- beside a window painted the new way.
--
-- @return table|nil
local function currentSkin()
    if type(Darken.GetSkin) ~= "function" then return nil end

    local ok, skin = pcall(Darken.GetSkin, Darken)
    if not ok or type(skin) ~= "table" then return nil end

    return skin
end

--- The core's media right now. The same way and for the same reason.
-- @return table|nil
local function currentMedia()
    if type(Darken.GetMedia) ~= "function" then return nil end

    local ok, media = pcall(Darken.GetMedia, Darken)
    if not ok or type(media) ~= "table" then return nil end

    return media
end

--- The number's inset from the icon's edge.
-- From the skin's scale of insets rather than as a number: one and the same
-- distance on screen is set by one value. Asked for at the same time as the
-- skin itself, and for the same reason.
--
-- The name is edge, "a label at the edge" (the contract, version 12). What
-- used to stand here was hair, the thickness of a hairline: it gave a suitable
-- number, but by accident — both quantities are small. A label pushed in by
-- exactly the border's thickness stands flush against the border, and an edit
-- of either quantity for its own reasons would move the other along with it,
-- silently. The stack counter on an aura icon, the level on a nameplate, the
-- item counter in a bag slot and the labels on bars all ask for the same
-- quantity under the same name — it is one distance for the whole addon.
--
-- The sign belongs to the corner and is applied in Level.Anchor rather than
-- here.
--
-- The two is the answer to "there is no skin at all" rather than a second
-- record of the quantity: the tests, which have no core beside them, take that
-- path.
-- @return number
local function insetOf(skin)
    if type(skin) ~= "table" or type(skin.Metrics) ~= "function" then
        return 2
    end
    return tonumber(skin.Metrics().edge) or 2
end

--- The number's fallback colour — the ordinary text colour from the core's
--- palette.
-- The number is painted with it as well when colouring by quality is switched
-- off. One table, rewritten in place: the colour is asked for on every slot,
-- and a new table per slot would cost the player frames.
-- @param skin table|nil
-- @param out table the table to write into
-- @return table the same table
local function fallbackColor(skin, out)
    out.r, out.g, out.b = 1, 1, 1
    if type(skin) ~= "table" or type(skin.Color) ~= "function" then
        return out
    end

    local r, g, b = skin.Color("text")
    if r then out.r, out.g, out.b = r, g, b end
    return out
end

-- The ledger of deferred repaints and the ledger of buttons we have
-- touched.
local pending  = ns.Pending.New()
local registry = ns.Display.NewRegistry()

-- Whether we are drawing right now. Separate from the setting: the event
-- handlers and the foreign functions we stood behind go on calling us after
-- the player has switched the display off.
local drawing = false

-- The hot path's reused tables. There are dozens of slots in a bag, and a
-- table per slot would cost the player frames.
local style = {}
local tint  = { fallback = {} }

--- Call a foreign object's method if it exists.
local function call(object, method, ...)
    if type(object) ~= "table" and type(object) ~= "userdata" then return nil end
    local fn = object[method]
    if type(fn) ~= "function" then return nil end

    local ok, a = pcall(fn, object, ...)
    if not ok then return nil end
    return a
end

--- A game function by name, in its new or its old location.
--
-- It stayed for the item lookups, and for them alone. The container functions
-- have left here: which spelling a client calls them by is decided by the
-- core's compatibility layer (the container-item-link group), because that is
-- a difference between the supported clients — the early line keeps them as
-- globals, the late one folded them into the C_Container table.
--
-- GetItemInfo and its neighbours are not such a difference: the global exists
-- on all three supported clients, and C_Item here is a guess about a client we
-- do not support. Putting what does not differ into the layer would turn it
-- into a reference of the game's API: it is about differences, not about
-- everything the module calls.
--
-- @param name string
-- @param namespaces table array of host-table names
-- @return function|nil
local function gameFunction(name, namespaces)
    local fn = _G[name]
    if type(fn) == "function" then return fn end

    for i = 1, #namespaces do
        local holder = _G[namespaces[i]]
        if type(holder) == "table" and type(holder[name]) == "function" then
            return holder[name]
        end
    end

    return nil
end

local ITEM_HOLDERS = { "C_Item" }

-- The layer group in which both spellings of reading a bag slot's link are
-- declared. This is a word of the core's contract (docs/module-api.md, section
-- 11) rather than the name of a foreign function.
local BAG_LINK = "container-item-link"

-- The resolved function and the "already asked" mark. Two variables rather
-- than one: a client on which neither spelling exists would otherwise ask the
-- door for every slot under the cursor.
local bagLink, bagLinkAsked

--- Reading a bag slot's link — by whichever spelling exists on this client.
--
-- Asked of the core once: the tooltip over a slot comes up on every movement
-- of the cursor, and walking the group for each would be paying for nothing.
-- Both spellings answer the same way, so the shape of the answer is not
-- named.
--
-- @param door function|nil a door of the shape door(group) -> function
-- @return function|nil
local function bagLinkFunction(door)
    if bagLinkAsked then return bagLink end
    bagLinkAsked = true

    if type(door) ~= "function" then
        if type(Darken) ~= "table"
            or type(Darken.GetGameFunction) ~= "function" then return nil end
        door = function(g, s) return Darken:GetGameFunction(g, s) end
    end

    local ok, fn = pcall(door, BAG_LINK)
    if ok and type(fn) == "function" then bagLink = fn end
    return bagLink
end

--- Ask the core afresh. Called when the module is enabled.
-- @param door function|nil
-- @return function|nil
function ns.BindGame(door)
    bagLink, bagLinkAsked = nil, false
    return bagLinkFunction(door)
end

--- The module's settings.
-- @return table|nil
local function Settings()
    return module and module:GetSettings() or nil
end

--- The link of the item lying in this place.
-- @param target table the place's record
-- @return string|nil
local function linkOf(target)
    if target.kind == "bag" then
        local fn = bagLinkFunction()
        if not fn then return nil end
        local ok, link = pcall(fn, target.container, target.slot)
        return ok and link or nil
    end

    local fn = gameFunction("GetInventoryItemLink", ITEM_HOLDERS)
    if not fn then return nil end
    local ok, link = pcall(fn, target.unit, target.slot)
    return ok and link or nil
end

--- The item's detailed level, upgrades included.
-- @param link string
-- @return number|nil
local function detailedOf(link)
    local fn = gameFunction("GetDetailedItemLevelInfo", ITEM_HOLDERS)
    if not fn then return nil end

    local ok, value = pcall(fn, link)
    return ok and value or nil
end

--- The level and the quality out of the item's general information.
--
-- This same call is what makes the client ask the server about an unknown
-- item: there is no separate "request the information" on the supported
-- clients, and the readiness event arrives precisely after such a question.
--
-- @param link string
-- @return number|nil the level
-- @return number|nil the quality
local function basicOf(link)
    local fn = gameFunction("GetItemInfo", ITEM_HOLDERS)
    if not fn then return nil, nil end

    local ok, _, _, quality, itemLevel = pcall(fn, link)
    if not ok then return nil, nil end
    return itemLevel, quality
end

--- Draw one place.
--
-- The only path to the display. The sweeps, the events and the foreign
-- functions we stood behind all converge here, and the pure rule Level.Decide
-- makes the decision: show, defer until the information is ready, or clear.
--
-- @param target table { kind, key, button, container/slot or unit/slot }
local function draw(target)
    if not drawing then return end

    local button = target.button
    local link = linkOf(target)
    local detailed, basic, quality

    if link then
        detailed = detailedOf(link)
        basic, quality = basicOf(link)
    end

    local verdict, value = ns.Level.Decide(link, detailed, basic)

    if verdict == "wait" then
        -- The information is on its way. The place does not "stay empty":
        -- it is recorded under the item's id and will be drawn on the
        -- readiness event.
        ns.Display.Clear(button)
        ns.Pending.Remember(pending, value, target.key, target)
        return
    end

    ns.Pending.Forget(pending, target.key)

    if verdict ~= "show" then
        ns.Display.Clear(button)
        return
    end

    local settings = Settings()
    local skin = currentSkin()

    tint.byQuality = settings and settings.quality and true or false
    tint.quality   = quality
    tint.colors    = _G.ITEM_QUALITY_COLORS
    fallbackColor(skin, tint.fallback)

    local point, x, y = ns.Level.Anchor(settings and settings.position,
        insetOf(skin))

    style.text  = ns.Level.Format(value)
    style.r, style.g, style.b = ns.Level.Color(tint)
    style.point, style.x, style.y = point, x, y
    style.size  = ns.Level.ClampSize(settings and settings.size)
    style.media = currentMedia()
    style.category = (settings and settings.font) or "hotkey"

    ns.Display.Show(registry, button, style)
end

-- The equipment slots. The core's groups rather than a list of foreign names
-- of our own: the compatibility layer is declared the only place that knows
-- Blizzard's frame names, and a second copy of nineteen names would diverge
-- from the client at the very first patch — silently, because the numbers
-- would simply stop appearing.
--
-- The core returns only those names that something stands behind on this
-- client, so a window that does not exist does not exist for the module.
local EQUIPMENT_GROUPS = {
    character = "equipment-slots",
    inspect   = "equipment-slots-inspect",
}

--- The equipment slot's number for a button.
--
-- Asked of the button itself: it knows its slot, because the game sets the
-- number on it at creation. The number used to be computed first by a game
-- function from the slot's name, but such a name is foreign knowledge just as
-- a frame's name is, and it cannot live beside the core's groups. The rule is
-- the same one the bag slots are walked by: a child knows its own number, and
-- asking it is more reliable than assembling a second piece of knowledge about
-- somebody else's window.
--
-- A zero means "there is no number": the game has no slot with that number,
-- while in Lua a zero is truthy, and without this check an empty button would
-- reach the drawing.
-- @param button table
-- @return number|nil
local function slotNumber(button)
    local id = tonumber(call(button, "GetID"))
    if id and id > 0 then return id end
    return nil
end

--- Sweep the equipment slots of one window.
-- @param which string the EQUIPMENT_GROUPS key: character or inspect
-- @param unit string the unit whose equipment is being read
local function sweepEquipment(which, unit)
    if not drawing then return end
    if type(unit) ~= "string" or unit == "" then return end

    local group = EQUIPMENT_GROUPS[which]
    if not group then return end

    -- The frames are taken as the door's second answer (contract 18) rather
    -- than by looking a name up in _G. A name in a group can be a path into a
    -- foreign frame, and _G[path] is nil: the module would silently stop
    -- drawing, with nobody to say so. The door returns the object itself and
    -- removes the question entirely.
    local names, objects = Darken:GetFrameNames(group)
    for i = 1, #names do
        local name = names[i]
        local button = objects[i]

        if type(button) == "table" then
            local slot = slotNumber(button)
            if slot then
                draw({
                    kind = "inventory",
                    key = name,
                    button = button,
                    unit = unit,
                    slot = slot,
                })
            end
        end
    end
end

--- The unit whose equipment the inspection window is showing.
-- The window's name belongs to the core as well: the inspect-window group.
-- @return string|nil
local function inspectUnit()
    -- The frame itself rather than the name: see sweepEquipment above.
    local _, objects = Darken:GetFrameNames("inspect-window")
    local frame = objects[1]
    local unit = frame and frame.unit
    if type(unit) == "string" and unit ~= "" then return unit end

    -- The inspection window exists but has no unit recorded on it: the
    -- target is being inspected.
    if type(UnitExists) == "function" then
        local ok, exists = pcall(UnitExists, "target")
        if ok and exists then return "target" end
    end

    return nil
end

--- The slot buttons of one of the game's bag windows.
--
-- A walk over the children rather than an assembly of names: a slot button's
-- name is made of the window's name plus a suffix, and that suffix is foreign
-- knowledge just as a frame's name is. A child knows its own slot number, and
-- asking it is more reliable than guessing.
--
-- @param frame table the bag window
local function sweepBagFrame(frame)
    if not drawing then return end
    if type(frame) ~= "table" then return end

    local container = tonumber(call(frame, "GetID"))
    if not container then return end
    if type(frame.GetChildren) ~= "function" then return end

    local packed = { pcall(frame.GetChildren, frame) }
    if not packed[1] then return end

    for i = 2, #packed do
        local child = packed[i]
        if type(child) == "table"
            and type(child.GetID) == "function"
            and type(child.CreateFontString) == "function" then

            local slot = tonumber(call(child, "GetID"))
            local name = call(child, "GetName")
            local looksLikeSlot = child.icon ~= nil
                or (type(name) == "string" and name:match("Item%d+$") ~= nil)

            if slot and looksLikeSlot then
                draw({
                    kind = "bag",
                    key = "bag:" .. container .. ":" .. slot,
                    button = child,
                    container = container,
                    slot = slot,
                })
            end
        end
    end
end

--- Sweep the game's bag windows — the ones the core styles.
local function sweepGameBags()
    if not drawing then return end

    -- The windows themselves rather than the names: see sweepEquipment
    -- above.
    local names, objects = Darken:GetFrameNames("bag-window")
    for i = 1, #names do
        local frame = objects[i]
        if type(frame) == "table" and call(frame, "IsShown") then
            sweepBagFrame(frame)
        end
    end
end

-- The slots of the bags module's window: the key of the core's display case
-- under which that module lays them out.
--
-- The window used to be found by a global name, and an item's place was read
-- out of the button's protected attribute. That cost two defects, and both
-- were recorded honestly: there was no witness of the repaint at all — the
-- order of two handlers of one event is not defined, and our number lagged
-- behind until the next change of the bags; and an attribute is edited
-- deferred in combat, so a slot the neighbour had not managed to mark looked
-- empty to us until combat ended.
--
-- Now the neighbour lays out onto the core's display case a list of its slots
-- — the button and the place of the item in it — and does so at the end of
-- every repaint of its window. The display case is itself the witness: the
-- subscription below calls us after it has finished rather than racing it. The
-- item's place arrives as an ordinary table and does not depend on combat at
-- all.
local BAGS_SLOTS = "umbrabags.slots"

--- Sweep the slots of the bags module's window.
--
-- The list belongs to the neighbour, and it must not be taken on trust: the
-- contract explicitly tells a subscriber to check a foreign object's shape
-- itself. An entry without a button is skipped; an entry marked as hidden is
-- cleared along with its pending repaint; an entry without the item's place is
-- not lost yet — the place can be asked of the button itself, through the
-- attribute it uses the item by on a click.
local function sweepModuleBags()
    if not drawing then return end
    if not module then return end

    local slots = module:GetFrame(BAGS_SLOTS)
    if type(slots) ~= "table" then return end

    for i = 1, #slots do
        local entry = slots[i]
        local button = type(entry) == "table" and entry.button or nil

        if type(button) == "table" then
            local key = "umbrabags:" .. i
            local container, slot

            if entry.shown ~= false then
                container = tonumber(entry.container)
                slot = tonumber(entry.slot)

                if not (container and slot) then
                    container, slot = ns.Level.ParseItemAttribute(
                        call(button, "GetAttribute", "item"))
                end
            end

            if container and slot then
                draw({
                    kind = "bag",
                    key = key,
                    button = button,
                    container = container,
                    slot = slot,
                })
            else
                ns.Pending.Forget(pending, key)
                ns.Display.Clear(button)
            end
        end
    end
end

--- Sweep the bags of both kinds.
local function sweepBags()
    sweepGameBags()
    sweepModuleBags()
end

--- Sweep everything that is on screen right now.
local function sweepAll()
    if not drawing then return end

    sweepEquipment("character", "player")

    local unit = inspectUnit()
    if unit then sweepEquipment("inspect", unit) end

    sweepBags()
end

--- Stop drawing and take every number away.
local function stop()
    drawing = false
    ns.Pending.Wipe(pending)
    ns.Display.HideAll(registry)
end

-- The events and their handlers. The subscription goes through the core (the
-- contract, the section on game events): a receiver frame of our own would
-- deprive the module of its protection and would turn an error in a handler
-- into a yellow error bearing Darken's name.
local EVENTS = {
    -- The item's information is ready. The whole of Pending.lua is written
    -- for this line: here and only here do the numbers appear that were not
    -- there during the first sweep.
    { "GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
        if not drawing then return end

        local targets = ns.Pending.Take(pending, itemID)
        if success == false then
            -- The item does not exist: the server answered with a refusal.
            -- The places are cleared and not deferred again — otherwise they
            -- would wait forever.
            for i = 1, #targets do ns.Display.Clear(targets[i].button) end
            return
        end

        for i = 1, #targets do draw(targets[i]) end
    end },

    { "PLAYER_ENTERING_WORLD",    function() sweepAll() end },
    { "PLAYER_EQUIPMENT_CHANGED", function() sweepEquipment("character", "player") end },
    { "UNIT_INVENTORY_CHANGED",   function(_, unit)
        if unit == "player" then sweepEquipment("character", "player") end

        local inspected = inspectUnit()
        if inspected and unit == inspected then
            sweepEquipment("inspect", inspected)
        end
    end },
    { "INSPECT_READY", function()
        local unit = inspectUnit()
        if unit then sweepEquipment("inspect", unit) end
    end },
    { "BAG_UPDATE_DELAYED", function() sweepBags() end },
}

-- The foreign functions after which our numbers have to be put back. This is
-- not a subscription to an event but standing behind them (hooksecurefunc):
-- the game repaints a bag window and an equipment slot itself, and after its
-- work our string would end up over a different item.
--
-- The names of the bag windows and the equipment slots are asked of the core
-- (Darken:GetFrameNames): a second list of foreign names would diverge from
-- the client at the very first patch. What stays here is only the names of the
-- two game functions that repaint the paper doll — their existence is checked
-- before standing behind them.
local PAPERDOLL_REPAINT = {
    "PaperDollItemSlotButton_Update",
    "InspectPaperDollItemSlotButton_Update",
}

--- Stand behind a foreign function, if it exists on this client.
-- @param name string
-- @param fn function
-- @return boolean
local function hookAfter(name, fn)
    if type(_G[name]) ~= "function" then return false end
    if type(hooksecurefunc) ~= "function" then return false end

    return (pcall(hooksecurefunc, name, fn))
end

--- Install the hooks. Once, from OnEnable: there is nothing to remove them
--- with, and a second hook would mean twice the work on every repaint of a
--- bag.
local function installHooks(handle)
    local names = Darken:GetFrameNames("bag-repaint")
    for i = 1, #names do
        hookAfter(names[i], function(frame)
            -- A module the core disabled is obliged to stop working by
            -- itself: the core removes the event subscriptions but not the
            -- hooks on foreign functions (the contract, the section on being
            -- switched off).
            if not handle:IsEnabled() or not drawing then return end

            if type(frame) == "table" then
                sweepBagFrame(frame)
            else
                sweepGameBags()
            end
        end)
    end

    for i = 1, #PAPERDOLL_REPAINT do
        local inspect = PAPERDOLL_REPAINT[i]:find("^Inspect") ~= nil
        hookAfter(PAPERDOLL_REPAINT[i], function()
            if not handle:IsEnabled() or not drawing then return end

            if inspect then
                local unit = inspectUnit()
                if unit then sweepEquipment("inspect", unit) end
            else
                sweepEquipment("character", "player")
            end
        end)
    end
end

--- The values of the list of the number's positions.
-- @return table key -> label
local function positionValues()
    local out = {}
    local list = ns.Level.POSITIONS
    for i = 1, #list do out[list[i].key] = ns.Localize(list[i].label) end
    return out
end

--- The values of the list of the core's font categories.
--
-- The list is asked of the core at the moment it is opened rather than
-- assembled at load time: the categories belong to the fonts subsystem, and a
-- second list of them would diverge from the first silently. The labels are
-- the keys themselves: translating somebody else's labels in our own place
-- would mean a second translation beside the core's.
-- @return table
local function fontValues()
    local out = {}
    local media = currentMedia()
    if not media or type(media.FontCategories) ~= "function" then
        out.hotkey = "hotkey"
        return out
    end

    local keys = media.FontCategories()
    for i = 1, #keys do out[keys[i]] = keys[i] end
    if next(out) == nil then out.hotkey = "hotkey" end
    return out
end

--- The get/set handlers for one setting.
-- @param field string
-- @return function, function
local function handlers(field)
    return function()
        local settings = Settings()
        return settings and settings[field]
    end,
    function(_, value)
        local settings = Settings()
        if not settings then return end
        settings[field] = value
        module:Apply()
    end
end

local getPosition, setPosition = handlers("position")
local getSize,     setSize     = handlers("size")
local getFont,     setFont     = handlers("font")

--- Whether the settings section is hidden.
--
-- Hidden where an item's level means nothing. The presence of game objects
-- decides, not the build number: the rule lies entirely in Level.Meaningful
-- and is tested outside the client.
-- @return boolean
local function hidden()
    return not ns.Level.Meaningful(_G)
end

local BOUNDS = ns.Level.BOUNDS

local options = {
    type = "group",
    -- The labels are functions rather than strings: the table is assembled
    -- at file level, that is, before the core hands over the descriptor, and
    -- without it there is nobody to translate them.
    name = function() return ns.Localize("Darken Item Level") end,
    hidden = hidden,
    args = {
        about = {
            type = "description",
            order = 1,
            width = "full",
            name = function() return ns.Localize("Draws the item level over "
                .. "the icon of an item: on the character sheet, when "
                .. "inspecting another player and in your bags. Off by "
                .. "default - a fresh install changes nothing.") end,
        },
        enabled = {
            type = "toggle",
            order = 2,
            width = "full",
            name = function() return ns.Localize("Show Item Level") end,
            desc = function() return ns.Localize("Off takes every number "
                .. "away at once, without reloading the interface.") end,
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
        position = {
            type = "select",
            order = 3,
            width = "full",
            name = function() return ns.Localize("Number Position") end,
            desc = function() return ns.Localize("Which corner of the icon "
                .. "the number sits in. The bottom right corner is where the "
                .. "game puts the stack count.") end,
            values = positionValues,
            get = getPosition,
            set = setPosition,
        },
        quality = {
            type = "toggle",
            order = 4,
            width = "full",
            name = function() return ns.Localize("Color by Item Quality") end,
            desc = function() return ns.Localize("Off draws every number in "
                .. "the addon's own text color.") end,
            get = function()
                local settings = Settings()
                return settings and settings.quality or false
            end,
            set = function(_, value)
                local settings = Settings()
                if not settings then return end
                settings.quality = value and true or false
                module:Apply()
            end,
        },
        size = {
            type = "range",
            order = 5,
            width = "full",
            name = function() return ns.Localize("Number Size") end,
            min = BOUNDS.size.min, max = BOUNDS.size.max, step = 1,
            get = getSize,
            set = setSize,
        },
        font = {
            type = "select",
            order = 6,
            width = "full",
            name = function() return ns.Localize("Font") end,
            desc = function() return ns.Localize("Which of Darken's font "
                .. "categories the number follows. The font itself is chosen "
                .. "in the addon's Fonts section; only the size above "
                .. "belongs to this module.") end,
            values = fontValues,
            get = getFont,
            set = setFont,
        },
    },
}

local handle, reason = Darken:RegisterModule({
    name = "umbrailevel",
    api  = API,

    -- The defaults: switched off. A fresh install changes nothing on screen,
    -- and every default stays a choice — colouring by quality can be switched
    -- on and off, and the position and the size return to these same
    -- values.
    defaults = {
        enabled  = false,
        position = ns.Level.DEFAULT_POSITION,
        quality  = true,
        size     = BOUNDS.size.default,
        font     = "hotkey",
    },

    options = options,

    OnEnable = function(self)
        -- The descriptor is taken from self, and that is still correct but
        -- no longer required: since contract version 16 RegisterModule
        -- returns the descriptor before the core calls the handlers, and the
        -- module variable has been assigned by that moment. The line is left
        -- as it is — it works on any version of the contract, and there is no
        -- reason to touch ten modules for its sake.
        module = module or self

        -- A client on which an item's level means nothing: the settings
        -- section is hidden, there are no subscriptions and no hooks.
        -- Silently: one line in the chat frame on every login on vanilla
        -- would be noise, and it has nothing to say — the module is simply
        -- beside the point there.
        if not ns.Level.Meaningful(_G) then
            self.unsupported = true
            return
        end

        -- Reading a bag slot's link is asked of the core here and once:
        -- while the file is read the core has not yet determined the client,
        -- and asking on every tooltip is expensive.
        ns.BindGame()

        for i = 1, #EVENTS do
            self:RegisterEvent(EVENTS[i][1], EVENTS[i][2])
        end

        installHooks(self)

        -- The witness of the neighbour's bag window. The neighbour lays out
        -- the list of its slots at the end of every repaint, and the
        -- subscription calls us after it — rather than racing it on the
        -- shared BAG_UPDATE_DELAYED event, where the order of two handlers is
        -- not defined. If it has laid the list out already, the handler is
        -- called at once: the load order of the two folders does not
        -- matter.
        self:OnRepaint(BAGS_SLOTS, function()
            if not drawing then return end
            sweepModuleBags()
        end)

        self:RegisterCommand("ilvl", function()
            local own = self:GetSettings()
            if not own then return end
            own.enabled = not own.enabled
            self:Apply()
            self:Print(own.enabled
                and ns.Localize("item level numbers on")
                or  ns.Localize("item level numbers off"))
        end)
    end,

    ApplySettings = function(self)
        module = module or self

        -- One path of application: entering the game, changing the profile
        -- and editing any setting all lead here.
        if self.unsupported then return end

        local settings = self:GetSettings()
        if not settings or not settings.enabled then
            stop()
            return
        end

        drawing = true

        -- The settings change the look of numbers that are already drawn, so
        -- the sweep runs afresh. It happens on an edit of a setting and on
        -- entering the game rather than per frame: the module has neither a
        -- timer nor an OnUpdate.
        sweepAll()
    end,

    OnDisable = function()
        -- A module the core disabled is obliged to tidy up after itself: the
        -- core removes the subscriptions, and we the numbers on foreign
        -- buttons.
        stop()
    end,
})

if not handle then
    -- The core has already shown the player the reason; there is nothing
    -- more to do.
    return
end

module = handle

-- The module's strings go into the core as soon as there is somebody to hand
-- them to: the settings section asks for a translation at the window's very
-- first drawing.
for locale, strings in pairs(ns.Strings or {}) do
    module:RegisterStrings(locale, strings)
end

--============================================================================
-- The settings page, declared as data
--============================================================================

-- A tab inside the gear page, beside durability: both are about the items one
-- wears, and as two rows in the column they were two entrances to one
-- conversation.

if type(core.Schema) == "table" then
    local Schema = core.Schema
    local PAGE = "umbrailevel"

    -- The containing page may already have been declared by durability:
    -- whichever of the two parts loaded first is the one that created it. A
    -- repeated declaration is refused silently and spoils nothing.
    Schema.Page("gear", { title = "Gear", order = 9 })

    Schema.Page(PAGE, {
        title = "Item Level",
        order = 9.1,
        section = "umbrailevel",
        parent = "gear",
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Show Item Level",
        path = { "enabled" },
        apply = "umbrailevel",
        hint = "Write the item level over the icon of an item: in the "
            .. "character sheet, in inspect and in the bags.",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Corner",
        path = { "position" },
        apply = "umbrailevel",
        hint = "Which corner of the icon the number stands in.",
        values = function()
            local out = {}
            for _, entry in ipairs(ns.Level.POSITIONS) do
                out[#out + 1] = {
                    key = entry.key,
                    text = module:Localize(entry.label),
                }
            end
            return out
        end,
    })

    Schema.Add(PAGE, {
        kind = "toggle",
        label = "Color by Quality",
        path = { "quality" },
        apply = "umbrailevel",
        hint = "Colour the number by the item's quality instead of writing "
            .. "it in one colour.",
    })

    Schema.Add(PAGE, {
        kind = "select",
        label = "Font",
        path = { "font" },
        apply = "umbrailevel",
        hint = "Which of Darken's font categories the number follows. The "
            .. "font itself is chosen in the addon's Fonts section; only "
            .. "the size below belongs to this module.",
        values = function()
            local out = {}
            for key, said in pairs(fontValues()) do
                out[#out + 1] = { key = key, text = said }
            end
            table.sort(out, function(a, b) return a.key < b.key end)
            return out
        end,
    })

    Schema.Add(PAGE, {
        kind = "slider",
        label = "Text Size",
        path = { "size" },
        min = ns.Level.BOUNDS.size.min,
        max = ns.Level.BOUNDS.size.max,
        step = 1,
        apply = "umbrailevel",
        hint = "How big the number is drawn.",
    })
end
