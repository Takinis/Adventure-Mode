local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("world", function(inst)

    if not TheWorld.ismastersim then
        return
    end

    if inst.components.blockertransversewall == nil then
        inst:AddComponent("blockertransversewall")
    end
end)