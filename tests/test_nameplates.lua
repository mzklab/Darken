local helpers = require("helpers")

-- The styling of the nameplates.
--
-- Three subjects the file is written for.
--
-- The first is standing aside for another addon. In the client it can be
-- checked in only one way: install Plater and look. Here it costs two lines,
-- and the rule stays checked for all eight names at once.
--
-- The second is the colour. The decision is made by the unit frames subsystem,
-- and what is checked here is not a second rule but that it is precisely that
-- one which arrives here: the same modes, the same fallbacks, the same setting names.
--
-- The third is that the subsystem does not touch frames that are not its own.
-- The game's raid frames are built out of the same button as the nameplates,
-- and the subscription to the repainting functions catches them on a par. The
-- marker "we styled this" is the only thing that separates them.

local savedLibStub = LibStub
local fakeMedia = {
    List    = function() return { "Darken Dark" } end,
    IsValid = function(_, kind, name)
        return kind == "statusbar" and name == "Darken Dark"
    end,
    Fetch   = function(_, kind, name)
        if kind == "statusbar" and name == "Darken Dark" then
            return "Media\\mzk-dark.tga"
        end
        return nil
    end,
}
LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return fakeMedia end
    return nil
end

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Skin.lua", ns)
-- Core/Media.lua: the resolution of a texture's name into a file lives there,
-- and ns.Skin.MediaTexture calls it (Core/Skin.lua). Without that file the core would not find a single texture.
helpers.loadAddonFile("Core/Media.lua", ns)
helpers.loadAddonFile("Core/Compat.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Events.lua", ns)
helpers.loadAddonFile("Core/Combat.lua", ns)
helpers.loadAddonFile("Modules/Darkness.lua", ns)
helpers.loadAddonFile("Modules/Fonts.lua", ns)
helpers.loadAddonFile("Modules/UnitFrames.lua", ns)
helpers.loadAddonFile("Modules/NamePlates.lua", ns)

local NP = ns.NamePlates

T.suite("the nameplates: another owner")

-- The addon is loaded, so we stand aside. The name is needed for more than
-- tidiness: the player has to read in the chat who exactly took the
-- nameplates, or the message is no different from "something went wrong".
do
    local asked = {}
    local function loaded(name)
        asked[#asked + 1] = name
        return name == "Plater"
    end

    T.eq(NP.ForeignOwner(loaded, {}), "Plater", "Plater was found by the addon's name")
    T.ok(#asked > 0, "the list of addons was asked for")
end

T.eq(NP.ForeignOwner(function(name) return name == "Platynator" end, {}),
     "Platynator", "Platynator was found by the addon's name")
T.eq(NP.ForeignOwner(function(name)
        return name == "TidyPlates_ThreatPlates"
     end, {}),
     "TidyPlates_ThreatPlates", "Threat Plates was found by the addon's name")

-- An addon may lie in a folder under a different name while its engine works
-- all the same: then a global table gives it away.
T.eq(NP.ForeignOwner(function() return false end, { Plater = {} }),
     "Plater", "Plater was found by its global table")
T.eq(NP.ForeignOwner(nil, { KuiNameplates = {} }),
     "Kui_Nameplates", "Kui was found with no list of addons")

-- Nobody is there, so we work ourselves.
T.eq(NP.ForeignOwner(function() return false end, {}), nil,
     "with no other addon there is no owner")
T.eq(NP.ForeignOwner(nil, nil), nil, "with neither source there is no owner")

-- Somebody else's function arrives from outside and may fall over. A failure
-- must not carry the subsystem's enabling with it: we count the addon as absent.
T.eq(NP.ForeignOwner(function() error("somebody else's error") end, {}), nil,
     "a failure of somebody else's function does not count as a find")

T.suite("the nameplates: the unit frame inside a nameplate")

do
    local inner = {}
    T.eq(NP.UnitFrameOf({ UnitFrame = inner }), inner, "the UnitFrame field")
    T.eq(NP.UnitFrameOf({ unitFrame = inner }), inner, "the unitFrame field")

    -- The field is absent entirely, which means the bars lie right on the
    -- nameplate. A refusal in that case would mean a silently non-working subsystem.
    local bare = { healthBar = {} }
    T.eq(NP.UnitFrameOf(bare), bare, "with no field the nameplate itself is taken")
    T.eq(NP.UnitFrameOf(nil), nil, "no frame comes out of nothing")
end

T.suite("the nameplates: the colour comes from the unit frames")

-- A stand-in client. Exactly as much game as the colour rule needs: the class,
-- the reaction and the colour tables.
local savedGlobals = {}
local function setGlobal(name, value)
    savedGlobals[name] = { _G[name] }
    _G[name] = value
end

setGlobal("RAID_CLASS_COLORS", {
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
})
setGlobal("FACTION_BAR_COLORS", {
    [1] = { r = 1, g = 0, b = 0 },
    [4] = { r = 1, g = 1, b = 0 },
})

local units = {}
setGlobal("UnitIsPlayer",  function(unit) return units[unit].player end)
setGlobal("UnitClass",     function(unit) return "class", units[unit].class end)
setGlobal("UnitReaction",  function(_, unit) return units[unit].reaction end)
setGlobal("UnitPowerType", function() return 0, "MANA" end)

--- A stand-in bar: it remembers the last colour and texture assigned.
local function newBar()
    local bar = { color = { 0, 1, 0, 1 }, texture = "native.tga" }
    function bar:SetStatusBarColor(r, g, b, a)
        self.color = { r, g, b, a }
    end
    function bar:GetStatusBarColor()
        return self.color[1], self.color[2], self.color[3], self.color[4]
    end
    function bar:SetStatusBarTexture(path) self.texture = path end
    function bar:GetStatusBarTexture() return self.texture end
    return bar
end

--- A stand-in font string for the name.
local function newLabel()
    local label = { color = { 1, 1, 1, 1 } }
    function label:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
    function label:GetTextColor()
        return self.color[1], self.color[2], self.color[3], self.color[4]
    end
    function label:SetFont() return true end
    function label:GetFont() return "font.ttf", 12, "" end
    return label
end

--- A stand-in nameplate with a unit frame inside.
local function newPlate(unit)
    local frame = { unit = unit, healthBar = newBar(), name = newLabel() }
    return { UnitFrame = frame }, frame
end

-- A client that can return a nameplate by unit. The table's name is the one
-- written down in the compatibility layer: the subsystem goes there for it.
local plates = {}
setGlobal("C_NamePlate", {
    GetNamePlateForUnit = function(unit) return plates[unit] end,
    GetNamePlates = function()
        local out = {}
        for _, plate in pairs(plates) do out[#out + 1] = plate end
        return out
    end,
})

ns.flavor = "vanilla"

local settings = {
    health      = "__native",
    healthColor = "__native",
    healthFixed = { r = 0.5, g = 0.5, b = 0.5 },
    nameColor   = "__native",
    nameFixed   = { r = 0.5, g = 0.5, b = 0.5 },
}
ns.Addon = { db = { profile = { nameplates = settings } } }

T.ok(NP.Available(), "the subsystem works in this client")

-- A fresh install: the native look, and not one object of the game's is touched.
do
    local plate, frame = newPlate("nameplate1")
    plates.nameplate1 = plate
    units.nameplate1 = { player = true, class = "MAGE", reaction = 5 }

    T.eq(NP.StyleUnit("nameplate1"), true, "the nameplate was styled")
    T.eq(frame.healthBar.texture, "native.tga", "the texture stayed native")
    T.eq(frame.healthBar.color[2], 1, "the bar's colour stayed native")
    T.eq(frame.name.color[1], 1, "the name's colour stayed native")
end

-- The colour by class. The decision is made by ns.UnitFrames.BarColor; what is
-- checked here is that the correct facts about the unit reach it.
do
    local plate, frame = newPlate("nameplate2")
    plates.nameplate2 = plate
    units.nameplate2 = { player = true, class = "MAGE", reaction = 5 }

    settings.health      = "Darken Dark"
    settings.healthColor = "class"
    settings.nameColor   = "class"

    NP.StyleUnit("nameplate2")

    T.eq(frame.healthBar.texture, "Interface\\AddOns\\Darken\\Media\\mzk-dark.tga", "our texture went on")
    T.eq(frame.healthBar.color[1], 0.41, "the bar was painted by class")
    T.eq(frame.healthBar.color[3], 0.94, "and so was the blue channel")
    T.eq(frame.name.color[1], 0.41, "the name was painted by class")
end

-- A creature has no class: we fall back to the reaction — the same rule as the
-- unit frames', and it is not rewritten here.
do
    local plate, frame = newPlate("nameplate3")
    plates.nameplate3 = plate
    units.nameplate3 = { player = false, class = "MAGE", reaction = 1 }

    NP.StyleUnit("nameplate3")

    T.eq(frame.healthBar.color[1], 1, "a creature's colour comes by reaction (red)")
    T.eq(frame.healthBar.color[2], 0, "and the green channel by reaction")
    T.eq(frame.name.color[2], 0, "a creature's name comes by reaction too")
end

-- The return to the native look: both the texture and the colour return to the
-- remembered ones rather than to our previous ones. That is precisely why a
-- look has no one-way road.
do
    local plate, frame = newPlate("nameplate4")
    plates.nameplate4 = plate
    units.nameplate4 = { player = true, class = "MAGE", reaction = 5 }

    NP.StyleUnit("nameplate4")
    T.eq(frame.healthBar.texture, "Interface\\AddOns\\Darken\\Media\\mzk-dark.tga", "our texture first")

    settings.health      = "__native"
    settings.healthColor = "__native"
    settings.nameColor   = "__native"
    NP.StyleUnit("nameplate4")

    T.eq(frame.healthBar.texture, "native.tga", "the native texture came back")
    T.eq(frame.healthBar.color[2], 1, "the bar's native colour came back")
    T.eq(frame.name.color[1], 1, "the name's native colour came back")
end

T.suite("the nameplates: applying the settings")

-- A pass over the nameplates that are on the screen right now. The rest will
-- be styled at the moment they appear: there is nothing to style what does not exist with.
do
    settings.health      = "Darken Dark"
    settings.healthColor = "class"

    NP:ApplySettings()

    local painted = 0
    for unit, plate in pairs(plates) do
        local frame = NP.UnitFrameOf(plate)
        if frame.healthBar.texture == "Interface\\AddOns\\Darken\\Media\\mzk-dark.tga" then
            painted = painted + 1
        end
    end
    T.eq(painted, 4, "every nameplate on the screen was styled")
end

T.suite("the nameplates: the repainting after the game")

-- The game repaints a bar itself, and our colour would be gone after its call.
-- The subscription to its functions leads here, and the frame arrives as an
-- argument: the work is on one frame rather than on every one on the screen.
do
    local frame = NP.UnitFrameOf(plates.nameplate2)
    frame.healthBar.color = { 0, 1, 0, 1 }

    T.eq(NP.Repaint(frame), true, "the repainting went through")
    T.eq(frame.healthBar.color[1], 0.41, "our colour came back into place")
end

-- Frames that are not ours are passed by. The game's raid frame is built out
-- of the same button, and repainting it here would be outright harm.
do
    local stranger = { unit = "party1", healthBar = newBar(), name = newLabel() }
    stranger.healthBar.color = { 0, 1, 0, 1 }
    units.party1 = { player = true, class = "MAGE", reaction = 5 }

    T.eq(NP.Repaint(stranger), false, "a frame that is not ours is not repainted")
    T.eq(stranger.healthBar.color[1], 0, "and the colour on it is untouched")
end

T.eq(NP.Repaint(nil), false, "with no frame there is nothing to repaint")

T.suite("the nameplates: standing aside for another addon")

-- Having stood aside, the subsystem touches nothing — neither on an event nor
-- on an application of the settings. Two owners of one bar give a flicker, and
-- the second owner is obliged to fall silent entirely rather than by half.
do
    local plate, frame = newPlate("nameplate9")
    plates.nameplate9 = plate
    units.nameplate9 = { player = true, class = "MAGE", reaction = 5 }

    NP.standDown = true

    T.eq(NP.StyleUnit("nameplate9"), false, "no styling is done")
    T.eq(frame.healthBar.texture, "native.tga", "the texture is untouched")
    T.eq(NP.Repaint(NP.UnitFrameOf(plates.nameplate2)), false,
         "no repainting is done")
    T.eq(NP.Available(), false, "the settings section hides itself")

    NP.standDown = nil
end

T.suite("the nameplates: the defaults")

-- A fresh install replaces neither the texture nor the colour — the same rule
-- as in the whole addon, and the native look stays not only the initial one
-- but a selectable one.
T.eq(NP.defaults.health, ns.UnitFrames.NATIVE, "the bar's texture is the native one")
T.eq(NP.defaults.healthColor, ns.UnitFrames.NATIVE, "the bar's colour is the native one")
T.eq(NP.defaults.nameColor, ns.UnitFrames.NATIVE, "the name's colour is the native one")

-- The settings' names match the unit frames' for a reason: the reuse of the
-- colour rule rests on them. A divergence would mean a second copy.
for _, field in ipairs({ "health", "healthColor", "healthFixed",
                         "nameColor", "nameFixed" }) do
    T.ok(ns.UnitFrames.defaults[field] ~= nil,
         "the setting \"" .. field .. "\" exists for the unit frames too")
end

-- The settings section hides itself when there is nothing to work with:
-- turning selects that affect nothing is worse than not seeing them at all.
do
    _G.C_NamePlate = nil
    T.eq(NP.Available(), false, "with no game API there is no section")
    T.eq(NP.options.hidden(), true, "and the section's predicate knows it")
end

-- The globals are restored: the next set of checks must not see our fakes.
--
for name, saved in pairs(savedGlobals) do _G[name] = saved[1] end
LibStub = savedLibStub
