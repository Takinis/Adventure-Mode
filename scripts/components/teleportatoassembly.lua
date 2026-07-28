local PART_SYMBOLS = {
	teleportato_ring = "RING",
	teleportato_crank = "CRANK",
	teleportato_box = "BOX",
	teleportato_potato = "POTATO",
}

local PART_COUNT = 4

local function OnPowerUp(inst)
	local self = inst.components.teleportatoassembly
	self.waitingforpowerup = false
	inst:RemoveEventCallback("powerup", OnPowerUp)
	self:PowerUp()
end

local function PowerUpTask(inst, self)
	self.poweruptask = nil
	self:PowerUp()
end

local function PlayActivationMouth(inst, self)
	self.mouthtask = nil
	inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_activate_mouth", "teleportato_activatemouth")
end

local function FinishActivation(inst, self, doer)
	self.activationtask = nil
	if doer ~= nil and doer:IsValid() and self.onactivatedfn ~= nil then
		self.onactivatedfn(inst, doer)
	end
end

local TeleportatoAssembly = Class(function(self, inst)
	self.inst = inst
	self.parts = {}
	for part in pairs(PART_SYMBOLS) do
		self.parts[part] = false
	end

	self.powered = false
	self.activatedonce = false
	self.waitingforpowerup = false
	self.poweruptask = nil
	self.mouthtask = nil
	self.activationtask = nil
	self.onactivatedfn = nil
end)

function TeleportatoAssembly:SetOnActivatedFn(fn)
	self.onactivatedfn = fn
end

function TeleportatoAssembly:GetPartCount()
	local count = 0
	for _, found in pairs(self.parts) do
		if found then
			count = count + 1
		end
	end
	return count
end

function TeleportatoAssembly:IsComplete()
	return self:GetPartCount() >= PART_COUNT
end

function TeleportatoAssembly:RefreshPartSymbols()
	for part, symbol in pairs(PART_SYMBOLS) do
		if self.parts[part] then
			self.inst.AnimState:Show(symbol)
		else
			self.inst.AnimState:Hide(symbol)
		end
	end
end

function TeleportatoAssembly:CanAccept(item)
	return item ~= nil and self.parts[item.prefab] == false
end

function TeleportatoAssembly:AddPart(item)
	if not self:CanAccept(item) then
		return false
	end

	self.parts[item.prefab] = true
	self.inst.SoundEmitter:KillSound("teleportato_addpart")
	self.inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_addpart", "teleportato_addpart")
	self:TryPowerUp()
	return true
end

function TeleportatoAssembly:PowerUp()
	if self.powered then
		return
	end

	self.powered = true
	self.inst.AnimState:PlayAnimation("power_on", false)
	self.inst.AnimState:PushAnimation("idle_on", true)
	self.inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_powerup", "teleportato_on")
	self.inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_idle_LP", "teleportato_idle")

	if self.inst.components.activatable ~= nil then
		self.inst.components.activatable.inactive = true
	end
	self.inst._poweredup:set(true)
end

function TeleportatoAssembly:TryPowerUp()
	self:RefreshPartSymbols()
	if not self:IsComplete() or self.powered then
		return
	end

	if self.inst.components.trader ~= nil then
		self.inst.components.trader:Disable()
	end

	local rodbase = TheSim:FindFirstEntityWithTag("rodbase")
	if rodbase ~= nil and rodbase.components.lock ~= nil and rodbase.components.lock:IsLocked() then
		if not self.waitingforpowerup then
			self.waitingforpowerup = true
			self.inst:ListenForEvent("powerup", OnPowerUp)
		end
		rodbase:PushEvent("ready")
	elseif self.poweruptask == nil then
		self.poweruptask = self.inst:DoTaskInTime(0.5, PowerUpTask, self)
	end
end

function TeleportatoAssembly:Activate(doer)
	if not self:IsComplete() then
		if self.inst.components.activatable ~= nil then
			self.inst.components.activatable.inactive = false
		end
		return false
	end

	if self.activatedonce then
		if self.onactivatedfn ~= nil then
			self.onactivatedfn(self.inst, doer)
		end
		return true
	end

	self.activatedonce = true
	self.inst.AnimState:PlayAnimation("activate", false)
	self.inst.AnimState:PushAnimation("active_idle", true)
	self.inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_activate", "teleportato_activate")
	self.inst.SoundEmitter:KillSound("teleportato_idle")
	self.inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_activeidle_LP", "teleportato_active_idle")

	self.mouthtask = self.inst:DoTaskInTime(40 * FRAMES, PlayActivationMouth, self)
	self.activationtask = self.inst:DoTaskInTime(3, FinishActivation, self, doer)
	return true
end

function TeleportatoAssembly:GetStatus()
	local partcount = self:GetPartCount()
	if partcount >= PART_COUNT then
		local rodbase = TheSim:FindFirstEntityWithTag("rodbase")
		if rodbase ~= nil and rodbase.components.lock ~= nil and rodbase.components.lock:IsLocked() then
			return "LOCKED"
		end
		return "ACTIVE"
	elseif partcount > 0 then
		return "PARTIAL"
	end
end

function TeleportatoAssembly:LoadData(data)
	if data ~= nil and data.parts ~= nil then
		for part in pairs(PART_SYMBOLS) do
			self.parts[part] = data.parts[part] == true
		end
	end

	self.activatedonce = data ~= nil and data.activatedonce == true
	self.powered = data ~= nil and data.powered == true
	self:RefreshPartSymbols()

	if self.powered then
		if self.activatedonce then
			self.inst.AnimState:PlayAnimation("active_idle", true)
			self.inst.SoundEmitter:KillSound("teleportato_idle")
			self.inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_activeidle_LP", "teleportato_active_idle")
		else
			self.inst.AnimState:PlayAnimation("idle_on", true)
			self.inst.SoundEmitter:PlaySound("dontstarve/common/teleportato/teleportato_idle_LP", "teleportato_idle")
		end
		if self.inst.components.activatable ~= nil then
			self.inst.components.activatable.inactive = true
		end
		self.inst._poweredup:set(true)
	else
		if self.inst.components.activatable ~= nil then
			self.inst.components.activatable.inactive = false
		end
		self:TryPowerUp()
	end
end

function TeleportatoAssembly:LoadLegacyData(data)
	if data ~= nil and data.Parts ~= nil then
		self:LoadData({
			parts = data.Parts,
			activatedonce = data.activatedonce,
			powered = data.powered,
		})
	end
end

function TeleportatoAssembly:OnSave()
	return {
		parts = deepcopy(self.parts),
		activatedonce = self.activatedonce or nil,
		powered = self.powered or nil,
	}
end

function TeleportatoAssembly:OnLoad(data)
	self:LoadData(data)
end

function TeleportatoAssembly:OnRemoveFromEntity()
	if self.poweruptask ~= nil then
		self.poweruptask:Cancel()
		self.poweruptask = nil
	end
	if self.mouthtask ~= nil then
		self.mouthtask:Cancel()
		self.mouthtask = nil
	end
	if self.activationtask ~= nil then
		self.activationtask:Cancel()
		self.activationtask = nil
	end
	if self.waitingforpowerup then
		self.waitingforpowerup = false
		self.inst:RemoveEventCallback("powerup", OnPowerUp)
	end
end

function TeleportatoAssembly:GetDebugString()
	return string.format("parts=%d/%d powered=%s activated=%s", self:GetPartCount(), PART_COUNT,
		tostring(self.powered), tostring(self.activatedonce))
end

return TeleportatoAssembly
