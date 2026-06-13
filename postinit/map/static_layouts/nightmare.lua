local NightmareStart = require "map/static_layouts/nightmare"
GLOBAL.setfenv(1, GLOBAL)

NightmareStart.layers[2].objects[6].type = "spawnpoint_master"