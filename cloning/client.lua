-- atlas_crimelife / cloning — client.
--
-- Player uses `vin_cloner`. We find the closest vehicle, prompt for the
-- new plate via InputDialog, then ship the request to the server. On
-- `start`, run the progress bar; on success, send `complete`.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = Cloning.Config

local cloning = false

local function findNearestVehicle()
    local pCoords = GetEntityCoords(PlayerPedId())
    local nearest, nearestDist = nil, config.maxDistance + 0.01
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(v) then
            local d = #(pCoords - GetEntityCoords(v))
            if d < nearestDist then
                nearest, nearestDist = v, d
            end
        end
    end
    if not nearest then return nil end
    return nearest, NetworkGetNetworkIdFromEntity(nearest)
end

local function cleanInputPlate(s)
    return (s or ''):upper():gsub('%s+$', ''):gsub('^%s+', '')
end

RegisterNetEvent('atlas_crimelife:cl:useCloner', function(slot)
    if cloning then
        Atlas.Functions.Notify('Already cloning a plate', 'error', 3000)
        return
    end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        Atlas.Functions.Notify('Step out first', 'error', 3000)
        return
    end
    local veh, netId = findNearestVehicle()
    if not veh or not netId then
        Atlas.Functions.Notify('No vehicle in range', 'error', 3000)
        return
    end

    local values = exports['atlas_core']:InputDialog(
        'Reflash Plate',
        {
            { type = 'input', name = 'plate', label = 'New plate (1-8 chars, A-Z 0-9)', isRequired = true },
        }
    )
    if not values then
        Atlas.Functions.Notify('Cancelled', 'primary', 2500)
        return
    end
    local newPlate = cleanInputPlate(values[1])
    if newPlate == '' or #newPlate > config.plateMaxLen then
        Atlas.Functions.Notify('Bad plate', 'error', 3000)
        return
    end

    TriggerServerEvent('atlas_crimelife:cl:requestClone', netId, newPlate, slot)
end)

RegisterNetEvent('atlas_crimelife:cl:start', function(durationMs)
    if cloning then return end
    cloning = true

    local ok = exports['atlas_core']:CircleProgressBar({
        label    = 'Reflashing plate…',
        duration = durationMs,
        anim     = config.anim,
        disable  = { car = true, move = true, mouse = false, combat = true },
    })
    cloning = false

    if ok then
        TriggerServerEvent('atlas_crimelife:cl:complete')
    else
        TriggerServerEvent('atlas_crimelife:cl:cancel')
        Atlas.Functions.Notify('Clone cancelled', 'primary', 3000)
    end
end)
