-- atlas_crimelife / shared config.
--
-- Tier thresholds for Street Cred (atlas_core's PlayerData.crime.xp).
-- AddCrimeXp(±N) is the single mutator; we just READ here. 100 XP/rank
-- by default in atlas_core.config (CrimeXpPerRank).
--
-- Tiers are derived from rank (rank = floor(xp / 100)). To unlock the
-- next tier, the player needs that many ranks.

Config = Config or {}

Config.Tiers = {
    -- name        rankMin   description
    { id = 'mule',        rankMin = 0,  label = 'Street Mule',
      desc = 'Foot/bike couriers moving small contraband packages.' },
    { id = 'distributor', rankMin = 5,  label = 'Distributor',
      desc = 'Dead drops, secure storage, larger payloads.' },
    { id = 'kingpin',     rankMin = 25, label = 'Kingpin',
      desc = 'Freight contracts and crew-defended cargo events.' },
}

-- Look up a player's current tier by their crime rank. Used by every
-- module to gate which content tier the player has access to.
function GetCrimeTier(rank)
    rank = rank or 0
    local current = Config.Tiers[1]
    for _, t in ipairs(Config.Tiers) do
        if rank >= t.rankMin then current = t else break end
    end
    return current
end

-- Convenience for tier comparisons (e.g. "is this player at least a Distributor?").
function HasCrimeTier(rank, tierId)
    for _, t in ipairs(Config.Tiers) do
        if t.id == tierId then return (rank or 0) >= t.rankMin end
    end
    return false
end
