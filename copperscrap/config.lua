-- atlas_crimelife / copperscrap — config (data only).
-- Loaded both client and server. Module #2 of the entry-crime tier:
-- introduces the materials economy. Players strip AC units / electrical
-- boxes for copper + scrap, then sell at the scrapyard fence (or save
-- the materials for higher-tier crafting recipes).

CopperScrap = CopperScrap or {}

CopperScrap.Config = {
    -- The wire cutters are required to start the action; consumed only
    -- on a botched skillcheck (small chance of breaking).
    tool = {
        item        = 'wire_cutters',
        breakChance = 0.20,    -- 20% chance to lose the cutters on a failed skillcheck
    },

    -- Two prop categories — different loot weights.
    -- AC units give more copper; electrical boxes give more scrap.
    propGroups = {
        ac = {
            label  = 'Strip AC unit',
            icon   = 'fas fa-fan',
            color  = '#22c55e',
            -- Rooftop / wall-mounted AC props. Rockstar's naming is
            -- `prop_aircon_*` (one word) — the previous list used
            -- `prop_air_con_*` which doesn't exist in the game and silently
            -- failed at CreateObject / ox_target model registration.
            -- Small variants only ship with a/b suffix; large variants are
            -- bare-numbered.
            models = {
                'prop_aircon_l_01', 'prop_aircon_l_02', 'prop_aircon_l_03',
                'prop_aircon_s_01a',
                'prop_aircon_s_02a', 'prop_aircon_s_02b',
                'prop_aircon_s_03a', 'prop_aircon_s_03b',
                'prop_aircon_s_04a',
            },
            loot = {
                { item = 'copper', min = 2, max = 4, chance = 1.00 },
                { item = 'scrap',  min = 0, max = 2, chance = 0.70 },
            },
        },
        elec = {
            label  = 'Strip electrical box',
            icon   = 'fas fa-bolt',
            color  = '#facc15',
            -- Same naming-fix as AC: `prop_elec_box_*` doesn't exist;
            -- Rockstar's actual is `prop_elecbox_*`. The 01-07 family uses
            -- a/b suffixes; 08+ are bare-numbered (with a few CR variants).
            models = {
                'prop_elecbox_01a', 'prop_elecbox_01b',
                'prop_elecbox_02a', 'prop_elecbox_02b',
                'prop_elecbox_03a',
                'prop_elecbox_04a',
                'prop_elecbox_05a',
                'prop_elecbox_06a',
                'prop_elecbox_07a',
                'prop_elecbox_08',
                'prop_elecbox_09',
                'prop_elecbox_11',
                'prop_elecbox_12',
            },
            loot = {
                { item = 'copper', min = 1, max = 2, chance = 1.00 },
                { item = 'scrap',  min = 1, max = 3, chance = 1.00 },
            },
        },
    },

    -- Skillcheck difficulty. SkillCheck(difficulty, inputs) returns bool.
    skillCheck = {
        difficulty = { 'medium', 'medium' },
        inputs     = { 'w', 'a', 's', 'd' },
    },

    -- Shock damage on a failed skillcheck — discourages spam-clicking
    -- and gives the failure some narrative weight.
    shockDamage = 15,

    -- Heat impact (calls into parkingmeters' BumpHeat shared zones).
    heatGainSuccess = 15,
    heatGainFailure = 5,

    -- Per-prop cooldown before it pays out again.
    perPropCooldownSec = 30 * 60,

    -- Per-player throttle.
    perPlayerCooldownSec = 6,

    -- Crime XP per successful strip.
    crimeXp = 4,

    -- Anim while working on the prop. Mechanic-style kneel-and-wrench.
    -- Was previously amb@prop_human_parking_meter@male@idle_a / idle_a,
    -- which is a STANDING parking-meter poke — wrong scenario for cutting
    -- copper out of an AC unit or floor-level electrical box. Matches the
    -- chopshop / vinscratch / cloning anim for visual consistency.
    anim = {
        dict = 'mini@repair',
        clip = 'fixing_a_ped',
        flag = 49,
    },

    -- ─── Scrapyard fence ──────────────────────────────────────────
    -- One NPC at the LS scrapyard who buys copper + scrap for cash.
    -- Players can also save the materials for higher-tier crafting.
    fence = {
        ped     = 's_m_y_dockwork_01',
        coords  = vec4(-460.69, -1721.88, 18.79, 175.0),
        label   = 'Scrap Fence',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        prices = {
            -- Per-unit cash price. These are intentionally low — the
            -- bigger pull is keeping mats for crafting downstream.
            copper = 12,
            scrap  = 8,
        },
        -- Max sell-batch in a single transaction. 40 units of copper +
        -- 40 of scrap per visit caps the grind loop.
        batchMax = 40,
        -- Anti-spam.
        sellCooldownSec = 30,
    },
}
