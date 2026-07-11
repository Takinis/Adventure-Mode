local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

local ColourCube = require("components/colourcube")

function ColourCube:AddSeasonColourCube(season_colourcubes)
    local OnSeasonTick = self.inst:GetEventCallbacks("seasontick", nil, "scripts/components/colourcube.lua")

    local SEASON_COLOURCUBES = nil

    if OnSeasonTick then
        SEASON_COLOURCUBES = ToolUtil.GetUpvalue(OnSeasonTick, "UpdateAmbientCCTable.SEASON_COLOURCUBES")
    end

    if not SEASON_COLOURCUBES then  -- try again
        local OnPlayerActivated = self.inst:GetEventCallbacks("playeractivated", nil, "scripts/components/colourcube.lua")
        if OnPlayerActivated then
            SEASON_COLOURCUBES = ToolUtil.GetUpvalue(OnPlayerActivated, "OnOverrideCCTable.UpdateAmbientCCTable.SEASON_COLOURCUBES")
        end
    end

    if SEASON_COLOURCUBES then
        for season, data in pairs(season_colourcubes) do
            SEASON_COLOURCUBES[season] = data
        end
    end
end

local AD_SEASON_COLOURCUBES = {
    autumn =
    {
        day = resolvefilepath("images/colour_cubes/ad_day05_cc.tex"),
        dusk = resolvefilepath("images/colour_cubes/ad_dusk03_cc.tex"),
        night = resolvefilepath("images/colour_cubes/ad_night03_cc.tex"),
        full_moon = "images/colour_cubes/purple_moon_cc.tex"
    }
}



AddComponentPostInit("colourcube", function(self, inst)
    if TheWorld.is_adventure then
        self:AddSeasonColourCube(AD_SEASON_COLOURCUBES)
        self.adventure_mode = true
    end
end)
