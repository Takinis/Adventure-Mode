local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("forest_network", function(inst)
    if inst.components.adventurestate == nil then
        inst:AddComponent("adventurestate")
    end
end)

AddPrefabPostInit("cave_network", function(inst)
    if inst.components.adventurestate == nil then
        inst:AddComponent("adventurestate")
    end
end)
