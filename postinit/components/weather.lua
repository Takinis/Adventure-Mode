local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

local RAIN_PARTICLE_MULT = 8
local RAIN_SPLASH_MULT = 4
local NEXT_RAIN_MOISTURE_DELTA = 480

AddComponentPostInit("weather", function(self)
    local OnUpdate = self.OnUpdate
    local rainfx = ToolUtil.GetUpvalue(OnUpdate, "_rainfx")
    local moisture = ToolUtil.GetUpvalue(OnUpdate, "_moisture")
    local moistureceil = ToolUtil.GetUpvalue(OnUpdate, "_moistureceil")
    local moisturefloor = ToolUtil.GetUpvalue(OnUpdate, "_moisturefloor")
    local preciptype = ToolUtil.GetUpvalue(OnUpdate, "_preciptype")
    local precipmode = ToolUtil.GetUpvalue(OnUpdate, "_precipmode")
    local PRECIP_TYPES = ToolUtil.GetUpvalue(OnUpdate, "PRECIP_TYPES")
    local PRECIP_MODES = ToolUtil.GetUpvalue(OnUpdate, "PRECIP_MODES")

    local function ForceDynamicRain()
        if TheWorld.ismastersim and precipmode ~= nil and PRECIP_MODES ~= nil then
            local dynamic = PRECIP_MODES.dynamic
            if dynamic ~= nil and precipmode:value() ~= dynamic then
                precipmode:set(dynamic)
            end
        end
    end

    local function LimitNextRainDelay()
        if not TheWorld.ismastersim or
            moisture == nil or
            moistureceil == nil or
            moisturefloor == nil or
            preciptype == nil or
            PRECIP_TYPES == nil or
            preciptype:value() ~= PRECIP_TYPES.none then
            return
        end

        local nextceil = math.max(moisturefloor:value() + 1, moisture:value() + NEXT_RAIN_MOISTURE_DELTA)
        if moistureceil:value() > nextceil then
            moistureceil:set(nextceil)
        end
    end

    function self:OnUpdate(dt)
        local is_rainy = TheWorld:IsAdventureLevel("RAINY")
        if is_rainy then
            ForceDynamicRain()
        end

        OnUpdate(self, dt)

        if is_rainy then
            LimitNextRainDelay()

            if rainfx ~= nil then
                rainfx.particles_per_tick = rainfx.particles_per_tick * RAIN_PARTICLE_MULT
                rainfx.splashes_per_tick = rainfx.splashes_per_tick * RAIN_SPLASH_MULT
            end
        end
    end

    self.LongUpdate = self.OnUpdate
end)
