local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

local easing = require("easing")

local RAINY_PRESET_ID = "RAINY"
local RAINY_PLAYER_MOISTURE_MULT = 10

local function GetAdventureState()
    local adventurestate = TheWorld ~= nil and
        TheWorld.net ~= nil and
        TheWorld.net.components ~= nil and
        TheWorld.net.components.adventurestate or nil

    return adventurestate ~= nil and adventurestate:GetState() or nil
end

local function IsRainyAdventure()
    local state = GetAdventureState()
    return state ~= nil and state.current_preset == RAINY_PRESET_ID
end

AddComponentPostInit("moisture", function(self, inst)
    function self:_GetMoistureRateAssumingRain()
        if inst.components.rainimmunity ~= nil then
            return 0
        end

        local waterproofmult =
            (inst.components.sheltered ~= nil and
                inst.components.sheltered.sheltered and
                inst.components.sheltered.waterproofness or 0) +
            (inst.components.inventory ~= nil and
                inst.components.inventory:GetWaterproofness() or 0) +
            (self.inherentWaterproofness or 0) +
            (self.waterproofnessmodifiers:Get() or 0)

        if waterproofmult >= 1 then
            return 0
        end

        local preciprate = math.clamp(TheWorld.state.precipitationrate, 0, 1)
        local rate = easing.inSine(preciprate, self.minMoistureRate, self.maxMoistureRate, 1)

        if rate > 0 and inst:HasTag("player") and IsRainyAdventure() then
            rate = rate * RAINY_PLAYER_MOISTURE_MULT
        end

        return rate * (1 - waterproofmult)
    end
end)
