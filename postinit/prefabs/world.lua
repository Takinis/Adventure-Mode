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
    end

    if ShardGameIndex ~= nil and ShardGameIndex.StartAdventureDeathCheck ~= nil then
        inst:DoTaskInTime(0, function()
            ShardGameIndex:StartAdventureDeathCheck(inst)
        end)
    end
end)
