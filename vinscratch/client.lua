-- atlas_crimelife / vinscratch — client.
--
-- Player uses `vin_kit` from inventory. Server fires `useKit` → we find
-- the closest vehicle within maxDistance and ask the server to start
-- the scrub. Server confirms `start` → we run the progress bar and
-- send `complete` on success.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = VinScratch.Config

local scrubbing = false

-- Find the closest vehicle within `maxDistance` of the player. Returns
-- the entity handle and netId, or nil if nothing in range.
local function findNearestVehicle()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local nearest, nearestDist = nil, config.maxDistance + 0.01

    -- The local pool is enough — we're looking for vehicles within ~3m.
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

RegisterNetEvent('atlas_crimelife:vs:useKit', function(slot)
    if scrubbing then
        Atlas.Functions.Notify('You\'re already scrubbing one', 'error', 3000)
        return
    end
    -- Don't allow inside a vehicle — feels wrong, and it confuses the
    -- "stand next to the car you're scrubbing" mental model.
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        Atlas.Functions.Notify('Step out first', 'error', 3000)
        return
    end
    local veh, netId = findNearestVehicle()
    if not veh or not netId then
        Atlas.Functions.Notify('No vehicle in range', 'error', 3000)
        return
    end
    TriggerServerEvent('atlas_crimelife:vs:requestScrub', netId, slot)
end)

RegisterNetEvent('atlas_crimelife:vs:start', function(durationMs)
    if scrubbing then return end
    scrubbing = true

    local ok = exports['atlas_core']:CircleProgressBar({
        label    = 'Scrubbing VIN…',
        duration = durationMs,
        anim     = config.anim,
        disable  = { car = true, move = true, mouse = false, combat = true },
    })
    scrubbing = false

    if ok then
        TriggerServerEvent('atlas_crimelife:vs:complete')
    else
        TriggerServerEvent('atlas_crimelife:vs:cancel')
        Atlas.Functions.Notify('Scrub cancelled', 'primary', 3000)
    end
end)
