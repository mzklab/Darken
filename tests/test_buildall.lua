local helpers = require("helpers")
local coldboot = require("coldboot")

-- Every row of every page is assembled without falling over.
--
-- === Why this is separate from the other checks ===
--
-- The others check DECISIONS: what was selected, what was hidden, where a row
-- went. What is checked here is what they do not see at all: whether a row
-- survives to the screen. A row that fell over used to carry the whole page
-- with it — the player saw an empty space where eighteen settings are — and
-- the only way to learn of it was to open the page and look.
--
-- And so it happened: a slider's number field was painted in the "field"
-- colour, and "field" is not a colour but a state. The palette knows no such
-- name, Skin.Get returns nothing, the engine falls over on SetColorTexture(nil).
--
-- === Why the fake engine here is a STRICT one ===
--
-- A lenient fake would not have noticed that mistake at all: its
-- SetColorTexture swallows anything, a nil included. So here it behaves like
-- the engine in exactly what the engine falls over on: a colour with no
-- number, a size with no number, an anchor to nowhere. A fake that forgives
-- more than the real thing checks something other than what the player will get.

local nothing = function() end

--- A fake frame.
-- @param kind string
-- @return table
local function fake(kind)
    local o = { kind = kind, shown = false, points = {} }

    o.Show = function(self) self.shown = true end
    o.Hide = function(self) self.shown = false end
    o.IsShown = function(self) return self.shown end
    o.SetText = function(self, value) self.text = value end
    o.GetText = function(self) return self.text or "" end
    o.ClearAllPoints = function(self) self.points = {} end
    o.CreateTexture = function() return fake("Texture") end
    o.CreateFontString = function() return fake("FontString") end
    o.GetThumbTexture = function() return fake("Texture") end
    o.SetScrollChild = function(self, child) self.child = child end
    o.SetScript = function(self, name, fn)
        self.scripts = self.scripts or {}
        self.scripts[name] = fn
    end

    o.GetStringHeight = function() return 12 end
    o.GetStringWidth = function() return 40 end
    o.GetValue = function(self) return self.value or 0 end
    o.GetFrameLevel = function() return 1 end
    o.GetVerticalScroll = function() return 0 end
    o.IsEnabled = function() return true end
    o.GetObjectType = function(self) return self.kind end

    -- Strict: exactly what the engine falls over on.
    o.SetColorTexture = function(self, r, g, b, a)
        if type(r) ~= "number" or type(g) ~= "number"
            or type(b) ~= "number" then
            error("SetColorTexture with no colour")
        end
        self.ink = { r, g, b, a }
    end
    o.SetTextColor = function(self, r, g, b)
        if type(r) ~= "number" or type(g) ~= "number"
            or type(b) ~= "number" then
            error("SetTextColor with no colour")
        end
        self.tint = { r, g, b }
    end
    o.SetHeight = function(self, value)
        if type(value) ~= "number" then error("SetHeight with no number") end
        self.height = value
    end
    o.SetWidth = function(self, value)
        if type(value) ~= "number" then error("SetWidth with no number") end
        self.width = value
    end
    o.GetHeight = function(self) return self.height or 20 end
    o.GetWidth = function(self) return self.width or 600 end
    o.SetSize = function(self, w, h)
        if type(w) ~= "number" or type(h) ~= "number" then
            error("SetSize with no numbers")
        end
        self.width, self.height = w, h
    end
    o.SetPoint = function(self, point, ...)
        if type(point) ~= "string" then error("SetPoint with no side") end
        self.points[#self.points + 1] = point
    end

    for _, name in ipairs({
        "SetAllPoints", "SetFrameStrata", "SetToplevel", "EnableMouse",
        "SetMovable", "SetClampedToScreen", "RegisterForDrag", "StartMoving",
        "StopMovingOrSizing", "SetBackdrop", "SetBackdropColor",
        "SetBackdropBorderColor", "SetAlpha", "SetTexture", "SetVertexColor",
        "SetDrawLayer", "SetJustifyH", "SetJustifyV", "SetWordWrap",
        "SetSpacing", "SetMinMaxValues", "SetValue", "SetValueStep",
        "SetObeyStepOnDrag", "SetOrientation", "SetThumbTexture", "Enable",
        "Disable", "SetAutoFocus", "SetMultiLine", "SetMaxLetters",
        "SetNumeric", "SetCursorPosition", "ClearFocus", "SetFocus",
        "HighlightText", "SetTextInsets", "SetFrameLevel", "SetHitRectInsets",
        "EnableMouseWheel", "SetVerticalScroll", "SetHorizontalScroll",
        "SetParent", "SetScale", "SetShown", "SetNormalTexture",
        "SetHighlightTexture", "SetPushedTexture", "SetShadowOffset",
        "SetShadowColor", "SetFont", "SetFontObject",
    }) do o[name] = nothing end

    return o
end

T.suite("the window: every row of every page survives to the screen")

do
    local r = coldboot.boot({ toc = "Darken.toc", interface = 11507,
        modules = true })
    local ns = r.ns

    -- The fake is installed AFTER the bring-up, and that order is
    -- obligatory: the bring-up creates a CreateFrame of its own and
    -- overwrites anybody else's. Installed earlier, the strict fake took no
    -- part in the assembly at all — and the check passed cleanly on the very code that fell over for the player.
    local saved = { CreateFrame = _G.CreateFrame, UIParent = _G.UIParent }
    _G.UIParent = fake("Frame")
    _G.CreateFrame = function(kind) return fake(kind) end

    local root, broken, pages, rows, blank
    if r.coreLoaded and type(ns.Window) == "table" then
        local okRoot, got = pcall(ns.Window.Build)
        root = okRoot and got or nil

        broken, pages, rows, blank = {}, 0, 0, {}
        local holder = root and root.scroll and root.scroll.content

        for _, page in ipairs(ns.Schema.Pages()) do
            pages = pages + 1
            for _, item in ipairs(ns.Window.Plan(page.id)) do
                rows = rows + 1
                local fine, why = pcall(ns.Window.Row, holder,
                    ns.Window.Owner(page, item), item)
                if not fine then
                    broken[#broken + 1] = page.id .. "/"
                        .. tostring(item.label or item.kind) .. ": "
                        .. tostring(why)
                end

                -- A select whose chosen value is not found in its own list
                -- shows an EMPTY row. The player reads that as "the setting
                -- does not work": that is how eleven selects of the
                -- darkening's areas stood for the author, and the cause was a read that had fallen over.
                --
                -- An empty value is legitimate: it is returned by the selects
                -- that have nothing to choose from until the player has
                -- chosen (where to copy a profile, for instance).
                if item.kind == "select" then
                    local own = ns.Window.Owner(page, item)
                    local okValue, value = pcall(ns.Window.Value, own, item)
                    local choices = ns.Window.Choices(item)

                    if okValue and value ~= nil and #choices > 0 then
                        local found = false
                        for _, choice in ipairs(choices) do
                            if choice.key == value then found = true break end
                        end
                        if not found then
                            blank[#blank + 1] = page.id .. "/"
                                .. tostring(item.label) .. ": the chosen \""
                                .. tostring(value) .. "\" is not in the list"
                        end
                    end
                end
            end
        end
    end

    _G.CreateFrame, _G.UIParent = saved.CreateFrame, saved.UIParent
    if r.restore then r.restore() end

    T.ok(root ~= nil, "the window assembled on the fake engine")
    T.ok(blank ~= nil and #blank == 0,
        "every select's chosen value is in its list: "
        .. table.concat(blank or { "the check did not get there" }, " | "))
    T.ok(broken ~= nil and #broken == 0, "not one row fell over: "
        .. table.concat(broken or { "the check did not get there" }, " | "))

    -- The numbers matter in themselves: a page that had lost all its rows
    -- would pass the check above cleanly — there is nothing to fall over.
    T.ok((pages or 0) >= 12, "pages assembled: " .. tostring(pages))
    T.ok((rows or 0) >= 100, "rows assembled: " .. tostring(rows))
end

T.suite("a choice can carry the picture it stands for")

-- A list of nine bar textures named "Darken Purple" against "Darken Pink" asks
-- the player to tell two pictures apart by their words. The row shows the
-- texture itself instead, and the window learns the path from the row that
-- declared the choices rather than knowing what a bar texture is.
do
    local r = coldboot.boot({ toc = "Darken.toc", interface = 11507,
        modules = true })
    local Window = r.ns.Window

    local item = {
        kind = "select",
        values = { a = "Alpha", b = "Beta" },
        preview = function(key)
            if key == "a" then return "Interface/Alpha" end
            return nil
        end,
    }

    local out = Window.Choices(item)
    T.eq(#out, 2, "both choices are offered")

    local byKey = {}
    for i = 1, #out do byKey[out[i].key] = out[i] end

    T.eq(byKey.a.preview, "Interface/Alpha", "the one with a picture carries it")
    T.eq(byKey.b.preview, nil, "and the one without carries nothing")

    -- A row that declares no preview at all is the ordinary case and must not
    -- be disturbed: the list draws exactly as it did before.
    local plain = Window.Choices({ kind = "select", values = { a = "Alpha" } })
    T.eq(plain[1].preview, nil, "a list with no previews has none")

    -- A preview that falls over is no preview, not a broken window.
    local broken = Window.Choices({
        kind = "select",
        values = { a = "Alpha" },
        preview = function() error("no such file") end,
    })
    T.eq(broken[1].preview, nil, "a preview that fell over is simply absent")
    T.eq(broken[1].text, "Alpha", "and the choice itself is untouched")
end
