local helpers = require("helpers")

T.suite("Registry")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Registry.lua", ns)
local Registry = ns.Registry

local a = Registry:Register({ name = "alpha", defaults = { x = 1 } })
local b = Registry:Register({ name = "beta" })

T.eq(Registry:Get("alpha"), a, "a module is found by name")
T.eq(Registry:Get("no-such-thing"), nil, "an unknown name gives nil")

-- The order of the walk is the order of registration. The order in which the
-- settings are applied depends on it, so it is part of the contract rather than an accident.
local seen = {}
for m in Registry:Each() do
    seen[#seen + 1] = m.name
end
T.eq(#seen, 2, "both modules were walked")
T.eq(seen[1], "alpha", "alpha was registered first")
T.eq(seen[2], "beta", "beta was registered second")

-- The contract is obligatory: a crooked module accepted silently breaks later
-- and further from the place of the mistake.
T.err(function() Registry:Register(nil) end, "a nil is not a module")
T.err(function() Registry:Register({}) end, "a module with no name")
T.err(function() Registry:Register({ name = "" }) end, "an empty name")
T.err(function() Registry:Register({ name = "alpha" }) end, "a repeated name")

T.suite("Registry:CollectDefaults")

local defaults = Registry:CollectDefaults()
T.eq(defaults.alpha.x, 1, "the defaults are gathered under the module's name")
T.eq(defaults.beta, nil, "a module with no defaults does not get into the table")

T.suite("Registry:ApplyAll")

local calls = {}
Registry:Register({
    name = "gamma",
    ApplySettings = function(self) calls[#calls + 1] = self.name end,
})
Registry:ApplyAll()
T.eq(#calls, 1, "ApplySettings was called on the one that has it")
T.eq(calls[1], "gamma", "it was gamma it was called on")

-- The order of application is the order of registration. The registry
-- declares that as a contract, so it has to be checked rather than assumed.
local ordered = helpers.newNamespace()
helpers.loadAddonFile("Core/Registry.lua", ordered)
local R2 = ordered.Registry

local applied = {}
local function record(self) applied[#applied + 1] = self.name end
R2:Register({ name = "first",  ApplySettings = record })
R2:Register({ name = "second", ApplySettings = record })
R2:Register({ name = "third",  ApplySettings = record })
R2:ApplyAll()

T.eq(#applied, 3, "the settings were applied on all three modules")
T.eq(applied[1], "first", "first comes the one registered first")
T.eq(applied[2], "second", "second comes the one registered second")
T.eq(applied[3], "third", "third comes the one registered third")
