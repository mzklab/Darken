local ADDON, ns = ...

-- The compatibility layer. Everything that differs between clients lives
-- here. Modules never check the client's version themselves.
local Compat = {}
ns.Compat = Compat

-- The flavours the addon supports. The order does not matter.
local SUPPORTED = {
    vanilla = true,   -- Classic Era, Hardcore
    tbc     = true,   -- Burning Crusade Classic
    mists   = true,   -- Mists of Pandaria Classic
}

-- Blizzard's frame names by group, separately for each flavour.
-- This is the only place in the addon where other people's frame names
-- occur. At stage 0 the table is filled only as far as the tests and the load
-- check need; the remaining groups are added by their own stages.
-- About the cast bars separately. The groups are split by unit rather than
-- gathered into one: the spec requires the player's, the target's and the
-- focus's bars to be configured separately, and a settings page for a bar the
-- client does not have must not be shown. One shared group gives no such
-- distinction.
--
-- Vanilla has no focus cast bar at all: the focus itself appeared in TBC. So
-- vanilla has no castbar-focus group — not as an empty list but as a missing
-- key: an empty list would mean "the group exists but is empty today", while
-- here we are speaking of a client where it never exists.
--
-- The player's bar is written as two candidates: some builds call it one
-- thing, some another. Which of the names is the real one is decided not by
-- this table but by Compat.FilterExisting: what the client does not have does
-- not reach a module.
local FRAMES = {
    vanilla = {
        -- What is known about this list comes from the live 1.60.1 client
        -- (build 70009): the player, target and pet frames are there, while
        -- not one of the four party member frames is — in that build the
        -- party is drawn by the compact frames, and those are already
        -- declared as the raidframe-member group, with a subsystem and
        -- settings of their own. Repeating them here would style one frame
        -- twice.
        --
        -- The party member frames must not be removed, though: the vanilla
        -- flavour is two builds at once (11507 and 16001), and in Classic Era
        -- those frames are in place. Hence the "partial" in the report on
        -- 1.60.1: not a mistake in the names but one key for two different
        -- clients.
        unitframe = {
            "PlayerFrame",
            "TargetFrame",
            -- The target-of-target frame. Confirmed indirectly and firmly:
            -- the scan for the Debuff pattern (a complete list, not
            -- truncated by the cap) found its children in 1.60.1.
            "TargetFrameToT",
            "PetFrame",
            "PartyMemberFrame1",
            "PartyMemberFrame2",
            "PartyMemberFrame3",
            "PartyMemberFrame4",
        },
        ["castbar-player"] = {
            "CastingBarFrame",
            "PlayerCastingBarFrame",
        },
        ["castbar-target"] = {
            "TargetFrameSpellBar",
        },
    },
    tbc = {
        unitframe = {
            "PlayerFrame",
            "TargetFrame",
            "TargetFrameToT",
            "PetFrame",
            "PartyMemberFrame1",
            "PartyMemberFrame2",
            "PartyMemberFrame3",
            "PartyMemberFrame4",
        },
        ["castbar-player"] = {
            "CastingBarFrame",
            "PlayerCastingBarFrame",
        },
        ["castbar-target"] = {
            "TargetFrameSpellBar",
        },
        ["castbar-focus"] = {
            "FocusFrameSpellBar",
        },
    },
    mists = {
        unitframe = {
            "PlayerFrame",
            "TargetFrame",
            "TargetFrameToT",
            "FocusFrame",
            "PetFrame",
        },
        ["castbar-player"] = {
            "CastingBarFrame",
            "PlayerCastingBarFrame",
        },
        ["castbar-target"] = {
            "TargetFrameSpellBar",
        },
        ["castbar-focus"] = {
            "FocusFrameSpellBar",
        },
    },
}


-- The action bars. Two groups per bar: the bar itself (it is moved, scaled
-- and made transparent) and its buttons (they are laid out and hidden). The
-- split is not convenience: a bar is an ordinary frame while a button is a
-- button the engine protects, built on a secure template, and working with
-- them obeys different rules.
--
-- The button names are built from a prefix and a number: twelve lines in a
-- row would read worse, and a wrong number would be easier to make. These
-- are still candidates: what the client does not have, Compat.FilterExisting
-- discards before a module sees it.
-- @param prefix string the name's prefix
-- @param count number how many numbers
-- @return table array of names
local function series(prefix, count)
    local out = {}
    for i = 1, count do out[i] = prefix .. i end
    return out
end

--- The stance bar's buttons across several prefixes at once.
--
-- There is more than one prefix because one flavour is not one client. The
-- vanilla key serves two builds at once, because the interface number of
-- both starts with a one (Compat.DetectFlavor looks at the leading part):
-- Classic Era 11507/11509 and Forever 16001. Their stance bar is named
-- differently, and choosing one prefix would break the other build silently.
--
-- Their TOC files are DIFFERENT, though: Darken_Vanilla.toc and
-- Darken_Camelot.toc. One flavour of code is not one TOC file, and the two
-- divisions must not be confused: the client chooses a file by its own
-- prefix, while the code chooses frame names by the leading part of the
-- number.
--
-- Twenty buttons instead of ten do not result from this: the scan in 1.60.1
-- (build 70009) ran the Shapeshift pattern and found no object with such a
-- name in the client at all, while the stance buttons are there. The two sets
-- do not occur in one client, and the extra one is filtered out by
-- Compat.FilterExisting.
-- @param prefixes table array of prefixes
-- @param count number how many numbers per prefix
-- @return table array of names
local function stanceSeries(prefixes, count)
    local out = {}
    for i = 1, #prefixes do
        local names = series(prefixes[i], count)
        for j = 1, #names do out[#out + 1] = names[j] end
    end
    return out
end

--- The action bar groups for one flavour.
--
-- The prefix of the stance bar's buttons differs between clients, so it
-- arrives as an argument: the compatibility table is the only place in the
-- addon allowed to know about such differences. Modules do not see it and do
-- not check the client's version.
--
-- The decorative chrome (the gryphons) is written both as separate textures
-- and as a holder frame: on some clients they are global textures, on others
-- fields inside a frame. The subsystem handles both kinds, and a surplus
-- candidate never reaches it.
--
-- More is known about the chrome's names than about the rest, and what is
-- known is bad: in the live 1.60.1 client (build 70009) not one of the three
-- globals is there, and neither is the main bar under its older name — the
-- bar is called something else there. The global names were kept for the
-- sake of the same flavour's other build, Classic Era 11507, where that
-- family is in place.
--
-- What the chrome is called in 1.60 the scan cannot say and never will: it
-- collects globals, while in newer builds the gryphons are a field inside a
-- frame and have no global name. But there is now something to name a field
-- with — a dotted path — and the group holds four such candidates. The next
-- report answers them: it checks every step of a path and prints how far it
-- got. If neither a path nor a name resolves, /framestack on the gryphon
-- itself remains; and if there are no gryphons on screen at all, then this
-- build has no such group — and its place is a missing key rather than an
-- empty list.
--
-- The names of the game's own functions that reposition the bars themselves
-- (a form change, a vehicle, entering a dungeon) form a group of their own.
-- Compat.FilterExisting checks an object's existence in _G, and a function is
-- as much an object as a frame: a non-existent name is filtered out the same
-- way.
--
-- @param stance table the prefixes of the stance bar's button names
-- @return table the groups
local function actionBarGroups(stance)
    return {
        ["actionbar-main"]         = { "MainMenuBar", "MainActionBar" },
        ["actionbar-main-buttons"] = series("ActionButton", 12),

        ["actionbar-bottomleft"]         = { "MultiBarBottomLeft" },
        ["actionbar-bottomleft-buttons"] = series("MultiBarBottomLeftButton", 12),

        ["actionbar-bottomright"]         = { "MultiBarBottomRight" },
        ["actionbar-bottomright-buttons"] = series("MultiBarBottomRightButton", 12),

        ["actionbar-right"]         = { "MultiBarRight" },
        ["actionbar-right-buttons"] = series("MultiBarRightButton", 12),

        ["actionbar-left"]         = { "MultiBarLeft" },
        ["actionbar-left-buttons"] = series("MultiBarLeftButton", 12),

        ["actionbar-pet"]         = { "PetActionBarFrame", "PetActionBar" },
        ["actionbar-pet-buttons"] = series("PetActionButton", 10),

        ["actionbar-stance"]         = { "StanceBarFrame", "ShapeshiftBarFrame",
                                         "StanceBar" },
        ["actionbar-stance-buttons"] = stanceSeries(stance, 10),

        -- The "leave vehicle" button. Three names: the game renamed it
        -- twice, and a different one is alive in each build.
        --
        -- It is a group of its own not for tidiness. The button is a child of
        -- the main bar, and whoever hides the main bar hides along with it
        -- the only way to dismount: the player is left sitting astride with
        -- no exit button, and only logging out brings it back. Whoever hides
        -- the bars must ask here first.
        ["actionbar-vehicle"] = {
            "MainMenuBarVehicleLeaveButton",
            "VehicleExitButton",
            "OverrideActionBarLeaveFrameLeaveButton",
        },

        -- The quest button and the zone ability: they come and go on their
        -- own, live outside the bars and must not be hidden along with
        -- them.
        ["actionbar-extra"] = {
            "ExtraActionBarFrame",
            "ExtraActionButton1",
            "ZoneAbilityFrame",
        },

        -- The decorative chrome: three global names and four paths.
        --
        -- The global names are correct for the older code base (Classic Era
        -- 11507) and must not be removed: the vanilla key serves two builds.
        -- In 1.60.1 not one of them is there, and there is no replacement
        -- among the globals at all — the chrome there is a field inside a
        -- frame, and a field has no global name. There used to be nothing to
        -- name it with; now there is.
        --
        -- The paths written here are exactly the ones the previous
        -- reconciliation put on the watch list, plus the left one's right
        -- twin and a nested spelling: the end-caps holder by itself is an
        -- answer too, and then what has to be hidden is what is inside it.
        --
        -- The art-frame holder stands here as paths rather than as a bare
        -- name, and that is not a change of behaviour but a record of what
        -- was. As a bare name it meant the holder whose two fields the
        -- subsystem hid, and the list of those fields lived in the subsystem
        -- itself — a second piece of knowledge about somebody else's
        -- structure, kept outside this file. The holder itself must not be
        -- hidden: in the older code base it carries the bar's whole artwork
        -- rather than only the gryphons.
        --
        -- These are still candidates, and a surplus candidate costs nothing:
        -- Compat.Resolve checks every step of a path and returns only what
        -- this client has.
        ["actionbar-art"] = {
            "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
            "MainMenuBarArtFrame.LeftEndCap",
            "MainMenuBarArtFrame.RightEndCap",
            "MainActionBar.LeftEndCap", "MainActionBar.RightEndCap",
            "MainActionBar.EndCaps.LeftEndCap",
            "MainActionBar.EndCaps.RightEndCap",
        },

        -- The interface's edit mode. On clients that have it, the POSITION
        -- of the bars and unit frames belongs to it: it moves them, it saves
        -- them, and the engine forbids an addon to move them at the same
        -- minute.
        --
        -- The name is needed not in order to meddle with it but for exactly
        -- the opposite reason — to ask "is it open right now" and do
        -- nothing.
        ["editmode"] = {
            "EditModeManagerFrame",
        },

        -- Switching tabs inside a window that is already open.
        --
        -- These are looked up in order to learn the moment the game fills a
        -- window afresh. ShowUIPanel is not called then: the window is
        -- already open and it is its insides that change — the reputation
        -- list, the skill list, the statistics page. The traversal does not
        -- reach there, and the strings created by the switch stay
        -- untouched.
        --
        -- There are several names because tabs open differently in different
        -- builds; a non-existent name simply is not found.
        ["panel-switch"] = {
            "ToggleCharacter",
            "CharacterFrame_ShowSubFrame",
            "TogglePVPFrame",
            "ToggleAchievementFrame",
            "PanelTemplates_SetTab",
        },

        -- Opening the bags. Separate from panel-switch, because the bags
        -- open bypassing ShowUIPanel entirely: they have calls of their own,
        -- and the game builds the slots window at that moment.
        ["bag-toggle"] = {
            "ToggleBackpack",
            "OpenBackpack",
            "OpenAllBags",
            "ToggleAllBags",
            "OpenBag",
        },

        -- The bag slot windows. They are looked up in order to walk exactly
        -- those when the player opened a bag: a full traversal of the
        -- interface on every bag opening cost the game a stall.
        ["bag-frames"] = {
            "ContainerFrameCombinedBags",
            "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
            "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
            "ContainerFrame7", "ContainerFrame8", "ContainerFrame9",
            "ContainerFrame10", "ContainerFrame11", "ContainerFrame12",
            "ContainerFrame13",
            "BankFrame",
        },

        ["actionbar-relayout"] = {
            "MultiActionBar_Update",
            "ActionBarController_UpdateAll",
            "MainMenuBar_Update",
            "UIParent_ManageFramePositions",
        },
    }
end

-- The game's own functions that recolour the unit frames' bars. These are
-- names of functions rather than frames, but the rule is the same: somebody
-- else's name lives only here, and Compat.FilterExisting checks an object's
-- existence in _G — to it a function is as much an object as a frame.
--
-- Why they are needed. The game assigns the health and power bar colours
-- itself on every update of a unit: a change of target, a change in health, a
-- change of form or of power type. Our colour would be gone after such a
-- call, and "by class" would look like it worked every other time. So the
-- unit frames subsystem attaches to these functions through hooksecurefunc —
-- after their work rather than instead of it.
--
-- The list is candidates: in different builds some of the names are absent,
-- and that is normal. It is the same for every flavour, so it is handed out
-- in a loop: three copies of one list would diverge at the very first
-- edit.
local UNITFRAME_RECOLOR = {
    "UnitFrame_Update",
    "UnitFrameHealthBar_Update",
    "UnitFrameManaBar_Update",
    "UnitFrameManaBar_UpdateType",
    "TargetFrame_Update",
    "PlayerFrame_Update",
    "PlayerFrame_UpdateArt",
}

for _, byFlavor in pairs(FRAMES) do
    local names = {}
    for i = 1, #UNITFRAME_RECOLOR do names[i] = UNITFRAME_RECOLOR[i] end
    byFlavor["unitframe-recolor"] = names
end

-- The aura icons on the unit frames: the auras of the target, the focus, the
-- pet and the party members.
--
-- These are buttons the game lays out on its own unit frames itself, and
-- until now they were not here at all. The compact auras module found them by
-- WALKING THE STRUCTURE — a descendant with a Cooldown child and a texture —
-- and that walk worked. But "find somebody else's object by its shape" is
-- knowledge about somebody else's structure living outside this file: let the
-- frame's contents change and the walk silently stops finding anything, in
-- exactly the way a list of names that drifted apart stays silent. The one
-- place that knows other people's names exists for this.
--
-- The names are guesses, like everything in this file, and that is admissible
-- precisely because Compat.FilterExisting discards a guess: what the client
-- does not have does not reach a module. A client in which none of them was
-- found yields an empty group — and the module is left with its walk of the
-- structure, that is, behaves exactly as it did before this group existed.
--
-- The numbers are caps on slots rather than facts: how many icons the game
-- shows today is its decision, and a surplus name costs nothing.
--
-- Vanilla has no focus at all (it appeared in TBC), so its names are not
-- handed out for vanilla: not as an empty list but as the absence of the
-- names themselves. The compact party and raid frames are deliberately not
-- included — the game creates their aura icons on the fly and gives them no
-- global names; the walk of the structure still works there.
local TARGET_AURA_LIMIT = 16   -- aura slots on the target frame
local FOCUS_AURA_LIMIT  = 8    -- on the focus frame
local PARTY_AURA_LIMIT  = 4    -- on a party member's frame
local PET_AURA_LIMIT    = 4    -- on the pet frame
local PARTY_MEMBER_LIMIT = 4   -- party members, the player aside

--- The names of one unit frame's buff and debuff icons.
-- @param prefix string the frame name's prefix
-- @param count number how many slots
-- @return table array of names
local function auraButtonNames(prefix, count)
    local out = {}
    for i = 1, count do
        out[#out + 1] = prefix .. "Buff" .. i
        out[#out + 1] = prefix .. "Debuff" .. i
    end
    return out
end

--- Every unit frame aura icon of one flavour.
-- @param flavor string
-- @return table array of names
local function unitFrameAuraNames(flavor)
    local out = {}

    local function add(names)
        for i = 1, #names do out[#out + 1] = names[i] end
    end

    add(auraButtonNames("TargetFrame", TARGET_AURA_LIMIT))
    if flavor ~= "vanilla" then
        add(auraButtonNames("FocusFrame", FOCUS_AURA_LIMIT))
    end
    for member = 1, PARTY_MEMBER_LIMIT do
        add(auraButtonNames("PartyMemberFrame" .. member, PARTY_AURA_LIMIT))
    end
    add(auraButtonNames("PetFrame", PET_AURA_LIMIT))

    return out
end

for flavor, byFlavor in pairs(FRAMES) do
    if byFlavor["unitframe-auras"] ~= nil then
        error("frame group declared twice: unitframe-auras", 0)
    end
    byFlavor["unitframe-auras"] = unitFrameAuraNames(flavor)
end

-- The game's own functions that reposition those icons.
--
-- The rule is the one the unitframe-recolor, actionbar-relayout and
-- bag-repaint groups follow, and this group exists for the same reason:
-- attaching through hooksecurefunc means standing AFTER the game by
-- construction rather than after a delay that happened to be enough. Without
-- it the subsystem is left waiting for the next frame: the game changes the
-- auras on the same event we wake on, and the order of two subscribers to one
-- event is not promised by the engine.
--
-- The list is candidates: some builds keep the layout in an object's methods
-- rather than in global functions, and then the group comes out empty. That
-- is not a failure: waiting for a frame remains and works.
--
-- Build 1.60.1 (70009) is exactly such a one: not one of the seven names is
-- there, and the target frame's update function is gone along with them,
-- while the player frame's is in place. The target frame family was moved to
-- object methods, and the group is empty there by the client's construction
-- rather than by a mistake in spelling.
--
-- The scan could long neither confirm nor refute this group: Scan.Collect
-- took only objects with frame-like behaviour (rawget(value, 0) is userdata),
-- and a function does not pass that check, so the directory was silent about
-- six groups of function names entirely. It now collects functions too, in a
-- list of their own (scan.functions), and "the name is spelled wrong" is
-- distinguishable from "no function of that name exists in the client". The
-- 1.60.1 run above was taken by the older scan, that is, from one report; the
-- next one will answer from the directory as well.
local UNITFRAME_AURA_RELAYOUT = {
    "TargetFrame_UpdateAuras",
    "TargetFrame_UpdateAuraPositions",
    "FocusFrame_UpdateAuras",
    "PartyMemberFrame_UpdateAuras",
    "CompactUnitFrame_UpdateAuras",
    "CompactUnitFrame_UpdateBuffs",
    "CompactUnitFrame_UpdateDebuffs",
}

for _, byFlavor in pairs(FRAMES) do
    if byFlavor["unitframe-auras-relayout"] ~= nil then
        error("frame group declared twice: unitframe-auras-relayout", 0)
    end
    local copy = {}
    for i = 1, #UNITFRAME_AURA_RELAYOUT do
        copy[i] = UNITFRAME_AURA_RELAYOUT[i]
    end
    byFlavor["unitframe-auras-relayout"] = copy
end

-- Nameplates. Two groups, and neither is frames in the usual sense.
--
-- The first (nameplate) is what the nameplate styling subsystem cannot work
-- without at all: the game API table that returns a nameplate's frame for a
-- unit, and the driver frame that creates those nameplates. The nameplates
-- themselves are not enumerated by name and cannot be: the game creates and
-- dismantles them constantly, as creatures appear on screen, and a list of
-- names would be stale a second after it was written.
--
-- The second (nameplate-recolor) is the names of the game's functions that
-- recolour a nameplate's bar and name. The rule is the unitframe-recolor
-- group's: our colour would be gone after their work, so the subsystem stands
-- after them through hooksecurefunc rather than instead of them.
--
-- Candidates, like everything in this file: Compat.FilterExisting checks an
-- object's existence in _G, and a table and a function are as much objects as
-- a frame. What the client does not have does not reach a module.
local NAMEPLATE = {
    nameplate = {
        "C_NamePlate",
        "NamePlateDriverFrame",
    },
    ["nameplate-recolor"] = {
        "CompactUnitFrame_UpdateHealthColor",
        "CompactUnitFrame_UpdateName",
    },
}

for _, byFlavor in pairs(FRAMES) do
    for group, names in pairs(NAMEPLATE) do
        if byFlavor[group] ~= nil then
            error("frame group declared twice: " .. group, 0)
        end
        local copy = {}
        for i = 1, #names do copy[i] = names[i] end
        byFlavor[group] = copy
    end
end

-- The interface chrome the dimming subsystem darkens.
--
-- These are the same candidates as everywhere in this file: what the client
-- does not have will not reach a module (Compat.FilterExisting). So a surplus
-- name costs nothing, while a missing one costs exactly what the author
-- complained about: "the slider dims the unit frames and nothing else".
--
-- The groups are divided by what the player calls them rather than by how
-- they are built inside: the exceptions list is for the player, and the row
-- "map" in it has to mean the whole map, together with its border and its
-- buttons.
--
-- The map itself, the portraits, the spell icons and the character model
-- never darken — that is decided not by this table of names but by the
-- selection rule in Modules/Darkness.lua: what is listed here is where to
-- look, not what to paint.
--
-- The list is the same for every flavour and is handed out in a loop: three
-- copies would diverge at the very first edit.
local CHROME = {
    minimap = {
        "MinimapCluster",
        "MinimapBackdrop",
        "MinimapBorder",
        "MinimapBorderTop",
        "MiniMapTrackingFrame",
        "MiniMapTrackingBorder",
        "MiniMapMailFrame",
        "MiniMapMailBorder",
        "MiniMapWorldMapButton",
        "MiniMapBattlefieldFrame",
        "MinimapZoneTextButton",
        "MinimapZoomIn",
        "MinimapZoomOut",
        "GameTimeFrame",
    },

    -- The ring around the minimap, on its own.
    --
    -- It is part of the group above and is darkened with it; it is named
    -- separately because one setting needs to HIDE it rather than paint it.
    -- A square minimap keeps the ring drawn across its corners, which reads
    -- as a broken addon rather than as a square map.
    --
    -- Here rather than in the module for the reason this whole file exists:
    -- a name of the game's lives in one place, and a second copy of it in a
    -- module would go stale without anyone noticing.
    ["minimap-ring"] = {
        -- The ring is drawn by different art from one client line to the
        -- next, and the names are not guessable: on the 1.60 line it is the
        -- compass, and the report said so in one line - "group minimap-ring
        -- resolved to nothing (2 names tried)" - while /dark scan minimap
        -- listed what is really there. The two it used to name are kept
        -- behind them for the lines that do have them.
        "MinimapCompassTexture",
        "MinimapCompassTextureUnderlay",
        "MinimapBorder",
        "MinimapBorderTop",
    },

    -- The world map's canvas: the terrain and the icons on it.
    --
    -- The group is needed not in order to reach into it but for exactly the
    -- opposite reason — so that the dimming passes it by. A map is a picture
    -- of the world, as the minimap is: it is read, and the icons on it are
    -- told apart by colour.
    --
    -- There are several names because there are several builds: in the older
    -- ones the map was a detail frame with a button on top, in the present
    -- ones a scroll container inside the map window (a dotted path, which the
    -- layer handles). A surplus name this client does not have simply is not
    -- found.
    ["map-canvas"] = {
        "WorldMapFrame.ScrollContainer",
        "WorldMapDetailFrame",
        "WorldMapButton",
        "BattlefieldMapFrame.ScrollContainer",
        "BattlefieldMapTab",
    },

    -- The colour picker. It is looked up so that the dimming passes it by:
    -- the colour wheel and the swatches are the very thing being chosen from,
    -- and a dimmed (let alone desaturated) wheel offers nothing to choose.
    ["color-picker"] = {
        "ColorPickerFrame",
        "OpacitySliderFrame",
    },

    objectives = {
        "ObjectiveTrackerFrame",
        "QuestWatchFrame",
        "WatchFrame",
        "QuestTimerFrame",
    },

    chat = {
        "ChatFrame1",
        "ChatFrame1Tab",
        "ChatFrame1EditBox",
        "ChatFrame1ButtonFrame",
        "GeneralDockManager",
        "ChatFrameMenuButton",
        "FriendsMicroButton",
    },

    bags = {
        "MainMenuBarBackpackButton",
        "CharacterBag0Slot",
        "CharacterBag1Slot",
        "CharacterBag2Slot",
        "CharacterBag3Slot",
        "KeyRingButton",
        "MicroButtonAndBagsBar",
        "CharacterMicroButton",
        "SpellbookMicroButton",
        "TalentMicroButton",
        "QuestLogMicroButton",
        "SocialsMicroButton",
        "WorldMapMicroButton",
        "MainMenuMicroButton",
        "HelpMicroButton",
        "LFGMicroButton",
        "AchievementMicroButton",
        "GuildMicroButton",
        "PVPMicroButton",
        "CollectionsMicroButton",
        "EJMicroButton",
        "StoreMicroButton",
    },

    tooltip = {
        "GameTooltip",
        "ItemRefTooltip",
        "ShoppingTooltip1",
        "ShoppingTooltip2",
        "WorldMapTooltip",
    },

    character = {
        "CharacterFrame",
        "CharacterFrameInset",
        "PaperDollFrame",
        "PaperDollItemsFrame",
        "CharacterAttributesFrame",
        "ReputationFrame",
        "SkillFrame",
        "PetPaperDollFrame",
        "TokenFrame",
    },

    -- The windows whose text is printed DARK on light: quests, a
    -- conversation with a creature, books and letters. The only such place in
    -- the game — everywhere else the letters are light.
    --
    -- A conversation lives here rather than among the other windows, and that
    -- is not a liberty: the player reads them in one and the same motion and
    -- considers them one and the same sheet, and the dimming decides the same
    -- thing about them.
    questlog = {
        "QuestLogFrame",
        "QuestLogDetailFrame",
        "QuestLogDetailScrollFrame",
        "QuestFrame",
        "QuestFrameDetailPanel",
        "QuestFrameRewardPanel",
        "QuestFrameProgressPanel",
        "QuestFrameGreetingPanel",
        "GossipFrame",
        "GossipFrameGreetingPanel",
        "ItemTextFrame",
        "QuestMapDetailsScrollFrame",
        "QuestScrollFrame",

        -- The quest window detached from the map, and the trainer's window.
        -- Both are written dark on light, both were darkened by the general
        -- pass, and the author sent both as screenshots with the words "the
        -- text is unreadable".
        "QuestLogPopupDetailFrame",
        "ClassTrainerFrame",
    },
}

for _, byFlavor in pairs(FRAMES) do
    for group, names in pairs(CHROME) do
        if byFlavor[group] ~= nil then
            error("frame group declared twice: " .. group, 0)
        end
        local copy = {}
        for i = 1, #names do copy[i] = names[i] end
        byFlavor[group] = copy
    end
end

-- The bag windows. This is not the bags group above: that one lists the bag
-- buttons on the main bar and in the micro menu — what is visible at all
-- times. Here are the windows with the items, which the game opens when those
-- buttons are pressed. They are separated because the player calls them by
-- different words and excludes them from the dimming separately: "the bag
-- buttons" and "an open bag" are two different places on screen.
--
-- The names are candidates by the file's general rule: vanilla has five bag
-- windows (the backpack plus four bags), later clients have more, and working
-- out how many there are today is not the list's job but
-- Compat.FilterExisting's. The same for every flavour and handed out in a
-- loop: three copies would diverge at the very first edit.
local BAG_WINDOW_LIMIT = 13

-- The largest number of slots in one bag. An upper bound too rather than a
-- fact: in vanilla the largest bag holds sixteen slots, in later clients
-- more. A surplus name is filtered out by the same existence filter.
local BAG_SLOT_LIMIT = 36

-- What the names of a bag window's parts are built from. The suffixes are as
-- much somebody else's names as the frame names are, and therefore live here
-- rather than in a subsystem: a slot's name is assembled from the window's
-- name and this table.
local BAG_PARTS = {
    slot  = "Item",        -- a slot button, with a number at the end
    money = "MoneyFrame",  -- the money frame (the backpack's only)
    title = "Name",        -- the label with the bag's name
}

local BAG_WINDOWS = {}
for i = 1, BAG_WINDOW_LIMIT do BAG_WINDOWS[i] = "ContainerFrame" .. i end

-- The "all bags in one list" window. In later clients the player can combine
-- the bags into one window, and then the separate bag frames are not shown at
-- all while the items lie in this one. A subsystem that does not know it does
-- nothing silently on such a client — neither styling nor replacement.
--
-- The name is a candidate like all the others in this file, and it came here
-- by the general naming rule rather than from a live client. It is handed out
-- to every flavour: deciding whether it exists today is
-- Compat.FilterExisting's business, not the list's.
BAG_WINDOWS[#BAG_WINDOWS + 1] = "ContainerFrameCombinedBags"

for _, byFlavor in pairs(FRAMES) do
    if byFlavor["bag-window"] ~= nil then
        error("frame group declared twice: bag-window", 0)
    end
    local copy = {}
    for i = 1, #BAG_WINDOWS do copy[i] = BAG_WINDOWS[i] end
    byFlavor["bag-window"] = copy
end

-- The game's own functions that redraw a bag window: they lay out the slots
-- and update the icons and labels. Our styling would be wiped after their
-- work, so the subsystem stands after them through hooksecurefunc — after
-- them rather than instead of them. The rule is the unitframe-recolor and
-- actionbar-relayout groups', and the names here are the same kind of
-- candidates: to Compat.FilterExisting a function is as much an object in _G
-- as a frame.
local BAG_REPAINT = {
    "ContainerFrame_Update",
    "ContainerFrame_GenerateFrame",
    "ContainerFrame_OnShow",
    "ToggleAllBags",
    "OpenAllBags",
}

for _, byFlavor in pairs(FRAMES) do
    if byFlavor["bag-repaint"] ~= nil then
        error("frame group declared twice: bag-repaint", 0)
    end
    local copy = {}
    for i = 1, #BAG_REPAINT do copy[i] = BAG_REPAINT[i] end
    byFlavor["bag-repaint"] = copy
end

-- The character's specialization: which one is chosen right now.
--
-- THIS GENUINELY DIFFERS between the supported clients, and the difference is
-- not in a name's spelling but in the concept itself. On the early line there
-- are no specializations at all: there is a talent tree, and "change
-- specialization" means unlearning at a trainer for money. On the later line
-- they exist and are switched between fights.
--
-- So the group is declared for one flavour rather than handed out to all.
-- Handed out to all, it would appear in the report as "the name was not
-- found" on early clients — that is, as our mistake, whereas the right answer
-- there is "there is no such concept".
--
-- Why the core needs this function. The raid frames' click sets are chosen by
-- specialization: a healer needs the left button for healing, the same healer
-- in another specialization for targeting. A module has to ask the client
-- whether they exist rather than ask the player, and to ask through the
-- compatibility layer: a second list of other people's names inside a
-- module's folder would diverge from this one silently.
if FRAMES.mists then
    if FRAMES.mists["player-spec"] ~= nil then
        error("frame group declared twice: player-spec", 0)
    end
    FRAMES.mists["player-spec"] = { "GetSpecialization" }
end

--- Hand the groups out to every flavour, each its own copy.
--
-- A copy rather than a shared array: a group goes out through
-- Compat.GetFrameNames, and one array for three flavours would mean that
-- editing the list for one client silently changes it for all. Declaring a
-- group twice is a load-time error rather than a quiet overwrite: two entries
-- about one group mean one of them has no effect, and that is worth learning
-- at once.
--
-- @param groups table group -> array of names
local function distribute(groups)
    for _, byFlavor in pairs(FRAMES) do
        for group, names in pairs(groups) do
            if byFlavor[group] ~= nil then
                error("frame group declared twice: " .. group, 0)
            end
            local copy = {}
            for i = 1, #names do copy[i] = names[i] end
            byFlavor[group] = copy
        end
    end
end

-- The game's standard grid of the player's buffs and debuffs.
--
-- The group exists for the compact auras module: it moves that grid under a
-- hidden frame and gives it back when switched off. The module no longer
-- carries a list of names of its own — otherwise there would be two lists of
-- somebody else's names, and they would diverge silently, in exactly the way
-- this whole file is written against.
--
-- The set differs between the clients' lines: the early builds have no
-- separate debuff frame (the debuffs live inside the buff frame), and the
-- consolidated buffs are not everywhere. Working out what exists today is not
-- the list's job but Compat.FilterExisting's.
local AURAS = {
    "BuffFrame",
    "DebuffFrame",
    "TemporaryEnchantFrame",
    "ConsolidatedBuffs",
}

-- The equipment slot buttons: the character window and the inspect window.
--
-- The suffixes are as much somebody else's names as the frame names are, and
-- therefore live here: a slot's name is assembled from the window's prefix
-- and this list. The order is the one the slots follow on the doll.
--
-- The slot numbers are deliberately not exposed from here: a button knows its
-- own number (button:GetID()), and asking it is more reliable than
-- establishing a second piece of knowledge about somebody else's window — the
-- very rule the bag slots are handled by.
local EQUIPMENT_SLOTS = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "ShirtSlot", "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot",
    "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot",
    "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

--- The slot button names for one window.
-- @param prefix string the window's prefix
-- @return table array of names
local function equipmentNames(prefix)
    local out = {}
    for i = 1, #EQUIPMENT_SLOTS do out[i] = prefix .. EQUIPMENT_SLOTS[i] end
    return out
end

distribute({
    auras = AURAS,

    -- The grid's own buttons: the icons of the player's buffs and debuffs.
    --
    -- A group separate from auras, and the difference is the one between a
    -- bar and its buttons: there the holder, here the icons. Outlining an
    -- icon and dimming a holder are different jobs, and different subsystems
    -- ask for them.
    --
    -- The count is taken with room to spare: how many icons fit is the game's
    -- decision, and Compat.FilterExisting returns only those that exist
    -- now.
    ["aura-buttons"] = series("BuffButton", 40),
    ["aura-debuff-buttons"] = series("DebuffButton", 40),

    ["equipment-slots"]         = equipmentNames("Character"),
    ["equipment-slots-inspect"] = equipmentNames("Inspect"),

    -- The inspect window itself: it is asked whose equipment is on show. A
    -- group of its own rather than together with the buttons: the buttons are
    -- walked, while the window is asked about one thing — the unit.
    ["inspect-window"] = { "InspectFrame" },
})

-- The pet's game functions used to be declared here: its happiness and what
-- it eats. They existed for the pet-feeding part, which is no longer in the
-- addon, and the groups went with it.
--
-- NOTE: the call below hands out an empty table and therefore does nothing.
-- It is left in place rather than removed along with the rest of the
-- migration's dead weight, which is still to be decided on.
distribute({
})

-- The container game functions: reading the bags and moving things between
-- them.
--
-- THIS GENUINELY DIFFERS, and it differs between the very clients the addon
-- supports — otherwise these groups would have no place here. The early line
-- keeps the container work in globals; the later one removed them and put the
-- same functions into a table. No client offers both spellings at once, and
-- we have no client without either — there is the one where the spelling is
-- the first and the one where it is the second. That is precisely why five
-- modules each wrote a fork of their own, "the table first, then the global":
-- each decided for itself what this file exists to decide once.
--
-- The item-info functions were deliberately not brought here, although they
-- too are written in the modules with two spellings. They do not differ: the
-- global exists on all three supported clients, while the table-based
-- spelling is a guess about a client we do not support. The layer is about
-- the differences between our clients rather than a directory of the game's
-- API: pile everything a module calls in here and it stops answering the one
-- question it was written for.
--
-- The order inside each group is the table first, the global second. That is
-- not the layer's preference but a record of how the modules read the bags
-- before the move: on a client with both spellings (we know of none) the
-- answer would stay the same.
--
-- THE SIGNATURES DIFFER, AND THAT IS PART OF THE DECLARATION. For
-- container-item the two spellings answer differently: the table-based one
-- returns a single record (itemID, hyperlink, stackCount fields), the global
-- one a flat list of values. Handing over "a function" and staying silent
-- about the shape of its answer would move the trouble rather than solve it,
-- so the shape is declared next to the path (SHAPES below), and the
-- ResolveFunction door asks the caller which shape it can read.

-- The group role and an incoming resurrection.
--
-- THIS GENUINELY DIFFERS between the supported clients. Roles — tank, healer,
-- damage — do not exist as a concept on the early line: a group was assembled
-- with words rather than with a marker. The "a resurrection is already on its
-- way to this one" flag appeared at the same time, along with the group
-- finder.
--
-- Handed out to every flavour: our vanilla is two builds at once, and a list
-- of names does not know which one is in front of us.
local GROUP_ROLES = {
    ["unit-role"] = { "UnitGroupRolesAssigned" },
    ["unit-resurrect"] = { "UnitHasIncomingResurrection" },
}

distribute(GROUP_ROLES)

-- Threat: whether this unit holds the enemy's attention.
--
-- THIS GENUINELY DIFFERS between the supported clients, and the difference is
-- in the concept itself rather than in a name's spelling. On the early line
-- threat exists in the game but is not given to addons as a number: it was
-- computed from damage and argued about. Later the game began naming the
-- level itself.
--
-- Handed out to every flavour: our vanilla is two builds at once, and a list
-- of names does not know which one is in front of us. That is
-- Compat.FilterExisting's business to settle.
local THREAT = {
    ["unit-threat"] = { "UnitThreatSituation" },
}

distribute(THREAT)

-- A tapped mob: somebody else struck it, and the kill will not count for us.
--
-- THIS GENUINELY DIFFERS, and it differs in the question rather than in the
-- spelling. The later line asks in one word — whether the kill is denied to
-- us. The early one gives two halves: whether it is tapped at all and whether
-- it is tapped by us, and the answer is assembled from both — tapped, but not
-- by us.
--
-- Handed out to every flavour: a list of names does not know which build is
-- in front of us, and Compat.FilterExisting will return only what the client
-- has.
local TAP = {
    ["unit-tap-denied"]    = { "UnitIsTapDenied" },
    ["unit-tapped"]        = { "UnitIsTapped" },
    ["unit-tapped-by-me"]  = { "UnitIsTappedByPlayer" },
}

distribute(TAP)

-- The spellbook: how to walk what the player has learned.
--
-- THIS GENUINELY DIFFERS, and it differs the same way the containers do: the
-- early line keeps the reading in a global, the later one removed it and put
-- the same reading into a table.
--
-- Their second argument differs too — which book we are reading — and that is
-- a VALUE rather than a function's name. The layer handles that as well: a
-- dotted path is resolved step by step, and the later line's enum simply is
-- not found on a client that does not know it. The early line's word is taken
-- instead — the same thing under its own name.
--
-- Why the core needs this. A click on a raid frame casts a spell, and the
-- player has to choose it from THEIR OWN spells rather than type a name by
-- hand: a typo in the field gives a dead click, and that is discovered in
-- combat. So the addon needs the list of what was learned, and asking it of
-- two different spellings is the layer's work rather than a module's.
local SPELLBOOK = {
    ["spellbook-item-name"] = {
        "C_SpellBook.GetSpellBookItemName",
        "GetSpellBookItemName",
    },
    ["spellbook-bank"] = {
        "Enum.SpellBookSpellBank.Player",
        "BOOKTYPE_SPELL",
    },
}

distribute(SPELLBOOK)

-- Reading a unit's auras.
--
-- THIS GENUINELY DIFFERS between the supported clients, and the difference is
-- the containers': the early line keeps the reading in a global, the later
-- one removed it and put the same reading into a table. No client offers both
-- spellings at once.
--
-- THE SIGNATURES DIFFER, AND THAT IS PART OF THE DECLARATION. The
-- table-based spelling answers with a single record (name, applications,
-- expirationTime fields), the global one with a flat list of a dozen and a
-- half values where the needed ones stand first, second, third, fifth, sixth,
-- seventh and tenth. Handing over "a function" and staying silent about the
-- shape of its answer would move the trouble rather than solve it.
--
-- Why the group appeared later than the reading itself. That fork was written
-- inside the compact auras module's folder — and was the only one there until
-- a second module came for the auras: the raid frames, because a healer needs
-- to know whether a party member carries something they can remove. Two
-- copies of the decision "how does this client give out auras" would diverge
-- silently — such a list does not complain when it drifts away from the
-- client, it simply stops reading anything.
local UNIT_AURAS = {
    ["unit-aura"] = {
        "C_UnitAuras.GetAuraDataByIndex",
        "UnitAura",
    },
}

distribute(UNIT_AURAS)

-- What a healer must see on a health bar besides the health itself.
--
-- THIS GENUINELY DIFFERS between the supported clients, and these are not
-- different spellings of one name but different abilities of the game. Heal
-- prediction did not come to the game at once; damage absorbs came later
-- still. On the early line these functions do not exist at all, and that is
-- not a broken client: there is nothing to show there, because the game does
-- not compute such quantities itself.
--
-- Handed out to every flavour deliberately, unlike player-spec above. There
-- the difference is sharp and known — the early line has no specializations
-- and never will. Here the boundary runs inside one line: our vanilla is two
-- builds at once (11507 and 16001), and a list of names does not know which
-- of them is in front of us. That is Compat.FilterExisting's business to
-- settle rather than the list's, and the report will say by name what was
-- found.
local HEALER_BARS = {
    ["heal-incoming"] = { "UnitGetIncomingHeals" },
    ["absorb-shield"] = { "UnitGetTotalAbsorbs" },
    ["absorb-heal"]   = { "UnitGetTotalHealAbsorbs" },
}

distribute(HEALER_BARS)

local CONTAINERS = {
    -- The list of installed addons. In two spellings: later clients put
    -- these functions into a table, earlier ones keep them as globals.
    --
    -- Exactly one party needs it: the dimming asks whose window this is — the
    -- game's or another addon's — and asks by name. There is no other way to
    -- work that out: a frame does not remember who created it.
    ["addon-count"] = {
        "C_AddOns.GetNumAddOns",
        "GetNumAddOns",
    },
    ["addon-info"] = {
        "C_AddOns.GetAddOnInfo",
        "GetAddOnInfo",
    },

    ["container-slots"] = {
        "C_Container.GetContainerNumSlots",
        "GetContainerNumSlots",
    },
    ["container-free-slots"] = {
        "C_Container.GetContainerNumFreeSlots",
        "GetContainerNumFreeSlots",
    },
    ["container-item"] = {
        "C_Container.GetContainerItemInfo",
        "GetContainerItemInfo",
    },
    ["container-item-link"] = {
        "C_Container.GetContainerItemLink",
        "GetContainerItemLink",
    },
    ["container-pickup"] = {
        "C_Container.PickupContainerItem",
        "PickupContainerItem",
    },
}

distribute(CONTAINERS)

-- The compact party and raid frames.
--
-- These are the game's most restricted frames, and they have four groups not
-- for tidiness but because each part is worked with in its own way.
--
-- raidframe-setup is neither a frame nor a function but a table of numbers
-- the game itself takes a party member's size from when it lays the list out.
-- It is the chief one here: a group's composition changes constantly, and
-- after every change the game lays the frames out afresh, reading that table.
-- A size applied only to the frames themselves would be gone after the first
-- change of composition; a size placed in the table the game applies itself,
-- and with our values.
--
-- raidframe-member is the member frames themselves. Their size is changed so
-- that a new number takes effect at once rather than after the next layout.
-- The names are built from three series: the flat raid list, the grid by
-- subgroups, and the separate frames of a party of five. How many there are
-- today, and whether they exist at all, is Compat.FilterExisting's decision.
--
-- raidframe-container is what holds those frames. The scale is applied to it
-- rather than to each frame: scale is inherited by children, and forty
-- separate calls would give the same look at the price of forty protected
-- operations.
--
-- raidframe-relayout is the names of the game's functions that do that
-- layout. The rule is the unitframe-recolor and actionbar-relayout groups':
-- the subsystem stands after them through hooksecurefunc, after their work
-- rather than instead of it.
--
-- Every name here is a guess, and that is admissible precisely because the
-- existence filter discards a guess: what the client does not have does not
-- reach the subsystem, and it silently does nothing. Some builds keep the
-- layout in an object's methods rather than in global functions — then the
-- raidframe-relayout group comes out empty, and reapplying is left to the
-- group-composition event the subsystem listens to anyway.
local RAID_FRAME_LIMIT = 40   -- the flat raid list
local RAID_GROUP_LIMIT = 8    -- subgroups in a raid
local RAID_MEMBER_LIMIT = 5   -- people in a subgroup

--- The names of the raid's and the party's member frames.
-- @return table array of names
local function raidMemberNames()
    local out = series("CompactRaidFrame", RAID_FRAME_LIMIT)

    for group = 1, RAID_GROUP_LIMIT do
        for member = 1, RAID_MEMBER_LIMIT do
            out[#out + 1] = "CompactRaidGroup" .. group .. "Member" .. member
        end
    end

    local party = series("CompactPartyFrameMember", RAID_MEMBER_LIMIT)
    for i = 1, #party do out[#out + 1] = party[i] end

    return out
end

distribute({
    ["raidframe-container"] = {
        "CompactRaidFrameContainer",
        "CompactPartyFrame",
    },

    ["raidframe-member"] = raidMemberNames(),

    ["raidframe-setup"] = {
        "DefaultCompactUnitFrameSetupOptions",
    },

    ["raidframe-relayout"] = {
        "CompactRaidFrameContainer_LayoutFrames",
        "CompactRaidFrameContainer_TryUpdate",
        "CompactRaidFrameContainer_UpdateDisplayedUnits",
        "CompactRaidFrameManager_UpdateShown",
        "CompactPartyFrame_Generate",
        "CompactUnitFrame_SetUpFrame",
        "DefaultCompactUnitFrameSetup",
    },
})

--- The slot button names of one bag window.
-- A pure function: the names are assembled rather than checked. Existence is
-- Compat.FilterExisting's decision, as it is for every other name in this
-- file.
-- @param frameName string the bag window's name
-- @param count number|nil how many slots to ask for; the upper bound by
--        default
-- @return table array of names
function Compat.BagSlotNames(frameName, count)
    if type(frameName) ~= "string" or frameName == "" then return {} end

    local limit = tonumber(count) or BAG_SLOT_LIMIT
    if limit < 0 then limit = 0 end
    if limit > BAG_SLOT_LIMIT then limit = BAG_SLOT_LIMIT end

    local out = {}
    for i = 1, limit do
        out[i] = frameName .. BAG_PARTS.slot .. i
    end
    return out
end

--- The name of a part of a bag window.
-- @param frameName string the bag window's name
-- @param part string a BAG_PARTS key: "money" or "title"
-- @return string|nil
function Compat.BagPartName(frameName, part)
    if type(frameName) ~= "string" or frameName == "" then return nil end

    local suffix = BAG_PARTS[part]
    if type(suffix) ~= "string" then return nil end

    return frameName .. suffix
end

-- The stance bar buttons' prefixes by flavour.
--
-- There used to be one prefix per flavour, and it was written that way
-- deliberately: two sets occurring in one client at once would give twenty
-- buttons instead of ten. The worry was removed by the scan rather than by
-- argument. The vanilla flavour serves two builds (11507 and 16001), and
-- their prefixes differ: 1.60.1 has the stance buttons, while there is not
-- one object with the shapeshift word in its name there — the scan's pattern
-- for that word returned an empty list, and that list is complete rather than
-- truncated by the cap. So the sets do not occur in one client, and both
-- prefixes live in one group safely.
local STANCE_PREFIX = {
    -- Both builds of the vanilla flavour at once: the stance prefix is
    -- confirmed in 1.60.1 (build 70009), the shapeshift one is kept for the
    -- sake of Classic Era.
    vanilla = { "StanceButton", "ShapeshiftButton" },
    tbc     = { "ShapeshiftButton" },
    mists   = { "StanceButton" },
}

for flavor, prefix in pairs(STANCE_PREFIX) do
    local byFlavor = FRAMES[flavor]
    for group, names in pairs(actionBarGroups(prefix)) do
        -- An existing group must not be overwritten: two entries about one
        -- group would mean one of them silently has no effect.
        if byFlavor[group] ~= nil then
            error("frame group declared twice: " .. group, 0)
        end
        byFlavor[group] = names
    end
end
--- Determine the flavour from the interface number.
-- The number is built as major * 10000 + minor * 100 + patch, so looking at
-- the leading part is enough.
-- The input goes through tonumber: there is no guarantee that every client
-- returns a number as GetBuildInfo()'s fourth value, and a mistaken "unknown"
-- would switch the addon off on a perfectly supported client.
-- @param toc number|string the interface number, usually from
--        select(4, GetBuildInfo())
-- @return string the flavour's name, or "unknown"
function Compat.DetectFlavor(toc)
    local number = tonumber(toc)
    if type(number) ~= "number" then return "unknown" end

    local major = math.floor(number / 10000)

    if major == 1  then return "vanilla"  end
    if major == 2  then return "tbc"      end
    if major == 3  then return "wrath"    end
    if major == 4  then return "cata"     end
    if major == 5  then return "mists"    end
    if major >= 10 then return "mainline" end

    return "unknown"
end

--- Whether the addon supports this flavour.
-- @param flavor string
-- @return boolean
function Compat.IsSupported(flavor)
    return SUPPORTED[flavor] == true
end

--- A group's frame names for a flavour. An internal function.
-- It returns candidates without checking existence: some of the names may be
-- absent on a particular build. Modules must go through Compat.Resolve, which
-- filters out objects that do not exist.
-- It always returns a table: a missing flavour or group gives an empty list,
-- and the calling module simply does nothing instead of raising.
-- A copy is returned so that the caller cannot damage the shared table.
-- @param flavor string
-- @param group string
-- @return table array of strings
function Compat.GetFrameNames(flavor, group)
    local byFlavor = FRAMES[flavor]
    if not byFlavor then return {} end

    local names = byFlavor[group]
    if not names then return {} end

    local out = {}
    for i = 1, #names do
        out[i] = names[i]
    end
    return out
end

--- Every group name declared for a flavour.
--
-- Needed by the tests and by the reconciliation with the contract document:
-- the groups are part of the promise to module authors, and the list in
-- docs/module-api.md has to match what is declared here. A list derived from
-- the table itself cannot diverge from it; a list written out beside it would
-- diverge silently.
--
-- The order is fixed (a sort) so that a test's message is the same from run
-- to run: a pairs walk promises no order.
-- @param flavor string
-- @return table array of group names
function Compat.Groups(flavor)
    local byFlavor = FRAMES[flavor]
    if not byFlavor then return {} end

    local out = {}
    for group in pairs(byFlavor) do out[#out + 1] = group end
    table.sort(out)
    return out
end

--- Whether a flavour has a non-empty frame group.
-- @param flavor string
-- @param group string
-- @return boolean
function Compat.HasGroup(flavor, group)
    local byFlavor = FRAMES[flavor]
    if not byFlavor then return false end

    local names = byFlavor[group]
    return names ~= nil and #names > 0
end

--- Keep only the names an existing object answers to.
-- The globals table arrives as an argument rather than being taken from _G
-- directly: that keeps the function pure and testable outside the game.
--
-- A name and a path are deliberately indistinguishable here: a bare name is a
-- path of one step, a dotted one a path of two, and the existence of both is
-- decided by one and the same Compat.Lookup. So a path and a plain name lie
-- in one group without qualification, and a group holding paths stays an
-- ordinary array of strings: neither GetFrameNames, nor the report, nor the
-- guard on the table's shape changes.
--
-- The second return value is the objects themselves, one per surviving name
-- and in the same order. They are returned from here rather than fetched by
-- the caller from a name: _G[name] does not work for a path at all, and a
-- module that tried it would get nil and silently do nothing — precisely the
-- trouble this whole file is written against.
-- @param names table array of names or paths (may be nil)
-- @param globals table name -> object
-- @return table array of existing names, order preserved
-- @return table array of objects, one per name
function Compat.FilterExisting(names, globals)
    local out, objects = {}, {}
    if type(names) ~= "table" or type(globals) ~= "table" then
        return out, objects
    end

    for i = 1, #names do
        local name = names[i]
        local object = Compat.Lookup(globals, name)
        if object ~= nil then
            out[#out + 1] = name
            objects[#objects + 1] = object
        end
    end
    return out, objects
end

--- The group's frames that actually exist on the current client.
-- The only entry point modules use, and the only place in the whole layer
-- that reads _G.
--
-- The second return value is the objects themselves, one per name and in the
-- same order. What exactly is there the layer does not promise: a path may
-- hold a frame, a texture, a game API table or a function. Exactly one thing
-- is promised — the object exists (is not nil) at every step of the path. The
-- caller asks what kind of object it is, and asks the object itself rather
-- than the list of names.
--
-- Both arrays are built afresh on every call: by damaging the answer the
-- caller damages nobody else's list.
-- Called with a dot, like everything else in this module:
-- ns.Compat.Resolve("unitframe").
-- @param group string
-- @return table array of names
-- @return table array of objects
function Compat.Resolve(group)
    -- ns.flavor is set in Core/Init.lua, which loads last. An empty list
    -- here would mean "nothing to do", and a module would silently fail to
    -- work; a failure at load time is incomparably cheaper to investigate.
    if ns.flavor == nil then
        error("Compat.Resolve was called before initialisation: ns.flavor is "
            .. "not set yet. Resolve frames inside OnEnable rather than at "
            .. "file scope", 2)
    end

    local candidates = Compat.GetFrameNames(ns.flavor, group)
    return Compat.FilterExisting(candidates, _G)
end

--============================================================================
-- The shape of an answer: two spellings of one function answer differently
--============================================================================
--
-- A name is not the whole difference between clients. The table-based
-- container reader returns a single record with fields, while the global one
-- returns a flat list of values in its own order. A layer that handed over "a
-- function" and stayed silent about which one it is would push onto a module
-- exactly the knowledge about the client this file exists to keep in one
-- place: whoever called it blindly would read a field off a number and
-- silently find nothing.
--
-- So the shape is declared here, next to the path, rather than guessed by the
-- caller from a name. There are three words:
--
--   record — the answer is one record with named fields;
--   values — the answer is a flat list of values;
--   plain  — the spellings share a shape; there is nothing to know about it.
--
-- plain is the default, and the right default: the overwhelming majority of
-- this file's paths are frames and functions to hook, which have no "shape of
-- an answer" at all.
Compat.SHAPE_RECORD = "record"
Compat.SHAPE_VALUES = "values"
Compat.SHAPE_PLAIN  = "plain"

local SHAPES = {
    ["C_Container.GetContainerItemInfo"] = Compat.SHAPE_RECORD,
    ["GetContainerItemInfo"]             = Compat.SHAPE_VALUES,
    ["C_UnitAuras.GetAuraDataByIndex"]   = Compat.SHAPE_RECORD,
    ["UnitAura"]                         = Compat.SHAPE_VALUES,
}

--- The answer shape of the function at this path.
-- @param path string
-- @return string one of the three words; plain when nothing is said about
--         the path
function Compat.PathShape(path)
    if type(path) ~= "string" then return Compat.SHAPE_PLAIN end
    return SHAPES[path] or Compat.SHAPE_PLAIN
end

--- Whether a group's spellings answer differently.
--
-- That is the marker of a group whose function must not be asked for without
-- a word about the shape: it holds two different contracts under one group
-- name.
-- @param flavor string
-- @param group string
-- @return boolean
function Compat.GroupMixesShapes(flavor, group)
    local names = Compat.GetFrameNames(flavor, group)
    local first
    for i = 1, #names do
        local shape = Compat.PathShape(names[i])
        if first == nil then
            first = shape
        elseif shape ~= first then
            return true
        end
    end
    return false
end

--- A group's game function — the one this client has.
--
-- Why a separate door when Compat.Resolve exists. Because three of Resolve's
-- promises do not match what a caller into the game needs: it returns every
-- name it found (while only one is to be called), it does not promise that a
-- path holds a function (a path may hold a frame), and it says nothing about
-- the shape of the answer.
--
-- THE SHAPE IS ASKED FOR, NOT ANNOUNCED. The caller names the shape it can
-- read and receives a function of that shape only. The opposite order ("here
-- is a function, here is a word, carry on") would leave precisely the mistake
-- all of this is written against: the word can be ignored while the function
-- is still called. Here the word cannot be ignored, because without it
-- nothing is handed over: for a group with mixed shapes the answer to a
-- question without the word is nil, and that is not strictness for its own
-- sake but the only way to make "call the wrong thing" impossible.
--
-- For a group whose spellings answer alike the word is optional: there is
-- nothing to confuse there, and demanding it would make a module repeat the
-- knowledge "there is no difference here" — that is, the same second piece of
-- knowledge again.
--
-- A client that has not one of the spellings answers nil — and that is a
-- legitimate answer rather than an error: the module must stay with its "I do
-- nothing".
--
-- The globals table and the flavour arrive as arguments for the reason they
-- do in FilterExisting: that keeps the function pure and testable outside the
-- game. The door for a live client is Compat.ResolveFunction below.
-- @param globals table name -> object
-- @param flavor string
-- @param group string the layer's group name
-- @param shape string|nil the answer shape the caller can read
-- @return function|nil the function itself
-- @return string|nil the shape of its answer
-- @return string|nil the path it was found at, for messages
function Compat.FindFunction(globals, flavor, group, shape)
    if type(group) ~= "string" or group == "" then return nil end
    if shape ~= nil and type(shape) ~= "string" then return nil end

    if shape == nil and Compat.GroupMixesShapes(flavor, group) then
        return nil
    end

    local names = Compat.GetFrameNames(flavor, group)
    local found, objects = Compat.FilterExisting(names, globals)

    for i = 1, #objects do
        if type(objects[i]) == "function" then
            local shapeHere = Compat.PathShape(found[i])
            if shape == nil or shape == shapeHere then
                return objects[i], shapeHere, found[i]
            end
        end
    end

    return nil
end

--- A group's game function on this client.
-- A thin wrapper over FindFunction for the live game: the globals are _G and
-- the flavour is the one the core determined. Built like the
-- GetFrameNames/Resolve pair.
-- @param group string the layer's group name
-- @param shape string|nil the answer shape
-- @return function|nil
-- @return string|nil the answer shape
-- @return string|nil the path
function Compat.ResolveFunction(group, shape)
    if ns.flavor == nil then
        error("Compat.ResolveFunction was called before initialisation: "
            .. "ns.flavor is not set yet. Ask for game functions inside "
            .. "OnEnable rather than at file scope", 2)
    end

    return Compat.FindFunction(_G, ns.flavor, group, shape)
end

--- Whether a mob was tapped by somebody else.
--
-- A pure function of the client's three answers, and therefore tested without
-- the game. Why there are three answers is written here as well: the later
-- line answers in one word, the early one in two halves, and somebody has to
-- put them together.
--
-- Not knowing means no. A mob the client is silent about must look ordinary:
-- a grey bar on a live kill is worse than a coloured one on somebody else's —
-- the first takes a target away from the player, the second merely fails to
-- hint.
--
-- @param denied boolean|nil the answer to "is the kill denied to us"
-- @param tapped boolean|nil the answer to "is it tapped at all"
-- @param mine boolean|nil the answer to "is it tapped by us"
-- @return boolean
function Compat.TapDenied(denied, tapped, mine)
    if denied == true then return true end
    if denied == false then return false end

    if tapped ~= true then return false end
    return mine ~= true
end

--- Ask the client whether this unit was tapped by somebody else.
--
-- Three guarded calls at worst and one at best: the later line answers with
-- the first. Called while a bar is recoloured, that is, on an event rather
-- than per frame.
--
-- @param unit any the unit
-- @return boolean
-- The game functions once found. They are looked up once: the client does
-- not change between questions, while the question is asked for every
-- nameplate in combat.
local tapDeniedFn, tappedFn, tappedByMeFn
local tapFound = false

--- One game function's answer as a boolean, or nil.
-- A function of its own rather than a closure inside the question: a closure
-- per call is garbage on every nameplate of every frame, and the hot path's
-- guard counts it (tests/test_nameplates2.lua).
-- @param fn function|nil
-- @param unit string
-- @return boolean|nil
local function askUnit(fn, unit)
    if type(fn) ~= "function" then return nil end

    local ok, answer = pcall(fn, unit)
    if not ok then return nil end
    return ns.Skin.Truth(answer)
end

function Compat.UnitTapDenied(unit)
    if type(unit) ~= "string" or unit == "" then return false end
    if ns.flavor == nil then return false end

    if not tapFound then
        tapFound = true
        tapDeniedFn  = Compat.FindFunction(_G, ns.flavor, "unit-tap-denied")
        tappedFn     = Compat.FindFunction(_G, ns.flavor, "unit-tapped")
        tappedByMeFn = Compat.FindFunction(_G, ns.flavor, "unit-tapped-by-me")
    end

    return Compat.TapDenied(askUnit(tapDeniedFn, unit),
        askUnit(tappedFn, unit), askUnit(tappedByMeFn, unit))
end

--- Forget the tap-status functions once found.
-- Needed by the tests: the client changes from file to file in them, while
-- what was found lives until the end of the session.
function Compat.ForgetTap()
    tapFound = false
    tapDeniedFn, tappedFn, tappedByMeFn = nil, nil, nil
end

--- Every group declared for at least one flavour.
--
-- Needed by the client report (Core/Report.lua), and needed for one
-- distinction without which the report would be worse than silence: a group
-- empty ON PURPOSE must differ from a group empty THROUGH OUR MISTAKE.
--
-- That distinction is already recorded in the table itself, and recorded by a
-- key: vanilla has no focus cast bar at all, so vanilla has no castbar-focus
-- key — not an empty list but no key. So "declared for another client and not
-- for this one" is "empty on purpose", while "declared for this one and not
-- one name was found" is "the names were guessed wrong". The report reads
-- both halves from here and from nowhere else: a second list of groups would
-- diverge from the table silently, and would diverge towards "all is well".
--
-- The order comes from a sort, as in Compat.Groups: a pairs walk promises no
-- order, and reports are compared between runs.
-- @return table array of group names
function Compat.AllGroups()
    local seen, out = {}, {}
    for _, byFlavor in pairs(FRAMES) do
        for group in pairs(byFlavor) do
            if not seen[group] then
                seen[group] = true
                out[#out + 1] = group
            end
        end
    end
    table.sort(out)
    return out
end

-- Guesses that cost more than the rest.
--
-- This whole file is candidates, and the existence filter makes a mistake
-- safe. But the safety here is not uniform. A surplus name in a series of
-- buttons costs nothing: the neighbouring names were found and the subsystem
-- works. The raid frames' size table, on the other hand, is one per client,
-- and if the wrong name was guessed then the group frame size is not applied
-- at all, and silently — precisely the outcome the report is written for.
--
-- So what is listed here is what the author must learn by name: whether it is
-- in a live client or not. The note is English and short: the author reads it
-- from disk rather than the player in chat, and it is not subject to
-- translation.
--
-- A path is written as a dotted string: some game functions live not in _G
-- but in a table, and "exists" for them means "lies at this path".
-- Compat.Lookup checks a path, and exactly as FilterExisting does — the
-- globals table arrives as an argument.
local WATCHLIST = {
    { path = "DefaultCompactUnitFrameSetupOptions",
      note = "raid frame size table - the group frame subsystem writes width "
          .. "and height into it; a wrong name here means group frame size "
          .. "does nothing at all" },
    { path = "CompactRaidFrameContainer_LayoutFrames",
      note = "raid frame relayout hook - without it size is reapplied only "
          .. "on the roster event" },
    { path = "CompactUnitFrame_SetUpFrame",
      note = "per-member setup hook - the other half of the same relayout" },

    -- The table-based spellings of the container functions. The globals are
    -- deliberately not here: the scan sees those (Core/Scan.lua walks the
    -- globals table), while a field inside a table it will never see. So only
    -- the report can answer about this half of the pair, and it answers by
    -- name, whereas the group answers with one verdict for both
    -- spellings.
    { path = "C_Container.GetContainerNumSlots",
      note = "bag size, table spelling - a field, so only this report can "
          .. "ever answer whether it is here; group container-slots" },
    { path = "C_Container.GetContainerItemInfo",
      note = "what is in a bag slot, table spelling - it answers with one "
          .. "record, where the plain global answers with a flat list; "
          .. "group container-item" },
    { path = "C_Container.GetContainerNumFreeSlots",
      note = "free slots and bag family, table spelling; group "
          .. "container-free-slots" },
    { path = "C_Container.GetContainerItemLink",
      note = "item link in a bag slot, table spelling; group "
          .. "container-item-link" },
    { path = "C_Container.PickupContainerItem",
      note = "pick up and drop an item, table spelling - without it bag "
          .. "sorting refuses to start at all; group container-pickup" },

    { path = "TargetFrame_UpdateAuras",
      note = "aura relayout on the target frame - without it the aura pass "
          .. "waits a frame instead of following the game" },
    { path = "TargetFrame_UpdateAuraPositions",
      note = "aura relayout, second spelling" },
    { path = "CompactUnitFrame_UpdateAuras",
      note = "aura relayout on compact group frames" },

    { path = "UnitFrameHealthBar_Update",
      note = "unit frame recolor hook - without it class color is repainted "
          .. "by the game on the next unit update" },
    { path = "CompactUnitFrame_UpdateHealthColor",
      note = "nameplate recolor hook" },
    { path = "MultiActionBar_Update",
      note = "action bar relayout hook" },
    { path = "UIParent_ManageFramePositions",
      note = "the game's own frame placement - it undoes moved frames" },
    { path = "C_NamePlate",
      note = "nameplate API table - the nameplate subsystem does nothing at "
          .. "all without it" },
    { path = "ContainerFrameCombinedBags",
      note = "combined bags window - written from the naming convention, "
          .. "and confirmed present in vanilla 1.60.1 build 70009" },

    -- The main bar's decorative chrome holder. In 1.60.1 there is neither
    -- the older bar name nor any of the three global chrome names, while the
    -- bar itself is called something else. As a field inside a frame the
    -- chrome has no global name and the scan will never see it — paths answer
    -- for it, and now not only here: the same paths are declared as the
    -- actionbar-art group, so a confirmed path does not merely get printed in
    -- the report but works at once.
    --
    -- They remain on the watch list because the list answers by name while
    -- the group answers with one verdict for the whole of it: actionbar-art
    -- is a group of spellings (ALTERNATIVES), and one found name is enough for
    -- an "ok". The author, though, needs to know which spelling answered.
    { path = "MainActionBar.LeftEndCap",
      note = "action bar art holder, field spelling - the gryphon toggle "
          .. "does nothing until one of these answers yes" },
    { path = "MainActionBar.EndCaps",
      note = "action bar art holder, nested spelling - if this one is the "
          .. "answer, the art pass needs a second level, not a new name" },
}

--============================================================================
-- Paths: naming what lies inside somebody else's object
--============================================================================
--
-- WHY. Some of what the addon needs to name has no global name at all. In
-- newer builds the main bar's decorative chrome is not a global texture but a
-- field inside a frame; game functions increasingly live not in _G but in a
-- table. While the layer could name only globals, such a thing could neither
-- be declared as a group nor asked about by the report — a setting silently
-- did nothing, and there was nowhere to learn that from.
--
-- HOW A PATH IS WRITTEN. As a dotted string, in the same array as plain
-- names: a bare name is a path of one step, a dotted one a path of two. There
-- is deliberately no separate notation (a table, a prefix, a second group
-- key): any of them would split the groups into two kinds and force every
-- reader of the table — GetFrameNames, the report, the guards — to know about
-- both. One notation means a path and a name sit in one group without
-- qualification.
--
-- EXISTENCE AT EVERY STEP. The file's rule ("what is not there does not
-- reach a module") extends to the whole path rather than to its end: a
-- missing first step, a missing last one and an unreachable middle all three
-- mean "this is not here". The difference between them is not in the verdict
-- but in what it tells the author, and it is therefore not lost:
-- LookupSteps answers how many steps were taken, and the report prints that
-- in words.
--
-- SOMEBODY ELSE'S OBJECT IS TOUCHED CAREFULLY. Reading a field is harmless;
-- assuming a table is there is not. So the type is asked before every step
-- and the reading itself goes through pcall: somebody else's object may carry
-- a metatable with an __index function, and that is entitled to raise. Not
-- one step calls anything and not one writes anything.
--
-- WHAT IS PROMISED TO THE CALLER. Exactly one thing: something exists at this
-- path. Neither the object's kind nor whether it is a frame or a texture is
-- promised by the layer, nor can be — on different clients one
-- actionbar-art group holds global textures and holder fields alike. The kind
-- is asked of the object itself (GetObjectType, the presence of a method),
-- and the chrome subsystem does exactly that.
--
-- A PATH DOES NOT LIFT THE ENGINE'S PROTECTION. An object obtained by a path
-- is protected exactly as one obtained by a name, and the deferral rule does
-- not change: defer when the operation is protected AND the object answers
-- IsProtected().

-- One step of a path. A function of its own, so that a field can be read
-- under pcall without a closure per step.
-- @param object table
-- @param key string
-- @return any
local function indexStep(object, key)
    return object[key]
end

--- Split a path into steps.
--
-- The parsing is strict: a step is letters, digits and underscores, a dot
-- separates steps and is never leading, trailing or doubled. Lenient parsing
-- would silently equate a doubled dot with a single one and accept a leading
-- one — that is, make a typo in the table indistinguishable from intent,
-- exactly as a wrong name once was.
-- @param path string
-- @return table array of steps; empty when the path is written wrongly
function Compat.PathParts(path)
    if type(path) ~= "string" or path == "" then return {} end
    if not path:find("^[%w_]+[%w_%.]*$") then return {} end

    local out = {}
    for part in path:gmatch("[^%.]+") do out[#out + 1] = part end

    -- Joining the steps back together must give the original string:
    -- otherwise the path held empty steps, and that is a typo rather than a
    -- path.
    if table.concat(out, ".") ~= path then return {} end
    return out
end

--- The object at a path, and how far along the path it was possible to get.
--
-- The globals table arrives as an argument for the reason it does in
-- FilterExisting: that keeps the function pure and testable outside the game.
--
-- The second return value is the walk's record, and it is the very difference
-- the function was written for:
--   parts   — how many steps the path has;
--   reached — how many steps were taken (reached == parts means the path
--             resolved);
--   stopped — the step it stopped at (nil when it got there);
--   blocked — true when it stopped not because the step is missing but
--             because the previous step cannot be entered: what is there is
--             not a table (userdata, a number, a string), or reading the
--             field raised.
--
-- reached > 0 together with reached < parts is "the middle is there, the end
-- is not", and that is a different fact from "nothing at all": it says the
-- name was almost guessed.
-- @param globals table name -> object
-- @param path string a name, or a dotted path
-- @return any|nil the object
-- @return table the record {path, parts, reached, stopped, blocked}
function Compat.LookupSteps(globals, path)
    local parts = Compat.PathParts(path)
    local info = {
        path    = type(path) == "string" and path or "",
        parts   = #parts,
        reached = 0,
        stopped = parts[1],
        blocked = false,
    }

    if type(globals) ~= "table" or #parts == 0 then return nil, info end

    local object = globals
    for i = 1, #parts do
        -- Only a table can be entered. Userdata, a number and a string are
        -- not "empty" but "no way further", and that is recorded
        -- separately.
        if type(object) ~= "table" then
            info.stopped = parts[i]
            info.blocked = true
            return nil, info
        end

        local ok, value = pcall(indexStep, object, parts[i])
        if not ok then
            info.stopped = parts[i]
            info.blocked = true
            return nil, info
        end
        if value == nil then
            info.stopped = parts[i]
            return nil, info
        end

        object = value
        info.reached = i
    end

    info.stopped = nil
    return object, info
end

--- The object at a dotted path.
-- A thin wrapper over LookupSteps for those who need only a yes-or-no answer:
-- the existence filter and the resolution of groups.
-- @param globals table name -> object
-- @param path string a name, or a dotted path
-- @return any|nil
function Compat.Lookup(globals, path)
    local object = Compat.LookupSteps(globals, path)
    return object
end

--- The guesses that need confirming by a live client.
-- A copy is returned: the list goes outwards, into the report, and the caller
-- must not be able to damage the shared array.
-- @return table array of records {path, note}
function Compat.Watchlist()
    local out = {}
    for i = 1, #WATCHLIST do
        out[i] = { path = WATCHLIST[i].path, note = WATCHLIST[i].note }
    end
    return out
end

--============================================================================
-- The client's build, known at once
--============================================================================
--
-- Why this is here when Core/Init.lua determines the build.
--
-- The addon's parts (the Features folder) are ordinary files of the same
-- addon as the core, and they are read BEFORE the game sends ADDON_LOADED,
-- that is, before OnInitialize, where ns.flavor is set. Yet they need to ask
-- the layer while being read: a part declines to exist on a client that lacks
-- what it needs, and that refusal is the absence of a registration — a
-- decision taken exactly while the file is read.
--
-- While the parts were separate addons the question did not arise: an addon
-- declaring a dependency on this one is read after the core in full, along
-- with its ADDON_LOADED. Moving them inside took that away for free — and
-- took it silently: the layer answered with an empty list, a part found not
-- one function and declared it had nothing to do on this client. On EVERY
-- client.
--
-- So the build is determined right here, while the layer is read: below this
-- point nobody has any reason not to know the client. Core/Init.lua sets it
-- again and by the same call — not because that is needed but because it is
-- its business: it answers for refusing an unsupported client, and reading
-- that from two places at once is pointless.
--
-- There may be no client at all (the tests read the layer by itself), and
-- then the build stays unset — exactly as before.
if type(GetBuildInfo) == "function" then
    local ok, _, _, _, toc = pcall(GetBuildInfo)
    if ok and toc ~= nil then
        ns.flavor = Compat.DetectFlavor(toc)
    end
end
