GLOBAL.setfenv(1, GLOBAL)

AddAdventureLevel({
	id = "ENDING",
	name = "ENDING",
	location = "forest",
	nomaxwell = true,
	version = 4,
	overrides = {
		task_set = "ENDING",
		wanderingtrader_enabled = "none",
		start_location = "MaxHome",
	
		day = "onlynight",
		season = "onlysummer",
		weather = "never",
		creepyeyes = "always",
		waves = "off",
		boons = "never",
		bearger = "never",
		dragonfly = "never",
		goosemoose = "never",
		hounds = "never",
	},
	hideminimap = true,
	teleportaction = "restart",
	teleportmaxwell = "ADVENTURE_6_TELEPORTFAIL",
	override_triggers = {
		["MaxHome"] = {
			{ "areaambient", "VOID" },
		},
	},
})
