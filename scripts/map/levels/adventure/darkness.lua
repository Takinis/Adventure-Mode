GLOBAL.setfenv(1, GLOBAL)

AddAdventureLevel({
	id = "DARKNESS",
	name = "DARKNESS",
	location = "forest",
	version = 4,
	overrides = {
		branching = "never",
		task_set = "DARKNESS",
		wanderingtrader_enabled = "none",
		start_location = "NightmareStart",
		has_ocean = false,
		specialevent = "none",

		day = "onlynight",
		season_start = "autumn",
		season = "onlysummer",
		weather = "often",
		boons = "always",
		roads = "never",
		berrybush = "never",
		spiders = "often",
		fireflies = "always",
		start_node = "BGGrass",
		maxwelllight_area = "always",
		bearger = "never",
		dragonfly = "never",
		goosemoose = "never",
		stageplays = "never",
		junkyard = "never",
		balatro = "never",
		terrariumchest = "never",

		portalresurection      = "none",
		ghostenabled           = "always",
		ghostsanitydrain       = "always",
		basicresource_regrowth = "none",
		spawnmode              = "fixed",
		resettime              = "default",
	},
	substitutes = MergeMaps(
		{ ["pighouse"] = { perstory = 1, weight = 1, pertask = 1 } },
		AdventureModeGetRandomSubstituteList(ADVENTURE_MODE_SUBS_1, 3)
	),
})
