local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

local RAIN_FX_MULTIPLIER = 2
local RAIN_WETNESS_RATE_MULTIPLIER = 2

AddComponentPostInit("weather", function(self)
    if not TheWorld:IsAdventurePreset("RAINY") then
        return
    end

    local CalculateWetnessRate, scope_fn, index =
        ToolUtil.GetUpvalue(self.OnUpdate, "CalculateWetnessRate")
    if CalculateWetnessRate == nil then
        print("[weather] failed to find CalculateWetnessRate upvalue")
    else
        debug.setupvalue(scope_fn, index, function(temperature, preciprate)
            local rate = CalculateWetnessRate(temperature, preciprate)
            return rate > 0 and rate * RAIN_WETNESS_RATE_MULTIPLIER or rate
        end)
    end

    local hasfx = ToolUtil.GetUpvalue(self.OnUpdate, "_hasfx")
    if not hasfx then
        return
    end

    local rainfx = ToolUtil.GetUpvalue(self.OnUpdate, "_rainfx")
    if rainfx == nil then
        print("[weather] failed to find _rainfx upvalue")
        return
    end

    local OnUpdate = self.OnUpdate
    local LongUpdate = self.LongUpdate
    function self:OnUpdate(dt)
        OnUpdate(self, dt)
        rainfx.particles_per_tick = rainfx.particles_per_tick * RAIN_FX_MULTIPLIER
        rainfx.splashes_per_tick = rainfx.splashes_per_tick * RAIN_FX_MULTIPLIER
    end

    if LongUpdate == OnUpdate then
        self.LongUpdate = self.OnUpdate
    end
end)
