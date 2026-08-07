local AddComponentPostInit = AddComponentPostInit
GLOBAL.setfenv(1, GLOBAL)

AddComponentPostInit("worldreset", function(self)
    if not TheWorld.ismastershard then
        return
    end

    -- Keep the vanilla countdown and replace only its terminal action.
    local WorldReset, OnUpdate, index = ToolUtil.GetUpvalue(self.OnUpdate, "WorldReset")
    if WorldReset == nil then
        return
    end

    debug.setupvalue(OnUpdate, index, function()
        if TheWorld.is_adventure then
            WorldResetFromSim()
            return
        end

        WorldReset()
    end)
end)
