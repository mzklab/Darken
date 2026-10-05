local ADDON, ns = ...

-- The addon's page inside the game's own settings: two lines and a button.
--
-- === Why no settings here ===
--
-- The panel is a narrow strip shared with the game's category list. The
-- settings window assumes its own width and its own page column, so the page
-- only links to it.
--
-- === Why a plain frame ===
--
-- AceConfig built this page before the move. Three elements do not justify a
-- library that draws whole settings trees, along with its skin and widgets.
--
-- === Two registration paths ===
--
-- Newer clients expose Settings.RegisterCanvasLayoutCategory, older ones
-- InterfaceOptions_AddCategory. Whichever exists is used. If neither does
-- there is no page; this is not an error, because /darken still opens the
-- window.

local Bliz = {}
ns.Bliz = Bliz

local Widgets = ns.Widgets
local Skin = ns.Skin
local Try = Widgets and Widgets.Try or function() end
local M = Skin and Skin.Metrics or {}

--- Build the page.
-- @return table|nil
function Bliz.Build()
    if Bliz.frame then return Bliz.frame end
    if type(Widgets) ~= "table" then return nil end

    local frame = Widgets.Frame("Frame", _G.UIParent)
    if frame == nil then return nil end

    -- The page uses the addon name verbatim: the game lists it among its
    -- categories, and a second name for the same thing is a search problem
    -- for the player.
    frame.name = ADDON

    local about = Widgets.Text(frame, "text")
    if about then
        Try(about, "SetPoint", "TOPLEFT", frame, "TOPLEFT", M.group, -M.group)
        Try(about, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", -M.group,
            -M.group)
        Try(about, "SetJustifyV", "TOP")
        Try(about, "SetWordWrap", true)
        Try(about, "SetText", ns.Localize("Darken has a settings window of "
            .. "its own. This page is narrow and shares the screen with the "
            .. "game's own panels, so the settings live in that window "
            .. "instead of here."))
    end
    frame.about = about

    local open = Widgets.Button(frame,
        ns.Localize("Open the Settings Window"), function()
            local addon = ns.Addon
            if type(addon) == "table"
                and type(addon.OpenConfig) == "function" then
                addon:OpenConfig()
            end
        end)
    if open then
        Try(open, "ClearAllPoints")
        Try(open, "SetPoint", "TOPLEFT", about or frame,
            about and "BOTTOMLEFT" or "TOPLEFT", 0, -M.group)
    end
    frame.open = open

    local command = Widgets.Text(frame, "textDim")
    if command then
        Try(command, "SetPoint", "TOPLEFT", open or frame, "BOTTOMLEFT", 0,
            -M.gap)
        Try(command, "SetText", ns.Localize("Typing /darken in chat opens "
            .. "the same window."))
    end
    frame.command = command

    Bliz.frame = frame
    return frame
end

--- Register the page with the game's settings.
--
-- Returns success and which API accepted it; the diagnostic report records
-- the path taken, not only the outcome.
--
-- @return boolean
-- @return string|nil "Settings" or "InterfaceOptions"
function Bliz.Add()
    local frame = Bliz.Build()
    if frame == nil then return false, nil end

    -- Newer path. The Settings table does not exist on TBC Classic, so it
    -- is checked before use: an unguarded call aborts the rest of
    -- initialisation.
    local settings = _G.Settings
    if type(settings) == "table"
        and type(settings.RegisterCanvasLayoutCategory) == "function"
        and type(settings.RegisterAddOnCategory) == "function" then
        local ok, category = pcall(settings.RegisterCanvasLayoutCategory,
            frame, ADDON)
        if ok and category ~= nil then
            category.ID = ADDON
            if pcall(settings.RegisterAddOnCategory, category) then
                Bliz.category = category
                return true, "Settings"
            end
        end
    end

    -- Older path.
    if type(_G.InterfaceOptions_AddCategory) == "function" then
        if pcall(_G.InterfaceOptions_AddCategory, frame) then
            return true, "InterfaceOptions"
        end
    end

    -- Neither path available: not an error, /darken still works.
    return false, nil
end
