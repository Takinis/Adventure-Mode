local modimport = modimport

local modules = {
    "toolutil",
    "worldsettings_overrides",
    "strings",
    "constants",
    "assets",
    "tuning",
    "containers",
    "RPC",
    "commands",
    "recipes",
    "postinit"
}

for i = 1, #modules do
    modimport("main/" .. modules[i])
end