local modimport = modimport
GLOBAL.setfenv(1, GLOBAL)

local prefab_posts = {
    "diviningrod",
    "forest",
    "player",
    "cave_entrance",
    "world",
    "world_network",
    "statuemaxwell",
    "statueharp",
}

local components_posts = {
    "colourcube",
    "worldstate",
    "frograin",
}

local stategraphs_posts = {
    "SGwilson",
}

modimport("postinit/widgets/redux/templates")

modimport("postinit/shardworldindex")
modimport("postinit/shardadventureindex")
modimport("postinit/shardsaveindex")
modimport("postinit/shardindex")

modimport("postinit/entityscript")
modimport("postinit/frontend")
modimport("postinit/sim")
modimport("postinit/scenarios/camera_maxwellthrone")

for _, file_name in ipairs(prefab_posts) do
    modimport("postinit/prefabs/" .. file_name)
end

for _, file_name in ipairs(components_posts) do
    modimport("postinit/components/" .. file_name)
end

for _, file_name in ipairs(stategraphs_posts) do
    modimport("postinit/stategraphs/" .. file_name)
end
