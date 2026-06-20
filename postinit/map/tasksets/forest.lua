local AddTaskSetPreInit = AddTaskSetPreInit
GLOBAL.setfenv(1, GLOBAL)

AddTaskSetPreInit("default", function(self)
    table.insert(self.required_prefabs, "adventure_portal")
end)