GLOBAL.setfenv(1, GLOBAL)
require("constants")

local StaticLayout = require("map/static_layout")
local AllLayouts = require("map/layouts").Layouts

AllLayouts["MaxHomeStart"] = StaticLayout.Get("map/static_layouts/maxhome_start")

local maxwell_home = AllLayouts["MaxwellHome"]
local adventure_mode_dev = StaticLayout.Get("map/static_layouts/adventure_mode_dev")

-- The 5x5 clearing immediately to the screen-right of MaxwellHome's graveyard.
local DEV_OFFSET_X = -56.5
local DEV_OFFSET_Y = -10.5
local DEV_GROUND_COLUMN = 17
local DEV_GROUND_ROW = 63

for prefab, objects in pairs(adventure_mode_dev.layout) do
    maxwell_home.layout[prefab] = maxwell_home.layout[prefab] or {}
    for _, data in ipairs(objects) do
        data.x = data.x + DEV_OFFSET_X
        data.y = data.y + DEV_OFFSET_Y
        table.insert(maxwell_home.layout[prefab], data)
    end
end

for row, tiles in ipairs(adventure_mode_dev.ground) do
    for column, tile in ipairs(tiles) do
        if tile ~= 0 then
            maxwell_home.ground[DEV_GROUND_ROW + row - 1][DEV_GROUND_COLUMN + column - 1] = tile
        end
    end
end

maxwell_home.force_rotation = LAYOUT_ROTATION.SOUTH
for _, prefabs in pairs(maxwell_home.layout) do
    for _, data in pairs(prefabs) do
        data.y = - data.y
    end
end

local new_ground = {}
for index, tile in pairs(maxwell_home.ground) do
    new_ground[150-index + 1] = tile
end
maxwell_home.ground = new_ground
