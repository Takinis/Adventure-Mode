local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

AddPrefabPostInit("cave_entrance", function(inst)
    if not TheWorld.ismastersim then
        return
    end

end)
