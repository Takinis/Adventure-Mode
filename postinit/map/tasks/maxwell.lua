AddTaskPreInit("MaxHome", function(task)
    task.locks = { LOCKS.NONE }
    task.keys_given = { KEYS.NONE }
    task.room_choices = {
        MaxHome = 1,
    }
    task.room_bg = WORLD_TILES.IMPASSABLE
    task.background_room = "BGImpassable"
    task.colour = { r = .05, g = .05, b = .05, a = 1 }
end)
