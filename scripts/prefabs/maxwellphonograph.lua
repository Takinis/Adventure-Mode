local assets = {
	Asset("ANIM", "anim/phonograph.zip"),
}

local function play(inst)
	inst.AnimState:PlayAnimation("play_loop", true)
   	inst.SoundEmitter:PlaySound(inst.songToPlay, "ragtime")
   	if inst.components.playerprox then
   		inst:RemoveComponent("playerprox")
   	end
   	inst:PushEvent("turnedon")
end

local function stop(inst)
	inst.AnimState:PlayAnimation("idle")
    inst.SoundEmitter:KillSound("ragtime")
    inst.SoundEmitter:PlaySound("dontstarve/music/gramaphone_end")

    inst:PushEvent("turnedoff")
end

local function fn()
    local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
	inst.entity:AddNetwork()

    inst.entity:SetCanSleep(false)

    inst.AnimState:SetBank("phonograph")
    inst.AnimState:SetBuild("phonograph")
    inst.AnimState:PlayAnimation("idle")

    MakeObstaclePhysics(inst, 0.1)

    inst:AddTag("maxwellphonograph")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("machine")
    inst.components.machine.turnonfn = play
    inst.components.machine.turnofffn = stop

    inst.songToPlay = "dontstarve/maxwell/ragtime"

    inst:AddComponent("playerprox")
    inst.components.playerprox:SetDist(600, 615)
    inst.components.playerprox:SetOnPlayerNear(function() inst.components.machine:TurnOn() end)

	return inst
end

return Prefab("maxwellphonograph", fn, assets) 
