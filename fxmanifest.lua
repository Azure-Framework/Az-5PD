fx_version 'cerulean'
games { 'gta5' }

author 'Azure'
version '2.0'

ui_page 'ui/index.html'

files {

    'ui/index.html',
    'ui/styles.css',
    'ui/*.js',
    'ui/images/*',
    'ui/fonts/*',

    'callouts/manifest.json',
    'callouts/*.callout'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'names.lua',
    'shared/sim_config.lua',
}

client_scripts {

    'source/client.lua',
    'client.lua',
    'source/traffic_manager.lua',
    'source/service.lua',
    'source/randomevents.lua',
    'client/sim_tools.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'source/server.lua',
    'server.lua',
    'server/sim_core.lua'
}

dependencies {
    'Az-Framework',
    'ox_lib',
    'ox_target',
    'oxmysql'
}
