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

local function SourceMatches(source, query)
    return query == nil
        or source == query
        or (type(source) == "string" and source:find(query, 1, true) ~= nil)
end

local function FindFrogRainWatchFn(self, inst, var)
    local worldstate = TheWorld ~= nil and TheWorld.components ~= nil and TheWorld.components.worldstate or nil
    if worldstate ~= nil and worldstate.FindWorldStateWatchFn ~= nil then
        local fn = worldstate:FindWorldStateWatchFn(var, inst, self, FROGRAIN_SOURCE)
        if fn ~= nil then
            return fn
        end
    end

    local watcherfns = inst.worldstatewatching ~= nil and inst.worldstatewatching[var] or nil
    if watcherfns == nil then
        return nil
    end

    for _, fn in ipairs(watcherfns) do
        if type(fn) == "function" then
            local info = debug.getinfo(fn, "S")
            if info ~= nil and SourceMatches(info.source, FROGRAIN_SOURCE) then
                return fn
            end

            local ok, localfrogs = pcall(ToolUtil.GetUpvalue, fn, "_localfrogs")
            if ok and localfrogs ~= nil then
                return fn
            end
        end
    end

    return nil
end

AddComponentPostInit("frograin", function(self, inst)
    local _OnIsRaining = FindFrogRainWatchFn(self, inst, "israining")
    if _OnIsRaining == nil then
        print("[frograin] failed to find original worldstate israining watcher")
        return
    end

    local ToggleUpdate = ToolUtil.GetUpvalue(self.SetSpawnTimes, "ToggleUpdate")
    if ToggleUpdate == nil then
        print("[frograin] failed to find ToggleUpdate upvalue")
        return
    end

    local _localfrogs = ToolUtil.GetUpvalue(_OnIsRaining, "_localfrogs")
    if _localfrogs == nil then
        print("[frograin] failed to find _localfrogs upvalue")
        return
    end

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
