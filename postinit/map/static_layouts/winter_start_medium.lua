local WinterStartMedium = require "map/static_layouts/winter_start_medium"
GLOBAL.setfenv(1, GLOBAL)

package.loaded["map/static_layouts/winter_start_medium"] = nil
local raw = require("map/static_layouts/winter_start_medium")

for _, layer in ipairs(raw.layers) do
    if layer.type == "objectgroup" and layer.name == "FG_OBJECTS" then
        for _, obj in ipairs(layer.objects) do
            if obj.type == "spawnpoint" then
                obj.type = "spawnpoint_master"
            end
        end
    end
end

package.loaded["map/layouts"] = nil