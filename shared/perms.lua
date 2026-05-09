-- atlas_crimelife / shared / perms — gang permission helper.
--
-- Thin wrapper around atlas_mgmt's HasGangPermission export. Centralised
-- here so per-module gates are a single line and we can swap the
-- underlying source (or stub for tests) without touching every call site.

GangPerms = GangPerms or {}

if IsDuplicityVersion() then
    function GangPerms.Has(src, perm)
        if type(src) ~= 'number' or src <= 0 or type(perm) ~= 'string' then
            return false
        end
        local ok = false
        pcall(function()
            ok = exports['atlas_mgmt']:HasGangPermission(src, perm) == true
        end)
        return ok
    end

    -- Returns the player's gang doc (with archetype, permissions, customPerms,
    -- homeTurf, hqLocation, founderCid). nil if not in a gang.
    function GangPerms.GetGang(src)
        local gang
        pcall(function() gang = exports['atlas_mgmt']:GetPlayerGang(src) end)
        if not gang or not gang.name or gang.name == 'none' or gang.name == '' then
            return nil
        end
        return gang
    end

    -- Convenience: is this player currently inside their gang's home
    -- heat zone? Returns (bool, zone) — zone is the resolved zone def
    -- if true, nil otherwise. Used by `homeland_bonus` payout multiplier
    -- in parkingmeters + copperscrap.
    function GangPerms.IsInHomeTurf(src)
        local gang = GangPerms.GetGang(src)
        if not gang or not gang.homeTurf then return false, nil end

        local pCoords = GetEntityCoords(GetPlayerPed(src))
        local zoneAt
        pcall(function() zoneAt = exports['atlas_crimelife']:GetZoneAtCoords(pCoords) end)
        if not zoneAt then return false, nil end
        if zoneAt.id == gang.homeTurf then return true, zoneAt end
        return false, nil
    end
end
