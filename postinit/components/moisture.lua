local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

local RAIN_MOISTURE_RATE_MULTIPLIER = 2

AddComponentPostInit("moisture", function(self, inst)
    if not inst:HasTag("player") or not TheWorld:IsAdventurePreset("RAINY") then
        return
    end

    local _GetMoistureRateAssumingRain = self._GetMoistureRateAssumingRain
    function self:_GetMoistureRateAssumingRain()
        return _GetMoistureRateAssumingRain(self) * RAIN_MOISTURE_RATE_MULTIPLIER
    end
end)
