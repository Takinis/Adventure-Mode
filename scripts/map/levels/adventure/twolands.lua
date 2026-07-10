GLOBAL.setfenv(1, GLOBAL)

	AddAdventureLevel({
	id = "TWOLANDS",
	name = STRINGS.UI.SANDBOXMENU.ADVENTURELEVELS[5],
	location = "forest",
	override_level_string = true,
	version = 4,
	min_playlist_position = 3,
	max_playlist_position = 4,
	overrides = {
		task_set = "TWOLANDS",
		is_two_worlds = true,
		day = "longday",
		season = "onlyautumn",
		season_start = "autumn",
		islands = "always",
		roads = "never",
		start_location = "BargainStart",
		has_ocean = false,
		start_node = "Clearing",
		bearger = "never",
		dragonfly = "never",
		goosemoose = "never",

		autumn = "veryshortseason",
		winter = "noseason",
		spring = "noseason",
		summer = "noseason",

		specialevent = "none",
		wanderingtrader_enabled = "none",
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
	override_triggers = {
		["START"] = {
			{ "weather", "never" },
			{ "day", "longday" },
		},
		["Land of Plenty"] = {
			{ "weather", "never" },
			{ "day", "longday" },
		},
		["The other side"] = {
			{ "weather", "often" },
			{ "day", "longdusk" },
		},
	},
})
