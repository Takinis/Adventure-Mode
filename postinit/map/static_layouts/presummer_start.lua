local PreSummerStart = require "map/static_layouts/presummer_start"
GLOBAL.setfenv(1, GLOBAL)

print("PreSummerStart : " .. tostring(PreSummerStart.layers[2].objects[2].type))

PreSummerStart.layers[2].objects[2].type = "spawnpoint_master"