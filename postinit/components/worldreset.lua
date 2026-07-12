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

    local adventure_return_pending = false
    debug.setupvalue(OnUpdate, index, function()
        if TheWorld.is_adventure then
            if adventure_return_pending then
                return
            end

            adventure_return_pending = true
            if ShardGameIndex.adventure:ReturnFromShard("death") then
                return
            end
            adventure_return_pending = false
        end

        WorldReset()
    end)
end)
