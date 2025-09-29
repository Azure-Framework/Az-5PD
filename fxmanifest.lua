fx_version 'cerulean'
games { 'gta5' }

author 'Azure-FivePD'
version '1.6'
lua54 'yes'

ui_page 'ui/index.html'

files {
    -- UI
    'ui/index.html',
    'ui/styles.css',
    'ui/*.js',
    'ui/images/*',
    'ui/fonts/*',

    -- callouts
    'callouts/manifest.json',
    'callouts/*.callout'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
        'server.lua'
}

client_scripts {
    'source/client.lua',
    'client.lua',
    'source/traffic_manager.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'source/server.lua',
    'server.lua'
}

-- ensure these resources are present before starting this resource
dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql'
}
