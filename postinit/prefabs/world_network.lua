local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

local function fn(inst)
    if inst.components.adventure == nil then
        inst:AddComponent("adventure")
    end
end

AddPrefabPostInit("forest_network", fn)
AddPrefabPostInit("cave_network", fn)
