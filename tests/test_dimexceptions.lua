local helpers = require("helpers")

-- The darkening exception list is assembled from what the pass darkened.
--
-- What the author said: "why are there so few frames in the exclusion list,
-- the game has far more frames". He is right, and the trouble is not a
-- forgotten line. The interface pass has for some time been a common one --
-- it takes every named window under the root -- while the exception list had
-- eleven checkboxes: ten of our own groups and "other windows". Professions,
-- bank, auction, mail, spellbook, merchant, guild -- all behind one switch.
--
-- What is checked here is a different design of the list: it is not written
-- but assembled. What the pass darkened is in it; what it did not is not.

T.suite("window exceptions: the catalogue is assembled from the pass")

local function newScene()
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Casefold.lua", ns)
    helpers.loadAddonFile("Core/Skin.lua", ns)
    helpers.loadAddonFile("Core/Compat.lua", ns)
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Registry.lua", ns)
    helpers.loadAddonFile("Modules/Darkness.lua", ns)
    return ns
end

--- Fake border texture.
local function newArt(path)
    local art = {
        r = 1, g = 1, b = 1, a = 1,
        GetObjectType = function() return "Texture" end,
        GetDrawLayer = function() return "ARTWORK" end,
        GetTexture = function() return path or "Interface\\Common\\Thing" end,
    }
    function art:GetVertexColor() return self.r, self.g, self.b, self.a end
    function art:SetVertexColor(cr, cg, cb, ca)
        self.r, self.g, self.b = cr, cg, cb
        if ca ~= nil then self.a = ca end
    end
    return art
end

--- Fake icon: content, with the image given as a file id.
local function newIcon()
    local icon = newArt(nil)
    icon.GetTexture = function() return 132863 end
    -- The name is the one this icon has in the client: the rule recognises
    -- content by name, while a file id on its own says nothing more.
    --
    icon.GetName = function() return "MockFrameIcon" end
    return icon
end

--- Fake window.
local function newWindow(name, regions, children)
    local frame = {
        GetObjectType = function() return "Frame" end,
        GetRegions = function() return unpack(regions or {}) end,
        GetChildren = function() return unpack(children or {}) end,
    }
    if name then frame.GetName = function() return name end end
    return frame
end

--- Scene with the database, the interface root and the settings.
local function newWorld(windows)
    local ns = newScene()
    ns.flavor = "vanilla"

    local profile = {
        darkness = { amount = 50, mode = {}, excludeWindow = {} },
    }
    local global = { darkness = { windows = {}, session = 0 } }
    ns.Addon = { db = { profile = profile, global = global } }

    _G.UIParent = newWindow("UIParent", {}, windows)
    return ns, profile.darkness, global.darkness
end

local savedUIParent = _G.UIParent

--============================================================================
-- A fresh install knows no window at all
--============================================================================

do
    local ns = newScene()
    T.eq(next(ns.Darkness.defaults.excludeWindow), nil,
        "a fresh install excludes no window")

    -- The catalogue is empty, and not because there is no database yet: the
    -- declared defaults of the shared section are empty too. The addon ships
    -- not a single guess about window names -- otherwise it would be exactly
    T.eq(next(ns.Darkness.globals.windows), nil,
        "the window catalogue is empty on a fresh install")
    T.eq(ns.Darkness.globals.session, 0, "and there has not been a single session yet")
    T.eq(next(ns.Darkness.Windows()), nil, "without a database the catalogue is empty too")
end

--============================================================================
-- What the pass darkened is what stands in the catalogue
--============================================================================

do
    local trade = newWindow("TradeSkillWindow", { newArt() })
    -- A window with not a single border texture: a checkbox on such a row
    -- would change nothing, which is why there is no row.
    local hollow = newWindow("HollowWindow", { newIcon() })

    local ns, settings, store = newWorld({ trade, hollow })
    ns.Darkness:ApplySettings()

    T.eq(store.windows["TradeSkillWindow"], 0, "a darkened window made it into the catalogue")
    T.eq(store.windows["HollowWindow"], nil,
        "a window with nothing to darken did not make it into the catalogue")

    T.eq(#ns.Darkness.WindowNames(store.windows), 1, "the catalogue holds one name")

    -- A window that did not yet exist at login: the game creates most of its
    -- windows on first open, and the catalogue is obliged to catch them --
    -- otherwise the list would stay as stunted as the author complains.
    local late = newWindow("LateWindow", { newArt() })
    ns.Darkness.ApplyToWindow(late)
    T.eq(store.windows["LateWindow"], 0,
        "a window opened for the first time in game was appended to the catalogue")

    T.eq(settings ~= nil, true, "the settings are in place")
end

--============================================================================
-- Frames of named groups do not enter the catalogue
--============================================================================

T.suite("window exceptions: coarse groups and exact windows do not conflict")

do
    -- The player unit frame is declared as a group in the compatibility
    -- layer, and the common pass does not take it. So it is not entitled to a
    -- second checkbox either: every texture has exactly one owner, not two.
    local names = ns and nil
    local ns2 = newScene()
    ns2.flavor = "vanilla"
    local group = ns2.Compat.GetFrameNames("vanilla", "unitframe")
    T.ok(#group > 0, "the compatibility layer knows the unit frame frames")

    local unit = newWindow(group[1], { newArt() })
    _G[group[1]] = unit

    local plain = newWindow("SomeGameWindow", { newArt() })

    local profile = {
        darkness = { amount = 50, mode = {}, excludeWindow = {} },
    }
    local global = { darkness = { windows = {}, session = 0 } }
    ns2.Addon = { db = { profile = profile, global = global } }
    _G.UIParent = newWindow("UIParent", {}, { unit, plain })

    ns2.Darkness:ApplySettings()

    T.eq(global.darkness.windows[group[1]], nil,
        "a frame of a named group did not enter the window catalogue")
    T.eq(global.darkness.windows["SomeGameWindow"], 0,
        "while a window of the common pass did")

    _G[group[1]] = nil
    T.eq(names, nil, "the scene did not leak")
end

--============================================================================
-- The checkbox takes effect at once and in both directions
--============================================================================

T.suite("window exceptions: the checkbox acts at once and both ways")

do
    local artA = newArt()
    local artB = newArt()
    local ns, settings, store = newWorld({
        newWindow("BankWindow", { artA }),
        newWindow("MailWindow", { artB }),
    })

    ns.Darkness:ApplySettings()
    -- A white border arrives at the brightness ceiling, see helpers.whiteAt.
    local dim = helpers.whiteAt(ns.Darkness.Factor(50))
    T.ok(math.abs(artA.r - dim) < 1e-9, "the window is darkened")
    T.ok(math.abs(artB.r - dim) < 1e-9, "and the neighbouring one too")

    -- Neither a scan nor an interface reload: application follows the ready
    -- plan, just like a slider step.
    settings.excludeWindow["BankWindow"] = true
    ns.Darkness.Refresh()
    T.eq(artA.r, 1, "an excluded window returned to its native colour at once")
    T.ok(math.abs(artB.r - dim) < 1e-9, "the neighbouring one stayed darkened")

    settings.excludeWindow["BankWindow"] = false
    ns.Darkness.Refresh()
    T.ok(math.abs(artA.r - dim) < 1e-9,
        "clearing the checkbox brings the darkening back just as promptly")

    -- Content never darkens under any checkbox: that rule is separate from
    -- the exceptions and is not governed by them.
    local icon = newIcon()
    local late = newWindow("VendorWindow", { icon })
    ns.Darkness.ApplyToWindow(late)
    T.eq(icon.r, 1, "the icon is untouched")
    T.eq(store.windows["VendorWindow"], nil,
        "and a window holding only content does not ask for a row")
end

--============================================================================
-- The coarse switch is visible rather than acting silently
--============================================================================

do
    local art = newArt()
    local ns, settings = newWorld({ newWindow("GuildWindow", { art }) })
    ns.Darkness:ApplySettings()

    local node = ns.Darkness.options.args.windowExclude
    T.eq(node.disabled(), false, "the window list is available")

    settings.mode["window"] = "native"
    ns.Darkness.Refresh()
    T.eq(art.r, 1, "\"other windows\" keeps the whole window in its native look")
    T.eq(node.disabled(), true,
        "and the per-window list is greyed out rather than silent")

    settings.mode["window"] = "follow"
    ns.Darkness.Refresh()
    T.ok(math.abs(art.r - helpers.whiteAt(ns.Darkness.Factor(50))) < 1e-9,
        "clearing the coarse checkbox brings the darkening back")
end

--============================================================================
-- How the list is shown
--============================================================================

T.suite("window exceptions: how the list is shown")

do
    local ns = newScene()
    local Darkness = ns.Darkness

    T.eq(Darkness.WindowLabel("MerchantFrame"), "Merchant",
        "the trailing Frame is not repeated in the label")
    T.eq(Darkness.WindowLabel("TradeSkillWindow"), "Trade Skill Window",
        "words are separated by spaces")
    T.eq(Darkness.WindowLabel("PVPUIFrame"), "PVPUI", "an abbreviation is not broken up")
    T.eq(Darkness.WindowLabel(nil), "", "garbage in gives an empty label")

    T.eq(Darkness.WindowMatches("MerchantFrame", "merch"), true,
        "the search is case-insensitive")
    T.eq(Darkness.WindowMatches("MerchantFrame", "Trade Skill"), false,
        "and does not find what is not there")
    T.eq(Darkness.WindowMatches("TradeSkillWindow", "skill win"), true,
        "it searches the label too, not only the joined name")
    T.eq(Darkness.WindowMatches("Anything", ""), true,
        "an empty query shows everything")

    local windows = {}
    for i = 1, 10 do windows["Window" .. i] = 1 end
    local rows, total = Darkness.WindowRows(windows, nil, 4)
    T.eq(#rows, 4, "no more than the cap is shown")
    T.eq(total, 10, "while the total mentions all of them")
    T.eq(rows[1] < rows[2], true, "the rows are alphabetical")
end

do
    -- First login on a fresh install: instead of an empty list of checkboxes
    -- a line saying why it is empty and when it will fill up.
    local ns = newWorld({})
    local args = ns.Darkness.options.args

    T.eq(args.windowEmpty.hidden(), false,
        "on an empty catalogue an explanation is shown, not an empty list")
    T.eq(args.windowExclude.hidden(), true, "and the list itself is hidden")
    T.eq(next(args.windowExclude.values()), nil, "and it holds no rows")

    local art = newArt()
    ns.Darkness.ApplyToWindow(newWindow("AuctionWindow", { art }))

    T.eq(args.windowEmpty.hidden(), true,
        "as soon as a window is seen the explanation goes away")
    T.eq(args.windowExclude.hidden(), false, "and the list appears")
    T.eq(args.windowExclude.values()["AuctionWindow"], "Auction Window",
        "as a row with a readable label")

    -- The search box is not a setting: it is not in the profile and never goes to disk.
    args.windowSearch.set(nil, "auc")
    T.eq(args.windowSearch.get(nil), "auc", "what was typed is visible in the box")
    T.eq(args.windowExclude.values()["AuctionWindow"], "Auction Window",
        "what matched stayed")
    args.windowSearch.set(nil, "zzz")
    T.eq(next(args.windowExclude.values()), nil, "what did not match went away")
    T.eq(ns.Addon.db.profile.darkness.windowSearch, nil,
        "the query is not stored in the profile")
    args.windowSearch.set(nil, "")

    T.eq(args.windowMore.hidden(), true,
        "while everything fits, nothing is said about a remainder")
end

--============================================================================
-- Forgetting
--============================================================================

T.suite("window exceptions: a forgotten name and a kept choice")

do
    local ns = newScene()
    local Darkness = ns.Darkness

    local windows = {
        Fresh = 10,
        Old = 10 - Darkness.FORGET_AFTER,
        Ancient = 10 - Darkness.FORGET_AFTER - 1,
        Broken = "not a number",
    }
    local dropped = Darkness.Forget(windows, 10, Darkness.FORGET_AFTER, 100)

    T.eq(windows.Fresh, 10, "what was seen this session is in place")
    T.eq(windows.Old, 10 - Darkness.FORGET_AFTER, "at the edge of the term, too")
    T.eq(windows.Ancient, nil, "past the edge of the term, forgotten")
    T.eq(windows.Broken, nil, "garbage from the saved variables is thrown out")
    T.eq(dropped, 2, "what was forgotten is counted")
end

do
    -- The cap: a foreign addon creating windows with new names every fight
    -- would otherwise grow the saved variables without bound.
    local ns = newScene()
    local windows = {}
    for i = 1, 20 do windows[string.format("W%02d", i)] = i end

    ns.Darkness.Forget(windows, 20, 100, 5)

    local left = ns.Darkness.WindowNames(windows)
    T.eq(#left, 5, "the catalogue is held within bounds")
    T.eq(left[1], "W16", "the freshest ones remained")
    T.eq(left[5], "W20", "and in order")
end

do
    -- The row is forgotten, not the decision. A window the game no longer
    -- hands out leaves the list; the exception on its name stays in the
    -- profile, and a returning window finds its choice untouched.
    local art = newArt()
    local ns, settings, store = newWorld({ newWindow("FairWindow", { art }) })

    ns.Darkness:ApplySettings()
    settings.excludeWindow["FairWindow"] = true
    ns.Darkness.Refresh()
    T.eq(art.r, 1, "the window is excluded")

    store.session = store.session + ns.Darkness.FORGET_AFTER + 1
    ns.Darkness.Forget(store.windows, store.session,
        ns.Darkness.FORGET_AFTER, ns.Darkness.CATALOG_MAX)

    T.eq(store.windows["FairWindow"], nil, "the row left the list")
    T.eq(settings.excludeWindow["FairWindow"], true,
        "while the player's decision stayed with it")

    -- The window came back under the same name: the choice applies as it stood.
    local back = newArt()
    ns.Darkness.ApplyToWindow(newWindow("FairWindow", { back }))
    T.eq(back.r, 1, "the returning window came back excluded")
    T.eq(store.windows["FairWindow"], store.session,
        "and stands in the list again")
end

do
    -- A session means logging into the game, not enabling the module. The
    -- count does not open twice: otherwise age would be measured by the wrong thing.
    local ns = newWorld({})
    local store = ns.Addon.db.global.darkness

    T.eq(ns.Darkness.StartSession(), true, "the session is open")
    T.eq(store.session, 1, "the counter went up")
    T.eq(ns.Darkness.StartSession(), false, "a second time, no")
    T.eq(store.session, 1, "and the counter did not move")
end

--============================================================================
-- Cost
--============================================================================

T.suite("window exceptions: the cost ceilings did not move")

do
    -- Recording what was found has no right to cost a pass. The ceilings are
    -- the same as in tests/test_darkcost.lua: a slider step does not touch
    -- the interface tree at all and costs at most two protected calls per texture.
    local pcalls, regions, children = 0, 0, 0
    local realpcall = pcall

    local ns = newScene()
    ns.flavor = "vanilla"

    local function art()
        local a = newArt()
        return a
    end

    local windows = {}
    for i = 1, 20 do
        local list = { art(), art(), art() }
        local frame = newWindow("CountedWindow" .. i, list, {})
        local rawRegions, rawChildren = frame.GetRegions, frame.GetChildren
        frame.GetRegions = function(...)
            regions = regions + 1
            return rawRegions(...)
        end
        frame.GetChildren = function(...)
            children = children + 1
            return rawChildren(...)
        end
        windows[i] = frame
    end

    local profile = {
        darkness = { amount = 40, mode = {}, excludeWindow = {} },
    }
    local global = { darkness = { windows = {}, session = 3 } }
    ns.Addon = { db = { profile = profile, global = global } }
    _G.UIParent = newWindow("UIParent", {}, windows)

    ns.Darkness:ApplySettings()
    local planSize = ns.Darkness.PlanSize()
    T.eq(planSize, 60, "the plan is assembled in full")
    T.eq(#ns.Darkness.WindowNames(global.darkness.windows), 20,
        "and the catalogue was assembled during the same scan")

    -- Half the windows are excluded by name: the most expensive case to apply.
    for i = 1, 20, 2 do
        profile.darkness.excludeWindow["CountedWindow" .. i] = true
    end

    regions, children, pcalls = 0, 0, 0
    _G.pcall = function(...)
        pcalls = pcalls + 1
        return realpcall(...)
    end

    profile.darkness.amount = 41
    ns.Darkness.Refresh()

    _G.pcall = realpcall

    T.eq(children, 0, "a slider step does not ask for child frames")
    T.eq(regions, 0, "and does not ask for regions")
    T.ok(pcalls <= 2 * planSize,
        "no more than two protected calls per texture of the plan")

    T.eq(#ns.Darkness.WindowNames(global.darkness.windows), 20,
        "the catalogue did not grow from a slider step")
end

--============================================================================
-- Storage
--============================================================================

T.suite("window exceptions: storage shape and migration")

do
    local ns = helpers.newNamespace()
    helpers.loadAddonFile("Core/Locale.lua", ns)
    helpers.loadAddonFile("Core/Defaults.lua", ns)

    T.ok(ns.DB_VERSION >= 9, "the schema version was raised for the new shape")
    T.ok(type(ns.Migrations[8]) == "function", "the 8 -> 9 step is in place")

    -- Keyed on absence rather than on value: whoever has already checked
    -- something does not lose their choice.
    local profile = { version = 8, darkness = { amount = 70 } }
    ns.MigrateProfile(profile, ns.Migrations, ns.DB_VERSION)
    T.eq(type(profile.darkness.excludeWindow), "table",
        "an older profile got a place for per-window exceptions")
    T.eq(next(profile.darkness.excludeWindow), nil, "and it is empty")
    T.eq(profile.darkness.amount, 70, "the former settings are untouched")

    local chosen = {
        version = 8,
        darkness = { amount = 70, excludeWindow = { SomeWindow = true } },
    }
    ns.MigrateProfile(chosen, ns.Migrations, ns.DB_VERSION)
    T.eq(chosen.darkness.excludeWindow.SomeWindow, true,
        "the migration does not touch a choice already made")

    -- A profile with no darkening section survives the migration too: AceDB
    -- will lay the section out from the defaults.
    local bare = { version = 8 }
    ns.MigrateProfile(bare, ns.Migrations, ns.DB_VERSION)
    T.eq(bare.version, ns.DB_VERSION, "the profile was brought up to the current version")
end

_G.UIParent = savedUIParent
