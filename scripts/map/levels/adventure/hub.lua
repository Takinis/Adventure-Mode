GLOBAL.setfenv(1, GLOBAL)

AddAdventureLevel({
	id = "HUB",
	name = "HUB",
	location = "forest",
	version = 4,
	overrides = {
		task_set = "HUB",
		start_location = "PreSummerStart",
		has_ocean = false,
		wanderingtrader_enabled = "none",

		day = "longdusk",
		-- start_node = "Clearing",
		season = "preonlysummer",
		season_start = "winter",
		spiders = "often",
		branching = "default",
		loop = "never",
		bearger = "never",
		dragonfly = "never",
		goosemoose = "never",
		deerclops = "never",

		junkyard = "never",
		balatro = "never",
		terrariumchest = "never",

		portalresurection      = "none",
		ghostenabled           = "always",
		ghostsanitydrain       = "always",
		basicresource_regrowth = "always",
		spawnmode              = "fixed",
		resettime              = "default",
	},
	substitutes = AdventureModeGetRandomSubstituteList(ADVENTURE_MODE_SUBS_1, 3),
})
