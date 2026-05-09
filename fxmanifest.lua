fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'atlas_crimelife'
description 'Illegal-life mechanics for Atlas: Shadow Market logistics, chop shops, parking-meter theft, copper scrap, VIN scratching, vehicle cloning. Each module is a self-contained subfolder.'
author 'Citgo'
version '0.1.0'

-- Shared layer (loaded into both client + server contexts).
shared_scripts {
    'config.lua',
    'shared/streetcred.lua',
    'shared/perms.lua',
}

-- Each module loads independently. Adding a new module = a new
-- subfolder + 2 lines below (one client, one server).
client_scripts {
    'shadowmarket/config.lua',
    'shadowmarket/client.lua',
    'chopshop/config.lua',
    'chopshop/client.lua',
    'vinscratch/config.lua',
    'vinscratch/client.lua',
    'cloning/config.lua',
    'cloning/client.lua',
    'parkingmeters/config.lua',
    'parkingmeters/client.lua',
    'copperscrap/config.lua',
    'copperscrap/client.lua',
}

server_scripts {
    '@atlas_mongodb/mongodb.lua',
    -- gangvault: standalone primitive used by atlas_mgmt + future
    -- gang-tier income features. Loads first so other modules can
    -- call its exports if needed.
    'gangvault/config.lua',
    'gangvault/server.lua',
    'shadowmarket/config.lua',
    'shadowmarket/server.lua',
    'chopshop/config.lua',
    'chopshop/server.lua',
    -- vinscratch BEFORE cloning so cloning can call exports['atlas_crimelife']:MarkScratched
    'vinscratch/config.lua',
    'vinscratch/server.lua',
    'cloning/config.lua',
    'cloning/server.lua',
    -- parkingmeters BEFORE copperscrap so it can call exports['atlas_crimelife']:BumpHeat
    'parkingmeters/config.lua',
    'parkingmeters/server.lua',
    'copperscrap/config.lua',
    'copperscrap/server.lua',
    'server/cascade.lua',
}
