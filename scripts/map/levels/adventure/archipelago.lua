GLOBAL.setfenv(1, GLOBAL)

-- ============================================================
-- ISLANDHOP — Archipelago
-- ============================================================
AddAdventureLevel({
	id = "ISLANDHOP",
	name = "ISLANDHOP",
	location = "forest",
	version = 4,
	overrides = {
		world_size = "medium",
		task_set = "IslandHop",
		start_location = "ThisMeansWarStart",
		has_ocean = false,
		wanderingtrader_enabled = "none",

		day        = "default",
		islands    = "always",
		roads      = "never",
		weather    = "default",

		season_start = "autumn",
		autumn       = "shortseason",
		winter       = "shortseason",
		spring       = "shortseason",
		summer       = "shortseason",
		is_archipelago = true,

		bearger    = "never",
		dragonfly  = "never",
		goosemoose = "never",
		deerclops  = "default",
		hounds     = "default",
		stageplays = "never",
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
