local function OnPlayerNear(inst)
	for k,v in pairs(inst.components.maxlightspawner.lights) do
		v.components.burnable:Ignite()
	end
end

local function OnPlayerFar(inst)
	for k,v in pairs(inst.components.maxlightspawner.lights) do
		v.components.burnable:Extinguish()
	end
end

local function fn()
	local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:AddNetwork()

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

	inst:AddComponent("playerprox")

	inst:AddComponent("maxlightspawner")

	inst.components.playerprox:SetOnPlayerNear(OnPlayerNear)
	inst.components.playerprox:SetOnPlayerFar(OnPlayerFar)
	inst.components.playerprox:SetDist(6,8)
	inst:DoTaskInTime(0, function() inst.components.maxlightspawner:SpawnAllLights() end)

	return inst
end

local function horizontal()
	local inst = fn()

	return inst
end

local function vertical()
	local inst = fn()

    if not TheWorld.ismastersim then
        return inst
    end

	inst.components.maxlightspawner.angleoffset = 90
	return inst
end

local function quad()
	local inst = fn()

    if not TheWorld.ismastersim then
        return inst
    end

	inst.components.maxlightspawner.angleoffset = 45
	inst.components.maxlightspawner.maxlights = 4
	inst.components.maxlightspawner.radius = 4.2
	return inst
end

return Prefab("horizontal_maxwelllight", horizontal),
    Prefab("vertical_maxwelllight", vertical),
    Prefab("quad_maxwelllight", quad) 
