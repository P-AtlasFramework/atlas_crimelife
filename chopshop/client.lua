-- atlas_crimelife / chopshop — client.
--
-- Drive a stolen vehicle into the chop shop zone → ox_target on the
-- vehicle exposes "Strip Vehicle" → progress bar runs → server awards
-- parts and deletes the car.
--
-- Zone draws a floor marker so players see WHERE to park. ox_target's
-- canInteract gates on (in-zone, vehicle is networked, vehicle isn't
-- excluded class). Server runs the actual gameplay logic.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = ChopShop.Config

local stripping = false
local zoneBlip = nil

-- ─── Map blip ────────────────────────────────────────────────────

CreateThread(function()
    zoneBlip = AddBlipForCoord(config.zone.center.x, config.zone.center.y, config.zone.center.z)
    SetBlipSprite(zoneBlip, 446)         -- spanner
    SetBlipColour(zoneBlip, 1)           -- red
    SetBlipScale(zoneBlip, 0.85)
    SetBlipAsShortRange(zoneBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Chop Shop')
    EndTextCommandSetBlipName(zoneBlip)
end)

-- ─── Floor marker ────────────────────────────────────────────────
-- Drawn only when the player is within ~30m of the zone, to keep the
-- per-frame draw cost off when not relevant.

CreateThread(function()
    while true do
        local pCoords = GetEntityCoords(PlayerPedId())
        local dist = #(pCoords - config.zone.center)
        if dist < 30.0 then
            DrawMarker(1,
                config.zone.marker.x, config.zone.marker.y, config.zone.marker.z,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                config.zone.radius * 2.0, config.zone.radius * 2.0, 1.0,
                239, 68, 68, 80,             -- red, semi-transparent
                false, false, 2, false, nil, nil, false)
            Wait(0)
        else
            Wait(1500)
        end
    end
end)

-- ─── Strip flow ──────────────────────────────────────────────────

local function inZone(vehicle)
    if not vehicle or vehicle == 0 then return false end
    local vCoords = GetEntityCoords(vehicle)
    return #(vCoords - config.zone.center) <= config.zone.radius
end

RegisterNetEvent('atlas_crimelife:cs:stripStart', function(durationMs)
    if stripping then return end
    stripping = true

    local ped = PlayerPedId()

    -- Force the player out of the vehicle (the chop crew works on it)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        TaskLeaveVehicle(ped, veh, 0)
        Wait(2000)
    end

    local ok = lib.progressCircle({
        label    = 'Stripping vehicle…',
        duration = durationMs,
        anim     = config.stripAnim,
        disable  = { car = true, move = true, mouse = false, combat = true },
    })

    if ok then
        TriggerServerEvent('atlas_crimelife:cs:requestStripComplete')
    else
        lib.notify({ description = 'Strip cancelled', type = 'info', duration = 3000 })
        stripping = false
    end
end)

RegisterNetEvent('atlas_crimelife:cs:stripDone', function()
    stripping = false
end)

-- ─── ox_target option on the targeted vehicle ─────────────────

CreateThread(function()
    while GetResourceState('ox_target') ~= 'started' do Wait(250) end

    exports.ox_target:addGlobalVehicle({
        {
            name      = 'atlas_crimelife:cs:strip',
            label     = 'Strip Vehicle',
            icon      = 'fas fa-screwdriver-wrench',
            iconColor = '#ef4444',
            distance  = 3.0,
            canInteract = function(entity)
                if stripping then return false end
                if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
                if not inZone(entity) then return false end
                local class = GetVehicleClass(entity)
                if config.excludedClasses[class] then return false end
                -- Player must NOT be in the vehicle (they have to step out
                -- to strip it — same as visiting the chop shop in real life).
                if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
                return true
            end,
            onSelect = function(target)
                local veh = target and target.entity
                if not veh or veh == 0 then return end
                local netId = NetworkGetNetworkIdFromEntity(veh)
                TriggerServerEvent('atlas_crimelife:cs:requestStrip', netId)
            end,
        },
    })

    print('^2[atlas_crimelife.chopshop]^7 strip option registered (zone @ ' ..
        ('%.1f, %.1f, %.1f'):format(config.zone.center.x, config.zone.center.y, config.zone.center.z) .. ')')
end)

-- ─── Cleanup ─────────────────────────────────────────────────────

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if zoneBlip then RemoveBlip(zoneBlip) end
end)
