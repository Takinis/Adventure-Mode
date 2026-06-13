local modimport = modimport

local modules = {
    "toolutil",
    "constants",
    "assets",
    "tuning",
    "RPC",
    "commands",
    "recipes",
    "postinit"
}

for i = 1, #modules do
    modimport("main/" .. modules[i])
end