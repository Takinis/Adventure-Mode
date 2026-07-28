local MAXWELL_SPEECH_BY_CHAPTER =
{
    "ADVENTURE_1",
    "ADVENTURE_2",
    "ADVENTURE_3",
    "ADVENTURE_4",
    "ADVENTURE_5",
    "ADVENTURE_6",
}

local WAIT_TIMEOUT = 45
local READY_SETTLE_TIME = .5
local MAXWELL_OFFSET = 4

local function IsPlayerValid(player)
    return player ~= nil and player:IsValid() and player.userid ~= nil and player.userid ~= ""
end

local function CountEntries(entries)
    local count = 0
    for _ in pairs(entries) do
        count = count + 1
    end
    return count
end

local function GetCurrentAdventureRun()
    return ShardGameIndex.adventure:GetState()
end

local function GetCurrentAdventureSpeechName()
    local run = GetCurrentAdventureRun()
    local preset = run ~= nil and run.current_preset or nil
    if preset == "ENDING" then
        return nil
    end

    local chapter = run ~= nil and run.chapter or nil
    if chapter == nil then
        return nil
    end

    return preset == "TWOLANDS" and "ADVENTURE_TWOLANDS" or MAXWELL_SPEECH_BY_CHAPTER[chapter]
end

local function LockPlayer(player)
    if not IsPlayerValid(player) then
        return false
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

local function UnlockPlayer(player)
    if not IsPlayerValid(player) then
        return
    end

    if player.sg ~= nil and player.sg.currentstate ~= nil and player.sg.currentstate.name == "sleep" then
        player.sg:GoToState("wakeup")
    elseif player.components.playercontroller ~= nil then
        player.components.playercontroller:EnableMapControls(true)
        player.components.playercontroller:Enable(true)
    end
end

local function OnWaitTimeout(inst, self)
    self.timeout_task = nil
    self:OnWaitTimeout()
end

local function OnReadySettled(inst, self)
    self.settle_task = nil
    self:StartSharedIntro()
end

local function OnClientAuthenticated(inst, data)
    local self = inst.components.maxwellintrospawner
    if self ~= nil then
        self:OnClientAuthenticated(data ~= nil and data.userid or nil)
    end
end

local function OnClientDisconnected(inst, data)
    local self = inst.components.maxwellintrospawner
    if self ~= nil then
        self:RemoveParticipant(data ~= nil and data.userid or nil)
    end
end

local function OnPlayerDeactivated(inst, player)
    local self = inst.components.maxwellintrospawner
    if self ~= nil and player ~= nil then
        self:RemoveParticipant(player.userid)
    end
end

local MaxwellIntroSpawner = Class(function(self, inst)
    assert(TheWorld.ismastersim, "MaxwellIntroSpawner should not exist on client")

    self.inst = inst
    self.phase = "idle"
    self.presentation_id = nil
    self.expected = {}
    self.ready = {}
    self.players = {}
    self.locked_players = {}
    self.participants = {}
    self.skip_votes = {}
    self.maxwell = nil
    self.timeout_task = nil
    self.settle_task = nil

    inst:ListenForEvent("ms_clientauthenticationcomplete", OnClientAuthenticated)
    inst:ListenForEvent("ms_clientdisconnected", OnClientDisconnected)
    inst:ListenForEvent("playerdeactivated", OnPlayerDeactivated)
end)

function MaxwellIntroSpawner:IsCurrentChapterPlayed()
    return ShardGameIndex.adventure:IsCurrentMaxwellIntroPlayed()
end

function MaxwellIntroSpawner:ShouldPlayCurrentChapter()
    return self.phase ~= "playing" and self.phase ~= "finished" and
        GetCurrentAdventureSpeechName() ~= nil and
        not self:IsCurrentChapterPlayed()
end

function MaxwellIntroSpawner:AddConnectedPlayers()
    local clients = TheNet:GetClientTable() or {}
    local client_hosted = TheNet:GetServerIsClientHosted()
    for _, client in ipairs(clients) do
        if type(client.userid) == "string" and client.userid ~= "" and
            (client_hosted or client.performance == nil) then
            self.expected[client.userid] = true
        end
    end
end

function MaxwellIntroSpawner:BeginCollection(presentation_id)
    self.phase = "collecting"
    self.presentation_id = presentation_id
    self.expected = {}
    self.ready = {}
    self.players = {}
    self.locked_players = {}
    self.participants = {}
    self.skip_votes = {}
    self:AddConnectedPlayers()
    self.timeout_task = self.inst:DoTaskInTime(WAIT_TIMEOUT, OnWaitTimeout, self)
end

function MaxwellIntroSpawner:PreparePlayer(player, presentation_id)
    if not IsPlayerValid(player) or type(presentation_id) ~= "string" or presentation_id == "" or
        not self:ShouldPlayCurrentChapter() then
        return false
    end

    if self.phase == "idle" then
        self:BeginCollection(presentation_id)
    elseif self.phase ~= "collecting" or self.presentation_id ~= presentation_id then
        return false
    end

    self.expected[player.userid] = true
    self.players[player.userid] = player
    return true
end

function MaxwellIntroSpawner:GetReadyUserids()
    local userids = {}
    for userid in pairs(self.ready) do
        table.insert(userids, userid)
    end
    return userids
end

function MaxwellIntroSpawner:SendWaitStatus()
    local userids = self:GetReadyUserids()
    if #userids > 0 then
        SendModRPCToClient(
            GetClientModRPC("AdventureMode", "UpdateAdventurePresentationWait"),
            userids,
            self.presentation_id,
            CountEntries(self.ready),
            CountEntries(self.expected)
        )
    end
end

function MaxwellIntroSpawner:CancelSettleTask()
    if self.settle_task ~= nil then
        self.settle_task:Cancel()
        self.settle_task = nil
    end
end

function MaxwellIntroSpawner:CheckAllReady()
    if self.phase ~= "collecting" then
        return
    end

    local expected_count = CountEntries(self.expected)
    if expected_count > 0 and CountEntries(self.ready) >= expected_count then
        if self.settle_task == nil then
            self.settle_task = self.inst:DoTaskInTime(READY_SETTLE_TIME, OnReadySettled, self)
        end
    else
        self:CancelSettleTask()
    end
end

function MaxwellIntroSpawner:SetPlayerReady(player, presentation_id)
    if self.phase ~= "collecting" or self.presentation_id ~= presentation_id or not IsPlayerValid(player) or
        self.players[player.userid] ~= player then
        return false
    end

    self.ready[player.userid] = true

    self:SendWaitStatus()
    self:CheckAllReady()
    return true
end

function MaxwellIntroSpawner:OnClientAuthenticated(userid)
    if self.phase ~= "collecting" or type(userid) ~= "string" or userid == "" then
        return
    end

    if not self.expected[userid] then
        self.expected[userid] = true
        self:CancelSettleTask()
        self:SendWaitStatus()
    end
end

function MaxwellIntroSpawner:UnlockAllPlayers()
    for userid, player in pairs(self.locked_players) do
        UnlockPlayer(player)
        self.locked_players[userid] = nil
    end
end

function MaxwellIntroSpawner:ClearTasks()
    if self.timeout_task ~= nil then
        self.timeout_task:Cancel()
        self.timeout_task = nil
    end
    self:CancelSettleTask()
end

function MaxwellIntroSpawner:ClearPresentation(phase)
    self:ClearTasks()
    self:UnlockAllPlayers()
    self.phase = phase or "finished"
    self.expected = {}
    self.ready = {}
    self.players = {}
    self.participants = {}
    self.skip_votes = {}
end

function MaxwellIntroSpawner:AbortCollection()
    if self.phase ~= "collecting" then
        return
    end

    local userids = self:GetReadyUserids()
    if #userids > 0 then
        SendModRPCToClient(
            GetClientModRPC("AdventureMode", "AbortAdventurePresentation"),
            userids,
            self.presentation_id
        )
    end
    self:ClearPresentation("finished")
end

function MaxwellIntroSpawner:OnWaitTimeout()
    if self.phase ~= "collecting" then
        return
    end

    for userid in pairs(self.expected) do
        if not self.ready[userid] then
            self.expected[userid] = nil
            self.players[userid] = nil
        end
    end

    if next(self.ready) == nil then
        self:AbortCollection()
    else
        self:SendWaitStatus()
        self:StartSharedIntro()
    end
end

function MaxwellIntroSpawner:GetSharedMaxwellPosition()
    local x, y, z = 0, 0, 0
    local count = 0
    for userid in pairs(self.ready) do
        local player = self.players[userid]
        if IsPlayerValid(player) then
            local px, py, pz = player.Transform:GetWorldPosition()
            x, y, z = x + px, y + py, z + pz
            count = count + 1
        end
    end
    if count <= 0 then
        return nil
    end

    x, y, z = x / count, y / count, z / count
    local theta = 45 * DEGREES
    return x + math.cos(theta) * MAXWELL_OFFSET, y, z - math.sin(theta) * MAXWELL_OFFSET, x, y, z
end

function MaxwellIntroSpawner:StartSharedIntro()
    if self.phase ~= "collecting" then
        return false
    end

    self:ClearTasks()
    self.participants = {}
    local has_non_maxwell = false
    for userid in pairs(self.ready) do
        local player = self.players[userid]
        if IsPlayerValid(player) then
            self.participants[userid] = player
            has_non_maxwell = has_non_maxwell or player.prefab ~= "waxwell"
        end
    end

    if next(self.participants) == nil then
        self:AbortCollection()
        return false
    elseif not has_non_maxwell then
        ShardGameIndex.adventure:MarkCurrentMaxwellIntroPlayed()
        self:AbortCollection()
        return false
    end

    local speech_name = GetCurrentAdventureSpeechName()
    local x, y, z, center_x, center_y, center_z = self:GetSharedMaxwellPosition()
    if speech_name == nil or x == nil then
        self:AbortCollection()
        return false
    end

    local maxwell = SpawnPrefab("maxwellintro")
    if maxwell == nil or maxwell.components.maxwelltalker == nil then
        if maxwell ~= nil then
            maxwell:Remove()
        end
        self:AbortCollection()
        return false
    end

    self.phase = "playing"
    self.maxwell = maxwell
    maxwell.Transform:SetPosition(x, y, z)
    maxwell.Transform:ClearTransformationHistory()
    maxwell:FacePoint(center_x, center_y, center_z)
    maxwell.components.maxwelltalker:SetSpeech(speech_name)
    if not maxwell.components.maxwelltalker:BeginSpeech(function(_, completed)
            self:OnMaxwellFinished(maxwell, completed)
        end) then
        self.maxwell = nil
        self.phase = "collecting"
        if maxwell:IsValid() then
            maxwell:Remove()
        end
        self:AbortCollection()
        return false
    end

    local userids = {}
    for userid, player in pairs(self.participants) do
        if self.locked_players[userid] == nil and LockPlayer(player) then
            self.locked_players[userid] = player
        end
        player:FacePoint(x, y, z)
        table.insert(userids, userid)
    end

    ShardGameIndex.adventure:MarkCurrentMaxwellIntroPlayed()
    SendModRPCToClient(
        GetClientModRPC("AdventureMode", "StartMaxwellIntro"),
        userids,
        self.presentation_id,
        maxwell.GUID,
        x,
        y,
        z
    )
    return true
end

function MaxwellIntroSpawner:OnMaxwellFinished(maxwell)
    if self.phase ~= "playing" or self.maxwell ~= maxwell then
        return
    end

    local userids = {}
    for userid in pairs(self.participants) do
        table.insert(userids, userid)
    end
    if #userids > 0 then
        SendModRPCToClient(
            GetClientModRPC("AdventureMode", "StopMaxwellIntro"),
            userids,
            self.presentation_id,
            maxwell.GUID
        )
    end

    self.maxwell = nil
    self:ClearPresentation("finished")
end

function MaxwellIntroSpawner:CheckSkipVotes()
    if self.phase ~= "playing" or self.maxwell == nil then
        return
    end

    for userid in pairs(self.participants) do
        if not self.skip_votes[userid] then
            return
        end
    end
    self.maxwell.components.maxwelltalker:RequestSkip()
end

function MaxwellIntroSpawner:RequestSkip(player, presentation_id, guid)
    if self.phase ~= "playing" or self.presentation_id ~= presentation_id or
        self.maxwell == nil or self.maxwell.GUID ~= guid or not IsPlayerValid(player) or
        self.participants[player.userid] ~= player then
        return false
    end

    self.skip_votes[player.userid] = true
    self:CheckSkipVotes()
    return true
end

function MaxwellIntroSpawner:RemoveParticipant(userid)
    if type(userid) ~= "string" or userid == "" then
        return
    end

    local locked_player = self.locked_players[userid]
    if locked_player ~= nil then
        UnlockPlayer(locked_player)
        self.locked_players[userid] = nil
    end
    self.expected[userid] = nil
    self.ready[userid] = nil
    self.players[userid] = nil
    self.participants[userid] = nil
    self.skip_votes[userid] = nil

    if self.phase == "collecting" then
        self:SendWaitStatus()
        if next(self.expected) == nil then
            self:AbortCollection()
        else
            self:CheckAllReady()
        end
    elseif self.phase == "playing" then
        if next(self.participants) == nil then
            local maxwell = self.maxwell
            self.maxwell = nil
            self:ClearPresentation("finished")
            if maxwell ~= nil and maxwell:IsValid() then
                maxwell.components.maxwelltalker:SetOnFinishedFn(nil)
                maxwell:Remove()
            end
        else
            self:CheckSkipVotes()
        end
    end
end

function MaxwellIntroSpawner:OnRemoveFromEntity()
    self.inst:RemoveEventCallback("ms_clientauthenticationcomplete", OnClientAuthenticated)
    self.inst:RemoveEventCallback("ms_clientdisconnected", OnClientDisconnected)
    self.inst:RemoveEventCallback("playerdeactivated", OnPlayerDeactivated)

    local maxwell = self.maxwell
    self.maxwell = nil
    self:ClearPresentation("finished")
    if maxwell ~= nil and maxwell:IsValid() then
        maxwell.components.maxwelltalker:SetOnFinishedFn(nil)
        maxwell:Remove()
    end
end

function MaxwellIntroSpawner:GetDebugString()
    return string.format(
        "phase=%s expected=%d ready=%d participants=%d",
        self.phase,
        CountEntries(self.expected),
        CountEntries(self.ready),
        CountEntries(self.participants)
    )
end

return MaxwellIntroSpawner
