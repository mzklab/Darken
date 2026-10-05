local ADDON, core = ...

-- This part's own namespace: inside one addon every file receives one and
-- the same table, and names such as Rules or Window would collide
-- silently.
local ns = core.Feature("auras")

-- The mouse on an aura icon: a tooltip on hover and cancelling one's own buff
-- with the right button.
--
-- The standard grid the module moves away has both. A replacement that lost
-- what the original could do reads to the player as a step backwards, whatever
-- it added in exchange — so they are here, and here under one setting rather
-- than two: "the mouse on an icon" is one behaviour seen from two sides.
--
-- === Cancelling a buff is protected by the engine ===
--
-- Only CancelUnitBuff can remove a buff from oneself, and the engine does not
-- allow calling it from ordinary code. One path is permitted: a button on
-- SecureActionButtonTemplate with the attributes type2 = "cancelaura", unit and
-- index — the engine, not us, carries out a click on it.
--
-- The price of that path is stated in docs/module-api.md §9: a protected frame
-- can be neither created, nor moved, nor have an attribute rewritten in
-- combat. And the aura's index is precisely an attribute, and it changes
-- constantly during a fight: an aura ended, the set shifted, and the third
-- icon no longer shows the third aura.
--
-- Hence the rule that must not be broken here: **in combat this button does
-- nothing**. Not "it works, but sometimes on the wrong thing" — exactly
-- nothing. Cancelling the wrong aura is worse than cancelling none: the player
-- presses it when shedding a harmful buff in the middle of a fight, and a miss
-- here costs the fight.
--
-- That promise is kept not by a check of ours but by the engine itself:
-- RegisterAttributeDriver sets type2 on the button as the condition
-- "[combat] none; cancelaura". A state driver is the only thing entitled to
-- change a protected button's attribute in combat, because the engine computes
-- it. In combat type2 becomes a word the engine does not know and a click does
-- nothing; out of combat it is "cancelaura" again. A combat check of ours
-- would say the same thing, but it can be circumvented by a stale attribute,
-- while there is nothing to circumvent a driver with.
--
-- The aura's index is written through the core's handle:Secure: out of combat
-- at once, in combat into the queue under the button's key, that is, as the
-- last state when combat ends. While the fight goes on the index on the button
-- may be stale, and that is safe precisely because it cannot be pressed in
-- combat at all.
--
-- If the client does not know RegisterAttributeDriver, the overlay is not
-- created at all and only the tooltip is left. Creating it "anyway" would mean
-- creating a button without the one thing that makes it safe.
--
-- === The tooltip ===
--
-- The tooltip protects nothing and works always, in combat too: it is an
-- ordinary GameTooltip on an ordinary frame. We have no aura description of our
-- own and there is no reason to add one — the game describes its own spells
-- itself.
--
-- === The pool ===
--
-- An icon's mouse handlers are set once, at its birth, and read the record on
-- the icon (frame.record) rather than a closure over the aura. A closure over
-- the aura would outlive the icon's return to the pool and show somebody
-- else's description under a new picture — precisely what Icon.lua forbids.
-- Icon.Release removes the overlay's attributes through Mouse.Forget: somebody
-- else's index on the button is somebody else's aura, cancelled by somebody
-- else's click.

local Mouse = {}
ns.Mouse = Mouse

-- What is written onto the button. The engine's words rather than ours:
-- "cancelaura" is the action's name in SecureTemplates, and type2 is the right
-- button.
Mouse.ATTRIBUTE = "type2"
Mouse.ACTION    = "cancelaura"

-- The state driver's condition. The engine does not know "none" as an action
-- — and not knowing it is the whole point here: in combat the button does
-- nothing.
Mouse.DRIVER = "[combat] none; " .. Mouse.ACTION

-- Whether the mouse is switched on by the setting. One for the whole module
-- rather than a field on an icon: the setting is one and the same for every
-- icon, and a field on an icon would be state the pool is obliged to wipe —
-- while there is nothing to wipe here.
Mouse.on = false

-- The doors outwards. The module replaces them with its own (Mouse.Setup)
-- when it is enabled, and the tests replace them with stand-ins: otherwise
-- cancelling a buff would be tested only in the client, that is, nowhere.
local hooks = {
    -- Deferring work on a protected object. The default is "do it now":
    -- before Setup there is no combat and nothing to protect.
    Secure = function(_, _, action)
        if type(action) == "function" then action() end
        return true
    end,
    InCombat = function()
        if type(InCombatLockdown) ~= "function" then return false end
        local ok, locked = pcall(InCombatLockdown)
        return ok and locked and true or false
    end,
    Create = function(...)
        if type(CreateFrame) ~= "function" then return nil end
        local ok, frame = pcall(CreateFrame, ...)
        return ok and frame or nil
    end,
    Tooltip = function()
        return type(GameTooltip) == "table" and GameTooltip or nil
    end,
    Driver = function(...)
        if type(RegisterAttributeDriver) ~= "function" then return false end
        return pcall(RegisterAttributeDriver, ...)
    end,
    HasDriver = function()
        return type(RegisterAttributeDriver) == "function"
    end,
}
Mouse.hooks = hooks

--- Replace the doors outwards.
-- @param replacements table|nil name -> function
function Mouse.Setup(replacements)
    if type(replacements) ~= "table" then return end
    for name, fn in pairs(replacements) do
        if hooks[name] ~= nil and type(fn) == "function" then
            hooks[name] = fn
        end
    end
end

--- Call an object's method if this client has it.
-- @param object table
-- @param method string
-- @return boolean whether it worked
local function invoke(object, method, ...)
    if type(object) ~= "table" or type(object[method]) ~= "function" then
        return false
    end
    return (pcall(object[method], object, ...))
end

--============================================================================
-- The tooltip
--============================================================================

--- Hide the tooltip.
-- @param tooltip table|nil
function Mouse.Forgo(tooltip)
    invoke(tooltip, "Hide")
end

--- Show the game's tooltip about the aura on an icon.
--
-- There are three paths to the description, and the first one this client
-- knows is taken: SetUnitBuff and SetUnitDebuff exist in every build,
-- SetUnitAura where the aura's kind is passed as a word, and the spell's id
-- remains the last answer for a client that knows neither. The decision is
-- made by a method's existence rather than by the build number.
--
-- @param tooltip table|nil
-- @param owner table|nil the icon the tooltip stands beside
-- @param record table|nil the record of the aura on the icon
-- @return boolean whether it was shown
function Mouse.Describe(tooltip, owner, record)
    if type(tooltip) ~= "table" or type(record) ~= "table" then return false end

    local index = tonumber(record.order)
    if not index then return false end

    invoke(tooltip, "SetOwner", owner, "ANCHOR_RIGHT")

    local harmful = record.harmful and true or false
    local shown = invoke(tooltip, harmful and "SetUnitDebuff" or "SetUnitBuff",
        "player", index)

    if not shown then
        shown = invoke(tooltip, "SetUnitAura", "player", index,
            harmful and "HARMFUL" or "HELPFUL")
    end
    if not shown and tonumber(record.spellId) then
        shown = invoke(tooltip, "SetSpellByID", tonumber(record.spellId))
    end

    if not shown then
        Mouse.Forgo(tooltip)
        return false
    end

    invoke(tooltip, "Show")
    return true
end

--============================================================================
-- Cancelling a buff
--============================================================================

--- Whether this aura can be cancelled.
--
-- Only a buff on oneself: a player does not remove a debuff from themselves —
-- neither CancelUnitBuff nor any other door can do it — and a button that
-- sometimes does nothing reads as broken. There is no rule about other
-- people's buffs: one applied by another player is removed from oneself
-- exactly as one's own is.
--
-- @param record table|nil
-- @return boolean
function Mouse.Cancellable(record)
    if type(record) ~= "table" then return false end
    if record.harmful then return false end
    local index = tonumber(record.order)
    return index ~= nil and index > 0
end

-- The next overlay's number. The combat queue's key has to be its own for
-- every button: under a shared key forty icons would defer one change between
-- them all.
local counter = 0

--- Create the secure overlay on an icon.
--
-- Returns nil both in combat (the engine then does not allow creating a
-- protected frame — we will try on the next repaint out of combat) and on a
-- client without a state driver (then forever: a button without a driver is
-- unsafe).
--
-- @param frame table|nil the icon
-- @return table|nil
function Mouse.Overlay(frame)
    if type(frame) ~= "table" then return nil end
    if frame.cancel ~= nil then return frame.cancel or nil end

    if not hooks.HasDriver() then
        frame.cancel = false
        return nil
    end
    if hooks.InCombat() then return nil end

    local button = hooks.Create("Button", nil, frame,
        "SecureActionButtonTemplate")
    if type(button) ~= "table" then return nil end

    counter = counter + 1
    button.umbraKey  = "cancel:" .. counter
    button.umbraIcon = frame

    invoke(button, "SetAllPoints", frame)
    invoke(button, "RegisterForClicks", "RightButtonUp")
    invoke(button, "EnableMouse", true)

    -- The only place where an action is set on the button. As a condition
    -- rather than a value: see the file's header.
    hooks.Driver(button, Mouse.ATTRIBUTE, Mouse.DRIVER)

    Mouse.Watch(button)

    frame.cancel = button
    return button
end

-- The "no aim" marker. It tells "aimed at nothing" apart from "never aimed at
-- all": without it the very first repaint after a return to the pool would
-- skip clearing the aim, having decided there was nothing to clear.
local NONE = {}

--- Write onto the overlay which aura it cancels.
--
-- The attributes go as a pair and only as a pair: an index without a unit and a
-- unit without an index equally mean a button that will cancel the wrong
-- thing.
--
-- An aim that matched the previous one is not written at all, and that is about
-- cost: a repaint arrives on every aura event, while the set of auras is most
-- often the same one. The comparison costs one comparison, and the write costs
-- a closure and two calls into the engine per icon.
--
-- What is remembered is the aim that was requested rather than the one that was
-- written. Work deferred in combat lies in the queue under this button's key
-- and will be carried out as the last one requested — that is, as what was
-- recorded here.
--
-- @param frame table|nil the icon
-- @param record table|nil the record of the aura; nil clears the aim entirely
-- @return boolean whether it was written right now (false means deferred until
--     combat ends)
function Mouse.Aim(frame, record)
    local button = type(frame) == "table" and frame.cancel or nil
    if type(button) ~= "table" then return false end

    local index = Mouse.Cancellable(record) and tonumber(record.order) or nil
    local want  = index or NONE
    if button.umbraAim == want then return true end
    button.umbraAim = want

    local unit = index and "player" or nil

    return hooks.Secure(button, button.umbraKey, function()
        invoke(button, "SetAttribute", "unit", unit)
        invoke(button, "SetAttribute", "index", index)
    end) and true or false
end

--- Clear any aim from the overlay.
--
-- Called from Icon.Release: an icon that returned to the pool carries nothing
-- of the previous aura — and the index on the secure button is part of that
-- "nothing" on equal terms with the picture and the labels.
--
-- @param frame table|nil
function Mouse.Forget(frame)
    Mouse.Aim(frame, nil)
end

--============================================================================
-- The handlers
--============================================================================

--- Hang the hover handlers on a frame.
--
-- A handler reads the record off the icon and remembers nothing itself: the
-- icon is reused, and a closure over the aura would outlive the return to the
-- pool.
--
-- @param frame table|nil the icon, or the overlay on it
function Mouse.Watch(frame)
    if type(frame) ~= "table" or type(frame.SetScript) ~= "function" then
        return
    end

    frame:SetScript("OnEnter", function(self)
        if not Mouse.on then return end
        local icon = self.umbraIcon or self
        Mouse.Describe(hooks.Tooltip(), icon, icon.record)
    end)

    frame:SetScript("OnLeave", function()
        Mouse.Forgo(hooks.Tooltip())
    end)
end

--- Bring the mouse on an icon into line with the setting and the aura shown.
--
-- Called for every shown icon of every repaint. The cost is a comparison, a
-- call of EnableMouse and, when the setting is on, two SetAttribute calls out
-- of combat: no tables, no strings, no walk. In combat the overlay is not
-- created and the attributes are not written at all — that would be the most
-- expensive thing here.
--
-- @param frame table|nil the icon
-- @param enabled any whether the setting is on
function Mouse.Update(frame, enabled)
    if type(frame) ~= "table" then return end

    Mouse.on = enabled and true or false

    invoke(frame, "EnableMouse", Mouse.on)

    if not Mouse.on then
        Mouse.Forget(frame)
        return
    end

    if Mouse.Overlay(frame) then
        Mouse.Aim(frame, frame.record)
    end
end
