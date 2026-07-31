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
local TITLE_TIMEOUT = 15
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
    if not IsPlayerValid(player) or player.sg == nil then
        return false
    end

    player.sg:GoToState("adventure_intro")
    return player.sg.currentstate ~= nil and player.sg.currentstate.name == "adventure_intro"
end

local function UnlockPlayer(player)
    if not IsPlayerValid(player) then
        return
    end

    if player.sg ~= nil and player.sg.currentstate ~= nil and player.sg.currentstate.name == "adventure_intro" then
        player.sg:GoToState("wakeup")
    end
end

local function OnWaitTimeout(inst, self)
    self.timeout_task = nil
    self:OnWaitTimeout()
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
    self.title_finished = {}
    self.players = {}
    self.locked_players = {}
    self.participants = {}
    self.skip_votes = {}
    self.can_skip_intro = false
    self.maxwell = nil
    self.timeout_task = nil
    self.barrier_pause_requested = false
    self.owns_server_pause = false

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
    local run = GetCurrentAdventureRun()
    if run ~= nil then
        for userid, participating in pairs(run.participants or {}) do
            if participating and type(userid) == "string" and userid ~= "" then
                self.expected[userid] = true
            end
        end

        for _, session in ipairs(run.player_sessions or {}) do
            if type(session.userid) == "string" and session.userid ~= "" then
                self.expected[session.userid] = true
            end
        end

        for _, session in ipairs(run.adventure_player_sessions or {}) do
            if type(session.userid) == "string" and session.userid ~= "" then
                self.expected[session.userid] = true
            end
        end
    end

    local clients = TheNet:GetClientTable() or {}
    local client_hosted = TheNet:GetServerIsClientHosted()
    for _, client in ipairs(clients) do
        if type(client.userid) == "string" and client.userid ~= "" and
            (client_hosted or client.performance == nil) then
            self.expected[client.userid] = true
        end
    end
end

function MaxwellIntroSpawner:SetBarrierPaused(paused)
    if self.barrier_pause_requested ~= paused or (not paused and self.owns_server_pause) then
        self.barrier_pause_requested = paused
        self.inst:StartWallUpdatingComponent(self)
    end
end

function MaxwellIntroSpawner:OnWallUpdate()
    self.inst:StopWallUpdatingComponent(self)

    local should_pause = self.barrier_pause_requested and
        (self.phase == "collecting" or self.phase == "title") and CountEntries(self.expected) > 1
    if self.barrier_pause_requested and not should_pause then
        self.barrier_pause_requested = false
    end

    if should_pause then
        if not self.owns_server_pause and not TheNet:IsServerPaused(true) then
            self.owns_server_pause = true
            SetServerPaused(true)
        end
    elseif self.owns_server_pause then
        self.owns_server_pause = false
        SetServerPaused(false)
    end
end

function MaxwellIntroSpawner:UpdateBarrierPause()
    self:SetBarrierPaused(
        (self.phase == "collecting" or self.phase == "title") and CountEntries(self.expected) > 1
    )
end

function MaxwellIntroSpawner:RestartTimeout(timeout)
    if self.timeout_task ~= nil then
        self.timeout_task:Cancel()
    end
    self.timeout_task = self.inst:DoStaticTaskInTime(timeout, OnWaitTimeout, self)
end

function MaxwellIntroSpawner:BeginCollection(presentation_id)
    self.phase = "collecting"
    self.presentation_id = presentation_id
    self.expected = {}
    self.ready = {}
    self.title_finished = {}
    self.players = {}
    self.locked_players = {}
    self.participants = {}
    self.skip_votes = {}
    self.can_skip_intro = false
    self:AddConnectedPlayers()
    self:UpdateBarrierPause()
    self:RestartTimeout(WAIT_TIMEOUT)
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
    self:UpdateBarrierPause()
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

function MaxwellIntroSpawner:CheckAllReady()
    if self.phase ~= "collecting" then
        return
    end

    local expected_count = CountEntries(self.expected)
    if expected_count > 0 and CountEntries(self.ready) >= expected_count then
        self:StartSharedTitle()
    end
end

function MaxwellIntroSpawner:SetPlayerReady(player, presentation_id)
    if self.presentation_id == presentation_id and IsPlayerValid(player) and
        self.participants[player.userid] == player and
        (self.phase == "title" or self.phase == "playing") then
        return true
    end

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
        self:UpdateBarrierPause()
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
end

function MaxwellIntroSpawner:ClearPresentation(phase)
    self:ClearTasks()
    self:SetBarrierPaused(false)
    self:UnlockAllPlayers()
    self.phase = phase or "finished"
    self.expected = {}
    self.ready = {}
    self.title_finished = {}
    self.players = {}
    self.participants = {}
    self.skip_votes = {}
    self.can_skip_intro = false
end

function MaxwellIntroSpawner:AbortPresentation()
    if self.phase ~= "collecting" and self.phase ~= "title" then
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
    if self.phase == "title" then
        self:AbortPresentation()
        return
    elseif self.phase ~= "collecting" then
        return
    end

    for userid in pairs(self.expected) do
        if not self.ready[userid] then
            self.expected[userid] = nil
            self.players[userid] = nil
        end
    end

    if next(self.ready) == nil then
        self:AbortPresentation()
    else
        self:SendWaitStatus()
        self:StartSharedTitle()
    end
end

function MaxwellIntroSpawner:StartSharedTitle()
    if self.phase ~= "collecting" then
        return false
    end

    local expected = {}
    local ready = {}
    local participants = {}
    local userids = {}
    for userid in pairs(self.ready) do
        local player = self.players[userid]
        if IsPlayerValid(player) then
            player:DisableLoadingProtection()
            expected[userid] = true
            ready[userid] = true
            participants[userid] = player
            table.insert(userids, userid)
        end
    end
    if #userids <= 0 then
        self:AbortPresentation()
        return false
    end

    self.phase = "title"
    self.expected = expected
    self.ready = ready
    self.participants = participants
    self.title_finished = {}
    self:UpdateBarrierPause()
    self:RestartTimeout(TITLE_TIMEOUT)
    SendModRPCToClient(
        GetClientModRPC("AdventureMode", "StartAdventureTitle"),
        userids,
        self.presentation_id
    )
    return true
end

function MaxwellIntroSpawner:CheckAllTitlesFinished()
    if self.phase == "title" and next(self.participants) ~= nil and
        CountEntries(self.title_finished) >= CountEntries(self.participants) then
        self:StartSharedIntro()
    end
end

function MaxwellIntroSpawner:SetTitleFinished(player, presentation_id)
    if self.phase == "playing" and self.presentation_id == presentation_id and IsPlayerValid(player) and
        self.participants[player.userid] == player then
        return true
    end

    if self.phase ~= "title" or self.presentation_id ~= presentation_id or not IsPlayerValid(player) or
        self.participants[player.userid] ~= player then
        return false
    end

    self.title_finished[player.userid] = true
    self:CheckAllTitlesFinished()
    return true
end

function MaxwellIntroSpawner:GetSharedMaxwellPosition()
    local x, y, z = 0, 0, 0
    local count = 0
    for userid, player in pairs(self.participants) do
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
    if self.phase ~= "title" then
        return false
    end

    self:ClearTasks()
    self:SetBarrierPaused(false)
    local participants = {}
    local has_non_maxwell = false
    for userid, player in pairs(self.participants) do
        if IsPlayerValid(player) then
            participants[userid] = player
            has_non_maxwell = has_non_maxwell or player.prefab ~= "waxwell"
        end
    end
    self.participants = participants

    if next(self.participants) == nil then
        self:AbortPresentation()
        return false
    elseif not has_non_maxwell then
        ShardGameIndex.adventure:MarkCurrentMaxwellIntroPlayed()
        self:AbortPresentation()
        return false
    end

    self.can_skip_intro = CountEntries(self.participants) == 1

    local speech_name = GetCurrentAdventureSpeechName()
    local x, y, z, center_x, center_y, center_z = self:GetSharedMaxwellPosition()
    if speech_name == nil or x == nil then
        self:AbortPresentation()
        return false
    end

    local maxwell = SpawnPrefab("maxwellintro")
    if maxwell == nil or maxwell.components.maxwelltalker == nil then
        if maxwell ~= nil then
            maxwell:Remove()
        end
        self:AbortPresentation()
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
        self.phase = "title"
        if maxwell:IsValid() then
            maxwell:Remove()
        end
        self:AbortPresentation()
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
        z,
        self.can_skip_intro
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
    if self.phase ~= "playing" or self.maxwell == nil or not self.can_skip_intro then
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
        not self.can_skip_intro or self.maxwell == nil or self.maxwell.GUID ~= guid or not IsPlayerValid(player) or
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
    self.title_finished[userid] = nil
    self.players[userid] = nil
    self.participants[userid] = nil
    self.skip_votes[userid] = nil

    if self.phase == "collecting" then
        self:UpdateBarrierPause()
        self:SendWaitStatus()
        if next(self.expected) == nil then
            self:AbortPresentation()
        else
            self:CheckAllReady()
        end
    elseif self.phase == "title" then
        self:UpdateBarrierPause()
        if next(self.participants) == nil then
            self:AbortPresentation()
        else
            self:CheckAllTitlesFinished()
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
    self.barrier_pause_requested = false
    self.inst:StopWallUpdatingComponent(self)
    if self.owns_server_pause then
        self.owns_server_pause = false
        SetServerPaused(false)
    end
    if maxwell ~= nil and maxwell:IsValid() then
        maxwell.components.maxwelltalker:SetOnFinishedFn(nil)
        maxwell:Remove()
    end
end

function MaxwellIntroSpawner:GetDebugString()
    return string.format(
        "phase=%s expected=%d ready=%d title_finished=%d participants=%d pause_requested=%s paused=%s can_skip=%s",
        self.phase,
        CountEntries(self.expected),
        CountEntries(self.ready),
        CountEntries(self.title_finished),
        CountEntries(self.participants),
        tostring(self.barrier_pause_requested),
        tostring(self.owns_server_pause),
        tostring(self.can_skip_intro)
    )
end

return MaxwellIntroSpawner
