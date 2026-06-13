local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("cave_entrance", function(inst)
    if not TheWorld.ismastersim then
        return
    end

    if ShardGameIndex:IsAdventureActive() then
        inst:DoTaskInTime(0, function(inst)
            inst:Remove()
        end)
    end

end)