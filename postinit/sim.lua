GLOBAL.setfenv(1, GLOBAL)

local _WorldResetFromSim = WorldResetFromSim

local function IsAdventureWorldReset()
    local adventure = ShardGameIndex ~= nil and ShardGameIndex.adventure or nil
    return TheWorld ~= nil and TheWorld.ismastersim and TheWorld.is_adventure == true and
        adventure ~= nil and (adventure:IsActive() or adventure._return_pending or adventure._reset_pending)
end

local function RestartCurrentSlot()
    if ShardGameIndex ~= nil and ShardGameIndex.worldindex ~= nil then
        ShardGameIndex.worldindex:RestartCurrentSlotAfterShardRPC()
    end
end

if type(_WorldResetFromSim) == "function" then
    function WorldResetFromSim(...)
        if IsAdventureWorldReset() then
            local queued = ShardGameIndex.adventure:ResetCurrentChapterShard({ reason = "worldreset" }, function(success)
                if not success then
                    print("[Adventure Mode] Unable to reset the current adventure chapter.")
                end
            end)
            if not queued and ShardGameIndex.adventure._return_pending then
                ShardGameIndex.adventure:ReturnFromShard("worldreset", function(success)
                    if not success then
                        RestartCurrentSlot()
                    end
                end)
            elseif not queued then
                print("[Adventure Mode] Unable to queue the current adventure chapter reset.")
                RestartCurrentSlot()
            end
            return
        end

        return _WorldResetFromSim(...)
    end
end
