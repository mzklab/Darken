local helpers = require("helpers")

-- The grid of the default bags' slots (Modules/Bags.lua) and the names of
-- the bag windows in the compatibility layer.
--
-- One setting is left of the subsystem: a slot's border. "Dark bags" went
-- away — the darkening reaches every window of the game's by itself, and a
-- second way of saying the same thing was superfluous (see the head of
-- Modules/Bags.lua). What is checked is what can be checked without a client:
-- the default, the border's reversibility and the assembly of the window
-- parts' names. The faked window here is honest enough: all the subsystem
-- asks a frame for is a few methods, and those are faked with a table.

T.suite("the bags: the compatibility layer")

local ns = helpers.newNamespace()
helpers.loadAddonFile("Core/Compat.lua", ns)
local Compat = ns.Compat

do
    local windows = Compat.GetFrameNames("vanilla", "bag-window")
    T.ok(#windows > 0, "the bag windows are declared for vanilla")
    T.eq(windows[1], "ContainerFrame1", "the first window is the backpack")
    T.eq(Compat.HasGroup("mists", "bag-window"), true, "and for mists too")

    -- The group of windows and the group of bag buttons on the bar are
    -- different things, and they must not overlap: otherwise one texture would
    -- have two owners, and the look would depend on the order the settings are applied in.
    local bar = {}
    local names = Compat.GetFrameNames("vanilla", "bags")
    for i = 1, #names do bar[names[i]] = true end

    local overlap = {}
    for i = 1, #windows do
        if bar[windows[i]] then overlap[#overlap + 1] = windows[i] end
    end
    T.eq(#overlap, 0, "the bag windows do not overlap the bag buttons: "
        .. table.concat(overlap, " | "))

    T.ok(Compat.HasGroup("vanilla", "bag-repaint"),
        "the bag redrawing functions are declared")
end

do
    local slots = Compat.BagSlotNames("ContainerFrame1", 3)
    T.eq(#slots, 3, "there are exactly as many slot names as were asked for")
    T.eq(slots[1], "ContainerFrame1Item1", "the first slot's name")
    T.eq(slots[3], "ContainerFrame1Item3", "the third slot's name")

    T.eq(#Compat.BagSlotNames("ContainerFrame1"), 36,
        "with no number the upper bound is taken")
    T.eq(#Compat.BagSlotNames("ContainerFrame1", 1000), 36,
        "more than the upper bound cannot be asked for")
    T.eq(#Compat.BagSlotNames(nil, 5), 0, "with no window name there are no names")

    T.eq(Compat.BagPartName("ContainerFrame1", "money"),
        "ContainerFrame1MoneyFrame", "the money frame's name")
    T.eq(Compat.BagPartName("ContainerFrame1", "title"),
        "ContainerFrame1Name", "the bag label's name")
    T.eq(Compat.BagPartName("ContainerFrame1", "no-such-part"), nil,
        "an unfamiliar part gives no name")
end

T.suite("the bags: the default")

helpers.loadAddonFile("Core/Registry.lua", ns)
helpers.loadAddonFile("Core/Locale.lua", ns)
helpers.loadAddonFile("Core/Skin.lua", ns)
helpers.loadAddonFile("Skin/Draw.lua", ns)
helpers.loadAddonFile("Modules/Bags.lua", ns)
local Bags = ns.Bags

do
    T.eq(Bags.name, "bags", "the subsystem's name")
    T.eq(Bags.defaults.slotBorder, false,
        "the default is the game's own look: a fresh install draws no border around a slot")

    -- The bags' look is no longer a setting: it was a second way of saying
    -- what the darkening slider says.
    T.eq(Bags.defaults.style, nil, "there is no bag look in the defaults")
    T.eq(Bags.options.args.style, nil, "nor is there such a setting in the section")

    -- The section stayed the subsystem's section but does not stand as a row
    -- in the column: its place is assigned by the settings tree (Config/Options.lua).
    T.eq(Bags.options.type, "group", "the section is an AceConfig group")
    T.eq(type(Bags.options.args.slotBorder), "table", "the border is in the section")
end

T.suite("the bags: the slots' border")

--- A stand-in texture.
local function fakeTexture(name, layer)
    local texture = { shown = true, r = 1, g = 1, b = 1, a = 1 }
    function texture:GetObjectType() return "Texture" end
    function texture:GetName() return name end
    function texture:GetDrawLayer() return layer or "ARTWORK" end
    function texture:GetTexture() return "interface\\buttons\\ui-slot" end
    function texture:GetVertexColor() return self.r, self.g, self.b, self.a end
    function texture:SetVertexColor(r, g, b, a)
        self.r, self.g, self.b, self.a = r, g, b, a
    end
    function texture:SetColorTexture(r, g, b, a)
        self.r, self.g, self.b, self.a = r, g, b, a
    end
    function texture:ClearAllPoints() end
    function texture:SetPoint() end
    function texture:SetWidth() end
    function texture:SetHeight() end
    function texture:SetAllPoints() end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    return texture
end

--- A stand-in font string: exactly the methods the game touches.
local function fakeText(r, g, b, a)
    local text = { r = r, g = g, b = b, a = a }
    function text:GetObjectType() return "FontString" end
    function text:GetTextColor() return self.r, self.g, self.b, self.a end
    function text:SetTextColor(nr, ng, nb, na)
        self.r, self.g, self.b, self.a = nr, ng, nb, na
    end
    return text
end

--- A stand-in frame with regions.
local function fakeFrame(regions)
    local frame = { regions = regions or {} }
    function frame:GetObjectType() return "Frame" end
    function frame:GetRegions() return unpack(self.regions) end
    function frame:GetChildren() return end
    function frame:CreateTexture()
        local texture = fakeTexture(nil)
        self.regions[#self.regions + 1] = texture
        return texture
    end
    return frame
end

do
    local art = fakeTexture("ContainerFrame1Background")
    local count = fakeText(1, 1, 1, 1)

    local window = fakeFrame({ art })
    local slot = fakeFrame({ count })

    _G.ContainerFrame1 = window
    _G.ContainerFrame1Item1 = slot

    T.eq(Bags.Paint("ContainerFrame1", true), true, "the window was found")
    local border = Bags.Border(slot)
    T.ok(border ~= nil, "the slot's border was built")
    T.eq(border.TOP.shown, true, "and shown")

    -- The subsystem does not touch the window's native picture at all: it is
    -- quenched by the general darkening, and a second owner of that texture would be superfluous.
    T.eq(art.r, 1, "the window's native picture was not touched")
    T.eq(window.umbraBg, nil, "and no fill of our own appeared beneath it")
    T.eq(count.r, 1, "the stack's number kept its own colour")

    -- Switching it off hides the border rather than deleting it: a texture
    -- cannot be released in this API anyway, and showing it again is cheaper than creating it afresh.
    T.eq(Bags.Paint("ContainerFrame1", false), true, "the border was switched off")
    T.eq(Bags.Border(slot).TOP.shown, false, "and hidden")

    T.eq(Bags.Paint("ContainerFrame1", true), true, "switched back on")
    T.eq(Bags.Border(slot).TOP.shown, true, "and shown again")

    T.eq(Bags.Paint("NoSuchWindow", true), false,
        "a window that does not exist is not an error")

    _G.ContainerFrame1 = nil
    _G.ContainerFrame1Item1 = nil
end
