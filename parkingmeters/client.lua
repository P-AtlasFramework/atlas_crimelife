-- atlas_crimelife / parkingmeters — client.
--
-- Registers atlas_target options on every parking meter / phonebox prop
-- in the world (atlas_target:AddTargetModel does the proximity matching
-- for us). Each tool gets its own option so the player chooses crowbar
-- vs master_key from the radial.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = ParkingMeters.Config

local busy = false

-- Scratch helper to query ped position for the canInteract gate.
local function localHasItem(item)
    local has = false
    pcall(function() has = exports['atlas_inv']:HasItem(item, 1) end)
    return has == true
end

-- True iff the named weapon (e.g. 'weapon_crowbar') is currently drawn.
-- We hit GetSelectedPedWeapon directly: Atlas.Cache.weapon read via
-- GetCoreObject() returns a snapshot of the cache table taken at resource
-- start (FiveM serializes cross-resource exports — not a live ref), so
-- it never reflects the live equipped weapon. Native call is cheap and
-- canInteract only runs while the player is aiming at a meter.
local function isWeaponEquipped(weaponName)
    local current = GetSelectedPedWeapon(PlayerPedId())
    return current == joaat(weaponName)
end

-- ─── atlas_target wiring ─────────────────────────────────────────

-- Build one atlas_target option per tool. canInteract gates on:
--   • not already busy
--   • not seated in a vehicle
--   • the tool is available (equipped if requireEquipped, else carried)
local function buildOptions()
    local opts = {}
    for toolKey, tool in pairs(config.tools) do
        opts[#opts + 1] = {
            name      = 'atlas_crimelife:pm:' .. toolKey,
            label     = tool.label,
            icon      = tool.icon,
            iconColor = tool.iconColor,
            distance  = 2.0,
            canInteract = function(entity)
                if busy then return false end
                if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
                if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
                if tool.requireEquipped then
                    return isWeaponEquipped(tool.item)
                end
                return localHasItem(tool.item)
            end,
            onSelect = function(target)
                local entity = target and target.entity
                if not entity or entity == 0 then return end
                local coords = GetEntityCoords(entity)
                TriggerServerEvent('atlas_crimelife:pm:requestSmash', toolKey, {
                    x = coords.x, y = coords.y, z = coords.z,
                })
            end,
        }
    end
    return opts
end

CreateThread(function()
    while GetResourceState('atlas_target') ~= 'started' do Wait(250) end
    pcall(function()
        exports['atlas_target']:AddTargetModel(config.targetModels, {
            options  = buildOptions(),
            distance = 2.0,
        })
    end)
    print('^2[atlas_crimelife.parkingmeters]^7 target options registered for ' ..
        tostring(#config.targetModels) .. ' models')
end)

-- ─── Smash flow ──────────────────────────────────────────────────

RegisterNetEvent('atlas_crimelife:pm:start', function(toolKey, durationMs)
    if busy then return end
    local tool = config.tools[toolKey]
    if not tool then return end
    busy = true

    -- Loud crowbar smash plays a clang sound the whole neighborhood
    -- can hear. Quiet master_key skips this.
    if tool.soundOnHit then
        local sc = GetEntityCoords(PlayerPedId())
        PlaySoundFromCoord(-1, 'CLICK_GENERIC',
            sc.x, sc.y, sc.z,
            'WEB_NAVIGATION_SOUNDS_PHONE', false, 0, false)
    end

    local ok = exports['atlas_core']:CircleProgressBar({
        label    = tool.label,
        duration = durationMs,
        anim     = tool.anim,
        disable  = { car = true, move = true, mouse = false, combat = true },
    })
    busy = false

    if ok then
        TriggerServerEvent('atlas_crimelife:pm:complete')
    else
        TriggerServerEvent('atlas_crimelife:pm:cancel')
        lib.notify({ description = 'Cancelled', type = 'info', duration = 2500 })
    end
end)
