GLOBAL.setfenv(1, GLOBAL)

is_islandventure_enabled = rawget(_G, "IA_CONFIG") ~= nil
is_porkland_enabled = rawget(_G, "PL_CONFIG") ~= nil