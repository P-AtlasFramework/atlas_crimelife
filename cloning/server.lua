-- atlas_crimelife / cloning — server.
--
-- Plate-clone flow:
--   1. Player uses `vin_cloner` from inventory near a vehicle.
--   2. Client InputDialog asks for the new plate text.
--   3. Client fires `cloning:requestClone` with netId + new plate.
--   4. Server validates: plate format, not registered to a player in
--      the `vehicles` collection (no clashing with someone's owned car).
--   5. Server replies `cloning:start` → client runs progress bar.
--   6. Client confirms `cloning:complete` → server applies plate via
--      SetVehicleNumberPlateText, optionally grants vehicle key + marks
--      scratched, consumes item, awards XP, audits.
--
-- Persisted in `vin_cloned` (audit log; one row per successful clone).
-- Plates set on entities aren't persistent across server restart unless
-- the vehicle is in the `parked_vehicles` or `vehicles` collection —
-- and we don't write to those. World vehicles will revert on restart,
-- which matches expectation: a clone's a temporary identity.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = Cloning.Config

-- citizenid → { netId, oldPlate, newPlate, slot, startedAt }
local Pending = {}

local function nowSec() return os.time() end
local function nowIso() return os.date('!%Y-%m-%dT%H:%M:%SZ') end

local function cidOf(src)
    local p = Atlas.Functions.GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function cleanPlate(plate)
    return (plate or ''):upper():gsub('%s+$', ''):gsub('^%s+', '')
end

-- Plate is valid GTA-style: 1-8 chars, alphanumeric + space.
local function validPlateFormat(plate)
    if type(plate) ~= 'string' then return false end
    local p = plate
    if #p < config.plateMinLen or #p > config.plateMaxLen then return false end
    return p:match('^[A-Z0-9 ]+$') ~= nil
end

-- Refuse plates already registered to a player vehicle.
local function isPlateOwned(plate)
    local owned = false
    pcall(function()
        owned = MongoDB.Game.findOne('vehicles', { plate = plate }) ~= nil
    end)
    return owned
end

-- ─── Useable item ────────────────────────────────────────────────

Atlas.Functions.CreateUseableItem(config.item, function(source, item)
    TriggerClientEvent('atlas_crimelife:cl:useCloner', source, item.slot)
end)

RegisterNetEvent('atlas_crimelife:cl:requestClone', function(vehNetId, newPlate, slot)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    if Pending[cid] then
        lib.notify({ source = src, description = 'Already cloning a plate', type = 'error', duration = 3000 })
        return
    end

    if type(vehNetId) ~= 'number' then return end
    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        lib.notify({ source = src, description = 'Vehicle not found', type = 'error', duration = 3000 })
        return
    end

    local pCoords = GetEntityCoords(GetPlayerPed(src))
    local vCoords = GetEntityCoords(vehicle)
    if #(pCoords - vCoords) > config.maxDistance + 1.0 then
        lib.notify({ source = src, description = 'Get closer to the vehicle', type = 'error', duration = 3000 })
        return
    end

    local cleaned = cleanPlate(newPlate)
    if not validPlateFormat(cleaned) then
        lib.notify({ source = src, description = 'Bad plate format (1-8 chars, A-Z 0-9)', type = 'error', duration = 4000 })
        return
    end

    if isPlateOwned(cleaned) then
        lib.notify({ source = src, description = 'That plate is already on someone\'s registry', type = 'error', duration = 4000 })
        return
    end

    local hasItem = false
    pcall(function() hasItem = exports['atlas_inv']:HasItem(src, config.item, 1) end)
    if not hasItem then
        lib.notify({ source = src, description = 'No cloner kit', type = 'error', duration = 3000 })
        return
    end

    local oldPlate = cleanPlate(GetVehicleNumberPlateText(vehicle))

    Pending[cid] = {
        netId     = vehNetId,
        oldPlate  = oldPlate,
        newPlate  = cleaned,
        slot      = slot,
        startedAt = nowSec(),
    }
    TriggerClientEvent('atlas_crimelife:cl:start', src, config.cloneDurationMs)
end)

RegisterNetEvent('atlas_crimelife:cl:complete', function()
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    local pending = Pending[cid]
    if not pending then return end

    local elapsedMs = (nowSec() - pending.startedAt) * 1000
    if elapsedMs < (config.cloneDurationMs - 1500) then
        Pending[cid] = nil
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(pending.netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        Pending[cid] = nil
        lib.notify({ source = src, description = 'Vehicle gone', type = 'error', duration = 3000 })
        return
    end

    local pCoords = GetEntityCoords(GetPlayerPed(src))
    local vCoords = GetEntityCoords(vehicle)
    if #(pCoords - vCoords) > config.maxDistance + 1.5 then
        Pending[cid] = nil
        lib.notify({ source = src, description = 'You moved too far away', type = 'error', duration = 3000 })
        return
    end

    -- Re-check: someone could have purchased that plate while the player
    -- was holding the bar. Rare, but cheap to check.
    if isPlateOwned(pending.newPlate) then
        Pending[cid] = nil
        lib.notify({ source = src, description = 'Plate registered while you worked — voided', type = 'error', duration = 4000 })
        return
    end

    local removed = false
    pcall(function() removed = exports['atlas_inv']:RemoveItem(src, config.item, 1, pending.slot, 'cloning:clone') end)
    if not removed then
        Pending[cid] = nil
        return
    end

    -- Apply the new plate to the vehicle. Server-side native works on
    -- networked entities and replicates to all clients.
    SetVehicleNumberPlateText(vehicle, pending.newPlate)

    -- Optional integrations
    if config.autoScratchOnClone then
        pcall(function() exports['atlas_crimelife']:MarkScratched(pending.newPlate, cid) end)
    end

    if config.grantKeyOnClone then
        pcall(function() exports['atlas_vehiclekeys']:GrantOwnerKey(src, pending.newPlate) end)
    end

    -- Audit
    pcall(function()
        MongoDB.Game.insertOne('vin_cloned', {
            citizenid = cid,
            oldPlate  = pending.oldPlate,
            newPlate  = pending.newPlate,
            timestamp = nowIso(),
        })
    end)
    pcall(function()
        MongoDB.Game.insertOne('crime_runs', {
            citizenid = cid,
            module    = 'cloning',
            status    = 'completed',
            data      = { oldPlate = pending.oldPlate, newPlate = pending.newPlate },
            timestamp = nowIso(),
        })
    end)

    StreetCred.AddXp(src, config.crimeXp)
    Pending[cid] = nil

    lib.notify({ source = src, description = ('Plate cloned to %s — +%d XP'):format(pending.newPlate, config.crimeXp), type = 'success', duration = 5500 })
end)

RegisterNetEvent('atlas_crimelife:cl:cancel', function()
    local src = source
    local cid = cidOf(src)
    if cid then Pending[cid] = nil end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local cid = cidOf(src)
    if cid then Pending[cid] = nil end
end)
