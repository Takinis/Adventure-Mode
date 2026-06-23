local assets =
{
	Asset("ANIM", "anim/maxwell_endgame.zip"),
	Asset("SOUND", "sound/maxwell.fsb"),
}

local prefabs =
{
    "maxwell_smoke",
}

local function createconversationline(line)
    return {
	    voice = "dontstarve/maxwell/talk_LP_world6",
        idleanim= "idle_loop",
        dialogpreanim = "dialog_pre",
        dialoganim="dialog_loop",
        dialogpostanim = "dialog_pst",
        disableplayer = false,
        skippable = false,
        {
            string = line,
            wait = 2, --The time this segment will last for
            waitbetweenlines = 0,
            anim = nil, --If there's a different animation, the animation maxwell will play
            sound = nil, --if there's an extra sound, the sound that will play
        }
    }
end

local SPEECH =
{
    NULL_SPEECH=
    {
	    voice = "dontstarve/maxwell/talk_LP_world6",
        appearanim = "appear",
        idleanim= "idle",
        dialogpreanim = "dialog_pre",
        dialoganim="dial_loop",
        dialogpostanim = "dialog_pst",
        disappearanim = "disappear",
        disableplayer = true,
        skippable = true,
        {
            string = "There is no speech number.", --The string maxwell will say
            wait = 2, --The time this segment will last for
            anim = nil, --If there's a different animation, the animation maxwell will play
            sound = nil, --if there's an extra sound, the sound that will play
        },
        {
            string = nil,
            wait = 0.5,
            anim = "smoke",
            sound = "dontstarve/common/destroy_metal",
        },
        {
            string = "Go set one.",
            wait = 2,
            anim = nil,
            sound = nil,
        },
        {
            string = "Goodbye",
            wait = 1,
            anim = nil,
            sound = "dontstarve/common/destroy_metal",
        },
    },

    INTRO =
    {
	    voice = "dontstarve/maxwell/talk_LP_world6",
        --appearanim = "appear",
        idleanim= "idle_loop",
        dialogpreanim = "dialog_pre",
        dialoganim="dialog_loop",
        dialogpostanim = "dialog_pst",
        --disappearanim = "disappear",
        disableplayer = false,
        skippable = false,
        {
            string = STRINGS.MAXWELL_ADVENTURETHRONE.LEVEL_6.INTRO.ONE,
            wait = 3,
            waitbetweenlines = 0,
            anim = nil,
            sound = nil,
        },
    },

    HIT =
    {
	    voice = "dontstarve/maxwell/talk_LP_world6",
        --appearanim = "appear",
        idleanim= "idle_loop",
        dialogpreanim = "dialog_pre",
        dialoganim="dialog_loop",
        dialogpostanim = "dialog_pst",
        --disappearanim = "disappear",
        disableplayer = false,
        skippable = false,
        {
            string = STRINGS.MAXWELL_ADVENTURETHRONE.LEVEL_6.HIT.ONE,
            wait = 3,
            waitbetweenlines = 0,
            anim = nil,
            sound = nil,
        },
    },

    NOUNLOCK =
    {
	    voice = "dontstarve/maxwell/talk_LP_world6",
        idleanim= "idle_loop",
        dialogpreanim = "dialog_pre",
        dialoganim="dialog_loop",
        dialogpostanim = "dialog_pst",
        disableplayer = false,
        skippable = false,
        {
            string = STRINGS.MAXWELL_ADVENTURETHRONE.LEVEL_6.NOUNLOCK.ONE,
            wait = 3,
            waitbetweenlines = 0,
            anim = nil,
            sound = nil,
        },
    },

    PHONOGRAPHON =
    {
        voice = "dontstarve/maxwell/talk_LP_world6",
        idleanim= "idle_loop",
        dialogpreanim = "dialog_pre",
        dialoganim="dialog_loop",
        dialogpostanim = "dialog_pst",
        disableplayer = false,
        skippable = false,
        {
            --string = STRINGS.MAXWELL_ADVENTURETHRONE.LEVEL_6.PHONOGRAPHON.ONE,
            wait = 1,
            anim = nil,
            sound = nil,
        },
        {
            string = STRINGS.MAXWELL_ADVENTURETHRONE.LEVEL_6.PHONOGRAPHON.ONE,
            wait = 3,
            anim = nil,
            sound = nil,
        },
    },

    PHONOGRAPHOFF =
    {
        voice = "dontstarve/maxwell/talk_LP_world6",
        idleanim= "idle_loop",
        dialogpreanim = "dialog_pre",
        dialoganim="dialog_loop",
        dialogpostanim = "dialog_pst",
        disableplayer = false,
        skippable = false,
        {
            --string = STRINGS.MAXWELL_ADVENTURETHRONE.LEVEL_6.PHONOGRAPHON.ONE,
            wait = 0.33,
            anim = nil,
            sound = nil,
        },
        {
            string = STRINGS.MAXWELL_ADVENTURETHRONE.LEVEL_6.PHONOGRAPHOFF.ONE,
            wait = 4,
            anim = nil,
            sound = nil,
        },
    },

    TELEPORTFAIL =
    {
        delay = 4,
        voice = "dontstarve/maxwell/talk_LP_world6",
        idleanim= "idle_loop",
        dialogpreanim = "dialog_pre",
        dialoganim="dialog_loop",
        dialogpostanim = "dialog_pst",
        disableplayer = false,
        skippable = false,
        {
            string = STRINGS.MAXWELL_ADVENTUREINTROS.LEVEL_6.TELEPORTFAIL,
            wait = 3,
            anim = nil,
            sound = nil,
        },
        {
            string = STRINGS.MAXWELL_ADVENTUREINTROS.LEVEL_6.TELEPORTFAIL2,
            wait = 3,
            anim = nil,
            sound = nil,
        },
    },

}
for k,v in ipairs(STRINGS.MAXWELL_ADVENTUREINTROS.LEVEL_6.CONVERSATION) do
	table.insert(SPEECH, createconversationline(v))
end

local function StopTalking(inst)
    if inst.task ~= nil then
        KillThread(inst.task)
        inst.task = nil
    end

    inst.speech = nil
    inst:RemoveTag("maxwellnottalking")
    inst.SoundEmitter:KillSound("talk")
    if inst.components.talker ~= nil then
        inst.components.talker:ShutUp()
    end
end

local function RefreshTalkAction(inst)
    if inst.components.talkable ~= nil and inst.components.maxwelltalker ~= nil and not inst.components.maxwelltalker:IsTalking() then
        inst:AddTag("maxwellnottalking")
    else
        inst:RemoveTag("maxwellnottalking")
    end
end

local function EnableTalkAction(inst)
    if inst.components.talkable == nil then
        inst:AddComponent("talkable")
    end

    RefreshTalkAction(inst)
end

local function DoTalk(inst)
    inst:RemoveTag("maxwellnottalking")
    inst.speech = nil
    inst.SoundEmitter:KillSound("talk")

    local talker = inst.components.maxwelltalker
    local speech = talker ~= nil and talker.speeches ~= nil and talker.speeches[talker.speech or "NULL_SPEECH"] or nil
    inst.speech = speech

    if speech == nil then
        inst.task = nil
        RefreshTalkAction(inst)
        return
    end

    if speech.delay ~= nil then
        Sleep(speech.delay)
    end

    if speech.appearanim ~= nil then
        inst.AnimState:PlayAnimation(speech.appearanim)
    end
    if speech.idleanim ~= nil then
        inst.AnimState:PushAnimation(speech.idleanim, true)
    end

    if speech.appearanim ~= nil then
        Sleep(0.4)
        inst.SoundEmitter:PlaySound("dontstarve/maxwell/disappear")
        local smoke = SpawnPrefab("maxwell_smoke")
        if smoke ~= nil then
            smoke.Transform:SetPosition(inst.Transform:GetWorldPosition())
        end
        Sleep(1)
    end

    for _, section in ipairs(speech) do
        local wait = section.wait or 1

        if section.anim ~= nil then
            inst.AnimState:PlayAnimation(section.anim)
            if speech.idleanim ~= nil then
                inst.AnimState:PushAnimation(speech.idleanim, true)
            end
        end

        if section.string ~= nil then
            if speech.dialogpreanim ~= nil then
                inst.AnimState:PlayAnimation(speech.dialogpreanim)
            end
            if speech.dialoganim ~= nil then
                inst.AnimState:PushAnimation(speech.dialoganim, true)
            end
            inst.SoundEmitter:PlaySound(speech.voice or "dontstarve/maxwell/talk_LP", "talk")
            if inst.components.talker ~= nil then
                inst.components.talker:Say(section.string, wait, nil, true)
            end
        end

        if section.sound ~= nil then
            inst.SoundEmitter:PlaySound(section.sound)
        end

        Sleep(wait)

        if section.string ~= nil then
            inst.SoundEmitter:KillSound("talk")
            if speech.dialogpostanim ~= nil then
                inst.AnimState:PlayAnimation(speech.dialogpostanim)
            end
        end

        if speech.idleanim ~= nil then
            inst.AnimState:PushAnimation(speech.idleanim, true)
        end

        Sleep(section.waitbetweenlines or 0.5)
    end

    inst.SoundEmitter:KillSound("talk")

    if speech.disappearanim ~= nil then
        inst.SoundEmitter:PlaySound("dontstarve/maxwell/disappear")
        local smoke = SpawnPrefab("maxwell_smoke")
        if smoke ~= nil then
            smoke.Transform:SetPosition(inst.Transform:GetWorldPosition())
        end
        inst.AnimState:PlayAnimation(speech.disappearanim, false)
    end

    inst.speech = nil
    inst.task = nil
    RefreshTalkAction(inst)
end

local function DoTalkComponent(self, inst)
    DoTalk(inst or self.inst)
end

local function StopTalkingComponent(self)
    StopTalking(self.inst)
end

local function IsTalkingComponent(self)
    return self.inst.speech ~= nil or self.inst.task ~= nil
end

local function StartSpeech(inst, speech)
    local maxwelltalker = inst.components.maxwelltalker
    if maxwelltalker == nil then
        return
    end

    if maxwelltalker:IsTalking() then
        maxwelltalker:StopTalking()
    end

    inst:RemoveTag("maxwellnottalking")
    maxwelltalker.speech = speech
    inst.task = inst:StartThread(function()
        maxwelltalker:DoTalk(inst)
    end)
end

local function activateintrospeech(inst)
    local conv_index = 1

    inst:DoTaskInTime(1.5, function()
        if inst.components.maxwelltalker then
            StartSpeech(inst, "INTRO")
            inst:RemoveComponent("playerprox")
        end
    end)

    inst:DoTaskInTime(4, function()
        if inst.components.maxwelltalker then
            inst.components.maxwelltalker.speech = conv_index
            EnableTalkAction(inst)
        end
    end)

    inst:ListenForEvent("talkedto", function()
        if inst.components.maxwelltalker then
            conv_index = math.min(#SPEECH, conv_index + 1)
            inst.components.maxwelltalker.speech = conv_index
        end
    end)
end


local function OnHit(inst, attacker)
    local doer = attacker
    if doer then
        TheWorld:PushEvent("ms_sendlightningstrike", doer:GetPosition())

        if doer.components.combat then
			doer.components.combat:GetAttacked(nil, TUNING.UNARMED_DAMAGE)
		end

		if doer.components.inventory then
			local tool = doer.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
			if tool then
				if tool.prefab == "diviningrod" then
					doer.components.inventory:DropItem(tool, true, true)
				else
					tool:Remove()
				end
			end
		end
    end

    StartSpeech(inst, "HIT")

end

local function phonographon(inst)
    if inst.components.maxwelltalker then
        StartSpeech(inst, "PHONOGRAPHON")
    end
end

local function phonographoff(inst)
    if inst.components.maxwelltalker then
        StartSpeech(inst, "PHONOGRAPHOFF")
    end
end

local function teleportfail(inst)
    if inst.components.playerprox then
        inst:RemoveComponent("playerprox")
    end

    if inst.components.maxwelltalker then
        StartSpeech(inst, "TELEPORTFAIL")
    end
    if not inst.components.talkable then
        local conv_index = 1
        inst:DoTaskInTime(4, function()
            if inst.components.maxwelltalker then
                inst.components.maxwelltalker.speech = conv_index
                EnableTalkAction(inst)
            end
        end)

        inst:ListenForEvent("talkedto", function()
            if inst.components.maxwelltalker then
                conv_index = math.min(#SPEECH, conv_index + 1)
                inst.components.maxwelltalker.speech = conv_index
            end
        end)
    end
end

local function fn()
    local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:AddAnimState()
	inst.entity:AddSoundEmitter()
	inst.entity:AddNetwork()

    MakeObstaclePhysics(inst, 2)

    inst.AnimState:SetBank("maxwellthrone")
    inst.AnimState:SetBuild("maxwell_endgame")
    inst.AnimState:PlayAnimation("idle_loop", true)

    inst:AddTag("maxwellendgame")

    inst:AddComponent("talker")
    inst.components.talker.fontsize = 40
    inst.components.talker.font = TALKINGFONT
    --inst.components.talker.colour = Vector3(133/255, 140/255, 167/255)
    inst.components.talker.offset = Vector3(0,-700,0)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("named")
    inst.components.named:SetName(STRINGS.NAMES.MAXWELL)

    inst:AddComponent("maxwelltalker")
    inst.components.maxwelltalker.speeches = SPEECH
    inst.components.maxwelltalker.DoTalk = DoTalkComponent
    inst.components.maxwelltalker.StopTalking = StopTalkingComponent
    inst.components.maxwelltalker.IsTalking = IsTalkingComponent

    inst:AddComponent("playerprox")
    inst.components.playerprox:SetDist(12, 15)
    inst.components.playerprox:SetOnPlayerNear(activateintrospeech)

    inst.phonograph = TheSim:FindFirstEntityWithTag("maxwellphonograph")
    if inst.phonograph then
        inst:ListenForEvent("turnedon", function() phonographon(inst) end, inst.phonograph)
        inst:ListenForEvent("turnedoff",function() phonographoff(inst) end, inst.phonograph)
    end

    inst.telefail = teleportfail

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(10000000)

    inst:AddComponent("combat")
    inst.components.combat.onhitfn = OnHit

	return inst
end

return Prefab("maxwellendgame", fn, assets, prefabs)
