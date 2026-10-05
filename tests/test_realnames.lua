local helpers = require("helpers")

-- The names seen in a live client rather than derived from habit.
--
-- Everything enumerated below came from one place: the `/umbra report`
-- taken on the vanilla 1.60.1 client, build 70009. The report asks the game
-- itself whether an object of that name exists and records the answer by name
-- — that is, every line here either was in the author's client or was not.
--
-- Why this check exists. The convenience of the compatibility layer's list
-- of candidates is that an extra name costs nothing: the existence filter
-- throws it out. That is exactly why it is so easy to **remove** a needed one
-- by accident — the checks will not fail, the client will not complain, and the subsystem will silently stop working.
-- A confirmed name is worth more than a guess and is lost most quietly of
-- all. Let it fail here.
--
-- How to read this: it is a fact about one build of one flavour. It says
-- "this name exists here" and says nothing about Classic Era 11507, about tbc
-- or about mists. So the check demands only a name's presence among the
-- vanilla candidates and never the absence of others.

T.suite("confirmed names: vanilla 1.60.1 (build 70009)")

local core = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", core)
local Compat = core.Compat

--- Whether a name is among a group's candidates.
-- @param group string
-- @param name string
-- @return boolean
local function declared(group, name)
    local names = Compat.GetFrameNames("vanilla", group)
    for i = 1, #names do
        if names[i] == name then return true end
    end
    return false
end

--- Every name of a group is obliged to be declared.
-- @param group string
-- @param names table
local function pin(group, names)
    for i = 1, #names do
        T.ok(declared(group, names[i]),
            group .. ": " .. names[i] .. " is confirmed by the client")
    end
end

--- A series of names numbered from one up to a ceiling.
-- @param prefix string
-- @param count number
-- @return table
local function upto(prefix, count)
    local out = {}
    for i = 1, count do out[i] = prefix .. i end
    return out
end

-- The unit frames. Three are confirmed by the report directly;
-- TargetFrameToT through its children TargetFrameToTDebuff1..4, which the
-- probe found as a list not cut off by the ceiling.
pin("unitframe", { "PlayerFrame", "TargetFrame", "PetFrame", "TargetFrameToT" })

-- The stance bar. That is the very edit the check was created for: before the
-- report vanilla carried the ShapeshiftButton prefix, and in 1.60.1 not one
-- of the ten buttons was found. StanceButton1..10 were.
pin("actionbar-stance", { "StanceBar" })
pin("actionbar-stance-buttons", upto("StanceButton", 10))

-- The Classic Era prefix stays beside it: the "vanilla" key serves build
-- 11507 too, where the stance bar is named the old way. Removing it would
-- mean fixing one client by breaking the other.
pin("actionbar-stance-buttons", upto("ShapeshiftButton", 10))

-- The action bars and their buttons.
pin("actionbar-main", { "MainActionBar" })
pin("actionbar-main-buttons", upto("ActionButton", 12))
pin("actionbar-bottomleft", { "MultiBarBottomLeft" })
pin("actionbar-bottomleft-buttons", upto("MultiBarBottomLeftButton", 12))
pin("actionbar-bottomright", { "MultiBarBottomRight" })
pin("actionbar-bottomright-buttons", upto("MultiBarBottomRightButton", 12))
pin("actionbar-left", { "MultiBarLeft" })
pin("actionbar-left-buttons", upto("MultiBarLeftButton", 12))
pin("actionbar-right", { "MultiBarRight" })
pin("actionbar-right-buttons", upto("MultiBarRightButton", 12))
pin("actionbar-pet", { "PetActionBar" })
pin("actionbar-pet-buttons", upto("PetActionButton", 10))
pin("actionbar-relayout",
    { "MultiActionBar_Update", "ActionBarController_UpdateAll" })

-- The cast bars.
pin("castbar-player", { "PlayerCastingBarFrame" })
pin("castbar-target", { "TargetFrameSpellBar" })

-- The unit frames' repainting. Six out of seven; TargetFrame_Update is not in
-- this build — the target frame family was moved onto an object's methods.
pin("unitframe-recolor", {
    "UnitFrame_Update",
    "UnitFrameHealthBar_Update",
    "UnitFrameManaBar_Update",
    "UnitFrameManaBar_UpdateType",
    "PlayerFrame_Update",
    "PlayerFrame_UpdateArt",
})

-- The nameplates. Both doors are in place and so are both repainting
-- functions: the counter of attached nameplates stands at zero for reasons other than the names.
pin("nameplate", { "C_NamePlate", "NamePlateDriverFrame" })
pin("nameplate-recolor", {
    "CompactUnitFrame_UpdateHealthColor",
    "CompactUnitFrame_UpdateName",
})

-- The compact party frames. In this build it is they that draw the party
-- rather than PartyMemberFrame1..4, which are not here at all.
pin("raidframe-container", { "CompactRaidFrameContainer", "CompactPartyFrame" })
pin("raidframe-member", upto("CompactPartyFrameMember", 5))
pin("raidframe-setup", { "DefaultCompactUnitFrameSetupOptions" })
pin("raidframe-relayout", {
    "CompactRaidFrameManager_UpdateShown",
    "CompactPartyFrame_Generate",
    "CompactUnitFrame_SetUpFrame",
    "DefaultCompactUnitFrameSetup",
})

-- The player's aura grid.
pin("auras", { "BuffFrame", "DebuffFrame" })

-- The equipment slots: all nineteen are in place.
pin("equipment-slots", {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
    "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
    "CharacterTabardSlot", "CharacterWristSlot", "CharacterHandsSlot",
    "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot",
    "CharacterTrinket1Slot", "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot", "CharacterRangedSlot",
})

-- The bag windows and their redrawing.
pin("bag-window", { "ContainerFrameCombinedBags" })
pin("bag-repaint", {
    "ContainerFrame_GenerateFrame", "ContainerFrame_OnShow",
    "ToggleAllBags", "OpenAllBags",
})

-- The interface's framing.
pin("minimap", { "MinimapCluster", "MinimapBackdrop", "GameTimeFrame" })
pin("objectives", { "ObjectiveTrackerFrame", "QuestTimerFrame" })
pin("chat", {
    "ChatFrame1", "ChatFrame1Tab", "ChatFrame1EditBox",
    "ChatFrame1ButtonFrame", "GeneralDockManager", "ChatFrameMenuButton",
})
pin("tooltip", {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
})
pin("character", {
    "CharacterFrame", "PaperDollFrame", "PaperDollItemsFrame",
    "ReputationFrame", "TokenFrame",
})
pin("questlog", {
    "QuestFrame", "QuestFrameDetailPanel", "QuestFrameRewardPanel",
    "QuestFrameProgressPanel", "QuestFrameGreetingPanel",
})

T.suite("confirmed watched paths: vanilla 1.60.1")

-- The list of guesses the author asked to be named one by one. Nine out of
-- sixteen were found, and the ones found must not vanish from the list: the
-- report about the next client is compared against this one.
local watch = {}
do
    local list = Compat.Watchlist()
    for i = 1, #list do watch[list[i].path] = true end
end

local CONFIRMED_PATHS = {
    "DefaultCompactUnitFrameSetupOptions",
    "CompactUnitFrame_SetUpFrame",
    "UnitFrameHealthBar_Update",
    "CompactUnitFrame_UpdateHealthColor",
    "MultiActionBar_Update",
    "C_NamePlate",
    "ContainerFrameCombinedBags",
}

for i = 1, #CONFIRMED_PATHS do
    T.ok(watch[CONFIRMED_PATHS[i]] == true,
        CONFIRMED_PATHS[i] .. ": the path is still watched")
end

-- What was not found stays watched as well: having vanished from the list it
-- would stop getting into the report, and the next client would stay silent about the same thing.
local ABSENT_PATHS = {
    "CompactRaidFrameContainer_LayoutFrames",
    "TargetFrame_UpdateAuras",
    "TargetFrame_UpdateAuraPositions",
    "CompactUnitFrame_UpdateAuras",
    "UIParent_ManageFramePositions",
}

for i = 1, #ABSENT_PATHS do
    T.ok(watch[ABSENT_PATHS[i]] == true,
        ABSENT_PATHS[i] .. ": the path that was not found is still watched")
end

T.suite("what does not exist in 1.60.1: declared for the second build's sake")

-- These names were not found in 1.60.1, and removing them is still not
-- allowed: the "vanilla" key is two builds, 11507 and 16001, and in Classic
-- Era they are in place. The check stands here so that "clean up by the report" does not pass silently.
local KEPT_FOR_ERA = {
    unitframe = upto("PartyMemberFrame", 4),
    -- The framing's container is written down as two paths rather than as a
    -- bare name: bare it always meant "two fields inside it", and the list of
    -- those fields lay in the subsystem. For Classic Era that is the same as
    -- it was; for 1.60 the report will now say how far it got.
    ["actionbar-art"] = {
        "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
        "MainMenuBarArtFrame.LeftEndCap", "MainMenuBarArtFrame.RightEndCap",
    },
    ["actionbar-main"] = { "MainMenuBar" },
}

local KEPT_ORDER = { "unitframe", "actionbar-art", "actionbar-main" }
for i = 1, #KEPT_ORDER do
    local group = KEPT_ORDER[i]
    local names = KEPT_FOR_ERA[group]
    for j = 1, #names do
        T.ok(declared(group, names[j]),
            group .. ": " .. names[j] .. " is kept for Classic Era's sake")
    end
end
