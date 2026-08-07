GLOBAL.setfenv(1, GLOBAL)

local _WorldResetFromSim = WorldResetFromSim

local function IsAdventureWorldReset()
    local adventure = ShardGameIndex ~= nil and ShardGameIndex.adventure or nil
    return TheWorld ~= nil and TheWorld.ismastersim and TheWorld.is_adventure and
        adventure ~= nil and (adventure:IsActive() or adventure._return_pending)
end

if type(_WorldResetFromSim) == "function" then
    function WorldResetFromSim(...)
        if IsAdventureWorldReset() then
            local completed = false
            local queued = ShardGameIndex.adventure:ReturnFromShard("worldreset", function(success)
                completed = true
                if not success then
                    print("[Adventure Mode] Unable to return to the main world after a world reset request.")
                end
            end)
            if not queued and not completed then
                print("[Adventure Mode] Unable to start the return to the main world after a world reset request.")
            end
            return
        end

        return _WorldResetFromSim(...)
    end
end
