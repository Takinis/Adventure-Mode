local Lock = require("components/lock")

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

local function ClearPendingUnlock(inst)
    inst._unlock_pending = nil
    inst._pending_key = nil
    inst._unlocker_userid = nil
    inst.throne = nil
end

local function SendUnlockPrompt(inst, throne, doer)
    local character = throne.isMaxwell and "waxwell" or throne.puppet._puppet_character:value()
    SendModRPCToClient(GetClientModRPC("AdventureMode", "UnlockMaxwell"), doer.userid, inst.GUID, character)
end

local function RequestUnlock(lock, key, doer)
    local inst = lock.inst
    if not lock:IsLocked() or
        doer == nil or doer.userid == nil or doer.userid == "" or
        key == nil or not key:IsValid() or key.components.key == nil or
        key.components.inventoryitem == nil or
        key.components.inventoryitem:GetGrandOwner() ~= doer or
        not lock:CompatableKey(key.components.key.keytype) then
        return
    end

    if inst._unlock_pending then
        local throne = inst.throne ~= nil and inst.throne:IsValid() and inst.throne or nil
        if inst._pending_key == key and inst._unlocker_userid == doer.userid and
            throne ~= nil and not throne._endgame_started then
            SendUnlockPrompt(inst, throne, doer)
        end
        return
    end

    local throne = FindThrone()
    if throne == nil or throne._endgame_started then
        return
    end

    inst.throne = throne
    inst._pending_key = key
    inst._unlocker_userid = doer.userid
    inst._unlock_pending = true
    inst.AnimState:PlayAnimation("idle_empty")

    SendUnlockPrompt(inst, throne, doer)
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
        else
            if key:IsInLimbo() then
                key:ReturnToScene()
            end
            key.Transform:SetPosition(inst.Transform:GetWorldPosition())
        end
    end
end

local function ConfirmUnlock(inst, doer)
    if not inst._unlock_pending then
        return false
    end

    local lock = inst.components.lock
    local key = inst._pending_key
    local throne = inst.throne ~= nil and inst.throne:IsValid() and inst.throne or FindThrone()
    if lock == nil or not lock:IsLocked() or throne == nil or throne._endgame_started or
        key == nil or not key:IsValid() or key.components.key == nil or
        key.components.inventoryitem == nil or
        key.components.inventoryitem:GetGrandOwner() ~= doer or
        not lock:CompatableKey(key.components.key.keytype) then
        ClearPendingUnlock(inst)
        inst.AnimState:PlayAnimation("idle_empty")
        return false
    end

    ClearPendingUnlock(inst)
    Lock.Unlock(lock, key, doer)
    if lock:IsLocked() then
        return false
    end

    inst._unlock_confirmed = true
    throne.lock = inst
    inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_add_divining")
    inst.AnimState:PlayAnimation("idle_full")
    return throne:StartEndGameSequence(doer)
end

local function CancelUnlock(inst, doer)
    if not inst._unlock_pending then
        return false
    end

    ClearPendingUnlock(inst)
    inst.AnimState:PlayAnimation("idle_empty")
    return true
end

local function OnSave(inst, data)
    data.maxwell_unlock_confirmed = inst._unlock_confirmed == true or nil
end

local function OnLoad(inst, data)
    inst._unlock_confirmed = data ~= nil and data.maxwell_unlock_confirmed == true or nil
    ClearPendingUnlock(inst)
end

local function OnLoadPostPass(inst)
    local lock = inst.components.lock
    if lock == nil or lock:IsLocked() then
        inst.AnimState:PlayAnimation("idle_empty")
        return
    end

    if inst._unlock_confirmed then
        local throne = FindThrone()
        if throne ~= nil then
            throne.lock = inst
            inst.AnimState:PlayAnimation("idle_full")
            throne:StartEndGameSequence(nil)
            return
        end
    end

    inst._unlock_confirmed = nil
    ReturnPendingKey(inst, nil)
    inst.AnimState:PlayAnimation("idle_empty")
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
    inst.components.lock:SetOnLockedFn(OnLock)
    inst.components.lock.Unlock = RequestUnlock

    inst.ConfirmUnlock = ConfirmUnlock
    inst.CancelUnlock = CancelUnlock
    inst.OnSave = OnSave
    inst.OnLoad = OnLoad
    inst.OnLoadPostPass = OnLoadPostPass

    return inst
end

return Prefab("maxwelllock", fn, assets, prefabs)
