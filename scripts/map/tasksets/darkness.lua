local EASTER_EGG_CHANCE = 0.01
local marble_forest_easter_egg = false

AddTaskPreInit("Chessworld", function()
	marble_forest_easter_egg = math.random() < EASTER_EGG_CHANCE
end)

AddRoomPreInit("MarbleForest", function(room)
	if marble_forest_easter_egg then
		local distributeprefabs = room.contents.distributeprefabs
		local marbletree_weight = distributeprefabs.marbletree
		local clockwork_weight = distributeprefabs.knight + distributeprefabs.bishop

		distributeprefabs.marbletree = nil
		distributeprefabs.knight = distributeprefabs.knight + marbletree_weight * distributeprefabs.knight / clockwork_weight
		distributeprefabs.bishop = distributeprefabs.bishop + marbletree_weight * distributeprefabs.bishop / clockwork_weight
		distributeprefabs.rook = nil
	end
end)

AddTaskSet("DARKNESS", {
	tasks = {
		"Swamp start",
		"Battlefield",
		"Walled Kill the spiders",
		"Sanity-Blocked Spider Queendom",
	},
	numoptionaltasks = 2,
	optionaltasks = {
		"Killer bees!",
		"Tentacle-Blocked The Deep Forest",
		"Tentacle-Blocked Spider Swamp",
		"Trapped Forest hunters",
		"Waspy The hunters",
		"Hounded Magic meadow",
		"Chessworld",
	},
	set_pieces = {
		["RuinedBase"] = { tasks = {
			"Swamp start",
			"Battlefield",
			"Walled Kill the spiders",
			"Killer bees!",
		} },
		["ResurrectionStoneLit"] = { count = 4, tasks = {
			"Swamp start",
			"Battlefield",
			"Walled Kill the spiders",
			"Sanity-Blocked Spider Queendom",
			"Killer bees!",
			"Chessworld",
			"Tentacle-Blocked The Deep Forest",
			"Tentacle-Blocked Spider Swamp",
			"Trapped Forest hunters",
			"Waspy The hunters",
			"Hounded Magic meadow",
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
		"spawnpoint_master",
		"teleportato_ring",
		"teleportato_box",
		"teleportato_crank",
		"teleportato_potato",
		"teleportato_base",
		"chester_eyebone",
	},
})
