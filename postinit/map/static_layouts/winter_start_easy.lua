local WinterStartEasy = require "map/static_layouts/winter_start_easy"
GLOBAL.setfenv(1, GLOBAL)

package.loaded["map/static_layouts/winter_start_easy"] = nil
local raw = require("map/static_layouts/winter_start_easy")

local function EnsurePortalAndMasterSpawn(rawlayout)
    for _, layer in ipairs(rawlayout.layers) do
        if layer.type == "objectgroup" and layer.name == "FG_OBJECTS" then
            for _, obj in ipairs(layer.objects) do
                if obj.type == "spawnpoint" then
                    obj.type = "spawnpoint_master"
                end
            end
        end
    end
end

EnsurePortalAndMasterSpawn(raw)

package.loaded["map/layouts"] = nil
