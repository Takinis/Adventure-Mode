local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

local RAIN_PARTICLE_MULT = 8
local RAIN_SPLASH_MULT = 4
local RAINY_PEAK_PRECIPITATION_RATE = 1
local RAINY_WORLD_WETNESS_MULT = 10
local RAINY_MAX_RAIN_INTERVAL = 60
local RAINY_RAIN_MOISTURE_SPAN = 7200
local RAINY_RAIN_START_PROGRESS = 0.5

AddComponentPostInit("weather", function(self)
    local OnUpdate = self.OnUpdate
    local rainfx = ToolUtil.GetUpvalue(OnUpdate, "_rainfx")
    local moisture = ToolUtil.GetUpvalue(OnUpdate, "_moisture")
    local moistureceil = ToolUtil.GetUpvalue(OnUpdate, "_moistureceil")
    local moisturefloor = ToolUtil.GetUpvalue(OnUpdate, "_moisturefloor")
    local moisturerate = ToolUtil.GetUpvalue(OnUpdate, "_moisturerate")
    local preciptype = ToolUtil.GetUpvalue(OnUpdate, "_preciptype")
    local precipmode = ToolUtil.GetUpvalue(OnUpdate, "_precipmode")
    local peakprecipitationrate = ToolUtil.GetUpvalue(OnUpdate, "_peakprecipitationrate")
    local wetness = ToolUtil.GetUpvalue(OnUpdate, "_wetness")
    local wet = ToolUtil.GetUpvalue(OnUpdate, "_wet")
    local PRECIP_TYPES = ToolUtil.GetUpvalue(OnUpdate, "PRECIP_TYPES")
    local PRECIP_MODES = ToolUtil.GetUpvalue(OnUpdate, "PRECIP_MODES")
    local CalculatePrecipitationRate = ToolUtil.GetUpvalue(OnUpdate, "CalculatePrecipitationRate")
    local rain_extended = false

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

        local rate = moisturerate ~= nil and math.max(moisturerate:value(), 0) or 0
        local intervaldelta = math.max(rate * RAINY_MAX_RAIN_INTERVAL, 1)
        local nextceil = math.max(moisturefloor:value() + 1, moisture:value() + intervaldelta)
        if moistureceil:value() > nextceil then
            moistureceil:set(nextceil)
        end
    end

    local function ForceHeavyWorldRain()
        if TheWorld.ismastersim and
            peakprecipitationrate ~= nil and
            preciptype ~= nil and
            PRECIP_TYPES ~= nil and
            preciptype:value() == PRECIP_TYPES.rain then
            peakprecipitationrate:set(RAINY_PEAK_PRECIPITATION_RATE)
        end
    end

    local function ExtendCurrentRain()
        if not TheWorld.ismastersim or
            rain_extended or
            moisture == nil or
            moistureceil == nil or
            moisturefloor == nil or
            preciptype == nil or
            PRECIP_TYPES == nil or
            preciptype:value() ~= PRECIP_TYPES.rain then
            return
        end

        local floor = moisturefloor:value()
        local ceil = math.max(moistureceil:value(), floor + RAINY_RAIN_MOISTURE_SPAN)
        moistureceil:set(ceil)
        moisture:set(floor + (ceil - floor) * RAINY_RAIN_START_PROGRESS)
        rain_extended = true
    end

    local function AccelerateWorldWetness(dt)
        if not TheWorld.ismastersim or
            wetness == nil or
            wet == nil or
            preciptype == nil or
            PRECIP_TYPES == nil or
            CalculatePrecipitationRate == nil or
            preciptype:value() ~= PRECIP_TYPES.rain then
            return
        end

        local preciprate = CalculatePrecipitationRate()
        if preciprate > 0 then
            local extra = preciprate * 0.75 * (RAINY_WORLD_WETNESS_MULT - 1) * dt
            wetness:set(math.clamp(wetness:value() + extra, 0, TUNING.MAX_WETNESS))
            if wetness:value() > TUNING.MOISTURE_WET_THRESHOLD then
                wet:set(true)
            end
        end
    end

    function self:OnUpdate(dt)
        local is_rainy = TheWorld:IsAdventureLevel("RAINY")
        if is_rainy then
            ForceDynamicRain()
        end

        OnUpdate(self, dt)

        if is_rainy then
            ExtendCurrentRain()
            ForceHeavyWorldRain()
            AccelerateWorldWetness(dt)
            LimitNextRainDelay()
        elseif rain_extended then
            rain_extended = false
        end

        if is_rainy and
            preciptype ~= nil and
            PRECIP_TYPES ~= nil and
            preciptype:value() ~= PRECIP_TYPES.rain then
            rain_extended = false
        end

        if is_rainy and rainfx ~= nil then
            rainfx.particles_per_tick = rainfx.particles_per_tick * RAIN_PARTICLE_MULT
            rainfx.splashes_per_tick = rainfx.splashes_per_tick * RAIN_SPLASH_MULT
        end
    end

    self.LongUpdate = self.OnUpdate
end)
