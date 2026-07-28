local MaxwellTalker = Class(function(self, inst)
    self.inst = inst
    self.speech = nil
    self.speeches = nil
    self.defaultvoice = "dontstarve/maxwell/talk_LP"
    self.canskip = false
    self.skip_requested = false
    self.onfinishedfn = nil
    self._speech_task = nil
    self._anim_remove_fn = function() self:RemoveAfterAnimation() end
end)

local function SpawnMaxwellSmokeAt(inst)
    local fx = SpawnPrefab("maxwell_smoke")
    if fx ~= nil then
        fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
    end
end

function MaxwellTalker:GetSpeechData()
    return self.speech ~= nil and self.speeches ~= nil and self.speeches[self.speech] or nil
end

function MaxwellTalker:SetSpeech(speech)
    self.speech = speech
end

function MaxwellTalker:SetOnFinishedFn(fn)
    self.onfinishedfn = fn
end

function MaxwellTalker:IsTalking()
    return self._speech_task ~= nil
end

function MaxwellTalker:ClearAnimRemoveCallback()
    self.inst:RemoveEventCallback("animqueueover", self._anim_remove_fn)
end

function MaxwellTalker:StopTalkSound()
    self.inst.SoundEmitter:KillSound("talk")
end

function MaxwellTalker:ShutUp()
    if self.inst.components.talker ~= nil then
        self.inst.components.talker:ShutUp()
    end
    self:StopTalkSound()
end

function MaxwellTalker:StopSpeechThread()
    if self._speech_task ~= nil then
        KillThread(self._speech_task)
        self._speech_task = nil
    end
end

function MaxwellTalker:RemoveAfterAnimation()
    self:ClearAnimRemoveCallback()
    if self.inst:IsValid() then
        self.inst:Remove()
    end
end

function MaxwellTalker:PlayAppearSequence(speech)
    if speech.appearanim ~= nil then
        self.inst.AnimState:PlayAnimation(speech.appearanim)
    end
    if speech.idleanim ~= nil then
        self.inst.AnimState:PushAnimation(speech.idleanim, true)
    end

    if speech.appearanim ~= nil then
        self.inst:DoTaskInTime(.4, function(inst)
            if inst:IsValid() then
                inst.SoundEmitter:PlaySound("dontstarve/maxwell/disappear")
                SpawnMaxwellSmokeAt(inst)
            end
        end)
        Sleep(1.4)
    end
end

function MaxwellTalker:PlayDisappearSequence(speech)
    self:StopTalkSound()

    if speech.disappearanim ~= nil then
        self.inst.SoundEmitter:PlaySound("dontstarve/maxwell/disappear")
        SpawnMaxwellSmokeAt(self.inst)
        if self.inst.DynamicShadow ~= nil then
            self.inst.DynamicShadow:Enable(false)
        end
        self.inst.AnimState:PlayAnimation(speech.disappearanim, false)
        self:ClearAnimRemoveCallback()
        self.inst:ListenForEvent("animqueueover", self._anim_remove_fn)
    else
        self.inst:Remove()
    end
end

function MaxwellTalker:FinishSpeech(speech)
    self.canskip = false
    self:ShutUp()
    if self.onfinishedfn ~= nil then
        local onfinishedfn = self.onfinishedfn
        self.onfinishedfn = nil
        onfinishedfn(self.inst, true)
    end
    self:PlayDisappearSequence(speech or self:GetSpeechData() or {})
end

function MaxwellTalker:RequestSkip()
    local speech = self:GetSpeechData()
    if speech == nil or speech.skippable ~= true then
        return false
    end

    self.skip_requested = true
    if not self.canskip then
        return true
    end

    self:StopSpeechThread()
    self:FinishSpeech(speech)
    return true
end

function MaxwellTalker:PlaySpeechThread()
    local speech = self:GetSpeechData()
    if speech == nil then
        self.inst:Remove()
        return
    end

    if speech.delay ~= nil then
        Sleep(speech.delay)
    end

    self.inst:Show()
    self:PlayAppearSequence(speech)
    self.canskip = speech.skippable == true
    if self.skip_requested and self.canskip then
        self._speech_task = nil
        self:FinishSpeech(speech)
        return
    end

    for _, section in ipairs(speech) do
        local wait = section.wait or 1

        if section.anim ~= nil then
            self.inst.AnimState:PlayAnimation(section.anim)
            if speech.idleanim ~= nil then
                self.inst.AnimState:PushAnimation(speech.idleanim, true)
            end
        end

        if section.string ~= nil then
            if speech.dialogpreanim ~= nil then
                self.inst.AnimState:PlayAnimation(speech.dialogpreanim)
            end
            if speech.dialoganim ~= nil then
                self.inst.AnimState:PushAnimation(speech.dialoganim, true)
            end

            self.inst.SoundEmitter:PlaySound(speech.voice or self.defaultvoice, "talk")
            if self.inst.components.talker ~= nil then
                self.inst.components.talker:Say(section.string, wait, nil, true)
            end
        end

        if section.sound ~= nil then
            self.inst.SoundEmitter:PlaySound(section.sound)
        end

        Sleep(wait)

        if section.string ~= nil then
            self:StopTalkSound()
            if speech.dialogpostanim ~= nil then
                self.inst.AnimState:PlayAnimation(speech.dialogpostanim)
            end
        end

        if speech.idleanim ~= nil then
            self.inst.AnimState:PushAnimation(speech.idleanim, true)
        end

        Sleep(section.waitbetweenlines or .5)
    end

    self._speech_task = nil
    self:FinishSpeech(speech)
end

function MaxwellTalker:BeginSpeech(onfinishedfn)
    if not TheWorld.ismastersim or self._speech_task ~= nil then
        return false
    end

    local speech = self:GetSpeechData()
    if speech == nil then
        self.inst:Remove()
        return false
    end

    self.skip_requested = false
    self.onfinishedfn = onfinishedfn
    self.inst:Hide()

    self._speech_task = self.inst:StartThread(function()
        self:PlaySpeechThread()
    end)

    return true
end

function MaxwellTalker:OnRemoveFromEntity()
    if self.onfinishedfn ~= nil then
        local onfinishedfn = self.onfinishedfn
        self.onfinishedfn = nil
        onfinishedfn(self.inst, false)
    end
    self:ClearAnimRemoveCallback()
    self:StopSpeechThread()
    self:ShutUp()
end

return MaxwellTalker
