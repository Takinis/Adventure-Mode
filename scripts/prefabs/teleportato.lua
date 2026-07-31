local assets = {
	Asset("ANIM", "anim/teleportato.zip"),
	Asset("ANIM", "anim/teleportato_build.zip"),
	Asset("ANIM", "anim/teleportato_adventure_build.zip"),
	Asset("ANIM", "anim/teleportato_adventure_parts_build.zip"),
}

local prefabs = {
	"ash",
	"teleportato_player_container",
}

local function ApplyPoweredPresentation(inst)
	if inst._poweredup:value() then
		inst.AnimState:PlayAnimation("power_on", false)
		inst.AnimState:PushAnimation("idle_on", true)
		inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_powerup", "teleportato_on")
		inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_idle_LP", "teleportato_idle")
	end
end

local function OnActivate(inst, doer)
	local activated = inst.components.teleportatoassembly:Activate(doer)
	if activated then
		inst.components.teleportatotravel:UpdateActivationAvailability()
	end
	return activated
end

local function OnActivated(inst, doer)
	inst.components.teleportatostore:Open(doer)
end

local function GetStatus(inst)
	return inst.components.teleportatoassembly:GetStatus()
end

local function ItemTradeTest(inst, item)
	return inst.components.teleportatoassembly:CanAccept(item)
end

local function OnItemAccepted(inst, giver, item)
	inst.components.teleportatoassembly:AddPart(item)
end

local function OnContainerChanged(inst)
	inst.components.teleportatotravel:UpdateActivationAvailability()
end

local function OnLoad(inst, data)
	inst.components.teleportatoassembly:LoadLegacyData(data)
	inst.components.teleportatostore:LoadLegacyData(data)
end

local function fn()
	local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
	inst.entity:AddMiniMapEntity()
	inst.entity:AddNetwork()

	inst.AnimState:SetBank("teleporter")
	inst.AnimState:SetBuild("teleportato_adventure_build")
	inst.AnimState:PlayAnimation("idle_off", true)

	inst:AddTag("teleportato")
	inst:AddTag("trader")
	inst._poweredup = net_bool(inst.GUID, "teleportato._poweredup", "teleportatopowerdirty")

	MakeObstaclePhysics(inst, 1.1)
	inst.MiniMapEntity:SetIcon("teleportato.png")
	inst.MiniMapEntity:SetPriority(1)
	inst.entity:SetPristine()

	if not TheWorld.ismastersim then
		inst:ListenForEvent("teleportatopowerdirty", ApplyPoweredPresentation)
		inst:DoTaskInTime(0, ApplyPoweredPresentation)
		return inst
	end

	inst:AddComponent("inspectable")
	inst.components.inspectable.getstatus = GetStatus
	inst.components.inspectable:RecordViews()

	inst:AddComponent("activatable")
	inst.components.activatable.OnActivate = OnActivate
	inst.components.activatable.inactive = false
	inst.components.activatable.quickaction = true

	inst:AddComponent("trader")
	inst.components.trader:SetAcceptTest(ItemTradeTest)
	inst.components.trader.onaccept = OnItemAccepted

	inst:AddComponent("teleportatoassembly")
	inst.components.teleportatoassembly:SetOnActivatedFn(OnActivated)
	inst.components.teleportatoassembly:RefreshPartSymbols()

	inst:AddComponent("teleportatostore")
	inst.components.teleportatostore:SetOnContainerChangedFn(OnContainerChanged)

	inst:AddComponent("teleportatotravel")

	inst.Adventure = function(inst, doer)
		return inst.components.teleportatotravel:Transition(doer)
	end
	inst.SetPlayerActivation = function(inst, doer, active)
		return inst.components.teleportatotravel:SetPlayerActivation(doer, active)
	end
	inst.CheckNextLevelSure = function(inst, doer)
		return inst.components.teleportatotravel:RequestConfirmation(doer)
	end
	inst.OnLoad = OnLoad

	return inst
end

return Prefab("teleportato_base", fn, assets, prefabs)
