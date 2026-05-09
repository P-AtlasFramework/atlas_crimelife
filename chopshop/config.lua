-- atlas_crimelife / chopshop — config (data only).
-- Loaded both client and server.

ChopShop = ChopShop or {}

ChopShop.Config = {
    -- Per-player cooldown between strips. Different from Shadow Market —
    -- chop shop is higher-effort, so the cooldown is per-vehicle (you
    -- can only strip ONE vehicle per cooldown window) AND tracked per
    -- player to prevent farm loops.
    cooldown = 8 * 60,          -- 8 minutes

    -- Strip duration: time the progress bar runs before parts drop.
    stripDurationMs = 30000,    -- 30 seconds

    -- The chop shop zone — drive a stolen vehicle into the marker, then
    -- atlas_target on the vehicle becomes "Strip Vehicle." La Mesa
    -- industrial — fits the "back-alley garage" aesthetic.
    zone = {
        center = vec3(720.84, -1080.05, 22.16),
        radius = 12.0,
        marker = vec3(720.84, -1080.05, 21.16),  -- 1m below center for the floor marker
    },

    -- Parts table: per vehicle class, what parts drop and their drop
    -- weights. Class IDs from GetVehicleClass:
    --   0 Compacts | 1 Sedans | 2 SUVs | 3 Coupes | 4 Muscle
    --   5 Sports Classics | 6 Sports | 7 Super | 8 Motorcycles
    --   9 Off-Road | 10 Industrial | 11 Utility | 12 Vans
    --   13 Cycles | 14 Boats | 15 Helicopters | 16 Planes
    --   17 Service | 18 Emergency | 19 Military | 20 Commercial
    --   21 Trains | 22 Open Wheel
    --
    -- Each entry is { item, min, max, chance }.
    -- chance is a 0-1 probability that this row even fires (rolled per
    -- strip, independently). min/max is the count if it fires.

    -- Basic loot — tier 0+ (anyone). Compacts/sedans/etc.
    basicParts = {
        { item = 'car_door',         min = 1, max = 2, chance = 1.00 },
        { item = 'car_tire',         min = 2, max = 4, chance = 1.00 },
        { item = 'car_battery',      min = 1, max = 1, chance = 0.70 },
        { item = 'car_radiator',     min = 1, max = 1, chance = 0.50 },
        { item = 'car_engine',       min = 1, max = 1, chance = 0.20 },
        { item = 'car_transmission', min = 1, max = 1, chance = 0.15 },
    },

    -- Premium loot — tier requires Distributor (rank 5+). Sports+/super.
    premiumParts = {
        { item = 'car_door',         min = 2, max = 3, chance = 1.00 },
        { item = 'car_tire',         min = 3, max = 4, chance = 1.00 },
        { item = 'car_battery',      min = 1, max = 1, chance = 0.85 },
        { item = 'car_radiator',     min = 1, max = 1, chance = 0.75 },
        { item = 'car_engine',       min = 1, max = 1, chance = 0.55 },
        { item = 'car_transmission', min = 1, max = 1, chance = 0.45 },
        { item = 'car_turbo',        min = 1, max = 1, chance = 0.30 },
        { item = 'car_ecu',          min = 1, max = 1, chance = 0.20 },
    },

    -- Crime XP per successful strip. Higher than mule runs because
    -- chop shop is a longer / more visible action.
    crimeXp = 25,

    -- Markedbills bonus for stripping a player-owned vehicle (extra
    -- incentive to chop OTHER players' stolen cars vs. world NPC traffic).
    playerVehicleBonus = { min = 500, max = 1500 },

    -- Vehicle classes that CANNOT be chopped (refuse at the zone).
    excludedClasses = {
        [13] = true,                -- Cycles
        [14] = true,                -- Boats
        [15] = true,                -- Helicopters
        [16] = true,                -- Planes
        [21] = true,                -- Trains
        [18] = true,                -- Emergency (police vehicles — RP only)
    },

    -- Anim played during the strip (mechanic kneeling).
    stripAnim = {
        dict = 'mini@repair',
        clip = 'fixing_a_ped',
        flag = 49,
    },
}
