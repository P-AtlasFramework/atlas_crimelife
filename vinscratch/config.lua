-- atlas_crimelife / vinscratch — config (data only).
-- Loaded both client and server.

VinScratch = VinScratch or {}

VinScratch.Config = {
    -- The item that triggers the scrub. Single-use; consumed on success.
    item = 'vin_kit',

    -- How long the scrub progress bar runs.
    scrubDurationMs = 12000,    -- 12s

    -- Maximum distance from the vehicle when starting the scrub. Player
    -- has to be standing right next to the car (not in it).
    maxDistance = 3.0,

    -- Crime XP awarded for a successful scrub.
    crimeXp = 8,

    -- Mechanic-style anim played during the scrub.
    anim = {
        dict = 'mini@repair',
        clip = 'fixing_a_ped',
        flag = 49,
    },

    -- When chopping a scratched plate, the chop shop pays this multiplier
    -- on top of the normal parts roll. 1.5 = 50% bonus parts. Implemented
    -- as a re-roll: each parts row rolls TWICE on a scratched plate.
    chopBonusMultiplier = 1.5,
}
