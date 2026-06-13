local FrogRain = require("components/frograin")
local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

AddComponentPostInit("components/frograin", function(self, inst)
    local _OnIsRaining = TheWorld.components.worldstate:GetWatchWorldStateFns("israining", inst)
    local ToggleUpdate = ToolUtil.GetUpvalue(self.SetSpawnTimes, "ToggleUpdate")
    local _localfrogs = ToolUtil.GetUpvalue(_OnIsRaining, "_localfrogs")
    local _frogcap

    local OnIsRaining = function(world, israining)
        if ShardGameIndex:IsAdventureActive() then
            _frogcap = math.random(TUNING.FROG_RAIN_LOCAL_MIN_ADVENTURE, TUNING.FROG_RAIN_LOCAL_MAX_ADVENTURE)
        elseif israining and (math.random() < TUNING.FROG_RAIN_CHANCE) then -- only add fromgs to some rains
            _frogcap = math.random(_localfrogs.min, _localfrogs.max)
        else
            _frogcap = 0
        end
        self:SetMaxFrogs(_frogcap)
        ToggleUpdate()
    end

    inst:StopWatchingWorldState("israining", _OnIsRaining)
    inst:WatchingWorldState("israining", OnIsRaining)
end)