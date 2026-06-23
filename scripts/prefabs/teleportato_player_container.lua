local containers = require("containers")

local container_config = deepcopy(containers.params.teleportato_player_container)

local function OnAnyOpen(inst, data)
	local opener = data ~= nil and data.doer or nil
	if opener ~= nil then
		inst.Network:SetClassifiedTarget(opener)
	end

	if inst._closecheck_task == nil then
		inst._closecheck_task = inst:DoPeriodicTask(0.5, inst.CheckTeleportatoDistance)
	end
end

local function OnAnyClose(inst)
	inst.Network:SetClassifiedTarget(inst)
	if inst.components.container == nil or not inst.components.container:IsOpen() then
		if inst._closecheck_task ~= nil then
			inst._closecheck_task:Cancel()
			inst._closecheck_task = nil
		end
	end
end

local function CheckTeleportatoDistance(inst)
	local base = inst._base
	local container = inst.components.container
	if container == nil then
		return
	end
	if base == nil or not base:IsValid() then
		container:Close()
		return
	end

	for opener in pairs(container.openlist) do
		if opener == nil or not opener:IsValid() or not opener:IsNear(base, 5) then
			container:Close(opener)
		end
	end
end

local function OnSave(inst, data)
	data.userid = inst._userid
end

local function fn()
	local inst = CreateEntity()

	if TheWorld.ismastersim then
		inst.entity:AddTransform()
	end
	inst.entity:AddNetwork()
	inst.entity:AddServerNonSleepable()
	inst.entity:SetCanSleep(false)
	inst.entity:Hide()

	inst:AddTag("CLASSIFIED")
	inst:AddTag("irreplaceable")
	inst:AddTag("teleportato_player_container")

	inst._teleportato_base = net_entity(inst.GUID, "teleportato_player_container._teleportato_base")

	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		return inst
	end

	inst.persists = false
	inst.Network:SetClassifiedTarget(inst)

	inst:AddComponent("container")
	inst.components.container:WidgetSetup("teleportato_player_container", container_config)
	inst.components.container.canbeopened = true
	inst.components.container.skipclosesnd = true
	inst.components.container.skipopensnd = true
	inst.components.container.skipautoclose = true
	inst.components.container.onanyopenfn = OnAnyOpen
	inst.components.container.onanyclosefn = OnAnyClose

	inst.CheckTeleportatoDistance = CheckTeleportatoDistance
	inst.OnSave = OnSave

	return inst
end

return Prefab("teleportato_player_container", fn)
