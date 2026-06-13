local SchoolSpawner = require("components/schoolspawner")
local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

AddComponentPostInit("schoolspawner", function(self, inst)
    local _is_adventure_active = ShardGameIndex:IsAdventureActive()
    local OnPlayerJoined = inst:GetEventCallbacks("ms_playerjoined", TheWorld, "scripts/components/schoolspawner.lua")
    local _ScheduleSpawn, scope_fn, i = ToolUtil.GetUpvalue(OnPlayerJoined, "ScheduleSpawn")

    local ScheduleSpawn = function(player)
        if _is_adventure_active then
            return
        end

        _ScheduleSpawn(player)
    end

    debug.setupvalue(scope_fn, i, ScheduleSpawn)
end)