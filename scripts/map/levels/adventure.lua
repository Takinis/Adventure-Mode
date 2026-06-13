local ENV = env
local AddLevel = AddLevel
local modimport = modimport
GLOBAL.setfenv(1, GLOBAL)

ADVENTURE_MODE_SUBS_1 = {
	["evergreen"]        = { perstory = 0.5, pertask = 1, weight = 1 },
	["evergreen_short"]  = { perstory = 1, pertask = 1, weight = 1 },
	["evergreen_normal"] = { perstory = 1, pertask = 1, weight = 1 },
	["evergreen_tall"]   = { perstory = 1, pertask = 1, weight = 1 },
	["sapling"]          = { perstory = 0.6, pertask = 0.95, weight = 1 },
	["beefalo"]          = { perstory = 1, pertask = 1, weight = 1 },
	["rabbithole"]       = { perstory = 1, pertask = 1, weight = 1 },
	["rock1"]            = { perstory = 0.3, pertask = 1, weight = 1 },
	["rock2"]            = { perstory = 0.5, pertask = 0.8, weight = 1 },
	["grass"]            = { perstory = 0.5, pertask = 0.9, weight = 1 },
	["flint"]            = { perstory = 0.5, pertask = 1, weight = 1 },
	["spiderden"]        = { perstory = 1, pertask = 1, weight = 1 },
}

function AdventureModeGetRandomSubstituteList(substitutes, num_choices)
	local subs = {}
	local list = {}

	for k, v in pairs(substitutes) do
		list[k] = v.weight
	end

	for i = 1, num_choices do
		local choice = weighted_random_choice(list)
		list[choice] = nil
		subs[choice] = substitutes[choice]
	end

	return subs
end

function AddAdventureLevel(data)
	AddLevel(LEVELTYPE.ADVENTURE, data)
end

ENV.AddAdventureLevel = AddAdventureLevel

modimport("scripts/map/levels/adventure/rainy")
modimport("scripts/map/levels/adventure/winter")
modimport("scripts/map/levels/adventure/hub")
modimport("scripts/map/levels/adventure/archipelago")
modimport("scripts/map/levels/adventure/twolands")
modimport("scripts/map/levels/adventure/darkness")
modimport("scripts/map/levels/adventure/ending")
