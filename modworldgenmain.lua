local postinit = {
    levels = {
        "forest"
    },
    tasks = {
        "maxwell"
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
modimport("scripts/map/levels/adventure")
modimport("scripts/map/ad_tasksets")
modimport("scripts/map/ad_startlocations")
modimport("scripts/map/levels/adventure_secondary")
modimport("scripts/map/tasksets/adventure_secondary")
modimport("scripts/map/tasks/adventure_secondary")
modimport("scripts/map/adventure_secondary_startlocation")
modimport("scripts/map/adventure_secondary_layout")

-- require("map/ad_layouts")
-- require("map/ad_startlocations")
modimport("postinit/map/forest_map")
modimport("postinit/map/resource_substitution")
modimport("postinit/map/storygen")
