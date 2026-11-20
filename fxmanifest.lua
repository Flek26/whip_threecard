fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'whip_threecard'
description 'Casino three card poker on whip: the casino\'s own tables, a dealer who deals, Ante, Play and Pair Plus, money through whip.'
version '0.1.0'
author 'Flek'

shared_script '@whip_core/lib/satellite.lua'
shared_script 'config.lua'
shared_script 'shared/cards.lua'
client_scripts {
    'client/table.lua',
    'client/play.lua',
    'client/editor.lua',
}
server_scripts {
    'server/main.lua',
    'server/round.lua',
}

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependency 'whip_core'
whip_requires '1.0'
