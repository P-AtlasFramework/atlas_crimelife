-- atlas_crimelife / shadowmarket — config (data only).
-- Loaded both client and server.

ShadowMarket = ShadowMarket or {}

ShadowMarket.Config = {
    -- Per-player cooldown between mule runs (seconds).
    cooldown = 5 * 60,

    -- Item names from atlas_inv. The mule carries a contraband package
    -- on pickup; the dropoff consumes it and pays out markedbills.
    package = 'contraband_smallpkg',
    payoutItem = 'markedbills',

    -- Payout: random in [min,max] — markedbills item count.
    -- Crime XP: flat amount per successful run.
    payout = {
        markedbills = { min = 800,  max = 1500 },
        crimeXp     = 12,                          -- ~9 runs to rank 1, ~42 to Distributor
    },

    -- Distance a drop ped must be from the pickup ped, in meters. The
    -- selected drop ped is sampled from `drops` and validated against
    -- this minimum range so the player has to actually traverse the city.
    minDropDistance = 600.0,

    -- Handler peds — players approach one of these to start a run.
    -- Each entry: vec4(x, y, z, heading), model. Spread them so different
    -- corners of the map become organic "criminal hotspots."
    handlers = {
        { coords = vec4(  -49.84, -1758.10, 29.42, 50.0),  model = 's_m_y_dealer_01' },
        { coords = vec4(  120.16,  -434.40, 41.05, 70.0),  model = 's_m_y_dealer_01' },
        { coords = vec4( -610.79, -1644.76, 26.11,  0.0),  model = 'a_m_m_hillbilly_01' },
        { coords = vec4(  476.86, -1818.50, 27.42,180.0),  model = 'a_m_y_business_01' },
    },

    -- Drop pool — the server picks one at random per run, filtered by
    -- minDropDistance from the originating handler. Spread across the map.
    drops = {
        { coords = vec4(  725.96, -1454.10, 25.55,  0.0),  model = 's_m_y_dealer_01' },
        { coords = vec4(   -75.18,  -310.66,  46.27,  90.0), model = 's_m_y_dealer_01' },
        { coords = vec4(  -1184.50, -1505.46,   4.37, 305.0), model = 'a_m_m_hillbilly_01' },
        { coords = vec4(  1383.07, -1500.18, 56.52,  240.0), model = 'a_m_y_business_01' },
        { coords = vec4(   307.13,  -592.20,  43.28, 165.0), model = 's_m_y_dealer_01' },
        { coords = vec4(  -1577.94, -415.59, 41.13,  207.0), model = 'a_m_y_business_01' },
        { coords = vec4(  -337.60, -2018.03, 26.92,  330.0), model = 'a_m_m_hillbilly_01' },
        { coords = vec4(  1716.18, 4733.15,  41.07,   85.0), model = 's_m_y_dealer_01' },
        { coords = vec4(  -3173.49, 1100.03,  20.83,  175.0), model = 'a_m_y_business_01' },
        { coords = vec4(    23.65, 6624.23,  31.57,  255.0), model = 'a_m_m_hillbilly_01' },
    },
}
