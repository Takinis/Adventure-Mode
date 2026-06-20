local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("world", function(inst)

    if not TheWorld.ismastersim then
        return
    end

    if inst.components.blockertransversewall == nil then
        inst:AddComponent("blockertransversewall")
    end

    if inst.components.adventuremanager == nil then
        inst:AddComponent("adventuremanager")
        inst:DoTaskInTime(0, function(inst)
            if inst.components.adventuremanager ~= nil then
                inst.components.adventuremanager:WatchExistingPlayers()
            end
        end)
    end
end)
