GLOBAL.setfenv(1, GLOBAL)

AddAdventureLevel({
	id = "RAINY",
	name = "RAINY",
	location = "forest",
	version = 4,
	overrides = {
		task_set = "RAINY",
		start_location = "WinterStartEasy",
		wanderingtrader_enabled = "none",

		world_size = "default",
		day = "longdusk",
		weather = "squall",
		weather_start = "wet",
		frograin = "often",

		start_node = "Forest",
		season = "autumn",
		season_start = "autumn",
		deerclops = "never",
		bearger = "never",
		dragonfly = "never",
		goosemoose = "never",
		hounds = "never",
		mactusk = "always",
		leifs = "always",
		trees = "often",
		carrot = "default",
		berrybush = "never",

		stageplays = "never",

		portalresurection      = "none",
		ghostenabled           = "always",
		ghostsanitydrain       = "always",
		basicresource_regrowth = "always",
		spawnmode              = "fixed",
		resettime              = "default",
	},
	substitutes = AdventureModeGetRandomSubstituteList(ADVENTURE_MODE_SUBS_1, 3),
})
