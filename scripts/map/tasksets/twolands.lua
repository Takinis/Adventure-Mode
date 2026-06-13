AddTaskSet("TWOLANDS", {
	tasks = {
		"Land of Plenty",
		"The other side",
	},
	set_pieces = {
		["MaxPigShrine"] = { tasks = { "Land of Plenty" } },
		["MaxMermShrine"] = { tasks = { "The other side" } },
		["ResurrectionStone"] = { count = 2, tasks = {
			"Land of Plenty",
			"The other side",
		} },
	},
	ordered_story_setpieces = {
		"TeleportatoRingLayout",
		"TeleportatoBoxLayout",
		"TeleportatoCrankLayout",
		"TeleportatoPotatoLayout",
		"TeleportatoBaseAdventureLayout",
	},
	required_prefabs = {
		"teleportato_ring",
		"teleportato_box",
		"teleportato_crank",
		"teleportato_potato",
		"teleportato_base",
		"chester_eyebone",
	},
})
