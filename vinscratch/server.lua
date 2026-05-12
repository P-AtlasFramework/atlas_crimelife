-- atlas_crimelife / vinscratch — server.
--
-- VIN scrubbing flow:
--   1. Player uses `vin_kit` from their inventory while standing next
--      to a vehicle. atlas_inv fires our useable-item handler.
--   2. Server validates: vehicle exists, player is close enough, plate
--      isn't already scratched.
--   3. Server replies `vinscratch:start` → client runs progress bar.
--   4. Client confirms `vinscratch:complete` → server re-validates,
--      removes the kit, marks the plate in `vin_scratched`, awards XP.
--
-- The "scratched" flag is kept in MongoDB so it survives restart. Every
-- module that wants to know "is this plate clean?" reads `IsScratched`
-- (exported below). Chop shop does this to bypass owner-refusal + add
-- a bonus multiplier on the parts table.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = VinScratch.Config

-- plate (cleaned) → true
local Scratched = {}

-- citizenid → { netId, plate, startedAt }
local Pending = {}

local function nowSec() return os.time() end
local function nowIso() return os.date('!%Y-%m-%dT%H:%M:%SZ') end

local function cidOf(src)
    local p = Atlas.Functions.GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function cleanPlate(plate)
    return (plate or ''):gsub('%s+', '')
end

-- ─── Persistence ─────────────────────────────────────────────────

local function loadAll()
    pcall(function()
        local rows = MongoDB.Game.findMany('vin_scratched',
            { _id = { ['$exists'] = true } }) or {}
        for _, r in ipairs(rows) do
            if r.plate and r.plate ~= '' then
                Scratched[r.plate] = true
            end
        end
    end)
    print(('^2[atlas_crimelife.vinscratch]^7 loaded %d scratched plates'):format(
        (function() local n = 0 for _ in pairs(Scratched) do n = n + 1 end return n end)()
    ))
end

local function persistScratch(plate, citizenid)
    pcall(function()
        local existing = MongoDB.Game.findOne('vin_scratched', { plate = plate })
        local doc = {
            plate     = plate,
            citizenid = citizenid,
            scrubbed_at = nowIso(),
        }
        if existing then
            MongoDB.Game.updateOne('vin_scratched', { plate = plate }, { ['$set'] = doc })
        else
            MongoDB.Game.insertOne('vin_scratched', doc)
        end
    end)
end

CreateThread(function()
    while not MongoDB or not MongoDB.Game do Wait(250) end
    Wait(2000)
    loadAll()
end)

-- ─── Useable item ────────────────────────────────────────────────

Atlas.Functions.CreateUseableItem(config.item, function(source, item)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    -- The scrub anim doesn't drive the gameplay state; the client just
    -- triggers the progress bar via the start event. The actual vehicle
    -- + distance check happens on the client, which sends back a netId
    -- the server can re-validate before consuming the item.
    TriggerClientEvent('atlas_crimelife:vs:useKit', src, item.slot)
end)

-- Client found a vehicle and wants to start the scrub. The client passes
-- the vehicle's netId. Server validates + replies with `start`.
RegisterNetEvent('atlas_crimelife:vs:requestScrub', function(vehNetId, slot)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    if Pending[cid] then
        lib.notify({ source = src, description = 'You\'re already scrubbing one', type = 'error', duration = 3000 })
        return
    end

    if type(vehNetId) ~= 'number' then return end
    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        lib.notify({ source = src, description = 'Vehicle not found', type = 'error', duration = 3000 })
        return
    end

    -- Distance gate
    local pCoords = GetEntityCoords(GetPlayerPed(src))
    local vCoords = GetEntityCoords(vehicle)
    if #(pCoords - vCoords) > config.maxDistance + 1.0 then
        lib.notify({ source = src, description = 'Get closer to the vehicle', type = 'error', duration = 3000 })
        return
    end

    local plate = cleanPlate(GetVehicleNumberPlateText(vehicle))
    if plate == '' then return end
    if Scratched[plate] then
        lib.notify({ source = src, description = 'This plate has already been scrubbed', type = 'info', duration = 3500 })
        return
    end

    -- Verify the kit is in the slot (anti-tamper)
    local hasKit = false
    pcall(function() hasKit = exports['atlas_inv']:HasItem(src, config.item, 1) end)
    if not hasKit then
        lib.notify({ source = src, description = 'No scrubbing kit', type = 'error', duration = 3000 })
        return
    end

    Pending[cid] = {
        netId     = vehNetId,
        plate     = plate,
        slot      = slot,
        startedAt = nowSec(),
    }
    TriggerClientEvent('atlas_crimelife:vs:start', src, config.scrubDurationMs)
end)

RegisterNetEvent('atlas_crimelife:vs:complete', function()
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    local pending = Pending[cid]
    if not pending then return end

    -- Anti-tamper: enforce minimum elapsed time
    local elapsedMs = (nowSec() - pending.startedAt) * 1000
    if elapsedMs < (config.scrubDurationMs - 1500) then
        Pending[cid] = nil
        return
    end

    -- Re-resolve vehicle (might have despawned mid-scrub).
    local vehicle = NetworkGetEntityFromNetworkId(pending.netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        Pending[cid] = nil
        lib.notify({ source = src, description = 'Vehicle gone', type = 'error', duration = 3000 })
        return
    end

    -- Re-check distance
    local pCoords = GetEntityCoords(GetPlayerPed(src))
    local vCoords = GetEntityCoords(vehicle)
    if #(pCoords - vCoords) > config.maxDistance + 1.5 then
        Pending[cid] = nil
        lib.notify({ source = src, description = 'You moved too far away', type = 'error', duration = 3000 })
        return
    end

    -- Plate must still match (anti-swap)
    local plate = cleanPlate(GetVehicleNumberPlateText(vehicle))
    if plate ~= pending.plate then
        Pending[cid] = nil
        lib.notify({ source = src, description = 'Plate changed mid-scrub — voided', type = 'error', duration = 3500 })
        return
    end

    -- Consume the kit
    local removed = false
    pcall(function() removed = exports['atlas_inv']:RemoveItem(src, config.item, 1, pending.slot, 'vinscratch:scrub') end)
    if not removed then
        Pending[cid] = nil
        return
    end

    Scratched[plate] = true
    persistScratch(plate, cid)

    StreetCred.AddXp(src, config.crimeXp)
    Pending[cid] = nil

    pcall(function()
        MongoDB.Game.insertOne('crime_runs', {
            citizenid = cid,
            module    = 'vinscratch',
            status    = 'completed',
            data      = { plate = plate },
            timestamp = nowIso(),
        })
    end)

    lib.notify({ source = src, description = ('Plate %s scrubbed — +%d XP'):format(plate, config.crimeXp), type = 'success', duration = 5000 })
end)

RegisterNetEvent('atlas_crimelife:vs:cancel', function()
    local src = source
    local cid = cidOf(src)
    if not cid then return end
    Pending[cid] = nil
end)

-- ─── Cleanup + exports ───────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    local cid = cidOf(src)
    if cid then Pending[cid] = nil end
end)

-- Cross-module read API. Chop shop calls this to decide owner-refusal
-- bypass + bonus payout.
exports('IsScratched', function(plate)
    return Scratched[cleanPlate(plate)] == true
end)

-- Cross-module write API. Cloning calls this when its `autoScratchOnClone`
-- is enabled, so the freshly-cloned plate is treated as untraceable.
exports('MarkScratched', function(plate, citizenid)
    plate = cleanPlate(plate)
    if plate == '' then return false end
    Scratched[plate] = true
    persistScratch(plate, citizenid or 'cloning')
    return true
end)

-- Admin clear for testing.
Atlas.Commands.Add('clearvin', 'Admin: clear scratched flag on a plate',
    { { name = 'plate', help = 'Plate text' } }, true,
    function(source, args)
        local plate = cleanPlate(tostring(args[1] or ''))
        if plate == '' then return end
        Scratched[plate] = nil
        pcall(function() MongoDB.Game.deleteOne('vin_scratched', { plate = plate }) end)
        lib.notify({ source = source, description = ('Cleared scratched flag on %s'):format(plate), type = 'success' })
    end, 'admin'
)
