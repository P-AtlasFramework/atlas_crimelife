-- atlas_crimelife / cloning — config (data only).
-- Loaded both client and server.

Cloning = Cloning or {}

Cloning.Config = {
    item = 'vin_cloner',

    cloneDurationMs = 18000,    -- 18s

    maxDistance = 3.0,

    crimeXp = 15,

    -- Min/max plate length. GTA plates are 1-8 chars (alphanumeric +
    -- spaces) — we enforce that on the server.
    plateMinLen = 1,
    plateMaxLen = 8,

    -- Mechanic-style anim during the clone.
    anim = {
        dict = 'mini@repair',
        clip = 'fixing_a_ped',
        flag = 49,
    },

    -- A successful clone also flags the new plate as scratched (it's a
    -- fresh / untraceable identity by definition). Set to false to keep
    -- the two systems independent.
    autoScratchOnClone = true,

    -- After cloning, the player gets a vehicle key on the new plate so
    -- they can drive it without hotwiring. Disable if you'd rather they
    -- still need to break in.
    grantKeyOnClone = true,
}
