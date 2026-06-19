local function AddTaskRoomTag(task, tag)
	task.room_tags = task.room_tags or {}
	if not table.contains(task.room_tags, tag) then
		table.insert(task.room_tags, tag)
	end
end

AddTaskPreInit("Land of Plenty", function(task)
	AddTaskRoomTag(task, "start_island")
end)

AddTaskPreInit("The other side", function(task)
	AddTaskRoomTag(task, "parts_island")
end)

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
