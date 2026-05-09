-- atlas_crimelife / copperscrap — server.
--
-- Strip AC units / electrical boxes for copper + scrap, then sell at
-- the scrapyard fence. Failure on the skillcheck shocks the player
-- (HP loss) and may break the wire cutters.
--
-- Heat is shared with parkingmeters via exports['atlas_crimelife']:BumpHeat
-- so a neighborhood gets hot regardless of which entry crime you ran.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = CopperScrap.Config

-- coordKey → unix timestamp (per-prop cooldown)
local PropCooldowns = {}

-- citizenid → unix timestamp of last action
local PlayerCooldowns = {}

-- citizenid → unix timestamp of last successful sell
local FenceCooldowns = {}

-- citizenid → { groupKey, coordKey, coords, startedAt }
local Pending = {}

local function nowSec() return os.time() end
local function nowIso() return os.date('!%Y-%m-%dT%H:%M:%SZ') end

local function cidOf(src)
    local p = Atlas.Functions.GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function coordKey(coords)
    return ('%d:%d:%d'):format(
        math.floor((coords.x or 0) * 10),
        math.floor((coords.y or 0) * 10),
        math.floor((coords.z or 0) * 10)
    )
end

local function bumpHeat(coords, delta)
    pcall(function() exports['atlas_crimelife']:BumpHeat(coords, delta) end)
end

local function logRun(citizenid, status, payload)
    pcall(function()
        MongoDB.Game.insertOne('crime_runs', {
            citizenid = citizenid,
            module    = 'copperscrap',
            status    = status,
            data      = payload or {},
            timestamp = nowIso(),
        })
    end)
end

-- ─── Strip flow ──────────────────────────────────────────────────

RegisterNetEvent('atlas_crimelife:cps:requestStrip', function(groupKey, propCoords)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    local group = config.propGroups[groupKey]
    if not group then return end

    if type(propCoords) ~= 'vector3' and type(propCoords) ~= 'table' then return end
    local coords = vec3(propCoords.x or 0, propCoords.y or 0, propCoords.z or 0)
    local key = coordKey(coords)

    if Pending[cid] then
        Atlas.Functions.Notify(src, 'Already on a job', 'error', 3000)
        return
    end

    if nowSec() - (PlayerCooldowns[cid] or 0) < config.perPlayerCooldownSec then
        Atlas.Functions.Notify(src, 'Slow down', 'error', 2500)
        return
    end

    if nowSec() - (PropCooldowns[key] or 0) < config.perPropCooldownSec then
        Atlas.Functions.Notify(src, 'This one\'s already been stripped', 'error', 3500)
        return
    end

    local pCoords = GetEntityCoords(GetPlayerPed(src))
    if #(pCoords - coords) > 3.5 then
        Atlas.Functions.Notify(src, 'Get closer', 'error', 3000)
        return
    end

    local hasItem = false
    pcall(function() hasItem = exports['atlas_inv']:HasItem(src, config.tool.item, 1) end)
    if not hasItem then
        Atlas.Functions.Notify(src, 'Need wire cutters', 'error', 3500)
        return
    end

    Pending[cid] = {
        groupKey  = groupKey,
        coordKey  = key,
        coords    = coords,
        startedAt = nowSec(),
    }
    TriggerClientEvent('atlas_crimelife:cps:start', src, groupKey)
end)

-- Client reports the skillcheck result. On success, roll loot. On
-- failure, deal shock damage + maybe break the cutters.
RegisterNetEvent('atlas_crimelife:cps:complete', function(success)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    local pending = Pending[cid]
    if not pending then return end
    local group = config.propGroups[pending.groupKey]
    if not group then Pending[cid] = nil; return end

    -- Re-check distance (player can't slip a fast-travel during the
    -- skillcheck either).
    local pCoords = GetEntityCoords(GetPlayerPed(src))
    if #(pCoords - pending.coords) > 4.5 then
        Pending[cid] = nil
        Atlas.Functions.Notify(src, 'You moved off it', 'error', 3000)
        return
    end

    PlayerCooldowns[cid] = nowSec()

    if success then
        -- homeland_bonus: gang members with the flag re-roll the loot
        -- table once when stripping in their home turf. Mirrors the
        -- chopshop scratched-plate pattern (~+50% expected yield).
        local rolls = 1
        if GangPerms.Has(src, 'homeland_bonus') then
            local inHome = false
            pcall(function() inHome = GangPerms.IsInHomeTurf(src) end)
            if inHome then rolls = 2 end
        end

        -- Roll the loot
        local awarded = {}
        for _, row in ipairs(group.loot) do
            for _ = 1, rolls do
                if math.random() <= row.chance then
                    local count = math.random(row.min, row.max)
                    if count > 0 then
                        local addOk = false
                        pcall(function() addOk = exports['atlas_inv']:AddItem(src, row.item, count, nil, nil, 'copperscrap:strip') end)
                        if addOk then
                            awarded[row.item] = (awarded[row.item] or 0) + count
                        end
                    end
                end
            end
        end

        PropCooldowns[pending.coordKey] = nowSec()
        StreetCred.AddXp(src, config.crimeXp)
        bumpHeat(pending.coords, config.heatGainSuccess)

        Pending[cid] = nil
        logRun(cid, 'completed', {
            group   = pending.groupKey,
            awarded = awarded,
            zone    = nil,
        })

        local parts = {}
        for k, v in pairs(awarded) do parts[#parts + 1] = ('+%d %s'):format(v, k) end
        Atlas.Functions.Notify(src,
            (#parts > 0 and table.concat(parts, ' / ') or 'No usable scrap') ..
                (' / +%d XP'):format(config.crimeXp),
            'success', 4500)
    else
        -- Failed skillcheck: shock the player and maybe break the tool.
        local ped = GetPlayerPed(src)
        local hp = GetEntityHealth(ped)
        SetEntityHealth(ped, math.max(101, hp - config.shockDamage))

        if math.random() < (config.tool.breakChance or 0) then
            pcall(function() exports['atlas_inv']:RemoveItem(src, config.tool.item, 1, nil, 'copperscrap:break') end)
            Atlas.Functions.Notify(src, 'Got shocked — cutters fried', 'error', 4500)
        else
            Atlas.Functions.Notify(src, 'Got shocked — try again', 'error', 4000)
        end

        bumpHeat(pending.coords, config.heatGainFailure)
        Pending[cid] = nil
        logRun(cid, 'failed', { group = pending.groupKey, reason = 'skillcheck' })
    end
end)

RegisterNetEvent('atlas_crimelife:cps:cancel', function()
    local src = source
    local cid = cidOf(src)
    if cid then Pending[cid] = nil end
end)

-- ─── Scrapyard fence ─────────────────────────────────────────────

RegisterNetEvent('atlas_crimelife:cps:fenceSell', function(itemName, qty)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    local price = config.fence.prices[itemName]
    if not price then return end

    qty = tonumber(qty) or 0
    if qty <= 0 or qty > config.fence.batchMax then
        Atlas.Functions.Notify(src,
            ('Sell 1-%d at a time'):format(config.fence.batchMax),
            'error', 3500)
        return
    end

    -- Distance check
    local pCoords = GetEntityCoords(GetPlayerPed(src))
    local fc = config.fence.coords
    if #(pCoords - vec3(fc.x, fc.y, fc.z)) > 4.0 then
        Atlas.Functions.Notify(src, 'Get to the fence', 'error', 3000)
        return
    end

    -- Cooldown
    if nowSec() - (FenceCooldowns[cid] or 0) < config.fence.sellCooldownSec then
        Atlas.Functions.Notify(src, 'Hold up — already counted last batch', 'error', 3500)
        return
    end

    local has = false
    pcall(function() has = exports['atlas_inv']:HasItem(src, itemName, qty) end)
    if not has then
        Atlas.Functions.Notify(src,
            ('Don\'t have %d %s'):format(qty, itemName),
            'error', 3500)
        return
    end

    local removed = false
    pcall(function() removed = exports['atlas_inv']:RemoveItem(src, itemName, qty, nil, 'copperscrap:fence') end)
    if not removed then
        Atlas.Functions.Notify(src, 'Failed to take the materials', 'error', 3500)
        return
    end

    -- Criminal fence pays markedbills, not clean cash.
    local pay = price * qty
    pcall(function() exports['atlas_inv']:AddItem(src, 'markedbills', pay, nil, nil, 'copperscrap:fence') end)

    FenceCooldowns[cid] = nowSec()
    logRun(cid, 'fence', { item = itemName, qty = qty, pay = pay })

    Atlas.Functions.Notify(src, ('Sold %d %s for $%d marked'):format(qty, itemName, pay), 'success', 4500)
end)

-- ─── Cleanup ─────────────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    local cid = cidOf(src)
    if cid then Pending[cid] = nil end
end)
