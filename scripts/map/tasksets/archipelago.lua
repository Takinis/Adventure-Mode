AddTaskSet("IslandHop", {
    -- Tasks must be in the same order as the task list in the map gen screen, otherwise the task set won't show up.
	tasks = {
		"IslandHop_Start",
		"IslandHop_Hounds",
		"IslandHop_Forest",
		"IslandHop_Savanna",
		"IslandHop_Rocky",
		"IslandHop_Merm",
	},
	numoptionaltasks = 0,
	optionaltasks = {},
	set_pieces = {
		["WesUnlock"] = { restrict_to = "background", tasks = {
			"IslandHop_Start",
			"IslandHop_Hounds",
			"IslandHop_Forest",
			"IslandHop_Savanna",
			"IslandHop_Rocky",
			"IslandHop_Merm",
		} },
	},
	-- substitutes = GetRandomSubstituteList(SUBS_1, 3),
	ordered_story_setpieces = {
		"TeleportatoRingLayout",
		"TeleportatoBoxLayout",
		"TeleportatoCrankLayout",
		"TeleportatoPotatoLayout",
		"TeleportatoBaseAdventureLayout",
	},
	-- required_setpieces = {
	-- 	"TeleportatoRingLayout",
	-- 	"TeleportatoBoxLayout",
	-- 	"TeleportatoCrankLayout",
	-- 	"TeleportatoPotatoLayout",
	-- 	"TeleportatoBaseAdventureLayout",
	-- },
	required_prefabs = {
		"teleportato_ring", "teleportato_box", "teleportato_crank",
		"teleportato_potato", "teleportato_base", "chester_eyebone",
	},
})