local assets = {
	Asset("ANIM", "anim/portal_adventure.zip"),
}

local function GetVerb(inst)
	return STRINGS.ACTIONS.ACTIVATE.GENERIC
end

local function Adventure(inst)
    if inst._adventure_transitioning then
        return false
    end

    inst._adventure_transitioning = true
    for _, player in pairs(AllPlayers) do
        if player.components.health and not player.components.health:IsDead() then
            player.sg:GoToState("teleportato_teleport")
        end
    end
    TheWorld:DoTaskInTime(5, function()
        local function oncomplete(success)
            if not success and inst:IsValid() then
                inst._adventure_transitioning = nil
            end
        end
        if not ShardGameIndex.adventure:Start(nil, oncomplete) and inst:IsValid() then
            inst._adventure_transitioning = nil
        end
    end)
    return true
end

local function DenyVote(doer, message)
    if doer ~= nil and doer.userid ~= nil then
        SendModRPCToClient(GetClientModRPC("AdventureMode", "AdventureVoteDenied"), doer.userid, message)
    end
end

local function RequestAdventureEntry(inst, doer)
    if doer == nil or not doer:IsValid() or doer.userid == nil or doer.userid == "" then
        return false
    end
    if not doer:IsNear(inst, 10) then
        DenyVote(doer, STRINGS.UI.ADVENTUREMODE_VOTE.TOO_FAR)
        return false
    end

    if ShardGameIndex == nil or ShardGameIndex.adventure == nil or
        not ShardGameIndex.adventure:IsMasterShard() then
        DenyVote(doer, STRINGS.UI.ADVENTUREMODE_VOTE.MASTER_ONLY)
        return false
    end
    if ShardGameIndex.adventure:IsActive() then
        DenyVote(doer, STRINGS.UI.ADVENTUREMODE_VOTE.ALREADY_ACTIVE)
        return false
    end
    if inst._adventure_transitioning then
        DenyVote(doer, STRINGS.UI.ADVENTUREMODE_VOTE.ALREADY_ACTIVE)
        return false
    end

    local clients = TheNet:GetClientTable()
    local player_count = TheNet:GetServerIsClientHosted() and #clients or #clients - 1
    if player_count <= 1 then
        return inst:Adventure()
    end

    local worldvoter = TheWorld.net ~= nil and TheWorld.net.components.worldvoter or nil
    if worldvoter == nil then
        DenyVote(doer, STRINGS.UI.ADVENTUREMODE_VOTE.FAILED)
        return false
    end
    if worldvoter:IsVoteActive() then
        DenyVote(doer, STRINGS.UI.ADVENTUREMODE_VOTE.ACTIVE)
        return false
    end

    local pending = TheWorld._adventure_entry_vote
    if pending ~= nil and not pending.started and pending.expires_at >= GetTime() then
        DenyVote(doer, STRINGS.UI.ADVENTUREMODE_VOTE.PENDING)
        return false
    end

    TheWorld._adventure_entry_vote = {
        portal = inst,
        starteruserid = doer.userid,
        expires_at = GetTime() + TUNING.ADVENTURE_ENTRY_VOTE_REQUEST_TIMEOUT,
    }
    SendModRPCToClient(GetClientModRPC("AdventureMode", "StartAdventureVote"), doer.userid)
    return true
end

local function GetBodyText()
    return STRINGS.UI.STARTADVENTURE.BODY_TEST
end

local function OnActivate(inst, doer)
    SendModRPCToClient(GetClientModRPC("AdventureMode", "Adventure???"), doer.userid, inst.GUID,
        ZipAndEncodeString({
            body = GetBodyText(),
            longness = "big",
            style = "dark_wide",
        }))
    inst.components.activatable.inactive = true
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
    inst.RequestAdventureEntry = RequestAdventureEntry
    
    return inst
end

return Prefab("adventure_portal", fn, assets) 
