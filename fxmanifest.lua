fx_version 'cerulean'
game 'gta5'

name 'rc_chat'
description 'Royal City chat — full replacement for the default chat resource with badge-styled commands, moderation and an in-game settings panel'
author 'sudo-umair'
version '1.0.0'

lua54 'yes'

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'shared/strings.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'bridge/server.lua',
    'server/main.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

provide 'chat'
