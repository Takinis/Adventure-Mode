local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

local TEST_SPAWN_TIMES = { min = 0, max = 0.1 }
local TEST_MAX_FROGS = math.max(TUNING.FROG_RAIN_LOCAL_MAX_ADVENTURE, 40)
local FROGRAIN_SOURCE = "scripts/components/frograin.lua"

local function StartAdventureFrogRainTest(self)
    if not ShardGameIndex:IsAdventureActive() then
        return
    end

    TheWorld:PushEvent("ms_setseason", "spring")
    TheWorld:PushEvent("ms_forceprecipitation", true)
    self:SetSpawnTimes(TEST_SPAWN_TIMES)
    self:SetMaxFrogs(TEST_MAX_FROGS)
end

local function GetFrogRainWatchFn(self, inst, var)
    return TheWorld.components.worldstate:GetWorldStateWatchFn(var, inst, self, FROGRAIN_SOURCE, function(fn)
        local ok, localfrogs = pcall(ToolUtil.GetUpvalue, fn, "_localfrogs")
        return ok and localfrogs ~= nil
    end)
end

AddComponentPostInit("frograin", function(self, inst)
    local _OnIsRaining = GetFrogRainWatchFn(self, inst, "israining")
    local ToggleUpdate = ToolUtil.GetUpvalue(self.SetSpawnTimes, "ToggleUpdate")
    local _localfrogs = ToolUtil.GetUpvalue(_OnIsRaining, "_localfrogs")

    local function OnIsRaining(world, israining)
        if ShardGameIndex:IsAdventureActive() then
            self:SetMaxFrogs(math.random(TUNING.FROG_RAIN_LOCAL_MIN_ADVENTURE, TUNING.FROG_RAIN_LOCAL_MAX_ADVENTURE))
        elseif israining and (math.random() < TUNING.FROG_RAIN_CHANCE) then
            self:SetMaxFrogs(math.random(_localfrogs.min, _localfrogs.max))
        else
            self:SetMaxFrogs(0)
        end
        ToggleUpdate()
    end

    inst:StopWatchingWorldState("israining", _OnIsRaining)
    inst:WatchWorldState("israining", OnIsRaining)

    function self:StartFrogRain()
        StartAdventureFrogRainTest(self)
    end
end)
