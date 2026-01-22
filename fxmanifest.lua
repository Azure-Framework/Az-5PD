fx_version 'cerulean'
games { 'gta5' }

author 'Azure'
version '2.0'
lua54 'yes'

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
}

client_scripts {

    'source/client.lua',
    'client.lua',
    'source/traffic_manager.lua',
    'source/service.lua',
    'source/randomevents.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'source/server.lua',
    'server.lua'
}

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql'
}
