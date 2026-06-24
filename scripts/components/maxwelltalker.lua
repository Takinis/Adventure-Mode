local MaxwellTalker = Class(function(self, inst)
    self.inst = inst
    self.speech = nil
    self.speeches = nil
    self.defaultvoice = "dontstarve/maxwell/talk_LP"
    self.canskip = false
    self.player = nil
    self._speech_task = nil
    self._client_cutscene_active = false
    self._player_cutscene_locked = false
    self._anim_remove_fn = function() self:RemoveAfterAnimation() end
end)

local function SpawnMaxwellSmokeAt(inst)
    local fx = SpawnPrefab("maxwell_smoke")
    if fx ~= nil then
        fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
    end
end

local function IsPlayerValid(player)
    return player ~= nil and player:IsValid() and player.userid ~= nil and player.userid ~= ""
end

local function GetSpawnPositionNearPlayer(player)
    local x, y, z = player.Transform:GetWorldPosition()
    local theta = (player.Transform:GetRotation() + 45) * DEGREES
    return x + math.cos(theta) * 4, y, z - math.sin(theta) * 4
end

local function SendClientCutsceneRPC(player, rpc_name, ...)
    if IsPlayerValid(player) then
        SendModRPCToClient(GetClientModRPC("AdventureMode", rpc_name), player.userid, ...)
    end
end

local function LockPlayerForCutscene(player)
    if not IsPlayerValid(player) then
        return
    end

    if player.components.locomotor ~= nil then
        player.components.locomotor:Stop()
        player.components.locomotor:StopMoving()
    end

    player:ClearBufferedAction()

    if player.components.playercontroller ~= nil then
        player.components.playercontroller:EnableMapControls(false)
        player.components.playercontroller:Enable(false)
    end

    if player.sg ~= nil then
        player.sg:GoToState("sleep")
    end
    return true
end

local function UnlockPlayerForCutscene(player)
    if not IsPlayerValid(player) then
        return
    end

    if player.sg ~= nil and
        player.sg.currentstate ~= nil and
        player.sg.currentstate.name == "sleep" then
        player.sg:GoToState("wakeup")
    elseif player.components.playercontroller ~= nil then
        player.components.playercontroller:EnableMapControls(true)
        player.components.playercontroller:Enable(true)
    end
end

function MaxwellTalker:GetSpeechData()
    return self.speech ~= nil and self.speeches ~= nil and self.speeches[self.speech] or nil
end

function MaxwellTalker:SetSpeech(speech)
    self.speech = speech
end

function MaxwellTalker:IsTalking()
    return self._speech_task ~= nil or self:GetSpeechData() ~= nil
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

function MaxwellTalker:PositionForPlayer(player)
    if not IsPlayerValid(player) then
        return
    end

    local x, y, z = GetSpawnPositionNearPlayer(player)
    self.inst.Transform:SetPosition(x, y, z)
    self.inst.Transform:ClearTransformationHistory()
    self.inst:FacePoint(player.Transform:GetWorldPosition())
    player:FacePoint(self.inst.Transform:GetWorldPosition())
end

function MaxwellTalker:StartClientCutscene()
    local x, y, z = self.inst.Transform:GetWorldPosition()
    self._player_cutscene_locked = LockPlayerForCutscene(self.player) == true
    SendClientCutsceneRPC(self.player, "StartMaxwellIntro", self.inst.GUID, x, y, z)
    self._client_cutscene_active = true
end

function MaxwellTalker:StopClientCutscene()
    if self._client_cutscene_active then
        SendClientCutsceneRPC(self.player, "StopMaxwellIntro", self.inst.GUID)
        self._client_cutscene_active = false
    end
    if self._player_cutscene_locked then
        self._player_cutscene_locked = false
        UnlockPlayerForCutscene(self.player)
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
    self:StopClientCutscene()
    self:PlayDisappearSequence(speech or self:GetSpeechData() or {})
end

function MaxwellTalker:CancelSpeech(player)
    if not self.canskip or (player ~= nil and player ~= self.player) then
        return false
    end

    local speech = self:GetSpeechData()
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

function MaxwellTalker:BeginSpeech(player)
    if not TheWorld.ismastersim or self._speech_task ~= nil then
        return false
    end

    local speech = self:GetSpeechData()
    if speech == nil or not IsPlayerValid(player) then
        self.inst:Remove()
        return false
    end

    self.player = player
    self:PositionForPlayer(self.player)
    self.inst:Hide()

    if speech.disableplayer then
        self:StartClientCutscene()
    end

    self._speech_task = self.inst:StartThread(function()
        self:PlaySpeechThread()
    end)

    return true
end

function MaxwellTalker:OnRemoveFromEntity()
    self:StopClientCutscene()
    self:ClearAnimRemoveCallback()
    self:StopSpeechThread()
    self:ShutUp()
end

return MaxwellTalker
