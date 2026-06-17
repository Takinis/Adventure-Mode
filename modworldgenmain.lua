modimport("main/toolutil")

local postinit = {
    levels = {
        "forest"
    },
    tasksets = {
        "forest",
    },
    static_layouts = {
        "thismeanswar_start",
        "presummer_start",
        "nightmare",
        "winter_start_easy",
        "winter_start_medium",
        "bargain_start",
        "maxwellhome",
    },
}

for k, v in pairs(postinit) do
    for i = 1, #v do
        modimport("postinit/map/" .. k .. "/" .. postinit[k][i])
    end
end

modimport("scripts/map/ad_layouts")
modimport("scripts/map/ad_tasksets")
modimport("scripts/map/ad_locations")
modimport("scripts/map/levels/adventure")
modimport("scripts/map/ad_startlocations")

modimport("scripts/map/tasks/maxwell")

-- require("map/ad_layouts")
-- require("map/ad_startlocations")
modimport("postinit/map/forest_map")
