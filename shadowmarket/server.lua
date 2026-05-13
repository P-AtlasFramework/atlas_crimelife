-- atlas_crimelife / shadowmarket — server.
--
-- Phase 1 mule loop:
--   1. Player approaches a handler ped → ox_target option fires
--      `atlas_crimelife:sm:requestPickup`.
--   2. Server validates: not on cooldown, not already on a run, has
--      inventory space. Selects a random drop ped (filtered by
--      minDropDistance from the handler).
--   3. Server gives the player a `contraband_smallpkg` item and stores
--      `ActiveRuns[citizenid] = { handlerIdx, dropIdx, startedAt }`.
--      Returns the drop coords + ped index to the client.
--   4. Player walks/drives to the drop ped → ox_target on the drop
--      ped fires `atlas_crimelife:sm:requestDropoff` with the ped index.
--   5. Server validates the ped index matches the active run, removes
--      the package, pays markedbills + crime XP, audits, clears state.
--
-- All persistence lives in atlas_mongodb. Crime XP goes through
-- atlas_core's AddCrimeXp (not stored locally — see streetcred.lua).

local Atlas = exports['atlas_core']:GetCoreObject()
local config = ShadowMarket.Config

-- citizenid → { handlerIdx, dropIdx, startedAt }
local ActiveRuns = {}

-- citizenid → unix timestamp of last run completion (cooldown gate)
local LastRun = {}

local function nowSec() return os.time() end
local function nowIso() return os.date('!%Y-%m-%dT%H:%M:%SZ') end

local function cidOf(src)
    local p = Atlas.Functions.GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

-- ─── Drop selection ──────────────────────────────────────────────

local function pickDrop(handlerIdx)
    local handler = config.handlers[handlerIdx]
    if not handler then return nil end
    local hCoords = vec3(handler.coords.x, handler.coords.y, handler.coords.z)

    -- Build the eligible pool — drops at or beyond minDropDistance.
    local pool = {}
    for i, drop in ipairs(config.drops) do
        local dCoords = vec3(drop.coords.x, drop.coords.y, drop.coords.z)
        if #(hCoords - dCoords) >= config.minDropDistance then
            pool[#pool + 1] = i
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

-- ─── Audit log ───────────────────────────────────────────────────

local function logRun(citizenid, status, payload)
    pcall(function()
        MongoDB.Game.insertOne('crime_runs', {
            citizenid = citizenid,
            module    = 'shadowmarket',
            status    = status,
            data      = payload or {},
            timestamp = nowIso(),
        })
    end)
end

-- ─── Net handlers ────────────────────────────────────────────────

-- Client requests a new pickup. handlerIdx is the index of the handler
-- ped the player interacted with (1..#config.handlers). Server replies
-- with `{ok=true, dropIdx, drop}` or `{ok=false, reason}`.
RegisterNetEvent('atlas_crimelife:sm:requestPickup', function(handlerIdx)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    if type(handlerIdx) ~= 'number' or not config.handlers[handlerIdx] then return end

    -- Cooldown
    local last = LastRun[cid] or 0
    local elapsed = nowSec() - last
    if elapsed < config.cooldown then
        local wait = config.cooldown - elapsed
        lib.notify({ source = src, description = ('Come back in %dm %ds'):format(math.floor(wait / 60), wait % 60), type = 'error', duration = 4000 })
        return
    end

    -- Already on a run — no double-dipping
    if ActiveRuns[cid] then
        lib.notify({ source = src, description = 'You\'re already moving a package', type = 'error', duration = 3500 })
        return
    end

    -- Inventory space + add package
    local hasItem = false
    pcall(function() hasItem = exports['atlas_inv']:CanCarry(src, config.package, 1) end)
    if hasItem == false then
        lib.notify({ source = src, description = 'Not enough room in your bag', type = 'error', duration = 3500 })
        return
    end

    local addOk = false
    pcall(function() addOk = exports['atlas_inv']:AddItem(src, config.package, 1, nil, nil, 'shadowmarket:pickup') end)
    if not addOk then
        lib.notify({ source = src, description = 'Couldn\'t take the package', type = 'error', duration = 3500 })
        return
    end

    local dropIdx = pickDrop(handlerIdx)
    if not dropIdx then
        -- Fallback: refund the item, abort.
        pcall(function() exports['atlas_inv']:RemoveItem(src, config.package, 1, nil, 'shadowmarket:pickup-rollback') end)
        lib.notify({ source = src, description = 'No buyer available right now', type = 'error', duration = 4000 })
        return
    end

    ActiveRuns[cid] = {
        handlerIdx = handlerIdx,
        dropIdx    = dropIdx,
        startedAt  = nowSec(),
    }

    logRun(cid, 'started', { handlerIdx = handlerIdx, dropIdx = dropIdx })

    TriggerClientEvent('atlas_crimelife:sm:pickupAck', src, dropIdx, config.drops[dropIdx])
    lib.notify({ source = src, description = 'Drop the package at the marker', type = 'info', duration = 5000 })
end)

-- Client confirms dropoff at drop ped `dropIdx`.
RegisterNetEvent('atlas_crimelife:sm:requestDropoff', function(dropIdx)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    local run = ActiveRuns[cid]
    if not run then
        lib.notify({ source = src, description = 'You don\'t have a package to drop', type = 'error', duration = 3500 })
        return
    end

    if type(dropIdx) ~= 'number' or dropIdx ~= run.dropIdx then
        lib.notify({ source = src, description = 'Wrong buyer — find the right one', type = 'error', duration = 4000 })
        return
    end

    -- Validate distance — client could lie about being there.
    local ped = GetPlayerPed(src)
    local pedCoords = GetEntityCoords(ped)
    local drop = config.drops[dropIdx]
    local dropCoords = vec3(drop.coords.x, drop.coords.y, drop.coords.z)
    if #(pedCoords - dropCoords) > 8.0 then
        lib.notify({ source = src, description = 'Get closer to the buyer', type = 'error', duration = 3500 })
        return
    end

    -- Validate package presence + remove
    local hasPkg = false
    pcall(function() hasPkg = exports['atlas_inv']:HasItem(src, config.package, 1) end)
    if not hasPkg then
        lib.notify({ source = src, description = 'You don\'t have the package', type = 'error', duration = 3500 })
        ActiveRuns[cid] = nil
        return
    end

    local removed = false
    pcall(function() removed = exports['atlas_inv']:RemoveItem(src, config.package, 1, nil, 'shadowmarket:dropoff') end)
    if not removed then
        lib.notify({ source = src, description = 'Failed to hand over the package', type = 'error', duration = 3500 })
        return
    end

    -- Pay out + crime XP
    local pay = math.random(config.payout.markedbills.min, config.payout.markedbills.max)
    pcall(function() exports['atlas_inv']:AddItem(src, config.payoutItem, pay, nil, nil, 'shadowmarket:payout') end)
    StreetCred.AddXp(src, config.payout.crimeXp)

    ActiveRuns[cid] = nil
    LastRun[cid] = nowSec()

    logRun(cid, 'completed', { handlerIdx = run.handlerIdx, dropIdx = dropIdx, pay = pay })

    lib.notify({ source = src, description = ('Run complete — $%d marked bills + %d XP'):format(pay, config.payout.crimeXp), type = 'success', duration = 5000 })
    TriggerClientEvent('atlas_crimelife:sm:runEnded', src)
end)

-- ─── Cleanup ─────────────────────────────────────────────────────

-- Player drops with an active run → log it as abandoned. The package
-- stays in their inventory (atlas_inv persists across DC). On rejoin
-- they CAN'T deliver it because ActiveRuns[cid] is empty — they'd need
-- to manually drop the item or wait for cooldown to start a new run.
AddEventHandler('playerDropped', function()
    local src = source
    local cid = cidOf(src)
    if not cid then return end
    if ActiveRuns[cid] then
        logRun(cid, 'abandoned', { handlerIdx = ActiveRuns[cid].handlerIdx })
        ActiveRuns[cid] = nil
    end
end)

-- ─── Exports for cross-module use ────────────────────────────────

exports('GetActiveRun', function(src)
    local cid = cidOf(src)
    return cid and ActiveRuns[cid] or nil
end)

exports('GetCooldownRemaining', function(src)
    local cid = cidOf(src)
    if not cid then return 0 end
    local last = LastRun[cid] or 0
    local remaining = config.cooldown - (nowSec() - last)
    return math.max(0, remaining)
end)
