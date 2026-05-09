-- atlas_crimelife / shared / streetcred — thin readers around
-- atlas_core's Player.Functions.AddCrimeXp / PlayerData.crime.{rank,xp}.
--
-- We don't store a separate XP value. atlas_core already owns
-- PlayerData.crime persistence. This file is just sugar:
--
--   StreetCred.GetRank(player)  — server-side, returns rank int
--   StreetCred.GetXp(player)    — server-side, returns xp int
--   StreetCred.AddXp(player, n) — wraps AddCrimeXp; one place to log
--                                 if we want to audit later.

StreetCred = StreetCred or {}

if IsDuplicityVersion() then
    -- Server side
    local Atlas

    local function getCore()
        Atlas = Atlas or exports['atlas_core']:GetCoreObject()
        return Atlas
    end

    function StreetCred.GetCrime(src)
        local A = getCore()
        local p = A.Functions.GetPlayer(src)
        if not p then return { rank = 0, xp = 0 } end
        return p.PlayerData.crime or { rank = 0, xp = 0 }
    end

    function StreetCred.GetRank(src)
        return StreetCred.GetCrime(src).rank or 0
    end

    function StreetCred.GetXp(src)
        return StreetCred.GetCrime(src).xp or 0
    end

    function StreetCred.AddXp(src, amount)
        local A = getCore()
        local p = A.Functions.GetPlayer(src)
        if not p then return false end
        p.Functions.AddCrimeXp(amount)
        -- Broadcast for atlas_mgmt's gang auto-promotion hook (and any
        -- future achievement / progress-bar consumer) — passes the new
        -- cumulative XP so listeners don't have to re-read PlayerData.
        local newXp = p.PlayerData and p.PlayerData.crime and p.PlayerData.crime.xp or 0
        TriggerEvent('atlas_crimelife:streetcred:xpChanged', src, newXp, amount)
        return true
    end
end
