GLOBAL.setfenv(1, GLOBAL)
require("constants")

local StaticLayout = require("map/static_layout")
local AllLayouts = require("map/layouts").Layouts

AllLayouts["MaxHomeStart"] = StaticLayout.Get("map/static_layouts/maxhome_start")

AllLayouts["MaxwellHome"].force_rotation = LAYOUT_ROTATION.SOUTH
for prefab_type, prefabs in pairs(AllLayouts["MaxwellHome"].layout) do
    for prefab, data in pairs(prefabs) do
        data.y = - data.y
    end
end

local new_ground = {}
for index, tile in pairs(AllLayouts["MaxwellHome"].ground) do
    new_ground[150-index + 1] = tile
end
AllLayouts["MaxwellHome"].ground = new_ground