-- Is the interface dark BEFORE a window is opened?
--
-- This asks the question the live client was answering until the beta closed,
-- and it asks it of the whole addon rather than of one function: the core is
-- booted on a fake client, the world is entered, the deferred work is run,
-- and only then is anything checked. Everything a player would do by hand
-- happens here in order.
--
-- What is examined is a window that has NEVER been shown. That is the case
-- the whole of the named painting exists for, and the case the general walk
-- cannot serve - it does not enter what is hidden.

local helpers = require("helpers")
local coldboot = require("coldboot")

T.suite("the interface is dark before a window is opened")

do
    -- A window of the game's that the player has not opened: hidden, with a
    -- backdrop of its own, a header inside it, a bar and a portrait.
    --
    -- The names are ones the compatibility layer knows, because that is what
    -- the painting works from. StaticPopup1 is the confirmation dialog - one
    -- of the windows reported as appearing in the game's own colours.
    local art = function()
        local object = { r = 1, g = 1, b = 1, a = 1 }
        object.GetObjectType = function() return "Texture" end
        object.GetDrawLayer = function() return "ARTWORK" end
        object.GetTexture = function() return 606060 end
        object.GetAtlas = function() return nil end
        object.IsForbidden = function() return false end
        object.IsObjectType = function(_, kind) return kind == "Texture" end
        function object:GetVertexColor() return self.r, self.g, self.b, self.a end
        function object:SetVertexColor(cr, cg, cb, ca)
            self.r, self.g, self.b = cr, cg, cb
            if ca ~= nil then self.a = ca end
        end
        function object:SetDesaturated() end
        function object:GetName() return nil end
        return object
    end

    local backdrop, header, fill, bed, portrait = art(), art(), art(), art(), art()
    portrait.GetName = function() return "ContainerFrame1Portrait" end

    local bar = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "StaticPopup1Bar" end,
        IsShown = function() return false end,
        IsForbidden = function() return false end,
        GetRegions = function() return fill, bed end,
        GetChildren = function() return end,
        Show = function() end,
    }
    bar.Fill = fill

    local inside = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "StaticPopup1Header" end,
        IsShown = function() return false end,
        IsForbidden = function() return false end,
        GetRegions = function() return header end,
        GetChildren = function() return end,
        Show = function() end,
    }

    local popup
    popup = {
        GetObjectType = function() return "Frame" end,
        GetName = function() return "StaticPopup1" end,
        IsShown = function() return false end,
        IsForbidden = function() return false end,
        GetRegions = function() return backdrop, portrait end,
        GetChildren = function() return inside, bar end,
        Show = function() end,
        GetParent = function() return _G.UIParent end,
    }

    -- The client this is asked of is the one the author plays: the TOC and
    -- the interface number are named rather than left to a default, because
    -- which windows exist is a property of the client line.
    local booted = coldboot.boot({
        toc = "Darken_Camelot.toc",
        interface = 16001,
        class = "HUNTER",
        saved = {
            profileKeys = { ["Tester - Test"] = "Default" },
            profiles = { Default = { darkness = { amount = 80, mode = {} } } },
        },
        beforeLogin = function()
            -- The window exists before the world is entered, as a window of
            -- the game's does.
            _G.StaticPopup1 = popup
            local root = _G.UIParent
            local was = root.GetChildren
            root.GetChildren = function(self)
                if was then return was(self), popup end
                return popup
            end
        end,
    })

    booted.pump()

    -- Nothing has been shown. This is the state the player is in a second
    -- after entering the world, before touching anything.
    T.eq(popup.IsShown(), false, "the window has still never been shown")

    T.ok(backdrop.r < 1,
        "its backdrop is already dark: " .. string.format("%.2f", backdrop.r))
    T.ok(header.r < 1,
        "and the header inside it: " .. string.format("%.2f", header.r))

    -- And the things that must never be painted are not, in the same breath.
    T.eq(fill.r, 1, "the bar's fill is untouched")
    T.eq(portrait.r, 1, "and the portrait named as an exception")

    booted.restore()
end
