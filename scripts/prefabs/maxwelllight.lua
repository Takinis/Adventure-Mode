local assets = {
	Asset("ANIM", "anim/maxwell_torch.zip"),
}

local prefabs =
{
    "maxwelllight_flame",
}

local function changelevels(inst, order)
    for i=1, #order do
        inst.components.burnable:SetFXLevel(order[i])
        Sleep(0.05)
    end
end

local function light(inst)    
    inst.task = inst:StartThread(function() changelevels(inst, inst.lightorder) end)    
end

local function extinguish(inst)
    local throne = TheSim:FindFirstEntityWithTag("maxwellthrone")
    if throne ~= nil and throne:IsValid() and throne._endgame_started then
        return
    end

    if inst.components.burnable:IsBurning() then
        inst.components.burnable:Extinguish()
    end
end

local function fn()
	local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()
    inst.entity:AddMiniMapEntity()

    inst.MiniMapEntity:SetIcon("maxwelltorch.tex")

    inst.AnimState:SetBank("maxwell_torch")
    inst.AnimState:SetBuild("maxwell_torch")
    inst.AnimState:PlayAnimation("idle",false)
  
    inst:AddTag("structure")

    MakeObstaclePhysics(inst, .1)    

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("burnable")
    inst.components.burnable:AddBurnFX("maxwelllight_flame", Vector3(0,0,0), "fire_marker")
    inst.components.burnable:SetOnIgniteFn(light)

    inst:AddComponent("inspectable")
    return inst
end

local function arealight()
    local inst = fn()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.lightorder = {5,6,7,8,7}
    inst:AddComponent("playerprox")
    inst.components.playerprox:SetDist(17, 27 )
    inst.components.playerprox:SetOnPlayerNear(function() if not inst.components.burnable:IsBurning() then inst.components.burnable:Ignite() end end)
    inst.components.playerprox:SetOnPlayerFar(extinguish)
    inst:AddComponent("named")
    inst.components.named:SetName(STRINGS.NAMES["MAXWELLLIGHT"])
    inst.components.inspectable.nameoverride = "maxwelllight"

    return inst
end

local function spotlight()
    local inst = fn()

    if not TheWorld.ismastersim then
        return inst
    end

    inst.lightorder = {1,2,3,4,3} 
    return inst
end

return Prefab( "common/objects/maxwelllight", spotlight, assets, prefabs),
Prefab("common/objects/maxwelllight_area", arealight, assets, prefabs) 
