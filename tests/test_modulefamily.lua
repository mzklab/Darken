local helpers = require("helpers")

-- The core's case folding is needed before the modules' files are read:
-- behind the Darken:GetCasefold door stands the real Core/Casefold.lua, and
-- the windows' headers are raised by it rather than by a fake beside it.
local coreCasefold, restoreCore = helpers.installCasefold()
_G.Darken = {}
_G.Darken = savedGlobal