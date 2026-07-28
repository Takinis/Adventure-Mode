local SLOT_ORDER = { 1, 2, 3, 4 }

local function IsValidUserId(userid)
	return userid ~= nil and userid ~= ""
end

local function CopySlotRecords(records)
	if type(records) ~= "table" then
		return nil
	end

	local out = {}
	local hasany = false
	for _, slot in ipairs(SLOT_ORDER) do
		if type(records[slot]) == "table" then
			out[slot] = deepcopy(records[slot])
			hasany = true
		end
	end
	return hasany and out or nil
end

local function BuildSlotRecords(container)
	if container == nil or not container:IsValid() or container.components.container == nil then
		return nil
	end

	local out = {}
	local hasany = false
	for _, slot in ipairs(SLOT_ORDER) do
		local item = container.components.container:GetItemInSlot(slot)
		if item ~= nil then
			out[slot] = item:GetSaveRecord()
			hasany = true
		end
	end
	return hasany and out or nil
end

local function LoadSlotRecords(container, records)
	if type(records) ~= "table" then
		return
	end

	for _, slot in ipairs(SLOT_ORDER) do
		local record = records[slot]
		if type(record) == "table" then
			local item = SpawnSaveRecord(record)
			if item ~= nil then
				container.components.container:GiveItem(item, slot)
			end
		end
	end
end

local function FilterInventory(record, slotrecords)
	if type(record) ~= "table" or type(record.data) ~= "table" then
		return record
	end

	local out = deepcopy(record)
	out.data.inventory = out.data.inventory or {}
	out.data.inventory.items = {}
	out.data.inventory.equip = {}
	out.data.inventory.activeitem = nil
	out.data.sleepinghandsitem = nil
	out.data.sleepingactiveitem = nil

	for index, slot in ipairs(SLOT_ORDER) do
		local itemrecord = slotrecords ~= nil and slotrecords[slot] or nil
		if type(itemrecord) == "table" then
			out.data.inventory.items[index] = deepcopy(itemrecord)
		end
	end
	return out
end

local TeleportatoStore = Class(function(self, inst)
	self.inst = inst
	self.playerstores = {}
	self.playercontainers = {}
	self.containercallbacks = {}
	self.oncontainerchangedfn = nil
end)

function TeleportatoStore:SetOnContainerChangedFn(fn)
	self.oncontainerchangedfn = fn
end

function TeleportatoStore:NotifyContainerChanged()
	if self.oncontainerchangedfn ~= nil then
		self.oncontainerchangedfn(self.inst)
	end
end

function TeleportatoStore:SaveContainer(userid, container)
	if IsValidUserId(userid) then
		self.playerstores[userid] = BuildSlotRecords(container)
	end
end

function TeleportatoStore:UntrackContainer(container)
	local callbacks = self.containercallbacks[container]
	if callbacks ~= nil then
		self.inst:RemoveEventCallback("onremove", callbacks.onremove, container)
		self.inst:RemoveEventCallback("onclose", callbacks.onclose, container)
		self.containercallbacks[container] = nil
	end
end

function TeleportatoStore:TrackContainer(userid, container)
	local function OnRemove()
		if self.playercontainers[userid] == container then
			self.playercontainers[userid] = nil
		end
		self:UntrackContainer(container)
		self:NotifyContainerChanged()
	end

	local function OnClose()
		self:SaveContainer(userid, container)
		self:NotifyContainerChanged()
	end

	self.playercontainers[userid] = container
	self.containercallbacks[container] = { onremove = OnRemove, onclose = OnClose }
	self.inst:ListenForEvent("onremove", OnRemove, container)
	self.inst:ListenForEvent("onclose", OnClose, container)
end

function TeleportatoStore:GetContainer(userid, create)
	if not IsValidUserId(userid) then
		return nil
	end

	local container = self.playercontainers[userid]
	if container ~= nil and container:IsValid() then
		return container
	end
	if not create then
		return nil
	end

	container = SpawnPrefab("teleportato_player_container")
	if container == nil then
		return nil
	end

	local x, y, z = self.inst.Transform:GetWorldPosition()
	container.Transform:SetPosition(x, y, z)
	container._userid = userid
	container._base = self.inst
	container._teleportato_base:set(self.inst)
	LoadSlotRecords(container, self.playerstores[userid])
	self:TrackContainer(userid, container)
	return container
end

function TeleportatoStore:Open(doer)
	if doer == nil or not IsValidUserId(doer.userid) then
		self:NotifyContainerChanged()
		return false
	end

	local container = self:GetContainer(doer.userid, true)
	if container ~= nil then
		container.components.container:Open(doer)
		if container.components.container:IsOpenedBy(doer) then
			return true
		end
	end
	self:NotifyContainerChanged()
	return false
end

function TeleportatoStore:GetSlotRecords(userid)
	local container = self:GetContainer(userid, false)
	if container ~= nil then
		local records = BuildSlotRecords(container)
		self.playerstores[userid] = records
		return records
	end
	return CopySlotRecords(self.playerstores[userid])
end

function TeleportatoStore:HasOpenContainer()
	for _, container in pairs(self.playercontainers) do
		if container ~= nil and container:IsValid() and container.components.container:IsOpen() then
			return true
		end
	end
	return false
end

function TeleportatoStore:CloseAll()
	for userid, container in pairs(self.playercontainers) do
		if container ~= nil and container:IsValid() then
			self:SaveContainer(userid, container)
			container.components.container:Close()
		end
	end
end

function TeleportatoStore:RemoveAll()
	local containers = {}
	for userid, container in pairs(self.playercontainers) do
		containers[#containers + 1] = { userid = userid, container = container }
	end

	for _, entry in ipairs(containers) do
		local container = entry.container
		if container ~= nil and container:IsValid() then
			self:SaveContainer(entry.userid, container)
			self:UntrackContainer(container)
			container:Remove()
		end
	end
	self.playercontainers = {}
end

function TeleportatoStore:FilterSession(session)
	if session == nil or not IsValidUserId(session.userid) then
		return session
	end

	local store = self:GetSlotRecords(session.userid)
	if store == nil then
		return session
	end

	local success, record = RunInSandboxSafe(session.data or "")
	if not success or type(record) ~= "table" then
		return session
	end

	local out = deepcopy(session)
	out.data = DataDumper(FilterInventory(record, store), nil, BRANCH ~= "dev")
	return out
end

function TeleportatoStore:BuildPlayerSessions()
	local sessions = {}
	local seen = {}

	for _, player in ipairs(AllPlayers or {}) do
		if IsValidUserId(player.userid) and player.prefab ~= nil then
			local record = FilterInventory(player:GetSaveRecord(), self:GetSlotRecords(player.userid))
			sessions[#sessions + 1] = {
				userid = player.userid,
				prefab = player.prefab,
				data = DataDumper(record, nil, BRANCH ~= "dev"),
				metadata = DataDumper({ character = player.prefab }, nil, BRANCH ~= "dev"),
				mode = "full",
			}
			seen[player.userid] = true
		end
	end

	local run = ShardGameIndex.adventure:GetState()
	if run ~= nil and run.adventure_player_sessions ~= nil then
		for _, session in ipairs(run.adventure_player_sessions) do
			if IsValidUserId(session.userid) and not seen[session.userid] then
				sessions[#sessions + 1] = self:FilterSession(session)
			end
		end
	end
	return sessions
end

function TeleportatoStore:BuildSaveData()
	local data = {}
	local userids = {}
	for userid in pairs(self.playerstores) do
		userids[userid] = true
	end
	for userid in pairs(self.playercontainers) do
		userids[userid] = true
	end

	for userid in pairs(userids) do
		local records = self:GetSlotRecords(userid)
		if records ~= nil then
			data[userid] = records
		end
	end
	return next(data) ~= nil and data or nil
end

function TeleportatoStore:LoadData(data)
	self.playerstores = {}
	local stores = data ~= nil and data.playerstores or nil
	if type(stores) == "table" then
		for userid, records in pairs(stores) do
			if type(userid) == "string" then
				self.playerstores[userid] = CopySlotRecords(records)
			end
		end
	end
end

function TeleportatoStore:LoadLegacyData(data)
	if data ~= nil and data.playerstores ~= nil then
		self:LoadData({ playerstores = data.playerstores })
	end
end

function TeleportatoStore:OnSave()
	local stores = self:BuildSaveData()
	return stores ~= nil and { playerstores = stores } or nil
end

function TeleportatoStore:OnLoad(data)
	self:LoadData(data)
end

function TeleportatoStore:OnRemoveFromEntity()
	self:RemoveAll()
end

TeleportatoStore.OnRemoveEntity = TeleportatoStore.OnRemoveFromEntity

function TeleportatoStore:GetDebugString()
	return string.format("stores=%d containers=%d", GetTableSize(self.playerstores), GetTableSize(self.playercontainers))
end

return TeleportatoStore
