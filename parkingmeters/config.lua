-- atlas_crimelife / parkingmeters — config (data only).
-- Loaded both client and server. Module #1 of the Phase 4 entry-crime
-- tier: zero-asset, foot-only, teaches map navigation + tool flow.

ParkingMeters = ParkingMeters or {}

ParkingMeters.Config = {
    -- World-prop models we attach atlas_target options to. Anything in
    -- these lists triggers the radial. Parking meters are concentrated
    -- in business districts; phone boxes are scattered everywhere.
    targetModels = {
        'prop_parknmeter_01',
        'prop_parknmeter_02',
        'prop_phonebox_01a',
        'prop_phonebox_01b',
        'prop_phonebox_02',
        'prop_phonebox_03',
        'prop_phonebox_04',
    },

    -- Tools the player can use. Each defines its own duration, payout
    -- band, heat impact, and (optional) Street Cred rank gate.
    --
    -- crowbar: loud, fast XP but raises heat
    -- master_key: silent, 3x payout, gated on Distributor (rank 5+)
    tools = {
        crowbar = {
            item       = 'weapon_crowbar',
            -- Require the crowbar to be the player's CURRENTLY DRAWN
            -- weapon, not just present in inventory. Cleaner UX than
            -- "Smash" appearing whenever you happen to be carrying one.
            requireEquipped = true,
            label      = 'Smash with crowbar',
            icon       = 'fas fa-hammer',
            iconColor  = '#ef4444',
            durationMs = 4000,
            payoutMin  = 8,
            payoutMax  = 25,
            heatGain   = 30,
            -- Standing hammering scenario — repeated downward strike + pull
            -- cadence reads as repeatedly leveraging a tool against the
            -- meter. flag=49 (LOOP|UPPERBODY|ENABLE_PLAYER_CONTROL) keeps
            -- the crowbar in the right hand while the upper-body override
            -- drives the strike motion. Replaces a takedown stab clip
            -- that didn't loop and looked stiff.
            anim       = { dict = 'amb@world_human_hammering@male@idle_a', clip = 'idle_b', flag = 49 },
            soundOnHit = true,    -- play a clang
        },
        master_key = {
            item       = 'master_key',
            label      = 'Pick the lock',
            icon       = 'fas fa-key',
            iconColor  = '#facc15',
            durationMs = 4000,
            payoutMin  = 24,
            payoutMax  = 75,
            heatGain   = 0,
            -- Gated by Street Cred rank (Distributor = rank 5).
            rankMin    = 5,
            -- mp_common_heist exists but `tap_screen` is not a real clip in
            -- it. The canonical "fiddling with a parking-meter" idle is
            -- amb@prop_human_parking_meter@male@idle_a / idle_a — Rockstar's
            -- own scenario animation for this exact prop family.
            anim       = { dict = 'amb@prop_human_parking_meter@male@idle_a', clip = 'idle_a', flag = 49 },
            soundOnHit = false,
        },
    },

    -- After a smash, the same prop pays $0 for this long. Keeps players
    -- moving instead of farming a single corner.
    perPropCooldownSec = 30 * 60,    -- 30 min

    -- Between-action throttle so a player can't spam back-to-back hits.
    perPlayerCooldownSec = 8,

    -- Crime XP per successful smash. Small — entry-tier.
    crimeXp = 2,

    -- Heat zones. Each smash in a zone adds the tool's heatGain. Heat
    -- linearly decays to 0 over heatDecayMs. While heat >= heatHighThreshold,
    -- atlas_crimelife emits `atlas_crimelife:heat:rise` events that future
    -- atlas_dispatch can subscribe to for cop spawns / NPC tip-offs.
    heatHighThreshold = 60,
    heatDecayMs       = 20 * 60 * 1000,   -- 20 min full decay
    zones = {
        { id = 'downtown',    center = vec3(195.0, -940.0, 30.0),    radius = 350.0, label = 'Downtown' },
        { id = 'vinewood',    center = vec3(280.0, 180.0, 90.0),     radius = 350.0, label = 'Vinewood' },
        { id = 'rockford',    center = vec3(-700.0, -500.0, 30.0),   radius = 400.0, label = 'Rockford Hills' },
        { id = 'mission',     center = vec3(40.0, -1500.0, 30.0),    radius = 400.0, label = 'Mission Row' },
        { id = 'davis',       center = vec3(80.0, -1900.0, 22.0),    radius = 400.0, label = 'Davis' },
        { id = 'strawberry',  center = vec3(160.0, -1700.0, 30.0),   radius = 350.0, label = 'Strawberry' },
        { id = 'mirror_park', center = vec3(1100.0, -650.0, 60.0),   radius = 300.0, label = 'Mirror Park' },
        { id = 'lameaza',     center = vec3(820.0, -1100.0, 25.0),   radius = 350.0, label = 'La Mesa' },
    },
}
