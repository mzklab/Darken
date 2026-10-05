local ADDON, ns = ...

-- The module registry. A module is a table with a mandatory `name` field and
-- optional defaults, options, OnEnable and ApplySettings. Adding a subsystem
-- requires no edits here.
--
-- The registry is an internal layer. It is called by our own subsystems in
-- Modules/, and with them it is strict: a malformed module here breaks
-- loading, because a malformed module here is our own typo and has to be
-- seen immediately. Third-party modules in separate folders do not come here
-- directly: they arrive through the public layer (Core/Api.lua), which checks
-- the same things but returns a refusal instead of raising. Strict inwards,
-- lenient outwards — those are different promises to different people, and
-- one function does not express both.
--
-- Calls into modules go through Protect/Invoke, and that applies to our own
-- modules too. The reason is not self-distrust: the execution path must be
-- one. Were our modules called directly and third-party ones through the
-- guard, the isolation would only ever be exercised on third-party code —
-- that is, on code we do not have.
--
-- The registry reads a module's name from the module's table exactly once —
-- at registration — and uses its own reverse map keys[module] from then on.
-- That is not pedantry but a closed hole. The `name` field lies in the very
-- table the contract tells a module's author to keep their state in, and
-- "name" is the first word that comes to mind for a display name. A module
-- that rewrote its own name to somebody else's and then raised would disable
-- that other module: it would drop out of the settings, out of the assembled
-- defaults and out of application, while the culprit kept running and would
-- never be named again, because Disable stays quiet for a name already
-- disabled. The registry's key must be unforgeable.
local Registry = {
    modules  = {},   -- [name] = module
    keys     = {},   -- [module] = the name it is registered under
    order    = {},   -- registration order
    failures = {},   -- [name] = the error text the module was disabled over
    started  = {},   -- [name] = this module's OnEnable has already happened
    pending  = {},   -- [name] = enabling deferred to the next frame
    enabled  = false, -- whether the registry has called OnEnable already
    enabling = false, -- whether a general enabling pass is running now
    applying = false, -- whether settings are being applied right now
}
ns.Registry = Registry

--- Register a module.
-- The contract is checked strictly: an error at load time is clearer than
-- strange behaviour an hour into the game.
-- @param module table the module's table
-- @return table the same module, for chaining
function Registry:Register(module)
    if type(module) ~= "table" then
        error("a module must be a table, got: " .. type(module), 2)
    end
    if type(module.name) ~= "string" or module.name == "" then
        error("a module must have a non-empty name", 2)
    end
    if self.modules[module.name] then
        error("module already registered: " .. module.name, 2)
    end

    -- The name is taken off the table here and only here. Everywhere else it
    -- comes from `keys`: see the note at the registry's declaration.
    local name = module.name

    self.modules[name] = module
    self.keys[module]  = name
    self.order[#self.order + 1] = name
    return module
end

--- Find a module by name.
-- @param name string
-- @return table|nil
function Registry:Get(name)
    return self.modules[name]
end

--- The name a module is registered under.
-- The only correct way to learn a module's name: the module.name field
-- belongs to the module's author and may be anything.
-- @param module table|nil
-- @return string|nil nil means "this table was never registered"
function Registry:NameOf(module)
    if type(module) ~= "table" then return nil end
    return self.keys[module]
end

--- Iterate the modules in registration order.
-- Disabled modules are not excluded from the walk: the walk is the list of
-- what is registered, while the decision "call or not" is Protect's.
-- Otherwise two places would know about disabling, and they could diverge
-- silently.
-- The iterator yields the name too: the caller needs it almost always, and
-- reading it from the module's table is not allowed.
-- @return function an iterator yielding a module and its name
function Registry:Each()
    local i = 0
    return function()
        i = i + 1
        local name = self.order[i]
        if name then return self.modules[name], name end
    end
end

--- Whether a module is disabled.
-- @param name string|nil
-- @return boolean
function Registry:IsFailed(name)
    return self.failures[name] ~= nil
end

--- The error text a module was disabled over.
-- @param name string|nil
-- @return string|nil
function Registry:FailureText(name)
    return self.failures[name]
end

--- Tell the player.
-- A function of its own rather than a direct Print call: the registry loads
-- before the addon's core and lives in the tests, where there is neither
-- ns.Addon nor the game's print. The Registry.report field is replaced by the
-- tests, so that what is checked is not the text in chat but the fact of one
-- message per failure.
-- @param text string
function Registry:Report(text)
    if type(self.report) == "function" then
        self.report(text)
        return
    end

    local addon = ns.Addon
    if type(addon) == "table" and type(addon.Print) == "function" then
        addon:Print(text)
    elseif type(print) == "function" then
        print(text)
    end
end

--- Disable a module.
-- Disabling again stays quiet: "reports itself once" is part of the
-- contract, or a module failing every frame would flood the chat.
--
-- The machinery for coming back is here — Registry:CanRetry and
-- Registry:Retry below — but nothing in the settings window currently offers
-- it: the page that explained a failure and carried a "try again" button
-- belonged to the old window and went with it. A disabled module therefore
-- says its one line in chat and is reachable again only by reloading the
-- interface.
-- @param name string the module's name
-- @param text string the message for the player, already assembled by the
--     caller
-- @return boolean whether it was disabled now (false means it already was)
function Registry:Disable(name, text)
    if type(name) ~= "string" or name == "" then return false end
    if self.failures[name] then return false end

    self.failures[name] = text or ns.Localize("this module was switched off")
    self:Report(self.failures[name])

    -- A deferred enable is cancelled: there is nothing to call a disabled
    -- module with, and no reason for it to wait for its frame.
    self.pending[name] = nil

    -- The module is told it was switched off. Without this the core stopped
    -- calling the module while the module kept calling outwards: a disabled
    -- nameplate engine with its own OnUpdate on somebody else's frame would
    -- keep running and burning frames until the interface was reloaded.
    -- OnDisable is the only call made to an already disabled module, and it
    -- is made exactly once.
    --
    -- Called through a plain pcall rather than Protect: Protect does nothing
    -- for a disabled name, and there is nothing left to disable if OnDisable
    -- raises. The error is swallowed here deliberately — the message about
    -- the first failure has already gone out, and a second one beside it
    -- would only confuse.
    local module = self.modules[name]
    if type(module) == "table" and type(module.OnDisable) == "function" then
        pcall(module.OnDisable, module, self.failures[name])
    end

    -- Game event subscriptions are removed along with the disabling. Without
    -- that a module which raised would keep waking the receiver on every one
    -- of its events until the interface was reloaded: Protect would not let
    -- it inside anyway, but the event itself would travel through the engine
    -- and cost the player frames. The rule "a switched-off module stops
    -- listening" is enforced by the core rather than by the module author's
    -- memory.
    --
    -- The table is checked for presence: the registry loads before the events
    -- subsystem, and in the tests it is sometimes not loaded at all.
    if type(ns.Events) == "table" and type(ns.Events.DropModule) == "function" then
        pcall(ns.Events.DropModule, name)
    end

    -- The queue of work deferred to the end of combat goes the same way.
    -- Nothing of a switched-off module should stay alive: the core will not
    -- let those actions run anyway (Protect refuses a disabled module), and
    -- until combat next ended they would hold references to the module's
    -- frames and closures.
    if type(ns.Combat) == "table" and type(ns.Combat.DropModule) == "function" then
        pcall(ns.Combat.DropModule, name)
    end


    -- Subsystems this module stood down are returned to the core. This is
    -- the same reckoning as the events and the deferred queue: nothing of a
    -- switched-off module should stay alive, and a subsystem it stood down is
    -- a live trace. Without the return the player would get the worst
    -- outcome: the module no longer draws, the core does not draw yet, and so
    -- it stays until the interface is reloaded.
    --
    -- The order matters: the return comes after OnDisable. In OnDisable the
    -- module lets go of other people's frames — handing the styling back to
    -- the core earlier would mean styling what the module still holds.
    if type(ns.ReleaseSubsystemsOf) == "function" then
        pcall(ns.ReleaseSubsystemsOf, name)
    end

    -- A leftover from the old settings tree. Nothing defines
    -- ns.RefreshOptions any more - the new window repaints itself - so this
    -- guarded call does nothing.
    if type(ns.RefreshOptions) == "function" then
        pcall(ns.RefreshOptions)
    end

    return true
end

--- Bring back a subsystem a module stood down.
--
-- It differs from Retry in two ways, and both are deliberate.
--
-- First: there is no "may we" question here. Retry is about a module that
-- raised, and the recoverable = false marker means "there will be no second
-- attempt". A subsystem that stood down did not fail: it was asked to step
-- aside, and the request has ended. Asking its permission to come back would
-- be asking the wrong party.
--
-- Second: OnEnable is called only if it never happened. Retry raises a module
-- from nothing — there the repeated enabling is the whole point of the
-- attempt. Here the subsystem has most often been enabled at login and stood
-- down later (the bags module takes the first window long after login), and a
-- second OnEnable would mean a second event subscription and a second handler
-- on top of every game function. But the opposite happens too: a subsystem
-- stood down before its turn to be enabled came — that one has to be enabled,
-- or it comes back alive in appearance only.
--
-- The isolation is not weakened by a step: both calls go through the same one
-- door — Protect — and a subsystem that raises on its return is disabled
-- again, with its own error text.
--
-- @param name string|nil the subsystem's name
-- @return boolean whether the subsystem works after the return
function Registry:Resume(name)
    if type(name) ~= "string" or name == "" then return false end

    local module = self.modules[name]
    if type(module) ~= "table" then return false end

    -- Not disabled means already in service, and there is nothing to do.
    if not self:IsFailed(name) then return true end

    -- Cleared right here: Protect refuses to call a disabled name, and
    -- without this the return would never reach the subsystem at all.
    self.failures[name] = nil

    -- The general enabling pass has not happened yet: calling OnEnable from
    -- here would create a second enabling path beside EnableAll. The marker
    -- is cleared — login does the rest.
    if not self.enabled then
        if type(ns.RefreshOptions) == "function" then
            pcall(ns.RefreshOptions)
        end
        return true
    end

    local ok = true
    if not self.started[name] then
        self.pending[name] = nil
        ok = self:Invoke(module, "OnEnable")
    end
    if ok then
        self:Invoke(module, "ApplySettings")
    end

    local alive = not self:IsFailed(name)

    -- Another leftover of the old settings tree: nothing defines
    -- ns.RefreshOptions any more, so this does nothing.
    if type(ns.RefreshOptions) == "function" then
        pcall(ns.RefreshOptions)
    end

    return alive
end

--- The message about a module that failed.
-- Separated out so that a test compares the message itself rather than a
-- retelling of it. ns.Localize is called directly even though Core/Locale.lua
-- loads after this file: the call happens in the game rather than while the
-- file is read, and by then the translation is in place. A wrapper around the
-- translation would be worse here — the translation-completeness test reads
-- the keys out of the sources by the name ns.Localize, and a key hidden
-- behind a wrapper would stop being seen.
--
-- NOTE: the text still promises that the module's place in the settings
-- window explains the failure and offers to start it up again. That page
-- belonged to the old window and went with it; see Registry:Disable.
-- @param name string the module's name
-- @param method string the name of the call that raised
-- @param err string the Lua error text
-- @return string
function ns.ModuleFailureText(name, method, err)
    return string.format(ns.Localize(
        "Module \"%s\" raised an error in %s and is switched off: the core "
        .. "will not call it again. The rest of Darken is unaffected. Its "
        .. "place in the settings window says so and offers to start it up "
        .. "again. Error: %s"),
        tostring(name), tostring(method), tostring(err))
end

--- The message about a module that came back into service.
-- @param name string the module's name
-- @return string
function ns.ModuleRecoveredText(name)
    return string.format(ns.Localize(
        "Module \"%s\" started up again and is working. Its settings are "
        .. "back where they were."), tostring(name))
end

--- Whether a module may be brought back without reloading the interface.
--
-- A disabled module is not necessarily hopeless. A failure can be a one-off:
-- a window that did not exist yet; data the server had not sent yet. A retry
-- at the player's request is not the same as an automatic one: an automatic
-- retry would flood the chat, while this one happens exactly once per press.
--
-- A module that cannot come back says so with recoverable = false in its
-- descriptor. The default is "it can": a module that said nothing will at
-- worst raise again and be disabled the same way, and offering an attempt and
-- not giving it is worse than the other way round.
--
-- @param name string|nil the module's name
-- @return boolean
function Registry:CanRetry(name)
    if not self:IsFailed(name) then return false end

    -- A subsystem a module stood down is not raised by a button. It did not
    -- fail: its place was taken by a module that is drawing instead of it
    -- right now, and a retry would give one frame a second owner — exactly
    -- the flicker handle:Replaces exists to prevent. Only whoever took it has
    -- the right to give it back, and they will do so themselves when they
    -- stop drawing.
    if type(ns.SubsystemOwner) == "function" and ns.SubsystemOwner(name) then
        return false
    end

    local module = self.modules[name]
    if type(module) ~= "table" then return false end

    -- A subsystem that stood aside is not raised even when it has no owner.
    -- The standDown marker is read on each of its entries, and that entry
    -- returns silently: OnEnable and ApplySettings pass without raising
    -- anything — and after such a "successful" attempt the subsystem still
    -- does not draw, while its rows stay hidden by their own condition. The
    -- core meanwhile told the player everything was back and the settings
    -- were in place. Reporting success where nothing works is worse than
    -- reporting a refusal.
    --
    -- A subsystem also stands itself down (Modules/NamePlates.lua, on seeing
    -- a third-party addon owning the same thing) — in that case there is no
    -- owner at all, and the check above does not catch it.
    if module.standDown then return false end

    return module.recoverable ~= false
end

--- Try to bring a disabled module back into service.
--
-- The isolation is not weakened by a step. The failure marker is cleared
-- immediately before the attempt, and both calls go through the same one door
-- — Protect: a module that raises again is disabled again, with its own new
-- error text, and stops being called again. What changes is not the guard but
-- what the player has: a way to try once more without leaving the game.
--
-- The enabling path is the one login takes: OnEnable, then ApplySettings.
-- There is deliberately no second path for the return; a module that came
-- back differently from the way it is normally enabled would end up in a
-- state that never occurs during a normal load.
--
-- NOTE: nothing in the settings window calls this today — the page that
-- carried the button went with the old window. See Registry:Disable.
--
-- @param name string|nil the module's name
-- @return boolean whether the module works after the attempt
function Registry:Retry(name)
    if not self:CanRetry(name) then return false end

    local module = self.modules[name]

    -- Cleared right here: Protect refuses to call a disabled name, and
    -- without this the attempt would never reach the module at all.
    self.failures[name] = nil
    self.pending[name] = nil

    if self:Invoke(module, "OnEnable") then
        self:Invoke(module, "ApplySettings")
    end

    local alive = not self:IsFailed(name)
    if alive then
        self:Report(ns.ModuleRecoveredText(name))
    end

    -- Another leftover of the old settings tree: nothing defines
    -- ns.RefreshOptions any more, so this does nothing.
    if type(ns.RefreshOptions) == "function" then
        pcall(ns.RefreshOptions)
    end

    return alive
end

--- A guarded call into a module.
-- The only door from the core into foreign code. A module that raises is
-- disabled right here and never called again: reloading the interface is the
-- only way to bring it back, and that is deliberate. A module that fails
-- while being enabled is just as likely to fail on the next attempt, and the
-- player would get a stream of messages instead of one.
-- @param name string the module's name
-- @param method string the call's name, for the message
-- @param fn function what to call
-- @param ... the arguments
-- @return boolean whether the call went through
-- @return any the first returned value on success, the error text on
--     failure
function Registry:Protect(name, method, fn, ...)
    if self:IsFailed(name) then return false end
    if type(fn) ~= "function" then return true end

    local ok, result = pcall(fn, ...)
    if ok then return true, result end

    -- The engine's text is kept alongside: without it "the module failed" is
    -- a message with no cause, and the cause has to be hunted for by
    -- guesswork.
    self.lastError = self.lastError or {}
    self.lastError[name] = tostring(result)

    self:Disable(name, ns.ModuleFailureText(name, method, result))
    return false, result
end

--- Call a module's method under the guard.
-- A missing method is not an error: the OnEnable and ApplySettings fields are
-- optional.
-- @param module table
-- @param method string the name of the field holding the function
-- @param ... the arguments after self
-- @return boolean whether the call went through
function Registry:Invoke(module, method, ...)
    if type(module) ~= "table" then return false end

    -- The name comes from the reverse map rather than from module.name: see
    -- the note at the registry's declaration. An unregistered table should
    -- never get here, and calling it blindly is not allowed — it has no name
    -- it could be disabled under if it raises.
    local name = self.keys[module]
    if name == nil then return false end

    local fn = module[method]
    if type(fn) ~= "function" then
        -- No method means nothing to call, but a disabled module must stay
        -- disabled in this case too.
        local alive = not self:IsFailed(name)
        -- A module without an OnEnable is enabled precisely by there being
        -- nothing to call: otherwise bringing a subsystem back (Resume) would
        -- look for its enabling forever and call it on every return.
        if alive and method == "OnEnable" then self.started[name] = true end
        return alive
    end

    local ok = self:Protect(name, method, fn, module, ...)

    -- The "it was enabled" marker is set here and only here. The return of
    -- a stood-down subsystem needs it: a subsystem stood down before its turn
    -- to be enabled came has to be enabled first, while one already enabled
    -- must not be enabled a second time — its event subscriptions and its
    -- handlers on top of game functions would silently double.
    if ok and method == "OnEnable" then self.started[name] = true end

    return ok
end

--- Whether a module is working right now.
-- Four conditions at once: the table is registered, the general enabling has
-- happened, the module was not disabled by a failure, and it is not waiting
-- for its frame. The last one is about the window between registration and
-- deferred enabling: the author already holds the descriptor while OnEnable
-- has not happened yet, and answering "it works" at that moment would be a
-- lie.
-- @param module table
-- @return boolean
function Registry:IsEnabled(module)
    local name = self:NameOf(module)
    if name == nil then return false end
    if self.pending[name] then return false end
    return self.enabled and not self:IsFailed(name)
end

--- Collect the default settings of every module.
-- @param field string|nil the descriptor's field: "defaults" (the profile,
--        the default) or "globals" (the account-wide store)
-- @return table of the form { [module name] = defaults }
function Registry:CollectDefaults(field)
    field = field or "defaults"

    local out = {}
    for module, name in self:Each() do
        if type(module[field]) == "table" and not self:IsFailed(name) then
            out[name] = module[field]
        end
    end
    return out
end

--- Apply the settings in every module.
-- The one application path: login, a profile switch and a changed setting all
-- lead here. A module that raises is disabled and does not hinder its
-- neighbours: the loop goes on, because the others' settings have nothing to
-- do with its failure.
--
-- Re-entry is forbidden. The contract tells a module to call Refresh from its
-- set handler, and Refresh leads here; a module that also called it from its
-- own ApplySettings would get infinite recursion and a stack overflow after
-- roughly fifteen hundred turns — that is, a yellow error naming nobody. Now
-- a re-entrant call simply does nothing: the settings are being applied right
-- now anyway.
-- @return boolean whether the application ran (false means one is already
--     running)
function Registry:ApplyAll()
    if self.applying then return false end
    self.applying = true

    for module, name in self:Each() do
        -- A module waiting for its frame is skipped: its OnEnable has not
        -- happened yet, and applying settings before enabling is a state that
        -- never occurs during a normal load. It will apply its own settings
        -- itself, right after its own OnEnable.
        if not self.pending[name] then
            self:Invoke(module, "ApplySettings")
        end
    end

    self.applying = false
    return true
end

--- Apply one module's settings.
-- Needed by modules that redraw themselves in response to a game event: the
-- nameplate engine has no reason to drive a settings pass across the whole
-- addon for every unit that appears. The path is the same one — the module's
-- ApplySettings — so the result of a targeted application matches that of a
-- general one.
-- @param module table
-- @return boolean whether the application ran
function Registry:ApplyOne(module)
    if self.applying then return false end

    -- The module called Apply without waiting for its frame. Refusing would
    -- be unfair — it asked about itself and deserves an answer — and applying
    -- settings before OnEnable is not allowed. So it no longer needs the
    -- frame: it is enabled right here, and everything goes the usual way from
    -- there.
    local pendingName = self:NameOf(module)
    if pendingName ~= nil and self.pending[pendingName] then
        self.pending[pendingName] = nil
        if not self:Invoke(module, "OnEnable") then return false end
    end

    self.applying = true

    local ok = self:Invoke(module, "ApplySettings")

    self.applying = false
    return ok
end

--- Enable every module.
-- Called by the core once, at login. After that the registry remembers that
-- enabling has happened: a module registered later (a separate addon loaded
-- on demand) is enabled on the next frame through EnableLater, or it would
-- stay registered and dead until the next /reload.
--
-- The list's length is taken before the loop. The `enabled` flag is raised on
-- the first line — which means a module registered from somebody else's
-- OnEnable (a set of modules: the bags core plus what plugs into it) goes to
-- the deferred ones. A live walk of self.order would reach it next and call
-- OnEnable a second time: a double event subscription, double frames. The
-- snapshot of the length draws the boundary exactly where it belongs, and
-- ApplyAll below skips the deferred ones — otherwise their settings would be
-- applied before they were enabled.
function Registry:EnableAll()
    self.enabled  = true
    self.enabling = true

    local count = #self.order
    for i = 1, count do
        self:Invoke(self.modules[self.order[i]], "OnEnable")
    end

    self.enabling = false
    self:ApplyAll()
end

--- Enable one module registered after the general enabling.
--
-- An internal door: called directly when the module may already be called. A
-- third-party module does not arrive through here but through EnableLater: it
-- was promised a frame.
-- @param module table
function Registry:EnableOne(module)
    if not self.enabled then return end

    local name = self:NameOf(module)
    if name ~= nil then self.pending[name] = nil end

    if self:Invoke(module, "OnEnable") then
        self:Invoke(module, "ApplySettings")
    end
end

--- Enable a module not now but on the next frame.
--
-- Why defer at all. Registration returns a descriptor, and a module's author
-- writes exactly what anyone would write: `local module = RegisterModule{...}`,
-- and then uses the `module` variable from their own handlers. While enabling
-- happened inside registration, that variable was still nil at the moment of
-- the first call — the call had not returned, the assignment had not
-- happened. The module failed on its own first line and was switched off
-- before it drew anything. All nine modules in the repository stepped on
-- this, and the exemplary tenth too; each worked around it by hand with the
-- line `module = module or self`.
--
-- The mistake was not in nine modules but in the shape of the door. A
-- contract whose correct use requires a warning is built wrong: what the
-- author writes without thinking has to be the correct thing. So enabling
-- moves past the call's boundary — by exactly one frame — and by the time
-- OnEnable runs the author's variable is already assigned.
--
-- One frame rather than "some time": C_Timer.After(0) happens on the next
-- frame in the client, that is, before any game event the module could have
-- subscribed to. There is no client without C_Timer, but outside the game
-- there is none, and then enabling happens immediately — the path stays the
-- same, and the old trouble returns only where there are no frames at
-- all.
-- @param module table
function Registry:EnableLater(module)
    if not self.enabled then return end

    local name = self:NameOf(module)
    if name == nil then return end

    -- One name is not deferred twice: one frame, one enabling.
    if self.pending[name] then return end
    self.pending[name] = true

    local timer = _G.C_Timer
    if type(timer) == "table" and type(timer.After) == "function" then
        local ok = pcall(timer.After, 0, function() self:FlushEnable() end)
        if ok then return end
    end

    self:FlushEnable()
end

--- Enable everything waiting for its frame.
--
-- A walk of `order` rather than of `pending` itself: the enabling order must
-- be the registration order here too, while walking the set would yield the
-- names in hash order — that is, in a different order on different runs.
function Registry:FlushEnable()
    local count = #self.order
    for i = 1, count do
        local name = self.order[i]
        if self.pending[name] then
            self:EnableOne(self.modules[name])
        end
    end
end
