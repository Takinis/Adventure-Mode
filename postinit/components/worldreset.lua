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

            local adventure = ShardGameIndex ~= nil and ShardGameIndex.adventure or nil
            if adventure == nil then
                print("[Adventure Mode] Unable to return to the original world after everyone died.")
                return
            end

            adventure_return_pending = true
            local completed = false
            local queued = adventure:ReturnFromShard("death", function(success)
                completed = true
                if not success then
                    adventure_return_pending = false
                    print("[Adventure Mode] Unable to return to the original world after everyone died.")
                end
            end)
            if not queued and not completed then
                adventure_return_pending = false
                print("[Adventure Mode] Unable to start returning to the original world after everyone died.")
            end
            return
        end

        WorldReset()
    end)
end)
