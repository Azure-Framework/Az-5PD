fx_version 'cerulean'
games { 'gta5' }
author 'Azure(TheStoicBear)'
description 'Az-5PD'
version '1.0'
lua54 'yes'

ui_page 'ui/index.html'
files { 'ui/index.html' }

shared_script '@ox_lib/init.lua'

client_scripts {
    'source/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'source/server.lua'
}

-- ensure these resources are present before starting this resource
dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql',
    'Az-Framework'
}
