-- atlas_crimelife / parkingmeters — server.
--
-- Entry-tier, foot-only crime. Player walks up to a parking meter or
-- phone box, picks crowbar (loud) or master_key (silent), and runs the
-- minigame. On success: cash payout + small crime XP + zone heat gain.
--
-- The "prop" we're operating on is a world-map decoration, not a
-- networked entity. We key per-prop cooldown by rounded coords —
-- stable across clients without needing entity ids.
--
-- Heat is in-memory only. Each zone (defined in config.zones) keeps a
-- decaying counter; when it crosses heatHighThreshold we emit
-- `atlas_crimelife:heat:rise` for atlas_dispatch (deferred) to consume.

local Atlas = exports['atlas_core']:GetCoreObject()
local config = ParkingMeters.Config

-- coordKey → unix timestamp last paid out
local PropCooldowns = {}

-- citizenid → unix timestamp of last action (any tool)
local PlayerCooldowns = {}

-- citizenid → { coordKey, tool, startedAt } — pending action
local Pending = {}

-- zone id → { heat = 0..N, lastUpdateMs = number }
local ZoneHeat = {}

local function nowSec() return os.time() end
local function nowMs()  return GetGameTimer() end
local function nowIso() return os.date('!%Y-%m-%dT%H:%M:%SZ') end

local function cidOf(src)
    local p = Atlas.Functions.GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

-- Stable string key for a world prop, derived from its coords. Decimeter
-- resolution is enough — meters don't move and aren't stacked.
local function coordKey(coords)
    return ('%d:%d:%d'):format(
        math.floor((coords.x or 0) * 10),
        math.floor((coords.y or 0) * 10),
        math.floor((coords.z or 0) * 10)
    )
end

-- ─── Heat tracking ───────────────────────────────────────────────

-- Returns the zone whose center is closest to coords (within radius).
-- nil if no zone applies — heat for actions outside any zone is dropped
-- on the floor. Future: add a global fallback.
local function zoneFor(coords)
    for _, z in ipairs(config.zones) do
        if #(coords - z.center) <= z.radius then return z end
    end
    return nil
end

local function decayedHeat(zoneId)
    local h = ZoneHeat[zoneId]
    if not h then return 0 end
    local age = nowMs() - h.lastUpdateMs
    if age <= 0 then return h.heat end
    -- Linear decay: 100 heat → 0 across heatDecayMs.
    local decay = (h.heat * age) / config.heatDecayMs
    return math.max(0, h.heat - decay)
end

local function bumpHeat(zone, delta)
    if not zone or delta <= 0 then return end
    local cur = decayedHeat(zone.id)
    local new = math.min(100, cur + delta)
    ZoneHeat[zone.id] = { heat = new, lastUpdateMs = nowMs() }

    if new >= config.heatHighThreshold and cur < config.heatHighThreshold then
        -- First crossing of the threshold this cycle. Future atlas_dispatch
        -- subscribers can now spawn cops / tip the player off / etc.
        TriggerEvent('atlas_crimelife:heat:rise', {
            module   = 'parkingmeters',
            zoneId   = zone.id,
            zoneLabel = zone.label,
            center   = zone.center,
            heat     = new,
            threshold = config.heatHighThreshold,
        })
    end
end

-- ─── Payout helpers ──────────────────────────────────────────────

local function pickToolDef(toolKey)
    return config.tools[toolKey]
end

local function logRun(citizenid, status, payload)
    pcall(function()
        MongoDB.Game.insertOne('crime_runs', {
            citizenid = citizenid,
            module    = 'parkingmeters',
            status    = status,
            data      = payload or {},
            timestamp = nowIso(),
        })
    end)
end

-- ─── Net handlers ────────────────────────────────────────────────

RegisterNetEvent('atlas_crimelife:pm:requestSmash', function(toolKey, propCoords)
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    local tool = pickToolDef(toolKey)
    if not tool then return end

    if type(propCoords) ~= 'vector3' and type(propCoords) ~= 'table' then return end
    local coords = vec3(propCoords.x or 0, propCoords.y or 0, propCoords.z or 0)
    local key = coordKey(coords)

    -- Player throttle
    local lastP = PlayerCooldowns[cid] or 0
    if nowSec() - lastP < config.perPlayerCooldownSec then
        lib.notify({ source = src, description = 'Slow down', type = 'error', duration = 2500 })
        return
    end

    -- Per-prop cooldown
    local lastProp = PropCooldowns[key] or 0
    if nowSec() - lastProp < config.perPropCooldownSec then
        lib.notify({ source = src, description = 'This one\'s already empty', type = 'error', duration = 3000 })
        return
    end

    -- Already pending
    if Pending[cid] then
        lib.notify({ source = src, description = 'You\'re already on one', type = 'error', duration = 3000 })
        return
    end

    -- Tool item present?
    local has = false
    pcall(function() has = exports['atlas_inv']:HasItem(src, tool.item, 1) end)
    if not has then
        lib.notify({ source = src, description = 'Need a ' .. tool.item, type = 'error', duration = 3500 })
        return
    end

    -- Rank gate (master_key)
    if tool.rankMin and tool.rankMin > 0 then
        local rank = StreetCred.GetRank(src)
        if rank < tool.rankMin then
            lib.notify({ source = src, description = ('Distributor only — need crime rank %d'):format(tool.rankMin), type = 'error', duration = 4000 })
            return
        end
    end

    -- Distance check (anti-spoof)
    local pCoords = GetEntityCoords(GetPlayerPed(src))
    if #(pCoords - coords) > 3.5 then
        lib.notify({ source = src, description = 'Get closer', type = 'error', duration = 3000 })
        return
    end

    Pending[cid] = {
        key       = key,
        coords    = coords,
        tool      = toolKey,
        startedAt = nowSec(),
    }
    TriggerClientEvent('atlas_crimelife:pm:start', src, toolKey, tool.durationMs)
end)

RegisterNetEvent('atlas_crimelife:pm:complete', function()
    local src = source
    local cid = cidOf(src)
    if not cid then return end

    local pending = Pending[cid]
    if not pending then return end
    local tool = pickToolDef(pending.tool)
    if not tool then Pending[cid] = nil; return end

    -- Anti-tamper: enforce minimum elapsed time
    local elapsedMs = (nowSec() - pending.startedAt) * 1000
    if elapsedMs < (tool.durationMs - 1500) then
        Pending[cid] = nil
        logRun(cid, 'failed', { reason = 'too-fast', elapsedMs = elapsedMs })
        return
    end

    -- Re-check distance + cooldown (window may have closed mid-action)
    local pCoords = GetEntityCoords(GetPlayerPed(src))
    if #(pCoords - pending.coords) > 4.0 then
        Pending[cid] = nil
        lib.notify({ source = src, description = 'You moved off it', type = 'error', duration = 3000 })
        return
    end
    if nowSec() - (PropCooldowns[pending.key] or 0) < config.perPropCooldownSec then
        Pending[cid] = nil
        return
    end

    -- Crime payouts are markedbills only — criminals don't deal in
    -- clean cash. (A laundering pathway will be added back in a future
    -- iteration of the racketeering / protection rework.)
    local payout = math.random(tool.payoutMin, tool.payoutMax)

    -- homeland_bonus: street gang members + others with the flag get
    -- +25% payout when smashing in their gang's home zone. Encourages
    -- staying on turf even though heat builds faster there.
    local bonus = false
    if GangPerms.Has(src, 'homeland_bonus') then
        local inHome = false
        pcall(function() inHome = GangPerms.IsInHomeTurf(src) end)
        if inHome then
            payout = math.floor(payout * 1.25)
            bonus = true
        end
    end

    pcall(function() exports['atlas_inv']:AddItem(src, 'markedbills', payout, nil, nil, 'parkingmeters:smash') end)

    -- Heat
    local zone = zoneFor(pending.coords)
    bumpHeat(zone, tool.heatGain)

    -- Cooldowns + cleanup
    PropCooldowns[pending.key] = nowSec()
    PlayerCooldowns[cid]       = nowSec()
    Pending[cid]               = nil

    StreetCred.AddXp(src, config.crimeXp)
    logRun(cid, 'completed', {
        tool   = pending.tool,
        coords = { x = pending.coords.x, y = pending.coords.y, z = pending.coords.z },
        zone   = zone and zone.id or nil,
        payout = payout,
    })

    lib.notify({ source = src, description = bonus
            and ('+$%d marked (home turf) / +%d XP'):format(payout, config.crimeXp)
            or  ('+$%d marked / +%d XP'):format(payout, config.crimeXp), type = 'success', duration = 4000 })
end)

RegisterNetEvent('atlas_crimelife:pm:cancel', function()
    local src = source
    local cid = cidOf(src)
    if cid then Pending[cid] = nil end
end)

-- ─── Cleanup ─────────────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    local cid = cidOf(src)
    if cid then Pending[cid] = nil end
end)

-- ─── Heat read API + admin ───────────────────────────────────────

exports('GetZoneHeat', function(zoneId)
    return decayedHeat(zoneId)
end)

exports('GetAllZoneHeat', function()
    local out = {}
    for _, z in ipairs(config.zones) do
        out[z.id] = { label = z.label, heat = decayedHeat(z.id) }
    end
    return out
end)

-- Cross-module zone lookup. atlas_mgmt's /gangturf validates zone ids
-- through here. Returns the full zone def or nil.
exports('GetZoneById', function(zoneId)
    for _, z in ipairs(config.zones) do
        if z.id == zoneId then return z end
    end
    return nil
end)

-- Returns the zone the player is currently inside, or nil if outside
-- every defined zone. Used by homeland_bonus checks in copperscrap +
-- parkingmeters to grant the gang's home-turf payout multiplier.
exports('GetZoneAtCoords', function(coords)
    if not coords then return nil end
    local v3 = vec3(coords.x or 0, coords.y or 0, coords.z or 0)
    for _, z in ipairs(config.zones) do
        if #(v3 - z.center) <= z.radius then return z end
    end
    return nil
end)

-- Cross-module API: any other entry crime (copper/scrap and future
-- modules) can dump its own heat impact into the same zone counters.
-- Keeps the "neighborhood gets hot whether you smash meters or strip
-- copper" effect. `coords` is the world position of the action; we
-- resolve to the zone. Returns the new heat value (post-bump,
-- post-decay), or 0 if no zone.
exports('BumpHeat', function(coords, delta)
    if not coords or type(delta) ~= 'number' or delta <= 0 then return 0 end
    local v3 = vec3(coords.x or 0, coords.y or 0, coords.z or 0)
    local zone = zoneFor(v3)
    if not zone then return 0 end
    bumpHeat(zone, delta)
    return decayedHeat(zone.id)
end)

Atlas.Commands.Add('heatmap', 'Admin: dump current zone heat',
    {}, false,
    function(source)
        local lines = {}
        for _, z in ipairs(config.zones) do
            lines[#lines + 1] = ('%-14s %5.1f'):format(z.label, decayedHeat(z.id))
        end
        lib.notify({ source = source, description = 'Heat:\n' .. table.concat(lines, '\n'), type = 'info', duration = 8000 })
    end,
    'admin'
)
