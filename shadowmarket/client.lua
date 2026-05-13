-- atlas_crimelife / shadowmarket — client.
--
-- Spawns the handler peds and (lazily) the drop peds when a run starts.
-- ox_target options on each ped drive the loop. Marker + waypoint
-- on the drop site so the player can find it.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = ShadowMarket.Config

local handlerEntities = {}     -- handlerIdx → ped entity
local dropEntities = {}        -- dropIdx → ped entity
local activeBlip = nil
local activeDropIdx = nil

-- ─── Ped spawning ────────────────────────────────────────────────

local function loadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    RequestModel(hash)
    local started = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - started < 2000 do Wait(0) end
    return HasModelLoaded(hash) and hash or false
end

local function spawnHandler(idx, data)
    if handlerEntities[idx] and DoesEntityExist(handlerEntities[idx]) then return end
    local hash = loadModel(data.model)
    if not hash then return end
    local ped = CreatePed(4, hash, data.coords.x, data.coords.y, data.coords.z - 1.0, data.coords.w, false, false)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    handlerEntities[idx] = ped
    SetModelAsNoLongerNeeded(hash)
end

local function spawnDrop(idx, data)
    if dropEntities[idx] and DoesEntityExist(dropEntities[idx]) then return dropEntities[idx] end
    local hash = loadModel(data.model)
    if not hash then return end
    local ped = CreatePed(4, hash, data.coords.x, data.coords.y, data.coords.z - 1.0, data.coords.w, false, false)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    dropEntities[idx] = ped
    SetModelAsNoLongerNeeded(hash)
    return ped
end

local function despawnDrop(idx)
    local ped = dropEntities[idx]
    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
    end
    dropEntities[idx] = nil
end

-- ─── ox_target wiring ─────────────────────────────────────────

CreateThread(function()
    while GetResourceState('ox_target') ~= 'started' do Wait(250) end

    -- Spawn handlers and register their target options.
    for idx, data in ipairs(config.handlers) do
        spawnHandler(idx, data)
        local ped = handlerEntities[idx]
        if ped then
            exports.ox_target:addLocalEntity(ped, {
                {
                    name        = 'atlas_crimelife:sm:pickup_' .. idx,
                    label       = 'Pick up package',
                    icon        = 'fas fa-box',
                    iconColor   = '#ff9f43',
                    distance    = 2.5,
                    onSelect    = function()
                        TriggerServerEvent('atlas_crimelife:sm:requestPickup', idx)
                    end,
                },
            })
        end
    end
end)

-- ─── Run lifecycle on the client ─────────────────────────────────

RegisterNetEvent('atlas_crimelife:sm:pickupAck', function(dropIdx, dropData)
    if not dropIdx or not dropData then return end
    activeDropIdx = dropIdx

    -- Spawn the drop ped + register its target option (added per-run so
    -- the option only exists while THIS player has an active run).
    local ped = spawnDrop(dropIdx, dropData)
    if ped then
        -- addLocalEntity takes (entity, options[]) positionally.
        exports.ox_target:addLocalEntity(ped, {
            {
                name      = 'atlas_crimelife:sm:dropoff_' .. dropIdx,
                label     = 'Hand over package',
                icon      = 'fas fa-handshake',
                iconColor = '#22c55e',
                distance  = 2.5,
                canInteract = function()
                    return activeDropIdx == dropIdx
                end,
                onSelect  = function()
                    TriggerServerEvent('atlas_crimelife:sm:requestDropoff', dropIdx)
                end,
            },
        })
    end

    -- Map blip + active waypoint
    if activeBlip then RemoveBlip(activeBlip) end
    activeBlip = AddBlipForCoord(dropData.coords.x, dropData.coords.y, dropData.coords.z)
    SetBlipSprite(activeBlip, 1)
    SetBlipColour(activeBlip, 5)         -- yellow
    SetBlipScale(activeBlip, 0.85)
    SetBlipAsShortRange(activeBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Buyer')
    EndTextCommandSetBlipName(activeBlip)
    SetNewWaypoint(dropData.coords.x, dropData.coords.y)
end)

-- Server doesn't push an explicit "complete" event — but the dropoff
-- target onSelect → requestDropoff → server pays out. We listen for our
-- own success notify by clearing local state when the player visits the
-- drop ped and the server completes successfully (notify is the signal).
-- Simplest: clear state when player no longer has the package OR after
-- a confirmed dropoff response. We add a clean-state event for clarity.

RegisterNetEvent('atlas_crimelife:sm:runEnded', function()
    activeDropIdx = nil
    if activeBlip then RemoveBlip(activeBlip); activeBlip = nil end
    -- Despawning drop peds keeps the world clean. Pool plates so peds
    -- don't accumulate; respawn next run.
    for idx, _ in pairs(dropEntities) do despawnDrop(idx) end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in pairs(handlerEntities) do
        if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    for _, ped in pairs(dropEntities) do
        if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    if activeBlip then RemoveBlip(activeBlip) end
end)
