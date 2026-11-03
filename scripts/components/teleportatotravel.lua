local function IsValidUserId(userid)
	return userid ~= nil and userid ~= ""
end

local function IsLivingPlayer(player)
	return IsValidUserId(player.userid) and not player.components.health:IsDead() and
		not player:HasTag("playerghost")
end

local function RecoverPlayerFromTransition(player)
	if player == nil or not player:IsValid() or not player.is_teleporting then
		return
	end

	player.is_teleporting = nil
	if player.sg.currentstate ~= nil and
		player.sg.currentstate.name == "teleportato_teleport" then
		player.sg:GoToState("idle")
	end
	player:SetCameraDistance()
end

local function RunProgressCheck(inst, self)
	self.progresschecktask = nil
	self:Transition()
end

local function PlayLaugh(inst, self)
	self.laughtask = nil
	inst.AnimState:PlayAnimation("laugh", false)
	inst.AnimState:PushAnimation("active_idle", true)
	inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_maxwelllaugh", "teleportato_laugh")
end

local function AdvanceShard(world, self, playersessions)
	self.advancetask = nil
	ShardGameIndex.adventure:AdvanceShard({ player_sessions = playersessions }, function(success)
		if success then
			return
		end
		self.activating = false
		self.confirmedplayers = {}
		self.inst.components.activatable.inactive = true
		for _, player in ipairs(AllPlayers) do
			RecoverPlayerFromTransition(player)
			self:Deny(player, STRINGS.UI.HUD.TELEPORTATO_TRANSITION_FAILED)
		end
	end)
end

local TeleportatoTravel = Class(function(self, inst)
	self.inst = inst
	self.activating = false
	self.confirmedplayers = {}
	self.playerdeathcallbacks = {}
	self.progresschecktask = nil
	self.laughtask = nil
	self.advancetask = nil
	self.onplayerspawned = function(_, player)
		self:TrackPlayer(player)
	end
	self.onsecondaryplayerschanged = function()
		self:ScheduleProgressCheck()
	end
	self.onplayerleft = function(_, player)
		self:StopTrackingPlayer(player)
		if IsValidUserId(player.userid) then
			self.confirmedplayers[player.userid] = nil
		end
	end

	inst:ListenForEvent("ms_playerspawn", self.onplayerspawned, TheWorld)
	inst:ListenForEvent("master_secondaryplayerschanged", self.onsecondaryplayerschanged, TheWorld)
	inst:ListenForEvent("ms_playerleft", self.onplayerleft, TheWorld)
	for _, player in ipairs(AllPlayers) do
		self:TrackPlayer(player)
	end
end)

function TeleportatoTravel:Deny(doer, message)
	if doer ~= nil and IsValidUserId(doer.userid) then
		SendModRPCToClient(GetClientModRPC("AdventureMode", "TeleportatoDenied"), doer.userid, message)
	end
end

function TeleportatoTravel:GetActivationProgress()
	local confirmed = {}
	local confirmedcount = 0
	local playercount = 0
	for _, player in ipairs(AllPlayers) do
		if IsLivingPlayer(player) then
			playercount = playercount + 1
			if self.confirmedplayers[player.userid] then
				confirmed[player.userid] = true
				confirmedcount = confirmedcount + 1
			end
		end
	end
	self.confirmedplayers = confirmed
	return confirmedcount, playercount
end

function TeleportatoTravel:Transition(doer)
	if not TheWorld.is_adventure then
		self:Deny(doer, STRINGS.UI.HUD.TELEPORTATO_ADVENTURE_INACTIVE)
		return false
	end
	if not self.inst.components.teleportatoassembly:IsComplete() then
		self:Deny(doer, STRINGS.UI.HUD.TELEPORTATO_INCOMPLETE)
		return false
	end
	if self.activating then
		return false
	end
	if ShardWorldIndex:IsMasterShard() and TheWorld:GetSecondaryShardPlayerCount() > 0 then
		self:Deny(doer, "Everyone must return from the Caves first.")
		return false
	end

	local confirmedcount, playercount = self:GetActivationProgress()
	if playercount == 0 or confirmedcount < playercount then
		self:Deny(doer, string.format("Waiting for all living players to activate the Teleportato (%d/%d).",
			confirmedcount, playercount))
		return false
	end

	local store = self.inst.components.teleportatostore
	store:CloseAll()
	local playersessions = store:BuildPlayerSessions()

	self.activating = true
	self.inst.components.activatable.inactive = false
	for _, player in ipairs(AllPlayers) do
		if not player.components.health:IsDead() then
			player.is_teleporting = true
			player.sg:GoToState("teleportato_teleport")
		end
	end

	self.laughtask = self.inst:DoTaskInTime(110 * FRAMES, PlayLaugh, self)
	self.advancetask = TheWorld:DoTaskInTime(5, AdvanceShard, self, playersessions)
	return true
end

function TeleportatoTravel:SetPlayerActivation(doer, active)
	if not active then
		self.confirmedplayers[doer.userid] = nil
		return false
	end
	if not IsLivingPlayer(doer) then
		return false
	end
	if not TheWorld.is_adventure then
		self:Deny(doer, STRINGS.UI.HUD.TELEPORTATO_ADVENTURE_INACTIVE)
		return false
	end
	if not self.inst.components.teleportatoassembly:IsComplete() then
		self:Deny(doer, STRINGS.UI.HUD.TELEPORTATO_INCOMPLETE)
		return false
	end
	if self.activating then
		return false
	end

	local wasconfirmed = self.confirmedplayers[doer.userid] == true
	self.confirmedplayers[doer.userid] = true
	if not wasconfirmed then
		local confirmedcount, playercount = self:GetActivationProgress()
		TheNet:Announce(string.format(
			STRINGS.UI.HUD.TELEPORTATO_PLAYER_CONFIRMED,
			doer:GetDisplayName(),
			confirmedcount,
			playercount
		))
	end
	return self:Transition(doer)
end

function TeleportatoTravel:RequestConfirmation(doer)
	SendModRPCToClient(
		GetClientModRPC("AdventureMode", "Adventure???"),
		doer.userid,
		self.inst.GUID,
		ZipAndEncodeString({
			title = STRINGS.UI.TELEPORTTITLE,
			body = STRINGS.UI.WORLDRESETDIALOG.ADVENTURE_NEXT_CHAPTER_CONFIRM_TITLE,
			yes = STRINGS.UI.TELEPORTYES,
			no = STRINGS.UI.TELEPORTNO,
		})
	)
end

function TeleportatoTravel:UpdateActivationAvailability()
	if not self.activating then
		self.inst.components.activatable.inactive = true
	end
end

function TeleportatoTravel:ScheduleProgressCheck()
	if self.progresschecktask == nil then
		self.progresschecktask = self.inst:DoTaskInTime(0, RunProgressCheck, self)
	end
end

function TeleportatoTravel:TrackPlayer(player)
	if self.playerdeathcallbacks[player] ~= nil then
		return
	end

	local function OnBecameGhost()
		self:ScheduleProgressCheck()
	end
	self.playerdeathcallbacks[player] = OnBecameGhost
	self.inst:ListenForEvent("ms_becameghost", OnBecameGhost, player)
end

function TeleportatoTravel:StopTrackingPlayer(player)
	local callback = self.playerdeathcallbacks[player]
	if callback ~= nil then
		self.inst:RemoveEventCallback("ms_becameghost", callback, player)
		self.playerdeathcallbacks[player] = nil
	end
end

function TeleportatoTravel:OnRemoveFromEntity()
	self.inst:RemoveEventCallback("ms_playerspawn", self.onplayerspawned, TheWorld)
	self.inst:RemoveEventCallback("master_secondaryplayerschanged", self.onsecondaryplayerschanged, TheWorld)
	self.inst:RemoveEventCallback("ms_playerleft", self.onplayerleft, TheWorld)
	local players = {}
	for player in pairs(self.playerdeathcallbacks) do
		players[#players + 1] = player
	end
	for _, player in ipairs(players) do
		self:StopTrackingPlayer(player)
	end
	if self.progresschecktask ~= nil then
		self.progresschecktask:Cancel()
	end
	if self.laughtask ~= nil then
		self.laughtask:Cancel()
	end
	if self.advancetask ~= nil then
		self.advancetask:Cancel()
	end
	self.progresschecktask = nil
	self.laughtask = nil
	self.advancetask = nil
end

TeleportatoTravel.OnRemoveEntity = TeleportatoTravel.OnRemoveFromEntity

function TeleportatoTravel:GetDebugString()
	local confirmedcount, playercount = self:GetActivationProgress()
	return string.format("confirmed=%d/%d activating=%s", confirmedcount, playercount, tostring(self.activating))
end

return TeleportatoTravel
