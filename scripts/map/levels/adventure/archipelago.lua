GLOBAL.setfenv(1, GLOBAL)

-- ============================================================
-- ISLANDHOP — Archipelago
-- ============================================================
AddAdventureLevel({
	id = "ISLANDHOP",
	name = STRINGS.UI.SANDBOXMENU.ADVENTURELEVELS[4],
	location = "forest",
	version = 4,
	min_playlist_position = 1,
	max_playlist_position = 4,
	overrides = {
		world_size = "medium",
		task_set = "IslandHop",
		start_location = "ThisMeansWarStart",
		has_ocean = false,
		wanderingtrader_enabled = "none",
		specialevent = "none",

		day        = "default",
		islands    = "always",
		roads      = "never",
		weather    = "default",

		season_start = "autumn",
		autumn       = "default",
		winter       = "default",
		spring       = "noseason",
		summer       = "noseason",
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

		prefabswaps_start = "classic",
		petrification = "none",
		portalresurection      = "none",
		ghostenabled           = "always",
		ghostsanitydrain       = "always",
		basicresource_regrowth = "none",
		spawnmode              = "fixed",
		resettime              = "default",
	},
	substitutes = AdventureModeGetRandomSubstituteList(ADVENTURE_MODE_SUBS_1, 3),
})
