local ThisMeansWarStart = require "map/static_layouts/thismeanswar_start"
GLOBAL.setfenv(1, GLOBAL)

ThisMeansWarStart.layers[2].objects[1].type = "spawnpoint_master"
