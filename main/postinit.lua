local modimport = modimport
GLOBAL.setfenv(1, GLOBAL)

local prefab_posts = {
    "teleportato_container",
    "diviningrod",
    "forest",
    "player",
    "cave_entrance",
}

local components_posts = {
    "worldstate",
    "frograin",
    "sharkboimanager",
    "wavemanager",
    "birdspawner",
    "schoolspawner",
}

modimport("postinit/shardindex")
modimport("postinit/entityscript")
modimport("postinit/frontend")
modimport("postinit/sim")

for _, file_name in ipairs(prefab_posts) do
    modimport("postinit/prefabs/" .. file_name)
end

for _, file_name in ipairs(components_posts) do
    modimport("postinit/components/" .. file_name)
end
