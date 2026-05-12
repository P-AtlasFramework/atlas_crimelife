-- atlas_crimelife / chopshop — server.
--
-- Strip-for-parts flow:
--   1. Client fires `atlas_crimelife:cs:requestStrip` with the vehicle netId.
--   2. Server validates:
--        - Player is at the chop shop zone.
--        - Vehicle exists, is networked, is not class-excluded.
--        - Player isn't on cooldown.
--        - Vehicle owner (atlas_mongodb lookup) is not the player.
--   3. Server replies `cs:stripStart` → client runs the progress bar.
--   4. Client confirms with `cs:requestStripComplete` after the bar fills.
--   5. Server validates the player + vehicle still match the request,
--      rolls the parts table, deletes the vehicle, awards parts +
--      crime XP + (if the vehicle was player-owned) a markedbills bonus.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = ChopShop.Config

-- citizenid → unix timestamp of last strip
local LastStrip = {}

-- citizenid → { netId, plate, class, isPlayerOwned, startedAt } — pending strip
local PendingStrips = {}

local function nowSec() return os.time() end
local function nowIso() return os.date('!%Y-%m-%dT%H:%M:%SZ') end

local function cidOf(src)
    local p = Atlas.Functions.GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function isInZone(src, vehicle)
    local pCoords = GetEntityCoords(GetPlayerPed(src))
    local center = config.zone.center
    if #(pCoords - center) > config.zone.radius then return false end
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        local vCoords = GetEntityCoords(vehicle)
        if #(vCoords - center) > config.zone.radius then return false end
    end
    return true
end

local function logRun(citizenid, status, payload)
    pcall(function()
        MongoDB.Game.insertOne('crime_runs', {
            citizenid = citizenid,
            module    = 'chopshop',
            status    = status,
            data      = payload or {},
            timestamp = nowIso(),
        })
    end)
end

-- Resolve vehicle owner via atlas_mongodb. Returns:
--   nil  → world NPC vehicle (no owner record)
--   cid  → owner citizenid
local function getVehicleOwner(plate)
    if not plate or plate == '' then return nil end
    local owner
    pcall(function() owner = exports['atlas_mongodb']:GetVehicleOwnerByPlate(plate) end)
    return owner
end

-- Pick the parts table for the vehicle's class + the player's tier.
local function pickPartsTable(vehicleClass, rank, src)
    -- Premium tier vehicles get the premium table for two routes:
    --   1. Solo grind — Distributor rank (5+) per the Phase 2 spec.
    --   2. Gang archetype — `chop_premium` permission flag (default
    --      MC Patched+ in the locked archetype design).
    local isPremiumClass =
        vehicleClass == 5 or vehicleClass == 6 or vehicleClass == 7
    if isPremiumClass and (
        HasCrimeTier(rank, 'distributor') or GangPerms.Has(src, 'chop_premium')
    ) then
        return config.premiumParts
    end
    return config.basicParts
end

-- ─── Net handlers ────────────────────────────────────────────────

RegisterNetEvent('atlas_crimelife:cs:requestStrip', function(vehNetId)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    -- Cooldown
    local last = LastStrip[cid] or 0
    local elapsed = nowSec() - last
    if elapsed < config.cooldown then
        local wait = config.cooldown - elapsed
        lib.notify({ source = src, description = ('Chop shop cooling down. %dm %ds'):format(math.floor(wait / 60), wait % 60), type = 'error', duration = 4500 })
        return
    end

    -- Already pending
    if PendingStrips[cid] then
        lib.notify({ source = src, description = 'You\'re already stripping a vehicle', type = 'error', duration = 3500 })
        return
    end

    -- Resolve the vehicle
    if type(vehNetId) ~= 'number' then return end
    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        lib.notify({ source = src, description = 'Vehicle not found', type = 'error', duration = 3500 })
        return
    end

    -- Class check
    local vehClass = -1
    pcall(function() vehClass = exports['atlas_core']:GetVehicleClass(GetEntityModel(vehicle)) end)
    if vehClass == -1 then
        -- Fallback: GetVehicleClass works server-side on networked entities.
        vehClass = GetVehicleClass(vehicle)
    end
    if config.excludedClasses[vehClass] then
        lib.notify({ source = src, description = 'That vehicle can\'t be stripped here', type = 'error', duration = 3500 })
        return
    end

    -- Zone check
    if not isInZone(src, vehicle) then
        lib.notify({ source = src, description = 'Vehicle must be inside the chop shop', type = 'error', duration = 3500 })
        return
    end

    -- Scratched-plate bypass: a scrubbed plate is "anonymous" — owner
    -- check is skipped (you can chop your own car if the VIN's been
    -- removed) and the parts table re-rolls for a payout bonus.
    local plate = (GetVehicleNumberPlateText(vehicle) or ''):gsub('%s+', '')
    local scratched = false
    pcall(function() scratched = exports['atlas_crimelife']:IsScratched(plate) end)

    -- Owner check — refuse if the player owns the vehicle, UNLESS the
    -- VIN has been scratched.
    local ownerCid = getVehicleOwner(plate)
    if not scratched and ownerCid and ownerCid == cid then
        lib.notify({ source = src, description = 'Can\'t chop your own vehicle', type = 'error', duration = 4000 })
        return
    end

    PendingStrips[cid] = {
        netId         = vehNetId,
        plate         = plate,
        class         = vehClass,
        isPlayerOwned = ownerCid ~= nil,
        scratched     = scratched,
        startedAt     = nowSec(),
    }
    logRun(cid, 'started', { plate = plate, class = vehClass })
    TriggerClientEvent('atlas_crimelife:cs:stripStart', src, config.stripDurationMs)
end)

RegisterNetEvent('atlas_crimelife:cs:requestStripComplete', function()
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    local pending = PendingStrips[cid]
    if not pending then
        lib.notify({ source = src, description = 'No active strip', type = 'error', duration = 3000 })
        return
    end

    -- Verify the strip duration actually elapsed (anti-tamper)
    local elapsed = (nowSec() - pending.startedAt) * 1000
    if elapsed < (config.stripDurationMs - 1500) then
        -- Way too fast — bail without rewarding
        PendingStrips[cid] = nil
        logRun(cid, 'failed', { reason = 'too-fast', elapsedMs = elapsed })
        return
    end

    -- Re-resolve the vehicle entity. It might have been despawned mid-strip.
    local vehicle = NetworkGetEntityFromNetworkId(pending.netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        PendingStrips[cid] = nil
        logRun(cid, 'failed', { reason = 'vehicle-gone', plate = pending.plate })
        lib.notify({ source = src, description = 'Vehicle gone — strip cancelled', type = 'error', duration = 3500 })
        return
    end

    -- Still in zone?
    if not isInZone(src, vehicle) then
        PendingStrips[cid] = nil
        logRun(cid, 'failed', { reason = 'zone-exit', plate = pending.plate })
        lib.notify({ source = src, description = 'Vehicle left the chop shop', type = 'error', duration = 3500 })
        return
    end

    -- Roll the parts table.
    local rank = StreetCred.GetRank(src)
    local parts = pickPartsTable(pending.class, rank, src)
    local awarded = {}

    -- Scratched plates re-roll each row twice → roughly +50% expected
    -- yield (each row's `chance` gets a second independent shot, and a
    -- fresh count rolls on each hit).
    local rerolls = pending.scratched and 2 or 1

    for _, row in ipairs(parts) do
        for _ = 1, rerolls do
            if math.random() <= row.chance then
                local count = math.random(row.min, row.max)
                local addOk = false
                pcall(function() addOk = exports['atlas_inv']:AddItem(src, row.item, count, nil, nil, 'chopshop:strip') end)
                if addOk then
                    awarded[row.item] = (awarded[row.item] or 0) + count
                end
            end
        end
    end

    -- Player-owned bonus: extra markedbills for chopping someone's car.
    local bonus = 0
    if pending.isPlayerOwned then
        bonus = math.random(config.playerVehicleBonus.min, config.playerVehicleBonus.max)
        pcall(function() exports['atlas_inv']:AddItem(src, 'markedbills', bonus, nil, nil, 'chopshop:bonus') end)
    end

    -- Award crime XP
    StreetCred.AddXp(src, config.crimeXp)

    -- Delete the vehicle
    DeleteEntity(vehicle)

    -- Cooldown + cleanup
    LastStrip[cid] = nowSec()
    PendingStrips[cid] = nil

    logRun(cid, 'completed', {
        plate          = pending.plate,
        class          = pending.class,
        isPlayerOwned  = pending.isPlayerOwned,
        scratched      = pending.scratched,
        awarded        = awarded,
        bonus          = bonus,
        rank           = rank,
        partsTable     = (parts == config.premiumParts) and 'premium' or 'basic',
    })

    local summary = ('+ %d XP'):format(config.crimeXp)
    if bonus > 0 then summary = summary .. (' / +$%d marked'):format(bonus) end
    if pending.scratched then summary = summary .. ' / scratched bonus' end
    lib.notify({ source = src, description = ('Stripped — %s'):format(summary), type = 'success', duration = 5000 })
    TriggerClientEvent('atlas_crimelife:cs:stripDone', src)
end)

-- Player drops mid-strip → log and clear pending state.
AddEventHandler('playerDropped', function()
    local src = source
    local cid = cidOf(src)
    if not cid then return end
    if PendingStrips[cid] then
        logRun(cid, 'abandoned', { plate = PendingStrips[cid].plate })
        PendingStrips[cid] = nil
    end
end)

-- Cross-module exports
exports('GetChopShopCooldown', function(src)
    local cid = cidOf(src)
    if not cid then return 0 end
    local last = LastStrip[cid] or 0
    return math.max(0, config.cooldown - (nowSec() - last))
end)
