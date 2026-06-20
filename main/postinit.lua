local modimport = modimport
GLOBAL.setfenv(1, GLOBAL)

local prefab_posts = {
    "diviningrod",
    "forest",
    "player",
    "cave_entrance",
    "world",
}

local components_posts = {
    "colourcube",
    "worldstate",
    "frograin",
    "sharkboimanager",
    "wavemanager",
    "birdspawner",
    "schoolspawner",
}

local stategraphs_posts = {
    "SGwilson",
}

modimport("postinit/widgets/redux/templates")
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

for _, file_name in ipairs(stategraphs_posts) do
    modimport("postinit/stategraphs/" .. file_name)
end
