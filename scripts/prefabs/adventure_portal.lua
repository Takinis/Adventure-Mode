local BigPopupDialogScreen = require "screens/bigpopupdialog"

local assets = {
	Asset("ANIM", "anim/portal_adventure.zip"),
}

local function GetVerb(inst)
	return STRINGS.ACTIONS.ACTIVATE.GENERIC
end

local function Adventure(inst)
    local allplayers_nearby = true
    local dist_sq = 30 * 30
    for k, v in pairs(AllPlayers) do
        if not v:IsNear(inst, 10) then
            allplayers_nearby = false
            break
        end
    end

    if allplayers_nearby then
        for k, v in pairs(AllPlayers) do
            if v.components.health and not v.components.health:IsDead() then
                v.sg:GoToState("teleportato_teleport")
            end
        end
        TheWorld:DoTaskInTime(5, function() StartShardAdventure({ level_sequence = ShardGameIndex:BuildAdventurePlaylist() } ) end)
    end
end

local function OnActivate(inst, doer)
    SendModRPCToClient(GetClientModRPC("AdventureMode", "Adventure???"), doer.userid, inst)
    return true
end

local OnNearPlayer = function(inst)
    inst.AnimState:PushAnimation("activate", false)
    inst.AnimState:PushAnimation("idle_loop_on", true)
    inst.SoundEmitter:PlaySound("dontstarve/common/maxwellportal_activate")
    inst.SoundEmitter:PlaySound("dontstarve/common/maxwellportal_idle", "idle")

    inst:DoTaskInTime(1, function()
        if inst.ragtime_playing == nil then
            inst.ragtime_playing = true
            inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/ragtime", "ragtime")
        else
            inst.SoundEmitter:SetVolume("ragtime", 1)
        end
    end)
end

local OnFarPlayers = function(inst)
    inst.AnimState:PushAnimation("deactivate", false)
    inst.AnimState:PushAnimation("idle_off", true)
    inst.SoundEmitter:KillSound("idle")
    inst.SoundEmitter:PlaySound("dontstarve/common/maxwellportal_shutdown")

    inst:DoTaskInTime(1, function()
        inst.SoundEmitter:SetVolume("ragtime", 0)
    end)
end

local function fn()
	local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()
    inst.entity:AddMiniMapEntity()

    MakeObstaclePhysics(inst, 1)

    inst.MiniMapEntity:SetIcon("portal.png")
   
    inst.AnimState:SetBank("portal_adventure")
    inst.AnimState:SetBuild("portal_adventure")
    inst.AnimState:PlayAnimation("idle_off", true)

    inst.GetActivateVerb = GetVerb

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")
	inst.components.inspectable:RecordViews()

	inst:AddComponent("playerprox")
	inst.components.playerprox:SetDist(4,5)
    inst.components.playerprox:SetOnPlayerNear(OnNearPlayer)
    inst.components.playerprox:SetOnPlayerFar(OnFarPlayers)

	inst:AddComponent("activatable")
    inst.components.activatable.OnActivate = OnActivate
    inst.components.activatable.inactive = true
    -- inst.components.activatable.getverb = GetVerb
	inst.components.activatable.quickaction = true

    inst.Adventure = Adventure
    
    return inst
end

return Prefab("adventure_portal", fn, assets) 
