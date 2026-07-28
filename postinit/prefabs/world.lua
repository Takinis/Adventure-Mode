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

    if TheWorld.is_adventure and TheWorld.ismastershard and inst.components.maxwellintrospawner == nil then
        inst:AddComponent("maxwellintrospawner")
    end
end)
