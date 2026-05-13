-- atlas_crimelife / copperscrap — client.
--
-- Two atlas_target hooks: one per prop group (AC vs electrical box).
-- Plus a scrapyard fence ped at the LS junkyard with its own InputDialog
-- prompts for selling.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = CopperScrap.Config

local busy = false

local function localHasItem(item)
    local has = false
    pcall(function() has = exports['atlas_inv']:HasItem(item, 1) end)
    return has == true
end

-- ─── atlas_target wiring (props) ─────────────────────────────────

CreateThread(function()
    while GetResourceState('ox_target') ~= 'started' do Wait(250) end

    for groupKey, group in pairs(config.propGroups) do
        pcall(function()
            exports.ox_target:AddTargetModel(group.models, {
                options = {
                    {
                        name      = 'atlas_crimelife:cps:' .. groupKey,
                        label     = group.label,
                        icon      = group.icon,
                        iconColor = group.color,
                        distance  = 2.0,
                        canInteract = function(entity)
                            if busy then return false end
                            if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
                            if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
                            return localHasItem(config.tool.item)
                        end,
                        onSelect = function(target)
                            local entity = target and target.entity
                            if not entity or entity == 0 then return end
                            local coords = GetEntityCoords(entity)
                            TriggerServerEvent('atlas_crimelife:cps:requestStrip', groupKey, {
                                x = coords.x, y = coords.y, z = coords.z,
                            })
                        end,
                    },
                },
                distance = 2.0,
            })
        end)
    end
    print('^2[atlas_crimelife.copperscrap]^7 prop hooks registered')
end)

-- ─── Strip flow ──────────────────────────────────────────────────

RegisterNetEvent('atlas_crimelife:cps:start', function()
    if busy then return end
    busy = true

    local anim = config.anim
    if anim and anim.dict and anim.clip then
        exports['atlas_core']:PlayAnim({
            dict = anim.dict, clip = anim.clip, flag = anim.flag or 49,
        })
    end

    local success = false
    pcall(function()
        success = lib.skillCheck(
            config.skillCheck.difficulty,
            config.skillCheck.inputs
        )
    end)

    local ped = PlayerPedId()
    if anim and anim.dict and anim.clip then
        StopAnimTask(ped, anim.dict, anim.clip, 1.0)
    end
    ClearPedSecondaryTask(ped)
    busy = false

    -- On failure, also play a small electrical pop sound. Stock SFX bank.
    if not success then
        local sc = GetEntityCoords(ped)
        PlaySoundFromCoord(-1, 'Zap', sc.x, sc.y, sc.z,
            'CELL_PHONE_THEFT_SOUNDSET', false, 0, false)
    end

    TriggerServerEvent('atlas_crimelife:cps:complete', success)
end)

-- ─── Scrapyard fence NPC ─────────────────────────────────────────

local fencePed
local fenceLoaded = false

CreateThread(function()
    while GetResourceState('ox_target') ~= 'started' do Wait(250) end

    local hash = GetHashKey(config.fence.ped)
    RequestModel(hash)
    local started = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - started < 4000 do Wait(0) end
    if not HasModelLoaded(hash) then return end

    local fc = config.fence.coords
    fencePed = CreatePed(4, hash, fc.x, fc.y, fc.z - 1.0, fc.w, false, false)
    SetEntityAsMissionEntity(fencePed, true, true)
    SetBlockingOfNonTemporaryEvents(fencePed, true)
    SetPedDiesWhenInjured(fencePed, false)
    SetPedCanRagdoll(fencePed, false)
    SetEntityInvincible(fencePed, true)
    FreezeEntityPosition(fencePed, true)
    if config.fence.scenario then
        TaskStartScenarioInPlace(fencePed, config.fence.scenario, 0, true)
    end
    SetModelAsNoLongerNeeded(hash)
    fenceLoaded = true

    -- Map blip
    local blip = AddBlipForCoord(fc.x, fc.y, fc.z)
    SetBlipSprite(blip, 365)         -- crate icon
    SetBlipColour(blip, 5)           -- yellow
    SetBlipScale(blip, 0.75)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(config.fence.label)
    EndTextCommandSetBlipName(blip)

    -- atlas_target option on the fence (entity, options[]) positional.
    pcall(function()
        exports.ox_target:addLocalEntity(fencePed, {
            {
                name      = 'atlas_crimelife:cps:fence_sell',
                label     = 'Sell scrap',
                icon      = 'fas fa-coins',
                iconColor = '#facc15',
                distance  = 2.5,
                onSelect  = function()
                    local opts = {}
                    for itemName, price in pairs(config.fence.prices) do
                        opts[#opts + 1] = {
                            value = itemName,
                            label = ('%s — $%d ea'):format(itemName, price),
                        }
                    end

                    local values = lib.inputDialog(
                        'Scrap Fence',
                        {
                            { type = 'select', name = 'item', label = 'Item',     options = opts, isRequired = true },
                            { type = 'number', name = 'qty',  label = 'Quantity', isRequired = true },
                        }
                    )
                    if not values then return end
                    local item = values[1]
                    local qty  = tonumber(values[2]) or 0
                    if not item or qty <= 0 then
                        lib.notify({ description = 'Bad quantity', type = 'error' })
                        return
                    end
                    TriggerServerEvent('atlas_crimelife:cps:fenceSell', item, qty)
                end,
            },
        })
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if fenceLoaded and fencePed and DoesEntityExist(fencePed) then
        DeleteEntity(fencePed)
    end
end)
