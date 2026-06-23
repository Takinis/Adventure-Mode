local assets = {
	Asset("ANIM", "anim/diviningrod.zip"),
    Asset("SOUND", "sound/common.fsb"),
    Asset("ANIM", "anim/diviningrod_maxwell.zip")
}

local prefabs = {
    "diviningrodstart",
}

local function FindThrone()
    local throne = TheSim:FindFirstEntityWithTag("maxwellthrone")
    return throne ~= nil and throne:IsValid() and throne or nil
end

local function OnUnlock(inst, key, doer)
    local throne = FindThrone()
    if throne == nil or throne.StartEndGameSequence == nil then
        if inst.components.lock ~= nil then
            inst.components.lock:Lock(doer)
        end
        return
    end

    inst.throne = throne
    throne.lock = inst
    inst._pending_key = key
    inst._unlocker_userid = doer ~= nil and doer.userid or nil

    if doer ~= nil and doer.userid ~= nil then
        inst._unlock_pending = true
        inst.AnimState:PlayAnimation("idle_empty")
        SendModRPCToClient(GetClientModRPC("AdventureMode", "UnlockMaxwell"), doer.userid, inst.GUID)
    else
        inst.AnimState:PlayAnimation("idle_full")
        inst._pending_key = nil
        throne:StartEndGameSequence(doer)
    end
end

local function OnLock(inst, doer)
    inst.AnimState:PlayAnimation("idle_empty")
end

local function ReturnPendingKey(inst, doer)
    local lock = inst.components.lock
    local key = lock ~= nil and lock.key or nil
    key = key ~= nil and key or inst._pending_key

    if lock ~= nil then
        lock.islocked = true
        if lock.onlocked ~= nil then
            lock.onlocked(inst, doer)
        end
        lock:SetKey(nil)
    end

    if key ~= nil and key:IsValid() then
        if key.components.key ~= nil then
            key.components.key:OnRemoved(inst, doer)
        end

        if doer ~= nil and doer.components.inventory ~= nil then
            doer.components.inventory:GiveItem(key, nil, inst:GetPosition())
        elseif key:IsInLimbo() then
            key:ReturnToScene()
            key.Transform:SetPosition(inst.Transform:GetWorldPosition())
        end
    end
end

local function ConfirmUnlock(inst, doer)
    if not inst._unlock_pending then
        return false
    end

    local throne = inst.throne ~= nil and inst.throne:IsValid() and inst.throne or FindThrone()
    if throne == nil or throne.StartEndGameSequence == nil then
        inst._unlock_pending = nil
        inst._unlocker_userid = nil
        inst.throne = nil
        ReturnPendingKey(inst, doer)
        inst._pending_key = nil
        return false
    end

    inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_add_divining")
    inst.AnimState:PlayAnimation("idle_full")
    inst._unlock_pending = nil
    inst._pending_key = nil
    inst._unlocker_userid = nil
    return throne:StartEndGameSequence(doer)
end

local function CancelUnlock(inst, doer)
    if not inst._unlock_pending then
        return false
    end

    inst._unlock_pending = nil
    inst._unlocker_userid = nil
    inst.throne = nil
    ReturnPendingKey(inst, doer)
    inst._pending_key = nil
    inst.AnimState:PlayAnimation("idle_empty")
    inst:PushEvent("notfree")
    return true
end

local function fn()
	local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
	inst.entity:AddNetwork()

    inst.AnimState:SetBank("diviningrod")
    inst.AnimState:SetBuild("diviningrod_maxwell")
    inst.AnimState:PlayAnimation("activate_loop", true)

    inst:AddTag("maxwelllock")

    MakeInventoryPhysics(inst)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("lock")
    inst.components.lock.locktype = "maxwell"
    inst.components.lock:SetOnUnlockedFn(OnUnlock)
    inst.components.lock:SetOnLockedFn(OnLock)

    inst.ConfirmUnlock = ConfirmUnlock
    inst.CancelUnlock = CancelUnlock

    return inst
end

return Prefab("maxwelllock", fn, assets, prefabs)
