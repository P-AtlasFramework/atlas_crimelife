-- atlas_crimelife / gangvault — server.
--
-- Standalone gang vault primitive. Per-gang shared markedbills balance,
-- capped at Config.vaultCap, persisted in MongoDB collection
-- `gang_vaults`. Three exports for cross-resource use:
--
--   GetGangVault(gang)         → vault record { balance, lastTick }
--   CreditGangVault(gang, amt) → adds (capped); returns actual added
--   DebitGangVault(gang, amt)  → subtracts; returns true on success
--
-- Originally lived inside racketeering/server.lua. Extracted so the
-- vault keeps working after the racketeering/protection feature was
-- removed (atlas_mgmt's gang menu + charterer NPC + archetype upgrade
-- charges still depend on these exports).

local Atlas  = exports['atlas_core']:GetCoreObject()
local config = GangVault.Config

local Vaults = {}    -- in-memory cache: [gangName] = { balance, lastTick }

local function nowEpochMs() return os.time() * 1000 end

local function ensureVault(gang)
    if not Vaults[gang] then
        Vaults[gang] = { balance = 0, lastTick = nowEpochMs() }
    end
    return Vaults[gang]
end

local function addToVault(gang, amount)
    local v = ensureVault(gang)
    local before = v.balance
    v.balance = math.min(v.balance + amount, config.vaultCap)
    return v.balance - before    -- actual amount added (capped)
end

local function persistVault(gang)
    local v = Vaults[gang]
    if not v then return end
    pcall(function()
        local existing = MongoDB.Game.findOne('gang_vaults', { gang = gang })
        local doc = {
            gang     = gang,
            balance  = v.balance,
            lastTick = v.lastTick,
        }
        if existing then
            MongoDB.Game.updateOne('gang_vaults', { gang = gang }, { ['$set'] = doc })
        else
            MongoDB.Game.insertOne('gang_vaults', doc)
        end
    end)
end

-- Bootstrap: pull every saved vault into memory on resource start. The
-- cache is the source of truth at runtime; persistVault writes it back.
CreateThread(function()
    while not MongoDB or not MongoDB.Game do Wait(250) end

    pcall(function()
        local rows = MongoDB.Game.findMany('gang_vaults',
            { _id = { ['$exists'] = true } }) or {}
        local now = nowEpochMs()
        for _, r in ipairs(rows) do
            Vaults[r.gang] = {
                balance  = r.balance or 0,
                lastTick = r.lastTick or now,
            }
        end
    end)

    print(('^2[atlas_crimelife.gangvault]^7 loaded %d gang vaults'):format(
        (function() local n = 0 for _ in pairs(Vaults) do n = n + 1 end return n end)()
    ))
end)

-- ─── Cross-resource exports ──────────────────────────────────────

exports('GetGangVault', function(gang)
    return Vaults[gang]
end)

-- atlas_mgmt's gang founding system charges archetype upgrades + turf
-- + HQ relocations directly from the gang vault. Returns true if the
-- vault had the funds and the debit succeeded.
exports('DebitGangVault', function(gang, amount)
    if type(gang) ~= 'string' or type(amount) ~= 'number' or amount <= 0 then
        return false
    end
    local v = Vaults[gang]
    if not v or v.balance < amount then return false end
    v.balance = v.balance - amount
    persistVault(gang)
    return true
end)

-- Symmetrical write — atlas_mgmt /gangdeposit, charterer NPC deposits,
-- and any future gang-tier income hook can drop money into a vault.
-- Caps at vaultCap; returns the actual amount accepted (post-cap).
exports('CreditGangVault', function(gang, amount)
    if type(gang) ~= 'string' or type(amount) ~= 'number' or amount <= 0 then
        return 0
    end
    local actual = addToVault(gang, amount)
    if actual > 0 then persistVault(gang) end
    return actual
end)
