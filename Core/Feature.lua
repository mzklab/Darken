local ADDON, ns = ...

-- A namespace of its own for each part of the addon.
--
-- === Why it exists ===
--
-- The game hands every file of one addon ONE shared table. While there were
-- few parts that was enough. There are seven now, and each arrived from a
-- separate addon with its own habits: the auras have Rules, so do the
-- nameplates, and the info panel has its own Format. Piled into one table
-- they overwrite each other — and they overwrite SILENTLY: both parts still
-- answer with a table, just not with their own.
--
-- So each part takes a separate table and works on it. The core stays on the
-- shared one: its names were claimed long ago and there is no need to split
-- it.
--
-- === Why not a table per file ===
--
-- Files of one part need each other: the aura grid calls that part's rules,
-- the panel window its own cells. The table is shared by a part rather than
-- by a file precisely because a part is what lives together.

--- A part's namespace, by its key.
--
-- Created on first request and returned unchanged afterwards: every file of
-- the part asks for it separately, and a second table for the same part would
-- mean half of it on one table and half on another.
--
-- @param key any the part's short name
-- @return table
function ns.Feature(key)
    if type(key) ~= "string" or key == "" then
        error("a part of the addon must name itself", 2)
    end

    ns.features = ns.features or {}

    local own = ns.features[key]
    if own == nil then
        own = {}
        ns.features[key] = own
    end

    return own
end
